#include "ui_settings_priv.h"
#include "ui_settings_common.h"
#include "ui_settings_modals.h"
#include "ui_internal.h"
#include "ui_axes_preset.h"
#include "nvs_shim.h"
#include "cnc_cmd_exports.h"
#include "audio_shim.h"

#include <stdio.h>
#include <string.h>

static bool s_hw_ref_exp = false;

static void dash_cnf_cb(lv_event_t *e)
{
    const char *key = (const char *)lv_event_get_user_data(e);
    const uint16_t idx = lv_dropdown_get_selected(lv_event_get_target(e));
    uint8_t v = 0;
    if (idx == 1) {
        v = 1;
    } else if (idx == 2) {
        v = 2;
    }
    modulus_nvs_set_u8(key, v);
}

static void dash_coal_cb(lv_event_t *e)
{
    lv_obj_t *sl = lv_event_get_target(e);
    int32_t v = (int32_t)lv_slider_get_value(sl);
    if (v < 0) {
        v = 0;
    }
    if (v > 100) {
        v = 100;
    }
    modulus_nvs_set_u8("jog_coal_ms", (uint8_t)v);
    modulus_zig_encoder_reload_settings();
}

static void dash_pend_cb(lv_event_t *e)
{
    lv_obj_t *sl = lv_event_get_target(e);
    int32_t v = (int32_t)lv_slider_get_value(sl);
    if (v < 4) {
        v = 4;
    }
    if (v > 64) {
        v = 64;
    }
    modulus_nvs_set_u8("jog_pend_max", (uint8_t)v);
    modulus_zig_encoder_reload_settings();
}

static void dash_wcs_edit_cb(lv_event_t *e)
{
    (void)e;
    settings_wcs_modal_show();
}

static void dash_mpg_edit_cb(lv_event_t *e)
{
    (void)e;
    settings_mpg_modal_show();
}

static void dash_probe_cb(lv_event_t *e)
{
    (void)e;
    settings_probe_modal_show();
}

static void incr_edit_cb(lv_event_t *e)
{
    (void)e;
    settings_incr_modal_show();
}

static void qbtn_edit_cb(lv_event_t *e)
{
    (void)e;
    settings_qbtn_modal_show();
}

static void mac_add_cb(lv_event_t *e)
{
    (void)e;
    settings_macro_slot_modal_show(-1);
}

static void mac_edit_cb(lv_event_t *e)
{
    const int slot = (int)(intptr_t)lv_event_get_user_data(e);
    settings_macro_slot_modal_show((int8_t)slot);
}

static void dash_contpct_cb(lv_event_t *e)
{
    const lv_event_code_t code = lv_event_get_code(e);
    if (code != LV_EVENT_VALUE_CHANGED && code != LV_EVENT_RELEASED) {
        return;
    }
    lv_obj_t *s = lv_event_get_target(e);
    int32_t val = lv_slider_get_value(s);
    if (val < 10) {
        val = 10;
    }
    if (val > 200) {
        val = 200;
    }
    lv_obj_t *vl = lv_obj_get_user_data(s);
    if (vl) {
        char buf[8];
        snprintf(buf, sizeof(buf), "%ld%%", (long)val);
        modulus_ui_label_set_text_if_changed(vl, buf);
    }
    if (code == LV_EVENT_RELEASED) {
        modulus_nvs_set_u8("cnc_contpct", (uint8_t)val);
        modulus_zig_encoder_reload_settings();
    }
}

static const uint16_t k_jogspd_opts[] = {500, 1000, 2000, 3000, 5000, 8000, 10000};

static void dash_jogspd_cb(lv_event_t *e)
{
    const uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    if (idx >= sizeof(k_jogspd_opts) / sizeof(k_jogspd_opts[0])) {
        return;
    }
    modulus_nvs_set_u16("cnc_jogspd", k_jogspd_opts[idx]);
    /* Both consumers reload live: encoder feed math + driver $J= clamp. */
    modulus_zig_encoder_reload_settings();
    modulus_zig_reload_machine_limits();
}

static uint8_t jogspd_to_idx(uint16_t v)
{
    uint8_t best = 1; /* 1000 default */
    for (uint8_t i = 0; i < sizeof(k_jogspd_opts) / sizeof(k_jogspd_opts[0]); i++) {
        if (k_jogspd_opts[i] == v) {
            return i;
        }
        if (k_jogspd_opts[i] <= v) {
            best = i;
        }
    }
    return best;
}

