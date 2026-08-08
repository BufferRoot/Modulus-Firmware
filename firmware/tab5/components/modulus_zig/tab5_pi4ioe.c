/*
 * PI4IOE5V6408 x2 — ported from Modulus C++ m5stack_tab5 BSP fork.
 * Registry espressif/m5stack_tab5 1.2 lacks PMIC/antenna helpers.
 */
#include "tab5_pi4ioe.h"
#include "tab5_hw.h"

#include <bsp/m5stack_tab5.h>
#include <esp_log.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <sdkconfig.h>

static const char *TAG = "tab5_pi4ioe";

#define PI4IO_REG_CHIP_RESET 0x01
#define PI4IO_REG_IO_DIR     0x03
#define PI4IO_REG_OUT_SET    0x05
#define PI4IO_REG_OUT_H_IM   0x07
#define PI4IO_REG_IN_DEF_STA 0x09
#define PI4IO_REG_PULL_EN    0x0B
#define PI4IO_REG_PULL_SEL   0x0D
#define PI4IO_REG_IN_STA     0x0F
#define PI4IO_REG_INT_MASK   0x11

#define I2C_TIMEOUT_MS 50

static i2c_master_dev_handle_t s_e1 = NULL;
static i2c_master_dev_handle_t s_e2 = NULL;
static bool s_ready = false;
static int64_t s_wlan_pwr_on_us;
static int64_t s_c6_reset_us;

static void setbit(uint8_t *x, uint8_t y) { *x |= (uint8_t)(1U << y); }
static void clrbit(uint8_t *x, uint8_t y) { *x &= (uint8_t)~(1U << y); }

static esp_err_t wr1(i2c_master_dev_handle_t dev, uint8_t reg, uint8_t val)
{
    uint8_t buf[2] = {reg, val};
    return i2c_master_transmit(dev, buf, sizeof(buf), I2C_TIMEOUT_MS);
}

static esp_err_t rd1(i2c_master_dev_handle_t dev, uint8_t reg, uint8_t *out)
{
    return i2c_master_transmit_receive(dev, &reg, 1, out, 1, I2C_TIMEOUT_MS);
}

static esp_err_t mod_out(i2c_master_dev_handle_t dev, uint8_t pin, bool high)
{
    uint8_t cur = 0;
    esp_err_t err = rd1(dev, PI4IO_REG_OUT_SET, &cur);
    if (err != ESP_OK) {
        return err;
    }
    if (high) {
        setbit(&cur, pin);
    } else {
        clrbit(&cur, pin);
    }
    return wr1(dev, PI4IO_REG_OUT_SET, cur);
}

static bool init_expander1(i2c_master_bus_handle_t bus)
{
    i2c_device_config_t cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = TAB5_I2C_ADDR_PI4IOE1,
        .scl_speed_hz = 400000,
    };
    if (i2c_master_bus_add_device(bus, &cfg, &s_e1) != ESP_OK || !s_e1) {
        return false;
    }

    uint8_t rb = 0;
    (void)wr1(s_e1, PI4IO_REG_CHIP_RESET, 0xFF);
    (void)rd1(s_e1, PI4IO_REG_CHIP_RESET, &rb);
    (void)wr1(s_e1, PI4IO_REG_IO_DIR, 0b01111111);
    (void)wr1(s_e1, PI4IO_REG_OUT_H_IM, 0b00000000);
    (void)wr1(s_e1, PI4IO_REG_PULL_SEL, 0b01111111);
    (void)wr1(s_e1, PI4IO_REG_PULL_EN, 0b01111111);
    /* SPK, EXT5V, LCD_RST, TP_RST, CAM_RST high */
    (void)wr1(s_e1, PI4IO_REG_OUT_SET, 0b01110110);
    return true;
}

