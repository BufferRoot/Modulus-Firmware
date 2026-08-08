/*
 * Tab5 I2C bus scanner — async worker + device name lookup (Storage diagnostics).
 */
#include "i2c_scan_shim.h"
#include "mbus_shim.h"
#include "battery_shim.h"
#include "ext_encoder_shim.h"
#include "tab5_hw.h"

#include <esp_log.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <stdio.h>
#include <string.h>

static const char *TAG = "modulus_i2c_scan";

typedef struct {
    uint8_t addr;
    const char *name;
} known_dev_t;

static const known_dev_t k_known[] = {
    {TAB5_I2C_ADDR_ES8388, "ES8388"},
    {TAB5_I2C_ADDR_ES7210, "ES7210"},
    {TAB5_I2C_ADDR_GT911, "GT911"},
    {TAB5_I2C_ADDR_ST7123, "ST7123"},
    {TAB5_I2C_ADDR_BMI270, "BMI270"},
    {TAB5_I2C_ADDR_RX8130, "RX8130"},
    {TAB5_I2C_ADDR_INA226, "INA226"},
    {TAB5_I2C_ADDR_PI4IOE1, "PI4IOE1"},
    {TAB5_I2C_ADDR_PI4IOE2, "PI4IOE2"},
    {TAB5_I2C_ADDR_EXT_ENCODER, "ExtEncoder"},
};

const char *modulus_i2c_device_name(uint8_t addr)
{
    for (size_t i = 0; i < sizeof(k_known) / sizeof(k_known[0]); ++i) {
        if (k_known[i].addr == addr) {
            return k_known[i].name;
        }
    }
    return "unknown";
}

void modulus_i2c_format_addr_list(const uint8_t *addrs, uint8_t count, char *buf, size_t len)
{
    if (!buf || len == 0) {
        return;
    }
    if (!addrs || count == 0) {
        snprintf(buf, len, "no devices");
        return;
    }
    enum { k_max_list_devices = 8 };
    const uint8_t show = count > k_max_list_devices ? k_max_list_devices : count;
    int n = 0;
    for (uint8_t i = 0; i < show && n < (int)len - 1; ++i) {
        const char *nm = modulus_i2c_device_name(addrs[i]);
        const bool known = strcmp(nm, "unknown") != 0;
        if (i == 0) {
            n += snprintf(buf + n, len - (size_t)n, known ? "0x%02X %s" : "0x%02X",
                          addrs[i], known ? nm : "");
        } else {
            n += snprintf(buf + n, len - (size_t)n, known ? ", 0x%02X %s" : ", 0x%02X",
                          addrs[i], known ? nm : "");
        }
    }
    if (count > k_max_list_devices && n < (int)len - 1) {
        snprintf(buf + n, len - (size_t)n, ", +%u more", (unsigned)(count - k_max_list_devices));
    }
}

static char s_status[32] = "Idle";
static char s_port_a[192] = "Not scanned";
static char s_mbus[192] = "Not scanned";
static char s_exp1[64] = "Not scanned";
static char s_exp2[64] = "Not scanned";

static volatile bool s_busy = false;
static volatile bool s_done = false;
static modulus_i2c_scan_target_t s_target = MODULUS_I2C_SCAN_ALL;

static void format_mbus_line(const modulus_mbus_scan_t *scan, char *buf, size_t len)
{
    char list[128];
    modulus_i2c_format_addr_list(scan->addrs, scan->addr_count, list, sizeof(list));

    modulus_battery_status_t bat = {};
    if (modulus_battery_get_status(&bat) && bat.voltage > 0.01f) {
        snprintf(buf, len, "%.2fV | %u: %s", (double)bat.voltage,
                 (unsigned)scan->addr_count, list);
    } else {
        snprintf(buf, len, "%u: %s", (unsigned)scan->addr_count, list);
    }
}

static void format_exp_line(const modulus_mbus_scan_t *scan, char *buf, size_t len)
{
    if (scan->addr_count == 0) {
        snprintf(buf, len, "not found");
        return;
    }
    const char *nm = modulus_i2c_device_name(scan->addrs[0]);
    snprintf(buf, len, "0x%02X %s OK", scan->addrs[0], nm);
}