static void dash_stepacc_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    modulus_nvs_set_u8("cnc_stepacc", on ? 1 : 0);
    modulus_zig_encoder_reload_settings();
}

static void dash_wcs_cb(lv_event_t *e)
{
    const uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    if (idx > 5) {
        return;
    }
    const uint8_t lock = modulus_nvs_get_u8("wcs_lock", 0);
    if ((lock & (1U << idx)) != 0) {
        modulus_audio_play_ui(2);
    }
    modulus_nvs_set_u8("cnc_wcs", idx);
    modulus_zig_set_wcs(idx);
    modulus_ui_dashboard_config_changed();
}

static void dash_jmode_seg_cb(lv_event_t *e)
{
    lv_obj_t *track = lv_obj_get_parent(lv_event_get_target(e));
    const uint8_t idx = modulus_ui_segmented_get_selected(track);
    if (idx > 2) {
        return;
    }
    modulus_nvs_set_u8("cnc_jmode", idx);
    modulus_zig_set_jog_mode(idx);
}

static void dash_axes_seg_cb(lv_event_t *e)
{
    lv_obj_t *track = lv_obj_get_parent(lv_event_get_target(e));
    const uint8_t preset = modulus_ui_segmented_get_selected(track);
    if (preset > 4) {
        return;
    }
    modulus_nvs_set_u8("cnc_axes", preset);
    modulus_ui_dashboard_config_changed();
}

static void dash_unit_cb(lv_event_t *e)
{
    const bool mm = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    modulus_nvs_set_u8("cnc_unit", mm ? 1 : 0);
    modulus_zig_set_units_mm(mm ? 1 : 0);
    modulus_ui_dashboard_config_changed();
}

static void dash_encdiv_cb(lv_event_t *e)
{
    const lv_event_code_t code = lv_event_get_code(e);
    if (code != LV_EVENT_VALUE_CHANGED && code != LV_EVENT_RELEASED) {
        return;
    }
    lv_obj_t *s = lv_event_get_target(e);
    int32_t val = lv_slider_get_value(s);
    if (val < 1) {
        val = 1;
    }
    if (val > 16) {
        val = 16;
    }
    lv_obj_t *vl = lv_obj_get_user_data(s);
    if (vl) {
        char buf[8];
        snprintf(buf, sizeof(buf), "%ld", (long)val);
        modulus_ui_label_set_text_if_changed(vl, buf);
    }
    if (code == LV_EVENT_RELEASED) {
        modulus_nvs_set_u8("cnc_encdiv", (uint8_t)val);
        modulus_zig_encoder_reload_settings();
    }
}

/* --- Quick buttons: custom G-code / aux-IO + dashboard slot arrange --- */

static void dash_build_quick_buttons_section(lv_obj_t *p)
{
    settings_section(p, "Quick buttons", NULL);
    settings_note(p,
                  "Create buttons (aux pins, macros), then place them on the dashboard.");

    bool any = false;
    for (uint8_t slot = 0; slot < SETTINGS_MACRO_SLOTS; slot++) {
        char name[16];
        char on[64];
        char off[64];
        if (!settings_macro_slot_load(slot, name, sizeof(name), on, sizeof(on), off, sizeof(off),
                                      NULL)) {
            continue;
        }
        any = true;
        char detail[96];
        if (off[0]) {
            snprintf(detail, sizeof(detail), "Toggle  %.32s / %.32s", on, off);
        } else {
            snprintf(detail, sizeof(detail), "Press  %.64s", on);
        }
        lv_obj_t *row = settings_action_row(p, name, detail);
        settings_bind_menu_click(row, mac_edit_cb, (void *)(intptr_t)slot);
    }
    if (!any) {
        settings_note(p, "Example toggle: ON = M64 P0, OFF = M65 P0");
    }

    if (settings_macro_slot_first_free() >= 0) {
        lv_obj_t *add = settings_action_row(p, "Add quick button", "Name + G-code");
        settings_bind_menu_click(add, mac_add_cb, NULL);
    } else {
        settings_note(p, "All 4 custom buttons used. Edit one to change or free a slot.");
    }

    lv_obj_t *arr = settings_action_row(p, "Arrange on dashboard", "Choose what each slot shows");
    settings_bind_menu_click(arr, qbtn_edit_cb, NULL);
}

