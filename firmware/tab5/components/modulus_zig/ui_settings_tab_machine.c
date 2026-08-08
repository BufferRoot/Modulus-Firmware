#include "ui_settings_priv.h"
#include "ui_settings_common.h"
#include "ui_settings_modals.h"
#include "ui_settings_modal_kb.h"
#include "ui_internal.h"
#include "nvs_shim.h"
#include "cnc_cmd_exports.h"

#include <esp_log.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static void toggle_nvs_u8_cb(lv_event_t *e)
{
    const char *key = lv_event_get_user_data(e);
    modulus_nvs_set_u8(key, lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED) ? 1 : 0);
}

static bool s_machine_ref_exp = false;
#define MACH_DEF_MAX_FEED    5000
#define MACH_DEF_MAX_SPINDLE 24000
#define MACH_DEF_JOG_SPD     1000
#define MACH_DEF_FEED_OVR    100
#define MACH_DEF_SPIND_OVR   100
#define MACH_XPORT_DEFAULT SETTINGS_CNC_XPORT_DEFAULT

static const char *mach_protocol_label(uint8_t idx)
{
    return settings_cnc_protocol_name(idx);
}

static uint32_t mach_read_maint_u32(const char *key_hi, const char *key_lo)
{
    const uint16_t hi = modulus_nvs_get_u16(key_hi, 0);
    const uint16_t lo = modulus_nvs_get_u16(key_lo, 0);
    return ((uint32_t)hi << 16) | lo;
}

static void mach_fmt_maint_duration(uint32_t sec, char *buf, size_t len)
{
    const uint32_t hours = sec / 3600U;
    const uint32_t mins = (sec % 3600U) / 60U;
    snprintf(buf, len, "%lu h %lu min", (unsigned long)hours, (unsigned long)mins);
}

static void mach_fmt_travel(uint32_t mm, char *buf, size_t len)
{
    if (mm >= 1000U) {
        snprintf(buf, len, "%.1f m", (double)mm / 1000.0);
    } else {
        snprintf(buf, len, "%lu mm", (unsigned long)mm);
    }
}

static void mach_fmt_service_pct(uint32_t value, uint64_t limit, char *buf, size_t len)
{
    if (limit == 0) {
        snprintf(buf, len, "interval off");
        return;
    }
    uint32_t pct = (uint32_t)((value * 100ULL) / limit);
    if (pct > 100) {
        pct = 100;
    }
    snprintf(buf, len, "%u%% of interval", (unsigned)pct);
}

static lv_timer_t *s_maint_tmr = NULL;
static lv_obj_t *s_maint_travel_lbl = NULL;
static lv_obj_t *s_maint_travel_x_lbl = NULL;
static lv_obj_t *s_maint_travel_y_lbl = NULL;
static lv_obj_t *s_maint_travel_z_lbl = NULL;
static lv_obj_t *s_maint_travel_a_lbl = NULL;
static lv_obj_t *s_maint_travel_b_lbl = NULL;
static lv_obj_t *s_maint_travel_c_lbl = NULL;
static lv_obj_t *s_maint_sph_lbl = NULL;
static lv_obj_t *s_maint_run_lbl = NULL;
static lv_obj_t *s_maint_travel_pct = NULL;
static lv_obj_t *s_maint_sph_pct = NULL;
static lv_obj_t *s_maint_run_pct = NULL;
static char s_maint_travel_cache[24] = {};
static char s_maint_tx_cache[24] = {};
static char s_maint_ty_cache[24] = {};
static char s_maint_tz_cache[24] = {};
static char s_maint_ta_cache[24] = {};
static char s_maint_tb_cache[24] = {};
static char s_maint_tc_cache[24] = {};
static char s_maint_sph_cache[24] = {};
static char s_maint_run_cache[24] = {};
static char s_maint_tp_cache[32] = {};
static char s_maint_sp_cache[32] = {};
static char s_maint_rp_cache[32] = {};

static const uint16_t k_mnt_odo_m[] = {0, 100, 250, 500, 1000, 2000, 5000};
static const uint16_t k_mnt_hours[] = {0, 25, 50, 100, 200, 500, 1000};
static const uint8_t k_mnt_warn[] = {80, 85, 90, 95, 100};

static int mach_find_u16_idx(const uint16_t *vals, int count, uint16_t val)
{
    for (int i = 0; i < count; i++) {
        if (vals[i] == val) {
            return i;
        }
    }
    return 0;
}

static void mach_fmt_deg(uint32_t deg, char *buf, size_t len)
{
    if (deg >= 10000U) {
        snprintf(buf, len, "%.1f kdeg", (double)deg / 1000.0);
    } else {
        snprintf(buf, len, "%lu deg", (unsigned long)deg);
    }
}

static void mach_set_travel_lbl(lv_obj_t *lbl, char *cache, size_t cache_len, uint32_t mm)
{
    char buf[24];
    mach_fmt_travel(mm, buf, sizeof(buf));
    if (lbl && strcmp(cache, buf) != 0) {
        lv_label_set_text(lbl, buf);
        strncpy(cache, buf, cache_len - 1);
        cache[cache_len - 1] = '\0';
    }
}

static void mach_set_deg_lbl(lv_obj_t *lbl, char *cache, size_t cache_len, uint32_t deg)
{
    char buf[24];
    mach_fmt_deg(deg, buf, sizeof(buf));
    if (lbl && strcmp(cache, buf) != 0) {
        lv_label_set_text(lbl, buf);
        strncpy(cache, buf, cache_len - 1);
        cache[cache_len - 1] = '\0';
    }
}

