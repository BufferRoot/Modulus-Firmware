/*
 * M5 Unit ExtEncoder — Port A I2C1 @ 0x59 (STM32F030).
 * C++ hal_ext_encoder.cpp parity: coex, no bus_reset before probe, split FW read.
 */
#include "ext_encoder_shim.h"
#include "mbus_shim.h"
#include "tab5_ext_i2c.h"
#include "tab5_hw.h"

#include <driver/i2c_master.h>
#include <esp_log.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <string.h>

static const char *TAG = "ext_encoder";

#define EXT_ENC_ADDR       0x59
#define REG_ENCODER_COUNT  0x00
#define REG_FW_VERSION     0xFE
#define I2C_TIMEOUT_MS     100
#define EXTENC_PROBE_MS    250
#define PORT_A_SCL_WAIT_US 50000
#define BOOT_DELAY_US      (2000 * 1000LL)
#define DETECT_INTERVAL_US (2000 * 1000LL)
#define SLOW_DETECT_INTERVAL_US (30000 * 1000LL)
#define EXT_ENC_FAST_ATTEMPTS   3U
#define HEARTBEAT_US            (10 * 1000 * 1000LL)
#define FW_READ_RETRIES         3U
#define READ_FAIL_REINIT        5U

static i2c_master_dev_handle_t s_dev = NULL;
static bool s_hw_init = false;
static int64_t s_boot_us = 0;
static int64_t s_last_detect_us = 0;
static int64_t s_last_hb_us = 0;
static uint32_t s_detect_failures = 0;
static uint8_t s_read_failures = 0;
static bool s_scan_hold = false;
/* Last handwheel block reason surfaced at INFO (0xFF = none reported yet). Lets
 * a turned-but-not-moving wheel explain itself without enabling Verbose. */
static uint8_t s_last_block = 0xFF;

static bool read_reg_repeat_start(uint8_t reg, uint8_t *out, size_t len)
{
    if (!s_dev) {
        return false;
    }
    if (!tab5_ext_i2c_lock(5000)) {
        return false;
    }
    const esp_err_t err = i2c_master_transmit_receive(s_dev, &reg, 1, out, len, I2C_TIMEOUT_MS);
    tab5_ext_i2c_unlock();
    return err == ESP_OK;
}

/* M5 getFirmwareVersion(): write 0xFE + STOP, then separate read. */
static bool read_reg_fw_version(uint8_t *ver_out)
{
    if (!s_dev || !ver_out) {
        return false;
    }
    if (!tab5_ext_i2c_lock(5000)) {
        return false;
    }
    const uint8_t reg = REG_FW_VERSION;
    esp_err_t err = i2c_master_transmit(s_dev, &reg, 1, I2C_TIMEOUT_MS);
    if (err == ESP_OK) {
        vTaskDelay(pdMS_TO_TICKS(2));
        err = i2c_master_receive(s_dev, ver_out, 1, I2C_TIMEOUT_MS);
    }
    tab5_ext_i2c_unlock();
    return err == ESP_OK;
}

static bool add_device_locked(i2c_master_bus_handle_t bus)
{
    if (s_dev) {
        return true;
    }
    const i2c_device_config_t cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = EXT_ENC_ADDR,
        .scl_speed_hz = 100000,
        .scl_wait_us = PORT_A_SCL_WAIT_US,
    };
    const esp_err_t err = i2c_master_bus_add_device(bus, &cfg, &s_dev);
    if (err != ESP_OK || s_dev == NULL) {
        ESP_LOGW(TAG, "add_device 0x%02X failed: %s", EXT_ENC_ADDR, esp_err_to_name(err));
        s_dev = NULL;
        return false;
    }
    return true;
}


static void remove_device(void)
{
    if (!s_dev) {
        return;
    }
    if (tab5_ext_i2c_lock(5000)) {
        (void)i2c_master_bus_rm_device(s_dev);
        tab5_ext_i2c_unlock();
    }
    s_dev = NULL;
}

