#include "ui_settings_priv.h"
#include "ui_settings_common.h"
#include "ui_settings_time.h"
#include "cnc_cmd_exports.h"
#include "modulus_zig.h"
#include "nvs_shim.h"
#include "power_shim.h"
#include "rtc_shim.h"
#include "i18n_shim.h"
#include "battery_shim.h"
#include "storage_shim.h"
#include "wireless_shim.h"
#include "c6_sdio_host.h"

#include <esp_heap_caps.h>
#include <esp_idf_version.h>
#include <esp_log.h>
#include <esp_system.h>

#include "sdkconfig.h"
#include <stdio.h>
#include <string.h>

static const char *TAG = "settings";

static void refresh_clock_labels(void);

static void dd_persist_u8_cb(lv_event_t *e)
{
    /* datefmt is the only user - now a segmented row */
    const char *key = lv_event_get_user_data(e);
    modulus_nvs_set_u8(key, modulus_ui_segmented_get_selected(lv_event_get_target(e)));
    refresh_clock_labels();
}

static void toggle_nvs_u8_cb(lv_event_t *e)
{
    const char *key = lv_event_get_user_data(e);
    modulus_nvs_set_u8(key, lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED) ? 1 : 0);
}

static void tz_changed_cb(lv_event_t *e)
{
    (void)e;
    modulus_rtc_tz_changed((uint8_t)lv_dropdown_get_selected(lv_event_get_target(e)));
    refresh_clock_labels();
}

static void t24h_cb(lv_event_t *e)
{
    const uint8_t idx = modulus_ui_segmented_get_selected(lv_event_get_target(e));
    modulus_nvs_set_u8("t_24h", idx == 0 ? 1 : 0);
    refresh_clock_labels();
}

static modulus_lang_t s_pending_lang = MOD_LANG_EN;

static void lang_apply_cb(void)
{
    modulus_i18n_set_lang(s_pending_lang, true);
    /* Confirm promises refresh screens — reuse theme path (dirty tabs + rebuild active). */
    modulus_ui_settings_theme_refresh();
}

static void lang_cancel_cb(void)
{
    s_pending_lang = modulus_i18n_current();
}

static void lang_changed_cb(lv_event_t *e)
{
    lv_obj_t *dd = lv_event_get_target(e);
    const uint16_t sel = (uint16_t)lv_dropdown_get_selected(dd);
    if (sel >= MOD_LANG_COUNT) {
        lv_dropdown_set_selected(dd, (uint16_t)modulus_i18n_current());
        return;
    }
    const modulus_lang_t chosen = (modulus_lang_t)sel;
    if (chosen == modulus_i18n_current()) {
        return;
    }
    s_pending_lang = chosen;
    lv_dropdown_set_selected(dd, (uint16_t)modulus_i18n_current());
    settings_confirm_show(
        modulus_i18n_tr(MOD_I18N_LANGUAGE_CHANGED),
        modulus_i18n_tr(MOD_I18N_APPLY_LANGUAGE),
        modulus_i18n_tr(MOD_I18N_APPLY),
        false,
        lang_apply_cb,
        lang_cancel_cb);
}

static bool s_dev_ref_exp = false;

static lv_timer_t *s_sys_timer = NULL;

static void sys_panel_scroll_cb(lv_event_t *e);
static void sys_panel_scroll_hook(bool attach);
static lv_obj_t *s_time_lbl = NULL;
static lv_obj_t *s_date_lbl = NULL;
static lv_obj_t *s_uptime_lbl = NULL;
static lv_obj_t *s_ntp_lbl = NULL;
static lv_obj_t *s_manual_row = NULL;
static lv_obj_t *s_heap_lbl = NULL;
static lv_obj_t *s_health_lbl[5] = {};
static int s_health_kind[5] = {SETTINGS_STATUS_DIM, SETTINGS_STATUS_DIM, SETTINGS_STATUS_DIM,
                               SETTINGS_STATUS_DIM, SETTINGS_STATUS_DIM};

