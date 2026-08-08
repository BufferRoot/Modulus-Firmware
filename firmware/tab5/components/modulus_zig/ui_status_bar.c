#include "ui_internal.h"
#include "ui_status_bar_priv.h"
#include "battery_shim.h"
#include "cnc_cmd_exports.h"
#include "wireless_shim.h"

#include <stdio.h>
#include <string.h>

static status_bar_t s_bar = {};

/* Cached state — dashboard tick calls update(); skip LVGL writes when unchanged. */
static char s_cached_clock[16] = {};
static uint8_t s_cached_state = 0xFF;
static uint8_t s_cached_session = 0xFF;
static int8_t s_cached_mpg = -1;
static int8_t s_cached_mpg_rem = -1;
static uint8_t s_cached_wcs = 0xFF;
static uint16_t s_cached_tool = 0xFFFF;
static float s_cached_feed = -1.0f;
static int8_t s_cached_units = -1;
static uint32_t s_cached_spindle = 0xFFFFFFFFu;
static uint16_t s_cached_batt = 0xFFFF;
static uint8_t s_cached_batt_charge = 0xFF;
static uint8_t s_cached_batt_icon = 0xFF;
static uint32_t s_cached_batt_color = 0xFFFFFFFFu;
static uint8_t s_cached_wifi_st = 0xFF;
static uint8_t s_cached_ble_st = 0xFF;
static uint8_t s_cached_en_st = 0xFF;
static uint32_t s_cached_wifi_color = 0xFFFFFFFFu;
static uint32_t s_cached_ble_color = 0xFFFFFFFFu;
static uint32_t s_cached_en_color = 0xFFFFFFFFu;
static bool s_alarm_snack = false;
static bool s_wifi_snack = false;
static uint8_t s_prev_wifi_st = 0xFF;

static void bar_bust_caches(void)
{
    s_cached_clock[0] = '\0';
    s_cached_state = 0xFF;
    s_cached_session = 0xFF;
    s_cached_mpg = -1;
    s_cached_mpg_rem = -1;
    s_cached_wcs = 0xFF;
    s_cached_tool = 0xFFFF;
    s_cached_feed = -1.0f;
    s_cached_units = -1;
    s_cached_spindle = 0xFFFFFFFFu;
    s_cached_batt = 0xFFFF;
    s_cached_batt_charge = 0xFF;
    s_cached_batt_icon = 0xFF;
    s_cached_batt_color = 0xFFFFFFFFu;
    s_cached_wifi_st = 0xFF;
    s_cached_ble_st = 0xFF;
    s_cached_en_st = 0xFF;
    s_cached_wifi_color = 0xFFFFFFFFu;
    s_cached_ble_color = 0xFFFFFFFFu;
    s_cached_en_color = 0xFFFFFFFFu;
}

void modulus_ui_status_bar_create(lv_obj_t *parent)
{
    bar_build(parent, &s_bar);
}

void modulus_ui_status_bar_invalidate(void)
{
    bar_bust_caches();
}

