#include "ui_settings_modals_priv.h"
#include "ui_settings_common.h"
#include "ui_settings_priv.h"
#include "ui_internal.h"
#include "ui_zero_confirm.h"
#include "nvs_shim.h"
#include "cnc_cmd_exports.h"

#include <stdio.h>

static lv_obj_t *s_probe_modal = NULL;
static lv_obj_t *s_status_lbl = NULL;
static lv_obj_t *s_start_btn = NULL;
static lv_timer_t *s_tmr = NULL;
static bool s_was_busy = false;

void settings_probe_modal_hide(void)
{
    if (s_tmr) {
        lv_timer_delete(s_tmr);
        s_tmr = NULL;
    }
    if (!s_probe_modal) {
        s_status_lbl = NULL;
        s_start_btn = NULL;
        s_was_busy = false;
        return;
    }
    s_status_lbl = NULL;
    s_start_btn = NULL;
    s_was_busy = false;
    modulus_ui_dialog_scrim_hide_animated(&s_probe_modal);
}

static void close_cb(lv_event_t *e)
{
    (void)e;
    if (modulus_zig_probe_busy()) {
        modulus_zig_probe_cancel();
    }
    settings_probe_modal_hide();
}

static void zero_z_apply(void)
{
    modulus_zig_cmd_zero_axis(2);
    modulus_ui_snackbar_show("Z zeroed", 2000);
    modulus_ui_resume_dashboard_refresh();
}

static void zero_z_cancel(void)
{
    modulus_ui_resume_dashboard_refresh();
}

static void offer_zero_z(void)
{
    modulus_ui_pause_dashboard_refresh();
    settings_confirm_show("Zero Z?", "Set current Z as work zero after plate touch-off.",
                          "Zero Z", false, zero_z_apply, zero_z_cancel);
}

static void set_status(const char *txt)
{
    if (s_status_lbl && txt) {
        lv_label_set_text(s_status_lbl, txt);
    }
}

static void poll_cb(lv_timer_t *t)
{
    (void)t;
    const bool busy = modulus_zig_probe_busy() != 0;
    if (busy) {
        s_was_busy = true;
        const bool pin = modulus_zig_probe_pin() != 0;
        set_status(pin ? "Probing... (pin)" : "Probing...");
        if (s_start_btn) {
            modulus_ui_obj_set_disabled_style(s_start_btn, false);
            lv_obj_add_state(s_start_btn, LV_STATE_DISABLED);
        }
        return;
    }
    if (s_was_busy) {
        s_was_busy = false;
        set_status("Complete");
        modulus_ui_snackbar_show("Z-plate probe done", 2500);
        if (s_start_btn) {
            lv_obj_remove_state(s_start_btn, LV_STATE_DISABLED);
            modulus_ui_obj_set_disabled_style(s_start_btn, true);
        }
        offer_zero_z();
        return;
    }
    set_status("Ready");
    if (s_start_btn) {
        lv_obj_remove_state(s_start_btn, LV_STATE_DISABLED);
        modulus_ui_obj_set_disabled_style(s_start_btn, true);
    }
}

static void start_cb(lv_event_t *e)
{
    (void)e;
    if (modulus_zig_probe_busy()) {
        return;
    }
    if (!modulus_zig_probe_start(MODULUS_PROBE_Z_PLATE)) {
        set_status("Failed to start");
        modulus_ui_snackbar_show("Probe start failed", 2500);
        return;
    }
    s_was_busy = true;
    set_status("Probing...");
    modulus_ui_snackbar_show("Z-plate probe started", 2000);
}

void settings_probe_modal_show(void)
{
    settings_probe_modal_hide();

    s_probe_modal = modulus_ui_dialog_scrim_create();
    lv_obj_t *card = modulus_ui_dialog_card_create(s_probe_modal, MOD_UI_DIALOG_W_STANDARD, 0);
    modulus_ui_motion_dialog_enter(card);

    modulus_ui_dialog_header(card, "Probe Z-plate", close_cb, NULL);
    modulus_ui_dialog_supporting(card, "Edge/center cycles: Quick Settings -> Probe.");
    modulus_ui_dialog_scrim_bind_dismiss(s_probe_modal, close_cb, NULL);

    lv_obj_t *body = lv_obj_create(card);
    lv_obj_remove_style_all(body);
    lv_obj_set_width(body, lv_pct(100));
    lv_obj_set_height(body, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(body, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(body, MOD_UI_SPACE_SM, 0);
    settings_no_scroll(body);

    const uint16_t zoff = modulus_nvs_get_u16("pb_zoff", 100);
    char plate[32];
    snprintf(plate, sizeof(plate), "%.1f mm", (double)zoff / 10.0);
    settings_detail_row(body, "Plate thickness", plate);
    s_status_lbl = settings_detail_row(body, "Status", "Ready");

    lv_obj_t *row = modulus_ui_dialog_actions(card, true);
    modulus_ui_dialog_action_btn(row, "Cancel", MOD_UI_DIALOG_BTN_TONAL, close_cb, NULL);
    s_start_btn =
        modulus_ui_dialog_action_btn(row, "Start", MOD_UI_DIALOG_BTN_FILLED, start_cb, NULL);

    s_tmr = lv_timer_create(poll_cb, 200, NULL);
    poll_cb(s_tmr);
}

void settings_probe_modal_theme_refresh(void)
{
    modulus_ui_dialog_theme_refresh(s_probe_modal);
}