static void run_scan(modulus_i2c_scan_target_t target)
{
    modulus_mbus_scan_t scan = {};

    switch (target) {
    case MODULUS_I2C_SCAN_ALL:
        if (modulus_mbus_scan(MODULUS_MBUS_INTERNAL, &scan)) {
            format_mbus_line(&scan, s_mbus, sizeof(s_mbus));
        } else {
            snprintf(s_mbus, sizeof(s_mbus), "M-Bus scan failed");
        }
        memset(&scan, 0, sizeof(scan));
        if (modulus_mbus_scan(MODULUS_MBUS_PORT_A, &scan)) {
            if (scan.addr_count == 0) {
                snprintf(s_port_a, sizeof(s_port_a), "no devices");
            } else {
                char list[128];
                modulus_i2c_format_addr_list(scan.addrs, scan.addr_count, list, sizeof(list));
                snprintf(s_port_a, sizeof(s_port_a), "%u: %s",
                         (unsigned)scan.addr_count, list);
            }
        } else {
            snprintf(s_port_a, sizeof(s_port_a), "Port A scan failed");
        }
        memset(&scan, 0, sizeof(scan));
        if (modulus_mbus_scan(MODULUS_MBUS_EXP1, &scan)) {
            format_exp_line(&scan, s_exp1, sizeof(s_exp1));
        }
        memset(&scan, 0, sizeof(scan));
        if (modulus_mbus_scan(MODULUS_MBUS_EXP2, &scan)) {
            format_exp_line(&scan, s_exp2, sizeof(s_exp2));
        }
        break;

    case MODULUS_I2C_SCAN_MBUS:
        if (modulus_mbus_scan(MODULUS_MBUS_INTERNAL, &scan)) {
            format_mbus_line(&scan, s_mbus, sizeof(s_mbus));
        } else {
            snprintf(s_mbus, sizeof(s_mbus), "scan failed");
        }
        break;

    case MODULUS_I2C_SCAN_PORT_A:
        if (modulus_mbus_scan(MODULUS_MBUS_PORT_A, &scan)) {
            if (scan.addr_count == 0) {
                snprintf(s_port_a, sizeof(s_port_a), "no devices");
            } else {
                char list[128];
                modulus_i2c_format_addr_list(scan.addrs, scan.addr_count, list, sizeof(list));
                snprintf(s_port_a, sizeof(s_port_a), "%u: %s",
                         (unsigned)scan.addr_count, list);
            }
        } else {
            snprintf(s_port_a, sizeof(s_port_a), "scan failed");
        }
        break;

    case MODULUS_I2C_SCAN_EXP1:
        if (modulus_mbus_scan(MODULUS_MBUS_EXP1, &scan)) {
            format_exp_line(&scan, s_exp1, sizeof(s_exp1));
        } else {
            snprintf(s_exp1, sizeof(s_exp1), "scan failed");
        }
        break;

    case MODULUS_I2C_SCAN_EXP2:
        if (modulus_mbus_scan(MODULUS_MBUS_EXP2, &scan)) {
            format_exp_line(&scan, s_exp2, sizeof(s_exp2));
        } else {
            snprintf(s_exp2, sizeof(s_exp2), "scan failed");
        }
        break;
    }
}

static void scan_task(void *arg)
{
    (void)arg;
    modulus_mbus_init();
    run_scan(s_target);
    snprintf(s_status, sizeof(s_status), "Done");
    s_busy = false;
    s_done = true;
    vTaskDelete(NULL);
}

void modulus_i2c_scan_init(void)
{
    /* Idempotent — mbus init deferred to first scan. */
}

bool modulus_i2c_scan_start(modulus_i2c_scan_target_t target)
{
    if (s_busy) {
        return false;
    }
    s_target = target;
    s_done = false;
    s_busy = true;
    snprintf(s_status, sizeof(s_status), "Scanning...");
    BaseType_t ok = xTaskCreatePinnedToCore(scan_task, "i2c_scan", 4096, NULL, 2, NULL, 0);
    if (ok != pdPASS) {
        s_busy = false;
        snprintf(s_status, sizeof(s_status), "Task failed");
        ESP_LOGE(TAG, "scan task create failed");
        return false;
    }
    ESP_LOGI(TAG, "scan start target=%d", (int)target);
    return true;
}

bool modulus_i2c_scan_busy(void) { return s_busy; }

bool modulus_i2c_scan_done(void) { return s_done; }

const char *modulus_i2c_scan_status_text(void) { return s_status; }
const char *modulus_i2c_scan_port_a_text(void) { return s_port_a; }
const char *modulus_i2c_scan_mbus_text(void) { return s_mbus; }
const char *modulus_i2c_scan_exp1_text(void) { return s_exp1; }
const char *modulus_i2c_scan_exp2_text(void) { return s_exp2; }
