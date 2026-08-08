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

void wl_maybe_reinit_espnow_transport(void)
{
    if (modulus_nvs_get_u8("cnc_conn", 4) == 0) {
        modulus_wireless_espnow_transport_reinit();
    }
}
void espnow_log_dd_cb(lv_event_t *e)
{
    const uint8_t lvl = modulus_ui_segmented_get_selected(lv_event_get_target(e));
    modulus_wireless_espnow_log_set_level(lvl);
    wl_rebuild();
}

void espnow_toggle_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    if (on) {
        if (!modulus_wireless_ready() && !modulus_wireless_wake_coprocessor()) {
            lv_obj_remove_state(lv_event_get_target(e), LV_STATE_CHECKED);
            modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        } else if (!modulus_wireless_ensure_wifi_stack() &&
                   !modulus_wireless_wake_coprocessor()) {
            lv_obj_remove_state(lv_event_get_target(e), LV_STATE_CHECKED);
            modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        } else if (!modulus_wireless_espnow_enable()) {
            lv_obj_remove_state(lv_event_get_target(e), LV_STATE_CHECKED);
            modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        } else if (modulus_nvs_get_u8("cnc_conn", 4) == 0) {
            wl_maybe_reinit_espnow_transport();
        }
    } else {
        /* disable() already tears down the CNC transport (transport_stop +
         * onDisconnect). Do NOT reinit here: when ESP-NOW is the active CNC
         * transport (cnc_conn==0), a reinit re-opens it via
         * modulus_espnow_transport_start() -> modulus_wireless_espnow_enable(),
         * which flips the radio straight back on. */
        modulus_wireless_espnow_disable();
    }
    wl_rebuild();
}
void dd_u8_cb(lv_event_t *e)
{
    const char *key = lv_event_get_user_data(e);
    modulus_nvs_set_u8(key, (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e)));
    if (strcmp(key, "en_chan") == 0 || strcmp(key, "en_rate") == 0) {
        wl_maybe_reinit_espnow_transport();
    }
}

void espnow_scan_cb(lv_event_t *e)
{
    (void)e;
    if (!modulus_wireless_espnow_is_enabled()) {
        return;
    }
    if (!modulus_wireless_espnow_scan_start()) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    wl_en_scan_done_cache = false;
    wl_en_scan_n_cache = -1;
    wl_en_scan_fail_cache = false;
    wl_rebuild();
}

void espnow_peer_row_cb(lv_event_t *e)
{
    const int idx = (int)(intptr_t)lv_event_get_user_data(e);
    if (!modulus_wireless_espnow_select_scan_peer(idx)) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    wl_rebuild();
}

void espnow_saved_activate_cb(lv_event_t *e)
{
    const int idx = (int)(intptr_t)lv_event_get_user_data(e);
    if (!modulus_wireless_espnow_activate_saved(idx)) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    wl_rebuild();
}

void espnow_saved_delete_cb(lv_event_t *e)
{
    const int idx = (int)(intptr_t)lv_event_get_user_data(e);
    (void)modulus_wireless_espnow_delete_saved(idx);
    wl_maybe_reinit_espnow_transport();
    wl_rebuild();
}

void espnow_clear_peers_cb(lv_event_t *e)
{
    (void)e;
    modulus_wireless_espnow_clear_peers();
    wl_rebuild();
}

void wl_espnow_mac_modal_hide(void)
{
    if (!wl_en_mac_modal) {
        wl_en_mac_kb = NULL;
        wl_en_mac_ta = NULL;
        wl_timer_maybe_start();
        return;
    }
    wl_en_mac_kb = NULL;
    wl_en_mac_ta = NULL;
    modulus_ui_dialog_scrim_hide_animated(&wl_en_mac_modal);
    wl_timer_maybe_start();
}

static void espnow_mac_ta_focus_cb(lv_event_t *e)
{
    if (wl_en_mac_kb) {
        lv_keyboard_set_textarea(wl_en_mac_kb, lv_event_get_target(e));
    }
}

static void espnow_mac_modal_apply_cb(lv_event_t *e)
{
    (void)e;
    const char *mac = wl_en_mac_ta ? lv_textarea_get_text(wl_en_mac_ta) : NULL;
    if (!mac || !mac[0] || !modulus_wireless_espnow_set_peer_mac(mac)) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    wl_espnow_mac_modal_hide();
    wl_rebuild();
}

static void espnow_mac_modal_hide_cb(lv_event_t *e)
{
    (void)e;
    wl_espnow_mac_modal_hide();
}

void espnow_mac_modal_show(lv_event_t *e)
{
    (void)e;
    if (wl_en_mac_modal) {
        return;
    }
    wl_timer_stop_activity();

    char mac[20];
    modulus_wireless_espnow_peer_mac_str(mac, sizeof(mac));

    wl_en_mac_modal = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(wl_en_mac_modal);
    lv_obj_set_size(wl_en_mac_modal, lv_pct(100), lv_pct(100));
    modulus_ui_apply_overlay_scrim(wl_en_mac_modal);

    lv_obj_t *card = lv_obj_create(wl_en_mac_modal);
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
    lv_label_set_text(title, "Bridge peer MAC");
    lv_obj_set_style_text_font(title, MOD_UI_FONT_TITLE_M, 0);

    lv_obj_t *hint = lv_label_create(card);
    lv_label_set_text(hint, "Format AA:BB:CC:DD:EE:FF");
    lv_obj_set_style_text_color(hint, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(hint, MOD_UI_FONT_BODY_M, 0);

    wl_en_mac_ta = lv_textarea_create(card);
    lv_textarea_set_one_line(wl_en_mac_ta, true);
    lv_textarea_set_max_length(wl_en_mac_ta, 17);
    lv_textarea_set_accepted_chars(wl_en_mac_ta, "0123456789ABCDEFabcdef:");
    lv_textarea_set_text(wl_en_mac_ta, mac);
    lv_obj_set_width(wl_en_mac_ta, lv_pct(100));
    modulus_ui_apply_textarea_theme(wl_en_mac_ta, false);
    lv_obj_add_event_cb(wl_en_mac_ta, espnow_mac_ta_focus_cb, LV_EVENT_FOCUSED, NULL);

    wl_modal_action_row(card, "Save", espnow_mac_modal_hide_cb, espnow_mac_modal_apply_cb);

    wl_en_mac_kb = lv_keyboard_create(wl_en_mac_modal);
    lv_keyboard_set_mode(wl_en_mac_kb, LV_KEYBOARD_MODE_TEXT_UPPER);
    wl_configure_connect_keyboard(wl_en_mac_kb);
    lv_keyboard_set_textarea(wl_en_mac_kb, wl_en_mac_ta);
}