static bool init_expander2(i2c_master_bus_handle_t bus)
{
    i2c_device_config_t cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = TAB5_I2C_ADDR_PI4IOE2,
        .scl_speed_hz = 400000,
    };
    if (i2c_master_bus_add_device(bus, &cfg, &s_e2) != ESP_OK || !s_e2) {
        return false;
    }

    uint8_t rb = 0;
    (void)wr1(s_e2, PI4IO_REG_CHIP_RESET, 0xFF);
    (void)rd1(s_e2, PI4IO_REG_CHIP_RESET, &rb);
    (void)wr1(s_e2, PI4IO_REG_IO_DIR, 0b10111001);
    (void)wr1(s_e2, PI4IO_REG_OUT_H_IM, 0b00000110);
    (void)wr1(s_e2, PI4IO_REG_PULL_SEL, 0b10111001);
    (void)wr1(s_e2, PI4IO_REG_PULL_EN, 0b11111001);
    (void)wr1(s_e2, PI4IO_REG_IN_DEF_STA, 0b01000000);
    (void)wr1(s_e2, PI4IO_REG_INT_MASK, 0b10111111);
    /* WLAN_PWR high; USB5V/CHG_EN low until power_shim applies NVS */
    (void)wr1(s_e2, PI4IO_REG_OUT_SET, 0b00000001);
    /* Read-back so the C6 power rail state is visible on serial (P4-only boot). */
    uint8_t out_rb = 0;
    (void)rd1(s_e2, PI4IO_REG_OUT_SET, &out_rb);
    ESP_LOGI(TAG, "WLAN_PWR_EN (E2.P0) -> 1 (OUT_SET=0x%02X P0=%d)", out_rb,
             (out_rb & (1U << TAB5_E2_P0_WLAN_PWR)) ? 1 : 0);
    tab5_pi4ioe_note_wlan_pwr_on();
    return true;
}

bool tab5_pi4ioe_init(i2c_master_bus_handle_t bus)
{
    if (s_ready) {
        return true;
    }
    if (!bus) {
        ESP_LOGE(TAG, "I2C bus handle NULL");
        return false;
    }

    if (!init_expander1(bus)) {
        ESP_LOGE(TAG, "PI4IOE1 (0x%02X) init failed", TAB5_I2C_ADDR_PI4IOE1);
        return false;
    }
    if (!init_expander2(bus)) {
        ESP_LOGE(TAG, "PI4IOE2 (0x%02X) init failed", TAB5_I2C_ADDR_PI4IOE2);
        return false;
    }

    /* QC bring-up only; CHG_EN restored from NVS in modulus_power_apply_rails(). */
    tab5_pi4ioe_set_charge_qc_en(true);
    vTaskDelay(pdMS_TO_TICKS(50));

    s_ready = true;
    ESP_LOGI(TAG, "PI4IOE1=0x%02X PI4IOE2=0x%02X ready", TAB5_I2C_ADDR_PI4IOE1, TAB5_I2C_ADDR_PI4IOE2);
    return true;
}

bool tab5_pi4ioe_is_ready(void) { return s_ready; }

bool tab5_pi4ioe_ensure_init(void)
{
    if (s_ready) {
        return true;
    }
    if (bsp_i2c_init() != ESP_OK) {
        ESP_LOGE(TAG, "bsp_i2c_init failed");
        return false;
    }
    return tab5_pi4ioe_init(bsp_i2c_get_handle());
}

