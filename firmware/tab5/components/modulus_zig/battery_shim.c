/*
 * INA226 battery monitor + NP-F curve — mirrors C++ hal_battery.cpp (simplified).
 */
#include "battery_shim.h"
#include "display_shim.h"
#include "event_shim.h"
#include "i2c_coex_shim.h"
#include "nvs_shim.h"

#include <bsp/m5stack_tab5.h>
#include "tab5_hw.h"
#include "tab5_pi4ioe.h"
#include <driver/i2c_master.h>
#include <driver/temperature_sensor.h>
#include <esp_log.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/portmacro.h>
#include <math.h>

static const char *TAG = "modulus_battery";

static const uint8_t k_ina226_addr = TAB5_I2C_ADDR_INA226;
static i2c_master_dev_handle_t s_ina_dev = NULL;
static bool s_ina_ok = false;
static temperature_sensor_handle_t s_temp = NULL;

/* Tab5: 5 mOhm shunt, 8.192 A max — matches C++ INA226::calibrate(0.005, 8.192). */
static const float k_shunt_ohm = 0.005f;
static const float k_imax_a = 8.192f;
static float s_current_lsb = 0.0001f;
static float s_power_lsb = 0.0025f;

static modulus_battery_status_t s_status = {};
static portMUX_TYPE s_status_mux = portMUX_INITIALIZER_UNLOCKED;
static uint8_t s_low_warn_pct = 15;
static uint8_t s_pack_type = 0;
static float s_capacity_mah = 2200.0f;
static bool s_charge_en = true;
static bool s_adaptive = false;
static bool s_low_warned = false;
static volatile bool s_poll_paused = false;
static uint16_t s_applied_dim_sec = 0xFFFF;
static uint16_t s_applied_sleep_sec = 0xFFFF;

/* NP-F presets — mAh for time-to-empty/full only; % stays voltage-based (2S Li-ion). */
typedef struct {
    uint16_t mah;
    const char *label;
} bat_pack_t;

static const bat_pack_t k_packs[] = {
    {2200, "F550 (2200 mAh)"},
    {3500, "F550 3500 mAh"},
    {5200, "F750"},
    {7800, "F950"},
    {9800, "F970"},
};
static const size_t k_pack_count = sizeof(k_packs) / sizeof(k_packs[0]);

static float s_ema_voltage = 0.0f;
static float s_ema_current = 0.0f;
static bool s_ema_primed = false;
static uint8_t s_smoothed_pct = 0;

static const float k_ema_alpha = 0.08f;
static const uint8_t k_pct_max_step = 1;

typedef struct {
    float v;
    uint8_t pct;
} volt_pct_t;

static const volt_pct_t k_curve[] = {
    {8.40f, 100}, {8.20f, 90}, {8.00f, 80}, {7.80f, 70}, {7.60f, 60},
    {7.40f, 50}, {7.20f, 40}, {7.00f, 30}, {6.80f, 20}, {6.40f, 10}, {6.00f, 0},
};

static uint8_t voltage_to_percent(float v)
{
    if (v >= k_curve[0].v) {
        return 100;
    }
    if (v <= k_curve[sizeof(k_curve) / sizeof(k_curve[0]) - 1].v) {
        return 0;
    }
    for (size_t i = 0; i < sizeof(k_curve) / sizeof(k_curve[0]) - 1; i++) {
        if (v >= k_curve[i + 1].v) {
            const float span_v = k_curve[i].v - k_curve[i + 1].v;
            const float span_p = (float)(k_curve[i].pct - k_curve[i + 1].pct);
            const float frac = (v - k_curve[i + 1].v) / span_v;
            return k_curve[i + 1].pct + (uint8_t)(frac * span_p);
        }
    }
    return 0;
}

static float pack_capacity_mah(uint8_t idx)
{
    if (idx >= k_pack_count) {
        idx = 0;
    }
    return (float)k_packs[idx].mah;
}

static esp_err_t ina226_write_reg(uint8_t reg, uint16_t val)
{
    uint8_t buf[3] = {reg, (uint8_t)(val >> 8), (uint8_t)(val & 0xFF)};
    return i2c_master_transmit(s_ina_dev, buf, sizeof(buf), 100);
}