static bool try_detect(int32_t *seed_count, uint8_t *fw_out)
{
    if (!modulus_mbus_port_a_ensure()) {
        ESP_LOGW(TAG, "Port A bus ensure failed (I2C%d G%d/G%d)",
                 TAB5_EXT_I2C_PORT, TAB5_EXT_I2C_SDA_GPIO, TAB5_EXT_I2C_SCL_GPIO);
        return false;
    }
    if (!tab5_ext_i2c_lock(5000)) {
        return false;
    }
    i2c_master_bus_handle_t bus = tab5_ext_i2c_get_handle();
    if (!bus) {
        tab5_ext_i2c_unlock();
        ESP_LOGW(TAG, "Port A I2C handle NULL after ensure");
        return false;
    }

    vTaskDelay(pdMS_TO_TICKS(50));
    if (!add_device_locked(bus)) {
        tab5_ext_i2c_unlock();
        if (s_detect_failures > 0U && (s_detect_failures % 10U) == 0U) {
            remove_device();
            (void)tab5_ext_i2c_recover_bus();
        }
        if (s_detect_failures == 0 || (s_detect_failures % 5U) == 0U) {
            ESP_LOGW(TAG, "add_device 0x%02X on I2C%d SDA=%d SCL=%d failed",
                     EXT_ENC_ADDR, TAB5_EXT_I2C_PORT, TAB5_EXT_I2C_SDA_GPIO, TAB5_EXT_I2C_SCL_GPIO);
            tab5_ext_i2c_log_line_levels("no ACK");
        }
        return false;
    }
    tab5_ext_i2c_unlock();

    uint8_t ver = 0;
    bool fw_ok = false;
    for (uint8_t attempt = 0; attempt < FW_READ_RETRIES && !fw_ok; ++attempt) {
        if (attempt > 0) {
            vTaskDelay(pdMS_TO_TICKS(20));
        }
        fw_ok = read_reg_fw_version(&ver);
    }
    if (!fw_ok && s_detect_failures > 0U && (s_detect_failures % 10U) == 0U) {
        remove_device();
        (void)tab5_ext_i2c_recover_bus();
    }
    if (!fw_ok || ver < 2) {
        if (s_detect_failures == 0 || (s_detect_failures % 5U) == 0U) {
            ESP_LOGW(TAG, "0x%02X FW read failed (v=%u, ok=%d) — check Grove SDA/SCL + EXT5V",
                     EXT_ENC_ADDR, (unsigned)ver, fw_ok ? 1 : 0);
        }
        remove_device();
        return false;
    }
    if (fw_out) {
        *fw_out = ver;
    }

    vTaskDelay(pdMS_TO_TICKS(20));

    uint8_t raw[4];
    int32_t val = 0;
    if (read_reg_repeat_start(REG_ENCODER_COUNT, raw, 4)) {
        memcpy(&val, raw, 4);
    }
    if (seed_count) {
        *seed_count = val;
    }

    ESP_LOGI(TAG, "ExtEncoder 0x%02X FW v%u count=%ld", EXT_ENC_ADDR, (unsigned)ver, (long)val);
    return true;
}

void modulus_ext_encoder_hw_init(void)
{
    if (s_hw_init) {
        return;
    }
    s_boot_us = esp_timer_get_time();
    s_last_detect_us = s_boot_us;
    s_detect_failures = 0;
    s_hw_init = true;
    ESP_LOGI(TAG, "HAL ready Port A I2C%d SDA=%d SCL=%d @ 0x%02X (wheel trace @ Verbose)",
             TAB5_EXT_I2C_PORT, TAB5_EXT_I2C_SDA_GPIO, TAB5_EXT_I2C_SCL_GPIO, EXT_ENC_ADDR);
}

void modulus_ext_encoder_hw_deinit(void)
{
    remove_device();
    s_hw_init = false;
    s_detect_failures = 0;
}

bool modulus_ext_encoder_hw_maintain(bool *connected, int32_t *count, uint8_t *fw_version)
{
    if (!s_hw_init || !connected || !count) {
        return false;
    }
    if (s_scan_hold) {
        return false;
    }

    const int64_t now = esp_timer_get_time();

    if (!*connected) {
        if ((now - s_boot_us) < BOOT_DELAY_US) {
            return false;
        }
        const int64_t interval = (s_detect_failures < EXT_ENC_FAST_ATTEMPTS)
                                     ? DETECT_INTERVAL_US
                                     : SLOW_DETECT_INTERVAL_US;
        if ((now - s_last_detect_us) < interval) {
            return false;
        }
        s_last_detect_us = now;

        int32_t seed = 0;
        uint8_t ver = 0;
        if (try_detect(&seed, &ver)) {
            *connected = true;
            *count = seed;
            if (fw_version) {
                *fw_version = ver;
            }
            s_detect_failures = 0;
            return true;
        }

        s_detect_failures++;
        if (s_detect_failures == 1U) {
            ESP_LOGI(TAG, "absent on Port A — check EXT5V + Grove on front Port A (not M5-Bus/ExtPort2)");
        } else if (s_detect_failures == EXT_ENC_FAST_ATTEMPTS) {
            ESP_LOGI(TAG, "still absent — slow re-probe 30 s (Storage: Scan Port A, or toggle EXT5V)");
        }
        return false;
    }

    uint8_t raw[4];
    if (!read_reg_repeat_start(REG_ENCODER_COUNT, raw, 4)) {
        s_read_failures++;
        if (s_read_failures < READ_FAIL_REINIT) {
            return false;
        }
        ESP_LOGW(TAG, "read failed x%u — recover Port A I2C bus", (unsigned)s_read_failures);
        remove_device();
        (void)tab5_ext_i2c_recover_bus();
        s_read_failures = 0;
        *connected = false;
        return false;
    }

    s_read_failures = 0;

    memcpy(count, raw, 4);
    return true;
}