void tab5_pi4ioe_set_ext_5v_en(bool en)
{
    if (!s_e1) {
        return;
    }
    /* The stock Espressif BSP creates its own esp_io_expander for PI4IOE1 inside
     * bsp_display_start_with_config(), which CHIP-RESETS the expander and writes
     * the High-Z register to 0xFF (every pin high-impedance), then only un-Hi-Z's
     * the pins it manages (LCD/TOUCH/SPK/CAM). EXT5V_EN (P2) is left
     * high-impedance, so writing OUT_SET alone cannot drive the load switch and
     * the rail floats at ~0.6 V (measured). Re-assert P2 as a driven push-pull
     * output every time: direction = output and clear its High-Z bit. This also
     * self-heals if a later bsp_feature_enable() re-Hi-Z's the pin via its cache. */
    uint8_t dir = 0;
    if (rd1(s_e1, PI4IO_REG_IO_DIR, &dir) == ESP_OK &&
        !(dir & (1U << TAB5_E1_P2_EXT5V_EN))) {
        setbit(&dir, TAB5_E1_P2_EXT5V_EN);
        (void)wr1(s_e1, PI4IO_REG_IO_DIR, dir);
    }
    uint8_t hiz = 0;
    if (rd1(s_e1, PI4IO_REG_OUT_H_IM, &hiz) == ESP_OK &&
        (hiz & (1U << TAB5_E1_P2_EXT5V_EN))) {
        clrbit(&hiz, TAB5_E1_P2_EXT5V_EN);
        (void)wr1(s_e1, PI4IO_REG_OUT_H_IM, hiz);
        ESP_LOGW(TAG, "EXT5V_EN (E1.P2) was High-Z (stock BSP clobber) — drive re-enabled");
    }
    uint8_t cur = 0;
    if (rd1(s_e1, PI4IO_REG_OUT_SET, &cur) != ESP_OK) {
        return;
    }
    const bool was = (cur & (1U << TAB5_E1_P2_EXT5V_EN)) != 0;
    (void)mod_out(s_e1, TAB5_E1_P2_EXT5V_EN, en);
    if (was != en) {
        ESP_LOGI(TAG, "EXT5V_EN (E1.P2) -> %d", en);
    }
}

void tab5_pi4ioe_set_usb_5v_en(bool en)
{
    if (!s_e2) {
        return;
    }
    (void)mod_out(s_e2, TAB5_E2_P3_USB5V_EN, en);
    ESP_LOGI(TAG, "USB5V_EN (E2.P3) -> %d", en);
}

void tab5_pi4ioe_note_wlan_pwr_on(void)
{
    if (s_wlan_pwr_on_us != 0) {
        return;
    }
    s_wlan_pwr_on_us = esp_timer_get_time();
    ESP_LOGI(TAG, "WLAN_PWR_EN noted (C6 boot timer started)");
}

void tab5_pi4ioe_cycle_wlan_pwr(void)
{
    if (!s_e2) {
        return;
    }
    ESP_LOGI(TAG, "C6 SDIO: WLAN_PWR cycle (P4 cold boot)");
    (void)mod_out(s_e2, TAB5_E2_P0_WLAN_PWR, false);
    vTaskDelay(pdMS_TO_TICKS(150));
    s_c6_reset_us = 0;
    s_wlan_pwr_on_us = 0;
    (void)mod_out(s_e2, TAB5_E2_P0_WLAN_PWR, true);
    uint8_t out_rb = 0;
    (void)rd1(s_e2, PI4IO_REG_OUT_SET, &out_rb);
    ESP_LOGI(TAG, "WLAN_PWR_EN (E2.P0) -> 1 (OUT_SET=0x%02X P0=%d)", out_rb,
             (out_rb & (1U << TAB5_E2_P0_WLAN_PWR)) ? 1 : 0);
    tab5_pi4ioe_note_wlan_pwr_on();
}

void tab5_pi4ioe_note_c6_reset(void)
{
    s_c6_reset_us = esp_timer_get_time();
    ESP_LOGI(TAG, "C6 SDIO: reset anchor (GPIO15 / esp_hosted retry)");
}

void tab5_pi4ioe_wait_c6_sdio_ready(void)
{
    const int required_ms = CONFIG_MODULUS_C6_BOOT_DELAY_MS;
    int64_t anchor_us = 0;
    const char *anchor_label = "WLAN_PWR_EN";

    if (s_c6_reset_us != 0) {
        anchor_us = s_c6_reset_us;
        anchor_label = "C6_reset";
    } else if (s_wlan_pwr_on_us != 0) {
        anchor_us = s_wlan_pwr_on_us;
    } else {
        tab5_pi4ioe_note_wlan_pwr_on();
        anchor_us = s_wlan_pwr_on_us;
    }

    const int64_t elapsed_ms = (esp_timer_get_time() - anchor_us) / 1000;
    int remain_ms = required_ms - (int)elapsed_ms;
    if (remain_ms < 0) {
        remain_ms = 0;
    }
    ESP_LOGI(TAG, "C6 SDIO: wait %d ms (anchor=%s elapsed=%lld required=%d)", remain_ms,
             anchor_label, (long long)elapsed_ms, required_ms);
    if (remain_ms > 0) {
        vTaskDelay(pdMS_TO_TICKS(remain_ms));
    }
}