static void dashboard_reset_cb(void)
{
    static const uint8_t qbtn_defaults[] = {0, 2, 3, 4};
    modulus_nvs_set_u8("cnc_unit", 1);
    modulus_nvs_set_u8("cnc_axes", 1);
    modulus_nvs_set_u8("cnc_wcs", 0);
    modulus_nvs_set_u8("cnc_jmode", 0);
    modulus_nvs_set_u8("cnc_encdiv", 2);
    modulus_nvs_set_u16("cnc_jogspd", 1000);
    modulus_nvs_set_u8("cnc_contpct", 100);
    modulus_nvs_set_u8("cnc_stepacc", 0);
    modulus_nvs_set_u8("cnc_mpgpol", 0);
    modulus_nvs_set_u8("jog_coal_ms", 20);
    modulus_nvs_set_u8("jog_pend_max", 32);
    modulus_nvs_set_str("cnc_incr", "0.001,0.01,0.1,1.0");
    modulus_nvs_set_str("cnc_macro", "");
    for (int i = 0; i < 4; i++) {
        char key[12];
        snprintf(key, sizeof(key), "cnc_qbtn%d", i);
        modulus_nvs_set_u8(key, qbtn_defaults[i]);
        settings_macro_slot_clear((uint8_t)i);
    }
    modulus_zig_set_jog_mode(0);
    modulus_zig_set_wcs(0);
    modulus_zig_set_units_mm(1);
    modulus_zig_encoder_reload_settings();
    modulus_zig_reload_machine_limits();
    modulus_ui_dashboard_config_changed();
    modulus_ui_settings_build_dashboard_tab();
}

