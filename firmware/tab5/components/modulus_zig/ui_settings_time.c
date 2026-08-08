#include "ui_settings_time.h"
#include "ui_settings_common.h"
#include "ui_settings_priv.h"
#include "ui_internal.h"
#include "rtc_shim.h"

#include <lvgl.h>
#include <stdio.h>
#include <stdlib.h>

static lv_obj_t *s_modal = NULL;
static lv_obj_t *s_kb = NULL;
static lv_obj_t *s_te_year = NULL;
static lv_obj_t *s_te_mon = NULL;
static lv_obj_t *s_te_day = NULL;
static lv_obj_t *s_te_hour = NULL;
static lv_obj_t *s_te_min = NULL;
static lv_obj_t *s_te_sec = NULL;

static void field_focus_cb(lv_event_t *e);

static lv_obj_t *make_num_field(lv_obj_t *parent, const char *text, int max_len, int width)
{
    lv_obj_t *ta = lv_textarea_create(parent);
    lv_textarea_set_text(ta, text);
    lv_textarea_set_max_length(ta, max_len);
    lv_textarea_set_accepted_chars(ta, "0123456789");
    lv_textarea_set_one_line(ta, true);
    lv_obj_set_width(ta, width);
    modulus_ui_apply_textarea_theme(ta, false);
    lv_obj_add_event_cb(ta, field_focus_cb, LV_EVENT_FOCUSED, NULL);
    return ta;
}

static void field_focus_cb(lv_event_t *e)
{
    if (s_kb) {
        lv_keyboard_set_textarea(s_kb, lv_event_get_target(e));
    }
}

static void cancel_cb(lv_event_t *e)
{
    (void)e;
    settings_time_modal_hide();
}

static void apply_cb(lv_event_t *e)
{
    (void)e;
    int yr = atoi(lv_textarea_get_text(s_te_year));
    int mo = atoi(lv_textarea_get_text(s_te_mon));
    int dy = atoi(lv_textarea_get_text(s_te_day));
    int hr = atoi(lv_textarea_get_text(s_te_hour));
    int mn = atoi(lv_textarea_get_text(s_te_min));
    int sc = atoi(lv_textarea_get_text(s_te_sec));
    if (yr < 2020) {
        yr = 2020;
    }
    if (yr > 2099) {
        yr = 2099;
    }
    if (mo < 1) {
        mo = 1;
    }
    if (mo > 12) {
        mo = 12;
    }
    if (dy < 1) {
        dy = 1;
    }
    if (dy > 31) {
        dy = 31;
    }
    if (hr > 23) {
        hr = 23;
    }
    if (mn > 59) {
        mn = 59;
    }
    if (sc > 59) {
        sc = 59;
    }
    modulus_rtc_set_local_time(yr, mo, dy, hr, mn, sc);
    settings_time_modal_hide();
    modulus_ui_settings_system_tab_refresh();
}

static lv_obj_t *make_sep_label(lv_obj_t *parent, const char *text)
{
    lv_obj_t *l = lv_label_create(parent);
    lv_label_set_text(l, text);
    return l;
}

void settings_time_modal_hide(void)
{
    if (!s_modal) {
        s_kb = NULL;
        s_te_year = NULL;
        s_te_mon = NULL;
        s_te_day = NULL;
        s_te_hour = NULL;
        s_te_min = NULL;
        s_te_sec = NULL;
        return;
    }
    s_kb = NULL;
    s_te_year = NULL;
    s_te_mon = NULL;
    s_te_day = NULL;
    s_te_hour = NULL;
    s_te_min = NULL;
    s_te_sec = NULL;
    modulus_ui_dialog_scrim_hide_animated(&s_modal);
}