void modulus_ui_status_bar_theme_refresh(void)
{
    if (!s_bar.bar) {
        return;
    }
    lv_obj_set_style_bg_color(s_bar.bar, modulus_ui_color_surface_container_high(), 0);
    lv_obj_set_style_bg_color(s_bar.mpg_btn, modulus_ui_color_surface_container_highest(), 0);
    lv_obj_set_style_text_color(s_bar.mpg_lbl, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_color(s_bar.wcs_val, modulus_ui_color_primary(), 0);
    lv_obj_set_style_text_color(s_bar.clock_lbl, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_color(s_bar.batt_pct, modulus_ui_color_on_surface_variant(), 0);
    if (s_bar.tool_hdr) {
        lv_obj_set_style_text_color(s_bar.tool_hdr, modulus_ui_color_on_surface_variant(), 0);
    }
    if (s_bar.tool_val) {
        lv_obj_set_style_text_color(s_bar.tool_val, modulus_ui_color_on_surface(), 0);
    }
    if (s_bar.feed_hdr) {
        lv_obj_set_style_text_color(s_bar.feed_hdr, modulus_ui_color_on_surface_variant(), 0);
    }
    if (s_bar.feed_val) {
        lv_obj_set_style_text_color(s_bar.feed_val, modulus_ui_color_on_surface(), 0);
    }
    if (s_bar.feed_unit) {
        lv_obj_set_style_text_color(s_bar.feed_unit, modulus_ui_color_on_surface_variant(), 0);
    }
    if (s_bar.spin_hdr) {
        lv_obj_set_style_text_color(s_bar.spin_hdr, modulus_ui_color_on_surface_variant(), 0);
    }
    if (s_bar.spin_val) {
        lv_obj_set_style_text_color(s_bar.spin_val, modulus_ui_color_on_surface(), 0);
    }
    if (s_bar.spin_unit) {
        lv_obj_set_style_text_color(s_bar.spin_unit, modulus_ui_color_on_surface_variant(), 0);
    }
    modulus_ui_icon_recolor(s_bar.settings_icon, modulus_ui_color_icon_chrome());
    modulus_ui_icon_recolor(s_bar.power_icon, MOD_UI_COLOR_SEMANTIC_POWER);
    if (s_bar.mpg_icon) {
        modulus_ui_icon_recolor(s_bar.mpg_icon, modulus_ui_color_icon_chrome());
    }
    bar_bust_caches();
}

void modulus_ui_status_bar_update(const modulus_cnc_status_t *st)
{
    if (!s_bar.state_lbl || !st) {
        return;
    }
    char buf[40];

    if (st->session != s_cached_session) {
        s_cached_session = st->session;
        lv_obj_set_style_bg_color(s_bar.conn_dot, bar_conn_color(st->session), 0);
    }

    const uint8_t display_state = st->connected ? st->state : 0;
    if (display_state != s_cached_state) {
        s_cached_state = display_state;
        lv_color_t bg = {};
        lv_color_t fg = {};
        bar_state_pill_style(display_state, st->connected != 0, &bg, &fg);
        lv_label_set_text(s_bar.state_lbl, bar_state_name(display_state));
        lv_obj_set_style_bg_color(s_bar.state_badge, bg, 0);
        lv_obj_set_style_text_color(s_bar.state_lbl, fg, 0);
        if (s_bar.alarm_badge) {
            if (st->connected && display_state == 5) {
                lv_obj_remove_flag(s_bar.alarm_badge, LV_OBJ_FLAG_HIDDEN);
            } else {
                lv_obj_add_flag(s_bar.alarm_badge, LV_OBJ_FLAG_HIDDEN);
            }
        }
        const bool alarm = st->connected && display_state == 5;
        if (alarm && !s_alarm_snack) {
            s_alarm_snack = true;
            modulus_ui_snackbar_show("Machine alarm active", 0);
        } else if (!alarm && s_alarm_snack) {
            s_alarm_snack = false;
            if (modulus_ui_snackbar_is_sticky()) {
                modulus_ui_snackbar_hide();
            }
        }
    }

    const uint8_t mpg_rem = modulus_zig_mpg_remote();
    if ((int8_t)st->mpg_active != s_cached_mpg || (int8_t)mpg_rem != s_cached_mpg_rem) {
        s_cached_mpg = (int8_t)st->mpg_active;
        s_cached_mpg_rem = (int8_t)mpg_rem;
        if (st->mpg_active) {
            lv_obj_set_style_bg_color(s_bar.mpg_btn, modulus_ui_color_primary(), 0);
            lv_obj_set_style_text_color(s_bar.mpg_lbl, modulus_ui_color_on_primary(), 0);
            modulus_ui_icon_recolor(s_bar.mpg_icon, modulus_ui_color_on_primary());
            modulus_ui_label_set_text_if_changed(s_bar.mpg_lbl, mpg_rem ? "MPG rem" : "MPG");
        } else {
            lv_obj_set_style_bg_color(s_bar.mpg_btn, modulus_ui_color_surface_container_highest(), 0);
            lv_obj_set_style_text_color(s_bar.mpg_lbl, modulus_ui_color_on_surface_variant(), 0);
            modulus_ui_icon_recolor(s_bar.mpg_icon, modulus_ui_color_icon_chrome());
            modulus_ui_label_set_text_if_changed(s_bar.mpg_lbl, "MPG off");
        }
    }

    if (st->wcs != s_cached_wcs) {
        s_cached_wcs = st->wcs;
        lv_label_set_text(s_bar.wcs_val, bar_wcs_name(st->wcs));
    }

    if (st->tool_number != s_cached_tool) {
        s_cached_tool = st->tool_number;
        snprintf(buf, sizeof(buf), "T%02u", st->tool_number);
        lv_label_set_text(s_bar.tool_val, buf);
    }

    if (st->feed_rate != s_cached_feed || (int8_t)st->units_mm != s_cached_units) {
        s_cached_feed = st->feed_rate;
        s_cached_units = (int8_t)st->units_mm;
        snprintf(buf, sizeof(buf), "%.0f", st->feed_rate);
        lv_label_set_text(s_bar.feed_val, buf);
        lv_label_set_text(s_bar.feed_unit, st->units_mm ? "mm/min" : "in/min");
    }

    if (st->spindle_rpm != s_cached_spindle) {
        s_cached_spindle = st->spindle_rpm;
        snprintf(buf, sizeof(buf), "%lu", (unsigned long)st->spindle_rpm);
        lv_label_set_text(s_bar.spin_val, buf);
    }

    bar_format_clock(buf, sizeof(buf));
    if (strcmp(buf, s_cached_clock) != 0) {
        strncpy(s_cached_clock, buf, sizeof(s_cached_clock) - 1);
        s_cached_clock[sizeof(s_cached_clock) - 1] = '\0';
        lv_label_set_text(s_bar.clock_lbl, buf);
    }

    modulus_battery_status_t batt = {};
    if (modulus_battery_get_status(&batt)) {
        const bool warn = modulus_battery_is_low_warn(&batt);
        const modulus_ui_icon_id_t icon = bar_batt_icon(&batt);
        const lv_color_t color = modulus_ui_icon_battery_color_for_state(batt.charge_state, batt.percent, warn);
        const uint32_t color_u32 = lv_color_to_u32(color);
        const bool pct_changed = batt.percent != s_cached_batt;
        const bool charge_changed = batt.charge_state != s_cached_batt_charge;
        const bool icon_changed = (uint8_t)icon != s_cached_batt_icon;
        const bool color_changed = color_u32 != s_cached_batt_color;
        if (pct_changed || charge_changed || icon_changed || color_changed) {
            s_cached_batt = batt.percent;
            s_cached_batt_charge = batt.charge_state;
            s_cached_batt_icon = (uint8_t)icon;
            s_cached_batt_color = color_u32;
            if (batt.charge_state == 3) {
                lv_label_set_text(s_bar.batt_pct, "N/A");
            } else {
                snprintf(buf, sizeof(buf), "%u%%", batt.percent);
                lv_label_set_text(s_bar.batt_pct, buf);
            }
            if (icon_changed) {
                modulus_ui_icon_set(s_bar.batt_icon, icon, MOD_UI_ICON_SZ_32);
            }
            if (color_changed) {
                modulus_ui_icon_recolor(s_bar.batt_icon, color);
                lv_obj_set_style_text_color(s_bar.batt_pct, color, 0);
            }
        }
    }

    bar_update_wireless(&s_bar, &s_cached_wifi_st, &s_cached_ble_st, &s_cached_en_st,
                        &s_cached_wifi_color, &s_cached_ble_color, &s_cached_en_color);

    if (s_prev_wifi_st == 3 && s_cached_wifi_st == 1 && modulus_wireless_wifi_is_enabled()) {
        if (!s_wifi_snack) {
            s_wifi_snack = true;
            modulus_ui_snackbar_show("Wi-Fi disconnected", 0);
        }
    } else if (s_cached_wifi_st == 3 && s_wifi_snack) {
        s_wifi_snack = false;
        if (modulus_ui_snackbar_is_sticky()) {
            modulus_ui_snackbar_hide();
        }
    }
    s_prev_wifi_st = s_cached_wifi_st;
}
