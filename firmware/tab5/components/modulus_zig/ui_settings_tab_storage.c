#include "ui_settings_priv.h"
#include "ui_settings_common.h"
#include "ui_settings_modals.h"
#include "ui_internal.h"
#include "ui_touch_sound.h"
#include "audio_shim.h"
#include "storage_shim.h"
#include "mbus_shim.h"
#include "i2c_scan_shim.h"
#include "tab5_port_map.h"
#include "nvs_shim.h"
#include "cnc_cmd_exports.h"

#include <esp_log.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static bool s_storage_i2c_exp = false;
static bool s_storage_i2c_ref_exp = false;
static bool s_storage_portmap_exp = false;
static lv_obj_t *s_stor_i2c_stat_lbl = NULL;
static lv_obj_t *s_stor_i2c_port_lbl = NULL;
static lv_obj_t *s_stor_i2c_mbus_lbl = NULL;
static lv_obj_t *s_stor_i2c_exp1_lbl = NULL;
static lv_obj_t *s_stor_i2c_exp2_lbl = NULL;
static char s_stor_i2c_stat_cache[32] = "Idle";
static char s_stor_i2c_port_cache[192] = "Not scanned";
static char s_stor_i2c_mbus_cache[192] = "Not scanned";
static char s_stor_i2c_exp1_cache[64] = "Not scanned";
static char s_stor_i2c_exp2_cache[64] = "Not scanned";
static int s_stor_i2c_stat_color = -1;

static void stor_i2c_refresh_labels(void);
static void stor_i2c_refresh_status_color(void);

static void stor_i2c_refresh_labels(void)
{
    modulus_ui_label_set_text_cached(s_stor_i2c_stat_lbl, s_stor_i2c_stat_cache,
                                     sizeof(s_stor_i2c_stat_cache),
                                     modulus_i2c_scan_status_text());
    modulus_ui_label_set_text_cached(s_stor_i2c_port_lbl, s_stor_i2c_port_cache,
                                     sizeof(s_stor_i2c_port_cache),
                                     modulus_i2c_scan_port_a_text());
    modulus_ui_label_set_text_cached(s_stor_i2c_mbus_lbl, s_stor_i2c_mbus_cache,
                                     sizeof(s_stor_i2c_mbus_cache),
                                     modulus_i2c_scan_mbus_text());
    modulus_ui_label_set_text_cached(s_stor_i2c_exp1_lbl, s_stor_i2c_exp1_cache,
                                     sizeof(s_stor_i2c_exp1_cache),
                                     modulus_i2c_scan_exp1_text());
    modulus_ui_label_set_text_cached(s_stor_i2c_exp2_lbl, s_stor_i2c_exp2_cache,
                                     sizeof(s_stor_i2c_exp2_cache),
                                     modulus_i2c_scan_exp2_text());
}

static void stor_i2c_scan_cb(lv_event_t *e)
{
    const modulus_i2c_scan_target_t target =
        (modulus_i2c_scan_target_t)(uintptr_t)lv_event_get_user_data(e);
    modulus_audio_play_ui(0);
    if (modulus_i2c_scan_start(target)) {
        stor_i2c_refresh_labels();
        stor_i2c_refresh_status_color();
    }
}
static bool s_storage_ref_exp = false;

static lv_timer_t *s_stor_timer = NULL;
static bool s_stor_scrolling = false;
static bool s_stor_rebuild_pending = false;

static void stor_build_tab_now(void);
static void stor_request_rebuild(void);
static void stor_panel_scroll_cb(lv_event_t *e);
static void stor_panel_scroll_hook(bool attach);
static lv_obj_t *s_stor_int_lbl = NULL;
static lv_obj_t *s_stor_ps_lbl = NULL;
static lv_obj_t *s_stor_lv_lbl = NULL;
static lv_obj_t *s_stor_min_lbl = NULL;
static lv_obj_t *s_stor_sd_lbl = NULL;
static lv_obj_t *s_stor_sd_free_lbl = NULL;
static lv_obj_t *s_stor_sd_act_val = NULL;
static lv_obj_t *s_stor_export_row = NULL;
static lv_obj_t *s_stor_export_val = NULL;
static lv_obj_t *s_stor_usb_lbl = NULL;

static char s_stor_int_cache[96] = "";
static char s_stor_ps_cache[96] = "";
static char s_stor_lv_cache[80] = "";
static char s_stor_min_cache[24] = "";
static char s_stor_sd_st_cache[16] = "";
static char s_stor_sd_free_cache[64] = "";
static char s_stor_sd_act_cache[8] = "";
static char s_stor_export_val_cache[48] = "";
static char s_stor_usb_cache[32] = "";
static char s_stor_usb_vbus_cache[24] = "";
static int s_stor_int_color = -1;
static int s_stor_ps_color = -1;
static int s_stor_lv_color = -1;
static int s_stor_sd_color = -1;
static int s_stor_usb_color = -1;
static int s_stor_usb_vbus_color = -1;
static int8_t s_stor_export_enabled = -1;

