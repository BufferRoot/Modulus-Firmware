#include "ui_settings_modals_priv.h"
#include "ui_settings_modal_kb.h"
#include "ui_settings_common.h"
#include "ui_settings_priv.h"
#include "ui_internal.h"
#include "ui_touch_sound.h"
#include "nvs_shim.h"
#include "security_shim.h"
#include "audio_shim.h"
#include "cnc_cmd_exports.h"
#include "ui_quick_grid.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static lv_obj_t *s_incr_modal = NULL;
static lv_obj_t *s_incr_ta = NULL;
static lv_obj_t *s_incr_kb = NULL;

static void incr_exit_ready(lv_anim_t *a)
{
    lv_obj_t *dlg = lv_anim_get_user_data(a);
    if (dlg) {
        lv_obj_delete(dlg);
    }
    s_incr_ta = NULL;
    s_incr_kb = NULL;
}

void settings_incr_modal_hide(void)
{
    if (!s_incr_modal) {
        s_incr_ta = NULL;
        s_incr_kb = NULL;
        return;
    }
    lv_obj_t *dlg = s_incr_modal;
    s_incr_modal = NULL;
    s_incr_ta = NULL;
    s_incr_kb = NULL;
    lv_obj_t *card = lv_obj_get_child(dlg, 0);
    if (card && modulus_ui_motion_smooth()) {
        modulus_ui_motion_dialog_exit(card, incr_exit_ready, dlg);
        return;
    }
    lv_obj_delete(dlg);
}

static void incr_close_cb(lv_event_t *e)
{
    (void)e;
    settings_incr_modal_hide();
}

static void incr_save_cb(lv_event_t *e)
{
    (void)e;
    if (!s_incr_ta) {
        return;
    }
    modulus_nvs_set_str("cnc_incr", lv_textarea_get_text(s_incr_ta));
    settings_incr_modal_hide();
    modulus_zig_encoder_reload_settings();
    modulus_ui_dashboard_config_changed();
    modulus_ui_settings_build_dashboard_tab();
}

static void incr_ta_focus_cb(lv_event_t *e)
{
    if (s_incr_kb) {
        lv_keyboard_set_textarea(s_incr_kb, lv_event_get_target(e));
    }
}

void settings_incr_modal_show(void)
{
    settings_incr_modal_hide();
    char buf[64];
    if (!modulus_nvs_get_str("cnc_incr", buf, sizeof(buf))) {
        snprintf(buf, sizeof(buf), "0.001,0.01,0.1,1.0");
    }

    s_incr_modal = modulus_ui_dialog_scrim_create();

    lv_obj_t *card = modulus_ui_dialog_card_create(s_incr_modal, MOD_UI_DIALOG_W_STANDARD, 0);
    settings_modal_fit_card_above_kb(card);
    modulus_ui_motion_dialog_enter(card);

    modulus_ui_dialog_header(card, "Edit jog increments", incr_close_cb, NULL);
    modulus_ui_dialog_scrim_bind_dismiss(s_incr_modal, incr_close_cb, NULL);
    modulus_ui_dialog_supporting(card, "Four comma-separated values in mm.");

    s_incr_ta = lv_textarea_create(card);
    lv_textarea_set_text(s_incr_ta, buf);
    lv_textarea_set_one_line(s_incr_ta, true);
    lv_textarea_set_max_length(s_incr_ta, 63);
    lv_obj_set_width(s_incr_ta, lv_pct(100));
    modulus_ui_apply_textarea_theme(s_incr_ta, false);
    lv_obj_add_event_cb(s_incr_ta, incr_ta_focus_cb, LV_EVENT_FOCUSED, NULL);

    lv_obj_t *row = modulus_ui_dialog_actions(card, true);
    modulus_ui_dialog_action_btn(row, "Cancel", MOD_UI_DIALOG_BTN_TONAL, incr_close_cb, NULL);
    modulus_ui_dialog_action_btn(row, "Save", MOD_UI_DIALOG_BTN_FILLED, incr_save_cb, NULL);

    s_incr_kb = lv_keyboard_create(s_incr_modal);
    lv_keyboard_set_mode(s_incr_kb, LV_KEYBOARD_MODE_TEXT_LOWER);
    settings_modal_kb_configure_text(s_incr_kb);
    lv_keyboard_set_textarea(s_incr_kb, s_incr_ta);
}

void settings_incr_modal_theme_refresh(void)
{
    if (s_incr_kb) {
        modulus_ui_apply_keyboard_theme(s_incr_kb);
    }
    if (s_incr_ta) {
        modulus_ui_apply_textarea_theme(s_incr_ta, false);
    }
    modulus_ui_dialog_theme_refresh(s_incr_modal);
}
