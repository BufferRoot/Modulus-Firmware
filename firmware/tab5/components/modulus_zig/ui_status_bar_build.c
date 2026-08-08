#include "ui_status_bar_priv.h"
#include "ui_internal.h"
#include "ui_settings_common.h"
#include "cnc_cmd_exports.h"
#include "nvs_shim.h"

static void mpg_click_cb(lv_event_t *e)
{
    (void)e;
    modulus_zig_cmd_mpg_toggle();
}

static void wcs_cycle_apply(void)
{
    modulus_zig_cycle_wcs();
    modulus_ui_resume_dashboard_refresh();
}

static void wcs_cycle_cancel(void)
{
    modulus_ui_resume_dashboard_refresh();
}

static void wcs_click_cb(lv_event_t *e)
{
    (void)e;
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    const uint8_t cur = st.wcs;
    const uint8_t next = (uint8_t)((cur + 1) % 6);
    const uint8_t lock = modulus_nvs_get_u8("wcs_lock", 0);
    if ((lock & (1U << next)) != 0 || (lock & (1U << cur)) != 0) {
        modulus_ui_pause_dashboard_refresh();
        settings_confirm_show("Change locked WCS?",
                              "This work coordinate system is locked.", "Change", false,
                              wcs_cycle_apply, wcs_cycle_cancel);
        return;
    }
    modulus_zig_cycle_wcs();
}

static void settings_click_cb(lv_event_t *e)
{
    (void)e;
    modulus_ui_show_settings();
}

static void bar_long_press_cb(lv_event_t *e)
{
    /* Long-press on any blank status-bar area opens quick settings. Only fires
     * when the press target is the bar itself — presses on child controls
     * (gear, WCS, MPG, power) never bubble here as LONG_PRESSED on the bar. */
    (void)e;
    modulus_ui_show_quick_settings();
}

static void power_click_cb(lv_event_t *e)
{
    (void)e;
    modulus_ui_show_power_menu();
}