static const char *const k_loglvl_strs[] = {
    "None", "Error", "Warn", "Info", "Debug", "Verbose",
};
/* Compact MD3 segmented (6 levels; Abbrev fits tab width). */
static const char *const k_loglvl_seg[] = {
    "Off", "Err", "Warn", "Info", "Dbg", "Verb",
};

static lv_obj_t *s_stor_usb_vbus_lbl = NULL;
static uint32_t s_stor_export_flash_start = 0; /* 0 = idle; else lv_tick start of flash */

static void stor_set_lbl_if_changed(lv_obj_t *lbl, const char *text, char *cache, size_t cache_len)
{
    if (!lbl || !text || !cache) {
        return;
    }
    if (cache[0] != '\0' && strcmp(cache, text) == 0) {
        return;
    }
    lv_label_set_text(lbl, text);
    strncpy(cache, text, cache_len - 1);
    cache[cache_len - 1] = '\0';
}

static void stor_set_action_enabled(lv_obj_t *row, bool enabled)
{
    modulus_ui_obj_set_disabled_style(row, enabled);
}

static void stor_set_value_color(lv_obj_t *lbl, int kind)
{
    if (!lbl) {
        return;
    }
    lv_obj_set_style_text_color(lbl, modulus_settings_status_color(kind), 0);
}

static void stor_fmt_bytes(char *buf, size_t len, size_t bytes)
{
    if (bytes >= (1024ULL * 1024 * 1024)) {
        snprintf(buf, len, "%.1f GB", (double)bytes / (1024.0 * 1024.0 * 1024.0));
    } else if (bytes >= (1024ULL * 1024)) {
        snprintf(buf, len, "%.0f MB", (double)bytes / (1024.0 * 1024.0));
    } else if (bytes >= 1024) {
        snprintf(buf, len, "%lu KB", (unsigned long)(bytes / 1024));
    } else {
        snprintf(buf, len, "%lu B", (unsigned long)bytes);
    }
}

static int stor_mem_color_kind(size_t free_bytes, size_t total_bytes)
{
    if (total_bytes == 0) {
        return SETTINGS_STATUS_DIM;
    }
    if (free_bytes * 10U < total_bytes) {
        return SETTINGS_STATUS_ERR;
    }
    if (free_bytes * 5U < total_bytes) {
        return SETTINGS_STATUS_WARN;
    }
    return SETTINGS_STATUS_OK;
}

static int stor_sd_color_kind(modulus_sd_state_t state)
{
    switch (state) {
    case MODULUS_SD_MOUNTED:
        return SETTINGS_STATUS_OK;
    case MODULUS_SD_ERROR:
        return SETTINGS_STATUS_ERR;
    default:
        return SETTINGS_STATUS_DIM;
    }
}

static void stor_set_value_color_if_changed(lv_obj_t *lbl, int kind, int *cache_kind)
{
    if (!lbl || !cache_kind) {
        return;
    }
    if (*cache_kind == kind) {
        return;
    }
    *cache_kind = kind;
    stor_set_value_color(lbl, kind);
}

static void stor_i2c_refresh_status_color(void)
{
    if (!s_stor_i2c_stat_lbl) {
        return;
    }
    int kind = SETTINGS_STATUS_DIM;
    if (modulus_i2c_scan_busy()) {
        kind = SETTINGS_STATUS_WARN;
    } else if (modulus_i2c_scan_done()) {
        kind = SETTINGS_STATUS_OK;
    }
    stor_set_value_color_if_changed(s_stor_i2c_stat_lbl, kind, &s_stor_i2c_stat_color);
}

static void stor_set_export_enabled(bool enabled)
{
    if (s_stor_export_enabled == (int8_t)enabled) {
        return;
    }
    s_stor_export_enabled = (int8_t)enabled;
    stor_set_action_enabled(s_stor_export_row, enabled);
}

static void stor_clear_label_caches(void)
{
    s_stor_int_cache[0] = '\0';
    s_stor_ps_cache[0] = '\0';
    s_stor_lv_cache[0] = '\0';
    s_stor_min_cache[0] = '\0';
    s_stor_sd_st_cache[0] = '\0';
    s_stor_sd_free_cache[0] = '\0';
    s_stor_sd_act_cache[0] = '\0';
    s_stor_export_val_cache[0] = '\0';
    s_stor_usb_cache[0] = '\0';
    s_stor_usb_vbus_cache[0] = '\0';
    s_stor_int_color = -1;
    s_stor_ps_color = -1;
    s_stor_lv_color = -1;
    s_stor_sd_color = -1;
    s_stor_usb_color = -1;
    s_stor_usb_vbus_color = -1;
    s_stor_export_enabled = -1;
    s_stor_i2c_stat_color = -1;
    s_stor_export_flash_start = 0;
}