static esp_err_t ina226_read_reg(uint8_t reg, uint16_t *out)
{
    uint8_t data[2] = {};
    esp_err_t err = i2c_master_transmit_receive(s_ina_dev, &reg, 1, data, 2, 100);
    if (err != ESP_OK) {
        return err;
    }
    *out = ((uint16_t)data[0] << 8) | data[1];
    return ESP_OK;
}

static bool ina226_calibrate(float r_shunt, float i_max_expected);

static bool ina226_begin(i2c_master_bus_handle_t bus)
{
    i2c_device_config_t dev_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = k_ina226_addr,
        .scl_speed_hz = 400000,
    };
    if (i2c_master_bus_add_device(bus, &dev_cfg, &s_ina_dev) != ESP_OK || s_ina_dev == NULL) {
        return false;
    }

    /* Averages=16, bus/shunt conv=1100us, shunt+bus continuous — hal_battery.cpp */
    const uint16_t cfg = (0x4 << 9) | (0x4 << 6) | (0x4 << 3) | 0x7;
    if (ina226_write_reg(0x00, cfg) != ESP_OK) {
        return false;
    }
    return ina226_calibrate(k_shunt_ohm, k_imax_a);
}

static bool ina226_calibrate(float r_shunt, float i_max_expected)
{
    const float minimum_lsb = i_max_expected / 32767.0f;
    float current_lsb = minimum_lsb;
    current_lsb /= 0.0001f;
    current_lsb = ceilf(current_lsb);
    current_lsb *= 0.0001f;
    s_current_lsb = current_lsb;
    s_power_lsb = current_lsb * 25.0f;
    const uint16_t cal = (uint16_t)(0.00512f / (current_lsb * r_shunt));
    return ina226_write_reg(0x05, cal) == ESP_OK;
}

static float ina226_read_bus_voltage(void)
{
    uint16_t raw = 0;
    if (ina226_read_reg(0x02, &raw) != ESP_OK) {
        return 0.0f;
    }
    /* Match power_monitor_ina226 ina226.cpp — not (raw >> 3); >>3 reads ~8x low on Tab5. */
    return ((float)(int16_t)raw) * 0.00125f;
}

static float ina226_read_current(void)
{
    uint16_t raw = 0;
    if (ina226_read_reg(0x04, &raw) != ESP_OK) {
        return 0.0f;
    }
    return ((float)(int16_t)raw) * s_current_lsb;
}

static float ina226_read_power(void)
{
    uint16_t raw = 0;
    if (ina226_read_reg(0x03, &raw) != ESP_OK) {
        return 0.0f;
    }
    return ((float)(int16_t)raw) * s_power_lsb;
}

/* 0=discharging 1=charging 2=full 3=no_battery — mirrors hal_battery::ChargeState */
static uint16_t clamp_timeout(uint16_t user_sec, uint16_t cap_sec)
{
    if (cap_sec == 0) {
        return user_sec;
    }
    if (user_sec == 0) {
        return cap_sec;
    }
    return user_sec < cap_sec ? user_sec : cap_sec;
}

static void effective_display_timeouts(uint16_t *dim_sec, uint16_t *sleep_sec)
{
    const uint16_t user_dim = modulus_nvs_get_u16("dim_to", 0);
    const uint16_t user_sleep = modulus_nvs_get_u16("scr_to", 0);
    *dim_sec = user_dim;
    *sleep_sec = user_sleep;

    if (!s_adaptive || s_status.charge_state == 1 || s_status.charge_state == 2) {
        return;
    }

    const uint8_t pct = s_status.percent;
    uint16_t cap_dim = 0;
    uint16_t cap_sleep = 0;
    if (pct <= 20) {
        cap_dim = 30;
        cap_sleep = 60;
    } else if (pct <= 50) {
        cap_dim = 60;
        cap_sleep = 120;
    } else {
        return;
    }

    *dim_sec = clamp_timeout(user_dim, cap_dim);
    *sleep_sec = clamp_timeout(user_sleep, cap_sleep);
}

void modulus_battery_apply_display_policy(void)
{
    uint16_t dim = 0;
    uint16_t sleep = 0;
    effective_display_timeouts(&dim, &sleep);
    if (dim == s_applied_dim_sec && sleep == s_applied_sleep_sec) {
        return;
    }
    s_applied_dim_sec = dim;
    s_applied_sleep_sec = sleep;
    modulus_display_set_timeouts(dim, sleep);
}

