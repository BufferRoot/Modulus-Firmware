#include "ui_internal.h"

#include <string.h>

void modulus_ui_label_set_text_if_changed(lv_obj_t *lbl, const char *text)
{
    if (!lbl || !text) {
        return;
    }
    const char *cur = lv_label_get_text(lbl);
    if (!cur || strcmp(cur, text) != 0) {
        lv_label_set_text(lbl, text);
    }
}

void modulus_ui_label_set_text_cached(lv_obj_t *lbl, char *cache, size_t cache_len, const char *text)
{
    if (!lbl || !cache || !text || cache_len == 0) {
        return;
    }
    if (strncmp(cache, text, cache_len) == 0) {
        return;
    }
    strncpy(cache, text, cache_len - 1);
    cache[cache_len - 1] = '\0';
    lv_label_set_text(lbl, cache);
}

lv_obj_t *modulus_ui_flex_row_create(lv_obj_t *parent, lv_coord_t h, bool space_between)
{
    lv_obj_t *row = lv_obj_create(parent);
    lv_obj_remove_style_all(row);
    lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_width(row, lv_pct(100));
    if (h > 0) {
        lv_obj_set_height(row, h);
    }
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    if (space_between) {
        lv_obj_set_flex_align(row, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER,
                              LV_FLEX_ALIGN_CENTER);
    }
    return row;
}

void modulus_ui_apply_overlay_scrim(lv_obj_t *obj)
{
    if (!obj) {
        return;
    }
    /* Opaque surface-dim scrim — avoids translucent composite under sw_rotate
     * when pause is incomplete. Callers still pause dashboard refresh. */
    lv_obj_set_style_bg_color(obj, modulus_ui_color_opaque_scrim(), 0);
    lv_obj_set_style_bg_opa(obj, MOD_UI_SCRIM_OPA, 0);
}

void modulus_ui_touch_expand(lv_obj_t *obj, lv_coord_t pad)
{
    if (!obj || pad <= 0) {
        return;
    }
    lv_obj_set_ext_click_area(obj, pad);
}

void modulus_ui_apply_focus_ring(lv_obj_t *obj)
{
    if (!obj) {
        return;
    }
    lv_obj_set_style_outline_width(obj, 0, 0);
    lv_obj_set_style_outline_width(obj, 2, LV_STATE_FOCUSED);
    lv_obj_set_style_outline_color(obj, modulus_ui_color_outline(), LV_STATE_FOCUSED);
    lv_obj_set_style_outline_opa(obj, LV_OPA_COVER, LV_STATE_FOCUSED);
    lv_obj_set_style_outline_pad(obj, 2, LV_STATE_FOCUSED);
}

void modulus_ui_touch_ensure_min(lv_obj_t *obj)
{
    if (!obj) {
        return;
    }
    lv_coord_t w = lv_obj_get_width(obj);
    lv_coord_t h = lv_obj_get_height(obj);
    if (w <= 0) {
        w = lv_obj_get_content_width(obj);
    }
    if (h <= 0) {
        h = lv_obj_get_content_height(obj);
    }
    lv_coord_t pad = 0;
    if (w > 0 && w < MOD_UI_TOUCH_MIN) {
        const lv_coord_t dw = MOD_UI_TOUCH_MIN - w;
        if (dw > pad) {
            pad = dw;
        }
    }
    if (h > 0 && h < MOD_UI_TOUCH_MIN) {
        const lv_coord_t dh = MOD_UI_TOUCH_MIN - h;
        if (dh > pad) {
            pad = dh;
        }
    }
    if (pad > 0) {
        lv_obj_set_ext_click_area(obj, (pad + 1) / 2);
    }
}

void modulus_ui_bind_menu_click(lv_obj_t *obj, lv_event_cb_t cb, void *user_data)
{
    if (!obj || !cb) {
        return;
    }
    lv_obj_add_event_cb(obj, cb, LV_EVENT_SHORT_CLICKED, user_data);
}

