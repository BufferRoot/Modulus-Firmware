#include "ui_internal.h"
#include "cnc_cmd_exports.h"

#include <stdio.h>
#include <stdint.h>

typedef struct {
    lv_obj_t *lbl_value;
    lv_obj_t *btn_up;
    lv_obj_t *btn_dn;
    lv_obj_t *btn_rst;
} override_col_t;

typedef struct {
    lv_obj_t *container;
    override_col_t feed;
    override_col_t spindle;
} overrides_widget_t;

static overrides_widget_t s_ovr = {};

#define OVR_NO_SCROLL(o) lv_obj_remove_flag((o), LV_OBJ_FLAG_SCROLLABLE)

static void up_click_cb(lv_event_t *e)
{
    const uintptr_t which = (uintptr_t)lv_event_get_user_data(e);
    if (which == 0) {
        modulus_zig_cmd_feed_override(10);
    } else {
        modulus_zig_cmd_spindle_override(10);
    }
}

static void down_click_cb(lv_event_t *e)
{
    const uintptr_t which = (uintptr_t)lv_event_get_user_data(e);
    if (which == 0) {
        modulus_zig_cmd_feed_override(-10);
    } else {
        modulus_zig_cmd_spindle_override(-10);
    }
}

static void reset_click_cb(lv_event_t *e)
{
    const uintptr_t which = (uintptr_t)lv_event_get_user_data(e);
    if (which == 0) {
        modulus_zig_cmd_feed_override(0);
    } else {
        modulus_zig_cmd_spindle_override(0);
    }
}

