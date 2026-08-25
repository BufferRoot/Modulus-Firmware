#include "ui_status_bar_priv.h"

#include "ui_internal.h"

#include "battery_shim.h"
#include "wireless_shim.h"

#include "nvs_shim.h"

#include <string.h>
#include <time.h>

const char *bar_state_name(uint8_t st)
{
    switch (st) {
    case 1:
        return "Idle";
    case 2:
        return "Run";
    case 3:
        return "Hold";
    case 4:
        return "Jog";
    case 5:
        return "Alarm";
    case 6:
        return "Door";
    case 7:
        return "Check";
    case 8:
        return "Home";
    case 9:
        return "Sleep";
    case 10:
        return "Tool";
    default:
        return "Offline";
    }
}

const char *bar_wcs_name(uint8_t wcs)
{
    static char s_custom[16];
    static const char *const k_keys[] = {
        "wcs_n0", "wcs_n1", "wcs_n2", "wcs_n3", "wcs_n4", "wcs_n5",
    };
    static const char *const k_def[] = {
        "G54", "G55", "G56", "G57", "G58", "G59",
    };
    if (wcs < 6) {
        if (modulus_nvs_get_str(k_keys[wcs], s_custom, sizeof(s_custom)) && s_custom[0] != '\0') {
            return s_custom;
        }
        return k_def[wcs];
    }
    switch (wcs) {
    case 6:
        return "G59.1";
    case 7:
        return "G59.2";
    case 8:
        return "G59.3";
    default:
        return "G54";
    }
}

lv_color_t bar_conn_color(uint8_t session)
{
    if (session >= 4 && session <= 6) {
        return modulus_ui_color_success();
    }
    if (session >= 1 && session <= 3) {
        return modulus_ui_color_warning();
    }
    return modulus_ui_color_neutral();
}

void bar_state_pill_style(uint8_t st, bool connected, lv_color_t *bg, lv_color_t *fg)
{
    /* Offline / idle: tonal containers. CNC cycle/hold/home stay fixed semantic. */
    if (!connected) {
        *bg = modulus_ui_color_tertiary_container();
        *fg = modulus_ui_color_on_tertiary_container();
        return;
    }

    switch (st) {
    case 1: /* Idle */
        *bg = modulus_ui_color_secondary_container();
        *fg = modulus_ui_color_on_secondary_container();
        break;
    case 2: /* Cycle */
        *bg = modulus_ui_color_cycle();
        *fg = modulus_ui_color_on_cycle();
        break;
    case 3:
    case 6: /* Hold / door */
        *bg = modulus_ui_color_hold();
        *fg = modulus_ui_color_on_hold();
        break;
    case 4: /* Jog / check */
        *bg = modulus_ui_color_primary_container();
        *fg = modulus_ui_color_on_primary_container();
        break;
    case 5: /* Alarm */
        *bg = modulus_ui_color_error_container();
        *fg = modulus_ui_color_on_error_container();
        break;
    case 8: /* Homing */
        *bg = modulus_ui_color_home_all();
        *fg = modulus_ui_color_on_home();
        break;
    default:
        *bg = modulus_ui_color_secondary_container();
        *fg = modulus_ui_color_on_secondary_container();
        break;
    }
}

void bar_format_clock(char *buf, size_t len)
{
    time_t now = time(NULL);
    struct tm t;

    localtime_r(&now, &t);
    if (modulus_nvs_get_u8("t_24h", 1) != 0) {
        strftime(buf, len, "%H:%M", &t);
        return;
    }

    strftime(buf, len, "%I:%M %p", &t);
}

modulus_ui_icon_id_t bar_batt_icon(const modulus_battery_status_t *st)
{
    const bool warn = modulus_battery_is_low_warn(st);
    return modulus_ui_icon_battery_for_state(st->charge_state, st->percent, warn);
}

uint8_t bar_wireless_wifi_state(void)
{
    if (!modulus_wireless_ready() || !modulus_wireless_wifi_is_enabled()) {
        return 0;
    }
    if (modulus_wireless_wifi_is_connecting()) {
        return 2;
    }
    if (modulus_wireless_wifi_is_connected()) {
        return 3;
    }
    return 1;
}

lv_color_t bar_wireless_wifi_color(uint8_t st)
{
    switch (st) {
    case 2:
        return modulus_ui_color_warning();
    case 3:
        return modulus_ui_color_success();
    case 1:
        return modulus_ui_color_icon_chrome();
    default:
        return modulus_ui_color_on_surface_variant();
    }
}