static char s_time_buf[32];
static char s_date_buf[32];
static char s_uptime_buf[32];
static char s_heap_buf[32];
static char s_time_cache[32] = "";
static char s_date_cache[32] = "";
static char s_uptime_cache[32] = "";
static char s_ntp_cache[32] = "";
static char s_heap_cache[32] = "";
static char s_health_cache[5][12] = {};

static void sys_health_chip_cb(lv_event_t *e)
{
    const int tab = (int)(intptr_t)lv_event_get_user_data(e);
    if (tab >= 0) {
        modulus_ui_settings_select_tab(tab);
    }
}

static int sys_health_cnc_kind(void)
{
    const uint8_t nvs_conn = modulus_nvs_get_u8("cnc_conn", 4);
    const uint8_t active = modulus_zig_active_transport();
    if (active == 0xFF) {
        return SETTINGS_STATUS_ERR;
    }
    if (active == nvs_conn) {
        return SETTINGS_STATUS_OK;
    }
    return SETTINGS_STATUS_WARN;
}

static void sys_health_refresh(void)
{
    static const char *const k_ok[] = {"C6", "Wi-Fi", "CNC", "SD", "Batt"};
    static const char *const k_bad[] = {"C6!", "Wi-Fi", "CNC", "SD", "Batt!"};
    int kinds[5];
    kinds[0] = (modulus_c6_sdio_ready() && modulus_wireless_ready()) ? SETTINGS_STATUS_OK
                                                                     : SETTINGS_STATUS_ERR;
    if (modulus_wireless_wifi_is_connected()) {
        kinds[1] = SETTINGS_STATUS_OK;
    } else if (modulus_wireless_ready()) {
        kinds[1] = SETTINGS_STATUS_WARN;
    } else {
        kinds[1] = SETTINGS_STATUS_ERR;
    }
    kinds[2] = sys_health_cnc_kind();
    kinds[3] = modulus_storage_is_mounted() ? SETTINGS_STATUS_OK : SETTINGS_STATUS_WARN;
    {
        modulus_battery_status_t bat = {};
        if (!modulus_battery_get_status(&bat) || bat.charge_state == 3) {
            kinds[4] = SETTINGS_STATUS_WARN;
        } else if (modulus_battery_is_low_warn(&bat)) {
            kinds[4] = SETTINGS_STATUS_ERR;
        } else {
            kinds[4] = SETTINGS_STATUS_OK;
        }
    }
    for (int i = 0; i < 5; i++) {
        if (!s_health_lbl[i]) {
            continue;
        }
        const char *txt = (kinds[i] == SETTINGS_STATUS_ERR) ? k_bad[i] : k_ok[i];
        if (s_health_cache[i][0] != '\0' && strcmp(s_health_cache[i], txt) == 0 &&
            s_health_kind[i] == kinds[i]) {
            continue;
        }
        lv_label_set_text(s_health_lbl[i], txt);
        lv_color_t fg = modulus_settings_status_color(kinds[i]);
        if (kinds[i] == SETTINGS_STATUS_ERR) {
            fg = modulus_ui_color_on_error_container();
        }
        lv_obj_set_style_text_color(s_health_lbl[i], fg, 0);
        lv_obj_t *chip = lv_obj_get_parent(s_health_lbl[i]);
        if (chip) {
            lv_color_t bg = modulus_ui_color_surface_container_high();
            if (kinds[i] == SETTINGS_STATUS_OK) {
                bg = modulus_ui_color_secondary_container();
            } else if (kinds[i] == SETTINGS_STATUS_ERR) {
                bg = modulus_ui_color_error_container();
            }
            lv_obj_set_style_bg_color(chip, bg, 0);
            if (kinds[i] == SETTINGS_STATUS_DIM) {
                lv_obj_set_style_border_width(chip, 1, 0);
                lv_obj_set_style_border_color(chip, modulus_ui_color_outline_variant(), 0);
            } else {
                lv_obj_set_style_border_width(chip, 0, 0);
            }
        }
        strncpy(s_health_cache[i], txt, sizeof(s_health_cache[i]) - 1);
        s_health_cache[i][sizeof(s_health_cache[i]) - 1] = '\0';
        s_health_kind[i] = kinds[i];
    }
}

