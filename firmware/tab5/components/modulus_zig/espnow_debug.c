/*
 * ESP-NOW debug / verbose logging — NVS-backed, serial + UI snapshot.
 */
#include "espnow_debug.h"
#include "c6_sdio_host.h"
#include "cnc_cmd_exports.h"
#include "espnow_stack.h"
#include "nvs_shim.h"
#include "transport_shim.h"
#include "ui_shim.h"
#include "wireless_shim.h"

#include "esp_log.h"

#include <stdio.h>
#include <stdarg.h>
#include <string.h>

static const char *TAG = "en_dbg";

static char s_last_event[96];

static const char *conn_label(uint8_t idx)
{
    if (idx >= 255) {
        return "off";
    }
    static const char *k[] = {"espnow", "ws", "telnet", "usb", "rs485",
                              "ble",    "i2c", "can"};
    return (idx < 8) ? k[idx] : "?";
}

static const char *session_label(uint8_t session)
{
    switch (session) {
    case 0:
        return "disc";
    case 1:
        return "wait";
    case 2:
        return "cfg";
    case 3:
        return "ready";
    default:
        return "?";
    }
}

uint8_t modulus_espnow_log_level(void)
{
    const uint8_t lvl = modulus_nvs_get_u8("en_log", MODULUS_ESPNOW_LOG_OFF);
    return (lvl <= MODULUS_ESPNOW_LOG_VERBOSE) ? lvl : MODULUS_ESPNOW_LOG_OFF;
}

void modulus_espnow_log_set_level(uint8_t level)
{
    if (level > MODULUS_ESPNOW_LOG_VERBOSE) {
        level = MODULUS_ESPNOW_LOG_OFF;
    }
    modulus_nvs_set_u8("en_log", level);
    modulus_espnow_debug_apply_log_tags();
}

bool modulus_espnow_log_active(void)
{
    return modulus_espnow_log_level() > MODULUS_ESPNOW_LOG_OFF;
}

void modulus_espnow_debug_apply_log_tags(void)
{
    const uint8_t lvl = modulus_espnow_log_level();
    const esp_log_level_t esp_lvl = (lvl >= MODULUS_ESPNOW_LOG_VERBOSE) ? ESP_LOG_DEBUG
                                 : (lvl >= MODULUS_ESPNOW_LOG_DEBUG)   ? ESP_LOG_INFO
                                                                       : ESP_LOG_WARN;
    esp_log_level_set("wl_espnow", esp_lvl);
    esp_log_level_set("espnow_tx", esp_lvl);
    esp_log_level_set(TAG, esp_lvl);
}

void modulus_espnow_debug_event(const char *src, const char *fmt, ...)
{
    char msg[80];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msg, sizeof(msg), fmt, ap);
    va_end(ap);

    snprintf(s_last_event, sizeof(s_last_event), "%s: %s", src ? src : "?", msg);

    const uint8_t lvl = modulus_espnow_log_level();
    if (lvl >= MODULUS_ESPNOW_LOG_DEBUG) {
        ESP_LOGI(TAG, "[%s] %s", src ? src : "?", msg);
    }
}

const char *modulus_espnow_debug_last_event(void)
{
    return s_last_event[0] ? s_last_event : "(none)";
}

const char *modulus_espnow_debug_snapshot(void)
{
    static char buf[128];
    const uint8_t nvs = modulus_nvs_get_u8("cnc_conn", 4);
    const uint8_t active = modulus_zig_active_transport();
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);

    snprintf(buf, sizeof(buf),
             "nvs=%s act=%s ses=%s cnc=%u | rad=%s br=%s tx=%s c6=%s stk=%s",
             conn_label(nvs), conn_label(active), session_label(st.session),
             (unsigned)st.connected,
             modulus_wireless_espnow_is_enabled() ? "on" : "off",
             modulus_wireless_espnow_bridge_ready() ? "ok" : "no",
             modulus_espnow_transport_is_open() ? "open" : "idle",
             modulus_c6_sdio_ready() ? "up" : "down",
             modulus_espnow_stack_inited() ? "ok" : "no");
    return buf;
}
