#include "ui_settings_priv.h"

#include "nvs_shim.h"

static lv_obj_t *s_panel = NULL;

void modulus_ui_settings_set_content_panel(lv_obj_t *panel) { s_panel = panel; }
lv_obj_t *modulus_ui_settings_panel(void) { return s_panel; }

void settings_no_scroll(lv_obj_t *obj)
{
    /* Make the object itself non-scrollable, but KEEP LV_OBJ_FLAG_SCROLL_CHAIN:
     * interactive children (tab buttons, rows) cover their scrollable parent
     * wall-to-wall, and LVGL's scroll-target walk stops at the first object
     * without the chain flag — stripping it here made the sidebar (and any
     * row-dense list) impossible to scroll by dragging on its children. */
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLL_ELASTIC);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLL_MOMENTUM);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SNAPPABLE);
}

#define SETTINGS_SCROLL_ANIM_MS 100

void settings_tune_scroll_container(lv_obj_t *obj)
{
    const bool smooth = modulus_nvs_get_u8("smooth_anim", 1) != 0;
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLL_ELASTIC);
    if (smooth) {
        lv_obj_add_flag(obj, LV_OBJ_FLAG_SCROLL_MOMENTUM);
        lv_obj_set_style_anim_duration(obj, SETTINGS_SCROLL_ANIM_MS, LV_PART_MAIN);
    } else {
        lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLL_MOMENTUM);
        lv_obj_set_style_anim_duration(obj, 0, LV_PART_MAIN);
    }
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLL_CHAIN);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SNAPPABLE);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_OVERFLOW_VISIBLE);
    lv_obj_set_scroll_snap_x(obj, LV_SCROLL_SNAP_NONE);
    lv_obj_set_scroll_snap_y(obj, LV_SCROLL_SNAP_NONE);
    lv_obj_set_style_anim_duration(obj, 0, LV_PART_SCROLLBAR);
    lv_obj_set_scrollbar_mode(obj, LV_SCROLLBAR_MODE_ACTIVE);
    lv_obj_set_style_clip_corner(obj, true, 0);
    /* Bottom reachability: without end padding the last row parks flush against
     * the clipped edge and a short flick often stops one row shy. 48 px of
     * overscroll room guarantees the final option lands fully visible. */
    lv_obj_set_style_pad_bottom(obj, MOD_UI_TOUCH_MIN, 0);
}

void settings_tune_sidebar_scroll(lv_obj_t *obj)
{
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLL_ELASTIC);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLL_MOMENTUM);
    lv_obj_set_style_anim_duration(obj, 0, LV_PART_MAIN);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLL_CHAIN);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SNAPPABLE);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_OVERFLOW_VISIBLE);
    lv_obj_set_scroll_snap_x(obj, LV_SCROLL_SNAP_NONE);
    lv_obj_set_scroll_snap_y(obj, LV_SCROLL_SNAP_NONE);
    lv_obj_set_style_anim_duration(obj, 0, LV_PART_SCROLLBAR);
    lv_obj_set_scrollbar_mode(obj, LV_SCROLLBAR_MODE_AUTO);
    lv_obj_set_style_clip_corner(obj, true, 0);
}

void settings_bind_menu_click(lv_obj_t *obj, lv_event_cb_t cb, void *user_data)
{
    modulus_ui_bind_menu_click(obj, cb, user_data);
}

/* Shared row scaffold: full width, fixed height, hairline bottom divider,
 * label-left / control-right flex. Matches C++ add_*_row geometry. */