static void sys_build_health_strip(lv_obj_t *p)
{
    settings_section(p, "Health", "Tap a chip to open related settings.");
    lv_obj_t *row = lv_obj_create(p);
    lv_obj_remove_style_all(row);
    lv_obj_set_width(row, lv_pct(100));
    lv_obj_set_height(row, 52);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_hor(row, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_pad_column(row, MOD_UI_SPACE_XS + MOD_UI_SPACE_XS / 2, 0);
    settings_no_scroll(row);

    static const char *const k_lbl[] = {"C6", "Wi-Fi", "CNC", "SD", "Batt"};
    static const int k_tabs[] = {
        MOD_UI_SETTINGS_TAB_WIRELESS, MOD_UI_SETTINGS_TAB_WIRELESS, MOD_UI_SETTINGS_TAB_CNC,
        MOD_UI_SETTINGS_TAB_STORAGE,  MOD_UI_SETTINGS_TAB_POWER,
    };
    for (int i = 0; i < 5; i++) {
        lv_obj_t *chip = lv_button_create(row);
        lv_obj_remove_style_all(chip);
        lv_obj_set_flex_grow(chip, 1);
        lv_obj_set_height(chip, 48);
        lv_obj_set_style_radius(chip, MOD_UI_SHAPE_FULL, 0);
        lv_obj_set_style_bg_opa(chip, LV_OPA_COVER, 0);
        lv_obj_set_style_bg_color(chip, modulus_ui_color_surface_container_high(), 0);
        lv_obj_set_style_border_width(chip, 1, 0);
        lv_obj_set_style_border_color(chip, modulus_ui_color_outline_variant(), 0);
        modulus_ui_apply_pressed_state_layer(chip);
        settings_bind_menu_click(chip, sys_health_chip_cb, (void *)(intptr_t)k_tabs[i]);
        modulus_ui_touch_ensure_min(chip);
        s_health_lbl[i] = lv_label_create(chip);
        lv_label_set_text(s_health_lbl[i], k_lbl[i]);
        lv_obj_set_style_text_font(s_health_lbl[i], MOD_UI_FONT_LABEL_M, 0);
        lv_obj_center(s_health_lbl[i]);
        s_health_cache[i][0] = '\0';
        s_health_kind[i] = SETTINGS_STATUS_DIM;
    }
    sys_health_refresh();
}

static void sys_set_lbl_if_changed(lv_obj_t *lbl, const char *text, char *cache, size_t cache_sz)
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

static void sync_manual_row(bool ntp_on)
{
    if (!s_manual_row) {
        return;
    }
    modulus_ui_row_set_content_enabled(s_manual_row, !ntp_on);
}

static void refresh_clock_labels(void)
{
    if (s_time_lbl) {
        modulus_rtc_format_time(s_time_buf, sizeof(s_time_buf));
        sys_set_lbl_if_changed(s_time_lbl, s_time_buf, s_time_cache, sizeof(s_time_cache));
    }
    if (s_date_lbl) {
        modulus_rtc_format_date(s_date_buf, sizeof(s_date_buf));
        sys_set_lbl_if_changed(s_date_lbl, s_date_buf, s_date_cache, sizeof(s_date_cache));
    }
    if (s_uptime_lbl) {
        modulus_rtc_format_uptime(s_uptime_buf, sizeof(s_uptime_buf));
        sys_set_lbl_if_changed(s_uptime_lbl, s_uptime_buf, s_uptime_cache, sizeof(s_uptime_cache));
    }
    if (s_ntp_lbl) {
        sys_set_lbl_if_changed(s_ntp_lbl, modulus_rtc_ntp_status_text(), s_ntp_cache,
                               sizeof(s_ntp_cache));
    }
    if (s_heap_lbl) {
        snprintf(s_heap_buf, sizeof(s_heap_buf), "%lu KB PSRAM free",
                 (unsigned long)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024));
        sys_set_lbl_if_changed(s_heap_lbl, s_heap_buf, s_heap_cache, sizeof(s_heap_cache));
    }
    sys_health_refresh();
}

