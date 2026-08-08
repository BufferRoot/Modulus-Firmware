#include "ui_settings_priv.h"
#include "ui_settings_common.h"
#include "nvs_shim.h"
#include "power_shim.h"
#include "battery_shim.h"
#include "rtc_shim.h"

#include <stdio.h>
#include <string.h>

#define PWR_WAKE_TOUCH 0x01U
#define PWR_WAKE_TIMER 0x02U
#define PWR_WAKE_USB   0x04U

static const uint16_t k_scr_vals[] = {0, 15, 30, 60, 120, 300, 600};
static const uint16_t k_dim_vals[] = {0, 10, 30, 60, 120, 300};
static const uint16_t k_ds_vals[] = {30, 60, 120, 300, 600};
static const uint16_t k_wtm_vals[] = {0, 5, 10, 15, 30, 60, 120, 240, 480};
static const uint8_t k_warn_vals[] = {0, 5, 10, 15, 20, 25, 30};

static bool s_batt_ref_exp = false;

static lv_timer_t *s_pwr_bat_timer = NULL;
static lv_obj_t *s_pwr_dd_dsto = NULL;
static lv_obj_t *s_pwr_dd_wtimer = NULL;
static lv_obj_t *s_pwr_gate_wifi = NULL;
static lv_obj_t *s_pwr_gate_ext = NULL;
static lv_obj_t *s_pwr_gate_usb = NULL;
static lv_obj_t *s_pwr_bat_pct_lbl = NULL;
static lv_obj_t *s_pwr_bat_state_lbl = NULL;
static lv_obj_t *s_pwr_bat_volt_lbl = NULL;
static lv_obj_t *s_pwr_bat_curr_lbl = NULL;
static lv_obj_t *s_pwr_bat_pwr_lbl = NULL;
static lv_obj_t *s_pwr_bat_temp_lbl = NULL;
static lv_obj_t *s_pwr_bat_rate_lbl = NULL;
static lv_obj_t *s_pwr_bat_eta_lbl = NULL;
static lv_obj_t *s_pwr_uptime_lbl = NULL;

static char s_pwr_pct_cache[12] = {};
static char s_pwr_state_cache[16] = {};
static char s_pwr_volt_cache[16] = {};
static char s_pwr_curr_cache[16] = {};
static char s_pwr_pwr_cache[16] = {};
static char s_pwr_temp_cache[16] = {};
static char s_pwr_rate_cache[32] = {};
static char s_pwr_eta_cache[32] = {};
static char s_pwr_uptime_cache[32] = {};
static uint32_t s_pwr_pct_color = 0;
static uint32_t s_pwr_state_color = 0;
static float s_pwr_volt_f = -1.0f;
static float s_pwr_curr_f = -1.0f;
static float s_pwr_pwr_f = -1.0f;
static float s_pwr_temp_f = -1.0f;
static float s_pwr_rate_f = -1.0f;
static uint8_t s_pwr_chg_state = 0xFF;

static void pwr_format_eta(char *buf, size_t len, const modulus_battery_status_t *bat)
{
    if (!buf || len == 0 || !bat || bat->charge_state == 3) {
        if (buf && len) {
            snprintf(buf, len, "--");
        }
        return;
    }
    int32_t mins = -1;
    const char *suffix = "";
    if (bat->charge_state == 1 && bat->time_to_full >= 0) {
        mins = bat->time_to_full;
        suffix = " to full";
    } else if (bat->charge_state == 0 && bat->time_to_empty >= 0) {
        mins = bat->time_to_empty;
        suffix = " left";
    }
    if (mins < 0) {
        snprintf(buf, len, "--");
        return;
    }
    const uint32_t h = (uint32_t)mins / 60U;
    const uint32_t m = (uint32_t)mins % 60U;
    if (h > 0) {
        snprintf(buf, len, "~%luh %lum%s", (unsigned long)h, (unsigned long)m, suffix);
    } else {
        snprintf(buf, len, "~%lum%s", (unsigned long)m, suffix);
    }
}

