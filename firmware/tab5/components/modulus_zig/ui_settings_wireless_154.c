#include "ui_settings_wireless_priv.h"
#include "ui_settings_wireless_kb.h"
#include "ui_settings_common.h"
#include "ui_internal.h"
#include "wireless_rpc.h"
#include "zb_automation.h"
#include "ui_touch_sound.h"
#include "audio_shim.h"
#include "nvs_shim.h"
#include "wireless_shim.h"
#include "transport_shim.h"
#include "cnc_cmd_exports.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void zb_join_cb(lv_event_t *e)
{
    (void)e;
    if (!modulus_wireless_zigbee_join()) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
    } else {
        modulus_nvs_set_u8("zb_auto", 1); /* auto-start the hub on reboot */
    }
    wl_rebuild();
}

void zb_leave_cb(lv_event_t *e)
{
    (void)e;
    (void)modulus_wireless_zigbee_leave();
    modulus_nvs_set_u8("zb_auto", 0);
    wl_rebuild();
}

void th_attach_cb(lv_event_t *e)
{
    (void)e;
    if (!modulus_wireless_thread_attach()) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
    }
    wl_rebuild();
}

void th_detach_cb(lv_event_t *e)
{
    (void)e;
    (void)modulus_wireless_thread_detach();
    wl_rebuild();
}

void zb_scan_cb(lv_event_t *e)
{
    (void)e;
    if (!modulus_nvs_get_u8("zigbee", 0)) {
        return;
    }
    if (!modulus_wireless_zigbee_scan_start()) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    wl_zb_scan_done_cache = false;
    wl_zb_scan_n_cache = -1;
    wl_rebuild();
}

void th_scan_cb(lv_event_t *e)
{
    (void)e;
    if (!modulus_nvs_get_u8("thread", 0)) {
        return;
    }
    if (!modulus_wireless_thread_scan_start()) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    wl_th_scan_done_cache = false;
    wl_th_scan_n_cache = -1;
    wl_rebuild();
}

void zb_scan_row_cb(lv_event_t *e)
{
    const int idx = (int)(intptr_t)lv_event_get_user_data(e);
    if (!modulus_wireless_zigbee_scan_select(idx)) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    wl_rebuild();
}

void th_scan_row_cb(lv_event_t *e)
{
    const int idx = (int)(intptr_t)lv_event_get_user_data(e);
    if (!modulus_wireless_thread_scan_select(idx)) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    wl_rebuild();
}

void zb_device_toggle_cb(lv_event_t *e)
{
    const int idx = (int)(intptr_t)lv_event_get_user_data(e);
    (void)modulus_wireless_zigbee_device_toggle(idx);
}

/* Inline rename: text input saves on defocus (keyboard close). */

/* Singleton keyboard for inline text rows on the wireless page. The page
 * (unlike the add-device modal) never had one, so focusing the Name field
 * did nothing. Created lazily on lv_layer_top(), reused, hidden when idle —
 * a single bounded widget, not a per-focus allocation. */
static lv_obj_t *s_wl_inline_kb = NULL;

static void wl_inline_kb_ready_cb(lv_event_t *e)
{
    lv_obj_t *kb = lv_event_get_target(e);
    lv_obj_t *ta = lv_keyboard_get_textarea(kb);
    lv_keyboard_set_textarea(kb, NULL);
    lv_obj_add_flag(kb, LV_OBJ_FLAG_HIDDEN);
    if (ta) {
        /* Route through the row's DEFOCUSED handler so save + rebuild run. */
        lv_obj_send_event(ta, LV_EVENT_DEFOCUSED, NULL);
    }
}

