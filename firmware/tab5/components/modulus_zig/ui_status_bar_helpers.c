#include "ui_status_bar_priv.h"
#include "ui_internal.h"

void bar_no_scroll(lv_obj_t *obj)
{
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLLABLE);
    /* lv_obj defaults to CLICKABLE — chrome children were eating hits so bar/group
     * QS gestures (double-tap / long-press) never fired. Re-add CLICKABLE only on
     * real controls (MPG, WCS, gear, power) and QS gesture targets. */
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_CLICKABLE);
}

static void bar_label_font(lv_obj_t *lbl, lv_color_t color, const lv_font_t *font)
{
    lv_obj_set_style_text_color(lbl, color, 0);
    lv_obj_set_style_text_font(lbl, font, 0);
}

lv_obj_t *bar_divider(lv_obj_t *parent)
{
    lv_obj_t *div = lv_obj_create(parent);
    lv_obj_remove_style_all(div);
    bar_no_scroll(div);
    lv_obj_set_size(div, 1, 32);
    lv_obj_set_style_bg_color(div, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_bg_opa(div, LV_OPA_40, 0);
    return div;
}

lv_obj_t *bar_make_pill(lv_obj_t *parent, const char *text, lv_color_t bg, lv_color_t fg)
{
    lv_obj_t *pill = lv_obj_create(parent);
    lv_obj_remove_style_all(pill);
    bar_no_scroll(pill);
    lv_obj_set_size(pill, LV_SIZE_CONTENT, MOD_UI_TOUCH_MIN);
    lv_obj_set_style_bg_color(pill, bg, 0);
    lv_obj_set_style_bg_opa(pill, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(pill, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_pad_hor(pill, MOD_UI_SPACE_MD, 0);
    lv_obj_set_style_pad_ver(pill, MOD_UI_SPACE_XS + MOD_UI_SPACE_XS / 2, 0);
    modulus_ui_bind_press_morph(pill, MOD_UI_SHAPE_FULL, MOD_UI_SHAPE_MD);
    lv_obj_t *lbl = lv_label_create(pill);
    bar_label_font(lbl, fg, MOD_UI_FONT_BODY_L);
    lv_obj_set_style_text_letter_space(lbl, 1, 0);
    lv_label_set_long_mode(lbl, LV_LABEL_LONG_CLIP);
    lv_label_set_text(lbl, text);
    lv_obj_center(lbl);
    bar_no_scroll(lbl);
    return pill;
}

/* Stat column: caption (montserrat_14) over value row (montserrat_24) with optional
 * unit (montserrat_14). CONTENT sizing prevents 80px bar clipping. WCS/TOOL use
 * left-aligned captions; FEED/SPINDLE pass right_align so caption + unit share the
 * same right edge (column + value-row min_width, cross/main flex END, space label
 * between value and unit — never lv_pct(100) on children, collapses col). */
lv_obj_t *bar_stat_col(lv_obj_t *parent, const char *hdr, const char *val, const char *unit,
                       lv_obj_t **out_hdr, lv_obj_t **out_val, lv_obj_t **out_unit,
                       bool clickable, bool right_align, int val_row_min_width)
{
    const bool unit_right = right_align && unit != NULL && out_unit != NULL;

    lv_obj_t *col = lv_obj_create(parent);
    lv_obj_remove_style_all(col);
    bar_no_scroll(col);
    lv_obj_set_size(col, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(col, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(col, 2, 0);
    if (unit_right) {
        lv_obj_set_flex_align(col, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_END, LV_FLEX_ALIGN_END);
        if (val_row_min_width > 0) {
            lv_obj_set_style_min_width(col, (lv_coord_t)val_row_min_width, 0);
        }
    } else {
        lv_obj_set_flex_align(col, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    }

    lv_obj_t *h = lv_label_create(col);
    bar_label_font(h, modulus_ui_color_on_surface_variant(), MOD_UI_FONT_LABEL_L);
    lv_obj_set_style_text_letter_space(h, 1, 0);
    lv_label_set_long_mode(h, LV_LABEL_LONG_CLIP);
    lv_label_set_text(h, hdr);
    bar_no_scroll(h);
    if (out_hdr) {
        *out_hdr = h;
    }

    lv_obj_t *vu = lv_obj_create(col);
    lv_obj_remove_style_all(vu);
    bar_no_scroll(vu);
    lv_obj_set_size(vu, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(vu, LV_FLEX_FLOW_ROW);
    if (unit_right) {
        lv_obj_set_flex_align(vu, LV_FLEX_ALIGN_END, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
        if (val_row_min_width > 0) {
            lv_obj_set_style_min_width(vu, (lv_coord_t)val_row_min_width, 0);
        }
    } else {
        lv_obj_set_style_pad_column(vu, 2, 0);
        lv_obj_set_flex_align(vu, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    }

    *out_val = lv_label_create(vu);
    bar_label_font(*out_val, modulus_ui_color_on_surface(), MOD_UI_FONT_TITLE_L);
    lv_label_set_long_mode(*out_val, LV_LABEL_LONG_CLIP);
    lv_label_set_text(*out_val, val);
    bar_no_scroll(*out_val);

    if (out_unit) {
        *out_unit = NULL;
    }
    if (unit && out_unit) {
        if (unit_right) {
            lv_obj_t *gap = lv_label_create(vu);
            bar_label_font(gap, modulus_ui_color_on_surface(), MOD_UI_FONT_TITLE_L);
            lv_label_set_text(gap, " ");
            bar_no_scroll(gap);
        }
        *out_unit = lv_label_create(vu);
        bar_label_font(*out_unit, modulus_ui_color_on_surface_variant(), MOD_UI_FONT_LABEL_L);
        lv_label_set_long_mode(*out_unit, LV_LABEL_LONG_CLIP);
        lv_label_set_text(*out_unit, unit);
        bar_no_scroll(*out_unit);
    }

    if (clickable) {
        lv_obj_add_flag(col, LV_OBJ_FLAG_CLICKABLE);
    }
    return col;
}
