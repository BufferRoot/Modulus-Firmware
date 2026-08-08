#include "ui_settings_modals_priv.h"
#include "ui_settings_modal_kb.h"
#include "ui_settings_common.h"
#include "ui_settings_priv.h"
#include "ui_internal.h"
#include "ui_touch_sound.h"
#include "ui_icons.h"
#include "nvs_shim.h"
#include "audio_shim.h"
#include "ui_quick_grid.h"

#include <stdio.h>
#include <string.h>

/* Create / edit a custom Quick Button (cnc_mac<slot>). Keyboard always shown. */

static lv_obj_t *s_macro_modal = NULL;
static lv_obj_t *s_macro_kb = NULL;
static lv_obj_t *s_ta_name = NULL;
static lv_obj_t *s_ta_on = NULL;
static lv_obj_t *s_ta_off = NULL;
static int8_t s_edit_slot = -1;
static uint8_t s_icon = (uint8_t)MOD_UI_ICON_SCROLL;

/* Subset of Phosphor icons for crowded 4-slot dashboard faces. */
static const uint8_t k_icon_pick[] = {
    MOD_UI_ICON_SCROLL,   MOD_UI_ICON_SPINDLE, MOD_UI_ICON_SPINDLE_CCW, MOD_UI_ICON_COOLANT,
    MOD_UI_ICON_FAN,      MOD_UI_ICON_CLOUD_FOG, MOD_UI_ICON_CROSSHAIR, MOD_UI_ICON_LIGHTNING,
    MOD_UI_ICON_CNC,      MOD_UI_ICON_CHECK,  MOD_UI_ICON_PLAY,         MOD_UI_ICON_STOP,
};

static void macro_assist_chip(lv_obj_t *row, const char *label, const char *insert);

static void macro_exit_ready(lv_anim_t *a)
{
    lv_obj_t *dlg = lv_anim_get_user_data(a);
    if (dlg) {
        lv_obj_delete(dlg);
    }
    s_macro_kb = NULL;
    s_ta_name = s_ta_on = s_ta_off = NULL;
    s_edit_slot = -1;
}

void settings_macro_modal_hide(void)
{
    if (!s_macro_modal) {
        s_macro_kb = NULL;
        s_ta_name = s_ta_on = s_ta_off = NULL;
        s_edit_slot = -1;
        return;
    }
    lv_obj_t *dlg = s_macro_modal;
    s_macro_modal = NULL;
    s_macro_kb = NULL;
    s_ta_name = s_ta_on = s_ta_off = NULL;
    s_edit_slot = -1;
    lv_obj_t *card = lv_obj_get_child(dlg, 0);
    if (card && modulus_ui_motion_smooth()) {
        modulus_ui_motion_dialog_exit(card, macro_exit_ready, dlg);
        return;
    }
    lv_obj_delete(dlg);
}

void settings_macro_slot_modal_hide(void)
{
    settings_macro_modal_hide();
}

static void macro_close_cb(lv_event_t *e)
{
    (void)e;
    settings_macro_modal_hide();
}

static void macro_ta_focus_cb(lv_event_t *e)
{
    if (s_macro_kb) {
        lv_keyboard_set_textarea(s_macro_kb, lv_event_get_target(e));
    }
}

static void macro_delete_cb(lv_event_t *e)
{
    (void)e;
    if (s_edit_slot < 0) {
        return;
    }
    const uint8_t assign = (uint8_t)(UI_QBTN_USER0 + s_edit_slot);
    for (int i = 0; i < UI_QBTN_MAX_SLOTS; i++) {
        char key[12];
        snprintf(key, sizeof(key), "cnc_qbtn%d", i);
        if (modulus_nvs_get_u8(key, 0xFF) == assign) {
            modulus_nvs_set_u8(key, UI_QBTN_OFF);
        }
    }
    settings_macro_slot_clear((uint8_t)s_edit_slot);
    modulus_audio_play_ui(1);
    settings_macro_modal_hide();
    modulus_ui_dashboard_config_changed();
    modulus_ui_settings_build_dashboard_tab();
}