static int pwr_find_u16_idx(const uint16_t *vals, int count, uint16_t val)
{
    for (int i = 0; i < count; i++) {
        if (vals[i] == val) {
            return i;
        }
    }
    return 0;
}

static int pwr_find_closest_idx(const uint16_t *vals, int count, uint16_t val, int fallback)
{
    int best = fallback;
    int best_diff = 32767;
    for (int i = 0; i < count; i++) {
        int diff = (int)vals[i] - (int)val;
        if (diff < 0) {
            diff = -diff;
        }
        if (diff < best_diff) {
            best_diff = diff;
            best = i;
        }
    }
    return best;
}

static void pwr_set_lbl_if_changed(lv_obj_t *lbl, const char *text, char *cache, size_t cache_sz)
{
    if (!lbl || !text) {
        return;
    }
    if (cache[0] != '\0' && strcmp(cache, text) == 0) {
        return;
    }
    lv_label_set_text(lbl, text);
    strncpy(cache, text, cache_sz - 1);
    cache[cache_sz - 1] = '\0';
}

static void pwr_set_color_if_changed(lv_obj_t *lbl, lv_color_t c, uint32_t *cache)
{
    if (!lbl || !cache) {
        return;
    }
    const uint32_t next = lv_color_to_u32(c);
    if (*cache == next) {
        return;
    }
    lv_obj_set_style_text_color(lbl, c, 0);
    *cache = next;
}

static void pwr_set_control_enabled(lv_obj_t *ctrl, bool enabled)
{
    if (!ctrl) {
        return;
    }
    modulus_ui_settings_row_set_enabled(lv_obj_get_parent(ctrl), ctrl, enabled);
}

static void pwr_sync_deep_sleep_ui(bool deep_sleep)
{
    pwr_set_control_enabled(s_pwr_dd_dsto, deep_sleep);
    pwr_set_control_enabled(s_pwr_gate_wifi, deep_sleep);
    pwr_set_control_enabled(s_pwr_gate_ext, deep_sleep);
    pwr_set_control_enabled(s_pwr_gate_usb, deep_sleep);
}

static void pwr_sync_wake_timer_ui(bool wake_timer_on)
{
    pwr_set_control_enabled(s_pwr_dd_wtimer, wake_timer_on);
}

static lv_color_t pwr_pct_color(uint8_t st, uint8_t pct)
{
    if (st == 1) {
        return modulus_ui_color_primary();
    }
    if (st == 2) {
        return modulus_ui_color_success();
    }
    if (pct > 50) {
        return modulus_ui_color_success();
    }
    if (pct > 20) {
        return modulus_ui_color_warning();
    }
    return modulus_ui_color_error();
}

static lv_color_t pwr_state_color(uint8_t st, uint8_t pct)
{
    if (st == 1) {
        return modulus_ui_color_primary();
    }
    if (st == 2) {
        return modulus_ui_color_success();
    }
    if (st == 3) {
        return modulus_ui_color_warning();
    }
    if (pct <= 20) {
        return modulus_ui_color_error();
    }
    if (pct <= 50) {
        return modulus_ui_color_warning();
    }
    return modulus_ui_color_on_surface_variant();
}

static const char *pwr_charge_state_str(uint8_t st)
{
    switch (st) {
    case 1:
        return "Charging";
    case 2:
        return "Full";
    case 3:
        return "No battery";
    default:
        return "Discharging";
    }
}

static void pwr_clear_bat_caches(void)
{
    s_pwr_pct_cache[0] = '\0';
    s_pwr_state_cache[0] = '\0';
    s_pwr_volt_cache[0] = '\0';
    s_pwr_curr_cache[0] = '\0';
    s_pwr_pwr_cache[0] = '\0';
    s_pwr_temp_cache[0] = '\0';
    s_pwr_rate_cache[0] = '\0';
    s_pwr_eta_cache[0] = '\0';
    s_pwr_uptime_cache[0] = '\0';
    s_pwr_pct_color = 0;
    s_pwr_state_color = 0;
    s_pwr_volt_f = -1.0f;
    s_pwr_curr_f = -1.0f;
    s_pwr_pwr_f = -1.0f;
    s_pwr_temp_f = -1.0f;
    s_pwr_rate_f = -1.0f;
    s_pwr_chg_state = 0xFF;
}