static void stor_refresh_sd_labels(void)
{
    modulus_sd_info_t sd = {};
    modulus_storage_get_sd_info(&sd);

    if (s_stor_sd_lbl) {
        const char *st = (sd.state == MODULUS_SD_MOUNTED) ? "Mounted"
                       : (sd.state == MODULUS_SD_ERROR)   ? "Error"
                                                          : "Not mounted";
        stor_set_lbl_if_changed(s_stor_sd_lbl, st, s_stor_sd_st_cache, sizeof(s_stor_sd_st_cache));
        stor_set_value_color_if_changed(s_stor_sd_lbl, stor_sd_color_kind(sd.state), &s_stor_sd_color);
    }
    if (s_stor_sd_free_lbl) {
        if (sd.state == MODULUS_SD_MOUNTED) {
            static char fr_buf[64];
            if (sd.free_bytes >= (1024ULL * 1024 * 1024)) {
                snprintf(fr_buf, sizeof(fr_buf), "%.1f GB free of %.1f GB",
                         (double)sd.free_bytes / (1024.0 * 1024.0 * 1024.0),
                         (double)sd.total_bytes / (1024.0 * 1024.0 * 1024.0));
            } else {
                snprintf(fr_buf, sizeof(fr_buf), "%.0f MB free of %.0f MB",
                         (double)sd.free_bytes / (1024.0 * 1024.0),
                         (double)sd.total_bytes / (1024.0 * 1024.0));
            }
            stor_set_lbl_if_changed(s_stor_sd_free_lbl, fr_buf, s_stor_sd_free_cache,
                                    sizeof(s_stor_sd_free_cache));
        } else {
            stor_set_lbl_if_changed(s_stor_sd_free_lbl, "--", s_stor_sd_free_cache,
                                    sizeof(s_stor_sd_free_cache));
        }
    }
    if (s_stor_sd_act_val) {
        const char *act = sd.state == MODULUS_SD_MOUNTED ? "Eject" : "Mount";
        stor_set_lbl_if_changed(s_stor_sd_act_val, act, s_stor_sd_act_cache, sizeof(s_stor_sd_act_cache));
    }
    if (s_stor_export_val) {
        const char *hint = sd.state == MODULUS_SD_MOUNTED ? "Save to SD" : "Need SD card";
        /* Hold success/fail text ~4 s (M3 snackbar stand-in). */
        if (s_stor_export_flash_start != 0 &&
            lv_tick_elaps(s_stor_export_flash_start) < 4000) {
            /* keep flash text */
        } else {
            s_stor_export_flash_start = 0;
            stor_set_lbl_if_changed(s_stor_export_val, hint, s_stor_export_val_cache,
                                    sizeof(s_stor_export_val_cache));
            stor_set_value_color(s_stor_export_val, SETTINGS_STATUS_DIM);
        }
    }
    stor_set_export_enabled(sd.state == MODULUS_SD_MOUNTED);
}

static void stor_refresh_mem_labels(void)
{
    modulus_mem_info_t mem = {};
    modulus_storage_get_mem_info(&mem);
    static char buf[48];
    static char buf2[32];

    if (s_stor_int_lbl) {
        stor_fmt_bytes(buf, sizeof(buf), mem.internal_free);
        stor_fmt_bytes(buf2, sizeof(buf2), mem.internal_total);
        static char int_buf[96];
        snprintf(int_buf, sizeof(int_buf), "%s / %s", buf, buf2);
        stor_set_lbl_if_changed(s_stor_int_lbl, int_buf, s_stor_int_cache, sizeof(s_stor_int_cache));
        stor_set_value_color_if_changed(s_stor_int_lbl,
                                        stor_mem_color_kind(mem.internal_free, mem.internal_total),
                                        &s_stor_int_color);
    }
    if (s_stor_ps_lbl) {
        stor_fmt_bytes(buf, sizeof(buf), mem.psram_free);
        stor_fmt_bytes(buf2, sizeof(buf2), mem.psram_total);
        static char ps_buf[96];
        snprintf(ps_buf, sizeof(ps_buf), "%s / %s", buf, buf2);
        stor_set_lbl_if_changed(s_stor_ps_lbl, ps_buf, s_stor_ps_cache, sizeof(s_stor_ps_cache));
        stor_set_value_color_if_changed(s_stor_ps_lbl,
                                        stor_mem_color_kind(mem.psram_free, mem.psram_total),
                                        &s_stor_ps_color);
    }
    if (s_stor_lv_lbl) {
        stor_fmt_bytes(buf, sizeof(buf), mem.lvgl_free);
        static char lv_buf[80];
        snprintf(lv_buf, sizeof(lv_buf), "%s max blk (%u%% used)", buf, mem.lvgl_used_pct);
        stor_set_lbl_if_changed(s_stor_lv_lbl, lv_buf, s_stor_lv_cache, sizeof(s_stor_lv_cache));
        stor_set_value_color_if_changed(s_stor_lv_lbl,
                                        mem.lvgl_used_pct >= 90 ? SETTINGS_STATUS_WARN
                                                                : SETTINGS_STATUS_DIM,
                                        &s_stor_lv_color);
    }
    if (s_stor_min_lbl) {
        stor_fmt_bytes(buf, sizeof(buf), mem.internal_min_free);
        stor_set_lbl_if_changed(s_stor_min_lbl, buf, s_stor_min_cache, sizeof(s_stor_min_cache));
    }
}