static lv_obj_t *bar_row_group(lv_obj_t *parent, lv_flex_align_t main_align)
{
    lv_obj_t *grp = lv_obj_create(parent);
    lv_obj_remove_style_all(grp);
    bar_no_scroll(grp);
    lv_obj_set_size(grp, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(grp, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(grp, main_align, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(grp, MOD_UI_SPACE_MD, 0);
    /* Blank space between stats belongs to the group — long-press there also
     * opens quick settings (groups are clickable by default in LVGL 9). */
    lv_obj_add_event_cb(grp, bar_long_press_cb, LV_EVENT_LONG_PRESSED, NULL);
    return grp;
}

void bar_build(lv_obj_t *parent, status_bar_t *out)
{
    lv_obj_t *bar = lv_obj_create(parent);
    lv_obj_remove_style_all(bar);
    bar_no_scroll(bar);
    lv_obj_set_width(bar, lv_pct(100));
    lv_obj_set_height(bar, 80);
    out->bar = bar;
    lv_obj_set_style_bg_color(bar, modulus_ui_color_surface_container_high(), 0);
    lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, 0);
    lv_obj_set_style_border_color(bar, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_border_width(bar, 1, 0);
    lv_obj_set_style_border_side(bar, LV_BORDER_SIDE_BOTTOM, 0);
    lv_obj_set_style_pad_hor(bar, MOD_UI_SPACE_LG, 0);
    lv_obj_set_flex_flow(bar, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(bar, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_add_event_cb(bar, bar_long_press_cb, LV_EVENT_LONG_PRESSED, NULL);

    lv_obj_t *left = bar_row_group(bar, LV_FLEX_ALIGN_START);

    out->conn_dot = lv_obj_create(left);
    lv_obj_remove_style_all(out->conn_dot);
    bar_no_scroll(out->conn_dot);
    lv_obj_set_size(out->conn_dot, 10, 10);
    lv_obj_set_style_radius(out->conn_dot, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(out->conn_dot, modulus_ui_color_neutral(), 0);
    lv_obj_set_style_bg_opa(out->conn_dot, LV_OPA_COVER, 0);

    out->state_badge = bar_make_pill(left, "Offline", modulus_ui_color_tertiary_container(),
                                     modulus_ui_color_on_tertiary_container());
    out->state_lbl = lv_obj_get_child(out->state_badge, 0);
    out->alarm_badge = lv_obj_create(out->state_badge);
    lv_obj_remove_style_all(out->alarm_badge);
    bar_no_scroll(out->alarm_badge);
    lv_obj_set_size(out->alarm_badge, 8, 8);
    lv_obj_set_style_radius(out->alarm_badge, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(out->alarm_badge, modulus_ui_color_error(), 0);
    lv_obj_set_style_bg_opa(out->alarm_badge, LV_OPA_COVER, 0);
    lv_obj_align(out->alarm_badge, LV_ALIGN_TOP_RIGHT, -2, 2);
    lv_obj_add_flag(out->alarm_badge, LV_OBJ_FLAG_HIDDEN);

    out->mpg_btn = lv_obj_create(left);
    lv_obj_remove_style_all(out->mpg_btn);
    bar_no_scroll(out->mpg_btn);
    lv_obj_set_size(out->mpg_btn, LV_SIZE_CONTENT, MOD_UI_TOUCH_MIN);
    lv_obj_set_style_bg_color(out->mpg_btn, modulus_ui_color_surface_container_highest(), 0);
    lv_obj_set_style_bg_opa(out->mpg_btn, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(out->mpg_btn, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_pad_hor(out->mpg_btn, MOD_UI_SPACE_SM + MOD_UI_SPACE_XS, 0);
    lv_obj_set_style_pad_ver(out->mpg_btn, MOD_UI_SPACE_XS, 0);
    lv_obj_set_flex_flow(out->mpg_btn, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(out->mpg_btn, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(out->mpg_btn, MOD_UI_SPACE_XS + MOD_UI_SPACE_XS / 2, 0);
    out->mpg_icon = modulus_ui_icon_create(out->mpg_btn, MOD_UI_ICON_MPG, MOD_UI_ICON_SZ_24);
    modulus_ui_icon_recolor(out->mpg_icon, modulus_ui_color_icon_chrome());
    out->mpg_lbl = lv_label_create(out->mpg_btn);
    lv_label_set_text(out->mpg_lbl, "MPG");
    lv_obj_set_style_text_color(out->mpg_lbl, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(out->mpg_lbl, MOD_UI_FONT_BODY_L, 0);
    lv_obj_add_flag(out->mpg_btn, LV_OBJ_FLAG_CLICKABLE);
    modulus_ui_apply_pressed_state_layer(out->mpg_btn);
    modulus_ui_bind_press_morph(out->mpg_btn, MOD_UI_SHAPE_FULL, MOD_UI_SHAPE_MD);
    lv_obj_add_event_cb(out->mpg_btn, mpg_click_cb, LV_EVENT_CLICKED, NULL);
    modulus_ui_touch_ensure_min(out->mpg_btn);
    modulus_ui_tooltip_bind_longpress(out->mpg_btn, "Toggle MPG");

    lv_obj_t *wcs_col = bar_stat_col(left, "WCS", "G54", NULL, NULL, &out->wcs_val, NULL, true, false, 0);
    lv_obj_set_style_text_color(out->wcs_val, modulus_ui_color_primary(), 0);
    lv_obj_add_event_cb(wcs_col, wcs_click_cb, LV_EVENT_CLICKED, NULL);

    bar_divider(left);

    bar_stat_col(left, "Tool", "T00", NULL, &out->tool_hdr, &out->tool_val, NULL, false, false, 0);

    lv_obj_t *right = bar_row_group(bar, LV_FLEX_ALIGN_END);

    bar_stat_col(right, "Feed", "0", "mm/min", &out->feed_hdr, &out->feed_val, &out->feed_unit, false,
                 true, 120);
    bar_stat_col(right, "Spindle", "0", "RPM", &out->spin_hdr, &out->spin_val, &out->spin_unit, false,
                 true, 88);

    bar_divider(right);

    out->wireless_row = lv_obj_create(right);
    lv_obj_remove_style_all(out->wireless_row);
    bar_no_scroll(out->wireless_row);
    lv_obj_set_size(out->wireless_row, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(out->wireless_row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(out->wireless_row, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(out->wireless_row, MOD_UI_SPACE_XS, 0);
    lv_obj_t *wifi_wrap = lv_obj_create(out->wireless_row);
    lv_obj_remove_style_all(wifi_wrap);
    bar_no_scroll(wifi_wrap);
    lv_obj_set_size(wifi_wrap, 28, 28);
    out->wifi_icon = modulus_ui_icon_create(wifi_wrap, MOD_UI_ICON_WIFI, MOD_UI_ICON_SZ_24);
    lv_obj_center(out->wifi_icon);
    modulus_ui_icon_recolor(out->wifi_icon, modulus_ui_color_on_surface_variant());
    out->wifi_badge = lv_obj_create(wifi_wrap);
    lv_obj_remove_style_all(out->wifi_badge);
    bar_no_scroll(out->wifi_badge);
    lv_obj_set_size(out->wifi_badge, 8, 8);
    lv_obj_set_style_radius(out->wifi_badge, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(out->wifi_badge, modulus_ui_color_primary(), 0);
    lv_obj_set_style_bg_opa(out->wifi_badge, LV_OPA_COVER, 0);
    lv_obj_align(out->wifi_badge, LV_ALIGN_TOP_RIGHT, 0, 0);
    lv_obj_add_flag(out->wifi_badge, LV_OBJ_FLAG_HIDDEN);
    modulus_ui_touch_ensure_min(wifi_wrap);
    out->ble_icon = modulus_ui_icon_create(out->wireless_row, MOD_UI_ICON_BLUETOOTH,
                                           MOD_UI_ICON_SZ_24);
    modulus_ui_icon_recolor(out->ble_icon, modulus_ui_color_icon_chrome());
    lv_obj_add_flag(out->ble_icon, LV_OBJ_FLAG_HIDDEN);
    out->espnow_icon = modulus_ui_icon_create(out->wireless_row, MOD_UI_ICON_BROADCAST,
                                              MOD_UI_ICON_SZ_24);
    modulus_ui_icon_recolor(out->espnow_icon, modulus_ui_color_icon_chrome());
    lv_obj_add_flag(out->espnow_icon, LV_OBJ_FLAG_HIDDEN);

    bar_divider(right);

    out->clock_lbl = lv_label_create(right);
    bar_no_scroll(out->clock_lbl);
    lv_label_set_text(out->clock_lbl, "--:--");
    lv_obj_set_style_text_color(out->clock_lbl, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_font(out->clock_lbl, MOD_UI_FONT_TITLE_L, 0);
    lv_obj_set_style_min_width(out->clock_lbl, 80, 0);
    lv_obj_set_style_text_align(out->clock_lbl, LV_TEXT_ALIGN_CENTER, 0);

    bar_divider(right);

    out->batt_row = lv_obj_create(right);
    lv_obj_remove_style_all(out->batt_row);
    bar_no_scroll(out->batt_row);
    lv_obj_set_size(out->batt_row, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(out->batt_row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(out->batt_row, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(out->batt_row, MOD_UI_SPACE_XS + MOD_UI_SPACE_XS / 2, 0);
    out->batt_icon = modulus_ui_icon_create(out->batt_row, MOD_UI_ICON_BATTERY_EMPTY, MOD_UI_ICON_SZ_32);
    modulus_ui_icon_recolor(out->batt_icon, modulus_ui_color_icon_chrome());
    out->batt_pct = lv_label_create(out->batt_row);
    bar_no_scroll(out->batt_pct);
    lv_label_set_text(out->batt_pct, "--%");
    lv_obj_set_style_text_color(out->batt_pct, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(out->batt_pct, MOD_UI_FONT_TITLE_M, 0);
    lv_obj_set_style_min_width(out->batt_pct, 44, 0);

    bar_divider(right);

    lv_obj_t *settings_btn = lv_obj_create(right);
    lv_obj_remove_style_all(settings_btn);
    bar_no_scroll(settings_btn);
    lv_obj_set_size(settings_btn, 48, 48);
    lv_obj_set_style_bg_color(settings_btn, modulus_ui_color_surface_container_high(), 0);
    lv_obj_set_style_bg_opa(settings_btn, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(settings_btn, MOD_UI_SHAPE_FULL, 0);
    lv_obj_add_flag(settings_btn, LV_OBJ_FLAG_CLICKABLE);
    modulus_ui_apply_pressed_state_layer(settings_btn);
    modulus_ui_bind_press_morph(settings_btn, MOD_UI_SHAPE_FULL, MOD_UI_SHAPE_MD);
    /* SHORT_CLICKED (not CLICKED): a released long-press must NOT also open the
     * settings shell — quick settings now lives on blank-bar long-press. */
    lv_obj_add_event_cb(settings_btn, settings_click_cb, LV_EVENT_SHORT_CLICKED, NULL);
    out->settings_icon = modulus_ui_icon_create(settings_btn, MOD_UI_ICON_GEAR_SIX, MOD_UI_ICON_SZ_40);
    lv_obj_center(out->settings_icon);
    bar_no_scroll(out->settings_icon);
    modulus_ui_icon_recolor(out->settings_icon, modulus_ui_color_icon_chrome());
    modulus_ui_touch_ensure_min(settings_btn);
    modulus_ui_apply_focus_ring(settings_btn);
    modulus_ui_tooltip_bind_longpress(settings_btn, "Settings");

    lv_obj_t *power_btn = lv_obj_create(right);
    lv_obj_remove_style_all(power_btn);
    bar_no_scroll(power_btn);
    lv_obj_set_size(power_btn, 48, 48);
    lv_obj_set_style_bg_opa(power_btn, LV_OPA_TRANSP, 0);
    lv_obj_add_flag(power_btn, LV_OBJ_FLAG_CLICKABLE);
    modulus_ui_apply_pressed_state_layer(power_btn);
    modulus_ui_bind_press_morph(power_btn, MOD_UI_SHAPE_FULL, MOD_UI_SHAPE_MD);
    lv_obj_add_event_cb(power_btn, power_click_cb, LV_EVENT_CLICKED, NULL);
    out->power_icon = modulus_ui_icon_create(power_btn, MOD_UI_ICON_POWER, MOD_UI_ICON_SZ_40);
    lv_obj_center(out->power_icon);
    bar_no_scroll(out->power_icon);
    modulus_ui_icon_recolor(out->power_icon, MOD_UI_COLOR_SEMANTIC_POWER);
    modulus_ui_touch_ensure_min(power_btn);
    modulus_ui_apply_focus_ring(power_btn);
    modulus_ui_tooltip_bind_longpress(power_btn, "Power menu");
}