static void pwr_bat_timer_cb(lv_timer_t *timer)
{
    (void)timer;
    char buf[32];
    if (s_pwr_uptime_lbl) {
        modulus_rtc_format_uptime(buf, sizeof(buf));
        pwr_set_lbl_if_changed(s_pwr_uptime_lbl, buf, s_pwr_uptime_cache, sizeof(s_pwr_uptime_cache));
    }
    modulus_battery_status_t bat = {};
    if (!modulus_battery_get_status(&bat)) {
        return;
    }
    if (s_pwr_bat_pct_lbl) {
        if (bat.charge_state == 3) {
            pwr_set_lbl_if_changed(s_pwr_bat_pct_lbl, "N/A", s_pwr_pct_cache, sizeof(s_pwr_pct_cache));
        } else {
            snprintf(buf, sizeof(buf), "%u%%", bat.percent);
            pwr_set_lbl_if_changed(s_pwr_bat_pct_lbl, buf, s_pwr_pct_cache, sizeof(s_pwr_pct_cache));
            pwr_set_color_if_changed(s_pwr_bat_pct_lbl, pwr_pct_color(bat.charge_state, bat.percent),
                                     &s_pwr_pct_color);
        }
    }
    if (s_pwr_bat_state_lbl) {
        pwr_set_lbl_if_changed(s_pwr_bat_state_lbl, pwr_charge_state_str(bat.charge_state),
                               s_pwr_state_cache, sizeof(s_pwr_state_cache));
        pwr_set_color_if_changed(s_pwr_bat_state_lbl, pwr_state_color(bat.charge_state, bat.percent),
                                 &s_pwr_state_color);
    }
    if (s_pwr_bat_volt_lbl &&
        (s_pwr_volt_f < 0.0f || bat.voltage - s_pwr_volt_f > 0.005f || s_pwr_volt_f - bat.voltage > 0.005f)) {
        snprintf(buf, sizeof(buf), "%.2f V", bat.voltage);
        pwr_set_lbl_if_changed(s_pwr_bat_volt_lbl, buf, s_pwr_volt_cache, sizeof(s_pwr_volt_cache));
        s_pwr_volt_f = bat.voltage;
    }
    if (s_pwr_bat_curr_lbl &&
        (s_pwr_curr_f < 0.0f || bat.current - s_pwr_curr_f > 0.001f || s_pwr_curr_f - bat.current > 0.001f)) {
        snprintf(buf, sizeof(buf), "%.0f mA", bat.current * 1000.0f);
        pwr_set_lbl_if_changed(s_pwr_bat_curr_lbl, buf, s_pwr_curr_cache, sizeof(s_pwr_curr_cache));
        s_pwr_curr_f = bat.current;
    }
    if (s_pwr_bat_pwr_lbl &&
        (s_pwr_pwr_f < 0.0f || bat.power - s_pwr_pwr_f > 0.005f || s_pwr_pwr_f - bat.power > 0.005f)) {
        snprintf(buf, sizeof(buf), "%.2f W", bat.power);
        pwr_set_lbl_if_changed(s_pwr_bat_pwr_lbl, buf, s_pwr_pwr_cache, sizeof(s_pwr_pwr_cache));
        s_pwr_pwr_f = bat.power;
    }
    if (s_pwr_bat_temp_lbl &&
        (s_pwr_temp_f < 0.0f || bat.cpu_temp - s_pwr_temp_f > 0.05f || s_pwr_temp_f - bat.cpu_temp > 0.05f)) {
        snprintf(buf, sizeof(buf), "%.1f C", bat.cpu_temp);
        pwr_set_lbl_if_changed(s_pwr_bat_temp_lbl, buf, s_pwr_temp_cache, sizeof(s_pwr_temp_cache));
        s_pwr_temp_f = bat.cpu_temp;
    }
    if (s_pwr_bat_rate_lbl &&
        (s_pwr_chg_state != bat.charge_state || s_pwr_rate_f < 0.0f ||
         bat.rate_mA - s_pwr_rate_f > 1.0f || s_pwr_rate_f - bat.rate_mA > 1.0f)) {
        if (bat.charge_state == 1) {
            snprintf(buf, sizeof(buf), "%.0f mA (charging)", bat.rate_mA);
        } else if (bat.charge_state == 0) {
            snprintf(buf, sizeof(buf), "%.0f mA (discharging)", bat.rate_mA);
        } else {
            snprintf(buf, sizeof(buf), "--");
        }
        pwr_set_lbl_if_changed(s_pwr_bat_rate_lbl, buf, s_pwr_rate_cache, sizeof(s_pwr_rate_cache));
        s_pwr_rate_f = bat.rate_mA;
        s_pwr_chg_state = bat.charge_state;
    }
    if (s_pwr_bat_eta_lbl) {
        pwr_format_eta(buf, sizeof(buf), &bat);
        pwr_set_lbl_if_changed(s_pwr_bat_eta_lbl, buf, s_pwr_eta_cache, sizeof(s_pwr_eta_cache));
    }
}