void modulus_battery_set_adaptive(bool on)
{
    s_adaptive = on;
    modulus_nvs_set_u8("bat_adapt", on ? 1 : 0);
    s_applied_dim_sec = 0xFFFF;
    s_applied_sleep_sec = 0xFFFF;
    modulus_battery_apply_display_policy();
}

bool modulus_battery_is_adaptive(void)
{
    return s_adaptive;
}

static uint8_t detect_charge_state(float voltage, float current)
{
    if (voltage < 5.0f) {
        return 3;
    }
    if (!s_charge_en) {
        return 0;
    }

    /* IP2326 CHG_STAT via PI4IOE2 P6: HIGH = charging (C++ bsp_get_charge_status). */
    const bool hw_charging = tab5_pi4ioe_get_charge_status();
    if (hw_charging) {
        if (voltage >= 8.30f && current < 0.20f) {
            return 2;
        }
        return 1;
    }
    if (voltage >= 8.30f && current < 0.15f) {
        return 2;
    }
    return 0;
}

static void battery_sample_locked(void)
{
    if (!s_ina_ok) {
        return;
    }

    const float v_raw = ina226_read_bus_voltage();
    const float i_raw = ina226_read_current();
    const float p_raw = ina226_read_power();

    if (!s_ema_primed) {
        s_ema_voltage = v_raw;
        s_ema_current = i_raw;
        s_smoothed_pct = voltage_to_percent(v_raw);
        s_ema_primed = true;
    } else {
        s_ema_voltage += k_ema_alpha * (v_raw - s_ema_voltage);
        s_ema_current += k_ema_alpha * (i_raw - s_ema_current);
    }

    uint8_t raw_pct = voltage_to_percent(s_ema_voltage);
    if (raw_pct > s_smoothed_pct) {
        uint8_t step = raw_pct - s_smoothed_pct;
        s_smoothed_pct += (step > k_pct_max_step) ? k_pct_max_step : step;
    } else if (raw_pct < s_smoothed_pct) {
        uint8_t step = s_smoothed_pct - raw_pct;
        s_smoothed_pct -= (step > k_pct_max_step) ? k_pct_max_step : step;
    }

    const uint8_t chg = detect_charge_state(s_ema_voltage, s_ema_current);

    int32_t tte = -1;
    int32_t ttf = -1;
    const float rate_mA = fabsf(s_ema_current) * 1000.0f;
    if (chg == 0 && rate_mA > 10.0f) {
        const float remaining = s_capacity_mah * (float)s_smoothed_pct / 100.0f;
        tte = (int32_t)(remaining / rate_mA * 60.0f);
        if (tte < 0) {
            tte = 0;
        }
    } else if (chg == 1 && rate_mA > 10.0f) {
        const float needed = s_capacity_mah * (float)(100 - s_smoothed_pct) / 100.0f;
        const float charge_rate = rate_mA * 0.5f;
        if (charge_rate > 10.0f) {
            ttf = (int32_t)(needed / charge_rate * 60.0f);
            if (ttf < 0) {
                ttf = 0;
            }
        }
    }

    taskENTER_CRITICAL(&s_status_mux);
    s_status.voltage = s_ema_voltage;
    /* INA226 + = into load (discharge); UI expects + when charging into pack. */
    s_status.current = -s_ema_current;
    s_status.power = p_raw;
    s_status.percent = s_smoothed_pct;
    s_status.charge_state = chg;
    s_status.rate_mA = rate_mA;
    s_status.time_to_empty = tte;
    s_status.time_to_full = ttf;
    taskEXIT_CRITICAL(&s_status_mux);
}

