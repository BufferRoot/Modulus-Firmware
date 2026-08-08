#include "ui_settings_modal_kb.h"
#include "ui_settings_priv.h"
#include "ui_internal.h"
#include "nvs_shim.h"

void settings_modal_kb_configure_text(lv_obj_t *kb)
{
    if (!kb) {
        return;
    }
    const bool full = modulus_nvs_get_u8("kb_full", 1) != 0;
    if (full) {
        lv_obj_set_size(kb, lv_pct(100), lv_pct(48));
        lv_obj_align(kb, LV_ALIGN_BOTTOM_MID, 0, 0);
    } else {
        lv_obj_set_size(kb, 560, 220);
        lv_obj_align(kb, LV_ALIGN_BOTTOM_MID, 0, -20);
    }
    modulus_ui_apply_keyboard_theme(kb);
}

void settings_modal_kb_configure_number(lv_obj_t *kb)
{
    if (!kb) {
        return;
    }
    lv_obj_set_size(kb, lv_pct(100), lv_pct(48));
    lv_obj_align(kb, LV_ALIGN_BOTTOM_MID, 0, 0);
    modulus_ui_apply_keyboard_theme(kb);
}

void settings_modal_fit_card_above_kb(lv_obj_t *card)
{
    if (!card) {
        return;
    }
    lv_display_t *disp = lv_display_get_default();
    const int32_t dh = disp ? lv_display_get_vertical_resolution(disp) : 720;
    const bool full = modulus_nvs_get_u8("kb_full", 1) != 0;
    /* Match settings_modal_kb_configure_text dock height. */
    const int32_t kb_h = full ? (dh * 48) / 100 : 240;
    const int32_t top = 16;
    const int32_t gap = 8;
    int32_t max_h = dh - kb_h - top - gap;
    if (max_h < 200) {
        max_h = 200;
    }
    lv_obj_set_style_max_height(card, max_h, 0);
    lv_obj_set_height(card, LV_SIZE_CONTENT);
    lv_obj_align(card, LV_ALIGN_TOP_MID, 0, top);
    lv_obj_add_flag(card, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scroll_dir(card, LV_DIR_VER);
    settings_tune_scroll_container(card);
}

/* Singleton keyboard for settings-shell / in-page text fields (search, text rows). */
static lv_obj_t *s_shell_kb = NULL;

static void shell_kb_ready_cb(lv_event_t *e)
{
    lv_obj_t *kb = lv_event_get_target(e);
    lv_obj_t *ta = lv_keyboard_get_textarea(kb);
    lv_keyboard_set_textarea(kb, NULL);
    lv_obj_add_flag(kb, LV_OBJ_FLAG_HIDDEN);
    if (ta) {
        lv_obj_send_event(ta, LV_EVENT_DEFOCUSED, NULL);
    }
}

static void shell_kb_ensure(void)
{
    if (s_shell_kb) {
        return;
    }
    s_shell_kb = lv_keyboard_create(lv_layer_top());
    settings_modal_kb_configure_text(s_shell_kb);
    lv_obj_add_flag(s_shell_kb, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_event_cb(s_shell_kb, shell_kb_ready_cb, LV_EVENT_READY, NULL);
    lv_obj_add_event_cb(s_shell_kb, shell_kb_ready_cb, LV_EVENT_CANCEL, NULL);
}

static void shell_ta_focus_cb(lv_event_t *e)
{
    shell_kb_ensure();
    lv_keyboard_set_textarea(s_shell_kb, lv_event_get_target(e));
    lv_obj_remove_flag(s_shell_kb, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(s_shell_kb);
}

static void shell_ta_defocus_cb(lv_event_t *e)
{
    if (!s_shell_kb) {
        return;
    }
    if (lv_keyboard_get_textarea(s_shell_kb) == lv_event_get_target(e)) {
        lv_keyboard_set_textarea(s_shell_kb, NULL);
        lv_obj_add_flag(s_shell_kb, LV_OBJ_FLAG_HIDDEN);
    }
}

void settings_shell_kb_bind_textarea(lv_obj_t *ta)
{
    if (!ta) {
        return;
    }
    lv_obj_add_event_cb(ta, shell_ta_focus_cb, LV_EVENT_FOCUSED, NULL);
    lv_obj_add_event_cb(ta, shell_ta_defocus_cb, LV_EVENT_DEFOCUSED, NULL);
}

void settings_shell_kb_hide(void)
{
    if (!s_shell_kb) {
        return;
    }
    lv_keyboard_set_textarea(s_shell_kb, NULL);
    lv_obj_add_flag(s_shell_kb, LV_OBJ_FLAG_HIDDEN);
}

void settings_shell_kb_theme_refresh(void)
{
    if (s_shell_kb) {
        modulus_ui_apply_keyboard_theme(s_shell_kb);
    }
}
