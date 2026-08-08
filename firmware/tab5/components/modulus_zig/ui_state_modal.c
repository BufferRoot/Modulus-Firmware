#include "ui_state_modal.h"
#include "ui_internal.h"
#include "cnc_cmd_exports.h"
#include "audio_shim.h"
#include "zb_automation.h"
#include "shop_recipe.h"

enum {
    k_state_hold = 3,
    k_state_alarm = 5,
};

static const char k_alarm_snack_msg[] =
    "Ensure the MPG is enabled to clear Alarm or to do a Soft Reset";

static lv_obj_t *s_overlay = NULL;
static lv_obj_t *s_title = NULL;
static lv_obj_t *s_body = NULL;
static lv_obj_t *s_primary_lbl = NULL;
static lv_timer_t *s_poll = NULL;
static uint8_t s_shown_for = 0xFF; /* HOLD modal only; 0xFF = none */
static uint8_t s_last_seen = 0xFF;
static uint8_t s_suppress = 0xFF; /* no re-popup until machine leaves this state */

static void overlay_exit_ready(lv_anim_t *a)
{
    lv_obj_t *dlg = lv_anim_get_user_data(a);
    if (dlg) {
        lv_obj_delete(dlg);
    }
    s_title = NULL;
    s_body = NULL;
    s_primary_lbl = NULL;
    s_shown_for = 0xFF;
    modulus_ui_resume_dashboard_refresh();
}

static void hide_modal(void)
{
    if (s_poll) {
        lv_timer_delete(s_poll);
        s_poll = NULL;
    }
    if (!s_overlay) {
        s_title = NULL;
        s_body = NULL;
        s_primary_lbl = NULL;
        s_shown_for = 0xFF;
        return;
    }
    lv_obj_t *dlg = s_overlay;
    s_overlay = NULL;
    s_title = NULL;
    s_body = NULL;
    s_primary_lbl = NULL;
    s_shown_for = 0xFF;
    lv_obj_t *card = lv_obj_get_child(dlg, 0);
    if (card && modulus_ui_motion_smooth()) {
        modulus_ui_motion_dialog_exit(card, overlay_exit_ready, dlg);
        return;
    }
    lv_obj_delete(dlg);
    modulus_ui_resume_dashboard_refresh();
}

void modulus_ui_state_modal_hide(void)
{
    hide_modal();
}

bool modulus_ui_state_modal_visible(void)
{
    return s_overlay != NULL;
}

static void sync_alarm_snackbar(uint8_t state)
{
    if (state == k_state_alarm) {
        if (!modulus_ui_snackbar_is_sticky()) {
            modulus_ui_snackbar_show(k_alarm_snack_msg, 0);
        }
        return;
    }
    if (modulus_ui_snackbar_is_sticky()) {
        modulus_ui_snackbar_hide();
    }
}

static void primary_cb(lv_event_t *e)
{
    (void)e;
    if (s_shown_for != k_state_hold) {
        return;
    }
    if (modulus_zb_door_blocks_cycle() || modulus_recipe_battery_blocks_cycle()) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    s_suppress = k_state_hold;
    hide_modal();
    modulus_zig_cmd_cycle_start();
}

static void dismiss_cb(lv_event_t *e)
{
    (void)e;
    s_suppress = s_shown_for;
    hide_modal();
}

static void poll_cb(lv_timer_t *t)
{
    (void)t;
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    if (s_shown_for == k_state_hold && st.state != k_state_hold) {
        hide_modal();
    }
}

static void show_hold_modal(void)
{
    hide_modal();
    s_shown_for = k_state_hold;
    modulus_ui_pause_dashboard_refresh();

    s_overlay = modulus_ui_dialog_scrim_create();

    lv_obj_t *card = modulus_ui_dialog_card_create(s_overlay, MOD_UI_DIALOG_W_STANDARD, 0);
    lv_obj_center(card);

    lv_obj_t *hdr = modulus_ui_dialog_header(card, "Feed hold", dismiss_cb, NULL);
    modulus_ui_dialog_scrim_bind_dismiss(s_overlay, dismiss_cb, NULL);
    s_title = lv_obj_get_child(hdr, 0);
    s_body = modulus_ui_dialog_supporting(card, "Program paused. Resume when clear.");
    lv_obj_set_style_text_align(s_body, LV_TEXT_ALIGN_CENTER, 0);
    if (s_title) {
        lv_obj_set_style_text_color(s_title, MOD_UI_COLOR_SEMANTIC_HOLD, 0);
    }

    lv_obj_t *row = modulus_ui_dialog_actions(card, false);
    modulus_ui_dialog_action_btn(row, "Dismiss", MOD_UI_DIALOG_BTN_TONAL, dismiss_cb, NULL);
    lv_obj_t *primary =
        modulus_ui_dialog_action_btn(row, "Resume", MOD_UI_DIALOG_BTN_FILLED, primary_cb, NULL);
    s_primary_lbl = lv_obj_get_child(primary, 0);
    lv_obj_set_style_bg_color(primary, MOD_UI_COLOR_SEMANTIC_RESUME, 0);
    if (s_primary_lbl) {
        lv_obj_set_style_text_color(s_primary_lbl, modulus_ui_color_on_tinted_btn(), 0);
    }
    modulus_ui_apply_pressed_state_layer_color(primary, modulus_ui_color_on_tinted_btn());

    modulus_ui_motion_dialog_enter(card);
    s_poll = lv_timer_create(poll_cb, 200, NULL);
}

void modulus_ui_state_modal_update(const modulus_cnc_status_t *st)
{
    if (!st) {
        return;
    }
    const uint8_t cur = st->state;

    /* Alarm: sticky snackbar only — no blocking overlay. Re-assert every tick
     * so a transient snackbar cannot permanently steal the alarm hint. */
    sync_alarm_snackbar(cur);

    if (s_suppress != 0xFF && cur != s_suppress) {
        s_suppress = 0xFF;
    }
    if (cur == s_last_seen) {
        return;
    }
    const uint8_t prev = s_last_seen;
    s_last_seen = cur;

    if (s_shown_for == k_state_hold && cur != k_state_hold) {
        hide_modal();
        return;
    }
    if (s_shown_for != 0xFF) {
        return;
    }

    /* Edge enter Hold only (not while already there at boot). */
    if (prev == 0xFF) {
        return;
    }
    if (cur == s_suppress) {
        return;
    }
    if (cur == k_state_hold && prev != k_state_hold) {
        show_hold_modal();
    }
}

void modulus_ui_state_modal_theme_refresh(void)
{
    if (!s_overlay || s_shown_for != k_state_hold) {
        return;
    }
    show_hold_modal();
}