void modulus_ui_settings_system_tab_refresh(void)
{
    refresh_clock_labels();
}

static void sys_timer_cb(lv_timer_t *timer)
{
    (void)timer;
    refresh_clock_labels();
}

void modulus_ui_settings_system_tab_stop_timer(void)
{
    sys_panel_scroll_hook(false);
    if (s_sys_timer) {
        lv_timer_delete(s_sys_timer);
        s_sys_timer = NULL;
    }
    s_time_lbl = NULL;
    s_date_lbl = NULL;
    s_uptime_lbl = NULL;
    s_ntp_lbl = NULL;
    s_manual_row = NULL;
    s_heap_lbl = NULL;
    for (int i = 0; i < 5; i++) {
        s_health_lbl[i] = NULL;
        s_health_cache[i][0] = '\0';
        s_health_kind[i] = SETTINGS_STATUS_DIM;
    }
    s_time_cache[0] = '\0';
    s_date_cache[0] = '\0';
    s_uptime_cache[0] = '\0';
    s_ntp_cache[0] = '\0';
    s_heap_cache[0] = '\0';
    settings_time_modal_hide();
}

void modulus_ui_settings_system_tab_pause_activity(void)
{
    sys_panel_scroll_hook(false);
    if (s_sys_timer) {
        lv_timer_pause(s_sys_timer);
    }
    settings_time_modal_hide();
}

void modulus_ui_settings_system_tab_resume_activity(void)
{
    if (s_sys_timer) {
        sys_panel_scroll_hook(true);
        lv_timer_resume(s_sys_timer);
        refresh_clock_labels();
    }
}

static void sys_panel_scroll_cb(lv_event_t *e)
{
    if (!s_sys_timer) {
        return;
    }
    const lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_SCROLL_BEGIN) {
        lv_timer_pause(s_sys_timer);
        return;
    }
    if (code == LV_EVENT_SCROLL_END) {
        lv_timer_resume(s_sys_timer);
        refresh_clock_labels();
    }
}

static void sys_panel_scroll_hook(bool attach)
{
    lv_obj_t *panel = modulus_ui_settings_tab_panel(MOD_UI_SETTINGS_TAB_SYSTEM);
    if (!panel) {
        return;
    }
    lv_obj_remove_event_cb(panel, sys_panel_scroll_cb);
    if (attach) {
        lv_obj_add_event_cb(panel, sys_panel_scroll_cb, LV_EVENT_SCROLL_BEGIN, NULL);
        lv_obj_add_event_cb(panel, sys_panel_scroll_cb, LV_EVENT_SCROLL_END, NULL);
    }
}

static void do_restart(void) { esp_restart(); }

static void restart_cb(lv_event_t *e)
{
    (void)e;
    settings_confirm_show("Restart?", "Device reboots now.", "Restart", false, do_restart, NULL);
}

static void do_shutdown(void) { modulus_power_shutdown(); }

static void shutdown_cb(lv_event_t *e)
{
    (void)e;
    settings_confirm_show("Shut down?", "Powers off. Press power to wake.", "Shut down", true,
                          do_shutdown, NULL);
}

static void paint_screen_black(void)
{
    lv_obj_t *scr = lv_screen_active();
    lv_obj_clean(scr);
    lv_obj_set_style_bg_color(scr, modulus_ui_color_surface_dim(), 0);
    lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);
    lv_obj_invalidate(scr);
    lv_refr_now(NULL);
}

static void do_factory_reset(void)
{
    modulus_zig_cmd_feed_hold();
    const int err = modulus_zig_factory_reset();
    if (err != 0) {
        ESP_LOGE(TAG, "factory reset failed: %d", err);
        return;
    }
    paint_screen_black();
    esp_restart();
}