uint8_t bar_wireless_ble_state(void)
{
    if (!modulus_wireless_ready() || !modulus_wireless_ble_is_enabled()) {
        return 0;
    }
    if (modulus_wireless_ble_is_connecting()) {
        return 2;
    }
    if (modulus_wireless_ble_is_connected()) {
        return 3;
    }
    return 1;
}

lv_color_t bar_wireless_ble_color(uint8_t st)
{
    switch (st) {
    case 2:
        return modulus_ui_color_warning();
    case 3:
        return modulus_ui_color_primary();
    case 1:
        return modulus_ui_color_icon_chrome();
    default:
        return modulus_ui_color_on_surface_variant();
    }
}

uint8_t bar_wireless_espnow_state(void)
{
    if (!modulus_wireless_ready()) {
        return 0;
    }
    if (modulus_wireless_espnow_transport_active()) {
        return 2;
    }
    if (modulus_wireless_espnow_is_enabled()) {
        return 1;
    }
    return 0;
}

lv_color_t bar_wireless_espnow_color(uint8_t st)
{
    switch (st) {
    case 2:
        return modulus_ui_color_success();
    case 1:
        return modulus_ui_color_icon_chrome();
    default:
        return modulus_ui_color_on_surface_variant();
    }
}

void bar_update_wireless(status_bar_t *bar, uint8_t *wifi_st, uint8_t *ble_st, uint8_t *en_st,
                         uint32_t *wifi_color_u32, uint32_t *ble_color_u32, uint32_t *en_color_u32)
{
    if (!bar || !bar->wifi_icon) {
        return;
    }

    const uint8_t wifi = bar_wireless_wifi_state();
    const lv_color_t wifi_color = bar_wireless_wifi_color(wifi);
    const uint32_t wifi_u32 = lv_color_to_u32(wifi_color);
    if (wifi != *wifi_st || wifi_u32 != *wifi_color_u32) {
        *wifi_st = wifi;
        *wifi_color_u32 = wifi_u32;
        modulus_ui_icon_recolor(bar->wifi_icon, wifi_color);
    }
    if (bar->wifi_badge) {
        /* MD3 small badge: Wi-Fi associating / reconnecting. */
        if (wifi == 2) {
            lv_obj_set_style_bg_color(bar->wifi_badge, modulus_ui_color_primary(), 0);
            lv_obj_remove_flag(bar->wifi_badge, LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_add_flag(bar->wifi_badge, LV_OBJ_FLAG_HIDDEN);
        }
    }

    const uint8_t ble = bar_wireless_ble_state();
    const bool ble_show = ble != 0;
    const lv_color_t ble_color = bar_wireless_ble_color(ble);
    const uint32_t ble_u32 = lv_color_to_u32(ble_color);
    const bool ble_visible = !lv_obj_has_flag(bar->ble_icon, LV_OBJ_FLAG_HIDDEN);
    if (ble_show != ble_visible) {
        if (ble_show) {
            lv_obj_remove_flag(bar->ble_icon, LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_add_flag(bar->ble_icon, LV_OBJ_FLAG_HIDDEN);
        }
    }
    if (ble_show && (ble != *ble_st || ble_u32 != *ble_color_u32)) {
        *ble_st = ble;
        *ble_color_u32 = ble_u32;
        modulus_ui_icon_recolor(bar->ble_icon, ble_color);
    } else if (!ble_show && *ble_st != 0) {
        *ble_st = 0;
        *ble_color_u32 = 0;
    }

    const uint8_t en = bar_wireless_espnow_state();
    const bool en_show = en != 0;
    const lv_color_t en_color = bar_wireless_espnow_color(en);
    const uint32_t en_u32 = lv_color_to_u32(en_color);
    const bool en_visible = !lv_obj_has_flag(bar->espnow_icon, LV_OBJ_FLAG_HIDDEN);
    if (en_show != en_visible) {
        if (en_show) {
            lv_obj_remove_flag(bar->espnow_icon, LV_OBJ_FLAG_HIDDEN);
        } else {
            lv_obj_add_flag(bar->espnow_icon, LV_OBJ_FLAG_HIDDEN);
        }
    }
    if (en_show && (en != *en_st || en_u32 != *en_color_u32)) {
        *en_st = en;
        *en_color_u32 = en_u32;
        modulus_ui_icon_recolor(bar->espnow_icon, en_color);
    } else if (!en_show && *en_st != 0) {
        *en_st = 0;
        *en_color_u32 = 0;
    }
}