static void mach_maint_refresh_labels(void)
{
    const uint32_t travel = mach_read_maint_u32("cnc_odo_h", "cnc_odo_l");
    const uint32_t tx = mach_read_maint_u32("cnc_odx_h", "cnc_odx_l");
    const uint32_t ty = mach_read_maint_u32("cnc_ody_h", "cnc_ody_l");
    const uint32_t tz = mach_read_maint_u32("cnc_odz_h", "cnc_odz_l");
    const uint32_t ta = mach_read_maint_u32("cnc_oda_h", "cnc_oda_l");
    const uint32_t tb = mach_read_maint_u32("cnc_odb_h", "cnc_odb_l");
    const uint32_t tc = mach_read_maint_u32("cnc_odc_h", "cnc_odc_l");
    const uint32_t sph = mach_read_maint_u32("cnc_sph_h", "cnc_sph_l");
    const uint32_t run = mach_read_maint_u32("cnc_run_h", "cnc_run_l");
    const uint16_t odo_m = modulus_nvs_get_u16("cnc_mnt_odo", 500);
    const uint16_t sph_h = modulus_nvs_get_u16("cnc_mnt_sph", 100);
    const uint16_t run_h = modulus_nvs_get_u16("cnc_mnt_run", 200);
    const uint8_t warn = modulus_nvs_get_u8("cnc_mnt_warn", 90);

    char buf[32];
    mach_set_travel_lbl(s_maint_travel_lbl, s_maint_travel_cache, sizeof(s_maint_travel_cache), travel);
    mach_set_travel_lbl(s_maint_travel_x_lbl, s_maint_tx_cache, sizeof(s_maint_tx_cache), tx);
    mach_set_travel_lbl(s_maint_travel_y_lbl, s_maint_ty_cache, sizeof(s_maint_ty_cache), ty);
    mach_set_travel_lbl(s_maint_travel_z_lbl, s_maint_tz_cache, sizeof(s_maint_tz_cache), tz);
    mach_set_deg_lbl(s_maint_travel_a_lbl, s_maint_ta_cache, sizeof(s_maint_ta_cache), ta);
    mach_set_deg_lbl(s_maint_travel_b_lbl, s_maint_tb_cache, sizeof(s_maint_tb_cache), tb);
    mach_set_deg_lbl(s_maint_travel_c_lbl, s_maint_tc_cache, sizeof(s_maint_tc_cache), tc);

    mach_fmt_maint_duration(sph, buf, sizeof(buf));
    if (s_maint_sph_lbl && strcmp(s_maint_sph_cache, buf) != 0) {
        lv_label_set_text(s_maint_sph_lbl, buf);
        strncpy(s_maint_sph_cache, buf, sizeof(s_maint_sph_cache) - 1);
    }
    mach_fmt_maint_duration(run, buf, sizeof(buf));
    if (s_maint_run_lbl && strcmp(s_maint_run_cache, buf) != 0) {
        lv_label_set_text(s_maint_run_lbl, buf);
        strncpy(s_maint_run_cache, buf, sizeof(s_maint_run_cache) - 1);
    }

    const uint64_t lim_odo = (uint64_t)odo_m * 1000ULL;
    const uint64_t lim_sph = (uint64_t)sph_h * 3600ULL;
    const uint64_t lim_run = (uint64_t)run_h * 3600ULL;
    mach_fmt_service_pct(travel, lim_odo, buf, sizeof(buf));
    if (s_maint_travel_pct && strcmp(s_maint_tp_cache, buf) != 0) {
        lv_label_set_text(s_maint_travel_pct, buf);
        strncpy(s_maint_tp_cache, buf, sizeof(s_maint_tp_cache) - 1);
        const bool hot = lim_odo > 0 && travel * 100ULL >= lim_odo * warn;
        lv_obj_set_style_text_color(s_maint_travel_pct,
                                    hot ? modulus_settings_status_color(SETTINGS_STATUS_WARN)
                                        : modulus_ui_color_on_surface_variant(),
                                    0);
    }
    mach_fmt_service_pct(sph, lim_sph, buf, sizeof(buf));
    if (s_maint_sph_pct && strcmp(s_maint_sp_cache, buf) != 0) {
        lv_label_set_text(s_maint_sph_pct, buf);
        strncpy(s_maint_sp_cache, buf, sizeof(s_maint_sp_cache) - 1);
        const bool hot = lim_sph > 0 && sph * 100ULL >= lim_sph * warn;
        lv_obj_set_style_text_color(s_maint_sph_pct,
                                    hot ? modulus_settings_status_color(SETTINGS_STATUS_WARN)
                                        : modulus_ui_color_on_surface_variant(),
                                    0);
    }
    mach_fmt_service_pct(run, lim_run, buf, sizeof(buf));
    if (s_maint_run_pct && strcmp(s_maint_rp_cache, buf) != 0) {
        lv_label_set_text(s_maint_run_pct, buf);
        strncpy(s_maint_rp_cache, buf, sizeof(s_maint_rp_cache) - 1);
        const bool hot = lim_run > 0 && run * 100ULL >= lim_run * warn;
        lv_obj_set_style_text_color(s_maint_run_pct,
                                    hot ? modulus_settings_status_color(SETTINGS_STATUS_WARN)
                                        : modulus_ui_color_on_surface_variant(),
                                    0);
    }
}

static void mach_maint_tmr_cb(lv_timer_t *t)
{
    (void)t;
    mach_maint_refresh_labels();
}

static void mach_mnt_odo_cb(lv_event_t *e)
{
    const uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    modulus_nvs_set_u16("cnc_mnt_odo", k_mnt_odo_m[idx < 7 ? idx : 3]);
    mach_maint_refresh_labels();
}

static void mach_mnt_sph_cb(lv_event_t *e)
{
    const uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    modulus_nvs_set_u16("cnc_mnt_sph", k_mnt_hours[idx < 7 ? idx : 3]);
    mach_maint_refresh_labels();
}

static void mach_mnt_run_cb(lv_event_t *e)
{
    const uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    modulus_nvs_set_u16("cnc_mnt_run", k_mnt_hours[idx < 7 ? idx : 3]);
    mach_maint_refresh_labels();
}

static void mach_mnt_warn_cb(lv_event_t *e)
{
    const uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    modulus_nvs_set_u8("cnc_mnt_warn", k_mnt_warn[idx < 5 ? idx : 2]);
    mach_maint_refresh_labels();
}

static void mach_slider_u16_cb(lv_event_t *e)
{
    const lv_event_code_t code = lv_event_get_code(e);
    if (code != LV_EVENT_VALUE_CHANGED && code != LV_EVENT_RELEASED) {
        return;
    }
    const char *key = lv_event_get_user_data(e);
    lv_obj_t *s = lv_event_get_target(e);
    const int32_t val = lv_slider_get_value(s);
    lv_obj_t *vl = lv_obj_get_user_data(s);
    const char *unit = vl ? (const char *)lv_obj_get_user_data(vl) : "";
    if (vl && unit && unit[0]) {
        char buf[16];
        snprintf(buf, sizeof(buf), "%ld %s", (long)val, unit);
        modulus_ui_label_set_text_if_changed(vl, buf);
    }
    if (code != LV_EVENT_RELEASED) {
        return;
    }
    modulus_nvs_set_u16(key, (uint16_t)val);
    if (key && strcmp(key, "cnc_jogspd") == 0) {
        /* Encoder base feed + cmdJog clamp both read cnc_jogspd — reload both. */
        modulus_zig_encoder_reload_settings();
        modulus_zig_reload_machine_limits();
    } else if (key &&
               (strcmp(key, "cnc_mxfeed") == 0 || strcmp(key, "cnc_mxrpm") == 0 ||
                strcmp(key, "cnc_tr_x") == 0 || strcmp(key, "cnc_tr_y") == 0 ||
                strcmp(key, "cnc_tr_z") == 0 || strcmp(key, "cnc_tr_a") == 0 ||
                strcmp(key, "cnc_tr_b") == 0 || strcmp(key, "cnc_tr_c") == 0)) {
        modulus_zig_limits_reload();
    }
}