static void stor_timer_cb(lv_timer_t *timer)
{
    (void)timer;
    stor_refresh_mem_labels();
    stor_refresh_sd_labels();
    if (s_stor_usb_lbl) {
        const char *usb_st = modulus_storage_usb_host_status_text();
        stor_set_lbl_if_changed(s_stor_usb_lbl, usb_st, s_stor_usb_cache, sizeof(s_stor_usb_cache));
        stor_set_value_color_if_changed(s_stor_usb_lbl, SETTINGS_STATUS_DIM, &s_stor_usb_color);
    }
    if (s_stor_usb_vbus_lbl) {
        const bool vbus = modulus_nvs_get_u8("usb5v", 0) != 0;
        stor_set_lbl_if_changed(s_stor_usb_vbus_lbl, vbus ? "On (Power tab)" : "Off",
                                s_stor_usb_vbus_cache, sizeof(s_stor_usb_vbus_cache));
        stor_set_value_color_if_changed(s_stor_usb_vbus_lbl,
                                        vbus ? SETTINGS_STATUS_OK : SETTINGS_STATUS_DIM,
                                        &s_stor_usb_vbus_color);
    }
    if (s_stor_i2c_stat_lbl) {
        stor_i2c_refresh_labels();
        stor_i2c_refresh_status_color();
        if (s_stor_timer) {
            lv_timer_set_period(s_stor_timer,
                                modulus_i2c_scan_busy() ? 500 : 2000);
        }
    }
}

void modulus_ui_settings_storage_tab_stop_timer(void)
{
    stor_panel_scroll_hook(false);
    s_stor_scrolling = false;
    s_stor_rebuild_pending = false;
    if (s_stor_timer) {
        lv_timer_delete(s_stor_timer);
        s_stor_timer = NULL;
    }
    stor_clear_label_caches();
    s_stor_int_lbl = NULL;
    s_stor_ps_lbl = NULL;
    s_stor_lv_lbl = NULL;
    s_stor_min_lbl = NULL;
    s_stor_sd_lbl = NULL;
    s_stor_sd_free_lbl = NULL;
    s_stor_sd_act_val = NULL;
    s_stor_export_row = NULL;
    s_stor_export_val = NULL;
    s_stor_usb_lbl = NULL;
    s_stor_usb_vbus_lbl = NULL;
    s_stor_i2c_stat_lbl = NULL;
    s_stor_i2c_port_lbl = NULL;
    s_stor_i2c_mbus_lbl = NULL;
    s_stor_i2c_exp1_lbl = NULL;
    s_stor_i2c_exp2_lbl = NULL;
}

void modulus_ui_settings_storage_tab_pause_activity(void)
{
    stor_panel_scroll_hook(false);
    if (s_stor_timer) {
        lv_timer_pause(s_stor_timer);
    }
}

void modulus_ui_settings_storage_tab_resume_activity(void)
{
    if (s_stor_timer) {
        stor_panel_scroll_hook(true);
        lv_timer_resume(s_stor_timer);
        stor_timer_cb(NULL);
    }
}

static void stor_panel_scroll_cb(lv_event_t *e)
{
    if (!s_stor_timer) {
        return;
    }
    const lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_SCROLL_BEGIN) {
        s_stor_scrolling = true;
        lv_timer_pause(s_stor_timer);
        return;
    }
    if (code != LV_EVENT_SCROLL_END) {
        return;
    }
    s_stor_scrolling = false;
    lv_timer_resume(s_stor_timer);
    stor_timer_cb(NULL);
    if (s_stor_rebuild_pending) {
        s_stor_rebuild_pending = false;
        stor_build_tab_now();
    }
}

