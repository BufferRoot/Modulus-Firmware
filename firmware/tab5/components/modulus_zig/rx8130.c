/*
 * RX8130CE RTC — register map from M5Stack reference (Modulus Firmware rx8130.cpp).
 */
#include "rx8130.h"

#include "i2c_coex_shim.h"

#include <esp_log.h>
#include <freertos/FreeRTOS.h>
#include <string.h>

static const char *TAG = "rx8130";

static i2c_master_dev_handle_t s_dev = NULL;

#define RX8130_REG_SEC   0x10
#define RX8130_REG_MIN   0x11
#define RX8130_REG_HOUR  0x12
#define RX8130_REG_WDAY  0x13
#define RX8130_REG_MDAY  0x14
#define RX8130_REG_MONTH 0x15
#define RX8130_REG_YEAR  0x16
#define RX8130_REG_FLAG  0x1D
#define RX8130_REG_CTRL0 0x1E
#define RX8130_REG_CTRL1 0x1F
#define RX8130_REG_EXTENSION 0x1C
#define RX8130_REG_TIMER_COUNTER_LOW  0x1A
#define RX8130_REG_TIMER_COUNTER_HIGH 0x1B

#define RX8130_BIT_CTRL_STOP 0x40
#define RX8130_BIT_FLAG_VLF  0x02

static uint8_t bcd2dec(uint8_t val)
{
    return (uint8_t)((val >> 4) * 10 + (val & 0x0f));
}

static uint8_t dec2bcd(uint8_t val)
{
    return (uint8_t)(((val / 10) << 4) + (val % 10));
}

static esp_err_t read_reg(uint8_t reg, uint8_t *buf, size_t len)
{
    if (!s_dev) {
        return ESP_ERR_INVALID_STATE;
    }
    return i2c_master_transmit_receive(s_dev, &reg, 1, buf, len, pdMS_TO_TICKS(100));
}

static esp_err_t write_reg(uint8_t reg, const uint8_t *buf, size_t len)
{
    if (!s_dev) {
        return ESP_ERR_INVALID_STATE;
    }
    uint8_t wbuf[1 + 8];
    if (len > sizeof(wbuf) - 1) {
        return ESP_ERR_INVALID_SIZE;
    }
    wbuf[0] = reg;
    memcpy(wbuf + 1, buf, len);
    return i2c_master_transmit(s_dev, wbuf, 1 + len, pdMS_TO_TICKS(100));
}

static esp_err_t read_reg8(uint8_t reg, uint8_t *out)
{
    return read_reg(reg, out, 1);
}

static esp_err_t write_reg8(uint8_t reg, uint8_t value)
{
    return write_reg(reg, &value, 1);
}

bool rx8130_is_ready(void)
{
    return s_dev != NULL;
}

bool rx8130_begin(i2c_master_bus_handle_t bus, uint8_t addr)
{
    if (s_dev) {
        return true;
    }
    if (!bus) {
        return false;
    }

    const i2c_device_config_t dev_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = addr,
        .scl_speed_hz = 400000,
    };
    if (i2c_master_bus_add_device(bus, &dev_cfg, &s_dev) != ESP_OK || s_dev == NULL) {
        ESP_LOGE(TAG, "I2C add device 0x%02X failed", addr);
        s_dev = NULL;
        return false;
    }
    return true;
}

void rx8130_init_bat(void)
{
    uint8_t data = 0;
    if (read_reg8(RX8130_REG_CTRL1, &data) != ESP_OK) {
        ESP_LOGW(TAG, "battery backup init read failed");
        return;
    }
    data |= (1 << 4);
    data |= (1 << 5);
    if (write_reg8(RX8130_REG_CTRL1, data) != ESP_OK) {
        ESP_LOGW(TAG, "battery backup init write failed");
        return;
    }
    if (read_reg8(RX8130_REG_CTRL1, &data) == ESP_OK) {
        ESP_LOGI(TAG, "battery backup CTRL1=0x%02X", data);
    }
}