lv_obj_t *settings_row_base(lv_obj_t *parent, int height, bool clickable)
{
    lv_obj_t *row = lv_obj_create(parent);
    lv_obj_remove_style_all(row);
    lv_obj_set_width(row, lv_pct(100));
    lv_obj_set_height(row, height);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_hor(row, MOD_UI_SPACE_MD, 0);
    lv_obj_set_style_border_width(row, 1, 0);
    lv_obj_set_style_border_side(row, LV_BORDER_SIDE_BOTTOM, 0);
    lv_obj_set_style_border_color(row, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_border_opa(row, LV_OPA_30, 0);
    settings_no_scroll(row);
    if (clickable) {
        lv_obj_add_flag(row, LV_OBJ_FLAG_CLICKABLE);
        modulus_ui_apply_pressed_state_layer(row);
    }
    return row;
}

lv_obj_t *settings_row_label(lv_obj_t *row, const char *text)
{
    lv_obj_t *lbl = lv_label_create(row);
    lv_label_set_text(lbl, text);
    lv_obj_set_style_text_color(lbl, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_font(lbl, MOD_UI_FONT_BODY_L, 0);
    return lbl;
}

lv_color_t modulus_settings_status_color(int kind)
{
    switch (kind) {
    case SETTINGS_STATUS_OK:   return modulus_ui_color_success();
    case SETTINGS_STATUS_WARN: return modulus_ui_color_warning();
    case SETTINGS_STATUS_ERR:  return modulus_ui_color_error();
    default:                   return modulus_ui_color_on_surface_variant();
    }
}

lv_color_t modulus_settings_cnc_transport_color(uint8_t idx, bool active)
{
    if (!active || idx >= 8) {
        return modulus_ui_color_on_surface_variant();
    }
    switch (idx) {
    case 0:
        return modulus_ui_color_secondary();
    case 1:
    case 2:
        return modulus_ui_color_primary();
    case 3:
    case 4:
        return modulus_ui_color_warning();
    case 5:
        return modulus_ui_color_tertiary();
    case 6:
        return modulus_ui_color_neutral();
    case 7:
        return modulus_ui_color_outline();
    default:
        return modulus_ui_color_on_surface_variant();
    }
}

void settings_section(lv_obj_t *parent, const char *title, const char *subtitle)
{
    lv_obj_t *hdr = lv_label_create(parent);
    lv_label_set_text(hdr, title);
    lv_obj_set_width(hdr, lv_pct(100));
    lv_obj_set_style_text_color(hdr, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(hdr, MOD_UI_FONT_TITLE_S, 0);
    lv_obj_set_style_pad_top(hdr, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_pad_bottom(hdr, subtitle ? MOD_UI_SPACE_XS : MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_pad_hor(hdr, MOD_UI_SPACE_SM, 0);
    if (!subtitle) {
        return;
    }
    lv_obj_t *sub = lv_label_create(parent);
    lv_label_set_text(sub, subtitle);
    lv_obj_set_width(sub, lv_pct(100));
    lv_label_set_long_mode(sub, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_color(sub, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_opa(sub, LV_OPA_70, 0);
    lv_obj_set_style_text_font(sub, MOD_UI_FONT_BODY_M, 0);
    lv_obj_set_style_pad_hor(sub, MOD_UI_SPACE_SM + MOD_UI_SPACE_XS, 0);
    lv_obj_set_style_pad_bottom(sub, MOD_UI_SPACE_XS, 0);
}

void settings_note(lv_obj_t *parent, const char *text)
{
    lv_obj_t *note = lv_label_create(parent);
    lv_label_set_text(note, text);
    lv_obj_set_width(note, lv_pct(100));
    lv_label_set_long_mode(note, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_color(note, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(note, MOD_UI_FONT_BODY_M, 0);
    lv_obj_set_style_pad_hor(note, MOD_UI_SPACE_SM, 0);
}

lv_obj_t *settings_detail_row(lv_obj_t *parent, const char *label, const char *value)
{
    lv_obj_t *row = settings_row_base(parent, 48, false);
    settings_row_label(row, label);
    lv_obj_t *val = lv_label_create(row);
    lv_label_set_text(val, value);
    lv_obj_set_style_text_color(val, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(val, MOD_UI_FONT_BODY_M, 0);
    return val;
}
