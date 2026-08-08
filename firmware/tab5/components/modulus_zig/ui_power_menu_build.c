#include "ui_power_menu_priv.h"

static void header_close_cb(lv_event_t *e)
{
    (void)e;
    modulus_pwr_hide_confirm();
    modulus_ui_hide_power_menu();
}

void modulus_pwr_build_header(lv_obj_t *card)
{
    lv_obj_t *hdr = lv_obj_create(card);
    lv_obj_remove_style_all(hdr);
    lv_obj_set_size(hdr, lv_pct(100), 80);
    lv_obj_set_style_bg_color(hdr, modulus_ui_color_surface_container_high(), 0);
    lv_obj_set_style_bg_opa(hdr, LV_OPA_COVER, 0);
    lv_obj_set_style_pad_hor(hdr, MOD_UI_SPACE_XL, 0);
    lv_obj_set_flex_flow(hdr, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(hdr, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_border_width(hdr, 1, 0);
    lv_obj_set_style_border_side(hdr, LV_BORDER_SIDE_BOTTOM, 0);
    lv_obj_set_style_border_color(hdr, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_border_opa(hdr, LV_OPA_30, 0);

    lv_obj_t *tg = lv_obj_create(hdr);
    lv_obj_remove_style_all(tg);
    lv_obj_set_size(tg, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(tg, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(tg, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(tg, MOD_UI_SPACE_MD, 0);
    lv_obj_t *gi = modulus_ui_icon_create(tg, MOD_UI_ICON_POWER, MOD_UI_ICON_SZ_24);
    modulus_ui_icon_recolor(gi, modulus_ui_color_error());
    lv_obj_t *gt = lv_label_create(tg);
    lv_label_set_text(gt, "Power menu");
    lv_obj_set_style_text_color(gt, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_font(gt, MOD_UI_FONT_TITLE_L, 0);

    lv_obj_t *xb = lv_button_create(hdr);
    lv_obj_remove_style_all(xb);
    lv_obj_set_size(xb, 48, 48);
    lv_obj_set_style_radius(xb, MOD_UI_SHAPE_FULL, 0);
    modulus_ui_apply_pressed_state_layer(xb);
    lv_obj_add_flag(xb, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_t *xl = modulus_ui_icon_create(xb, MOD_UI_ICON_X, MOD_UI_ICON_SZ_24);
    modulus_ui_icon_recolor(xl, modulus_ui_color_on_surface_variant());
    lv_obj_center(xl);
    lv_obj_add_event_cb(xb, header_close_cb, LV_EVENT_SHORT_CLICKED, NULL);
}

lv_obj_t *modulus_pwr_section_title(lv_obj_t *parent, const char *text)
{
    lv_obj_t *hdr = lv_label_create(parent);
    lv_label_set_text(hdr, text);
    lv_obj_set_width(hdr, lv_pct(100));
    lv_obj_set_style_text_color(hdr, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_font(hdr, MOD_UI_FONT_TITLE_M, 0);
    lv_obj_set_style_pad_top(hdr, MOD_UI_SPACE_MD, 0);
    lv_obj_set_style_pad_bottom(hdr, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_pad_hor(hdr, MOD_UI_SPACE_MD, 0);
    return hdr;
}

void modulus_pwr_row_set_disabled(lv_obj_t *row, bool disabled)
{
    modulus_ui_obj_set_disabled_style(row, !disabled);
}
