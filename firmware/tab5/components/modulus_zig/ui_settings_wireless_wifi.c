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

static void connect_modal_hide_cb(lv_event_t *e);

void wifi_radio_toggle_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    if (on) {
        modulus_wireless_wifi_enable();
    } else {
        modulus_wireless_wifi_disable();
    }
    wl_refresh_wifi_labels();
}
void scan_cb(lv_event_t *e)
{
    (void)e;
    if (!modulus_wireless_wifi_is_enabled()) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    if (modulus_wireless_wifi_is_connecting()) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    if (!modulus_wireless_wifi_scan_start()) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    wl_scan_done_cache = false;
    wl_scan_n_cache = -1;
    wl_refresh_wifi_labels();
}
static void connect_ta_focus_cb(lv_event_t *e)
{
    if (wl_connect_kb) {
        lv_keyboard_set_textarea(wl_connect_kb, lv_event_get_target(e));
    }
}

void wl_connect_modal_hide(void)
{
    if (!wl_connect_modal) {
        wl_connect_kb = NULL;
        wl_connect_ta = NULL;
        return;
    }
    wl_connect_kb = NULL;
    wl_connect_ta = NULL;
    modulus_ui_dialog_scrim_hide_animated(&wl_connect_modal);
}

static void connect_apply_cb(lv_event_t *e)
{
    (void)e;
    const char *pass = wl_connect_ta ? lv_textarea_get_text(wl_connect_ta) : "";
    if (!modulus_wireless_wifi_connect(wl_connect_ssid, pass)) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        modulus_ui_snackbar_show("Wi-Fi connect failed", 2800);
        return;
    }
    wl_connect_modal_hide();
    wl_wifi_conn_cache = 1;
    wl_rebuild();
}

static void wl_show_connect_modal(const char *ssid)
{
    wl_connect_modal_hide();
    strncpy(wl_connect_ssid, ssid, sizeof(wl_connect_ssid) - 1);
    wl_connect_ssid[sizeof(wl_connect_ssid) - 1] = '\0';

    wl_connect_modal = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(wl_connect_modal);
    lv_obj_set_size(wl_connect_modal, lv_pct(100), lv_pct(100));
    modulus_ui_apply_overlay_scrim(wl_connect_modal);

    lv_obj_t *card = lv_obj_create(wl_connect_modal);
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
    char hdr[48];
    snprintf(hdr, sizeof(hdr), "Connect to %s", ssid);
    lv_label_set_text(title, hdr);
    lv_obj_set_style_text_font(title, MOD_UI_FONT_TITLE_M, 0);

    lv_obj_t *hint = lv_label_create(card);
    lv_label_set_text(hint, "Password (empty for open):");
    lv_obj_set_style_text_color(hint, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(hint, MOD_UI_FONT_BODY_M, 0);
    lv_obj_set_width(hint, lv_pct(100));
    lv_label_set_long_mode(hint, LV_LABEL_LONG_WRAP);

    wl_connect_ta = lv_textarea_create(card);
    lv_textarea_set_one_line(wl_connect_ta, true);
    lv_textarea_set_password_mode(wl_connect_ta, true);
    lv_textarea_set_max_length(wl_connect_ta, 64);
    lv_obj_set_width(wl_connect_ta, lv_pct(100));
    lv_textarea_set_placeholder_text(wl_connect_ta, "Wi-Fi password");
    modulus_ui_apply_textarea_theme(wl_connect_ta, false);
    lv_obj_add_event_cb(wl_connect_ta, connect_ta_focus_cb, LV_EVENT_FOCUSED, NULL);

    wl_modal_action_row(card, "Connect", connect_modal_hide_cb, connect_apply_cb);

    wl_connect_kb = lv_keyboard_create(wl_connect_modal);
    lv_keyboard_set_mode(wl_connect_kb, LV_KEYBOARD_MODE_TEXT_LOWER);
    wl_configure_connect_keyboard(wl_connect_kb);
    lv_keyboard_set_textarea(wl_connect_kb, wl_connect_ta);
}

static void connect_modal_hide_cb(lv_event_t *e)
{
    (void)e;
    wl_connect_modal_hide();
}
void ap_row_click_cb(lv_event_t *e)
{
    const int idx = (int)(intptr_t)lv_event_get_user_data(e);
    modulus_wifi_ap_t ap = {};
    if (!modulus_wireless_wifi_scan_get(idx, &ap)) {
        return;
    }
    if (!modulus_wireless_wifi_ap_needs_pass(ap.auth)) {
        if (!modulus_wireless_wifi_connect(ap.ssid, "")) {
            modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
            return;
        }
        wl_wifi_conn_cache = 1;
        wl_rebuild();
        return;
    }
    wl_show_connect_modal(ap.ssid);
}