static void battery_poll_task(void *arg)
{
    (void)arg;
    while (true) {
        if (!s_poll_paused) {
            if (modulus_i2c_coex_lock(2000)) {
                battery_sample_locked();

                if (s_temp) {
                    float t = 0.0f;
                    if (temperature_sensor_get_celsius(s_temp, &t) == ESP_OK) {
                        s_status.cpu_temp = t;
                    }
                }
                modulus_i2c_coex_unlock();

                if (s_adaptive) {
                    modulus_battery_apply_display_policy();
                }

                if (s_low_warn_pct > 0 && s_status.percent <= s_low_warn_pct &&
                    s_status.charge_state == 0) {
                    if (!s_low_warned) {
                        s_low_warned = true;
                        ESP_LOGW(TAG, "Low battery: %u%%", s_status.percent);
                        modulus_event_publish(0x0400, &s_status.percent, sizeof(s_status.percent));
                    }
                } else {
                    s_low_warned = false;
                }
            }
        }
        /* Display asleep -> nobody is reading the gauge; 10 s sampling cuts
         * INA226/temp I2C traffic and wakeups 5x. 2 s while awake keeps the
         * status-bar percent and low-battery warning responsive. */
        vTaskDelay(pdMS_TO_TICKS(modulus_display_is_sleeping() ? 10000 : 2000));
    }
}

void modulus_battery_init(void)
{
    temperature_sensor_config_t tcfg = {.range_min = 20, .range_max = 100};
    if (temperature_sensor_install(&tcfg, &s_temp) == ESP_OK) {
        temperature_sensor_enable(s_temp);
    }

    i2c_master_bus_handle_t bus = bsp_i2c_get_handle();
    s_ina_ok = bus && ina226_begin(bus);
    if (s_ina_ok) {
        ESP_LOGI(TAG, "INA226 ready, bus voltage: %.2fV", ina226_read_bus_voltage());
    } else {
        ESP_LOGW(TAG, "INA226 not detected at 0x41");
    }

    s_low_warn_pct = modulus_nvs_get_u8("bat_warn", 15);
    s_pack_type = modulus_nvs_get_u8("bat_type", 0);
    if (s_pack_type >= k_pack_count) {
        s_pack_type = 0;
    }
    s_capacity_mah = pack_capacity_mah(s_pack_type);
    s_charge_en = modulus_nvs_get_u8("chg_en", 1) != 0;
    s_adaptive = modulus_nvs_get_u8("bat_adapt", 0) != 0;

    /* Prime status before UI first paint (poll task is async). */
    if (s_ina_ok && modulus_i2c_coex_lock(2000)) {
        battery_sample_locked();
        modulus_i2c_coex_unlock();
    }
    modulus_battery_apply_display_policy();

    xTaskCreatePinnedToCore(battery_poll_task, "bat_poll", 4096, NULL, 3, NULL, 0);
    ESP_LOGI(TAG, "Battery HAL init (warn=%u%%, pack=%s, adapt=%u)", s_low_warn_pct,
             k_packs[s_pack_type].label, s_adaptive ? 1U : 0U);
}

bool modulus_battery_get_status(modulus_battery_status_t *out)
{
    if (!out) {
        return false;
    }
    taskENTER_CRITICAL(&s_status_mux);
    *out = s_status;
    taskEXIT_CRITICAL(&s_status_mux);
    return s_ina_ok;
}

bool modulus_battery_is_low_warn(const modulus_battery_status_t *st)
{
    if (!st) {
        return false;
    }
    if (st->charge_state == 3) {
        return true;
    }
    return st->charge_state == 0 && st->percent <= s_low_warn_pct;
}

void modulus_battery_set_charge_en(bool en)
{
    s_charge_en = en;
}

void modulus_battery_set_low_warn_pct(uint8_t pct)
{
    s_low_warn_pct = pct;
    modulus_nvs_set_u8("bat_warn", pct);
}

void modulus_battery_set_pack_type(uint8_t idx)
{
    if (idx >= k_pack_count) {
        idx = 0;
    }
    s_pack_type = idx;
    s_capacity_mah = pack_capacity_mah(idx);
    modulus_nvs_set_u8("bat_type", idx);
}

uint8_t modulus_battery_get_pack_type(void)
{
    return s_pack_type;
}

const char *modulus_battery_pack_label(uint8_t idx)
{
    if (idx >= k_pack_count) {
        idx = 0;
    }
    return k_packs[idx].label;
}

void modulus_battery_set_poll_paused(bool paused)
{
    s_poll_paused = paused;
    if (paused) {
        ESP_LOGD(TAG, "Battery poll paused (deep sleep)");
    } else {
        ESP_LOGD(TAG, "Battery poll resumed");
    }
}

bool modulus_battery_is_poll_paused(void)
{
    return s_poll_paused;
}