static void mach_pct_u8_cb(lv_event_t *e)
{
    const lv_event_code_t code = lv_event_get_code(e);
    if (code != LV_EVENT_VALUE_CHANGED && code != LV_EVENT_RELEASED) {
        return;
    }
    const char *key = lv_event_get_user_data(e);
    lv_obj_t *s = lv_event_get_target(e);
    const uint8_t val = (uint8_t)lv_slider_get_value(s);
    lv_obj_t *vl = lv_obj_get_user_data(s);
    if (vl) {
        char buf[8];
        snprintf(buf, sizeof(buf), "%u%%", val);
        modulus_ui_label_set_text_if_changed(vl, buf);
    }
    if (code != LV_EVENT_RELEASED) {
        return;
    }
    modulus_nvs_set_u8(key, val);
    if (key && (strcmp(key, "cnc_feedovr") == 0 || strcmp(key, "cnc_spindovr") == 0)) {
        modulus_zig_limits_reload();
    }
}

static void mach_slim_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    modulus_nvs_set_u8("cnc_slim", on ? 1 : 0);
    modulus_zig_limits_reload();
}

static void mach_grbl_dump_cb(lv_event_t *e)
{
    (void)e;
    settings_grbl_dump_modal_show();
}

static void mach_maint_meters_cb(lv_event_t *e)
{
    (void)e;
    settings_maint_modal_show();
}

static void mach_sync_env_cb(lv_event_t *e)
{
    (void)e;
    modulus_zig_sync_envelope();
    modulus_ui_snackbar_show("Envelope pushed", 2500);
}

/* --- Pull envelope FROM controller (Grbl-family $$ -> NVS) --- */
static lv_timer_t *s_pull_tmr = NULL;
static uint8_t s_pull_polls = 0;

static void mach_pull_stop_timer(void)
{
    if (s_pull_tmr) {
        lv_timer_delete(s_pull_tmr);
        s_pull_tmr = NULL;
    }
}

void modulus_ui_settings_machine_tab_stop_timer(void)
{
    mach_pull_stop_timer();
    modulus_zig_settings_dump_cancel();
    s_pull_polls = 0;
    if (s_maint_tmr) {
        lv_timer_delete(s_maint_tmr);
        s_maint_tmr = NULL;
    }
    s_maint_travel_lbl = NULL;
    s_maint_travel_x_lbl = NULL;
    s_maint_travel_y_lbl = NULL;
    s_maint_travel_z_lbl = NULL;
    s_maint_travel_a_lbl = NULL;
    s_maint_travel_b_lbl = NULL;
    s_maint_travel_c_lbl = NULL;
    s_maint_sph_lbl = NULL;
    s_maint_run_lbl = NULL;
    s_maint_travel_pct = NULL;
    s_maint_sph_pct = NULL;
    s_maint_run_pct = NULL;
    s_maint_travel_cache[0] = '\0';
    s_maint_tx_cache[0] = '\0';
    s_maint_ty_cache[0] = '\0';
    s_maint_tz_cache[0] = '\0';
    s_maint_ta_cache[0] = '\0';
    s_maint_tb_cache[0] = '\0';
    s_maint_tc_cache[0] = '\0';
    s_maint_sph_cache[0] = '\0';
    s_maint_run_cache[0] = '\0';
    s_maint_tp_cache[0] = '\0';
    s_maint_sp_cache[0] = '\0';
    s_maint_rp_cache[0] = '\0';
    settings_maint_modal_hide();
}

void modulus_ui_settings_machine_tab_pause_activity(void)
{
    modulus_ui_settings_machine_tab_stop_timer();
}

static void mach_pull_finish(const char *msg)
{
    mach_pull_stop_timer();
    lv_obj_t *p = modulus_ui_settings_tab_panel(MOD_UI_SETTINGS_TAB_MACHINE);
    if (p) {
        modulus_ui_settings_build_machine_tab(); /* re-read sliders from NVS */
    }
    ESP_LOGI("settings", "Envelope pull: %s", msg);
    if (msg && msg[0]) {
        char snack[48];
        snprintf(snack, sizeof(snack), "Pull %s", msg);
        modulus_ui_snackbar_show(snack, 2500);
    }
}

static void mach_pull_poll_cb(lv_timer_t *t)
{
    (void)t;
    if (modulus_zig_settings_dump_failed()) {
        mach_pull_finish("dump failed");
        return;
    }
    if (modulus_zig_settings_dump_ready()) {
        const uint8_t n = modulus_zig_envelope_pull_apply();
        mach_pull_finish(n ? "applied" : "no matching settings");
        return;
    }
    if (++s_pull_polls > 40) { /* 10 s @ 250 ms */
        modulus_zig_settings_dump_cancel();
        mach_pull_finish("timeout");
    }
}

static void mach_pull_env_cb(lv_event_t *e)
{
    (void)e;
    if (s_pull_tmr) {
        return;
    }
    modulus_zig_settings_dump_begin();
    s_pull_polls = 0;
    s_pull_tmr = lv_timer_create(mach_pull_poll_cb, 250, NULL);
}

static lv_obj_t *mach_metric_slider_row(lv_obj_t *parent, const char *label,
                                        int32_t val, int32_t min_v, int32_t max_v,
                                        const char *unit)
{
    lv_obj_t *sl = settings_slider_row(parent, label, val, min_v, max_v);
    lv_obj_t *vl = lv_obj_get_user_data(sl);
    if (vl) {
        char buf[16];
        snprintf(buf, sizeof(buf), "%ld %s", (long)val, unit);
        lv_label_set_text(vl, buf);
        lv_obj_set_user_data(vl, (void *)unit);
    }
    return sl;
}

