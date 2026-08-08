#include "ui_settings_modals_priv.h"
#include "ui_settings_common.h"
#include "ui_settings_priv.h"
#include "ui_internal.h"
#include "nvs_shim.h"
#include "cnc_cmd_exports.h"
#include "ui_axes_preset.h"

#include <stdint.h>

static lv_obj_t *s_mpg_modal = NULL;

static const char *k_mpg_pol_axes[] = {
    "X Inverted", "Y Inverted", "Z Inverted",
    "A Inverted", "B Inverted", "C Inverted",
};

void settings_mpg_modal_hide(void)
{
    if (!s_mpg_modal) {
        return;
    }
    modulus_ui_dialog_scrim_hide_animated(&s_mpg_modal);
}

static void mpg_close_cb(lv_event_t *e)
{
    (void)e;
    settings_mpg_modal_hide();
}

static void mpg_pol_cb(lv_event_t *e)
{
    lv_obj_t *sw = lv_event_get_target(e);
    const int bit = (int)(intptr_t)lv_obj_get_user_data(sw);
    const bool on = lv_obj_has_state(sw, LV_STATE_CHECKED);
    uint8_t pol = modulus_nvs_get_u8("cnc_mpgpol", 0);
    if (on) {
        pol |= (uint8_t)(1U << bit);
    } else {
        pol &= (uint8_t)~(1U << bit);
    }
    modulus_nvs_set_u8("cnc_mpgpol", pol);
    modulus_zig_encoder_reload_settings();
}

void settings_mpg_modal_show(void)
{
    settings_mpg_modal_hide();

    s_mpg_modal = modulus_ui_dialog_scrim_create();
    lv_obj_t *card = modulus_ui_dialog_card_create(s_mpg_modal, MOD_UI_DIALOG_W_STANDARD, 0);
    modulus_ui_motion_dialog_enter(card);
    modulus_ui_dialog_scrim_bind_dismiss(s_mpg_modal, mpg_close_cb, NULL);

    modulus_ui_dialog_header(card, "MPG direction", mpg_close_cb, NULL);
    modulus_ui_dialog_supporting(card, "Invert handwheel direction per axis.");

    lv_obj_t *body = lv_obj_create(card);
    lv_obj_remove_style_all(body);
    lv_obj_set_width(body, lv_pct(100));
    lv_obj_set_height(body, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(body, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(body, MOD_UI_SPACE_SM, 0);
    settings_no_scroll(body);

    const uint8_t num_active =
        modulus_ui_axes_visible_count(modulus_nvs_get_u8("cnc_axes", 1));
    const uint8_t cur_pol = modulus_nvs_get_u8("cnc_mpgpol", 0);
    for (uint8_t i = 0; i < num_active && i < 6; i++) {
        const bool inv = (cur_pol >> i) & 1U;
        lv_obj_t *sw = settings_toggle_row(body, k_mpg_pol_axes[i], inv);
        lv_obj_set_user_data(sw, (void *)(intptr_t)i);
        lv_obj_add_event_cb(sw, mpg_pol_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }

    lv_obj_t *row = modulus_ui_dialog_actions(card, true);
    modulus_ui_dialog_action_btn(row, "Done", MOD_UI_DIALOG_BTN_FILLED, mpg_close_cb, NULL);
}

void settings_mpg_modal_theme_refresh(void)
{
    modulus_ui_dialog_theme_refresh(s_mpg_modal);
}