static void style_pct_label(lv_obj_t *lbl)
{
    lv_obj_set_style_text_color(lbl, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_font(lbl, MOD_UI_FONT_DISPLAY_M, 0);
    lv_obj_set_style_text_align(lbl, LV_TEXT_ALIGN_CENTER, 0);
}

static lv_obj_t *circle_btn(lv_obj_t *parent, modulus_ui_icon_id_t icon, lv_event_cb_t cb, uintptr_t which)
{
    lv_obj_t *btn = lv_obj_create(parent);
    lv_obj_remove_style_all(btn);
    OVR_NO_SCROLL(btn);
    lv_obj_set_size(btn, 68, 68);
    lv_obj_set_style_bg_color(btn, modulus_ui_color_surface_container_high(), 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
    modulus_ui_apply_pressed_state_layer(btn);
    /* Expressive: circle at rest → squarer on press. */
    modulus_ui_bind_press_morph(btn, LV_RADIUS_CIRCLE, MOD_UI_SHAPE_MD);
    lv_obj_add_event_cb(btn, cb, LV_EVENT_CLICKED, (void *)which);
    lv_obj_t *ico = modulus_ui_icon_create(btn, icon, MOD_UI_ICON_SZ_32);
    modulus_ui_icon_recolor(ico, modulus_ui_color_icon_chrome());
    lv_obj_center(ico);
    return btn;
}

static void make_col(lv_obj_t *parent, const char *title, override_col_t *col, uintptr_t which)
{
    lv_obj_t *box = lv_obj_create(parent);
    lv_obj_remove_style_all(box);
    OVR_NO_SCROLL(box);
    lv_obj_set_flex_grow(box, 1);
    lv_obj_set_height(box, lv_pct(100));
    lv_obj_set_style_bg_color(box, modulus_ui_color_surface_container_low(), 0);
    lv_obj_set_style_bg_opa(box, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(box, MOD_UI_SHAPE_CARD, 0);
    lv_obj_set_style_pad_all(box, MOD_UI_SPACE_MD, 0);
    lv_obj_set_flex_flow(box, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(box, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);

    lv_obj_t *hdr = lv_label_create(box);
    lv_label_set_text(hdr, title);
    lv_obj_set_width(hdr, lv_pct(100));
    lv_obj_set_style_text_align(hdr, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_text_color(hdr, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_font(hdr, MOD_UI_FONT_BODY_M, 0);
    lv_obj_set_style_text_letter_space(hdr, 1, 0);

    col->btn_up = circle_btn(box, MOD_UI_ICON_ARROW_UP, up_click_cb, which);
    col->lbl_value = lv_label_create(box);
    lv_label_set_text(col->lbl_value, "100%");
    lv_obj_set_width(col->lbl_value, lv_pct(100));
    style_pct_label(col->lbl_value);
    col->btn_dn = circle_btn(box, MOD_UI_ICON_ARROW_DOWN, down_click_cb, which);

    lv_obj_t *rst = lv_obj_create(box);
    col->btn_rst = rst;
    lv_obj_remove_style_all(rst);
    OVR_NO_SCROLL(rst);
    lv_obj_set_width(rst, lv_pct(80));
    lv_obj_set_height(rst, 44);
    lv_obj_set_style_min_height(rst, 44, 0);
    lv_obj_set_style_bg_color(rst, modulus_ui_color_surface_container_high(), 0);
    lv_obj_set_style_bg_opa(rst, LV_OPA_COVER, 0);
    lv_obj_add_flag(rst, LV_OBJ_FLAG_CLICKABLE);
    modulus_ui_apply_pressed_state_layer(rst);
    modulus_ui_bind_press_morph(rst, MOD_UI_SHAPE_FULL, MOD_UI_SHAPE_MD);
    lv_obj_add_event_cb(rst, reset_click_cb, LV_EVENT_CLICKED, (void *)which);
    lv_obj_t *rst_lbl = lv_label_create(rst);
    lv_label_set_text(rst_lbl, "Reset");
    lv_obj_set_style_text_color(rst_lbl, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_font(rst_lbl, MOD_UI_FONT_BODY_M, 0);
    lv_obj_center(rst_lbl);
}

void modulus_ui_overrides_create(lv_obj_t *parent)
{
    s_ovr.container = lv_obj_create(parent);
    lv_obj_remove_style_all(s_ovr.container);
    OVR_NO_SCROLL(s_ovr.container);
    lv_obj_set_width(s_ovr.container, lv_pct(100));
    lv_obj_set_flex_grow(s_ovr.container, 1);
    lv_obj_set_flex_flow(s_ovr.container, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(s_ovr.container, MOD_UI_SPACE_LG, 0);

    make_col(s_ovr.container, "Feed override", &s_ovr.feed, 0);
    make_col(s_ovr.container, "Spindle override", &s_ovr.spindle, 1);
}

static void ovr_refresh_col(override_col_t *col, lv_obj_t *box)
{
    if (box) {
        lv_obj_set_style_bg_color(box, modulus_ui_color_surface_container_low(), 0);
    }
    if (col->btn_up) {
        lv_obj_set_style_bg_color(col->btn_up, modulus_ui_color_surface_container_high(), 0);
        lv_obj_t *ico = lv_obj_get_child(col->btn_up, 0);
        if (ico) {
            modulus_ui_icon_recolor(ico, modulus_ui_color_icon_chrome());
        }
    }
    if (col->btn_dn) {
        lv_obj_set_style_bg_color(col->btn_dn, modulus_ui_color_surface_container_high(), 0);
        lv_obj_t *ico = lv_obj_get_child(col->btn_dn, 0);
        if (ico) {
            modulus_ui_icon_recolor(ico, modulus_ui_color_icon_chrome());
        }
    }
    if (col->btn_rst) {
        lv_obj_set_style_bg_color(col->btn_rst, modulus_ui_color_surface_container_high(), 0);
        lv_obj_t *lbl = lv_obj_get_child(col->btn_rst, 0);
        if (lbl) {
            lv_obj_set_style_text_color(lbl, modulus_ui_color_on_surface(), 0);
        }
    }
    if (col->lbl_value) {
        style_pct_label(col->lbl_value);
    }
}

void modulus_ui_overrides_theme_refresh(void)
{
    if (!s_ovr.container) {
        return;
    }
    const uint32_t n = lv_obj_get_child_count(s_ovr.container);
    if (n >= 1) {
        ovr_refresh_col(&s_ovr.feed, lv_obj_get_child(s_ovr.container, 0));
    }
    if (n >= 2) {
        ovr_refresh_col(&s_ovr.spindle, lv_obj_get_child(s_ovr.container, 1));
    }
}

void modulus_ui_overrides_update(const modulus_cnc_status_t *st)
{
    if (!s_ovr.feed.lbl_value || !st) {
        return;
    }
    static uint8_t s_feed = 0xFF;
    static uint8_t s_spindle = 0xFF;
    char buf[12];
    if (st->feed_ovr != s_feed) {
        s_feed = st->feed_ovr;
        snprintf(buf, sizeof(buf), "%u%%", st->feed_ovr);
        modulus_ui_label_set_text_if_changed(s_ovr.feed.lbl_value, buf);
    }
    if (st->spindle_ovr != s_spindle) {
        s_spindle = st->spindle_ovr;
        snprintf(buf, sizeof(buf), "%u%%", st->spindle_ovr);
        modulus_ui_label_set_text_if_changed(s_ovr.spindle.lbl_value, buf);
    }
}