static lv_obj_t *mach_pct_slider_row(lv_obj_t *parent, const char *label,
                                     int32_t val, int32_t min_v, int32_t max_v)
{
    lv_obj_t *sl = settings_slider_row(parent, label, val, min_v, max_v);
    lv_obj_t *vl = lv_obj_get_user_data(sl);
    if (vl) {
        char buf[8];
        snprintf(buf, sizeof(buf), "%ld%%", (long)val);
        lv_label_set_text(vl, buf);
    }
    return sl;
}

static void mach_type_cb(lv_event_t *e)
{
    const char *const *names = lv_event_get_user_data(e);
    uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    if (idx >= 8) {
        idx = 7;
    }
    modulus_nvs_set_str("mach_type", names[idx]);
}

static void machine_maint_reset_cb(void)
{
    modulus_nvs_set_u16("cnc_odo_h", 0);
    modulus_nvs_set_u16("cnc_odo_l", 0);
    modulus_nvs_set_u16("cnc_odx_h", 0);
    modulus_nvs_set_u16("cnc_odx_l", 0);
    modulus_nvs_set_u16("cnc_ody_h", 0);
    modulus_nvs_set_u16("cnc_ody_l", 0);
    modulus_nvs_set_u16("cnc_odz_h", 0);
    modulus_nvs_set_u16("cnc_odz_l", 0);
    modulus_nvs_set_u16("cnc_oda_h", 0);
    modulus_nvs_set_u16("cnc_oda_l", 0);
    modulus_nvs_set_u16("cnc_odb_h", 0);
    modulus_nvs_set_u16("cnc_odb_l", 0);
    modulus_nvs_set_u16("cnc_odc_h", 0);
    modulus_nvs_set_u16("cnc_odc_l", 0);
    modulus_nvs_set_u16("cnc_sph_h", 0);
    modulus_nvs_set_u16("cnc_sph_l", 0);
    modulus_nvs_set_u16("cnc_run_h", 0);
    modulus_nvs_set_u16("cnc_run_l", 0);
    modulus_zig_maint_reset_counters();
    ESP_LOGI("settings", "Maintenance counters reset");
    modulus_ui_settings_build_machine_tab();
}

static void machine_reset_cb(void)
{
    modulus_nvs_set_u16("cnc_mxfeed", MACH_DEF_MAX_FEED);
    modulus_nvs_set_u16("cnc_mxrpm", MACH_DEF_MAX_SPINDLE);
    modulus_nvs_set_u16("cnc_jogspd", MACH_DEF_JOG_SPD);
    modulus_nvs_set_u8("cnc_feedovr", MACH_DEF_FEED_OVR);
    modulus_nvs_set_u8("cnc_spindovr", MACH_DEF_SPIND_OVR);
    modulus_nvs_set_u8("cnc_slim", 0);
    modulus_nvs_set_u16("cnc_tr_x", 300);
    modulus_nvs_set_u16("cnc_tr_y", 300);
    modulus_nvs_set_u16("cnc_tr_z", 100);
    modulus_nvs_set_u16("cnc_tr_a", 360);
    modulus_nvs_set_u16("cnc_tr_b", 360);
    modulus_nvs_set_u16("cnc_tr_c", 360);
    modulus_nvs_set_u16("cnc_odo_h", 0);
    modulus_nvs_set_u16("cnc_odo_l", 0);
    modulus_nvs_set_u16("cnc_odx_h", 0);
    modulus_nvs_set_u16("cnc_odx_l", 0);
    modulus_nvs_set_u16("cnc_ody_h", 0);
    modulus_nvs_set_u16("cnc_ody_l", 0);
    modulus_nvs_set_u16("cnc_odz_h", 0);
    modulus_nvs_set_u16("cnc_odz_l", 0);
    modulus_nvs_set_u16("cnc_oda_h", 0);
    modulus_nvs_set_u16("cnc_oda_l", 0);
    modulus_nvs_set_u16("cnc_odb_h", 0);
    modulus_nvs_set_u16("cnc_odb_l", 0);
    modulus_nvs_set_u16("cnc_odc_h", 0);
    modulus_nvs_set_u16("cnc_odc_l", 0);
    modulus_nvs_set_u16("cnc_sph_h", 0);
    modulus_nvs_set_u16("cnc_sph_l", 0);
    modulus_nvs_set_u16("cnc_run_h", 0);
    modulus_nvs_set_u16("cnc_run_l", 0);
    modulus_nvs_set_u16("cnc_mnt_odo", 500);
    modulus_nvs_set_u16("cnc_mnt_sph", 100);
    modulus_nvs_set_u16("cnc_mnt_run", 200);
    modulus_nvs_set_u8("cnc_mnt_warn", 90);
    modulus_zig_maint_reset_counters();
    modulus_zig_limits_reload();
    modulus_zig_encoder_reload_settings();
    ESP_LOGI("settings", "Machine settings reset");
    modulus_ui_settings_build_machine_tab();
}

static void mach_name_load(char *buf, size_t len)
{
    if (!modulus_nvs_get_str("mach_name", buf, len)) {
        strncpy(buf, "My CNC", len - 1);
        buf[len - 1] = '\0';
    }
}

static void mach_name_edit_cb(lv_event_t *e)
{
    (void)e;
    settings_mach_name_modal_show();
}

/* ── Last service date / notes (one-field NVS string modal) ───────── */

static lv_obj_t *s_svc_modal = NULL;
static lv_obj_t *s_svc_ta = NULL;
static lv_obj_t *s_svc_kb = NULL;
static const char *s_svc_key = NULL;
static uint32_t s_svc_max = 15;

static void mach_svc_exit_ready(lv_anim_t *a)
{
    lv_obj_t *dlg = lv_anim_get_user_data(a);
    if (dlg) {
        lv_obj_delete(dlg);
    }
    s_svc_ta = NULL;
    s_svc_kb = NULL;
    s_svc_key = NULL;
}

static void mach_svc_modal_hide(void)
{
    if (!s_svc_modal) {
        s_svc_ta = NULL;
        s_svc_kb = NULL;
        s_svc_key = NULL;
        return;
    }
    lv_obj_t *dlg = s_svc_modal;
    s_svc_modal = NULL;
    s_svc_ta = NULL;
    s_svc_kb = NULL;
    s_svc_key = NULL;
    lv_obj_t *card = lv_obj_get_child(dlg, 0);
    if (card && modulus_ui_motion_smooth()) {
        modulus_ui_motion_dialog_exit(card, mach_svc_exit_ready, dlg);
        return;
    }
    lv_obj_delete(dlg);
}