static void stor_panel_scroll_hook(bool attach)
{
    lv_obj_t *panel = modulus_ui_settings_tab_panel(MOD_UI_SETTINGS_TAB_STORAGE);
    if (!panel) {
        return;
    }
    lv_obj_remove_event_cb(panel, stor_panel_scroll_cb);
    if (attach) {
        lv_obj_add_event_cb(panel, stor_panel_scroll_cb, LV_EVENT_SCROLL_BEGIN, NULL);
        lv_obj_add_event_cb(panel, stor_panel_scroll_cb, LV_EVENT_SCROLL_END, NULL);
    }
}

static void stor_request_rebuild(void)
{
    if (s_stor_scrolling) {
        s_stor_rebuild_pending = true;
        return;
    }
    s_stor_rebuild_pending = false;
    stor_build_tab_now();
}

static void stor_eject_confirmed(void)
{
    modulus_storage_unmount();
    modulus_audio_play_ui(1);
    ESP_LOGI("settings", "SD card ejected");
    modulus_ui_settings_build_storage_tab();
}

static void stor_loglvl_cb(lv_event_t *e)
{
    uint8_t lvl = modulus_ui_segmented_get_selected(lv_event_get_target(e));
    if (lvl > 5) {
        lvl = 2;
    }
    modulus_nvs_set_u8("loglvl", lvl);
    esp_log_level_set("*", (esp_log_level_t)lvl);
    ESP_LOGI("settings", "Log level set to %s", k_loglvl_strs[lvl]);
}

static void stor_sd_click_cb(lv_event_t *e)
{
    (void)e;
    modulus_sd_info_t info = {};
    modulus_storage_get_sd_info(&info);
    if (info.state == MODULUS_SD_MOUNTED) {
        settings_confirm_show(
            "Eject SD card",
            "Unmount the card before removing it from the slot.",
            "Eject", false, stor_eject_confirmed, NULL);
    } else {
        modulus_audio_play_ui(0);
        if (modulus_storage_mount()) {
            modulus_audio_play_ui(1);
        }
        ESP_LOGI("settings", "SD card mount requested");
        modulus_ui_settings_build_storage_tab();
    }
}

static void stor_settings_export_cb(lv_event_t *e)
{
    (void)e;
    modulus_sd_info_t info = {};
    modulus_storage_get_sd_info(&info);
    if (info.state != MODULUS_SD_MOUNTED) {
        modulus_audio_play_ui(2);
        return;
    }
    if (modulus_storage_export_settings("/sdcard/modulus_settings.json", false)) {
        modulus_audio_play_ui(1);
        modulus_ui_snackbar_show("Settings exported", 2800);
    } else {
        modulus_audio_play_ui(2);
        modulus_ui_snackbar_show("Export failed", 2800);
    }
}

static void stor_settings_import_apply(void)
{
    if (modulus_storage_import_settings("/sdcard/modulus_settings.json", false)) {
        modulus_audio_play_ui(1);
        modulus_ui_snackbar_show("Settings imported", 2800);
        modulus_zig_transport_reinit();
        modulus_ui_settings_build_storage_tab();
    } else {
        modulus_audio_play_ui(2);
        modulus_ui_snackbar_show("Import failed", 2800);
    }
}

static void stor_settings_import_cb(lv_event_t *e)
{
    (void)e;
    modulus_sd_info_t info = {};
    modulus_storage_get_sd_info(&info);
    if (info.state != MODULUS_SD_MOUNTED) {
        modulus_audio_play_ui(2);
        return;
    }
    settings_confirm_show("Import settings?",
                          "Overwrites current NVS settings from SD JSON.", "Import", true,
                          stor_settings_import_apply, NULL);
}

