#include "ui_settings_wireless_priv.h"
#include "ui_settings_wireless_kb.h"
#include "ui_settings_common.h"
#include "ui_internal.h"
#include "ui_touch_sound.h"
#include "audio_shim.h"
#include "nvs_shim.h"
#include "wireless_shim.h"
#include "transport_shim.h"
#include "cnc_cmd_exports.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void wl_bt_passkey_modal_hide(void)
{
    if (!wl_bt_pk_modal) {
        wl_bt_pk_kb = NULL;
        wl_bt_pk_ta = NULL;
        wl_bt_pk_hint = NULL;
        return;
    }
    wl_bt_pk_kb = NULL;
    wl_bt_pk_ta = NULL;
    wl_bt_pk_hint = NULL;
    modulus_ui_dialog_scrim_hide_animated(&wl_bt_pk_modal);
}

static void bt_passkey_hide_cb(lv_event_t *e)
{
    (void)e;
    modulus_wireless_ble_passkey_cancel();
    wl_bt_passkey_modal_hide();
    modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
}

static void bt_passkey_ta_focus_cb(lv_event_t *e)
{
    if (wl_bt_pk_kb) {
        lv_keyboard_set_textarea(wl_bt_pk_kb, lv_event_get_target(e));
    }
}

static void bt_passkey_apply_cb(lv_event_t *e)
{
    (void)e;
    bool ok = false;
    if (wl_bt_pk_ta) {
        const char *txt = lv_textarea_get_text(wl_bt_pk_ta);
        if (txt && txt[0]) {
            const uint32_t pin = (uint32_t)strtoul(txt, NULL, 10);
            ok = modulus_wireless_ble_passkey_submit(pin);
        }
    } else {
        ok = modulus_wireless_ble_passkey_confirm();
    }
    if (!ok) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    wl_bt_passkey_modal_hide();
    wl_refresh_bt_labels();
}

void wl_bt_passkey_modal_show(uint8_t mode, uint32_t value)
{
    if (wl_bt_pk_modal) {
        return;
    }
    wl_bt_passkey_modal_hide();

    wl_bt_pk_modal = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(wl_bt_pk_modal);
    lv_obj_set_size(wl_bt_pk_modal, lv_pct(100), lv_pct(100));
    modulus_ui_apply_overlay_scrim(wl_bt_pk_modal);

    lv_obj_t *card = lv_obj_create(wl_bt_pk_modal);
    lv_obj_remove_style_all(card);
    lv_obj_set_size(card, 420, LV_SIZE_CONTENT);
    lv_obj_align(card, LV_ALIGN_TOP_MID, 0, 40);
    lv_obj_set_style_bg_color(card, modulus_ui_color_surface_container_highest(), 0);
    lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(card, MOD_UI_SHAPE_XL, 0);
    lv_obj_set_style_border_color(card, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_border_width(card, 1, 0);
    lv_obj_set_style_pad_all(card, 20, 0);
    lv_obj_set_flex_flow(card, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(card, 10, 0);
    settings_no_scroll(card);

    lv_obj_t *title = lv_label_create(card);
    lv_label_set_text(title, "Bluetooth pairing");
    lv_obj_set_style_text_font(title, MOD_UI_FONT_TITLE_M, 0);

    wl_bt_pk_hint = lv_label_create(card);
    lv_obj_set_style_text_color(wl_bt_pk_hint, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(wl_bt_pk_hint, MOD_UI_FONT_BODY_M, 0);
    lv_obj_set_width(wl_bt_pk_hint, lv_pct(100));
    lv_label_set_long_mode(wl_bt_pk_hint, LV_LABEL_LONG_WRAP);

    char hint[64];
    if (mode == WL_BLE_PK_INPUT) {
        lv_label_set_text(wl_bt_pk_hint, "Enter 6-digit PIN on remote device:");
        wl_bt_pk_ta = lv_textarea_create(card);
        lv_textarea_set_one_line(wl_bt_pk_ta, true);
        lv_textarea_set_max_length(wl_bt_pk_ta, 6);
        lv_textarea_set_accepted_chars(wl_bt_pk_ta, "0123456789");
        lv_obj_set_width(wl_bt_pk_ta, lv_pct(100));
        lv_textarea_set_placeholder_text(wl_bt_pk_ta, "000000");
        modulus_ui_apply_textarea_theme(wl_bt_pk_ta, false);
        lv_obj_add_event_cb(wl_bt_pk_ta, bt_passkey_ta_focus_cb, LV_EVENT_FOCUSED, NULL);
    } else if (mode == WL_BLE_PK_CONFIRM) {
        snprintf(hint, sizeof(hint), "Confirm pairing code: %06lu", (unsigned long)value);
        lv_label_set_text(wl_bt_pk_hint, hint);
        wl_bt_pk_ta = NULL;
    } else {
        snprintf(hint, sizeof(hint), "Enter on other device: %06lu", (unsigned long)value);
        lv_label_set_text(wl_bt_pk_hint, hint);
        wl_bt_pk_ta = NULL;
    }

    wl_modal_action_row(card, mode == WL_BLE_PK_INPUT ? "Pair" : "Confirm",
                        bt_passkey_hide_cb, bt_passkey_apply_cb);

    if (mode == WL_BLE_PK_INPUT) {
        wl_bt_pk_kb = lv_keyboard_create(wl_bt_pk_modal);
        lv_keyboard_set_mode(wl_bt_pk_kb, LV_KEYBOARD_MODE_NUMBER);
        wl_configure_connect_keyboard(wl_bt_pk_kb);
        lv_keyboard_set_textarea(wl_bt_pk_kb, wl_bt_pk_ta);
    }
}
void bt_radio_toggle_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    if (on) {
        if (!modulus_wireless_ble_enable()) {
            lv_obj_remove_state(lv_event_get_target(e), LV_STATE_CHECKED);
        }
    } else {
        modulus_wireless_ble_disable();
    }
    wl_rebuild();
}

void bt_scan_cb(lv_event_t *e)
{
    (void)e;
    if (!modulus_wireless_ble_is_enabled()) {
        return;
    }
    if (modulus_wireless_ble_is_connected() || modulus_wireless_ble_is_connecting()) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    if (!modulus_wireless_ble_scan_start()) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    wl_bt_scan_done_cache = false;
    wl_bt_scan_n_cache = -1;
    wl_rebuild();
}

void bt_device_row_cb(lv_event_t *e)
{
    const int idx = (int)(intptr_t)lv_event_get_user_data(e);
    if (!modulus_wireless_ble_connect(idx)) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    wl_bt_conn_cache = 1;
    wl_rebuild();
}

void bt_disconnect_cb(lv_event_t *e)
{
    (void)e;
    modulus_wireless_ble_disconnect();
    wl_rebuild();
}

void bt_clear_paired_cb(lv_event_t *e)
{
    (void)e;
    modulus_wireless_ble_clear_paired();
    wl_rebuild();
}