static void mach_svc_close_cb(lv_event_t *e)
{
    (void)e;
    mach_svc_modal_hide();
}

static void mach_svc_save_cb(lv_event_t *e)
{
    (void)e;
    if (!s_svc_ta || !s_svc_key) {
        return;
    }
    const char *txt = lv_textarea_get_text(s_svc_ta);
    modulus_nvs_set_str(s_svc_key, txt ? txt : "");
    mach_svc_modal_hide();
    modulus_ui_settings_build_machine_tab();
}

static void mach_svc_ta_focus_cb(lv_event_t *e)
{
    if (s_svc_kb) {
        lv_keyboard_set_textarea(s_svc_kb, lv_event_get_target(e));
    }
}

static void mach_svc_modal_show(const char *key, const char *title, const char *hint,
                                uint32_t max_len)
{
    mach_svc_modal_hide();
    s_svc_key = key;
    s_svc_max = max_len;

    char buf[64];
    if (!modulus_nvs_get_str(key, buf, sizeof(buf))) {
        buf[0] = '\0';
    }

    s_svc_modal = modulus_ui_dialog_scrim_create();

    lv_obj_t *card = modulus_ui_dialog_card_create(s_svc_modal, MOD_UI_DIALOG_W_STANDARD, 0);
    lv_obj_align(card, LV_ALIGN_TOP_MID, 0, 40);
    modulus_ui_motion_dialog_enter(card);

    modulus_ui_dialog_header(card, title, mach_svc_close_cb, NULL);
    modulus_ui_dialog_scrim_bind_dismiss(s_svc_modal, mach_svc_close_cb, NULL);
    if (hint && hint[0]) {
        modulus_ui_dialog_supporting(card, hint);
    }

    s_svc_ta = lv_textarea_create(card);
    lv_textarea_set_text(s_svc_ta, buf);
    lv_textarea_set_one_line(s_svc_ta, true);
    lv_textarea_set_max_length(s_svc_ta, max_len);
    lv_obj_set_width(s_svc_ta, lv_pct(100));
    modulus_ui_apply_textarea_theme(s_svc_ta, false);
    lv_obj_add_event_cb(s_svc_ta, mach_svc_ta_focus_cb, LV_EVENT_FOCUSED, NULL);

    lv_obj_t *row = modulus_ui_dialog_actions(card, true);
    modulus_ui_dialog_action_btn(row, "Cancel", MOD_UI_DIALOG_BTN_TONAL, mach_svc_close_cb, NULL);
    modulus_ui_dialog_action_btn(row, "Save", MOD_UI_DIALOG_BTN_FILLED, mach_svc_save_cb, NULL);

    s_svc_kb = lv_keyboard_create(s_svc_modal);
    lv_keyboard_set_mode(s_svc_kb, LV_KEYBOARD_MODE_TEXT_LOWER);
    settings_modal_kb_configure_text(s_svc_kb);
    lv_keyboard_set_textarea(s_svc_kb, s_svc_ta);
}

static void mach_svc_dt_cb(lv_event_t *e)
{
    (void)e;
    mach_svc_modal_show("cnc_svc_dt", "Last service date", "YYYY-MM-DD", 15);
}

static void mach_svc_nt_cb(lv_event_t *e)
{
    (void)e;
    mach_svc_modal_show("cnc_svc_nt", "Service notes", "Short note (grease, belts, etc.)", 63);
}