static void macro_save_cb(lv_event_t *e)
{
    (void)e;
    if (s_edit_slot < 0 || !s_ta_name || !s_ta_on) {
        return;
    }
    const char *name = lv_textarea_get_text(s_ta_name);
    const char *on = lv_textarea_get_text(s_ta_on);
    const char *off = s_ta_off ? lv_textarea_get_text(s_ta_off) : "";
    if (!name || !on || name[0] == '\0' || on[0] == '\0') {
        return;
    }
    if (!settings_macro_slot_save((uint8_t)s_edit_slot, name, on, off, s_icon)) {
        return;
    }
    {
        const uint8_t assign = (uint8_t)(UI_QBTN_USER0 + s_edit_slot);
        bool placed = false;
        for (int i = 0; i < UI_QBTN_MAX_SLOTS; i++) {
            if (ui_qbtn_slot_assign(i) == assign) {
                placed = true;
                break;
            }
        }
        if (!placed) {
            for (int i = 0; i < UI_QBTN_MAX_SLOTS; i++) {
                char key[12];
                snprintf(key, sizeof(key), "cnc_qbtn%d", i);
                if (ui_qbtn_slot_assign(i) == UI_QBTN_OFF) {
                    modulus_nvs_set_u8(key, assign);
                    break;
                }
            }
        }
    }
    modulus_audio_play_ui(1);
    settings_macro_modal_hide();
    modulus_ui_dashboard_config_changed();
    modulus_ui_settings_build_dashboard_tab();
}

static lv_obj_t *macro_field(lv_obj_t *card, const char *label, const char *text, uint32_t max_len,
                             lv_obj_t **out_ta)
{
    lv_obj_t *lb = lv_label_create(card);
    lv_label_set_text(lb, label);
    lv_obj_set_style_text_font(lb, MOD_UI_FONT_LABEL_L, 0);
    lv_obj_set_style_text_color(lb, modulus_ui_color_on_surface_variant(), 0);

    lv_obj_t *ta = lv_textarea_create(card);
    lv_textarea_set_text(ta, text ? text : "");
    lv_textarea_set_one_line(ta, true);
    lv_textarea_set_max_length(ta, max_len);
    lv_obj_set_width(ta, lv_pct(100));
    modulus_ui_apply_textarea_theme(ta, false);
    lv_obj_add_event_cb(ta, macro_ta_focus_cb, LV_EVENT_FOCUSED, NULL);
    *out_ta = ta;
    return ta;
}

static void macro_assist_cb(lv_event_t *e)
{
    const char *insert = lv_event_get_user_data(e);
    lv_obj_t *ta = NULL;
    if (s_macro_kb) {
        ta = lv_keyboard_get_textarea(s_macro_kb);
    }
    if (!ta) {
        ta = s_ta_on;
    }
    if (!ta || !insert) {
        return;
    }
    /* Only inject into ON/OFF fields — not the name. */
    if (ta != s_ta_on && ta != s_ta_off) {
        ta = s_ta_on;
        if (s_macro_kb) {
            lv_keyboard_set_textarea(s_macro_kb, ta);
        }
    }
    lv_textarea_set_text(ta, insert);
}