void zb_rename_focus_cb(lv_event_t *e)
{
    if (!s_wl_inline_kb) {
        s_wl_inline_kb = lv_keyboard_create(lv_layer_top());
        lv_obj_set_size(s_wl_inline_kb, lv_pct(100), 280);
        lv_obj_align(s_wl_inline_kb, LV_ALIGN_BOTTOM_MID, 0, 0);
        modulus_ui_apply_keyboard_theme(s_wl_inline_kb);
        lv_obj_add_event_cb(s_wl_inline_kb, wl_inline_kb_ready_cb, LV_EVENT_READY, NULL);
        lv_obj_add_event_cb(s_wl_inline_kb, wl_inline_kb_ready_cb, LV_EVENT_CANCEL, NULL);
    }
    lv_keyboard_set_textarea(s_wl_inline_kb, lv_event_get_target(e));
    lv_obj_remove_flag(s_wl_inline_kb, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(s_wl_inline_kb);
}

void zb_device_rename_cb(lv_event_t *e)
{
    if (lv_event_get_code(e) != LV_EVENT_DEFOCUSED) {
        return;
    }
    if (s_wl_inline_kb && lv_keyboard_get_textarea(s_wl_inline_kb) == lv_event_get_target(e)) {
        lv_keyboard_set_textarea(s_wl_inline_kb, NULL);
        lv_obj_add_flag(s_wl_inline_kb, LV_OBJ_FLAG_HIDDEN);
    }
    const int idx = (int)(intptr_t)lv_event_get_user_data(e);
    const char *name = lv_textarea_get_text(lv_event_get_target(e));
    if (name && name[0]) {
        (void)modulus_wireless_zigbee_device_rename(idx, name);
        wl_rebuild();
    }
}

/* Brightness slider (ZCL Level Control 0-254). Slider drag updates the value
 * label live; the radio command fires once on RELEASED so a drag doesn't
 * flood the 802.15.4 network with move_to_level requests. */
void zb_device_level_cb(lv_event_t *e)
{
    const lv_event_code_t code = lv_event_get_code(e);
    if (code != LV_EVENT_VALUE_CHANGED && code != LV_EVENT_RELEASED) {
        return;
    }
    lv_obj_t *s = lv_event_get_target(e);
    int32_t val = lv_slider_get_value(s);
    if (val < 0) {
        val = 0;
    }
    if (val > 254) {
        val = 254;
    }
    lv_obj_t *vl = lv_obj_get_user_data(s);
    if (vl) {
        char buf[8];
        snprintf(buf, sizeof(buf), "%d%%", (int)((val * 100) / 254));
        modulus_ui_label_set_text_if_changed(vl, buf);
    }
    if (code == LV_EVENT_RELEASED) {
        const int idx = (int)(intptr_t)lv_event_get_user_data(e);
        (void)modulus_wireless_zigbee_device_set_level(idx, (uint8_t)val);
    }
}

void th_device_toggle_cb(lv_event_t *e)
{
    const int idx = (int)(intptr_t)lv_event_get_user_data(e);
    (void)modulus_wireless_thread_device_toggle(idx);
}

void zb_cover_open_cb(lv_event_t *e)
{
    (void)modulus_wireless_zigbee_device_cover((int)(intptr_t)lv_event_get_user_data(e), 0);
}

void zb_cover_close_cb(lv_event_t *e)
{
    (void)modulus_wireless_zigbee_device_cover((int)(intptr_t)lv_event_get_user_data(e), 1);
}

void zb_cover_stop_cb(lv_event_t *e)
{
    (void)modulus_wireless_zigbee_device_cover((int)(intptr_t)lv_event_get_user_data(e), 2);
}

void zb_identify_cb(lv_event_t *e)
{
    if (!modulus_wireless_zigbee_device_identify((int)(intptr_t)lv_event_get_user_data(e))) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
    }
}

void zb_device_remove_cb(lv_event_t *e)
{
    const int idx = (int)(intptr_t)lv_event_get_user_data(e);
    if (!modulus_wireless_zigbee_device_leave(idx)) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
    }
    wl_rebuild();
}

/* Cycle CNC automation: Manual -> On-while-runs -> Off-while-runs -> Manual.
 * Persisted per device (NVS zbN_auto); zb_automation.c applies it on the
 * machine-state edges. */
void zb_auto_cycle_cb(lv_event_t *e)
{
    const int idx = (int)(intptr_t)lv_event_get_user_data(e);
    modulus_zb_auto_set(idx, (uint8_t)((modulus_zb_auto_get(idx) + 1) % 3));
    wl_rebuild();
}

void zb_energy_scan_cb(lv_event_t *e)
{
    (void)e;
    if (!modulus_wireless_zigbee_energy_scan()) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
    }
    wl_rebuild();
}

void th_device_remove_cb(lv_event_t *e)
{
    const int idx = (int)(intptr_t)lv_event_get_user_data(e);
    (void)modulus_wireless_thread_device_remove(idx);
    wl_rebuild();
}

void zb_devices_clear_cb(lv_event_t *e)
{
    (void)e;
    modulus_wireless_zigbee_devices_clear();
    wl_rebuild();
}

