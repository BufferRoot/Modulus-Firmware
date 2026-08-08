#include "ui_settings_modals_priv.h"
#include "ui_settings_modal_kb.h"
#include "ui_settings_common.h"
#include "ui_settings_priv.h"
#include "ui_internal.h"
#include "ui_touch_sound.h"
#include "nvs_shim.h"
#include "security_shim.h"
#include "audio_shim.h"

#include <stdio.h>
#include <string.h>

static lv_obj_t *s_pin_modal = NULL;
static lv_obj_t *s_pin_kb = NULL;
static lv_obj_t *s_pin_ta1 = NULL;
static lv_obj_t *s_pin_ta2 = NULL;
static lv_obj_t *s_pin_status = NULL;
static uint8_t s_pin_mode = 0; /* 0=set/change 1=clear */

static void pin_ta_focus_cb(lv_event_t *e)
{
    if (s_pin_kb) {
        lv_keyboard_set_textarea(s_pin_kb, lv_event_get_target(e));
    }
}

static bool pin_digits_valid(const char *pin)
{
    if (!pin) {
        return false;
    }
    const size_t len = strlen(pin);
    if (len < 4 || len > 8) {
        return false;
    }
    for (size_t i = 0; i < len; i++) {
        if (pin[i] < '0' || pin[i] > '9') {
            return false;
        }
    }
    return true;
}

static void pin_set_status(const char *msg, bool error)
{
    if (!s_pin_status || !msg) {
        return;
    }
    lv_label_set_text(s_pin_status, msg);
    lv_obj_set_style_text_color(s_pin_status,
                                error ? modulus_ui_color_error()
                                      : modulus_ui_color_on_surface_variant(),
                                0);
}

void settings_pin_modal_hide(void)
{
    if (!s_pin_modal) {
        s_pin_kb = NULL;
        s_pin_ta1 = NULL;
        s_pin_ta2 = NULL;
        s_pin_status = NULL;
        return;
    }
    s_pin_kb = NULL;
    s_pin_ta1 = NULL;
    s_pin_ta2 = NULL;
    s_pin_status = NULL;
    modulus_ui_dialog_scrim_hide_animated(&s_pin_modal);
}

static void pin_close_cb(lv_event_t *e)
{
    (void)e;
    modulus_audio_play_ui(0);
    settings_pin_modal_hide();
}

static void pin_save_cb(lv_event_t *e)
{
    (void)e;
    if (!s_pin_ta1) {
        return;
    }
    const char *p1 = lv_textarea_get_text(s_pin_ta1);
    if (s_pin_mode == 1) {
        if (!pin_digits_valid(p1)) {
            pin_set_status("Enter your current PIN", true);
            modulus_audio_play_ui(2);
            return;
        }
        if (!modulus_security_clear_pin(p1)) {
            pin_set_status("Incorrect PIN", true);
            modulus_audio_play_ui(2);
            return;
        }
        modulus_audio_play_ui(1);
        settings_pin_modal_hide();
        modulus_ui_snackbar_show("PIN cleared", 2500);
        modulus_ui_settings_build_security_tab();
        return;
    }
    if (!s_pin_ta2) {
        return;
    }
    const char *p2 = lv_textarea_get_text(s_pin_ta2);
    if (!pin_digits_valid(p1) || !pin_digits_valid(p2)) {
        pin_set_status("PIN must be 4-8 digits", true);
        modulus_audio_play_ui(2);
        return;
    }
    if (strcmp(p1, p2) != 0) {
        pin_set_status("PIN entries must match", true);
        modulus_audio_play_ui(2);
        return;
    }
    if (!modulus_security_set_pin(p1)) {
        pin_set_status("Could not store PIN", true);
        modulus_audio_play_ui(2);
        return;
    }
    modulus_audio_play_ui(1);
    settings_pin_modal_hide();
    modulus_ui_snackbar_show("PIN saved", 2500);
    modulus_ui_settings_build_security_tab();
}