void rx8130_set_time(struct tm *time)
{
    if (!s_dev || !time) {
        return;
    }

    struct tm t = *time;
    t.tm_year -= 100;

    uint8_t ctrl = 0;
    if (read_reg8(RX8130_REG_CTRL0, &ctrl) != ESP_OK) {
        return;
    }
    ctrl |= RX8130_BIT_CTRL_STOP;
    if (write_reg8(RX8130_REG_CTRL0, ctrl) != ESP_OK) {
        return;
    }

    const uint8_t date[7] = {
        dec2bcd((uint8_t)t.tm_sec),
        dec2bcd((uint8_t)t.tm_min),
        dec2bcd((uint8_t)t.tm_hour),
        dec2bcd((uint8_t)t.tm_wday),
        dec2bcd((uint8_t)t.tm_mday),
        dec2bcd((uint8_t)t.tm_mon),
        dec2bcd((uint8_t)(t.tm_year % 100)),
    };
    if (write_reg(RX8130_REG_SEC, date, sizeof(date)) != ESP_OK) {
        ESP_LOGW(TAG, "set_time write failed");
        return;
    }

    if (read_reg8(RX8130_REG_CTRL0, &ctrl) != ESP_OK) {
        return;
    }
    ctrl &= (uint8_t)~RX8130_BIT_CTRL_STOP;
    write_reg8(RX8130_REG_CTRL0, ctrl);
}

bool rx8130_get_time(struct tm *time)
{
    if (!s_dev || !time) {
        return false;
    }

    uint8_t date[7] = {};
    if (read_reg(RX8130_REG_SEC, date, sizeof(date)) != ESP_OK) {
        return false;
    }

    memset(time, 0, sizeof(*time));
    time->tm_sec = bcd2dec(date[0] & 0x7f);
    time->tm_min = bcd2dec(date[1] & 0x7f);
    time->tm_hour = bcd2dec(date[2] & 0x3f);
    time->tm_wday = bcd2dec(date[3] & 0x7f);
    time->tm_mday = bcd2dec(date[4] & 0x3f);
    time->tm_mon = bcd2dec(date[5] & 0x1f);
    time->tm_year = bcd2dec(date[6]) + 100;
    time->tm_isdst = -1;
    return true;
}

void rx8130_clear_irq_flags(void)
{
    write_reg8(RX8130_REG_FLAG, 0);
}

void rx8130_disable_irq(void)
{
    write_reg8(RX8130_REG_CTRL0, 0);
}

bool rx8130_voltage_low(void)
{
    uint8_t flag = 0;
    if (read_reg8(RX8130_REG_FLAG, &flag) != ESP_OK) {
        return false;
    }
    return (flag & RX8130_BIT_FLAG_VLF) != 0;
}

void rx8130_set_timer_irq(uint16_t seconds)
{
    if (!s_dev || seconds == 0) {
        return;
    }

    uint8_t ext = 0;
    if (read_reg8(RX8130_REG_EXTENSION, &ext) != ESP_OK) {
        return;
    }
    ext &= (uint8_t)~(1 << 4);
    write_reg8(RX8130_REG_EXTENSION, ext);

    const uint8_t cnt[2] = {
        (uint8_t)(seconds & 0xFF),
        (uint8_t)((seconds >> 8) & 0xFF),
    };
    if (write_reg(RX8130_REG_TIMER_COUNTER_LOW, cnt, sizeof(cnt)) != ESP_OK) {
        return;
    }

    if (read_reg8(RX8130_REG_EXTENSION, &ext) != ESP_OK) {
        return;
    }
    ext |= (1 << 4);
    ext &= (uint8_t)~(1 << 2);
    ext |= (1 << 1);
    ext &= (uint8_t)~1;
    write_reg8(RX8130_REG_EXTENSION, ext);

    uint8_t ctrl = 0;
    if (read_reg8(RX8130_REG_CTRL0, &ctrl) != ESP_OK) {
        return;
    }
    ctrl |= (1 << 4);
    write_reg8(RX8130_REG_CTRL0, ctrl);
    ESP_LOGI(TAG, "Timer IRQ armed %u s -> E_TRG", (unsigned)seconds);
}
