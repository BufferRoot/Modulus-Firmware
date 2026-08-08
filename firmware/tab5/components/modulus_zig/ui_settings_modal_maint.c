#include "ui_settings_modals_priv.h"
#include "ui_settings_common.h"
#include "ui_settings_priv.h"
#include "ui_internal.h"
#include "nvs_shim.h"

#include <stdio.h>
#include <string.h>

static lv_obj_t *s_maint_modal = NULL;
static lv_timer_t *s_tmr = NULL;
static lv_obj_t *s_travel_lbl;
static lv_obj_t *s_tx_lbl;
static lv_obj_t *s_ty_lbl;
static lv_obj_t *s_tz_lbl;
static lv_obj_t *s_ta_lbl;
static lv_obj_t *s_tb_lbl;
static lv_obj_t *s_tc_lbl;
static lv_obj_t *s_sph_lbl;
static lv_obj_t *s_run_lbl;
static lv_obj_t *s_tp_lbl;
static lv_obj_t *s_sp_lbl;
static lv_obj_t *s_rp_lbl;
static char s_c_travel[24];
static char s_c_tx[24];
static char s_c_ty[24];
static char s_c_tz[24];
static char s_c_ta[24];
static char s_c_tb[24];
static char s_c_tc[24];
static char s_c_sph[24];
static char s_c_run[24];
static char s_c_tp[32];
static char s_c_sp[32];
static char s_c_rp[32];

static uint32_t read_u32(const char *hi, const char *lo)
{
    return ((uint32_t)modulus_nvs_get_u16(hi, 0) << 16) | modulus_nvs_get_u16(lo, 0);
}

static void fmt_dur(uint32_t sec, char *buf, size_t len)
{
    snprintf(buf, len, "%lu h %lu min", (unsigned long)(sec / 3600U),
             (unsigned long)((sec % 3600U) / 60U));
}

static void fmt_travel(uint32_t mm, char *buf, size_t len)
{
    if (mm >= 1000U) {
        snprintf(buf, len, "%.1f m", (double)mm / 1000.0);
    } else {
        snprintf(buf, len, "%lu mm", (unsigned long)mm);
    }
}

static void fmt_deg(uint32_t deg, char *buf, size_t len)
{
    snprintf(buf, len, "%lu deg", (unsigned long)deg);
}

static void fmt_pct(uint32_t value, uint64_t limit, char *buf, size_t len)
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

static void set_if_changed(lv_obj_t *lbl, char *cache, size_t cache_len, const char *txt)
{
    if (!lbl || !txt) {
        return;
    }
    if (strcmp(cache, txt) == 0) {
        return;
    }
    lv_label_set_text(lbl, txt);
    strncpy(cache, txt, cache_len - 1);
    cache[cache_len - 1] = '\0';
}

static void refresh(void)
{
    char buf[32];
    const uint32_t travel = read_u32("cnc_odo_h", "cnc_odo_l");
    const uint32_t tx = read_u32("cnc_odx_h", "cnc_odx_l");
    const uint32_t ty = read_u32("cnc_ody_h", "cnc_ody_l");
    const uint32_t tz = read_u32("cnc_odz_h", "cnc_odz_l");
    const uint32_t ta = read_u32("cnc_oda_h", "cnc_oda_l");
    const uint32_t tb = read_u32("cnc_odb_h", "cnc_odb_l");
    const uint32_t tc = read_u32("cnc_odc_h", "cnc_odc_l");
    const uint32_t sph = read_u32("cnc_sph_h", "cnc_sph_l");
    const uint32_t run = read_u32("cnc_run_h", "cnc_run_l");
    const uint16_t odo_m = modulus_nvs_get_u16("cnc_mnt_odo", 500);
    const uint16_t sph_h = modulus_nvs_get_u16("cnc_mnt_sph", 100);
    const uint16_t run_h = modulus_nvs_get_u16("cnc_mnt_run", 200);

    fmt_travel(travel, buf, sizeof(buf));
    set_if_changed(s_travel_lbl, s_c_travel, sizeof(s_c_travel), buf);
    fmt_travel(tx, buf, sizeof(buf));
    set_if_changed(s_tx_lbl, s_c_tx, sizeof(s_c_tx), buf);
    fmt_travel(ty, buf, sizeof(buf));
    set_if_changed(s_ty_lbl, s_c_ty, sizeof(s_c_ty), buf);
    fmt_travel(tz, buf, sizeof(buf));
    set_if_changed(s_tz_lbl, s_c_tz, sizeof(s_c_tz), buf);
    fmt_deg(ta, buf, sizeof(buf));
    set_if_changed(s_ta_lbl, s_c_ta, sizeof(s_c_ta), buf);
    fmt_deg(tb, buf, sizeof(buf));
    set_if_changed(s_tb_lbl, s_c_tb, sizeof(s_c_tb), buf);
    fmt_deg(tc, buf, sizeof(buf));
    set_if_changed(s_tc_lbl, s_c_tc, sizeof(s_c_tc), buf);
    fmt_dur(sph, buf, sizeof(buf));
    set_if_changed(s_sph_lbl, s_c_sph, sizeof(s_c_sph), buf);
    fmt_dur(run, buf, sizeof(buf));
    set_if_changed(s_run_lbl, s_c_run, sizeof(s_c_run), buf);
    fmt_pct(travel, (uint64_t)odo_m * 1000ULL, buf, sizeof(buf));
    set_if_changed(s_tp_lbl, s_c_tp, sizeof(s_c_tp), buf);
    fmt_pct(sph, (uint64_t)sph_h * 3600ULL, buf, sizeof(buf));
    set_if_changed(s_sp_lbl, s_c_sp, sizeof(s_c_sp), buf);
    fmt_pct(run, (uint64_t)run_h * 3600ULL, buf, sizeof(buf));
    set_if_changed(s_rp_lbl, s_c_rp, sizeof(s_c_rp), buf);
}