static void stor_export_click_cb(lv_event_t *e)
{
    (void)e;
    modulus_sd_info_t info = {};
    modulus_storage_get_sd_info(&info);
    if (info.state != MODULUS_SD_MOUNTED) {
        modulus_audio_play_ui(2);
        ESP_LOGW("settings", "Diagnostics export requires mounted SD");
        modulus_ui_snackbar_show("Need SD card", 2500);
        if (s_stor_export_val) {
            stor_set_lbl_if_changed(s_stor_export_val, "Need SD card",
                                    s_stor_export_val_cache, sizeof(s_stor_export_val_cache));
            stor_set_value_color(s_stor_export_val, SETTINGS_STATUS_WARN);
            s_stor_export_flash_start = lv_tick_get();
        }
        return;
    }
    modulus_audio_play_ui(0);
    if (modulus_storage_export_diagnostics("/sdcard/modulus_diag.txt")) {
        modulus_audio_play_ui(1);
        ESP_LOGI("settings", "Diagnostics exported to /sdcard/modulus_diag.txt");
        modulus_ui_snackbar_show("Diagnostics exported", 2800);
        if (s_stor_export_val) {
            stor_set_lbl_if_changed(s_stor_export_val, "Saved modulus_diag.txt",
                                    s_stor_export_val_cache, sizeof(s_stor_export_val_cache));
            stor_set_value_color(s_stor_export_val, SETTINGS_STATUS_OK);
            s_stor_export_flash_start = lv_tick_get();
        }
    } else {
        modulus_audio_play_ui(2);
        ESP_LOGW("settings", "Diagnostics export failed");
        modulus_ui_snackbar_show("Export failed", 2800);
        if (s_stor_export_val) {
            stor_set_lbl_if_changed(s_stor_export_val, "Export failed",
                                    s_stor_export_val_cache, sizeof(s_stor_export_val_cache));
            stor_set_value_color(s_stor_export_val, SETTINGS_STATUS_ERR);
            s_stor_export_flash_start = lv_tick_get();
        }
    }
}

static void stor_cache_click_cb(lv_event_t *e)
{
    (void)e;
    modulus_audio_play_ui(0);
    modulus_storage_clear_ui_cache();
    modulus_audio_play_ui(1);
}