void th_devices_clear_cb(lv_event_t *e)
{
    (void)e;
    modulus_wireless_thread_devices_clear();
    wl_rebuild();
}
void wl_zb_add_modal_hide(void)
{
    if (!wl_zb_add_modal) {
        wl_zb_add_kb = NULL;
        wl_zb_name_ta = NULL;
        wl_zb_ieee_ta = NULL;
        wl_zb_code_ta = NULL;
        wl_timer_maybe_start();
        return;
    }
    wl_zb_add_kb = NULL;
    wl_zb_name_ta = NULL;
    wl_zb_ieee_ta = NULL;
    wl_zb_code_ta = NULL;
    modulus_ui_dialog_scrim_hide_animated(&wl_zb_add_modal);
    wl_timer_maybe_start();
}

static void zb_add_modal_hide_cb(lv_event_t *e)
{
    (void)e;
    wl_zb_add_modal_hide();
}

static void zb_add_ta_focus_cb(lv_event_t *e)
{
    if (wl_zb_add_kb) {
        lv_keyboard_set_textarea(wl_zb_add_kb, lv_event_get_target(e));
    }
}

static void zb_add_modal_apply_cb(lv_event_t *e)
{
    (void)e;
    const char *name = wl_zb_name_ta ? lv_textarea_get_text(wl_zb_name_ta) : "";
    const char *ieee = wl_zb_ieee_ta ? lv_textarea_get_text(wl_zb_ieee_ta) : "";
    const char *code = wl_zb_code_ta ? lv_textarea_get_text(wl_zb_code_ta) : "";
    if (!ieee || !ieee[0] ||
        !modulus_wireless_zigbee_device_add(name, ieee, 1, code)) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    /* Register the install code with the Trust Center so this device can join
     * securely with a per-device link key. Requires the hub to be formed;
     * harmless (ignored) on raw/OT firmware. */
    if (code[0] && modulus_wireless_zb_joined()) {
        (void)modulus_wireless_zb_ic_add(ieee, code);
    }
    wl_zb_add_modal_hide();
    wl_rebuild();
}

void zb_add_modal_show(lv_event_t *e)
{
    (void)e;
    if (wl_zb_add_modal) {
        return;
    }
    wl_timer_stop_core();

    wl_zb_add_modal = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(wl_zb_add_modal);
    lv_obj_set_size(wl_zb_add_modal, lv_pct(100), lv_pct(100));
    modulus_ui_apply_overlay_scrim(wl_zb_add_modal);

    lv_obj_t *card = lv_obj_create(wl_zb_add_modal);
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
    lv_label_set_text(title, "Add Zigbee device");
    lv_obj_set_style_text_font(title, MOD_UI_FONT_TITLE_M, 0);

    wl_zb_name_ta = lv_textarea_create(card);
    lv_textarea_set_one_line(wl_zb_name_ta, true);
    lv_textarea_set_max_length(wl_zb_name_ta, 23);
    lv_textarea_set_placeholder_text(wl_zb_name_ta, "Name");
    lv_obj_set_width(wl_zb_name_ta, lv_pct(100));
    modulus_ui_apply_textarea_theme(wl_zb_name_ta, false);
    lv_obj_add_event_cb(wl_zb_name_ta, zb_add_ta_focus_cb, LV_EVENT_FOCUSED, NULL);

    wl_zb_ieee_ta = lv_textarea_create(card);
    lv_textarea_set_one_line(wl_zb_ieee_ta, true);
    lv_textarea_set_max_length(wl_zb_ieee_ta, 16);
    lv_textarea_set_accepted_chars(wl_zb_ieee_ta, "0123456789ABCDEFabcdef");
    lv_textarea_set_placeholder_text(wl_zb_ieee_ta, "IEEE 16 hex");
    lv_obj_set_width(wl_zb_ieee_ta, lv_pct(100));
    modulus_ui_apply_textarea_theme(wl_zb_ieee_ta, false);
    lv_obj_add_event_cb(wl_zb_ieee_ta, zb_add_ta_focus_cb, LV_EVENT_FOCUSED, NULL);

    wl_zb_code_ta = lv_textarea_create(card);
    lv_textarea_set_one_line(wl_zb_code_ta, true);
    lv_textarea_set_max_length(wl_zb_code_ta, 36);
    lv_textarea_set_placeholder_text(wl_zb_code_ta, "Install code (optional)");
    lv_obj_set_width(wl_zb_code_ta, lv_pct(100));
    modulus_ui_apply_textarea_theme(wl_zb_code_ta, false);
    lv_obj_add_event_cb(wl_zb_code_ta, zb_add_ta_focus_cb, LV_EVENT_FOCUSED, NULL);

    wl_modal_action_row(card, "Save", zb_add_modal_hide_cb, zb_add_modal_apply_cb);

    wl_zb_add_kb = lv_keyboard_create(wl_zb_add_modal);
    lv_keyboard_set_mode(wl_zb_add_kb, LV_KEYBOARD_MODE_TEXT_UPPER);
    wl_configure_connect_keyboard(wl_zb_add_kb);
    lv_keyboard_set_textarea(wl_zb_add_kb, wl_zb_name_ta);
}

