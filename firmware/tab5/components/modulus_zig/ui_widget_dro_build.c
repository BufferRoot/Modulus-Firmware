#include "ui_internal.h"
#include "ui_widget_dro_priv.h"

#define DRO_NO_SCROLL(o) lv_obj_remove_flag((o), LV_OBJ_FLAG_SCROLLABLE)

static const char *k_axis_names[] = {"X", "Y", "Z", "A", "B", "C"};

static lv_obj_t *dro_action_btn(lv_obj_t *parent, modulus_ui_icon_id_t icon, const char *text,
                                lv_event_cb_t cb, uintptr_t idx, int btn_w, int btn_h)
{
    lv_obj_t *btn = lv_obj_create(parent);
    lv_obj_remove_style_all(btn);
    DRO_NO_SCROLL(btn);
    lv_obj_set_size(btn, btn_w, btn_h);
    lv_obj_set_style_bg_color(btn, modulus_ui_color_surface_container_high(), 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(btn, MOD_UI_SHAPE_MD, 0);
    lv_obj_set_flex_flow(btn, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(btn, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(btn, MOD_UI_SPACE_XS, 0);
    lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
    modulus_ui_apply_pressed_state_layer(btn);
    lv_obj_add_event_cb(btn, cb, LV_EVENT_CLICKED, (void *)idx);
    lv_obj_t *ico = modulus_ui_icon_create(btn, icon, MOD_UI_ICON_SZ_24);
    modulus_ui_icon_recolor(ico, modulus_ui_color_icon_chrome());
    lv_obj_t *lbl = lv_label_create(btn);
    lv_label_set_text(lbl, text);
    lv_obj_set_style_text_color(lbl, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_font(lbl, MOD_UI_FONT_BODY_M, 0);
    return btn;
}

void dro_set_btn_enabled(lv_obj_t *btn, bool enabled)
{
    if (!btn) {
        return;
    }
    const bool was_disabled = lv_obj_has_state(btn, LV_STATE_DISABLED);
    if (was_disabled == !enabled) {
        return;
    }
    if (enabled) {
        lv_obj_remove_state(btn, LV_STATE_DISABLED);
        lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
    } else {
        lv_obj_add_state(btn, LV_STATE_DISABLED);
        lv_obj_clear_flag(btn, LV_OBJ_FLAG_CLICKABLE);
    }
    /* Dim the children (leaves), NOT the parent: lv_obj_set_style_opa() on a
     * container with children forces LVGL to composite it into an intermediate
     * layer. Under sw_rotate full-refresh that allocates a layer buffer from
     * the 64 KB LVGL pool EVERY frame (disabled buttons persist while the CNC
     * is disconnected), thrashing the TLSF allocator and pinning taskLVGL ->
     * IDLE0 WDT. Per-leaf opacity (bg + label + image) blends directly, no
     * layer, no per-frame allocation. */
    const lv_opa_t opa = enabled ? LV_OPA_COVER : LV_OPA_40;
    lv_obj_set_style_bg_opa(btn, opa, 0);
    const uint32_t n = lv_obj_get_child_count(btn);
    for (uint32_t i = 0; i < n; i++) {
        lv_obj_set_style_opa(lv_obj_get_child(btn, i), opa, 0);
    }
}

void dro_build_axis_card(lv_obj_t *container, dro_axis_t *ac, int axis_idx, bool units_mm,
                         bool visible, int min_card_h, int btn_w, int btn_h,
                         lv_event_cb_t axis_cb, lv_event_cb_t home_cb, lv_event_cb_t zero_cb)
{
    ac->card = lv_obj_create(container);
    lv_obj_remove_style_all(ac->card);
    DRO_NO_SCROLL(ac->card);
    lv_obj_set_width(ac->card, lv_pct(100));
    lv_obj_set_flex_grow(ac->card, 1);
    lv_obj_set_style_min_height(ac->card, min_card_h, 0);
    lv_obj_set_style_bg_color(ac->card, modulus_ui_color_surface_container_low(), 0);
    lv_obj_set_style_bg_opa(ac->card, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(ac->card, MOD_UI_SHAPE_CARD, 0);
    lv_obj_set_style_border_width(ac->card, 2, 0);
    lv_obj_set_style_border_color(ac->card, modulus_ui_color_primary(), 0);
    lv_obj_set_style_border_opa(ac->card, LV_OPA_TRANSP, 0);
    lv_obj_set_style_pad_all(ac->card, MOD_UI_SPACE_MD, 0);
    lv_obj_set_flex_flow(ac->card, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(ac->card, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_add_flag(ac->card, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(ac->card, axis_cb, LV_EVENT_CLICKED, (void *)(uintptr_t)axis_idx);
    if (!visible) {
        lv_obj_add_flag(ac->card, LV_OBJ_FLAG_HIDDEN);
    }

    lv_obj_t *axis_col = lv_obj_create(ac->card);
    lv_obj_remove_style_all(axis_col);
    DRO_NO_SCROLL(axis_col);
    lv_obj_set_size(axis_col, 60, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(axis_col, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(axis_col, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    ac->lbl_axis = lv_label_create(axis_col);
    lv_label_set_text(ac->lbl_axis, k_axis_names[axis_idx]);
    lv_obj_set_style_text_color(ac->lbl_axis, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(ac->lbl_axis, MOD_UI_FONT_DISPLAY_L, 0);
    ac->lbl_active = lv_label_create(axis_col);
    lv_label_set_text(ac->lbl_active, "");
    lv_obj_set_style_text_color(ac->lbl_active, modulus_ui_color_primary(), 0);
    lv_obj_set_style_text_font(ac->lbl_active, MOD_UI_FONT_LABEL_M, 0);
    lv_obj_set_style_text_letter_space(ac->lbl_active, 1, 0);

    lv_obj_t *pos_col = lv_obj_create(ac->card);
    lv_obj_remove_style_all(pos_col);
    DRO_NO_SCROLL(pos_col);
    lv_obj_set_size(pos_col, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_grow(pos_col, 1);
    lv_obj_set_flex_flow(pos_col, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_left(pos_col, MOD_UI_SPACE_SM, 0);
    ac->lbl_work = lv_label_create(pos_col);
    lv_label_set_text(ac->lbl_work, "+0.000");
    lv_obj_set_style_text_color(ac->lbl_work, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_font(ac->lbl_work, MOD_UI_FONT_DISPLAY_M, 0);
    ac->lbl_mach = lv_label_create(pos_col);
    lv_label_set_text(ac->lbl_mach, "M: +0.000");
    lv_obj_set_style_text_color(ac->lbl_mach, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_opa(ac->lbl_mach, LV_OPA_60, 0);
    lv_obj_set_style_text_font(ac->lbl_mach, MOD_UI_FONT_TITLE_M, 0);

    lv_obj_t *right_col = lv_obj_create(ac->card);
    lv_obj_remove_style_all(right_col);
    DRO_NO_SCROLL(right_col);
    lv_obj_set_size(right_col, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(right_col, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(right_col, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_END, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_row(right_col, MOD_UI_SPACE_XS, 0);

    lv_obj_t *top_row = lv_obj_create(right_col);
    lv_obj_remove_style_all(top_row);
    DRO_NO_SCROLL(top_row);
    lv_obj_set_size(top_row, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(top_row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(top_row, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(top_row, MOD_UI_SPACE_SM, 0);
    ac->lbl_unit = lv_label_create(top_row);
    lv_label_set_text(ac->lbl_unit, units_mm ? "MM" : "IN");
    lv_obj_set_style_text_color(ac->lbl_unit, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(ac->lbl_unit, MOD_UI_FONT_LABEL_M, 0);
    lv_obj_set_style_text_letter_space(ac->lbl_unit, 2, 0);
    ac->btn_home = dro_action_btn(top_row, MOD_UI_ICON_HOUSE_FILL, "Home", home_cb,
                                  (uintptr_t)axis_idx, btn_w, btn_h);
    ac->btn_zero = dro_action_btn(right_col, MOD_UI_ICON_ZERO, "Zero", zero_cb,
                                  (uintptr_t)axis_idx, btn_w, btn_h);
}