void modulus_ui_settings_build_dashboard_tab(void)
{
    lv_obj_t *p = modulus_ui_settings_tab_panel(MOD_UI_SETTINGS_TAB_DASHBOARD);
    if (!p) {
        return;
    }
    lv_obj_clean(p);

    char incr[64];
    if (!modulus_nvs_get_str("cnc_incr", incr, sizeof(incr))) {
        snprintf(incr, sizeof(incr), "0.001,0.01,0.1,1.0");
    }

    settings_section(p, "Jog increments", NULL);
    settings_detail_row(p, "Current", incr);
    lv_obj_t *ed = settings_action_row(p, "Edit increments", "");
    settings_bind_menu_click(ed, incr_edit_cb, NULL);

    uint8_t jmode = modulus_nvs_get_u8("cnc_jmode", 0);
    if (jmode > 2) {
        jmode = 0;
    }
    {
        static const char *const k_jm_lbl[] = {"Step", "Cont", "Velo"};
        lv_obj_t *row = settings_row_base(p, 64, false);
        settings_row_label(row, "Jog mode");
        lv_obj_t *seg = modulus_ui_segmented_create(row, k_jm_lbl, 3, 82, dash_jmode_seg_cb, NULL);
        modulus_ui_segmented_set_selected(seg, jmode);
    }

    settings_section(p, "Active axes", NULL);
    {
        /* Highlighted button = number of axes shown on the DRO (XYZ default). */
        static const char *const k_ax_lbl[] = {"2", "3", "4", "5", "6"};
        const uint8_t ax_preset = modulus_ui_axes_preset_normalize(modulus_nvs_get_u8("cnc_axes", 1));
        lv_obj_t *row = settings_row_base(p, 64, false);
        settings_row_label(row, "Axes");
        lv_obj_t *seg = modulus_ui_segmented_create(row, k_ax_lbl, 5, 56, dash_axes_seg_cb, NULL);
        modulus_ui_segmented_set_selected(seg, ax_preset < 5 ? ax_preset : 1);
    }

    settings_section(p, "Work coordinate system", NULL);
    uint8_t wcs = modulus_nvs_get_u8("cnc_wcs", 0);
    if (wcs > 5) {
        wcs = 0;
    }
    lv_obj_t *wcs_dd = settings_dropdown_row(p, "WCS", "G54\nG55\nG56\nG57\nG58\nG59", wcs);
    lv_obj_add_event_cb(wcs_dd, dash_wcs_cb, LV_EVENT_VALUE_CHANGED, NULL);
    {
        const uint8_t lock = modulus_nvs_get_u8("wcs_lock", 0);
        uint8_t locked = 0;
        for (uint8_t i = 0; i < 6; i++) {
            if (lock & (1U << i)) {
                locked++;
            }
        }
        char detail[40];
        if (locked == 0) {
            snprintf(detail, sizeof(detail), "None locked");
        } else {
            snprintf(detail, sizeof(detail), "%u locked", (unsigned)locked);
        }
        lv_obj_t *wcs_edit = settings_action_row(p, "WCS lock & names", detail);
        settings_bind_menu_click(wcs_edit, dash_wcs_edit_cb, NULL);
    }

    settings_section(p, "Confirm policy", "Never / Always / When running.");
    {
        static const char *const opts = "Never\nAlways\nWhen running";
        static const struct {
            const char *label;
            const char *key;
            uint8_t def;
        } rows[] = {
            { "Cycle start", "cnf_cycle", 0 },
            { "Spindle start", "cnf_spin", 0 },
            { "Zero axes", "cnf_zero", 2 },
            { "Home", "cnf_home", 0 },
            { "Macros", "cnf_mac", 0 },
        };
        for (unsigned i = 0; i < sizeof(rows) / sizeof(rows[0]); i++) {
            uint8_t cur = modulus_nvs_get_u8(rows[i].key, rows[i].def);
            if (cur > 2) {
                cur = rows[i].def;
            }
            lv_obj_t *dd = settings_dropdown_row(p, rows[i].label, opts, cur);
            lv_obj_add_event_cb(dd, dash_cnf_cb, LV_EVENT_VALUE_CHANGED, (void *)rows[i].key);
        }
    }

    settings_section(p, "Jog coalesce", "Limits handwheel $J= flood.");
    {
        uint8_t coal = modulus_nvs_get_u8("jog_coal_ms", 20);
        if (coal > 100) {
            coal = 100;
        }
        lv_obj_t *csl = settings_slider_row(p, "Coalesce window (ms)", coal, 0, 100);
        lv_obj_add_event_cb(csl, dash_coal_cb, LV_EVENT_VALUE_CHANGED, NULL);
        lv_obj_add_event_cb(csl, dash_coal_cb, LV_EVENT_RELEASED, NULL);
        uint8_t pend = modulus_nvs_get_u8("jog_pend_max", 32);
        if (pend < 4) {
            pend = 4;
        }
        if (pend > 64) {
            pend = 64;
        }
        lv_obj_t *psl = settings_slider_row(p, "Max pending STEP detents", pend, 4, 64);
        lv_obj_add_event_cb(psl, dash_pend_cb, LV_EVENT_VALUE_CHANGED, NULL);
        lv_obj_add_event_cb(psl, dash_pend_cb, LV_EVENT_RELEASED, NULL);
    }

    settings_section(p, "Handwheel / MPG", NULL);
    uint8_t encdiv = modulus_nvs_get_u8("cnc_encdiv", 2);
    if (encdiv < 1) {
        encdiv = 1;
    }
    if (encdiv > 16) {
        encdiv = 16;
    }
    lv_obj_t *enc = settings_slider_row(p, "Encoder counts/step", encdiv, 1, 16);
    lv_obj_add_event_cb(enc, dash_encdiv_cb, LV_EVENT_VALUE_CHANGED, NULL);
    lv_obj_add_event_cb(enc, dash_encdiv_cb, LV_EVENT_RELEASED, NULL);

    {
        const uint16_t jogspd = modulus_nvs_get_u16("cnc_jogspd", 1000);
        lv_obj_t *js = settings_dropdown_row(p, "Max jog feed (mm/min)",
                                             "500\n1000\n2000\n3000\n5000\n8000\n10000",
                                             jogspd_to_idx(jogspd));
        lv_obj_add_event_cb(js, dash_jogspd_cb, LV_EVENT_VALUE_CHANGED, NULL);
        settings_note(p, "Handwheel $J= feed cap.");
    }

    uint8_t contpct = modulus_nvs_get_u8("cnc_contpct", 100);
    if (contpct < 10) {
        contpct = 10;
    }
    if (contpct > 200) {
        contpct = 200;
    }
    lv_obj_t *cpc = settings_slider_row(p, "CONT speed rate %", contpct, 10, 200);
    lv_obj_add_event_cb(cpc, dash_contpct_cb, LV_EVENT_VALUE_CHANGED, NULL);
    lv_obj_add_event_cb(cpc, dash_contpct_cb, LV_EVENT_RELEASED, NULL);
    settings_note(p, "Scales CONT feed. VELO uses wheel velocity only.");

    lv_obj_t *acc = settings_toggle_row(p, "STEP accuracy mode",
                                        modulus_nvs_get_u8("cnc_stepacc", 0) != 0);
    lv_obj_add_event_cb(acc, dash_stepacc_cb, LV_EVENT_VALUE_CHANGED, NULL);
    settings_note(p, "1:1 wheel distance - detents are never dropped.");

    dash_build_quick_buttons_section(p);

    settings_section(p, "MPG direction", NULL);
    {
        const uint8_t pol = modulus_nvs_get_u8("cnc_mpgpol", 0);
        uint8_t n = 0;
        const uint8_t axes = modulus_ui_axes_visible_count(modulus_nvs_get_u8("cnc_axes", 1));
        for (uint8_t i = 0; i < axes && i < 6; i++) {
            if (pol & (1U << i)) {
                n++;
            }
        }
        char detail[24];
        if (n == 0) {
            snprintf(detail, sizeof(detail), "None inverted");
        } else {
            snprintf(detail, sizeof(detail), "%u inverted", (unsigned)n);
        }
        lv_obj_t *mpg_row = settings_action_row(p, "MPG direction", detail);
        settings_bind_menu_click(mpg_row, dash_mpg_edit_cb, NULL);
    }

    settings_section(p, "Probe", NULL);
    {
        const uint16_t zoff = modulus_nvs_get_u16("pb_zoff", 100);
        char detail[24];
        snprintf(detail, sizeof(detail), "%.1f mm plate", (double)zoff / 10.0);
        lv_obj_t *probe_row = settings_action_row(p, "Probe Z-plate", detail);
        settings_bind_menu_click(probe_row, dash_probe_cb, NULL);
    }

    settings_section(p, "Handwheel reference", NULL);
    if (s_hw_ref_exp) {
        settings_detail_row(p, "To jog \xE2\x91\xA0", "Tap an axis card (X/Y/Z) on the dashboard");
        settings_detail_row(p, "To jog \xE2\x91\xA1", "Tap the MPG badge on the status bar");
        settings_detail_row(p, "To jog \xE2\x91\xA2", "Turn the wheel - moves the selected axis");
        settings_detail_row(p, "Distance/detent", "Step size x Encoder counts/step");
        settings_detail_row(p, "Machine state", "Must be Idle (clear Alarm/Hold first)");
        settings_detail_row(p, "Port A Grove", "I2C1 SDA G53 / SCL G54");
        settings_detail_row(p, "Unit address", "0x59 ExtEncoder");
        settings_detail_row(p, "Power", "Enable EXT 5V in Power settings");
        settings_expandable_link(p, "Hide handwheel reference", "Show handwheel reference",
                                 &s_hw_ref_exp, modulus_ui_settings_build_dashboard_tab);
    } else {
        settings_expandable_link(p, "Show handwheel reference", "Hide handwheel reference",
                                 &s_hw_ref_exp, modulus_ui_settings_build_dashboard_tab);
    }

    settings_section(p, "Units", NULL);
    lv_obj_t *unit = settings_toggle_row(p, "Metric (mm)", modulus_nvs_get_u8("cnc_unit", 1) != 0);
    lv_obj_add_event_cb(unit, dash_unit_cb, LV_EVENT_VALUE_CHANGED, NULL);

    settings_section(p, "Related settings", NULL);
    settings_link_tab_row(p, "Machine", "", 7);
    settings_link_tab_row(p, "CNC connection", "", 0);
    settings_link_tab_row(p, "Display & Theme", "Left-handed layout", 2);

    static settings_reset_ctx_t dash_reset = {
        .title = "Reset dashboard defaults?",
        .body = "Restores jog, axes, WCS, units, quick buttons, and handwheel tuning.",
        .fn = dashboard_reset_cb,
    };
    settings_reset_row(p, "Reset dashboard & handwheel", &dash_reset);
    modulus_ui_settings_note_tab_built(MOD_UI_SETTINGS_TAB_DASHBOARD);
}

void modulus_ui_settings_dashboard_tab_stop(void)
{
    settings_wcs_modal_hide();
    settings_mpg_modal_hide();
    settings_probe_modal_hide();
}

void settings_dashboard_kb_theme_refresh(void)
{
    /* WCS names keyboard lives in settings_wcs_modal; theme via settings_modals. */
}