void wl_th_add_modal_hide(void)
{
    if (!wl_th_add_modal) {
        wl_th_add_kb = NULL;
        wl_th_name_ta = NULL;
        wl_th_ext_ta = NULL;
        wl_timer_maybe_start();
        return;
    }
    wl_th_add_kb = NULL;
    wl_th_name_ta = NULL;
    wl_th_ext_ta = NULL;
    modulus_ui_dialog_scrim_hide_animated(&wl_th_add_modal);
    wl_timer_maybe_start();
}

static void th_add_modal_hide_cb(lv_event_t *e)
{
    (void)e;
    wl_th_add_modal_hide();
}

static void th_add_ta_focus_cb(lv_event_t *e)
{
    if (wl_th_add_kb) {
        lv_keyboard_set_textarea(wl_th_add_kb, lv_event_get_target(e));
    }
}

static void th_add_modal_apply_cb(lv_event_t *e)
{
    (void)e;
    const char *name = wl_th_name_ta ? lv_textarea_get_text(wl_th_name_ta) : "";
    const char *ext = wl_th_ext_ta ? lv_textarea_get_text(wl_th_ext_ta) : "";
    if (!ext || !ext[0] || !modulus_wireless_thread_device_add(name, ext)) {
        modulus_audio_play_ui(MODULUS_UI_SOUND_DROP);
        return;
    }
    wl_th_add_modal_hide();
    wl_rebuild();
}

void th_add_modal_show(lv_event_t *e)
{
    (void)e;
    if (wl_th_add_modal) {
        return;
    }
    wl_timer_stop_core();

    wl_th_add_modal = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(wl_th_add_modal);
    lv_obj_set_size(wl_th_add_modal, lv_pct(100), lv_pct(100));
    modulus_ui_apply_overlay_scrim(wl_th_add_modal);

    lv_obj_t *card = lv_obj_create(wl_th_add_modal);
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
    lv_label_set_text(title, "Add Thread node");
    lv_obj_set_style_text_font(title, MOD_UI_FONT_TITLE_M, 0);

    wl_th_name_ta = lv_textarea_create(card);
    lv_textarea_set_one_line(wl_th_name_ta, true);
    lv_textarea_set_max_length(wl_th_name_ta, 23);
    lv_textarea_set_placeholder_text(wl_th_name_ta, "Name");
    lv_obj_set_width(wl_th_name_ta, lv_pct(100));
    modulus_ui_apply_textarea_theme(wl_th_name_ta, false);
    lv_obj_add_event_cb(wl_th_name_ta, th_add_ta_focus_cb, LV_EVENT_FOCUSED, NULL);

    wl_th_ext_ta = lv_textarea_create(card);
    lv_textarea_set_one_line(wl_th_ext_ta, true);
    lv_textarea_set_max_length(wl_th_ext_ta, 16);
    lv_textarea_set_accepted_chars(wl_th_ext_ta, "0123456789ABCDEFabcdef");
    lv_textarea_set_placeholder_text(wl_th_ext_ta, "Extended address 16 hex");
    lv_obj_set_width(wl_th_ext_ta, lv_pct(100));
    modulus_ui_apply_textarea_theme(wl_th_ext_ta, false);
    lv_obj_add_event_cb(wl_th_ext_ta, th_add_ta_focus_cb, LV_EVENT_FOCUSED, NULL);

    wl_modal_action_row(card, "Save", th_add_modal_hide_cb, th_add_modal_apply_cb);

    wl_th_add_kb = lv_keyboard_create(wl_th_add_modal);
    lv_keyboard_set_mode(wl_th_add_kb, LV_KEYBOARD_MODE_TEXT_UPPER);
    wl_configure_connect_keyboard(wl_th_add_kb);
    lv_keyboard_set_textarea(wl_th_add_kb, wl_th_name_ta);
}

void settings_wireless_inline_kb_theme_refresh(void)
{
    if (s_wl_inline_kb) {
        modulus_ui_apply_keyboard_theme(s_wl_inline_kb);
    }
}