void tab5_pi4ioe_set_wifi_power_en(bool en)
{
    if (!s_e2) {
        ESP_LOGW(TAG, "WLAN_PWR_EN skipped — expander2 missing");
        return;
    }
    const esp_err_t err = mod_out(s_e2, TAB5_E2_P0_WLAN_PWR, en);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "WLAN_PWR_EN write failed: %s", esp_err_to_name(err));
        return;
    }
    if (en) {
        tab5_pi4ioe_note_wlan_pwr_on();
    }
    ESP_LOGI(TAG, "WLAN_PWR_EN (E2.P0) -> %d", en);
}

void tab5_pi4ioe_set_ext_antenna_enable(bool en)
{
    if (!s_e1) {
        ESP_LOGW(TAG, "RF antenna skipped — expander1 missing");
        return;
    }
    const esp_err_t err = mod_out(s_e1, TAB5_E1_P0_RF_ANT, en);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "RF antenna write failed: %s", esp_err_to_name(err));
        return;
    }
    ESP_LOGI(TAG, "RF antenna (E1.P0) -> %s", en ? "external MMCX" : "internal PCB");
}

void tab5_pi4ioe_set_spk_en(bool en)
{
    if (!s_e1) {
        return;
    }
    (void)mod_out(s_e1, TAB5_E1_P1_SPK_EN, en);
    ESP_LOGI(TAG, "SPK_EN (E1.P1) -> %d", en);
}

bool tab5_pi4ioe_get_headphone_detect(void)
{
    if (!s_e1) {
        return false;
    }
    uint8_t sta = 0;
    if (rd1(s_e1, PI4IO_REG_IN_STA, &sta) != ESP_OK) {
        return false;
    }
    return (sta & (1U << TAB5_E1_P7_HP_DET)) != 0;
}

void tab5_pi4ioe_set_charge_en(bool en)
{
    if (!s_e2) {
        ESP_LOGW(TAG, "CHG_EN skipped — expander2 missing");
        return;
    }
    const esp_err_t err = mod_out(s_e2, TAB5_E2_P7_CHG_EN, en);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "CHG_EN write failed: %s", esp_err_to_name(err));
        return;
    }
    ESP_LOGI(TAG, "CHG_EN (E2.P7) -> %d", en);
}

void tab5_pi4ioe_set_charge_qc_en(bool en)
{
    if (!s_e2) {
        return;
    }
    uint8_t cur = 0;
    if (rd1(s_e2, PI4IO_REG_OUT_SET, &cur) != ESP_OK) {
        return;
    }
    /* Active-low nCHG_QC: en=true clears P5 */
    if (en) {
        clrbit(&cur, TAB5_E2_P5_NCHG_QC);
    } else {
        setbit(&cur, TAB5_E2_P5_NCHG_QC);
    }
    (void)wr1(s_e2, PI4IO_REG_OUT_SET, cur);
}

void tab5_pi4ioe_generate_poweroff_signal(void)
{
    if (!s_e2) {
        ESP_LOGW(TAG, "PWROFF skipped — PI4IOE2 not ready");
        return;
    }
    ESP_LOGW(TAG, "PMIC PWROFF pulse (E2.P4) x3");
    for (int i = 0; i < 3; i++) {
        (void)mod_out(s_e2, TAB5_E2_P4_PWROFF, true);
        vTaskDelay(pdMS_TO_TICKS(100));
        (void)mod_out(s_e2, TAB5_E2_P4_PWROFF, false);
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

bool tab5_pi4ioe_get_charge_status(void)
{
    if (!s_e2) {
        return false;
    }
    uint8_t sta = 0;
    if (rd1(s_e2, PI4IO_REG_IN_STA, &sta) != ESP_OK) {
        return false;
    }
    return (sta & (1U << TAB5_E2_P6_CHG_STAT)) != 0;
}