static void pwr_panel_scroll_cb(lv_event_t *e)
{
    if (!s_pwr_bat_timer) {
        return;
    }
    const lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_SCROLL_BEGIN) {
        lv_timer_pause(s_pwr_bat_timer);
    } else if (code == LV_EVENT_SCROLL_END) {
        lv_timer_resume(s_pwr_bat_timer);
        pwr_bat_timer_cb(NULL);
    }
}

static void pwr_panel_scroll_hook(bool attach)
{
    lv_obj_t *panel = modulus_ui_settings_tab_panel(MOD_UI_SETTINGS_TAB_POWER);
    if (!panel) {
        return;
    }
    lv_obj_remove_event_cb(panel, pwr_panel_scroll_cb);
    if (attach) {
        lv_obj_add_event_cb(panel, pwr_panel_scroll_cb, LV_EVENT_SCROLL_BEGIN, NULL);
        lv_obj_add_event_cb(panel, pwr_panel_scroll_cb, LV_EVENT_SCROLL_END, NULL);
    }
}

static void rail_ext5v_cb(lv_event_t *e)
{
    modulus_power_set_ext5v(lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED));
}

static void rail_usb5v_cb(lv_event_t *e)
{
    modulus_power_set_usb5v(lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED));
}

static void chg_en_cb(lv_event_t *e)
{
    modulus_power_set_charge_en(lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED));
}

static void pwr_gate_wifi_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    modulus_nvs_set_u8("pwr_gwifi", on ? 1 : 0);
    modulus_power_set_gate_wifi(on);
}

static void pwr_gate_ext_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    modulus_nvs_set_u8("pwr_gext", on ? 1 : 0);
    modulus_power_set_gate_ext5v(on);
}

static void pwr_gate_usb_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    modulus_nvs_set_u8("pwr_gusb", on ? 1 : 0);
    modulus_power_set_gate_usb5v(on);
}

static void pwr_adapt_cb(lv_event_t *e)
{
    modulus_battery_set_adaptive(lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED));
}

static void pwr_qc_cb(lv_event_t *e)
{
    modulus_power_set_quick_charge(lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED));
}

static void pwr_dim_cb(lv_event_t *e)
{
    const uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    const uint16_t sec = k_dim_vals[idx < 6 ? idx : 0];
    modulus_nvs_set_u16("dim_to", sec);
    modulus_battery_apply_display_policy();
}

static void pwr_scr_cb(lv_event_t *e)
{
    const uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    const uint16_t sec = k_scr_vals[idx < 7 ? idx : 0];
    modulus_nvs_set_u16("scr_to", sec);
    modulus_battery_apply_display_policy();
}

static void pwr_mode_cb(lv_event_t *e)
{
    const uint8_t mode = modulus_ui_segmented_get_selected(lv_event_get_target(e));
    if (mode > 1) {
        return;
    }
    modulus_nvs_set_u8("pwr_mode", mode);
    modulus_power_set_sleep_policy(mode, modulus_nvs_get_u16("pwr_dsto", 120));
    pwr_sync_deep_sleep_ui(mode == 1);
}