static void tmr_cb(lv_timer_t *t)
{
    (void)t;
    refresh();
}

void settings_maint_modal_hide(void)
{
    if (s_tmr) {
        lv_timer_delete(s_tmr);
        s_tmr = NULL;
    }
    if (!s_maint_modal) {
        s_travel_lbl = s_tx_lbl = s_ty_lbl = s_tz_lbl = NULL;
        s_ta_lbl = s_tb_lbl = s_tc_lbl = NULL;
        s_sph_lbl = s_run_lbl = s_tp_lbl = s_sp_lbl = s_rp_lbl = NULL;
        return;
    }
    s_travel_lbl = s_tx_lbl = s_ty_lbl = s_tz_lbl = NULL;
    s_ta_lbl = s_tb_lbl = s_tc_lbl = NULL;
    s_sph_lbl = s_run_lbl = s_tp_lbl = s_sp_lbl = s_rp_lbl = NULL;
    modulus_ui_dialog_scrim_hide_animated(&s_maint_modal);
}

static void close_cb(lv_event_t *e)
{
    (void)e;
    settings_maint_modal_hide();
    modulus_ui_settings_build_machine_tab();
}

void settings_maint_modal_show(void)
{
    settings_maint_modal_hide();

    s_maint_modal = modulus_ui_dialog_scrim_create();
    lv_obj_t *card = modulus_ui_dialog_card_create(s_maint_modal, MOD_UI_DIALOG_W_WIDE, 0);
    modulus_ui_motion_dialog_enter(card);
    modulus_ui_dialog_scrim_bind_dismiss(s_maint_modal, close_cb, NULL);

    modulus_ui_dialog_header(card, "Maintenance meters", close_cb, NULL);
    modulus_ui_dialog_supporting(card, "Live travel, spindle, and run-time meters.");

    lv_obj_t *body = lv_obj_create(card);
    lv_obj_remove_style_all(body);
    lv_obj_set_width(body, lv_pct(100));
    lv_obj_set_height(body, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(body, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(body, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_max_height(body, 420, 0);
    lv_obj_add_flag(body, LV_OBJ_FLAG_SCROLLABLE);

    settings_section(body, "Travel", NULL);
    s_travel_lbl = settings_detail_row(body, "Path travel", "--");
    s_tx_lbl = settings_detail_row(body, "X travel", "--");
    s_ty_lbl = settings_detail_row(body, "Y travel", "--");
    s_tz_lbl = settings_detail_row(body, "Z travel", "--");
    s_ta_lbl = settings_detail_row(body, "A travel", "--");
    s_tb_lbl = settings_detail_row(body, "B travel", "--");
    s_tc_lbl = settings_detail_row(body, "C travel", "--");
    s_tp_lbl = settings_detail_row(body, "Travel service", "--");

    settings_section(body, "Time", NULL);
    s_sph_lbl = settings_detail_row(body, "Spindle time", "--");
    s_sp_lbl = settings_detail_row(body, "Spindle service", "--");
    s_run_lbl = settings_detail_row(body, "Job run time", "--");
    s_rp_lbl = settings_detail_row(body, "Run service", "--");

    memset(s_c_travel, 0, sizeof(s_c_travel));
    memset(s_c_tx, 0, sizeof(s_c_tx));
    memset(s_c_ty, 0, sizeof(s_c_ty));
    memset(s_c_tz, 0, sizeof(s_c_tz));
    memset(s_c_ta, 0, sizeof(s_c_ta));
    memset(s_c_tb, 0, sizeof(s_c_tb));
    memset(s_c_tc, 0, sizeof(s_c_tc));
    memset(s_c_sph, 0, sizeof(s_c_sph));
    memset(s_c_run, 0, sizeof(s_c_run));
    memset(s_c_tp, 0, sizeof(s_c_tp));
    memset(s_c_sp, 0, sizeof(s_c_sp));
    memset(s_c_rp, 0, sizeof(s_c_rp));
    refresh();
    s_tmr = lv_timer_create(tmr_cb, 2000, NULL);

    lv_obj_t *row = modulus_ui_dialog_actions(card, true);
    modulus_ui_dialog_action_btn(row, "Done", MOD_UI_DIALOG_BTN_FILLED, close_cb, NULL);
}

void settings_maint_modal_theme_refresh(void)
{
    modulus_ui_dialog_theme_refresh(s_maint_modal);
}