void modulus_ui_style_filled_button(lv_obj_t *btn)
{
    if (!btn) {
        return;
    }
    lv_obj_set_style_radius(btn, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_bg_color(btn, modulus_ui_color_primary(), 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    modulus_ui_apply_pressed_state_layer_color(btn, modulus_ui_color_on_primary());
}

void modulus_ui_style_tonal_button(lv_obj_t *btn)
{
    if (!btn) {
        return;
    }
    lv_obj_set_style_radius(btn, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_bg_color(btn, modulus_ui_color_secondary_container(), 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    modulus_ui_apply_pressed_state_layer_color(btn, modulus_ui_color_on_secondary_container());
}

lv_obj_t *modulus_ui_filled_button_create(lv_obj_t *parent, lv_coord_t w, lv_coord_t h)
{
    lv_obj_t *btn = lv_button_create(parent);
    if (w > 0) {
        lv_obj_set_width(btn, w);
    }
    if (h > 0) {
        lv_obj_set_height(btn, h);
    }
    if (h <= 0 && w <= 0) {
        lv_obj_set_height(btn, MOD_UI_TOUCH_MIN);
    } else if (h > 0 && h < MOD_UI_TOUCH_MIN) {
        lv_obj_set_height(btn, MOD_UI_TOUCH_MIN);
    }
    modulus_ui_style_filled_button(btn);
    return btn;
}

lv_obj_t *modulus_ui_tonal_button_create(lv_obj_t *parent, lv_coord_t w, lv_coord_t h)
{
    lv_obj_t *btn = lv_button_create(parent);
    if (w > 0) {
        lv_obj_set_width(btn, w);
    }
    if (h > 0) {
        lv_obj_set_height(btn, h);
    }
    if (h <= 0 && w <= 0) {
        lv_obj_set_height(btn, MOD_UI_TOUCH_MIN);
    } else if (h > 0 && h < MOD_UI_TOUCH_MIN) {
        lv_obj_set_height(btn, MOD_UI_TOUCH_MIN);
    }
    modulus_ui_style_tonal_button(btn);
    return btn;
}

lv_obj_t *modulus_ui_dialog_card_create(lv_obj_t *parent, lv_coord_t w, lv_coord_t h)
{
    lv_obj_t *card = lv_obj_create(parent);
    lv_obj_remove_style_all(card);
    if (w > 0) {
        lv_obj_set_width(card, w);
    }
    if (h > 0) {
        lv_obj_set_height(card, h);
    } else {
        lv_obj_set_height(card, LV_SIZE_CONTENT);
    }
    modulus_ui_dialog_card_apply(card);
    lv_obj_set_style_pad_all(card, MOD_UI_SPACE_LG, 0);
    lv_obj_set_flex_flow(card, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(card, MOD_UI_SPACE_SM, 0);
    lv_obj_remove_flag(card, LV_OBJ_FLAG_SCROLLABLE);
    return card;
}

void modulus_ui_dialog_card_apply(lv_obj_t *card)
{
    if (!card) {
        return;
    }
    /* MD3 basic dialog: surface_container_highest + outline, tonal not shadow. */
    lv_obj_set_style_bg_color(card, modulus_ui_color_surface_container_highest(), 0);
    lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(card, MOD_UI_SHAPE_DIALOG, 0);
    lv_obj_set_style_border_color(card, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_border_width(card, 1, 0);
    lv_obj_set_style_shadow_width(card, 0, 0);
}

lv_obj_t *modulus_ui_dialog_scrim_create(void)
{
    lv_obj_t *scrim = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(scrim);
    lv_obj_set_size(scrim, lv_pct(100), lv_pct(100));
    modulus_ui_apply_overlay_scrim(scrim);
    lv_obj_add_flag(scrim, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_remove_flag(scrim, LV_OBJ_FLAG_SCROLLABLE);
    return scrim;
}

void modulus_ui_dialog_theme_refresh(lv_obj_t *scrim)
{
    if (!scrim) {
        return;
    }
    modulus_ui_apply_overlay_scrim(scrim);
    /* First child is the dialog card; later siblings may be keyboards. */
    lv_obj_t *card = lv_obj_get_child(scrim, 0);
    if (card) {
        modulus_ui_dialog_card_apply(card);
    }
}

lv_obj_t *modulus_ui_dialog_title(lv_obj_t *card, const char *text)
{
    lv_obj_t *ttl = lv_label_create(card);
    lv_label_set_text(ttl, text ? text : "");
    lv_obj_set_style_text_color(ttl, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_font(ttl, MOD_UI_FONT_TITLE_M, 0);
    lv_obj_set_width(ttl, lv_pct(100));
    return ttl;
}

typedef struct {
    lv_event_cb_t cb;
    void *user_data;
} mod_ui_scrim_dismiss_t;

static void scrim_dismiss_ud_free_cb(lv_event_t *e)
{
    mod_ui_scrim_dismiss_t *ud = lv_event_get_user_data(e);
    if (ud) {
        lv_free(ud);
    }
}

static void scrim_dismiss_click_cb(lv_event_t *e)
{
    if (lv_event_get_code(e) != LV_EVENT_SHORT_CLICKED) {
        return;
    }
    if (lv_event_get_target(e) != lv_event_get_current_target(e)) {
        return;
    }
    mod_ui_scrim_dismiss_t *ud = lv_event_get_user_data(e);
    if (ud && ud->cb) {
        ud->cb(e);
    }
}

void modulus_ui_dialog_scrim_bind_dismiss(lv_obj_t *scrim, lv_event_cb_t cb, void *user_data)
{
    if (!scrim || !cb) {
        return;
    }
    mod_ui_scrim_dismiss_t *ud = lv_malloc(sizeof(*ud));
    if (!ud) {
        return;
    }
    ud->cb = cb;
    ud->user_data = user_data;
    lv_obj_add_event_cb(scrim, scrim_dismiss_click_cb, LV_EVENT_SHORT_CLICKED, ud);
    lv_obj_add_event_cb(scrim, scrim_dismiss_ud_free_cb, LV_EVENT_DELETE, ud);
}

lv_obj_t *modulus_ui_dialog_header(lv_obj_t *card, const char *title, lv_event_cb_t close_cb,
                                   void *user_data)
{
    lv_obj_t *row = lv_obj_create(card);
    lv_obj_remove_style_all(row);
    lv_obj_set_width(row, lv_pct(100));
    lv_obj_set_height(row, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(row, MOD_UI_SPACE_SM, 0);
    lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *ttl = lv_label_create(row);
    lv_label_set_text(ttl, title ? title : "");
    lv_obj_set_style_text_color(ttl, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_font(ttl, MOD_UI_FONT_TITLE_L, 0);
    /* Emphasized title tracking (MD3 emphasized type without new bitmaps). */
    lv_obj_set_style_text_letter_space(ttl, 1, 0);
    lv_obj_set_flex_grow(ttl, 1);

    modulus_ui_icon_button_create(row, MOD_UI_ICON_X, MOD_UI_ICON_BTN_STANDARD, close_cb,
                                  user_data);
    return row;
}

lv_obj_t *modulus_ui_icon_button_create_sz(lv_obj_t *parent, modulus_ui_icon_id_t id,
                                           modulus_ui_icon_size_t sz, int variant,
                                           lv_event_cb_t cb, void *user_data)
{
    lv_obj_t *btn = lv_button_create(parent);
    const lv_coord_t box = (lv_coord_t)sz + MOD_UI_SPACE_SM;
    const lv_coord_t hit = box < MOD_UI_TOUCH_MIN ? MOD_UI_TOUCH_MIN : box;
    lv_obj_set_size(btn, hit, hit);
    lv_obj_set_style_radius(btn, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_shadow_width(btn, 0, 0);

    lv_color_t icon_color = modulus_ui_color_icon_chrome();
    if (variant == MOD_UI_ICON_BTN_TONAL) {
        lv_obj_set_style_bg_color(btn, modulus_ui_color_secondary_container(), 0);
        lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
        icon_color = modulus_ui_color_on_secondary_container();
        modulus_ui_apply_pressed_state_layer_color(btn, icon_color);
    } else if (variant == MOD_UI_ICON_BTN_OUTLINED) {
        lv_obj_set_style_bg_opa(btn, LV_OPA_TRANSP, 0);
        lv_obj_set_style_border_width(btn, 1, 0);
        lv_obj_set_style_border_color(btn, modulus_ui_color_outline_variant(), 0);
        modulus_ui_apply_pressed_state_layer(btn);
    } else {
        lv_obj_set_style_bg_opa(btn, LV_OPA_TRANSP, 0);
        modulus_ui_apply_pressed_state_layer(btn);
    }

    lv_obj_t *ico = modulus_ui_icon_create(btn, id, sz);
    if (ico) {
        lv_obj_center(ico);
        modulus_ui_icon_recolor(ico, icon_color);
    }
    modulus_ui_apply_focus_ring(btn);
    modulus_ui_touch_ensure_min(btn);
    if (cb) {
        lv_obj_add_event_cb(btn, cb, LV_EVENT_SHORT_CLICKED, user_data);
    }
    return btn;
}

lv_obj_t *modulus_ui_icon_button_create(lv_obj_t *parent, modulus_ui_icon_id_t id, int variant,
                                        lv_event_cb_t cb, void *user_data)
{
    return modulus_ui_icon_button_create_sz(parent, id, MOD_UI_ICON_SZ_24, variant, cb, user_data);
}

static void dialog_scrim_hide_ready(lv_anim_t *a)
{
    lv_obj_t *dlg = lv_anim_get_user_data(a);
    if (dlg) {
        lv_obj_delete(dlg);
    }
}

void modulus_ui_dialog_scrim_hide_animated(lv_obj_t **scrim_slot)
{
    if (!scrim_slot || !*scrim_slot) {
        return;
    }
    lv_obj_t *dlg = *scrim_slot;
    *scrim_slot = NULL;
    lv_obj_t *card = lv_obj_get_child(dlg, 0);
    if (card && modulus_ui_motion_smooth()) {
        modulus_ui_motion_dialog_exit(card, dialog_scrim_hide_ready, dlg);
        return;
    }
    lv_obj_delete(dlg);
}

lv_obj_t *modulus_ui_linear_progress_create(lv_obj_t *parent)
{
    lv_obj_t *bar = lv_bar_create(parent);
    lv_obj_set_width(bar, lv_pct(100));
    lv_obj_set_height(bar, 6);
    lv_bar_set_range(bar, 0, 100);
    lv_bar_set_value(bar, 0, LV_ANIM_OFF);
    lv_obj_set_style_bg_color(bar, modulus_ui_color_surface_container_high(), LV_PART_MAIN);
    lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, LV_PART_MAIN);
    lv_obj_set_style_radius(bar, MOD_UI_SHAPE_FULL, LV_PART_MAIN);
    lv_obj_set_style_bg_color(bar, modulus_ui_color_primary(), LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, LV_PART_INDICATOR);
    lv_obj_set_style_radius(bar, MOD_UI_SHAPE_FULL, LV_PART_INDICATOR);
    return bar;
}

void modulus_ui_linear_progress_set(lv_obj_t *bar, int32_t pct)
{
    if (!bar) {
        return;
    }
    if (pct < 0) {
        pct = 0;
    } else if (pct > 100) {
        pct = 100;
    }
    if (lv_bar_get_value(bar) == pct) {
        return;
    }
    lv_bar_set_value(bar, pct, LV_ANIM_OFF);
}

lv_obj_t *modulus_ui_list_item_create(lv_obj_t *parent, modulus_ui_icon_id_t leading,
                                      const char *primary, const char *supporting,
                                      lv_event_cb_t cb, void *user_data)
{
    lv_obj_t *row = lv_obj_create(parent);
    lv_obj_remove_style_all(row);
    lv_obj_set_width(row, lv_pct(100));
    lv_obj_set_height(row, LV_SIZE_CONTENT);
    lv_obj_set_style_min_height(row, 56, 0);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_hor(row, MOD_UI_SPACE_MD, 0);
    lv_obj_set_style_pad_column(row, MOD_UI_SPACE_MD, 0);
    lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);
    if (cb) {
        lv_obj_add_flag(row, LV_OBJ_FLAG_CLICKABLE);
        modulus_ui_apply_pressed_state_layer(row);
        modulus_ui_apply_focus_ring(row);
        lv_obj_add_event_cb(row, cb, LV_EVENT_SHORT_CLICKED, user_data);
    }

    const bool has_icon = (int)leading >= 0 && (int)leading < (int)MOD_UI_ICON_COUNT;
    if (has_icon) {
        lv_obj_t *ico = modulus_ui_icon_create(row, leading, MOD_UI_ICON_SZ_24);
        if (ico) {
            modulus_ui_icon_recolor(ico, modulus_ui_color_on_surface_variant());
        }
    }

    lv_obj_t *col = lv_obj_create(row);
    lv_obj_remove_style_all(col);
    lv_obj_set_flex_grow(col, 1);
    lv_obj_set_height(col, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(col, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(col, 2, 0);
    lv_obj_remove_flag(col, LV_OBJ_FLAG_SCROLLABLE);

    lv_obj_t *pri = lv_label_create(col);
    lv_label_set_text(pri, primary ? primary : "");
    lv_obj_set_style_text_color(pri, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_font(pri, MOD_UI_FONT_LABEL_L, 0);
    lv_obj_set_width(pri, lv_pct(100));

    if (supporting && supporting[0]) {
        lv_obj_t *sup = lv_label_create(col);
        lv_label_set_text(sup, supporting);
        lv_obj_set_style_text_color(sup, modulus_ui_color_on_surface_variant(), 0);
        lv_obj_set_style_text_font(sup, MOD_UI_FONT_BODY_S, 0);
        lv_obj_set_width(sup, lv_pct(100));
    }
    return row;
}

typedef struct {
    lv_event_cb_t item_cb;
    void *user_data;
} mod_ui_menu_ctx_t;

static lv_obj_t *s_menu_dismiss = NULL;

void modulus_ui_menu_hide(void)
{
    if (s_menu_dismiss) {
        lv_obj_delete(s_menu_dismiss);
        s_menu_dismiss = NULL;
    }
}

static void menu_ctx_free_cb(lv_event_t *e)
{
    mod_ui_menu_ctx_t *ctx = lv_event_get_user_data(e);
    if (ctx) {
        lv_free(ctx);
    }
}

static void menu_dismiss_cb(lv_event_t *e)
{
    (void)e;
    modulus_ui_menu_hide();
}

static void menu_item_click_cb(lv_event_t *e)
{
    if (lv_event_get_code(e) != LV_EVENT_SHORT_CLICKED) {
        return;
    }
    if (!s_menu_dismiss) {
        return;
    }
    mod_ui_menu_ctx_t *ctx = lv_obj_get_user_data(s_menu_dismiss);
    if (!ctx || !ctx->item_cb) {
        modulus_ui_menu_hide();
        return;
    }
    /* Item index: lv_obj_get_user_data(lv_event_get_target(e)).
     * Menu user_data: lv_event_get_user_data(e). */
    ctx->item_cb(e);
    modulus_ui_menu_hide();
}

lv_obj_t *modulus_ui_menu_show(lv_obj_t *anchor, const char *const *labels, uint8_t count,
                               lv_event_cb_t item_cb, void *user_data)
{
    modulus_ui_menu_hide();
    if (!anchor || !labels || count == 0 || !item_cb) {
        return NULL;
    }

    mod_ui_menu_ctx_t *ctx = lv_malloc(sizeof(*ctx));
    if (!ctx) {
        return NULL;
    }
    ctx->item_cb = item_cb;
    ctx->user_data = user_data;

    s_menu_dismiss = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(s_menu_dismiss);
    lv_obj_set_size(s_menu_dismiss, lv_pct(100), lv_pct(100));
    lv_obj_set_style_bg_opa(s_menu_dismiss, LV_OPA_TRANSP, 0);
    lv_obj_add_flag(s_menu_dismiss, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_remove_flag(s_menu_dismiss, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_event_cb(s_menu_dismiss, menu_dismiss_cb, LV_EVENT_SHORT_CLICKED, NULL);
    lv_obj_add_event_cb(s_menu_dismiss, menu_ctx_free_cb, LV_EVENT_DELETE, ctx);
    lv_obj_set_user_data(s_menu_dismiss, ctx);

    lv_obj_t *panel = lv_obj_create(s_menu_dismiss);
    lv_obj_remove_style_all(panel);
    lv_obj_set_width(panel, 220);
    lv_obj_set_height(panel, LV_SIZE_CONTENT);
    lv_obj_set_style_bg_color(panel, modulus_ui_color_surface_container_highest(), 0);
    lv_obj_set_style_bg_opa(panel, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(panel, MOD_UI_SHAPE_SM, 0);
    lv_obj_set_style_border_color(panel, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_border_width(panel, 1, 0);
    lv_obj_set_style_shadow_width(panel, 0, 0);
    lv_obj_set_style_pad_ver(panel, MOD_UI_SPACE_XS, 0);
    lv_obj_set_flex_flow(panel, LV_FLEX_FLOW_COLUMN);
    lv_obj_remove_flag(panel, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_remove_flag(panel, LV_OBJ_FLAG_CLICKABLE);

    lv_area_t anchor_coords;
    lv_obj_get_coords(anchor, &anchor_coords);
    lv_coord_t panel_h = (lv_coord_t)(count * MOD_UI_TOUCH_MIN + MOD_UI_SPACE_XS * 2);
    lv_coord_t y = anchor_coords.y2 + MOD_UI_SPACE_XS;
    if (y + panel_h > (lv_coord_t)LV_VER_RES) {
        y = anchor_coords.y1 - panel_h - MOD_UI_SPACE_XS;
    }
    lv_obj_set_pos(panel, anchor_coords.x1, y);

    for (uint8_t i = 0; i < count; i++) {
        lv_obj_t *item = lv_obj_create(panel);
        lv_obj_remove_style_all(item);
        lv_obj_set_width(item, lv_pct(100));
        lv_obj_set_height(item, MOD_UI_TOUCH_MIN);
        lv_obj_add_flag(item, LV_OBJ_FLAG_CLICKABLE);
        modulus_ui_apply_pressed_state_layer(item);
        lv_obj_set_user_data(item, (void *)(intptr_t)i);
        lv_obj_add_event_cb(item, menu_item_click_cb, LV_EVENT_SHORT_CLICKED, user_data);

        lv_obj_t *lbl = lv_label_create(item);
        lv_label_set_text(lbl, labels[i] ? labels[i] : "");
        const bool destructive = labels[i] && labels[i][0] &&
                                 (strcmp(labels[i], "Remove") == 0 ||
                                  strcmp(labels[i], "Delete") == 0);
        lv_obj_set_style_text_color(lbl, destructive ? modulus_ui_color_error()
                                                     : modulus_ui_color_on_surface(), 0);
        lv_obj_set_style_text_font(lbl, MOD_UI_FONT_BODY_L, 0);
        lv_obj_align(lbl, LV_ALIGN_LEFT_MID, MOD_UI_SPACE_MD, 0);
    }

    return panel;
}

static lv_obj_t *s_tooltip = NULL;

static void tooltip_hide(void)
{
    if (s_tooltip) {
        lv_obj_delete(s_tooltip);
        s_tooltip = NULL;
    }
}

static void tooltip_scrim_cb(lv_event_t *e)
{
    (void)e;
    tooltip_hide();
}

void modulus_ui_tooltip_show(lv_obj_t *anchor, const char *text)
{
    tooltip_hide();
    if (!anchor || !text || !text[0]) {
        return;
    }

    s_tooltip = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(s_tooltip);
    lv_obj_set_size(s_tooltip, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_style_max_width(s_tooltip, 320, 0);
    lv_obj_set_style_bg_color(s_tooltip, modulus_ui_color_inverse_surface(), 0);
    lv_obj_set_style_bg_opa(s_tooltip, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(s_tooltip, MOD_UI_SHAPE_SM, 0);
    lv_obj_set_style_pad_hor(s_tooltip, MOD_UI_SPACE_MD, 0);
    lv_obj_set_style_pad_ver(s_tooltip, MOD_UI_SPACE_SM, 0);
    lv_obj_add_flag(s_tooltip, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(s_tooltip, tooltip_scrim_cb, LV_EVENT_SHORT_CLICKED, NULL);

    lv_obj_t *lbl = lv_label_create(s_tooltip);
    lv_label_set_text(lbl, text);
    lv_label_set_long_mode(lbl, LV_LABEL_LONG_WRAP);
    lv_obj_set_width(lbl, LV_SIZE_CONTENT);
    lv_obj_set_style_max_width(lbl, 280, 0);
    lv_obj_set_style_text_color(lbl, modulus_ui_color_inverse_on_surface(), 0);
    lv_obj_set_style_text_font(lbl, MOD_UI_FONT_BODY_S, 0);

    lv_obj_align_to(s_tooltip, anchor, LV_ALIGN_OUT_BOTTOM_MID, 0, 4);
    lv_obj_move_foreground(s_tooltip);
}

typedef struct {
    const char *text;
} mod_ui_tooltip_bind_t;

static void tooltip_bind_ud_free_cb(lv_event_t *e)
{
    mod_ui_tooltip_bind_t *bind = lv_event_get_user_data(e);
    if (bind) {
        lv_free(bind);
    }
}

static void tooltip_bind_longpress_cb(lv_event_t *e)
{
    const lv_event_code_t code = lv_event_get_code(e);
    mod_ui_tooltip_bind_t *bind = lv_event_get_user_data(e);
    if (!bind) {
        return;
    }
    if (code == LV_EVENT_LONG_PRESSED) {
        modulus_ui_tooltip_show(lv_event_get_target(e), bind->text);
    } else if (code == LV_EVENT_PRESS_LOST || code == LV_EVENT_RELEASED ||
               code == LV_EVENT_SHORT_CLICKED) {
        tooltip_hide();
    }
}

void modulus_ui_tooltip_bind_longpress(lv_obj_t *obj, const char *text)
{
    if (!obj || !text) {
        return;
    }
    mod_ui_tooltip_bind_t *bind = lv_malloc(sizeof(*bind));
    if (!bind) {
        return;
    }
    bind->text = text;
    lv_obj_add_event_cb(obj, tooltip_bind_longpress_cb, LV_EVENT_LONG_PRESSED, bind);
    lv_obj_add_event_cb(obj, tooltip_bind_longpress_cb, LV_EVENT_PRESS_LOST, bind);
    lv_obj_add_event_cb(obj, tooltip_bind_longpress_cb, LV_EVENT_RELEASED, bind);
    lv_obj_add_event_cb(obj, tooltip_bind_longpress_cb, LV_EVENT_SHORT_CLICKED, bind);
    lv_obj_add_event_cb(obj, tooltip_bind_ud_free_cb, LV_EVENT_DELETE, bind);
}

lv_obj_t *modulus_ui_dialog_supporting(lv_obj_t *card, const char *text)
{
    lv_obj_t *msg = lv_label_create(card);
    lv_label_set_text(msg, text ? text : "");
    lv_obj_set_width(msg, lv_pct(100));
    lv_label_set_long_mode(msg, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_color(msg, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(msg, MOD_UI_FONT_BODY_M, 0);
    return msg;
}

lv_obj_t *modulus_ui_dialog_actions(lv_obj_t *card, bool end_align)
{
    lv_obj_t *row = lv_obj_create(card);
    lv_obj_remove_style_all(row);
    lv_obj_set_size(row, lv_pct(100), LV_SIZE_CONTENT);
    lv_obj_set_style_min_height(row, MOD_UI_TOUCH_MIN, 0);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row,
                          end_align ? LV_FLEX_ALIGN_END : LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(row, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_pad_top(row, MOD_UI_SPACE_XS, 0);
    lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);
    return row;
}

lv_obj_t *modulus_ui_dialog_action_btn(lv_obj_t *row, const char *label, int kind,
                                       lv_event_cb_t cb, void *user_data)
{
    lv_obj_t *btn = lv_button_create(row);
    lv_obj_set_size(btn, LV_SIZE_CONTENT, MOD_UI_TOUCH_MIN);
    lv_obj_set_style_min_width(btn, 96, 0);
    lv_obj_set_style_pad_hor(btn, MOD_UI_SPACE_MD, 0);
    lv_obj_set_style_radius(btn, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_shadow_width(btn, 0, 0);

    lv_color_t bg;
    lv_color_t fg;
    if (kind == MOD_UI_DIALOG_BTN_DESTRUCTIVE) {
        bg = modulus_ui_color_error();
        fg = modulus_ui_color_on_error();
        lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    } else if (kind == MOD_UI_DIALOG_BTN_FILLED) {
        bg = modulus_ui_color_primary();
        fg = modulus_ui_color_on_primary();
        lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    } else if (kind == MOD_UI_DIALOG_BTN_TEXT) {
        bg = modulus_ui_color_surface();
        fg = modulus_ui_color_primary();
        lv_obj_set_style_bg_opa(btn, LV_OPA_TRANSP, 0);
    } else {
        bg = modulus_ui_color_secondary_container();
        fg = modulus_ui_color_on_secondary_container();
        lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    }
    lv_obj_set_style_bg_color(btn, bg, 0);
    modulus_ui_apply_pressed_state_layer_color(btn, fg);

    lv_obj_t *lbl = lv_label_create(btn);
    lv_label_set_text(lbl, label ? label : "");
    lv_obj_set_style_text_color(lbl, fg, 0);
    lv_obj_set_style_text_font(lbl, MOD_UI_FONT_LABEL_L, 0);
    lv_obj_center(lbl);

    if (cb) {
        lv_obj_add_event_cb(btn, cb, LV_EVENT_SHORT_CLICKED, user_data);
    }
    modulus_ui_apply_focus_ring(btn);
    return btn;
}

static void seg_group_delete_cb(lv_event_t *e)
{
    modulus_ui_segmented_t *grp = lv_event_get_user_data(e);
    if (grp) {
        lv_free(grp);
    }
}

static void seg_apply_segment_style(lv_obj_t *btn, bool selected)
{
    lv_obj_set_style_bg_color(btn, selected ? modulus_ui_color_secondary_container()
                                            : modulus_ui_color_surface_container_high(), 0);
    lv_obj_set_style_bg_opa(btn, selected ? LV_OPA_COVER : LV_OPA_TRANSP, 0);
    lv_obj_t *lbl = lv_obj_get_child(btn, 0);
    if (lbl) {
        lv_obj_set_style_text_color(lbl, selected ? modulus_ui_color_on_secondary_container()
                                                  : modulus_ui_color_on_surface_variant(), 0);
    }
    /* Expressive ButtonGroup: selected segment morphs toward fuller radius. */
    const lv_coord_t r = selected ? MOD_UI_SHAPE_LG_INC : MOD_UI_SHAPE_SM;
    if (modulus_ui_motion_expressive()) {
        modulus_ui_morph_radius(btn, r, MOD_UI_MOTION_MORPH_MS);
    } else {
        lv_obj_set_style_radius(btn, r, 0);
    }
}

static void seg_click_cb(lv_event_t *e)
{
    lv_obj_t *btn = lv_event_get_target(e);
    lv_obj_t *track = lv_obj_get_parent(btn);
    modulus_ui_segmented_t *grp = lv_obj_get_user_data(track);
    if (!grp) {
        return;
    }
    for (uint8_t i = 0; i < grp->count; i++) {
        if (grp->segments[i] == btn) {
            modulus_ui_segmented_set_selected(track, i);
            if (grp->user_cb) {
                grp->user_cb(e);
            }
            break;
        }
    }
}

lv_obj_t *modulus_ui_segmented_create(lv_obj_t *parent, const char *const *labels, uint8_t count,
                                      lv_coord_t seg_w, lv_event_cb_t cb, void *user_data)
{
    if (!parent || !labels || count == 0 || count > 8) {
        return NULL;
    }

    modulus_ui_segmented_t *grp = lv_malloc(sizeof(*grp));
    if (!grp) {
        return NULL;
    }
    memset(grp, 0, sizeof(*grp));
    grp->count = count;
    grp->user_cb = cb;
    grp->user_data = user_data;

    grp->track = lv_obj_create(parent);
    lv_obj_remove_style_all(grp->track);
    lv_obj_remove_flag(grp->track, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_size(grp->track, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(grp->track, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(grp->track, 0, 0);
    lv_obj_set_style_bg_color(grp->track, modulus_ui_color_surface_container_high(), 0);
    lv_obj_set_style_bg_opa(grp->track, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(grp->track, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_border_width(grp->track, 1, 0);
    lv_obj_set_style_border_color(grp->track, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_pad_all(grp->track, 2, 0);
    lv_obj_set_user_data(grp->track, grp);
    lv_obj_add_event_cb(grp->track, seg_group_delete_cb, LV_EVENT_DELETE, grp);

    for (uint8_t i = 0; i < count; i++) {
        lv_obj_t *btn = lv_obj_create(grp->track);
        lv_obj_remove_style_all(btn);
        lv_obj_remove_flag(btn, LV_OBJ_FLAG_SCROLLABLE);
        if (seg_w > 0) {
            lv_obj_set_width(btn, seg_w);
        }
        lv_obj_set_height(btn, MOD_UI_TOUCH_MIN);
        lv_obj_set_style_radius(btn, MOD_UI_SHAPE_SM, 0);
        lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
        modulus_ui_apply_pressed_state_layer(btn);
        modulus_ui_apply_focus_ring(btn);
        lv_obj_add_event_cb(btn, seg_click_cb, LV_EVENT_CLICKED, NULL);
        lv_obj_t *lbl = lv_label_create(btn);
        lv_label_set_text(lbl, labels[i]);
        lv_obj_set_style_text_font(lbl, MOD_UI_FONT_BODY_M, 0);
        lv_obj_center(lbl);
        grp->segments[i] = btn;
    }

    modulus_ui_segmented_set_selected(grp->track, 0);
    return grp->track;
}

void modulus_ui_segmented_set_selected(lv_obj_t *track, uint8_t idx)
{
    modulus_ui_segmented_t *grp = track ? lv_obj_get_user_data(track) : NULL;
    if (!grp || idx >= grp->count) {
        return;
    }
    grp->selected = idx;
    for (uint8_t i = 0; i < grp->count; i++) {
        seg_apply_segment_style(grp->segments[i], i == idx);
    }
}

uint8_t modulus_ui_segmented_get_selected(lv_obj_t *track)
{
    modulus_ui_segmented_t *grp = track ? lv_obj_get_user_data(track) : NULL;
    return grp ? grp->selected : 0;
}

lv_obj_t *modulus_ui_segmented_get_segment(lv_obj_t *track, uint8_t idx)
{
    modulus_ui_segmented_t *grp = track ? lv_obj_get_user_data(track) : NULL;
    if (!grp || idx >= grp->count) {
        return NULL;
    }
    return grp->segments[idx];
}

static void chip_group_delete_cb(lv_event_t *e)
{
    modulus_ui_chip_group_t *grp = lv_event_get_user_data(e);
    if (grp) {
        lv_free(grp);
    }
}

static void chip_apply_style(lv_obj_t *btn, bool selected)
{
    lv_obj_set_style_bg_color(btn, selected ? modulus_ui_color_primary_container()
                                            : modulus_ui_color_surface_container_high(), 0);
    lv_obj_t *val = lv_obj_get_child(btn, 0);
    lv_obj_t *mult = lv_obj_get_child(btn, 1);
    if (val && lv_obj_check_type(val, &lv_label_class)) {
        lv_obj_set_style_text_color(val, selected ? modulus_ui_color_on_primary_container()
                                                  : modulus_ui_color_on_surface(), 0);
    }
    if (mult && lv_obj_check_type(mult, &lv_label_class)) {
        lv_obj_set_style_text_color(mult, selected ? modulus_ui_color_on_primary_container()
                                                   : modulus_ui_color_on_surface_variant(), 0);
    }
    const lv_coord_t r = selected ? MOD_UI_SHAPE_FULL : MOD_UI_SHAPE_LG;
    if (modulus_ui_motion_expressive()) {
        modulus_ui_morph_radius(btn, r, MOD_UI_MOTION_MORPH_MS);
    } else {
        lv_obj_set_style_radius(btn, r, 0);
    }
}

static void chip_click_cb(lv_event_t *e)
{
    lv_obj_t *btn = lv_event_get_target(e);
    lv_obj_t *row = lv_obj_get_parent(btn);
    modulus_ui_chip_group_t *grp = lv_obj_get_user_data(row);
    if (!grp) {
        return;
    }
    for (uint8_t i = 0; i < grp->count; i++) {
        if (grp->segments[i] == btn) {
            modulus_ui_filter_chip_set_selected(row, i);
            if (grp->user_cb) {
                grp->user_cb(e);
            }
            break;
        }
    }
}

lv_obj_t *modulus_ui_filter_chip_group_create(lv_obj_t *parent, lv_coord_t seg_h,
                                              lv_event_cb_t cb)
{
    modulus_ui_chip_group_t *grp = lv_malloc(sizeof(*grp));
    if (!grp) {
        return NULL;
    }
    memset(grp, 0, sizeof(*grp));
    grp->user_cb = cb;

    grp->row = lv_obj_create(parent);
    lv_obj_remove_style_all(grp->row);
    lv_obj_remove_flag(grp->row, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_width(grp->row, lv_pct(100));
    if (seg_h > 0) {
        lv_obj_set_height(grp->row, seg_h);
    }
    lv_obj_set_flex_flow(grp->row, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(grp->row, MOD_UI_SPACE_SM + MOD_UI_SPACE_XS, 0);
    lv_obj_set_user_data(grp->row, grp);
    lv_obj_add_event_cb(grp->row, chip_group_delete_cb, LV_EVENT_DELETE, grp);
    return grp->row;
}

lv_obj_t *modulus_ui_filter_chip_add(lv_obj_t *group, const char *label, void *user_data)
{
    modulus_ui_chip_group_t *grp = group ? lv_obj_get_user_data(group) : NULL;
    if (!grp || grp->count >= 8 || !label) {
        return NULL;
    }
    const uint8_t idx = grp->count;
    lv_obj_t *btn = lv_obj_create(group);
    lv_obj_remove_style_all(btn);
    lv_obj_remove_flag(btn, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_flex_grow(btn, 1);
    lv_obj_set_height(btn, 72);
    lv_obj_set_flex_flow(btn, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(btn, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_row(btn, 2, 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(btn, MOD_UI_SHAPE_LG, 0);
    lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
    modulus_ui_apply_pressed_state_layer(btn);
    lv_obj_set_user_data(btn, user_data);
    lv_obj_add_event_cb(btn, chip_click_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t *lbl = lv_label_create(btn);
    lv_label_set_text(lbl, label);
    lv_obj_set_style_text_font(lbl, MOD_UI_FONT_DISPLAY_S, 0);
    grp->segments[idx] = btn;
    grp->count++;
    chip_apply_style(btn, idx == grp->selected);
    return btn;
}

lv_obj_t *modulus_ui_filter_chip_add_stacked(lv_obj_t *group, const char *primary, const char *secondary,
                                             void *user_data)
{
    modulus_ui_chip_group_t *grp = group ? lv_obj_get_user_data(group) : NULL;
    if (!grp || grp->count >= 8 || !primary) {
        return NULL;
    }
    const uint8_t idx = grp->count;
    lv_obj_t *btn = lv_obj_create(group);
    lv_obj_remove_style_all(btn);
    lv_obj_remove_flag(btn, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_flex_grow(btn, 1);
    lv_obj_set_height(btn, 72);
    lv_obj_set_flex_flow(btn, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(btn, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_row(btn, 2, 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(btn, MOD_UI_SHAPE_LG, 0);
    lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
    modulus_ui_apply_pressed_state_layer(btn);
    lv_obj_set_user_data(btn, user_data);
    lv_obj_add_event_cb(btn, chip_click_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t *val = lv_label_create(btn);
    lv_label_set_text(val, primary);
    lv_obj_set_style_text_font(val, MOD_UI_FONT_DISPLAY_S, 0);
    if (secondary && secondary[0]) {
        lv_obj_t *mult = lv_label_create(btn);
        lv_label_set_text(mult, secondary);
        lv_obj_set_style_text_font(mult, MOD_UI_FONT_LABEL_M, 0);
    }
    grp->segments[idx] = btn;
    grp->count++;
    chip_apply_style(btn, idx == grp->selected);
    return btn;
}

void modulus_ui_filter_chip_set_selected(lv_obj_t *group, uint8_t idx)
{
    modulus_ui_chip_group_t *grp = group ? lv_obj_get_user_data(group) : NULL;
    if (!grp || idx >= grp->count) {
        return;
    }
    grp->selected = idx;
    for (uint8_t i = 0; i < grp->count; i++) {
        chip_apply_style(grp->segments[i], i == idx);
    }
}

uint8_t modulus_ui_filter_chip_get_selected(lv_obj_t *group)
{
    modulus_ui_chip_group_t *grp = group ? lv_obj_get_user_data(group) : NULL;
    return grp ? grp->selected : 0;
}

static void row_apply_leaf_opa(lv_obj_t *obj, lv_opa_t opa)
{
    if (!obj) {
        return;
    }
    if (lv_obj_check_type(obj, &lv_label_class)) {
        lv_obj_set_style_text_opa(obj, opa, 0);
        return;
    }
    const uint32_t n = lv_obj_get_child_count(obj);
    for (uint32_t i = 0; i < n; i++) {
        row_apply_leaf_opa(lv_obj_get_child(obj, i), opa);
    }
}

void modulus_ui_row_set_content_enabled(lv_obj_t *row, bool enabled)
{
    if (!row) {
        return;
    }
    const lv_opa_t opa = enabled ? LV_OPA_COVER : MOD_UI_DISABLED_CONTENT_OPA;
    row_apply_leaf_opa(row, opa);
    if (enabled) {
        lv_obj_remove_state(row, LV_STATE_DISABLED);
    } else {
        lv_obj_add_state(row, LV_STATE_DISABLED);
    }
}

void modulus_ui_settings_row_set_enabled(lv_obj_t *row, lv_obj_t *ctrl, bool enabled)
{
    if (ctrl) {
        if (enabled) {
            lv_obj_remove_state(ctrl, LV_STATE_DISABLED);
        } else {
            lv_obj_add_state(ctrl, LV_STATE_DISABLED);
        }
    }
    modulus_ui_row_set_content_enabled(row, enabled);
}

void modulus_ui_obj_set_disabled_style(lv_obj_t *obj, bool enabled)
{
    if (!obj) {
        return;
    }
    if (enabled) {
        lv_obj_add_flag(obj, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_set_style_opa(obj, LV_OPA_COVER, 0);
    } else {
        lv_obj_clear_flag(obj, LV_OBJ_FLAG_CLICKABLE);
    }
    modulus_ui_row_set_content_enabled(obj, enabled);
}