static void stor_build_tab_now(void)
{
    lv_obj_t *p = modulus_ui_settings_tab_panel(MOD_UI_SETTINGS_TAB_STORAGE);
    if (!p) {
        return;
    }

    modulus_ui_settings_storage_tab_stop_timer();
    stor_clear_label_caches();
    lv_obj_clean(p);

    settings_section(p, "microSD card", NULL);

    modulus_sd_info_t sd = {};
    modulus_storage_get_sd_info(&sd);
    const char *sd_st = (sd.state == MODULUS_SD_MOUNTED) ? "Mounted"
                      : (sd.state == MODULUS_SD_ERROR)   ? "Error"
                                                         : "Not mounted";
    s_stor_sd_lbl = settings_detail_row(p, "Status", sd_st);
    stor_set_value_color(s_stor_sd_lbl, stor_sd_color_kind(sd.state));

    {
        static char fr_buf[64];
        if (sd.state == MODULUS_SD_MOUNTED) {
            if (sd.free_bytes >= (1024ULL * 1024 * 1024)) {
                snprintf(fr_buf, sizeof(fr_buf), "%.1f GB free of %.1f GB",
                         (double)sd.free_bytes / (1024.0 * 1024.0 * 1024.0),
                         (double)sd.total_bytes / (1024.0 * 1024.0 * 1024.0));
            } else {
                snprintf(fr_buf, sizeof(fr_buf), "%.0f MB free of %.0f MB",
                         (double)sd.free_bytes / (1024.0 * 1024.0),
                         (double)sd.total_bytes / (1024.0 * 1024.0));
            }
        } else {
            snprintf(fr_buf, sizeof(fr_buf), "--");
        }
        s_stor_sd_free_lbl = settings_detail_row(p, "Capacity", fr_buf);
    }

    {
        lv_obj_t *sd_row = settings_action_row(p, "SD card",
            sd.state == MODULUS_SD_MOUNTED ? "Eject" : "Mount");
        lv_obj_t *rg = lv_obj_get_child(sd_row, 1);
        s_stor_sd_act_val = rg ? lv_obj_get_child(rg, 0) : NULL;
        settings_bind_menu_click(sd_row, stor_sd_click_cb, NULL);
        modulus_ui_suppress_touch_tick(sd_row);
    }

    settings_section(p, "Memory", "Live heap telemetry.");
    modulus_mem_info_t mem = {};
    modulus_storage_get_mem_info(&mem);
    {
        static char buf[48];
        static char buf2[32];
        static char int_buf[96];
        stor_fmt_bytes(buf, sizeof(buf), mem.internal_free);
        stor_fmt_bytes(buf2, sizeof(buf2), mem.internal_total);
        snprintf(int_buf, sizeof(int_buf), "%s / %s", buf, buf2);
        s_stor_int_lbl = settings_detail_row(p, "Internal SRAM", int_buf);
        stor_set_value_color(s_stor_int_lbl,
                            stor_mem_color_kind(mem.internal_free, mem.internal_total));
    }
    {
        static char buf[48];
        static char buf2[32];
        static char ps_buf[96];
        stor_fmt_bytes(buf, sizeof(buf), mem.psram_free);
        stor_fmt_bytes(buf2, sizeof(buf2), mem.psram_total);
        snprintf(ps_buf, sizeof(ps_buf), "%s / %s", buf, buf2);
        s_stor_ps_lbl = settings_detail_row(p, "PSRAM", ps_buf);
        stor_set_value_color(s_stor_ps_lbl, stor_mem_color_kind(mem.psram_free, mem.psram_total));
    }
    {
        static char buf[48];
        static char lv_buf[80];
        stor_fmt_bytes(buf, sizeof(buf), mem.lvgl_free);
        snprintf(lv_buf, sizeof(lv_buf), "%s max blk (%u%% used)", buf, mem.lvgl_used_pct);
        s_stor_lv_lbl = settings_detail_row(p, "CLIB + PSRAM", lv_buf);
    }
    {
        static char mf_buf[24];
        stor_fmt_bytes(mf_buf, sizeof(mf_buf), mem.internal_min_free);
        s_stor_min_lbl = settings_detail_row(p, "Min free ever", mf_buf);
    }

    settings_section(p, "Logging & diagnostics", NULL);
    {
        uint8_t cur_lvl = modulus_nvs_get_u8("loglvl", 2);
        if (cur_lvl > 5) {
            cur_lvl = 2;
        }
        lv_obj_t *ll = settings_segmented_row(p, "Log level", k_loglvl_seg, 6, cur_lvl, 72);
        if (ll) {
            lv_obj_add_event_cb(ll, stor_loglvl_cb, LV_EVENT_VALUE_CHANGED, NULL);
        }
    }
    s_stor_export_row = settings_action_row(p, "Export diagnostics",
        sd.state == MODULUS_SD_MOUNTED ? "Save to SD" : "Need SD card");
    {
        lv_obj_t *rg = lv_obj_get_child(s_stor_export_row, 1);
        s_stor_export_val = rg ? lv_obj_get_child(rg, 0) : NULL;
    }
    stor_set_export_enabled(sd.state == MODULUS_SD_MOUNTED);
    settings_bind_menu_click(s_stor_export_row, stor_export_click_cb, NULL);
    modulus_ui_suppress_touch_tick(s_stor_export_row);

    settings_section(p, "Settings backup", "JSON on SD (passwords excluded by default).");
    {
        lv_obj_t *exp = settings_action_row(p, "Export settings",
            sd.state == MODULUS_SD_MOUNTED ? "modulus_settings.json" : "Need SD");
        settings_bind_menu_click(exp, stor_settings_export_cb, NULL);
        modulus_ui_suppress_touch_tick(exp);
        lv_obj_t *imp = settings_action_row(p, "Import settings", "Confirm first");
        settings_bind_menu_click(imp, stor_settings_import_cb, NULL);
        modulus_ui_suppress_touch_tick(imp);
        settings_note(p, "Does not include PIN hash or WiFi password.");
    }

    lv_obj_t *cache_row = settings_action_row(p, "Clear UI cache", "Refresh draw buffers");
    settings_bind_menu_click(cache_row, stor_cache_click_cb, NULL);
    modulus_ui_suppress_touch_tick(cache_row);

    settings_section(p, "USB host", "VBUS is Power tab; host-link detect pending BSP.");
    s_stor_usb_lbl = settings_detail_row(p, "Host data",
                                         modulus_storage_usb_host_status_text());
    stor_set_value_color(s_stor_usb_lbl, SETTINGS_STATUS_DIM);
    {
        const bool vbus = modulus_nvs_get_u8("usb5v", 0) != 0;
        s_stor_usb_vbus_lbl = settings_detail_row(p, "Type-A VBUS",
                                                  vbus ? "On (Power tab)" : "Off");
        stor_set_value_color(s_stor_usb_vbus_lbl,
                             vbus ? SETTINGS_STATUS_OK : SETTINGS_STATUS_DIM);
    }

    settings_section(p, "Storage reference", NULL);
    settings_expandable_link(p, "Show reference details", "Hide reference details",
                             &s_storage_ref_exp, modulus_ui_settings_build_storage_tab);
    if (s_storage_ref_exp) {
        settings_detail_row(p, "Flash chip", "16 MB");
        settings_detail_row(p, "SD interface", "SDMMC 4-bit @ /sdcard");
        settings_detail_row(p, "USB host", "Type-A USB 2.0");
    }

    settings_expandable_link(p, "Show I2C bus diagnostics", "Hide I2C bus diagnostics",
                             &s_storage_i2c_exp, modulus_ui_settings_build_storage_tab);
    if (s_storage_i2c_exp) {
        modulus_i2c_scan_init();
        {
            lv_obj_t *row = settings_action_row(p, "Scan all buses", "Tap to scan");
            settings_bind_menu_click(row, stor_i2c_scan_cb,
                                (void *)(uintptr_t)MODULUS_I2C_SCAN_ALL);
            modulus_ui_suppress_touch_tick(row);
        }
        {
            lv_obj_t *row = settings_action_row(p, "Scan M-Bus", "Tap to scan");
            settings_bind_menu_click(row, stor_i2c_scan_cb,
                                (void *)(uintptr_t)MODULUS_I2C_SCAN_MBUS);
            modulus_ui_suppress_touch_tick(row);
        }
        {
            lv_obj_t *row = settings_action_row(p, "Scan Port A", "Tap to scan");
            settings_bind_menu_click(row, stor_i2c_scan_cb,
                                (void *)(uintptr_t)MODULUS_I2C_SCAN_PORT_A);
            modulus_ui_suppress_touch_tick(row);
        }
        {
            lv_obj_t *row = settings_action_row(p, "Scan EXP1 PI4IOE", "Tap to scan");
            settings_bind_menu_click(row, stor_i2c_scan_cb,
                                (void *)(uintptr_t)MODULUS_I2C_SCAN_EXP1);
            modulus_ui_suppress_touch_tick(row);
        }
        {
            lv_obj_t *row = settings_action_row(p, "Scan EXP2 PI4IOE", "Tap to scan");
            settings_bind_menu_click(row, stor_i2c_scan_cb,
                                (void *)(uintptr_t)MODULUS_I2C_SCAN_EXP2);
            modulus_ui_suppress_touch_tick(row);
        }
        s_stor_i2c_stat_lbl = settings_detail_row(p, "Scanner", s_stor_i2c_stat_cache);
        s_stor_i2c_port_lbl = settings_detail_row(p, "Port A Grove I2C1", s_stor_i2c_port_cache);
        s_stor_i2c_mbus_lbl = settings_detail_row(p, "Int I2C0 M-Bus", s_stor_i2c_mbus_cache);
        s_stor_i2c_exp1_lbl = settings_detail_row(p, "EXP1 PI4IOE1", s_stor_i2c_exp1_cache);
        s_stor_i2c_exp2_lbl = settings_detail_row(p, "EXP2 PI4IOE2", s_stor_i2c_exp2_cache);
        {
            const bool ext5v = modulus_nvs_get_u8("ext5v", 1) != 0;
            lv_obj_t *pwr = settings_detail_row(p, "Port A EXT5V rail",
                ext5v ? "On (Grove pin 2 powered)" : "Off - enable in Power tab");
            stor_set_value_color(pwr, ext5v ? SETTINGS_STATUS_OK : SETTINGS_STATUS_WARN);
        }
        settings_expandable_link(p, "Show expansion port map", "Hide expansion port map",
                                 &s_storage_portmap_exp, modulus_ui_settings_build_storage_tab);
        if (s_storage_portmap_exp) {
            const size_t n = tab5_port_map_row_count();
            for (size_t i = 0; i < n; ++i) {
                const tab5_port_map_row_t *row = tab5_port_map_row(i);
                if (row) {
                    settings_detail_row(p, row->title, row->detail);
                }
            }
        }
        settings_expandable_link(p, "Show bus details", "Hide bus details",
                                 &s_storage_i2c_ref_exp, modulus_ui_settings_build_storage_tab);
        if (s_storage_i2c_ref_exp) {
            settings_detail_row(p, "RS-485 UART1", "TX G20 RX G21 DE G34");
            settings_detail_row(p, "Int I2C0 pins", "SDA G31 SCL G32");
            settings_detail_row(p, "Port A I2C1 pins", "SDA G53 SCL G54 (STD_GPIO mux)");
            settings_detail_row(p, "Port A note",
                                "Schematic STD_GPIO = matrix pin; fw uses I2C1");
            settings_detail_row(p, "ExtPort2 I2C tap", "Same Int I2C0 (G31/G32)");
            settings_detail_row(p, "M5-Bus Int I2C", "Pins 17-18 = G31/G32");
            settings_detail_row(p, "Known addrs",
                                "ES8388 0x10 ES7210 0x40 GT911 0x14 ST7123 0x55");
            settings_detail_row(p, "Known addrs 2",
                                "BMI270 0x68 RX8130 0x32 INA226 0x41 PI4IOE 0x43/0x44");
            settings_detail_row(p, "Port A module", "ExtEncoder 0x59 (handwheel MPG)");
        }
        stor_i2c_refresh_labels();
    }

    stor_timer_cb(NULL);
    s_stor_timer = lv_timer_create(stor_timer_cb, 2000, NULL);
    stor_panel_scroll_hook(true);
    modulus_ui_settings_note_tab_built(MOD_UI_SETTINGS_TAB_STORAGE);
}

void modulus_ui_settings_build_storage_tab(void)
{
    stor_request_rebuild();
}