void modulus_ui_settings_build_machine_tab(void)
{
    lv_obj_t *p = modulus_ui_settings_tab_panel(MOD_UI_SETTINGS_TAB_MACHINE);
    if (!p) {
        return;
    }
    /* Abort in-flight pull / maint refresh before wipe. */
    modulus_ui_settings_machine_tab_stop_timer();
    mach_svc_modal_hide();
    lv_obj_clean(p);

    settings_section(p, "Work envelope", "Limits enforced on jog and overrides.");
    {
        uint16_t mxfeed = modulus_nvs_get_u16("cnc_mxfeed", MACH_DEF_MAX_FEED);
        if (mxfeed < 100) {
            mxfeed = 100;
        }
        if (mxfeed > 20000) {
            mxfeed = 20000;
        }
        lv_obj_t *sl_feed = mach_metric_slider_row(p, "Max feed rate", mxfeed, 100, 20000, "mm/min");
        lv_obj_add_event_cb(sl_feed, mach_slider_u16_cb, LV_EVENT_VALUE_CHANGED, (void *)"cnc_mxfeed");
        lv_obj_add_event_cb(sl_feed, mach_slider_u16_cb, LV_EVENT_RELEASED, (void *)"cnc_mxfeed");
    }
    {
        uint16_t mxrpm = modulus_nvs_get_u16("cnc_mxrpm", MACH_DEF_MAX_SPINDLE);
        if (mxrpm < 1000) {
            mxrpm = 1000;
        }
        if (mxrpm > 60000) {
            mxrpm = 60000;
        }
        lv_obj_t *sl_rpm = mach_metric_slider_row(p, "Max spindle RPM", mxrpm, 1000, 60000, "RPM");
        lv_obj_add_event_cb(sl_rpm, mach_slider_u16_cb, LV_EVENT_VALUE_CHANGED, (void *)"cnc_mxrpm");
        lv_obj_add_event_cb(sl_rpm, mach_slider_u16_cb, LV_EVENT_RELEASED, (void *)"cnc_mxrpm");
    }
    {
        uint16_t jogspd = modulus_nvs_get_u16("cnc_jogspd", MACH_DEF_JOG_SPD);
        if (jogspd < 100) {
            jogspd = 100;
        }
        if (jogspd > 10000) {
            jogspd = 10000;
        }
        lv_obj_t *sl_jog = mach_metric_slider_row(p, "Default jog speed", jogspd, 100, 10000, "mm/min");
        lv_obj_add_event_cb(sl_jog, mach_slider_u16_cb, LV_EVENT_VALUE_CHANGED, (void *)"cnc_jogspd");
        lv_obj_add_event_cb(sl_jog, mach_slider_u16_cb, LV_EVENT_RELEASED, (void *)"cnc_jogspd");
    }
    {
        uint8_t feedovr = modulus_nvs_get_u8("cnc_feedovr", MACH_DEF_FEED_OVR);
        if (feedovr < 10) {
            feedovr = 10;
        }
        if (feedovr > 200) {
            feedovr = 200;
        }
        lv_obj_t *sl_fovr = mach_pct_slider_row(p, "Default feed override", feedovr, 10, 200);
        lv_obj_add_event_cb(sl_fovr, mach_pct_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"cnc_feedovr");
        lv_obj_add_event_cb(sl_fovr, mach_pct_u8_cb, LV_EVENT_RELEASED, (void *)"cnc_feedovr");
    }
    {
        uint8_t spindovr = modulus_nvs_get_u8("cnc_spindovr", MACH_DEF_SPIND_OVR);
        if (spindovr < 10) {
            spindovr = 10;
        }
        if (spindovr > 200) {
            spindovr = 200;
        }
        lv_obj_t *sl_sovr = mach_pct_slider_row(p, "Default spindle override", spindovr, 10, 200);
        lv_obj_add_event_cb(sl_sovr, mach_pct_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"cnc_spindovr");
        lv_obj_add_event_cb(sl_sovr, mach_pct_u8_cb, LV_EVENT_RELEASED, (void *)"cnc_spindovr");
    }

    settings_section(p, "Pendant soft limits",
                     "Linear mm / rotary deg. Machine coords 0..max after homing.");
    {
        const bool slim = modulus_nvs_get_u8("cnc_slim", 0) != 0;
        lv_obj_t *sw = settings_toggle_row(p, "Soft limit enforcement", slim);
        lv_obj_add_event_cb(sw, mach_slim_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }
    {
        uint16_t trx = modulus_nvs_get_u16("cnc_tr_x", 300);
        if (trx < 50) {
            trx = 50;
        }
        if (trx > 2000) {
            trx = 2000;
        }
        lv_obj_t *sl_x = mach_metric_slider_row(p, "Max travel X", trx, 50, 2000, "mm");
        lv_obj_add_event_cb(sl_x, mach_slider_u16_cb, LV_EVENT_VALUE_CHANGED, (void *)"cnc_tr_x");
        lv_obj_add_event_cb(sl_x, mach_slider_u16_cb, LV_EVENT_RELEASED, (void *)"cnc_tr_x");
    }
    {
        uint16_t try_ = modulus_nvs_get_u16("cnc_tr_y", 300);
        if (try_ < 50) {
            try_ = 50;
        }
        if (try_ > 2000) {
            try_ = 2000;
        }
        lv_obj_t *sl_y = mach_metric_slider_row(p, "Max travel Y", try_, 50, 2000, "mm");
        lv_obj_add_event_cb(sl_y, mach_slider_u16_cb, LV_EVENT_VALUE_CHANGED, (void *)"cnc_tr_y");
        lv_obj_add_event_cb(sl_y, mach_slider_u16_cb, LV_EVENT_RELEASED, (void *)"cnc_tr_y");
    }
    {
        uint16_t trz = modulus_nvs_get_u16("cnc_tr_z", 100);
        if (trz < 10) {
            trz = 10;
        }
        if (trz > 1000) {
            trz = 1000;
        }
        lv_obj_t *sl_z = mach_metric_slider_row(p, "Max travel Z", trz, 10, 1000, "mm");
        lv_obj_add_event_cb(sl_z, mach_slider_u16_cb, LV_EVENT_VALUE_CHANGED, (void *)"cnc_tr_z");
        lv_obj_add_event_cb(sl_z, mach_slider_u16_cb, LV_EVENT_RELEASED, (void *)"cnc_tr_z");
    }
    {
        uint16_t tra = modulus_nvs_get_u16("cnc_tr_a", 360);
        if (tra < 1) {
            tra = 1;
        }
        if (tra > 7200) {
            tra = 7200;
        }
        lv_obj_t *sl_a = mach_metric_slider_row(p, "Max travel A", tra, 1, 7200, "deg");
        lv_obj_add_event_cb(sl_a, mach_slider_u16_cb, LV_EVENT_VALUE_CHANGED, (void *)"cnc_tr_a");
        lv_obj_add_event_cb(sl_a, mach_slider_u16_cb, LV_EVENT_RELEASED, (void *)"cnc_tr_a");
    }
    {
        uint16_t trb = modulus_nvs_get_u16("cnc_tr_b", 360);
        if (trb < 1) {
            trb = 1;
        }
        if (trb > 7200) {
            trb = 7200;
        }
        lv_obj_t *sl_b = mach_metric_slider_row(p, "Max travel B", trb, 1, 7200, "deg");
        lv_obj_add_event_cb(sl_b, mach_slider_u16_cb, LV_EVENT_VALUE_CHANGED, (void *)"cnc_tr_b");
        lv_obj_add_event_cb(sl_b, mach_slider_u16_cb, LV_EVENT_RELEASED, (void *)"cnc_tr_b");
    }
    {
        uint16_t trc = modulus_nvs_get_u16("cnc_tr_c", 360);
        if (trc < 1) {
            trc = 1;
        }
        if (trc > 7200) {
            trc = 7200;
        }
        lv_obj_t *sl_c = mach_metric_slider_row(p, "Max travel C", trc, 1, 7200, "deg");
        lv_obj_add_event_cb(sl_c, mach_slider_u16_cb, LV_EVENT_VALUE_CHANGED, (void *)"cnc_tr_c");
        lv_obj_add_event_cb(sl_c, mach_slider_u16_cb, LV_EVENT_RELEASED, (void *)"cnc_tr_c");
    }
    settings_note(p, "A/B/C soft limits in degrees. Unused axes: leave default 360.");

    settings_section(p, "Controller sync", NULL);
    {
        uint8_t sync_proto = modulus_nvs_get_u8("cnc_proto", SETTINGS_CNC_PROTO_DEFAULT);
        if (sync_proto >= SETTINGS_CNC_PROTOCOL_COUNT) {
            sync_proto = SETTINGS_CNC_PROTO_DEFAULT;
        }
        char sync_hdr[64];
        snprintf(sync_hdr, sizeof(sync_hdr), "Active MCS: %s", mach_protocol_label(sync_proto));
        settings_note(p, sync_hdr);
        if (settings_cnc_protocol_supports_dump(sync_proto)) {
            if (sync_proto == SETTINGS_CNC_PROTO_LINUXCNC) {
                lv_obj_t *pull_row = settings_action_row(p, "Pull from controller",
                                                         "get ini TRAJ/AXIS/SPINDLE -> pendant");
                settings_bind_menu_click(pull_row, mach_pull_env_cb, NULL);
                settings_note(p,
                    "linuxcncrsh INI pull (no $$). Sliders remain source of truth if keys missing.");
            } else {
                /* GrblHAL / Grbl / FluidNC share $$ dump dialect. */
                lv_obj_t *pull_row = settings_action_row(p, "Pull from controller",
                                                         "$110/$30/$130-135 -> pendant");
                settings_bind_menu_click(pull_row, mach_pull_env_cb, NULL);
                lv_obj_t *sync_row = settings_action_row(p, "Push to controller", "$110-$112, $30");
                settings_bind_menu_click(sync_row, mach_sync_env_cb, NULL);
                lv_obj_t *dump_row = settings_action_row(p, "Settings browser ($$)", "Read all $nn");
                settings_bind_menu_click(dump_row, mach_grbl_dump_cb, NULL);
            }
        } else if (sync_proto == SETTINGS_CNC_PROTO_LINUXCNC) {
            /* unreachable if supports_dump includes LCNC — kept for clarity */
            settings_note(p, "Set envelope on pendant sliders.");
        } else if (sync_proto == SETTINGS_CNC_PROTO_MACH3) {
            settings_note(p,
                "No remote INI on Mach3. Run tools/mmbp_bridge on PC (Telnet 7878). "
                "Paste $110/$30/$130 lines or set sliders.");
            settings_note(p, "Paste format: $110=4000  $30=18000  $130=610 (one per line).");
        } else if (sync_proto == SETTINGS_CNC_PROTO_MASSO) {
            char ip[40], sn[28];
            if (!modulus_nvs_get_str("masso_ip", ip, sizeof(ip)) || ip[0] == '\0') {
                strncpy(ip, "(not set)", sizeof(ip) - 1);
                ip[sizeof(ip) - 1] = '\0';
            }
            if (!modulus_nvs_get_str("masso_sn", sn, sizeof(sn)) || sn[0] == '\0') {
                strncpy(sn, "(none)", sizeof(sn) - 1);
                sn[sizeof(sn) - 1] = '\0';
            }
            char sum[96];
            snprintf(sum, sizeof(sum), "%s / %s  UDP %u/%u",
                     ip, sn,
                     (unsigned)modulus_nvs_get_u16("masso_tx", 11000),
                     (unsigned)modulus_nvs_get_u16("masso_rx", 65535));
            settings_detail_row(p, "Masso Link", sum);
            settings_note(p,
                "UDP status/keepalive live. Link packets lack XYZ DRO - envelope is pendant-local.");
            settings_link_tab_row(p, "CNC connection", "Edit Masso fields", 0);
        } else {
            settings_note(p, "Controller sync not available for this MCS yet. Change MCS on CNC tab.");
        }
    }

    settings_section(p, "Machine identity", NULL);
    char name[32];
    mach_name_load(name, sizeof(name));
    lv_obj_t *name_row = settings_action_row(p, "Machine name", name);
    settings_bind_menu_click(name_row, mach_name_edit_cb, NULL);
    {
        static const char *const k_mach_types[] = {"Mill",   "Router", "Lathe",     "Plasma",
                                                   "Laser",  "EDM",    "Drill/Tap", "Other"};
        static const char k_mach_type_opts[] =
            "Mill\nRouter\nLathe\nPlasma\nLaser\nEDM\nDrill/Tap\nOther";
        char type_buf[24];
        if (!modulus_nvs_get_str("mach_type", type_buf, sizeof(type_buf))) {
            strncpy(type_buf, "Mill", sizeof(type_buf) - 1);
            type_buf[sizeof(type_buf) - 1] = '\0';
        }
        uint8_t type_idx = 7; /* Other */
        for (uint8_t i = 0; i < 8; i++) {
            if (strcmp(type_buf, k_mach_types[i]) == 0) {
                type_idx = i;
                break;
            }
        }
        lv_obj_t *dd_type = settings_dropdown_row(p, "Machine type", k_mach_type_opts, type_idx);
        lv_obj_add_event_cb(dd_type, mach_type_cb, LV_EVENT_VALUE_CHANGED, (void *)k_mach_types);
    }
    {
        uint8_t proto = modulus_nvs_get_u8("cnc_proto", SETTINGS_CNC_PROTO_DEFAULT);
        if (proto >= SETTINGS_CNC_PROTOCOL_COUNT) {
            proto = SETTINGS_CNC_PROTO_DEFAULT;
        }
        uint8_t conn = modulus_nvs_get_u8("cnc_conn", MACH_XPORT_DEFAULT);
        if (conn >= 8) {
            conn = MACH_XPORT_DEFAULT;
        }
        static char conn_summary[72];
        snprintf(conn_summary, sizeof(conn_summary), "%s / %s",
                 mach_protocol_label(proto), settings_cnc_transport_name(conn));
        settings_detail_row(p, "Controller link", conn_summary);
    }
    settings_link_tab_row(p, "CNC connection", "Edit transport", 0);

    settings_section(p, "Spindle", NULL);
    lv_obj_t *ccw = settings_toggle_row(p, "Allow CCW (M4)", modulus_nvs_get_u8("cnc_spcw", 1) != 0);
    lv_obj_add_event_cb(ccw, toggle_nvs_u8_cb, LV_EVENT_VALUE_CHANGED, (void *)"cnc_spcw");

    settings_section(p, "Maintenance",
                     "Accrues from jog/run motion, spindle-on time, and program RUN.");
    {
        char travel[24], tp[32], sp[32], rp[32];
        const uint32_t travel_mm = mach_read_maint_u32("cnc_odo_h", "cnc_odo_l");
        const uint32_t sph_sec = mach_read_maint_u32("cnc_sph_h", "cnc_sph_l");
        const uint32_t run_sec = mach_read_maint_u32("cnc_run_h", "cnc_run_l");
        const uint16_t odo_m = modulus_nvs_get_u16("cnc_mnt_odo", 500);
        const uint16_t sph_h = modulus_nvs_get_u16("cnc_mnt_sph", 100);
        const uint16_t run_h = modulus_nvs_get_u16("cnc_mnt_run", 200);
        mach_fmt_travel(travel_mm, travel, sizeof(travel));
        mach_fmt_service_pct(travel_mm, (uint64_t)odo_m * 1000ULL, tp, sizeof(tp));
        mach_fmt_service_pct(sph_sec, (uint64_t)sph_h * 3600ULL, sp, sizeof(sp));
        mach_fmt_service_pct(run_sec, (uint64_t)run_h * 3600ULL, rp, sizeof(rp));

        s_maint_travel_lbl = settings_detail_row(p, "Path travel", travel);
        s_maint_travel_pct = settings_detail_row(p, "Travel service", tp);
        s_maint_sph_pct = settings_detail_row(p, "Spindle service", sp);
        s_maint_run_pct = settings_detail_row(p, "Run service", rp);
        s_maint_travel_x_lbl = NULL;
        s_maint_travel_y_lbl = NULL;
        s_maint_travel_z_lbl = NULL;
        s_maint_travel_a_lbl = NULL;
        s_maint_travel_b_lbl = NULL;
        s_maint_travel_c_lbl = NULL;
        s_maint_sph_lbl = NULL;
        s_maint_run_lbl = NULL;
        strncpy(s_maint_travel_cache, travel, sizeof(s_maint_travel_cache) - 1);
        strncpy(s_maint_tp_cache, tp, sizeof(s_maint_tp_cache) - 1);
        strncpy(s_maint_sp_cache, sp, sizeof(s_maint_sp_cache) - 1);
        strncpy(s_maint_rp_cache, rp, sizeof(s_maint_rp_cache) - 1);
        s_maint_tx_cache[0] = '\0';
        s_maint_ty_cache[0] = '\0';
        s_maint_tz_cache[0] = '\0';
        s_maint_ta_cache[0] = '\0';
        s_maint_tb_cache[0] = '\0';
        s_maint_tc_cache[0] = '\0';
        s_maint_sph_cache[0] = '\0';
        s_maint_run_cache[0] = '\0';

        lv_obj_t *meters = settings_action_row(p, "Maintenance meters", "Axes + times");
        settings_bind_menu_click(meters, mach_maint_meters_cb, NULL);
    }
    {
        char svc_dt[16] = "";
        char svc_nt[64] = "";
        if (!modulus_nvs_get_str("cnc_svc_dt", svc_dt, sizeof(svc_dt)) || svc_dt[0] == '\0') {
            strncpy(svc_dt, "Not set", sizeof(svc_dt) - 1);
        }
        if (!modulus_nvs_get_str("cnc_svc_nt", svc_nt, sizeof(svc_nt)) || svc_nt[0] == '\0') {
            strncpy(svc_nt, "-", sizeof(svc_nt) - 1);
        }
        lv_obj_t *dt_row = settings_action_row(p, "Last service", svc_dt);
        settings_bind_menu_click(dt_row, mach_svc_dt_cb, NULL);
        lv_obj_t *nt_row = settings_action_row(p, "Service notes", svc_nt);
        settings_bind_menu_click(nt_row, mach_svc_nt_cb, NULL);
    }
    {
        lv_obj_t *dd = settings_dropdown_row(p, "Travel interval",
            "Off\n100 m\n250 m\n500 m\n1 km\n2 km\n5 km",
            (uint16_t)mach_find_u16_idx(k_mnt_odo_m, 7, modulus_nvs_get_u16("cnc_mnt_odo", 500)));
        lv_obj_add_event_cb(dd, mach_mnt_odo_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }
    {
        lv_obj_t *dd = settings_dropdown_row(p, "Spindle interval",
            "Off\n25 h\n50 h\n100 h\n200 h\n500 h\n1000 h",
            (uint16_t)mach_find_u16_idx(k_mnt_hours, 7, modulus_nvs_get_u16("cnc_mnt_sph", 100)));
        lv_obj_add_event_cb(dd, mach_mnt_sph_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }
    {
        lv_obj_t *dd = settings_dropdown_row(p, "Run-time interval",
            "Off\n25 h\n50 h\n100 h\n200 h\n500 h\n1000 h",
            (uint16_t)mach_find_u16_idx(k_mnt_hours, 7, modulus_nvs_get_u16("cnc_mnt_run", 200)));
        lv_obj_add_event_cb(dd, mach_mnt_run_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }
    {
        uint8_t w = modulus_nvs_get_u8("cnc_mnt_warn", 90);
        uint8_t widx = 2;
        for (uint8_t i = 0; i < 5; i++) {
            if (k_mnt_warn[i] == w) {
                widx = i;
                break;
            }
        }
        lv_obj_t *dd = settings_dropdown_row(p, "Warn at", "80%\n85%\n90%\n95%\n100%", widx);
        lv_obj_add_event_cb(dd, mach_mnt_warn_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }
    settings_note(p, "Warn fires once per threshold (event + highlighted %). Off = no service interval.");
    static settings_reset_ctx_t mreset = {
        .title = "Reset maintenance counters?",
        .body = "Clear axis travel, spindle time, and job run time. Cannot undo.",
        .fn = machine_maint_reset_cb,
    };
    settings_reset_row(p, "Reset counters", &mreset);
    s_maint_tmr = lv_timer_create(mach_maint_tmr_cb, 2000, NULL);
    mach_maint_refresh_labels();

    settings_section(p, "Related settings", NULL);
    settings_link_tab_row(p, "Dashboard & handwheel", "", 1);

    settings_section(p, "Grbl / GrblHAL reference", NULL);
    settings_expandable_link(p, "Show reference", "Hide reference",
                             &s_machine_ref_exp, modulus_ui_settings_build_machine_tab);
    if (s_machine_ref_exp) {
        settings_detail_row(p, "$130 / $131 / $132", "Max travel: X / Y / Z (mm)");
        settings_detail_row(p, "$133 / $134 / $135", "Max travel: A / B / C (deg)");
        settings_detail_row(p, "$110 / $111 / $112", "Max rate: X / Y / Z (mm/min)");
        settings_detail_row(p, "$120 / $121 / $122", "Acceleration: X / Y / Z (mm/s2)");
        settings_detail_row(p, "$22", "Homing cycle enable");
        settings_detail_row(p, "$23", "Homing direction invert mask");
        settings_detail_row(p, "$20", "Soft limits enable (controller)");
        settings_note(p, "Pendant soft limits clamp jog before $J= is sent.");
        settings_note(p, "Feed, spindle, and jog limits above apply on the pendant side.");
    }

    static settings_reset_ctx_t mreset_full = {
        .title = "Reset machine settings?",
        .body = "Restores work envelope, soft limits, and maintenance counters.",
        .fn = machine_reset_cb,
    };
    settings_reset_row(p, "Reset machine settings", &mreset_full);
    modulus_ui_settings_note_tab_built(MOD_UI_SETTINGS_TAB_MACHINE);
}

void settings_machine_svc_kb_theme_refresh(void)
{
    if (s_svc_kb) {
        modulus_ui_apply_keyboard_theme(s_svc_kb);
    }
    if (s_svc_ta) {
        modulus_ui_apply_textarea_theme(s_svc_ta, false);
    }
    modulus_ui_dialog_theme_refresh(s_svc_modal);
}

