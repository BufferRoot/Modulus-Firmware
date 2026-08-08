#include "ui_power_menu_priv.h"
#include "ui_internal.h"
#include "ui_settings_priv.h"

#include <string.h>

/* Buttons carry [0]=label, [1]=hint. */
static lv_obj_t *btn_hint_label(lv_obj_t *btn)
{
    return lv_obj_get_child(btn, 1);
}

void modulus_pwr_update_device_rows(lv_obj_t *row_restart, lv_obj_t *row_shutdown,
                                    bool busy)
{
    const char *hint = "Stop program first";
    const char *restart_hint = busy ? hint : "Reboot now";
    const char *shutdown_hint = busy ? hint : "Power off";
    lv_obj_t *hr = btn_hint_label(row_restart);
    lv_obj_t *hs = btn_hint_label(row_shutdown);
    if (hr) {
        modulus_ui_label_set_text_if_changed(hr, restart_hint);
    }
    if (hs) {
        modulus_ui_label_set_text_if_changed(hs, shutdown_hint);
    }
    modulus_pwr_row_set_disabled(row_restart, busy);
    modulus_pwr_row_set_disabled(row_shutdown, busy);
}

/* MD3 tonal button: surface-container (normal) / solid error (destructive).
 * Full-contrast fill so Shutdown stays readable in light and dark. */
lv_obj_t *modulus_pwr_action_button(lv_obj_t *parent, const char *label,
                                    const char *hint, bool destructive,
                                    lv_event_cb_t cb)
{
    lv_obj_t *btn = lv_button_create(parent);
    lv_obj_set_size(btn, lv_pct(48), 72);
    lv_obj_set_style_radius(btn, MOD_UI_SHAPE_LG_INC, 0);
    lv_obj_set_style_shadow_width(btn, 0, 0);
    const lv_color_t bg = destructive ? modulus_ui_color_error()
                                      : modulus_ui_color_surface_container_high();
    const lv_color_t fg = destructive ? modulus_ui_color_on_error()
                                      : modulus_ui_color_on_surface();
    lv_obj_set_style_bg_color(btn, bg, 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    modulus_ui_apply_pressed_state_layer(btn);
    modulus_ui_bind_press_morph(btn, MOD_UI_SHAPE_LG_INC, MOD_UI_SHAPE_MD);
    lv_obj_set_flex_flow(btn, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(btn, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_row(btn, 2, 0);

    lv_obj_t *lbl = lv_label_create(btn);
    lv_label_set_text(lbl, label);
    lv_obj_set_style_text_color(lbl, fg, 0);
    lv_obj_set_style_text_font(lbl, MOD_UI_FONT_BODY_L, 0);

    lv_obj_t *hl = lv_label_create(btn);
    lv_label_set_text(hl, hint ? hint : "");
    lv_obj_set_style_text_color(hl, fg, 0);
    lv_obj_set_style_text_opa(hl, destructive ? LV_OPA_80 : LV_OPA_70, 0);
    lv_obj_set_style_text_font(hl, MOD_UI_FONT_LABEL_M, 0);

    if (cb) {
        lv_obj_add_event_cb(btn, cb, LV_EVENT_SHORT_CLICKED, NULL);
    }
    return btn;
}

static lv_obj_t *pwr_button_grid(lv_obj_t *body)
{
    lv_obj_t *grid = lv_obj_create(body);
    lv_obj_remove_style_all(grid);
    lv_obj_set_size(grid, lv_pct(100), LV_SIZE_CONTENT);
    lv_obj_remove_flag(grid, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_flex_flow(grid, LV_FLEX_FLOW_ROW_WRAP);
    lv_obj_set_flex_align(grid, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_START);
    lv_obj_set_style_pad_row(grid, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_pad_bottom(grid, MOD_UI_SPACE_SM, 0);
    return grid;
}

void modulus_pwr_create_menu(modulus_pwr_menu_t *out, lv_event_cb_t hide_overlay_cb,
                             lv_event_cb_t card_click_cb, lv_event_cb_t reset_cb,
                             lv_event_cb_t unlock_cb,
                             lv_event_cb_t restart_cb, lv_event_cb_t shutdown_cb)
{
    out->overlay = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(out->overlay);
    lv_obj_set_size(out->overlay, lv_pct(100), lv_pct(100));
    /* Scrim @ 60% — dashboard refresh paused while menu is open. */
    modulus_ui_apply_overlay_scrim(out->overlay);
    lv_obj_add_flag(out->overlay, LV_OBJ_FLAG_CLICKABLE | LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_event_cb(out->overlay, hide_overlay_cb, LV_EVENT_CLICKED, NULL);

    lv_obj_t *card = lv_obj_create(out->overlay);
    out->card = card;
    lv_obj_remove_style_all(card);
    lv_obj_set_width(card, lv_pct(52));
    lv_obj_set_height(card, LV_SIZE_CONTENT);
    lv_obj_center(card);
    lv_obj_set_style_max_width(card, 640, 0);
    lv_obj_set_style_bg_color(card, modulus_ui_color_surface_container_low(), 0);
    lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(card, MOD_UI_SHAPE_DIALOG, 0);
    lv_obj_set_style_clip_corner(card, true, 0);
    lv_obj_set_style_border_color(card, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_border_width(card, 1, 0);
    lv_obj_set_style_pad_all(card, 0, 0);
    lv_obj_set_flex_flow(card, LV_FLEX_FLOW_COLUMN);
    lv_obj_add_flag(card, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(card, card_click_cb, LV_EVENT_CLICKED, NULL);

    modulus_pwr_build_header(card);

    lv_obj_t *body = lv_obj_create(card);
    lv_obj_remove_style_all(body);
    lv_obj_set_width(body, lv_pct(100));
    lv_obj_set_height(body, LV_SIZE_CONTENT);
    lv_obj_set_style_max_height(body, 520, 0);
    lv_obj_set_flex_flow(body, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_all(body, MOD_UI_SPACE_LG, 0);
    lv_obj_set_style_pad_row(body, 0, 0);
    settings_tune_scroll_container(body);
    /* The 48 px list-reachability padding is for full-height tabs; in a
     * content-sized dialog it reads as a dead strip. */
    lv_obj_set_style_pad_bottom(body, MOD_UI_SPACE_MD, 0);

    modulus_pwr_section_title(body, "Machine control");
    lv_obj_t *mc = pwr_button_grid(body);
    modulus_pwr_action_button(mc, "Reset CNC", "Soft reset (Ctrl-X)", false, reset_cb);
    modulus_pwr_action_button(mc, "Clear alarm", "Unlock ($X)", false, unlock_cb);
    /* Emergency Stop removed: the pendant hardware has a physical E-stop;
     * a soft duplicate here invited habit-forming reliance on the wrong one. */

    modulus_pwr_section_title(body, "Device power");
    lv_obj_t *dp = pwr_button_grid(body);
    out->row_restart =
        modulus_pwr_action_button(dp, "Restart device", "Reboot now", false, restart_cb);
    out->row_shutdown =
        modulus_pwr_action_button(dp, "Shut down device", "Power off", true, shutdown_cb);
}