#include "ui_settings_wireless_priv.h"
#include "ui_settings_common.h"
#include "ui_touch_sound.h"
#include "audio_shim.h"
#include "nvs_shim.h"
#include "wireless_shim.h"
#include "transport_shim.h"
#include "cnc_cmd_exports.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

lv_obj_t *wl_modal_action_row(lv_obj_t *card, const char *ok_label,
                              lv_event_cb_t cancel_cb, lv_event_cb_t ok_cb)
{
    lv_obj_t *row = modulus_ui_dialog_actions(card, true);
    lv_obj_t *cancel = modulus_ui_dialog_action_btn(row, "Cancel", MOD_UI_DIALOG_BTN_TONAL,
                                                    cancel_cb, NULL);
    lv_obj_t *ok = modulus_ui_dialog_action_btn(row, ok_label ? ok_label : "OK",
                                                MOD_UI_DIALOG_BTN_FILLED, ok_cb, NULL);
    modulus_ui_suppress_touch_tick(cancel);
    modulus_ui_suppress_touch_tick(ok);
    return row;
}

static void wl_theme_modal_card(lv_obj_t *modal)
{
    if (!modal) {
        return;
    }
    modulus_ui_apply_overlay_scrim(modal);
    lv_obj_t *card = lv_obj_get_child(modal, 0);
    if (!card) {
        return;
    }
    lv_obj_set_style_bg_color(card, modulus_ui_color_surface_container_highest(), 0);
    lv_obj_set_style_border_color(card, modulus_ui_color_outline_variant(), 0);
}

void modulus_ui_wireless_theme_refresh(void)
{
    if (wl_connect_kb) {
        modulus_ui_apply_keyboard_theme(wl_connect_kb);
    }
    if (wl_bt_pk_kb) {
        modulus_ui_apply_keyboard_theme(wl_bt_pk_kb);
    }
    if (wl_en_mac_kb) {
        modulus_ui_apply_keyboard_theme(wl_en_mac_kb);
    }
    if (wl_zb_add_kb) {
        modulus_ui_apply_keyboard_theme(wl_zb_add_kb);
    }
    if (wl_th_add_kb) {
        modulus_ui_apply_keyboard_theme(wl_th_add_kb);
    }

    modulus_ui_apply_textarea_theme(wl_connect_ta, false);
    modulus_ui_apply_textarea_theme(wl_bt_pk_ta, false);
    modulus_ui_apply_textarea_theme(wl_en_mac_ta, false);
    modulus_ui_apply_textarea_theme(wl_zb_name_ta, false);
    modulus_ui_apply_textarea_theme(wl_zb_ieee_ta, false);
    modulus_ui_apply_textarea_theme(wl_zb_code_ta, false);
    modulus_ui_apply_textarea_theme(wl_th_name_ta, false);
    modulus_ui_apply_textarea_theme(wl_th_ext_ta, false);

    wl_theme_modal_card(wl_connect_modal);
    wl_theme_modal_card(wl_bt_pk_modal);
    wl_theme_modal_card(wl_en_mac_modal);
    wl_theme_modal_card(wl_zb_add_modal);
    wl_theme_modal_card(wl_th_add_modal);
}