static void pin_modal_open(const char *title, bool two_field, uint8_t mode)
{
    settings_pin_modal_hide();
    s_pin_mode = mode;

    s_pin_modal = modulus_ui_dialog_scrim_create();

    lv_obj_t *card = modulus_ui_dialog_card_create(s_pin_modal, MOD_UI_DIALOG_W_COMPACT, 0);
    lv_obj_align(card, LV_ALIGN_TOP_MID, 0, 40);
    modulus_ui_motion_dialog_enter(card);
    modulus_ui_dialog_scrim_bind_dismiss(s_pin_modal, pin_close_cb, NULL);

    modulus_ui_dialog_header(card, title, pin_close_cb, NULL);

    s_pin_status = lv_label_create(card);
    lv_label_set_text(s_pin_status, "");
    lv_obj_set_style_text_color(s_pin_status, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(s_pin_status, MOD_UI_FONT_BODY_M, 0);
    lv_obj_set_width(s_pin_status, lv_pct(100));
    lv_label_set_long_mode(s_pin_status, LV_LABEL_LONG_WRAP);

    lv_obj_t *lbl1 = lv_label_create(card);
    lv_label_set_text(lbl1, two_field ? "New PIN (4-8 digits):" : "Current PIN:");
    lv_obj_set_style_text_color(lbl1, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(lbl1, MOD_UI_FONT_BODY_M, 0);

    s_pin_ta1 = lv_textarea_create(card);
    lv_textarea_set_one_line(s_pin_ta1, true);
    lv_textarea_set_password_mode(s_pin_ta1, true);
    lv_textarea_set_max_length(s_pin_ta1, 8);
    lv_textarea_set_accepted_chars(s_pin_ta1, "0123456789");
    lv_obj_set_width(s_pin_ta1, lv_pct(100));
    modulus_ui_apply_textarea_theme(s_pin_ta1, false);
    lv_obj_add_event_cb(s_pin_ta1, pin_ta_focus_cb, LV_EVENT_FOCUSED, NULL);

    if (two_field) {
        lv_obj_t *lbl2 = lv_label_create(card);
        lv_label_set_text(lbl2, "Confirm PIN");
        lv_obj_set_style_text_color(lbl2, modulus_ui_color_on_surface_variant(), 0);
        lv_obj_set_style_text_font(lbl2, MOD_UI_FONT_BODY_M, 0);

        s_pin_ta2 = lv_textarea_create(card);
        lv_textarea_set_one_line(s_pin_ta2, true);
        lv_textarea_set_password_mode(s_pin_ta2, true);
        lv_textarea_set_max_length(s_pin_ta2, 8);
        lv_textarea_set_accepted_chars(s_pin_ta2, "0123456789");
        lv_obj_set_width(s_pin_ta2, lv_pct(100));
        modulus_ui_apply_textarea_theme(s_pin_ta2, false);
        lv_obj_add_event_cb(s_pin_ta2, pin_ta_focus_cb, LV_EVENT_FOCUSED, NULL);
    }

    lv_obj_t *row = modulus_ui_dialog_actions(card, true);
    lv_obj_t *cancel =
        modulus_ui_dialog_action_btn(row, "Cancel", MOD_UI_DIALOG_BTN_TONAL, pin_close_cb, NULL);
    modulus_ui_suppress_touch_tick(cancel);
    lv_obj_t *save = modulus_ui_dialog_action_btn(row, mode == 1 ? "Clear" : "Save",
                                                   mode == 1 ? MOD_UI_DIALOG_BTN_DESTRUCTIVE
                                                             : MOD_UI_DIALOG_BTN_FILLED,
                                                   pin_save_cb, NULL);
    modulus_ui_suppress_touch_tick(save);

    s_pin_kb = lv_keyboard_create(s_pin_modal);
    lv_keyboard_set_mode(s_pin_kb, LV_KEYBOARD_MODE_NUMBER);
    settings_modal_kb_configure_number(s_pin_kb);
    lv_keyboard_set_textarea(s_pin_kb, s_pin_ta1);
}

void settings_pin_modal_show_set(void)
{
    pin_modal_open("Set PIN", true, 0);
}

void settings_pin_modal_show_change(void)
{
    pin_modal_open("Change PIN", true, 0);
}

void settings_pin_modal_show_clear(void)
{
    pin_modal_open("Clear PIN", false, 1);
}

void settings_pin_modal_theme_refresh(void)
{
    if (s_pin_kb) {
        modulus_ui_apply_keyboard_theme(s_pin_kb);
    }
    if (s_pin_ta1) {
        modulus_ui_apply_textarea_theme(s_pin_ta1, false);
    }
    if (s_pin_ta2) {
        modulus_ui_apply_textarea_theme(s_pin_ta2, false);
    }
    if (!s_pin_modal) {
        return;
    }
    modulus_ui_dialog_theme_refresh(s_pin_modal);
    if (s_pin_status) {
        const char *txt = lv_label_get_text(s_pin_status);
        const bool err = txt && txt[0] != '\0' &&
                         (strstr(txt, "Incorrect") != NULL || strstr(txt, "must") != NULL ||
                          strstr(txt, "match") != NULL || strstr(txt, "Could not") != NULL);
        lv_obj_set_style_text_color(s_pin_status,
                                    err ? modulus_ui_color_error()
                                        : modulus_ui_color_on_surface_variant(),
                                    0);
    }
}