static void pwr_dsto_cb(lv_event_t *e)
{
    const uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    const uint16_t sec = k_ds_vals[idx < 5 ? idx : 2];
    modulus_nvs_set_u16("pwr_dsto", sec);
    modulus_power_set_sleep_policy(modulus_nvs_get_u8("pwr_mode", 0), sec);
}

static void pwr_wake_bit_cb(lv_event_t *e)
{
    const uint8_t mask = (uint8_t)(uintptr_t)lv_event_get_user_data(e);
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    uint8_t w = modulus_nvs_get_u8("pwr_wake", PWR_WAKE_TOUCH);
    if (on) {
        w |= mask;
    } else {
        w &= (uint8_t)~mask;
    }
    modulus_nvs_set_u8("pwr_wake", w);
    modulus_power_set_wake_sources(w);
    if (mask == PWR_WAKE_TIMER) {
        pwr_sync_wake_timer_ui(on);
    }
}

static void pwr_wtmin_cb(lv_event_t *e)
{
    const uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    const uint16_t min = k_wtm_vals[idx < 9 ? idx : 0];
    modulus_nvs_set_u16("pwr_wtmin", min);
    modulus_power_set_wake_timer_min(min);
}

static void pwr_warn_cb(lv_event_t *e)
{
    const uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    if (idx >= 7) {
        return;
    }
    modulus_battery_set_low_warn_pct(k_warn_vals[idx]);
}

static void pwr_bat_type_cb(lv_event_t *e)
{
    const uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    if (idx >= 5) {
        return;
    }
    modulus_battery_set_pack_type(idx);
}

static void sleep_now_cb(lv_event_t *e)
{
    (void)e;
    modulus_power_enter_deep_sleep();
}

static void power_reset_cb(void)
{
    modulus_nvs_set_u16("dim_to", 0);
    modulus_nvs_set_u16("scr_to", 0);
    modulus_battery_apply_display_policy();

    modulus_nvs_set_u8("pwr_mode", 0);
    modulus_nvs_set_u8("pwr_wake", PWR_WAKE_TOUCH);
    modulus_nvs_set_u16("pwr_dsto", 120);
    modulus_nvs_set_u16("pwr_wtmin", 0);
    modulus_nvs_set_u8("pwr_gwifi", 1);
    modulus_nvs_set_u8("pwr_gext", 1);
    modulus_nvs_set_u8("pwr_gusb", 0);
    modulus_power_set_sleep_policy(0, 120);
    modulus_power_set_wake_sources(PWR_WAKE_TOUCH);
    modulus_power_set_wake_timer_min(0);
    modulus_power_set_gate_wifi(true);
    modulus_power_set_gate_ext5v(true);
    modulus_power_set_gate_usb5v(false);

    modulus_battery_set_low_warn_pct(15);
    modulus_battery_set_pack_type(0);
    modulus_battery_set_adaptive(false);
    modulus_power_set_charge_en(true);
    modulus_power_set_quick_charge(true);
    modulus_power_set_ext5v(true);
    modulus_power_set_usb5v(false);

    modulus_ui_settings_build_power_tab();
}

void modulus_ui_settings_power_tab_stop_timer(void)
{
    pwr_panel_scroll_hook(false);
    if (s_pwr_bat_timer) {
        lv_timer_delete(s_pwr_bat_timer);
        s_pwr_bat_timer = NULL;
    }
    s_pwr_dd_dsto = NULL;
    s_pwr_dd_wtimer = NULL;
    s_pwr_gate_wifi = NULL;
    s_pwr_gate_ext = NULL;
    s_pwr_gate_usb = NULL;
    s_pwr_bat_pct_lbl = NULL;
    s_pwr_bat_state_lbl = NULL;
    s_pwr_bat_volt_lbl = NULL;
    s_pwr_bat_curr_lbl = NULL;
    s_pwr_bat_pwr_lbl = NULL;
    s_pwr_bat_temp_lbl = NULL;
    s_pwr_bat_rate_lbl = NULL;
    s_pwr_bat_eta_lbl = NULL;
    s_pwr_uptime_lbl = NULL;
    pwr_clear_bat_caches();
}