void modulus_ext_encoder_trace_wheel(int32_t count, int32_t delta, bool mpg_active, char axis,
                                     uint8_t machine_state, int32_t jog_steps, float jog_mm,
                                     uint8_t block_code)
{
    const int64_t now = esp_timer_get_time();
    const char axis_ch = axis ? axis : '-';

    if (delta != 0) {
        if (jog_steps != 0) {
            ESP_LOGV(TAG,
                     "wheel count=%ld delta=%+ld mpg=%d axis=%c state=%u steps=%+ld dist=%+.4f mm",
                     (long)count, (long)delta, mpg_active ? 1 : 0, axis_ch,
                     (unsigned)machine_state, (long)jog_steps, (double)jog_mm);
            if (s_last_block != 0) {
                s_last_block = 0;
                ESP_LOGI(TAG, "handwheel: jogging axis %c (%+.3f mm)", axis_ch, (double)jog_mm);
            }
        } else if (block_code != 0) {
            ESP_LOGV(TAG, "wheel count=%ld delta=%+ld blocked=%u mpg=%d axis=%c state=%u",
                     (long)count, (long)delta, (unsigned)block_code, mpg_active ? 1 : 0, axis_ch,
                     (unsigned)machine_state);
            /* Surface why a turned wheel produced no motion, once per reason
             * change, at INFO so it's visible without Verbose. block_code values
             * mirror Zig WheelBlock: 1=mpg_off 2=no_axis 3=bad_state 4=session
             * 5=substep. substep is normal sub-division accumulation, not a fault. */
            if (block_code != s_last_block && block_code != 5) {
                s_last_block = block_code;
                const char *why =
                    (block_code == 1) ? "MPG off — tap the MPG badge on the status bar" :
                    (block_code == 2) ? "no axis selected — tap an axis (X/Y/Z) on the dashboard" :
                    (block_code == 3) ? "machine not idle — clear alarm/hold, then retry" :
                    (block_code == 4) ? "controller not ready — connect grblHAL and unlock" :
                                        "blocked";
                ESP_LOGI(TAG, "handwheel: %s", why);
            }
        } else {
            ESP_LOGV(TAG, "wheel count=%ld delta=%+ld mpg=%d axis=%c state=%u (no jog)",
                     (long)count, (long)delta, mpg_active ? 1 : 0, axis_ch,
                     (unsigned)machine_state);
        }
        s_last_hb_us = now;
        return;
    }

    if ((now - s_last_hb_us) < HEARTBEAT_US) {
        return;
    }
    s_last_hb_us = now;
    ESP_LOGV(TAG, "heartbeat count=%ld mpg=%d axis=%c state=%u",
             (long)count, mpg_active ? 1 : 0, axis_ch, (unsigned)machine_state);
}

void modulus_ext_encoder_trace_status(bool connected, uint8_t fw_version)
{
    const int64_t now = esp_timer_get_time();
    if ((now - s_last_hb_us) < HEARTBEAT_US) {
        return;
    }
    s_last_hb_us = now;
    if (connected) {
        ESP_LOGV(TAG, "status connected fw=%u (wheel trace active)", (unsigned)fw_version);
        return;
    }
    ESP_LOGV(TAG, "status disconnected — probing I2C%d @ 0x%02X (fails=%lu)",
             TAB5_EXT_I2C_PORT, EXT_ENC_ADDR, (unsigned long)s_detect_failures);
}

void modulus_ext_encoder_notify_ext5v(bool enabled)
{
    modulus_mbus_port_a_power_invalidate();
    if (!enabled) {
        ESP_LOGV(TAG, "EXT5V off — Port A units unpowered");
        return;
    }
    /* STM32F030 on ExtEncoder needs margin after rail enable. */
    vTaskDelay(pdMS_TO_TICKS(800));
    modulus_ext_encoder_force_detect();
    ESP_LOGI(TAG, "EXT5V on — Port A re-probe ExtEncoder 0x%02X", EXT_ENC_ADDR);
}

void modulus_ext_encoder_force_detect(void)
{
    s_detect_failures = 0;
    s_last_detect_us = 0;
    s_boot_us = esp_timer_get_time();
    ESP_LOGV(TAG, "forced Port A re-probe for ExtEncoder 0x%02X", EXT_ENC_ADDR);
}

void modulus_ext_encoder_scan_begin(void)
{
    s_scan_hold = true;
    remove_device();
}

void modulus_ext_encoder_scan_end(void)
{
    s_scan_hold = false;
    modulus_ext_encoder_force_detect();
}