void settings_time_modal_show(void)
{
    if (s_modal) {
        return;
    }

    struct tm now = {};
    modulus_rtc_get_local_time(&now);

    s_modal = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(s_modal);
    lv_obj_set_size(s_modal, lv_pct(100), lv_pct(100));
    modulus_ui_apply_overlay_scrim(s_modal);
    lv_obj_add_flag(s_modal, LV_OBJ_FLAG_CLICKABLE);

    lv_obj_t *card = lv_obj_create(s_modal);
    lv_obj_remove_style_all(card);
    lv_obj_set_size(card, 500, 260);
    lv_obj_align(card, LV_ALIGN_TOP_MID, 0, 30);
    lv_obj_set_style_bg_color(card, modulus_ui_color_surface_container_highest(), 0);
    lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(card, MOD_UI_SHAPE_XL, 0);
    lv_obj_set_style_border_color(card, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_border_width(card, 1, 0);
    lv_obj_set_style_pad_all(card, 20, 0);
    lv_obj_set_flex_flow(card, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(card, MOD_UI_SPACE_SM + MOD_UI_SPACE_XS, 0);

    lv_obj_t *title = lv_label_create(card);
    lv_label_set_text(title, "Set date and time");
    lv_obj_set_style_text_font(title, MOD_UI_FONT_TITLE_M, 0);

    char buf[16];

    lv_obj_t *dr = lv_obj_create(card);
    lv_obj_remove_style_all(dr);
    lv_obj_set_width(dr, lv_pct(100));
    lv_obj_set_height(dr, 48);
    lv_obj_set_flex_flow(dr, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(dr, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(dr, MOD_UI_SPACE_SM, 0);
    lv_obj_t *dl = lv_label_create(dr);
    lv_label_set_text(dl, "Date");
    snprintf(buf, sizeof(buf), "%04d", now.tm_year + 1900);
    s_te_year = make_num_field(dr, buf, 4, 80);
    make_sep_label(dr, "-");
    snprintf(buf, sizeof(buf), "%02d", now.tm_mon + 1);
    s_te_mon = make_num_field(dr, buf, 2, 60);
    make_sep_label(dr, "-");
    snprintf(buf, sizeof(buf), "%02d", now.tm_mday);
    s_te_day = make_num_field(dr, buf, 2, 60);

    lv_obj_t *tr = lv_obj_create(card);
    lv_obj_remove_style_all(tr);
    lv_obj_set_width(tr, lv_pct(100));
    lv_obj_set_height(tr, 48);
    lv_obj_set_flex_flow(tr, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(tr, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(tr, MOD_UI_SPACE_SM, 0);
    lv_obj_t *tl = lv_label_create(tr);
    lv_label_set_text(tl, "Time");
    snprintf(buf, sizeof(buf), "%02d", now.tm_hour);
    s_te_hour = make_num_field(tr, buf, 2, 60);
    make_sep_label(tr, ":");
    snprintf(buf, sizeof(buf), "%02d", now.tm_min);
    s_te_min = make_num_field(tr, buf, 2, 60);
    make_sep_label(tr, ":");
    snprintf(buf, sizeof(buf), "%02d", now.tm_sec);
    s_te_sec = make_num_field(tr, buf, 2, 60);

    lv_obj_t *br = modulus_ui_dialog_actions(card, true);
    modulus_ui_dialog_action_btn(br, "Cancel", MOD_UI_DIALOG_BTN_TONAL, cancel_cb, NULL);
    modulus_ui_dialog_action_btn(br, "Apply", MOD_UI_DIALOG_BTN_FILLED, apply_cb, NULL);

    s_kb = lv_keyboard_create(s_modal);
    lv_keyboard_set_mode(s_kb, LV_KEYBOARD_MODE_NUMBER);
    lv_obj_align(s_kb, LV_ALIGN_BOTTOM_MID, 0, 0);
    modulus_ui_apply_keyboard_theme(s_kb);
    lv_keyboard_set_textarea(s_kb, s_te_year);
}

void settings_time_modal_theme_refresh(void)
{
    if (s_kb) {
        modulus_ui_apply_keyboard_theme(s_kb);
    }
    modulus_ui_apply_textarea_theme(s_te_year, false);
    modulus_ui_apply_textarea_theme(s_te_mon, false);
    modulus_ui_apply_textarea_theme(s_te_day, false);
    modulus_ui_apply_textarea_theme(s_te_hour, false);
    modulus_ui_apply_textarea_theme(s_te_min, false);
    modulus_ui_apply_textarea_theme(s_te_sec, false);
    if (s_modal) {
        modulus_ui_apply_overlay_scrim(s_modal);
        lv_obj_t *card = lv_obj_get_child(s_modal, 0);
        if (card) {
            lv_obj_set_style_bg_color(card, modulus_ui_color_surface_container_highest(), 0);
            lv_obj_set_style_border_color(card, modulus_ui_color_outline_variant(), 0);
        }
    }
}
