#include "ui_settings_priv.h"

#include <stdio.h>

/* Right-anchored value + chevron group used by action rows. */
static lv_obj_t *row_right_group(lv_obj_t *row)
{
    lv_obj_t *rg = lv_obj_create(row);
    lv_obj_remove_style_all(rg);
    lv_obj_set_size(rg, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(rg, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(rg, LV_FLEX_ALIGN_END, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(rg, MOD_UI_SPACE_SM, 0);
    settings_no_scroll(rg);
    return rg;
}

lv_obj_t *settings_action_row(lv_obj_t *parent, const char *label, const char *value)
{
    lv_obj_t *row = settings_row_base(parent, 48, true);
    settings_row_label(row, label);
    lv_obj_t *rg = row_right_group(row);
    if (value && value[0]) {
        lv_obj_t *val = lv_label_create(rg);
        lv_label_set_text(val, value);
        lv_obj_set_style_text_color(val, modulus_ui_color_on_surface_variant(), 0);
        lv_obj_set_style_text_font(val, MOD_UI_FONT_BODY_M, 0);
    }
    lv_obj_t *chev = lv_label_create(rg);
    lv_label_set_text(chev, LV_SYMBOL_RIGHT);
    lv_obj_set_style_text_color(chev, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(chev, MOD_UI_FONT_BODY_L, 0);
    modulus_ui_touch_expand(row, 12);
    /* Soft morph on press — rows are full-width, so rest stays MD radius. */
    lv_obj_set_style_radius(row, MOD_UI_SHAPE_SM, 0);
    modulus_ui_bind_press_morph(row, MOD_UI_SHAPE_SM, MOD_UI_SHAPE_XS);
    return row;
}

lv_obj_t *settings_destructive_row(lv_obj_t *parent, const char *label, const char *value)
{
    lv_obj_t *row = settings_action_row(parent, label, value);
    lv_obj_t *lbl = lv_obj_get_child(row, 0);
    if (lbl) {
        lv_obj_set_style_text_color(lbl, modulus_ui_color_error(), 0);
    }
    return row;
}

lv_obj_t *settings_toggle_row(lv_obj_t *parent, const char *label, bool on)
{
    lv_obj_t *row = settings_row_base(parent, 48, false);
    settings_row_label(row, label);
    lv_obj_t *sw = lv_switch_create(row);
    lv_obj_set_size(sw, 52, 32);
    modulus_ui_touch_expand(sw, 8);
    modulus_ui_apply_switch_theme(sw);
    modulus_ui_touch_ensure_min(sw);
    if (on) {
        lv_obj_add_state(sw, LV_STATE_CHECKED);
    }
    return sw;
}

lv_obj_t *settings_slider_row(lv_obj_t *parent, const char *label,
                              int32_t val, int32_t min_v, int32_t max_v)
{
    lv_obj_t *row = settings_row_base(parent, 52, false);
    settings_row_label(row, label);
    lv_obj_t *rg = lv_obj_create(row);
    lv_obj_remove_style_all(rg);
    lv_obj_set_size(rg, 300, 40);
    lv_obj_set_flex_flow(rg, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(rg, LV_FLEX_ALIGN_END, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(rg, MOD_UI_SPACE_SM + MOD_UI_SPACE_XS, 0);
    settings_no_scroll(rg);
    lv_obj_t *sl = lv_slider_create(rg);
    lv_obj_set_width(sl, 230);
    lv_slider_set_range(sl, min_v, max_v);
    lv_slider_set_value(sl, val, LV_ANIM_OFF);
    modulus_ui_apply_slider_theme(sl);
    lv_obj_t *vl = lv_label_create(rg);
    char buf[12];
    snprintf(buf, sizeof(buf), "%ld", (long)val);
    lv_label_set_text(vl, buf);
    lv_obj_set_style_text_color(vl, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(vl, MOD_UI_FONT_BODY_M, 0);
    lv_obj_set_style_min_width(vl, 38, 0);
    lv_obj_set_user_data(sl, vl);
    return sl;
}

lv_obj_t *settings_dropdown_row(lv_obj_t *parent, const char *label,
                                const char *options, uint16_t selected)
{
    lv_obj_t *row = settings_row_base(parent, 52, false);
    settings_row_label(row, label);
    lv_obj_t *dd = lv_dropdown_create(row);
    lv_dropdown_set_options(dd, options);
    lv_dropdown_set_selected(dd, selected);
    lv_obj_set_width(dd, 180);
    modulus_ui_apply_dropdown_theme(dd);
    return dd;
}

/* All options visible, one tap to change — the MD3 replacement for small
 * dropdowns. Forwards VALUE_CHANGED on the track so call sites keep the
 * familiar lv_obj_add_event_cb(seg, cb, LV_EVENT_VALUE_CHANGED, ud) shape. */
static void seg_row_click_fwd_cb(lv_event_t *e)
{
    lv_obj_t *btn = lv_event_get_target(e);
    lv_obj_t *track = lv_obj_get_parent(btn);
    modulus_ui_segmented_set_selected(track, (uint8_t)lv_obj_get_index(btn));
    lv_obj_send_event(track, LV_EVENT_VALUE_CHANGED, NULL);
}

lv_obj_t *settings_segmented_row(lv_obj_t *parent, const char *label,
                                 const char *const *labels, uint8_t count,
                                 uint8_t selected, lv_coord_t seg_w)
{
    lv_obj_t *row = settings_row_base(parent, 60, false);
    settings_row_label(row, label);
    lv_obj_t *seg = modulus_ui_segmented_create(row, labels, count, seg_w,
                                                seg_row_click_fwd_cb, NULL);
    if (seg) {
        modulus_ui_segmented_set_selected(seg, selected < count ? selected : 0);
    }
    return seg;
}

lv_obj_t *settings_text_input_row(lv_obj_t *parent, const char *label,
                                  const char *text, int max_len,
                                  const char *accepted)
{
    lv_obj_t *row = settings_row_base(parent, 52, false);
    settings_row_label(row, label);
    lv_obj_t *ta = lv_textarea_create(row);
    lv_textarea_set_text(ta, text);
    lv_textarea_set_max_length(ta, max_len);
    if (accepted) {
        lv_textarea_set_accepted_chars(ta, accepted);
    }
    lv_textarea_set_one_line(ta, true);
    lv_obj_set_width(ta, 200);
    modulus_ui_apply_textarea_theme(ta, false);
    return ta;
}