static void macro_assist_chip(lv_obj_t *row, const char *label, const char *insert)
{
    lv_obj_t *btn = lv_button_create(row);
    lv_obj_set_height(btn, 36);
    lv_obj_set_style_radius(btn, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_bg_color(btn, modulus_ui_color_secondary_container(), 0);
    lv_obj_set_style_pad_hor(btn, MOD_UI_SPACE_SM + MOD_UI_SPACE_XS, 0);
    lv_obj_t *lb = lv_label_create(btn);
    lv_label_set_text(lb, label);
    lv_obj_set_style_text_font(lb, MOD_UI_FONT_LABEL_M, 0);
    lv_obj_set_style_text_color(lb, modulus_ui_color_on_secondary_container(), 0);
    lv_obj_center(lb);
    settings_bind_menu_click(btn, macro_assist_cb, (void *)insert);
}

static void macro_icon_pick_cb(lv_event_t *e)
{
    s_icon = (uint8_t)(uintptr_t)lv_event_get_user_data(e);
    lv_obj_t *btn = lv_event_get_target(e);
    lv_obj_t *parent = lv_obj_get_parent(btn);
    if (!parent) {
        return;
    }
    const uint32_t n = lv_obj_get_child_count(parent);
    for (uint32_t i = 0; i < n; i++) {
        lv_obj_t *ch = lv_obj_get_child(parent, i);
        const bool sel = (ch == btn);
        lv_obj_set_style_bg_color(ch,
                                  sel ? modulus_ui_color_primary_container()
                                      : modulus_ui_color_surface_container_high(),
                                  0);
    }
}

static void macro_build_icon_row(lv_obj_t *card)
{
    lv_obj_t *lb = lv_label_create(card);
    lv_label_set_text(lb, "Icon");
    lv_obj_set_style_text_font(lb, MOD_UI_FONT_LABEL_L, 0);
    lv_obj_set_style_text_color(lb, modulus_ui_color_on_surface_variant(), 0);

    lv_obj_t *row = lv_obj_create(card);
    lv_obj_remove_style_all(row);
    lv_obj_set_width(row, lv_pct(100));
    lv_obj_set_height(row, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW_WRAP);
    lv_obj_set_style_pad_column(row, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_pad_row(row, MOD_UI_SPACE_SM, 0);
    settings_no_scroll(row);

    for (unsigned i = 0; i < sizeof(k_icon_pick) / sizeof(k_icon_pick[0]); i++) {
        const uint8_t id = k_icon_pick[i];
        const bool sel = (id == s_icon);
        lv_obj_t *btn = lv_button_create(row);
        lv_obj_set_size(btn, 48, 48);
        lv_obj_set_style_radius(btn, MOD_UI_SHAPE_MD, 0);
        lv_obj_set_style_bg_color(btn, sel ? modulus_ui_color_primary_container()
                                           : modulus_ui_color_surface_container_high(),
                                  0);
        lv_obj_set_style_pad_all(btn, 0, 0);
        lv_obj_t *img = modulus_ui_icon_create(btn, (modulus_ui_icon_id_t)id, MOD_UI_ICON_SZ_24);
        if (img) {
            lv_obj_center(img);
            modulus_ui_icon_recolor(img, modulus_ui_color_on_surface());
        }
        settings_bind_menu_click(btn, macro_icon_pick_cb, (void *)(uintptr_t)id);
    }
}

void settings_macro_slot_modal_show(int8_t slot)
{
    settings_macro_modal_hide();

    int8_t use = slot;
    char name[16] = "";
    char on[64] = "";
    char off[64] = "";
    s_icon = (uint8_t)MOD_UI_ICON_SCROLL;
    const bool is_edit = (slot >= 0 && slot < SETTINGS_MACRO_SLOTS &&
                          settings_macro_slot_load((uint8_t)slot, name, sizeof(name), on, sizeof(on),
                                                   off, sizeof(off), &s_icon));
    if (!is_edit) {
        use = (int8_t)settings_macro_slot_first_free();
        if (use < 0) {
            return;
        }
        name[0] = on[0] = off[0] = '\0';
        s_icon = (uint8_t)MOD_UI_ICON_SCROLL;
    }
    s_edit_slot = use;

    s_macro_modal = modulus_ui_dialog_scrim_create();

    lv_obj_t *card = modulus_ui_dialog_card_create(s_macro_modal, MOD_UI_DIALOG_W_WIDE, 0);
    settings_modal_fit_card_above_kb(card);
    modulus_ui_motion_dialog_enter(card);

    modulus_ui_dialog_header(card, is_edit ? "Edit quick button" : "Add quick button",
                             macro_close_cb, NULL);
    modulus_ui_dialog_scrim_bind_dismiss(s_macro_modal, macro_close_cb, NULL);
    modulus_ui_dialog_supporting(
        card, "For aux pins: ON = M64 P0, OFF = M65 P0 (toggle). Leave OFF blank for one-shot.");

    macro_field(card, "Button name", name, 15, &s_ta_name);
    macro_field(card, "G-code when ON / pressed", on, 63, &s_ta_on);
    {
        lv_obj_t *chips = lv_obj_create(card);
        lv_obj_remove_style_all(chips);
        lv_obj_set_width(chips, lv_pct(100));
        lv_obj_set_height(chips, LV_SIZE_CONTENT);
        lv_obj_set_flex_flow(chips, LV_FLEX_FLOW_ROW_WRAP);
        lv_obj_set_style_pad_column(chips, MOD_UI_SPACE_SM, 0);
        lv_obj_set_style_pad_row(chips, MOD_UI_SPACE_SM, 0);
        settings_no_scroll(chips);
        macro_assist_chip(chips, "M64 P0", "M64 P0");
        macro_assist_chip(chips, "M65 P0", "M65 P0");
        macro_assist_chip(chips, "M8", "M8");
        macro_assist_chip(chips, "M9", "M9");
    }
    macro_field(card, "G-code when OFF (optional)", off, 63, &s_ta_off);
    {
        lv_obj_t *chips = lv_obj_create(card);
        lv_obj_remove_style_all(chips);
        lv_obj_set_width(chips, lv_pct(100));
        lv_obj_set_height(chips, LV_SIZE_CONTENT);
        lv_obj_set_flex_flow(chips, LV_FLEX_FLOW_ROW_WRAP);
        lv_obj_set_style_pad_column(chips, MOD_UI_SPACE_SM, 0);
        lv_obj_set_style_pad_row(chips, MOD_UI_SPACE_SM, 0);
        settings_no_scroll(chips);
        macro_assist_chip(chips, "M65 P0", "M65 P0");
        macro_assist_chip(chips, "M9", "M9");
        macro_assist_chip(chips, "M64 P0", "M64 P0");
        macro_assist_chip(chips, "M8", "M8");
    }

    macro_build_icon_row(card);

    lv_obj_t *row = modulus_ui_dialog_actions(card, true);

    if (is_edit) {
        modulus_ui_dialog_action_btn(row, "Delete", MOD_UI_DIALOG_BTN_DESTRUCTIVE, macro_delete_cb,
                                     NULL);
    }

    modulus_ui_dialog_action_btn(row, "Cancel", MOD_UI_DIALOG_BTN_TONAL, macro_close_cb, NULL);
    modulus_ui_dialog_action_btn(row, "Save", MOD_UI_DIALOG_BTN_FILLED, macro_save_cb, NULL);

    s_macro_kb = lv_keyboard_create(s_macro_modal);
    lv_keyboard_set_mode(s_macro_kb, LV_KEYBOARD_MODE_TEXT_UPPER);
    settings_modal_kb_configure_text(s_macro_kb);
    lv_keyboard_set_textarea(s_macro_kb, s_ta_name);
}

void settings_macro_modal_show(void)
{
    settings_macro_slot_modal_show(-1);
}

void settings_macro_modal_theme_refresh(void)
{
    if (s_macro_kb) {
        modulus_ui_apply_keyboard_theme(s_macro_kb);
    }
    modulus_ui_apply_textarea_theme(s_ta_name, false);
    modulus_ui_apply_textarea_theme(s_ta_on, false);
    modulus_ui_apply_textarea_theme(s_ta_off, false);
    modulus_ui_dialog_theme_refresh(s_macro_modal);
}