static void factory_cb(lv_event_t *e)
{
    (void)e;
    settings_confirm_show("Factory reset?", "Erases all settings. Cannot undo.", "Erase & reset",
                          true, do_factory_reset, NULL);
}

static void ntp_toggle_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    modulus_rtc_ntp_set_enabled(on);
    sync_manual_row(on);
    refresh_clock_labels();
}

static void sync_now_cb(lv_event_t *e)
{
    (void)e;
    (void)modulus_rtc_ntp_sync_now();
    refresh_clock_labels();
}

static void manual_time_cb(lv_event_t *e)
{
    (void)e;
    settings_time_modal_show();
}

static void build_device_card(lv_obj_t *p)
{
    lv_obj_t *card = lv_obj_create(p);
    lv_obj_remove_style_all(card);
    lv_obj_set_width(card, lv_pct(100));
    lv_obj_set_height(card, LV_SIZE_CONTENT);
    lv_obj_set_style_bg_color(card, modulus_ui_color_surface_container_highest(), 0);
    lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(card, MOD_UI_SHAPE_MD, 0);
    lv_obj_set_style_border_color(card, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_border_width(card, 1, 0);
    lv_obj_set_style_pad_all(card, MOD_UI_SPACE_MD, 0);
    lv_obj_set_style_pad_column(card, MOD_UI_SPACE_MD, 0);
    lv_obj_set_flex_flow(card, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(card, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);

    lv_obj_t *rail = lv_obj_create(card);
    lv_obj_remove_style_all(rail);
    lv_obj_set_size(rail, 4, 64);
    lv_obj_set_style_bg_color(rail, modulus_ui_color_primary(), 0);
    lv_obj_set_style_bg_opa(rail, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(rail, MOD_UI_SHAPE_FULL, 0);

    lv_obj_t *tile = lv_obj_create(card);
    lv_obj_remove_style_all(tile);
    lv_obj_set_size(tile, 64, 64);
    lv_obj_set_style_bg_color(tile, modulus_ui_color_primary_container(), 0);
    lv_obj_set_style_bg_opa(tile, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(tile, MOD_UI_SHAPE_MD, 0);
    lv_obj_t *ic = modulus_ui_icon_create(tile, MOD_UI_ICON_CNC, MOD_UI_ICON_SZ_32);
    modulus_ui_icon_recolor(ic, modulus_ui_color_on_primary_container());
    lv_obj_center(ic);

    lv_obj_t *col = lv_obj_create(card);
    lv_obj_remove_style_all(col);
    lv_obj_set_flex_grow(col, 1);
    lv_obj_set_height(col, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(col, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(col, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_START);
    lv_obj_set_style_pad_row(col, 2, 0);

    lv_obj_t *nm = lv_label_create(col);
    lv_label_set_text(nm, "Modulus OS");
    lv_obj_set_style_text_color(nm, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_font(nm, MOD_UI_FONT_TITLE_M, 0);

    lv_obj_t *sub = lv_label_create(col);
    lv_label_set_text(sub, "M5Stack Tab5 | ESP32-P4 + C6");
    lv_obj_set_style_text_color(sub, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(sub, MOD_UI_FONT_BODY_M, 0);

    lv_obj_t *cred = lv_label_create(col);
    lv_label_set_text(cred, "Hardware by M5Stack");
    lv_obj_set_style_text_color(cred, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(cred, MOD_UI_FONT_LABEL_M, 0);

    lv_obj_t *pill = lv_obj_create(card);
    lv_obj_remove_style_all(pill);
    lv_obj_set_size(pill, LV_SIZE_CONTENT, 32);
    lv_obj_set_style_bg_color(pill, modulus_ui_color_secondary_container(), 0);
    lv_obj_set_style_bg_opa(pill, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(pill, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_pad_hor(pill, MOD_UI_SPACE_SM + MOD_UI_SPACE_XS, 0);
    lv_obj_set_style_pad_ver(pill, MOD_UI_SPACE_XS + MOD_UI_SPACE_XS / 2, 0);
    lv_obj_t *pv = lv_label_create(pill);
    char ver[24];
    snprintf(ver, sizeof(ver), "v%s", modulus_zig_version());
    lv_label_set_text(pv, ver);
    lv_obj_set_style_text_color(pv, modulus_ui_color_on_secondary_container(), 0);
    lv_obj_set_style_text_font(pv, MOD_UI_FONT_LABEL_L, 0);
    lv_obj_center(pv);
}

void modulus_ui_settings_build_system_tab(void)
{
    lv_obj_t *p = modulus_ui_settings_tab_panel(MOD_UI_SETTINGS_TAB_SYSTEM);
    if (!p) {
        return;
    }

    modulus_ui_settings_system_tab_stop_timer();
    lv_obj_clean(p);

    sys_build_health_strip(p);

    settings_section(p, "Device", "Hardware and firmware.");
    build_device_card(p);
    char fw[48];
    snprintf(fw, sizeof(fw), "Modulus v%s", modulus_zig_version());
    settings_detail_row(p, "Firmware", fw);
    settings_detail_row(p, "ESP-IDF", esp_get_idf_version());
    settings_detail_row(p, "Zig", modulus_zig_toolchain_version());
    {
        char lvgl[16];
        snprintf(lvgl, sizeof(lvgl), "%d.%d.%d", CONFIG_LVGL_VERSION_MAJOR,
                 CONFIG_LVGL_VERSION_MINOR, CONFIG_LVGL_VERSION_PATCH);
        settings_detail_row(p, "LVGL", lvgl);
    }
    settings_detail_row(p, "Platform", "ESP32-P4 + C6 | M5Stack Tab5");
    settings_detail_row(p, "Theme contrast",
                        modulus_ui_theme_contrast_ok() ? "AA pass (WCAG 4.5:1)" : "FAIL - check log");

    settings_section(p, "Language & region", NULL);
    {
        static char lang_opts[128];
        modulus_i18n_build_lang_options(lang_opts, sizeof(lang_opts));
        lv_obj_t *lang = settings_dropdown_row(p, modulus_i18n_tr(MOD_I18N_LANGUAGE),
                                                 lang_opts,
                                                 (uint8_t)modulus_i18n_current());
        lv_obj_add_event_cb(lang, lang_changed_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }
    lv_obj_t *tz = settings_dropdown_row(p, "Time zone",
        "UTC\nUTC-8 Pacific\nUTC-5 Eastern\nUTC+0 London\nUTC+1 Berlin\nUTC+8 China",
        modulus_nvs_get_u8("tz_idx", 0));
    lv_obj_add_event_cb(tz, tz_changed_cb, LV_EVENT_VALUE_CHANGED, NULL);
    static const char *const k_clk[] = {"24-hour", "12-hour"};
    lv_obj_t *clk = settings_segmented_row(p, "Time format", k_clk, 2,
                                           modulus_nvs_get_u8("t_24h", 1) ? 0 : 1, 96);
    lv_obj_add_event_cb(clk, t24h_cb, LV_EVENT_VALUE_CHANGED, NULL);
    static const char *const k_dfmt[] = {"YYYY-MM-DD", "MM/DD/YYYY", "DD/MM/YYYY"};
    lv_obj_t *df = settings_segmented_row(p, "Date format", k_dfmt, 3,
                                          modulus_nvs_get_u8("datefmt", 0), 112);
    lv_obj_add_event_cb(df, dd_persist_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"datefmt");
    lv_obj_t *kb = settings_toggle_row(p, "Full-screen keyboard",
                                       modulus_nvs_get_u8("kb_full", 1) != 0);
    lv_obj_add_event_cb(kb, toggle_nvs_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"kb_full");

    settings_section(p, "Date & time", NULL);
    modulus_rtc_format_time(s_time_buf, sizeof(s_time_buf));
    s_time_lbl = settings_detail_row(p, "Current time", s_time_buf);
    strncpy(s_time_cache, s_time_buf, sizeof(s_time_cache) - 1);
    s_time_cache[sizeof(s_time_cache) - 1] = '\0';
    modulus_rtc_format_date(s_date_buf, sizeof(s_date_buf));
    s_date_lbl = settings_detail_row(p, "Current date", s_date_buf);
    strncpy(s_date_cache, s_date_buf, sizeof(s_date_cache) - 1);
    s_date_cache[sizeof(s_date_cache) - 1] = '\0';

    const bool ntp_on = modulus_nvs_get_u8("ntp", 1) != 0;
    lv_obj_t *ntp = settings_toggle_row(p, "NTP sync", ntp_on);
    lv_obj_add_event_cb(ntp, ntp_toggle_cb, LV_EVENT_VALUE_CHANGED, NULL);
    s_ntp_lbl = settings_detail_row(p, "NTP status", modulus_rtc_ntp_status_text());
    strncpy(s_ntp_cache, lv_label_get_text(s_ntp_lbl), sizeof(s_ntp_cache) - 1);
    s_ntp_cache[sizeof(s_ntp_cache) - 1] = '\0';

    lv_obj_t *sync_row = settings_action_row(p, "Sync now", "NTP");
    settings_bind_menu_click(sync_row, sync_now_cb, NULL);

    s_manual_row = settings_action_row(p, "Set date/time manually", "Manual");
    settings_bind_menu_click(s_manual_row, manual_time_cb, NULL);
    sync_manual_row(ntp_on);

    settings_section(p, "System actions", NULL);
    modulus_rtc_format_uptime(s_uptime_buf, sizeof(s_uptime_buf));
    s_uptime_lbl = settings_detail_row(p, "Since boot", s_uptime_buf);
    strncpy(s_uptime_cache, s_uptime_buf, sizeof(s_uptime_cache) - 1);
    s_uptime_cache[sizeof(s_uptime_cache) - 1] = '\0';
    lv_obj_t *rst = settings_action_row(p, "Restart device", "");
    settings_bind_menu_click(rst, restart_cb, NULL);
    lv_obj_t *sdn = settings_destructive_row(p, "Shutdown device", "");
    settings_bind_menu_click(sdn, shutdown_cb, NULL);
    lv_obj_t *fac = settings_destructive_row(p, "Factory reset", "");
    settings_bind_menu_click(fac, factory_cb, NULL);

    settings_link_tab_row(p, "Storage & Diagnostics", "", 8);

    settings_section(p, "Firmware update", "Host OTA not available yet.");
    settings_not_implemented_row(p, "Check for updates", modulus_zig_ota_status_text());
    settings_not_implemented_row(p, "Auto-update", "Not implemented");

    settings_expandable_link(p, "Show device reference", "Hide device reference",
                             &s_dev_ref_exp, modulus_ui_settings_build_system_tab);
    if (s_dev_ref_exp) {
        settings_detail_row(p, "Host", "ESP32-P4 RISC-V 360 MHz");
        settings_detail_row(p, "Display", "ST7123 1280x720 DSI");
        settings_detail_row(p, "RTC",
                            modulus_rtc_is_ready() ? "RX8130CE @ 0x32 ready" : "Not detected");
        char abi[32];
        snprintf(abi, sizeof(abi), "ABI epoch %lu", (unsigned long)modulus_zig_abi_epoch());
        settings_detail_row(p, "ABI", abi);
    }

    settings_section(p, "Runtime", NULL);
    snprintf(s_heap_buf, sizeof(s_heap_buf), "%lu KB PSRAM free",
             (unsigned long)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024));
    s_heap_lbl = settings_detail_row(p, "Memory", s_heap_buf);
    strncpy(s_heap_cache, s_heap_buf, sizeof(s_heap_cache) - 1);
    s_heap_cache[sizeof(s_heap_cache) - 1] = '\0';

    s_sys_timer = lv_timer_create(sys_timer_cb, 1000, NULL);
    sys_panel_scroll_hook(true);
    modulus_ui_settings_note_tab_built(MOD_UI_SETTINGS_TAB_SYSTEM);
}
