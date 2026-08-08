#include "ui_settings_modals_priv.h"
#include "ui_settings_modal_kb.h"
#include "ui_settings_common.h"
#include "ui_settings_priv.h"
#include "ui_internal.h"
#include "nvs_shim.h"

#include <stdio.h>
#include <string.h>

static lv_obj_t *s_wcs_modal = NULL;
static lv_obj_t *s_wcs_kb = NULL;
static lv_obj_t *s_wcs_ta[6];

static const char *const k_name_keys[] = {
    "wcs_n0", "wcs_n1", "wcs_n2", "wcs_n3", "wcs_n4", "wcs_n5",
};

void settings_wcs_modal_hide(void)
{
    if (!s_wcs_modal) {
        s_wcs_kb = NULL;
        memset(s_wcs_ta, 0, sizeof(s_wcs_ta));
        return;
    }
    s_wcs_kb = NULL;
    memset(s_wcs_ta, 0, sizeof(s_wcs_ta));
    modulus_ui_dialog_scrim_hide_animated(&s_wcs_modal);
}

static void wcs_close_cb(lv_event_t *e)
{
    (void)e;
    for (int i = 0; i < 6; i++) {
        if (s_wcs_ta[i]) {
            const char *txt = lv_textarea_get_text(s_wcs_ta[i]);
            if (txt) {
                modulus_nvs_set_str(k_name_keys[i], txt);
            }
        }
    }
    settings_wcs_modal_hide();
    modulus_ui_snackbar_show("WCS names saved", 2000);
    modulus_ui_settings_build_dashboard_tab();
}

static void wcs_lock_cb(lv_event_t *e)
{
    lv_obj_t *sw = lv_event_get_target(e);
    const int bit = (int)(intptr_t)lv_obj_get_user_data(sw);
    const bool on = lv_obj_has_state(sw, LV_STATE_CHECKED);
    uint8_t lock = modulus_nvs_get_u8("wcs_lock", 0);
    if (on) {
        lock |= (uint8_t)(1U << bit);
    } else {
        lock &= (uint8_t)~(1U << bit);
    }
    modulus_nvs_set_u8("wcs_lock", lock);
}

static void wcs_name_save_cb(lv_event_t *e)
{
    const int idx = (int)(intptr_t)lv_event_get_user_data(e);
    if (idx < 0 || idx > 5 || !s_wcs_ta[idx]) {
        return;
    }
    const char *txt = lv_textarea_get_text(s_wcs_ta[idx]);
    if (txt) {
        modulus_nvs_set_str(k_name_keys[idx], txt);
    }
}

static void wcs_ta_focus_cb(lv_event_t *e)
{
    if (s_wcs_kb) {
        lv_keyboard_set_textarea(s_wcs_kb, lv_event_get_target(e));
    }
}

void settings_wcs_modal_show(void)
{
    settings_wcs_modal_hide();

    s_wcs_modal = modulus_ui_dialog_scrim_create();

    lv_obj_t *card = modulus_ui_dialog_card_create(s_wcs_modal, MOD_UI_DIALOG_W_WIDE, 0);
    settings_modal_fit_card_above_kb(card);
    modulus_ui_motion_dialog_enter(card);
    modulus_ui_dialog_scrim_bind_dismiss(s_wcs_modal, wcs_close_cb, NULL);

    modulus_ui_dialog_header(card, "WCS lock & names", wcs_close_cb, NULL);
    modulus_ui_dialog_supporting(card, "Locked WCS asks before change on status bar.");

    lv_obj_t *body = lv_obj_create(card);
    lv_obj_remove_style_all(body);
    lv_obj_set_width(body, lv_pct(100));
    lv_obj_set_height(body, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(body, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(body, MOD_UI_SPACE_SM, 0);
    settings_no_scroll(body);

    static const char *const k_lock_lbl[] = {
        "Lock G54", "Lock G55", "Lock G56", "Lock G57", "Lock G58", "Lock G59",
    };
    static const char *const k_name_lbl[] = {
        "Name G54", "Name G55", "Name G56", "Name G57", "Name G58", "Name G59",
    };

    const uint8_t lock = modulus_nvs_get_u8("wcs_lock", 0);
    settings_section(body, "Locks", NULL);
    for (uint8_t i = 0; i < 6; i++) {
        lv_obj_t *sw = settings_toggle_row(body, k_lock_lbl[i], (lock & (1U << i)) != 0);
        lv_obj_set_user_data(sw, (void *)(intptr_t)i);
        lv_obj_add_event_cb(sw, wcs_lock_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }

    settings_section(body, "Custom names", "ASCII, up to 15 characters.");
    for (uint8_t i = 0; i < 6; i++) {
        char cur[16];
        if (!modulus_nvs_get_str(k_name_keys[i], cur, sizeof(cur))) {
            cur[0] = '\0';
        }
        s_wcs_ta[i] = settings_text_input_row(body, k_name_lbl[i], cur, 15, NULL);
        lv_obj_add_event_cb(s_wcs_ta[i], wcs_ta_focus_cb, LV_EVENT_FOCUSED, NULL);
        lv_obj_add_event_cb(s_wcs_ta[i], wcs_name_save_cb, LV_EVENT_DEFOCUSED,
                            (void *)(intptr_t)i);
    }

    lv_obj_t *row = modulus_ui_dialog_actions(card, true);
    modulus_ui_dialog_action_btn(row, "Done", MOD_UI_DIALOG_BTN_FILLED, wcs_close_cb, NULL);

    s_wcs_kb = lv_keyboard_create(s_wcs_modal);
    lv_keyboard_set_mode(s_wcs_kb, LV_KEYBOARD_MODE_TEXT_LOWER);
    settings_modal_kb_configure_text(s_wcs_kb);
    if (s_wcs_ta[0]) {
        lv_keyboard_set_textarea(s_wcs_kb, s_wcs_ta[0]);
    }
}

void settings_wcs_modal_theme_refresh(void)
{
    if (s_wcs_kb) {
        modulus_ui_apply_keyboard_theme(s_wcs_kb);
    }
    for (int i = 0; i < 6; i++) {
        if (s_wcs_ta[i]) {
            modulus_ui_apply_textarea_theme(s_wcs_ta[i], false);
        }
    }
    modulus_ui_dialog_theme_refresh(s_wcs_modal);
}