void modulus_ui_settings_power_tab_pause_activity(void)
{
    pwr_panel_scroll_hook(false);
    if (s_pwr_bat_timer) {
        lv_timer_pause(s_pwr_bat_timer);
    }
}

void modulus_ui_settings_power_tab_resume_activity(void)
{
    if (s_pwr_bat_timer) {
        pwr_panel_scroll_hook(true);
        lv_timer_resume(s_pwr_bat_timer);
        pwr_bat_timer_cb(NULL);
    }
}

void modulus_ui_settings_build_power_tab(void)
{
    lv_obj_t *p = modulus_ui_settings_tab_panel(MOD_UI_SETTINGS_TAB_POWER);
    if (!p) {
        return;
    }
    modulus_ui_settings_power_tab_stop_timer();
    lv_obj_clean(p);

    modulus_battery_status_t bat = {};
    const bool bat_ok = modulus_battery_get_status(&bat);

    settings_section(p, "Battery status", NULL);
    if (bat_ok) {
        lv_obj_t *hero = lv_obj_create(p);
        lv_obj_remove_style_all(hero);
        lv_obj_set_width(hero, lv_pct(100));
        lv_obj_set_height(hero, 48);
        lv_obj_set_flex_flow(hero, LV_FLEX_FLOW_ROW);
        lv_obj_set_flex_align(hero, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER,
                              LV_FLEX_ALIGN_CENTER);
        lv_obj_set_style_pad_hor(hero, MOD_UI_SPACE_MD, 0);

        s_pwr_bat_pct_lbl = lv_label_create(hero);
        lv_obj_set_style_text_font(s_pwr_bat_pct_lbl, MOD_UI_FONT_TITLE_L, 0);

        s_pwr_bat_state_lbl = lv_label_create(hero);
        lv_obj_set_style_text_font(s_pwr_bat_state_lbl, MOD_UI_FONT_BODY_L, 0);
        lv_obj_set_style_text_align(s_pwr_bat_state_lbl, LV_TEXT_ALIGN_RIGHT, 0);

        s_pwr_bat_volt_lbl = settings_detail_row(p, "Voltage", "-- V");
        s_pwr_bat_curr_lbl = settings_detail_row(p, "Current", "-- mA");
        s_pwr_bat_pwr_lbl = settings_detail_row(p, "Power", "-- W");
        s_pwr_bat_rate_lbl = settings_detail_row(p, "Charge rate", "--");
        s_pwr_bat_eta_lbl = settings_detail_row(p, "Time remaining", "--");
        s_pwr_bat_temp_lbl = settings_detail_row(p, "SoC temperature", "-- C");
    } else {
        settings_detail_row(p, "Battery", "INA226 unavailable");
    }
    {
        char up[32];
        modulus_rtc_format_uptime(up, sizeof(up));
        s_pwr_uptime_lbl = settings_detail_row(p, "Since boot", up);
        strncpy(s_pwr_uptime_cache, up, sizeof(s_pwr_uptime_cache) - 1);
        s_pwr_uptime_cache[sizeof(s_pwr_uptime_cache) - 1] = '\0';
    }
    pwr_bat_timer_cb(NULL);
    s_pwr_bat_timer = lv_timer_create(pwr_bat_timer_cb, 1000, NULL);
    pwr_panel_scroll_hook(true);

    settings_section(p, "Power rails", NULL);
    lv_obj_t *ext = settings_toggle_row(p, "EXT 5V output", modulus_nvs_get_u8("ext5v", 1) != 0);
    lv_obj_add_event_cb(ext, rail_ext5v_cb, LV_EVENT_VALUE_CHANGED, NULL);
    lv_obj_t *usb = settings_toggle_row(p, "USB 5V output", modulus_nvs_get_u8("usb5v", 0) != 0);
    lv_obj_add_event_cb(usb, rail_usb5v_cb, LV_EVENT_VALUE_CHANGED, NULL);

    settings_section(p, "Display sleep", NULL);
    {
        const uint16_t dim = modulus_nvs_get_u16("dim_to", 0);
        lv_obj_t *dd_dim = settings_dropdown_row(p, "Dim display after",
            "Never\n10 sec\n30 sec\n1 min\n2 min\n5 min",
            (uint16_t)pwr_find_u16_idx(k_dim_vals, 6, dim));
        lv_obj_add_event_cb(dd_dim, pwr_dim_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }
    {
        const uint16_t scr = modulus_nvs_get_u16("scr_to", 0);
        lv_obj_t *dd_scr = settings_dropdown_row(p, "Screen timeout",
            "Never\n15 sec\n30 sec\n1 min\n2 min\n5 min\n10 min",
            (uint16_t)pwr_find_u16_idx(k_scr_vals, 7, scr));
        lv_obj_add_event_cb(dd_scr, pwr_scr_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }
    settings_link_tab_row(p, "Display & Theme", "", 2);

    settings_section(p, "Actions", NULL);
    lv_obj_t *sleep_row = settings_action_row(p, "Sleep now", "Enter deep sleep");
    settings_bind_menu_click(sleep_row, sleep_now_cb, NULL);

    settings_section(p, "System sleep", NULL);
    {
        const uint8_t mode = modulus_nvs_get_u8("pwr_mode", 0);
        static const char *const k_slp[] = {"Display only", "Deep sleep"};
        lv_obj_t *dd_mode = settings_segmented_row(p, "Sleep mode", k_slp, 2,
                                                   mode > 1 ? 0 : mode, 116);
        lv_obj_add_event_cb(dd_mode, pwr_mode_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }
    {
        const uint16_t dsto = modulus_nvs_get_u16("pwr_dsto", 120);
        s_pwr_dd_dsto = settings_dropdown_row(p, "Deep sleep after",
            "30 sec\n1 min\n2 min\n5 min\n10 min",
            (uint16_t)pwr_find_closest_idx(k_ds_vals, 5, dsto, 2));
        lv_obj_add_event_cb(s_pwr_dd_dsto, pwr_dsto_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }
    {
        const uint8_t wake = modulus_nvs_get_u8("pwr_wake", PWR_WAKE_TOUCH);
        lv_obj_t *sw_touch = settings_toggle_row(p, "Wake on touch", (wake & PWR_WAKE_TOUCH) != 0);
        lv_obj_add_event_cb(sw_touch, pwr_wake_bit_cb, LV_EVENT_VALUE_CHANGED, (void *)(uintptr_t)PWR_WAKE_TOUCH);
        lv_obj_t *sw_usb = settings_toggle_row(p, "Wake on USB-C", (wake & PWR_WAKE_USB) != 0);
        lv_obj_add_event_cb(sw_usb, pwr_wake_bit_cb, LV_EVENT_VALUE_CHANGED, (void *)(uintptr_t)PWR_WAKE_USB);
        lv_obj_t *sw_timer = settings_toggle_row(p, "Wake on timer", (wake & PWR_WAKE_TIMER) != 0);
        lv_obj_add_event_cb(sw_timer, pwr_wake_bit_cb, LV_EVENT_VALUE_CHANGED, (void *)(uintptr_t)PWR_WAKE_TIMER);
    }
    {
        const uint16_t wt = modulus_nvs_get_u16("pwr_wtmin", 0);
        s_pwr_dd_wtimer = settings_dropdown_row(p, "Auto-wake timer",
            "Disabled\n5 min\n10 min\n15 min\n30 min\n1 hr\n2 hr\n4 hr\n8 hr",
            (uint16_t)pwr_find_closest_idx(k_wtm_vals, 9, wt, 0));
        lv_obj_add_event_cb(s_pwr_dd_wtimer, pwr_wtmin_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }
    s_pwr_gate_wifi = settings_toggle_row(p, "Gate Wi-Fi in sleep",
                                          modulus_nvs_get_u8("pwr_gwifi", 1) != 0);
    lv_obj_add_event_cb(s_pwr_gate_wifi, pwr_gate_wifi_cb, LV_EVENT_VALUE_CHANGED, NULL);
    s_pwr_gate_ext = settings_toggle_row(p, "Gate EXT 5V in sleep",
                                         modulus_nvs_get_u8("pwr_gext", 1) != 0);
    lv_obj_add_event_cb(s_pwr_gate_ext, pwr_gate_ext_cb, LV_EVENT_VALUE_CHANGED, NULL);
    s_pwr_gate_usb = settings_toggle_row(p, "Gate USB 5V in sleep",
                                         modulus_nvs_get_u8("pwr_gusb", 0) != 0);
    lv_obj_add_event_cb(s_pwr_gate_usb, pwr_gate_usb_cb, LV_EVENT_VALUE_CHANGED, NULL);

    pwr_sync_deep_sleep_ui(modulus_nvs_get_u8("pwr_mode", 0) == 1);
    pwr_sync_wake_timer_ui((modulus_nvs_get_u8("pwr_wake", PWR_WAKE_TOUCH) & PWR_WAKE_TIMER) != 0);

    settings_section(p, "Battery behavior", NULL);
    {
        const uint8_t pack = modulus_battery_get_pack_type();
        lv_obj_t *dd_pack = settings_dropdown_row(p, "Battery pack",
            "F550 (2200 mAh)\nF550 3500 mAh\nF750\nF950\nF970",
            pack > 4 ? 0 : pack);
        lv_obj_add_event_cb(dd_pack, pwr_bat_type_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }
    {
        const uint8_t warn = modulus_nvs_get_u8("bat_warn", 15);
        uint8_t warn_idx = 3;
        for (uint8_t i = 0; i < 7; i++) {
            if (k_warn_vals[i] == warn) {
                warn_idx = i;
                break;
            }
        }
        lv_obj_t *dd_warn = settings_dropdown_row(p, "Warn at",
            "Off\n5%\n10%\n15%\n20%\n25%\n30%", warn_idx);
        lv_obj_add_event_cb(dd_warn, pwr_warn_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }
    lv_obj_t *chg = settings_toggle_row(p, "Charging enabled", modulus_nvs_get_u8("chg_en", 1) != 0);
    lv_obj_add_event_cb(chg, chg_en_cb, LV_EVENT_VALUE_CHANGED, NULL);
    lv_obj_t *adapt = settings_toggle_row(p, "Adaptive battery",
                                          modulus_nvs_get_u8("bat_adapt", 0) != 0);
    lv_obj_add_event_cb(adapt, pwr_adapt_cb, LV_EVENT_VALUE_CHANGED, NULL);
    lv_obj_t *qc = settings_toggle_row(p, "Quick charge (QC 2.0/3)",
                                       modulus_nvs_get_u8("qc", 1) != 0);
    lv_obj_add_event_cb(qc, pwr_qc_cb, LV_EVENT_VALUE_CHANGED, NULL);

    settings_expandable_link(p, "Show battery reference", "Hide battery reference",
                             &s_batt_ref_exp, modulus_ui_settings_build_power_tab);
    if (s_batt_ref_exp) {
        settings_detail_row(p, "Compatible packs", "NP-F330 / F530 / F550 / F750 / F770 / F960 / F970");
        settings_detail_row(p, "Percent source", "Voltage curve (not mAh)");
        settings_detail_row(p, "Chemistry", "Li-ion 2S (7.2V nominal)");
        settings_detail_row(p, "Voltage range", "6.0V empty - 8.4V full");
        settings_detail_row(p, "Charge IC", "IP2326");
        settings_detail_row(p, "Monitor", "INA226 (0x41)");
        settings_detail_row(p, "Adaptive battery",
                            "Tightens dim/screen timeout on battery (<=50% / <=20%)");
        settings_detail_row(p, "SoC temperature", "ESP32-P4 die (not pack thermistor)");
    }

    static settings_reset_ctx_t reset_ctx = {
        .title = "Reset power defaults?",
        .body = "Restores display sleep, system sleep, rails, and battery behavior.",
        .fn = power_reset_cb,
    };
    settings_reset_row(p, "Reset power settings", &reset_ctx);
    modulus_ui_settings_note_tab_built(MOD_UI_SETTINGS_TAB_POWER);
}
