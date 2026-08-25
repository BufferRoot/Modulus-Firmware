#include "ui_settings_common.h"
#include "ui_settings_modal_kb.h"
#include "ui_internal.h"
#include "display_shim.h"
#include "audio_shim.h"
#include "nvs_shim.h"
#include "wireless_shim.h"
#include "wireless_shim_802154.h"
#include "wireless_rpc.h"
#include "zb_link_proto.h"
#include "cnc_cmd_exports.h"
#include "zb_automation.h"
#include "shop_recipe.h"
#include "ui_cnc_profiles.h"
#include "ui_shim.h"

#include <stdio.h>
#include <string.h>

/* Quick Settings: MD3 bottom sheet.
 *  System   - radios, brightness/volume, CNC/shift status, macros
 *  Devices  - Machine state (scenes + profiles) + Zigbee device tiles
 *  Terminal - MDI + scrollback (sheet lifts over keyboard)
 *  Probe    - pin indicator, plate settings, Z/edge cycles
 *  Material - Aluminum/Wood/Acrylic job recipes */

#define QS_NO_SCROLL(o) lv_obj_remove_flag((o), LV_OBJ_FLAG_SCROLLABLE)

static void qs_disable_scroll(lv_obj_t *obj)
{
    QS_NO_SCROLL(obj);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLL_ELASTIC);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLL_MOMENTUM);
    lv_obj_set_scrollbar_mode(obj, LV_SCROLLBAR_MODE_OFF);
}

static lv_obj_t *s_sheet = NULL;
static lv_obj_t *s_panel = NULL; /* bottom sheet chrome (lifted when kb open) */
static lv_obj_t *s_body = NULL;   /* tab content container */
static lv_obj_t *s_detail = NULL; /* long-press device overlay */
static lv_timer_t *s_qs_refresh = NULL;
static lv_timer_t *s_qs_body_rebuild_tmr = NULL;
static uint32_t s_seen_gen = 0;
static int s_detail_idx = -1;

static void qs_build_body(void);

static void qs_section_title(lv_obj_t *parent, const char *txt)
{
    lv_obj_t *t = lv_label_create(parent);
    lv_label_set_text(t, txt);
    /* MD3 list section header: label-large / on_surface_variant. */
    lv_obj_set_style_text_color(t, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(t, MOD_UI_FONT_LABEL_L, 0);
    lv_obj_set_width(t, lv_pct(100));
    lv_obj_set_style_pad_top(t, MOD_UI_SPACE_XS, 0);
}

static bool s_qs_drag;
static lv_coord_t s_qs_drag_start_ty;
static lv_coord_t s_qs_drag_start_py;

static void qs_handle_drag_cb(lv_event_t *e)
{
    if (!s_panel) {
        return;
    }
    lv_indev_t *indev = lv_event_get_indev(e);
    if (!indev) {
        indev = lv_indev_active();
    }
    if (!indev) {
        return;
    }
    lv_point_t p;
    lv_indev_get_point(indev, &p);
    const lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_PRESSED) {
        s_qs_drag = true;
        s_qs_drag_start_ty = lv_obj_get_style_translate_y(s_panel, 0);
        s_qs_drag_start_py = p.y;
        lv_anim_delete(s_panel, NULL);
        return;
    }
    if (code == LV_EVENT_PRESSING && s_qs_drag) {
        lv_coord_t dy = p.y - s_qs_drag_start_py;
        if (dy < 0) {
            dy = 0; /* dismiss only downward */
        }
        lv_obj_set_style_translate_y(s_panel, s_qs_drag_start_ty + dy, 0);
        return;
    }
    if ((code == LV_EVENT_RELEASED || code == LV_EVENT_PRESS_LOST) && s_qs_drag) {
        s_qs_drag = false;
        const lv_coord_t ty = lv_obj_get_style_translate_y(s_panel, 0);
        if (ty > 96) {
            modulus_ui_hide_quick_settings();
        } else {
            modulus_ui_anim_translate_y(s_panel, ty, 0, modulus_ui_motion_spatial_ms(true), true,
                                        NULL, NULL);
        }
    }
}

static void qs_drag_handle(lv_obj_t *parent)
{
    /* MD3 drag handle — ≥48dp hit; drag down dismisses sheet. */
    lv_obj_t *wrap = lv_obj_create(parent);
    lv_obj_remove_style_all(wrap);
    lv_obj_set_size(wrap, lv_pct(100), MOD_UI_TOUCH_MIN);
    qs_disable_scroll(wrap);
    lv_obj_add_flag(wrap, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_flex_flow(wrap, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(wrap, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_add_event_cb(wrap, qs_handle_drag_cb, LV_EVENT_PRESSED, NULL);
    lv_obj_add_event_cb(wrap, qs_handle_drag_cb, LV_EVENT_PRESSING, NULL);
    lv_obj_add_event_cb(wrap, qs_handle_drag_cb, LV_EVENT_RELEASED, NULL);
    lv_obj_add_event_cb(wrap, qs_handle_drag_cb, LV_EVENT_PRESS_LOST, NULL);
    lv_obj_t *bar = lv_obj_create(wrap);
    lv_obj_remove_style_all(bar);
    lv_obj_set_size(bar, 32, 4);
    lv_obj_set_style_bg_color(bar, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(bar, MOD_UI_SHAPE_FULL, 0);
    lv_obj_remove_flag(bar, LV_OBJ_FLAG_CLICKABLE);
}

static void qs_status_card(lv_obj_t *parent, const char *line1, const char *line2, bool warn)
{
    lv_obj_t *card = lv_obj_create(parent);
    lv_obj_remove_style_all(card);
    lv_obj_set_size(card, lv_pct(100), LV_SIZE_CONTENT);
    qs_disable_scroll(card);
    lv_obj_set_style_bg_color(card, warn ? modulus_ui_color_error_container()
                                         : modulus_ui_color_surface_container(), 0);
    lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(card, MOD_UI_SHAPE_MD, 0);
    lv_obj_set_style_pad_hor(card, MOD_UI_SPACE_MD, 0);
    lv_obj_set_style_pad_ver(card, MOD_UI_SPACE_SM, 0);
    lv_obj_set_flex_flow(card, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(card, MOD_UI_SPACE_XS, 0);
    lv_obj_t *a = lv_label_create(card);
    lv_label_set_text(a, line1);
    lv_obj_set_style_text_color(a, warn ? modulus_ui_color_on_error_container()
                                        : modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_font(a, MOD_UI_FONT_BODY_M, 0);
    if (line2 && line2[0]) {
        lv_obj_t *b = lv_label_create(card);
        lv_label_set_text(b, line2);
        lv_obj_set_style_text_color(b, warn ? modulus_ui_color_on_error_container()
                                            : modulus_ui_color_on_surface_variant(), 0);
        lv_obj_set_style_text_font(b, MOD_UI_FONT_LABEL_M, 0);
    }
}

static void qs_term_set_lift(lv_obj_t *kb, bool up)
{
    if (!s_panel) {
        return;
    }
    if (up && kb) {
        const int32_t kh = lv_obj_get_height(kb);
        lv_obj_align(s_panel, LV_ALIGN_BOTTOM_MID, 0, kh > 0 ? -kh : -220);
    } else {
        lv_obj_align(s_panel, LV_ALIGN_BOTTOM_MID, 0, 0);
    }
}

/* Never lv_obj_clean+rebuild synchronously inside click/tab handlers — nested
 * on the input stack plus sw_rotate draw frames overflowed 16 KiB taskLVGL. */
static void qs_body_rebuild_timer_cb(lv_timer_t *t)
{
    (void)t;
    s_qs_body_rebuild_tmr = NULL;
    qs_build_body();
}

static void qs_body_rebuild_deferred(void)
{
    if (!s_body) {
        return;
    }
    if (s_qs_body_rebuild_tmr) {
        return;
    }
    s_qs_body_rebuild_tmr = lv_timer_create(qs_body_rebuild_timer_cb, 1, NULL);
    lv_timer_set_repeat_count(s_qs_body_rebuild_tmr, 1);
}

static void qs_body_rebuild_cancel(void)
{
    if (s_qs_body_rebuild_tmr) {
        lv_timer_delete(s_qs_body_rebuild_tmr);
        s_qs_body_rebuild_tmr = NULL;
    }
}

/* -- System tab: radio toggles ---------------------------------------- */

typedef struct {
    const char *label;
    modulus_ui_icon_id_t icon;
    const char *nvs_key;
    bool (*enable)(void);
    void (*disable)(void);
} qs_radio_t;

static bool qs_radio_on(const qs_radio_t *r)
{
    return modulus_nvs_get_u8(r->nvs_key, 0) != 0;
}

static const qs_radio_t k_radios[4] = {
    {"Wi-Fi", MOD_UI_ICON_WIFI, "wifi", modulus_wireless_wifi_enable, modulus_wireless_wifi_disable},
    {"BLE", MOD_UI_ICON_BLUETOOTH, "bt", modulus_wireless_ble_enable, modulus_wireless_ble_disable},
    {"ESP-NOW", MOD_UI_ICON_BROADCAST, "espnow", modulus_wireless_espnow_enable,
     modulus_wireless_espnow_disable},
    {"Zigbee", MOD_UI_ICON_LIGHTNING, "zigbee", modulus_wireless_zigbee_enable,
     modulus_wireless_zigbee_disable},
};

static void qs_radio_cb(lv_event_t *e)
{
    const qs_radio_t *r = &k_radios[(uintptr_t)lv_event_get_user_data(e) & 3];
    if (qs_radio_on(r)) {
        r->disable();
    } else {
        (void)r->enable();
    }
    qs_body_rebuild_deferred(); /* re-tint from actual state */
}

static void qs_radio_tile(lv_obj_t *grid, uint8_t idx)
{
    const qs_radio_t *r = &k_radios[idx];
    const bool on = qs_radio_on(r);
    lv_obj_t *btn = lv_button_create(grid);
    lv_obj_set_size(btn, lv_pct(23), 72);
    lv_obj_set_style_radius(btn, MOD_UI_SHAPE_LG, 0);
    lv_obj_set_style_bg_color(btn, on ? modulus_ui_color_primary_container()
                                      : modulus_ui_color_surface_container_high(), 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    lv_obj_set_style_shadow_width(btn, 0, 0);
    lv_obj_set_style_border_width(btn, on ? 0 : 1, 0);
    lv_obj_set_style_border_color(btn, modulus_ui_color_outline_variant(), 0);
    qs_disable_scroll(btn);
    lv_obj_set_flex_flow(btn, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(btn, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_row(btn, 2, 0);
    modulus_ui_apply_pressed_state_layer_color(
        btn, on ? modulus_ui_color_on_primary_container() : modulus_ui_color_on_surface());
    const lv_color_t fg = on ? modulus_ui_color_on_primary_container()
                             : modulus_ui_color_on_surface_variant();
    lv_obj_t *ic = modulus_ui_icon_create(btn, r->icon, MOD_UI_ICON_SZ_24);
    if (ic) {
        modulus_ui_icon_recolor(ic, fg);
    }
    lv_obj_t *lb = lv_label_create(btn);
    lv_label_set_text(lb, r->label);
    lv_obj_set_style_text_color(lb, fg, 0);
    lv_obj_set_style_text_font(lb, MOD_UI_FONT_LABEL_M, 0);
    lv_obj_add_event_cb(btn, qs_radio_cb, LV_EVENT_SHORT_CLICKED, (void *)(uintptr_t)idx);
}

/* -- Shared slider row (brightness / volume / detail level) ----------- */

static void qs_slider_live_cb(lv_event_t *e)
{
    lv_obj_t *sl = lv_event_get_target(e);
    const int32_t v = lv_slider_get_value(sl);
    const char *kind = lv_event_get_user_data(e);
    if (kind[0] == 'b') {
        modulus_display_set_brightness((uint8_t)v); /* persist on release only */
    } else if (kind[0] == 'v') {
        modulus_audio_set_volume((uint8_t)v);
    }
    lv_obj_t *vl = lv_obj_get_user_data(sl);
    if (vl) {
        char buf[8];
        snprintf(buf, sizeof(buf), "%ld%%", (long)v);
        modulus_ui_label_set_text_if_changed(vl, buf);
    }
}

static void qs_bright_rel_cb(lv_event_t *e)
{
    modulus_nvs_set_u8("bright", (uint8_t)lv_slider_get_value(lv_event_get_target(e)));
}

static lv_obj_t *qs_slider_row(lv_obj_t *parent, const char *name, int32_t min_v, int32_t max_v,
                               int32_t val, const char *kind)
{
    lv_obj_t *row = lv_obj_create(parent);
    lv_obj_remove_style_all(row);
    lv_obj_set_size(row, lv_pct(100), MOD_UI_TOUCH_MIN);
    qs_disable_scroll(row);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(row, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_bg_color(row, modulus_ui_color_surface_container(), 0);
    lv_obj_set_style_bg_opa(row, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(row, MOD_UI_SHAPE_MD, 0);
    lv_obj_set_style_pad_hor(row, MOD_UI_SPACE_SM, 0);
    lv_obj_t *lb = lv_label_create(row);
    lv_label_set_text(lb, name);
    lv_obj_set_width(lb, 104);
    lv_obj_set_style_text_color(lb, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_font(lb, MOD_UI_FONT_BODY_M, 0);
    lv_obj_t *sl = lv_slider_create(row);
    lv_slider_set_range(sl, min_v, max_v);
    lv_slider_set_value(sl, val, LV_ANIM_OFF);
    lv_obj_set_flex_grow(sl, 1);
    lv_obj_set_height(sl, 28);
    qs_disable_scroll(sl);
    modulus_ui_apply_slider_theme(sl);
    lv_obj_t *vl = lv_label_create(row);
    char buf[8];
    snprintf(buf, sizeof(buf), "%ld%%", (long)val);
    lv_label_set_text(vl, buf);
    lv_obj_set_width(vl, 52);
    lv_obj_set_style_text_align(vl, LV_TEXT_ALIGN_RIGHT, 0);
    lv_obj_set_style_text_color(vl, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(vl, MOD_UI_FONT_LABEL_L, 0);
    lv_obj_set_user_data(sl, vl);
    lv_obj_add_event_cb(sl, qs_slider_live_cb, LV_EVENT_VALUE_CHANGED, (void *)kind);
    return sl;
}

/* -- User quick-macro buttons ("cnc_mac<N>": "Label|on|off") ----------- */

static void qs_macro_cb(lv_event_t *e)
{
    const uint8_t slot = (uint8_t)(uintptr_t)lv_event_get_user_data(e);
    char name[16], on[64], off[64];
    if (!settings_macro_slot_load(slot, name, sizeof(name), on, sizeof(on), off, sizeof(off),
                                  NULL)) {
        return;
    }
    lv_obj_t *btn = lv_event_get_target(e);
    const char *cmd = on;
    if (off[0] != '\0' && !lv_obj_has_state(btn, LV_STATE_CHECKED)) {
        cmd = off; /* checkable button just left CHECKED -> send the off command */
    }
    modulus_zig_cmd_send_gcode((const uint8_t *)cmd, strlen(cmd));
}

static void qs_macro_tint_cb(lv_event_t *e)
{
    lv_obj_t *btn = lv_event_get_target(e);
    lv_obj_t *lbl = lv_obj_get_child(btn, 0);
    if (!lbl) {
        return;
    }
    const bool on = lv_obj_has_state(btn, LV_STATE_CHECKED);
    lv_obj_set_style_text_color(lbl,
                                on ? modulus_ui_color_on_primary_container()
                                   : modulus_ui_color_on_secondary_container(),
                                0);
}

static void qs_build_macros(lv_obj_t *panel)
{
    lv_obj_t *grid = NULL;
    for (uint8_t slot = 0; slot < SETTINGS_MACRO_SLOTS; slot++) {
        char name[16], on[64], off[64];
        if (!settings_macro_slot_load(slot, name, sizeof(name), on, sizeof(on), off,
                                      sizeof(off), NULL)) {
            continue;
        }
        if (!grid) {
            qs_section_title(panel, "Macros");
            grid = lv_obj_create(panel);
            lv_obj_remove_style_all(grid);
            lv_obj_set_size(grid, lv_pct(100), LV_SIZE_CONTENT);
            qs_disable_scroll(grid);
            lv_obj_set_flex_flow(grid, LV_FLEX_FLOW_ROW_WRAP);
            lv_obj_set_style_pad_column(grid, MOD_UI_SPACE_SM, 0);
            lv_obj_set_style_pad_row(grid, MOD_UI_SPACE_SM, 0);
        }
        lv_obj_t *btn = lv_button_create(grid);
        lv_obj_set_size(btn, LV_SIZE_CONTENT, MOD_UI_TOUCH_MIN);
        lv_obj_set_style_min_width(btn, 96, 0);
        lv_obj_set_style_pad_hor(btn, MOD_UI_SPACE_MD, 0);
        lv_obj_set_style_radius(btn, MOD_UI_SHAPE_FULL, 0);
        lv_obj_set_style_bg_color(btn, modulus_ui_color_secondary_container(), 0);
        lv_obj_set_style_bg_color(btn, modulus_ui_color_primary_container(), LV_STATE_CHECKED);
        lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
        lv_obj_set_style_shadow_width(btn, 0, 0);
        qs_disable_scroll(btn);
        modulus_ui_apply_pressed_state_layer_color(btn, modulus_ui_color_on_secondary_container());
        if (off[0] != '\0') {
            lv_obj_add_flag(btn, LV_OBJ_FLAG_CHECKABLE);
            lv_obj_add_event_cb(btn, qs_macro_tint_cb, LV_EVENT_VALUE_CHANGED, NULL);
        }
        lv_obj_t *lbl = lv_label_create(btn);
        lv_label_set_text(lbl, name);
        lv_obj_set_style_text_color(lbl, modulus_ui_color_on_secondary_container(), 0);
        lv_obj_set_style_text_font(lbl, MOD_UI_FONT_LABEL_L, 0);
        lv_obj_center(lbl);
        lv_obj_add_event_cb(btn, qs_macro_cb, LV_EVENT_CLICKED, (void *)(uintptr_t)slot);
    }
}

/* -- Devices tab: Zigbee tiles ----------------------------------------- */

static const char *qs_dev_tag(uint8_t caps)
{
    if (caps & ZIGBEE_CAP_COVER) {
        return "Cover";
    }
    if (caps & ZIGBEE_CAP_THERMOSTAT) {
        return "Climate";
    }
    if (caps == ZIGBEE_CAP_SENSOR) {
        return "Sense";
    }
    return "Out"; /* switches, plugs, lights */
}

static void qs_close_detail(void)
{
    if (s_detail) {
        lv_obj_delete(s_detail);
        s_detail = NULL;
        s_detail_idx = -1;
    }
}

static void qs_detail_bg_cb(lv_event_t *e)
{
    (void)e;
    qs_close_detail();
}

static void qs_detail_level_cb(lv_event_t *e)
{
    const lv_event_code_t code = lv_event_get_code(e);
    lv_obj_t *sl = lv_event_get_target(e);
    lv_obj_t *vl = lv_obj_get_user_data(sl);
    const int32_t v = lv_slider_get_value(sl);
    if (vl) {
        char b[12];
        snprintf(b, sizeof(b), "%d%%", (int)((v * 100) / 254));
        modulus_ui_label_set_text_if_changed(vl, b);
    }
    if (code == LV_EVENT_RELEASED) {
        (void)modulus_wireless_zigbee_device_set_level(s_detail_idx, (uint8_t)v);
    }
}

static void qs_detail_identify_cb(lv_event_t *e)
{
    (void)e;
    (void)modulus_wireless_zigbee_device_identify(s_detail_idx);
}

static void qs_detail_leave_cb(lv_event_t *e)
{
    (void)e;
    const int idx = s_detail_idx;
    qs_close_detail();
    (void)modulus_wireless_zigbee_device_leave(idx);
    qs_body_rebuild_deferred();
}

static void qs_detail_refresh_cb(lv_event_t *e)
{
    (void)e;
    (void)modulus_wireless_zigbee_device_read_sensors(s_detail_idx);
}

static void qs_detail_cover_cb(lv_event_t *e)
{
    (void)modulus_wireless_zigbee_device_cover(s_detail_idx,
                                               (uint8_t)(uintptr_t)lv_event_get_user_data(e));
}

static lv_obj_t *qs_detail_btn(lv_obj_t *parent, const char *txt, lv_event_cb_t cb, void *ud)
{
    lv_obj_t *b = lv_button_create(parent);
    lv_obj_set_size(b, LV_SIZE_CONTENT, MOD_UI_TOUCH_MIN);
    lv_obj_set_style_min_width(b, 96, 0);
    lv_obj_set_style_pad_hor(b, MOD_UI_SPACE_MD, 0);
    lv_obj_set_style_radius(b, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_bg_color(b, modulus_ui_color_secondary_container(), 0);
    lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
    lv_obj_set_style_shadow_width(b, 0, 0);
    modulus_ui_apply_pressed_state_layer_color(b, modulus_ui_color_on_secondary_container());
    lv_obj_t *l = lv_label_create(b);
    lv_label_set_text(l, txt);
    lv_obj_set_style_text_color(l, modulus_ui_color_on_secondary_container(), 0);
    lv_obj_set_style_text_font(l, MOD_UI_FONT_LABEL_L, 0);
    lv_obj_center(l);
    lv_obj_add_event_cb(b, cb, LV_EVENT_SHORT_CLICKED, ud);
    return b;
}

/* Long-press detail overlay: shows only what the device exposes. */
static void qs_open_detail(int idx)
{
    modulus_zb_device_t d = {};
    if (!modulus_wireless_zigbee_device_get(idx, &d) || !s_sheet) {
        return;
    }
    qs_close_detail();
    s_detail_idx = idx;
    s_detail = lv_obj_create(s_sheet);
    lv_obj_remove_style_all(s_detail);
    lv_obj_set_size(s_detail, lv_pct(100), lv_pct(100));
    qs_disable_scroll(s_detail);
    lv_obj_set_style_bg_color(s_detail, modulus_ui_color_opaque_scrim(), 0);
    lv_obj_set_style_bg_opa(s_detail, LV_OPA_COVER, 0);
    lv_obj_add_flag(s_detail, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(s_detail, qs_detail_bg_cb, LV_EVENT_CLICKED, NULL);

    lv_obj_t *card = lv_obj_create(s_detail);
    lv_obj_remove_style_all(card);
    lv_obj_set_size(card, 460, LV_SIZE_CONTENT);
    lv_obj_center(card);
    qs_disable_scroll(card);
    lv_obj_set_style_bg_color(card, modulus_ui_color_surface_container_highest(), 0);
    lv_obj_set_style_bg_opa(card, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(card, MOD_UI_SHAPE_DIALOG, 0);
    lv_obj_set_style_border_width(card, 1, 0);
    lv_obj_set_style_border_color(card, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_pad_all(card, MOD_UI_SPACE_LG, 0);
    lv_obj_set_flex_flow(card, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(card, MOD_UI_SPACE_SM, 0);
    lv_obj_add_flag(card, LV_OBJ_FLAG_CLICKABLE); /* eat clicks so bg doesn't close */
    modulus_ui_motion_dialog_enter(card);

    lv_obj_t *ttl = lv_label_create(card);
    lv_label_set_text(ttl, d.name);
    lv_obj_set_style_text_color(ttl, modulus_ui_color_on_surface(), 0);
    lv_obj_set_style_text_font(ttl, MOD_UI_FONT_TITLE_M, 0);

    if (d.short_addr != 0 && (d.lqi != 0 || d.rssi != 0)) {
        lv_obj_t *lk = lv_label_create(card);
        char lbuf[40];
        if (d.rssi != 0) {
            snprintf(lbuf, sizeof(lbuf), "LQI %u | %d dBm", (unsigned)d.lqi, (int)d.rssi);
        } else {
            snprintf(lbuf, sizeof(lbuf), "LQI %u", (unsigned)d.lqi);
        }
        lv_label_set_text(lk, lbuf);
        lv_obj_set_style_text_color(lk, modulus_ui_color_on_surface_variant(), 0);
        lv_obj_set_style_text_font(lk, MOD_UI_FONT_BODY_M, 0);
    }
    if ((d.caps & ZIGBEE_CAP_SENSOR) && d.zone_seen) {
        lv_obj_t *zn = lv_label_create(card);
        lv_label_set_text(zn, (d.zone_status & 0x0001u) ? "Zone: Alarm (open)" : "Zone: Clear");
        lv_obj_set_style_text_color(zn,
                                    (d.zone_status & 0x0001u) ? modulus_ui_color_error()
                                                              : modulus_ui_color_on_surface_variant(),
                                    0);
        lv_obj_set_style_text_font(zn, MOD_UI_FONT_BODY_M, 0);
    }

    if (d.caps & ZIGBEE_CAP_LEVEL) {
        lv_obj_t *sl = qs_slider_row(card, "Brightness", 0, 254, d.level, "l");
        /* reroute: level goes to the device, not backlight/volume */
        lv_obj_remove_event_cb(sl, qs_slider_live_cb);
        lv_obj_add_event_cb(sl, qs_detail_level_cb, LV_EVENT_VALUE_CHANGED, NULL);
        lv_obj_add_event_cb(sl, qs_detail_level_cb, LV_EVENT_RELEASED, NULL);
    }
    if (d.caps & (ZIGBEE_CAP_POWER | ZIGBEE_CAP_METER)) {
        lv_obj_t *sv = lv_label_create(card);
        char buf[96];
        if (d.sensors_seen) {
            snprintf(buf, sizeof(buf), "%.1f V   %.3f A   %.1f W   %.2f kWh",
                     d.volt_raw / 10.0, d.curr_raw / 1000.0, d.power_raw / 10.0,
                     d.energy_raw / 100.0);
        } else {
            snprintf(buf, sizeof(buf), "Tap Refresh to read power data");
        }
        lv_label_set_text(sv, buf);
        lv_obj_set_style_text_color(sv, modulus_ui_color_on_surface_variant(), 0);
        lv_obj_set_style_text_font(sv, MOD_UI_FONT_BODY_M, 0);
    }

    lv_obj_t *btns = lv_obj_create(card);
    lv_obj_remove_style_all(btns);
    lv_obj_set_size(btns, lv_pct(100), LV_SIZE_CONTENT);
    qs_disable_scroll(btns);
    lv_obj_set_flex_flow(btns, LV_FLEX_FLOW_ROW_WRAP);
    lv_obj_set_style_pad_column(btns, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_pad_row(btns, MOD_UI_SPACE_SM, 0);
    if (d.caps & ZIGBEE_CAP_COVER) {
        qs_detail_btn(btns, "Open", qs_detail_cover_cb, (void *)0);
        qs_detail_btn(btns, "Close", qs_detail_cover_cb, (void *)1);
        qs_detail_btn(btns, "Stop", qs_detail_cover_cb, (void *)2);
    }
    if (d.caps & (ZIGBEE_CAP_POWER | ZIGBEE_CAP_METER)) {
        qs_detail_btn(btns, "Refresh", qs_detail_refresh_cb, NULL);
    }
    if (d.short_addr != 0) {
        qs_detail_btn(btns, "Identify", qs_detail_identify_cb, NULL);
    }
    qs_detail_btn(btns, "Remove", qs_detail_leave_cb, NULL);
}

static void qs_tile_cb(lv_event_t *e)
{
    const int idx = (int)(intptr_t)lv_event_get_user_data(e);
    if (lv_event_get_code(e) == LV_EVENT_LONG_PRESSED) {
        qs_open_detail(idx);
        return;
    }
    modulus_zb_device_t d = {};
    if (!modulus_wireless_zigbee_device_get(idx, &d)) {
        return;
    }
    if (d.caps & ZIGBEE_CAP_COVER) {
        qs_open_detail(idx); /* covers have no single toggle action */
    } else if (d.caps == ZIGBEE_CAP_SENSOR) {
        (void)modulus_wireless_zigbee_device_read_sensors(idx);
    } else {
        (void)modulus_wireless_zigbee_device_toggle(idx);
        qs_body_rebuild_deferred(); /* re-tint */
    }
}

static void qs_cols_cb(lv_event_t *e)
{
    (void)e;
    modulus_nvs_set_u8("qs_cols", modulus_nvs_get_u8("qs_cols", 3) == 3 ? 2 : 3);
    qs_body_rebuild_deferred();
}

static void qs_scene_cb(lv_event_t *e)
{
    modulus_zb_scene_apply((uint8_t)(uintptr_t)lv_event_get_user_data(e));
    qs_body_rebuild_deferred();
}

static void qs_clog_id_cb(lv_event_t *e)
{
    const int idx = (int)(intptr_t)lv_event_get_user_data(e);
    if (!modulus_wireless_zigbee_device_identify(idx)) {
        /* fall through */
    }
}

static void qs_recipe_cb(lv_event_t *e)
{
    modulus_recipe_set((uint8_t)(uintptr_t)lv_event_get_user_data(e));
    qs_body_rebuild_deferred();
}

static void qs_machine_cb(lv_event_t *e)
{
    modulus_ui_cnc_profile_activate((uint8_t)(uintptr_t)lv_event_get_user_data(e));
    qs_body_rebuild_deferred();
}

static void qs_build_devices(lv_obj_t *panel)
{
    qs_section_title(panel, "Machine state");

    const bool hub_down = modulus_nvs_get_u8("zigbee", 0) != 0 &&
                          modulus_wireless_zb_hub_offline();
    if (hub_down) {
        lv_obj_t *warn = lv_label_create(panel);
        lv_label_set_text(warn, "Zigbee hub offline - check wiring/power");
        lv_obj_set_style_text_color(warn, modulus_ui_color_error(), 0);
        lv_obj_set_style_text_font(warn, MOD_UI_FONT_BODY_M, 0);
        lv_obj_set_width(warn, lv_pct(100));
    }
    const char *pwr = modulus_zb_power_warn_text();
    if (pwr) {
        lv_obj_t *pw = lv_label_create(panel);
        lv_label_set_text(pw, pwr);
        lv_obj_set_style_text_color(pw, modulus_ui_color_error(), 0);
        lv_obj_set_style_text_font(pw, MOD_UI_FONT_BODY_M, 0);
        lv_obj_set_width(pw, lv_pct(100));
        const int ci = modulus_zb_clog_device_idx();
        if (ci >= 0) {
            lv_obj_t *id = qs_detail_btn(panel, "Identify weak vacuum", qs_clog_id_cb,
                                         (void *)(intptr_t)ci);
            (void)id;
        }
    }
    /* Scenes: shop presets (no ZCL group dependency). */
    qs_section_title(panel, "Scenes");
    lv_obj_t *scenes = lv_obj_create(panel);
    lv_obj_remove_style_all(scenes);
    lv_obj_set_size(scenes, lv_pct(100), LV_SIZE_CONTENT);
    qs_disable_scroll(scenes);
    lv_obj_set_flex_flow(scenes, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(scenes, MOD_UI_SPACE_SM, 0);
    static const char *const k_scene[] = {"Cut", "Cleanup", "Idle", "E-Stop"};
    static const uint8_t k_sid[] = {MODULUS_ZB_SCENE_CUT, MODULUS_ZB_SCENE_CLEANUP,
                                    MODULUS_ZB_SCENE_IDLE, MODULUS_ZB_SCENE_EMERGENCY};
    for (int i = 0; i < 4; i++) {
        lv_obj_t *b = lv_button_create(scenes);
        lv_obj_set_size(b, lv_pct(23), MOD_UI_TOUCH_MIN);
        lv_obj_set_style_radius(b, MOD_UI_SHAPE_FULL, 0);
        lv_obj_set_style_shadow_width(b, 0, 0);
        lv_obj_set_style_bg_color(b,
                                  i == 3 ? modulus_ui_color_error_container()
                                         : modulus_ui_color_secondary_container(),
                                  0);
        lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
        modulus_ui_apply_pressed_state_layer_color(
            b, i == 3 ? modulus_ui_color_on_error_container()
                      : modulus_ui_color_on_secondary_container());
        lv_obj_t *l = lv_label_create(b);
        lv_label_set_text(l, k_scene[i]);
        lv_obj_set_style_text_color(l,
                                    i == 3 ? modulus_ui_color_on_error_container()
                                           : modulus_ui_color_on_secondary_container(),
                                    0);
        lv_obj_set_style_text_font(l, MOD_UI_FONT_LABEL_M, 0);
        lv_obj_center(l);
        lv_obj_add_event_cb(b, qs_scene_cb, LV_EVENT_SHORT_CLICKED, (void *)(uintptr_t)k_sid[i]);
    }

    /* Machine profiles (saved slots only). */
    qs_section_title(panel, "Profiles");
    lv_obj_t *mach = lv_obj_create(panel);
    lv_obj_remove_style_all(mach);
    lv_obj_set_size(mach, lv_pct(100), LV_SIZE_CONTENT);
    qs_disable_scroll(mach);
    lv_obj_set_flex_flow(mach, LV_FLEX_FLOW_ROW_WRAP);
    lv_obj_set_style_pad_column(mach, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_pad_row(mach, MOD_UI_SPACE_SM, 0);
    const uint8_t cur_m = modulus_nvs_get_u8("cnc_prof", 0);
    for (uint8_t i = 0; i < 4; i++) {
        char nm[28];
        if (!modulus_ui_cnc_profile_name(i, nm, sizeof(nm)) || nm[0] == '\0') {
            continue;
        }
        lv_obj_t *b = lv_button_create(mach);
        lv_obj_set_size(b, lv_pct(48), MOD_UI_TOUCH_MIN);
        lv_obj_set_style_radius(b, MOD_UI_SHAPE_MD, 0);
        lv_obj_set_style_shadow_width(b, 0, 0);
        lv_obj_set_style_bg_color(b,
                                  i == cur_m ? modulus_ui_color_secondary_container()
                                             : modulus_ui_color_surface_container_high(),
                                  0);
        lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
        lv_obj_set_style_border_width(b, i == cur_m ? 0 : 1, 0);
        lv_obj_set_style_border_color(b, modulus_ui_color_outline_variant(), 0);
        modulus_ui_apply_pressed_state_layer_color(
            b, i == cur_m ? modulus_ui_color_on_secondary_container()
                          : modulus_ui_color_on_surface());
        lv_obj_t *l = lv_label_create(b);
        lv_label_set_text(l, nm);
        lv_obj_set_width(l, lv_pct(90));
        lv_label_set_long_mode(l, LV_LABEL_LONG_DOT);
        lv_obj_set_style_text_align(l, LV_TEXT_ALIGN_CENTER, 0);
        lv_obj_set_style_text_color(l,
                                    i == cur_m ? modulus_ui_color_on_secondary_container()
                                               : modulus_ui_color_on_surface(),
                                    0);
        lv_obj_set_style_text_font(l, MOD_UI_FONT_LABEL_M, 0);
        lv_obj_center(l);
        lv_obj_add_event_cb(b, qs_machine_cb, LV_EVENT_SHORT_CLICKED, (void *)(uintptr_t)i);
    }

    qs_section_title(panel, "Zigbee devices");

    const int n = modulus_wireless_zigbee_device_count();
    if (n == 0) {
        lv_obj_t *empty = lv_label_create(panel);
        lv_label_set_text(empty,
                          hub_down ? "Hub link lost - devices unreachable until restore."
                                   : "No Zigbee devices paired yet.\n"
                                     "Settings > Wireless > Zigbee > Pair devices.");
        lv_obj_set_style_text_color(empty, modulus_ui_color_on_surface_variant(), 0);
        lv_obj_set_style_text_font(empty, MOD_UI_FONT_BODY_M, 0);
        return;
    }
    const uint8_t cols = modulus_nvs_get_u8("qs_cols", 3) == 2 ? 2 : 3;
    lv_obj_t *grid = lv_obj_create(panel);
    lv_obj_remove_style_all(grid);
    lv_obj_set_size(grid, lv_pct(100), LV_SIZE_CONTENT);
    qs_disable_scroll(grid);
    lv_obj_set_flex_flow(grid, LV_FLEX_FLOW_ROW_WRAP);
    lv_obj_set_style_pad_column(grid, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_pad_row(grid, MOD_UI_SPACE_SM, 0);
    for (int i = 0; i < n; i++) {
        modulus_zb_device_t d = {};
        if (!modulus_wireless_zigbee_device_get(i, &d)) {
            continue;
        }
        const bool offline = d.short_addr == 0;
        const bool lit = d.on && !offline;
        lv_obj_t *t = lv_button_create(grid);
        lv_obj_set_size(t, lv_pct(cols == 2 ? 48 : 31), 80);
        lv_obj_set_style_radius(t, MOD_UI_SHAPE_LG, 0);
        lv_obj_set_style_shadow_width(t, 0, 0);
        lv_obj_set_style_bg_color(t, lit ? modulus_ui_color_primary_container()
                                         : modulus_ui_color_surface_container_high(), 0);
        lv_obj_set_style_bg_opa(t, LV_OPA_COVER, 0);
        lv_obj_set_style_border_width(t, lit ? 0 : 1, 0);
        lv_obj_set_style_border_color(t, modulus_ui_color_outline_variant(), 0);
        qs_disable_scroll(t);
        lv_obj_set_flex_flow(t, LV_FLEX_FLOW_COLUMN);
        lv_obj_set_flex_align(t, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER,
                              LV_FLEX_ALIGN_CENTER);
        lv_obj_set_style_pad_row(t, 2, 0);
        modulus_ui_apply_pressed_state_layer_color(
            t, lit ? modulus_ui_color_on_primary_container() : modulus_ui_color_on_surface());
        const lv_color_t fg = lit ? modulus_ui_color_on_primary_container()
                                  : modulus_ui_color_on_surface_variant();
        const lv_opa_t leaf_opa = offline ? LV_OPA_50 : LV_OPA_COVER;
        lv_obj_t *ic = lv_label_create(t);
        char head[40];
        if ((d.caps & (ZIGBEE_CAP_POWER | ZIGBEE_CAP_METER)) && (d.sensors_seen & 0x04)) {
            snprintf(head, sizeof(head), "%s %.0fW", qs_dev_tag(d.caps), d.power_raw / 10.0);
        } else if ((d.caps & ZIGBEE_CAP_SENSOR) && d.zone_seen) {
            snprintf(head, sizeof(head), "%s %s", qs_dev_tag(d.caps),
                     (d.zone_status & 0x0001u) ? "Open" : "Ok");
        } else if (d.lqi != 0) {
            snprintf(head, sizeof(head), "%s L%u", qs_dev_tag(d.caps), (unsigned)d.lqi);
        } else {
            snprintf(head, sizeof(head), "%s", qs_dev_tag(d.caps));
        }
        lv_label_set_text(ic, head);
        lv_obj_set_style_text_color(ic, fg, 0);
        lv_obj_set_style_text_opa(ic, leaf_opa, 0);
        lv_obj_set_style_text_font(ic, MOD_UI_FONT_LABEL_M, 0);
        lv_obj_t *nm = lv_label_create(t);
        lv_label_set_text(nm, d.name);
        lv_obj_set_width(nm, lv_pct(94));
        lv_label_set_long_mode(nm, LV_LABEL_LONG_DOT);
        lv_obj_set_style_text_align(nm, LV_TEXT_ALIGN_CENTER, 0);
        lv_obj_set_style_text_color(nm, fg, 0);
        lv_obj_set_style_text_opa(nm, leaf_opa, 0);
        lv_obj_set_style_text_font(nm, MOD_UI_FONT_LABEL_L, 0);
        lv_obj_add_event_cb(t, qs_tile_cb, LV_EVENT_SHORT_CLICKED, (void *)(intptr_t)i);
        lv_obj_add_event_cb(t, qs_tile_cb, LV_EVENT_LONG_PRESSED, (void *)(intptr_t)i);
    }
    (void)qs_detail_btn(panel, cols == 2 ? "3 columns" : "2 columns", qs_cols_cb, NULL);
}

/* -- Sheet shell: header with tabs, tab body, lifecycle ---------------- */

static void hide_quick_cb(lv_event_t *e)
{
    (void)e;
    modulus_ui_hide_quick_settings();
}

static void open_settings_cb(lv_event_t *e)
{
    (void)e;
    modulus_ui_hide_quick_settings();
    modulus_ui_show_settings();
}

static void panel_click_cb(lv_event_t *e)
{
    lv_event_stop_bubbling(e);
}

static void qs_tab_cb(lv_event_t *e)
{
    lv_obj_t *track = lv_obj_get_parent(lv_event_get_target(e));
    modulus_nvs_set_u8("qs_tab", (uint8_t)modulus_ui_segmented_get_selected(track));
    qs_body_rebuild_deferred();
}

static void qs_build_system(lv_obj_t *panel)
{
    qs_section_title(panel, "Connectivity");
    lv_obj_t *grid = lv_obj_create(panel);
    lv_obj_remove_style_all(grid);
    lv_obj_set_size(grid, lv_pct(100), LV_SIZE_CONTENT);
    qs_disable_scroll(grid);
    lv_obj_set_flex_flow(grid, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(grid, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    for (uint8_t i = 0; i < 4; i++) {
        qs_radio_tile(grid, i);
    }

    qs_section_title(panel, "Display & sound");
    lv_obj_t *bs = qs_slider_row(panel, "Brightness", 5, 100,
                                 modulus_nvs_get_u8("bright", 80), "b");
    lv_obj_add_event_cb(bs, qs_bright_rel_cb, LV_EVENT_RELEASED, NULL);
    (void)qs_slider_row(panel, "Volume", 0, 100, modulus_audio_get_volume(), "v");

    qs_section_title(panel, "Status");
    char sbuf[96];
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    if (st.sd_percent > 0.5f) {
        snprintf(sbuf, sizeof(sbuf), "CNC: %s  |  Job %.0f%%",
                 settings_cnc_transport_name(
                     modulus_nvs_get_u8("cnc_conn", SETTINGS_CNC_XPORT_DEFAULT)),
                 (double)st.sd_percent);
    } else {
        snprintf(sbuf, sizeof(sbuf), "CNC: %s",
                 settings_cnc_transport_name(
                     modulus_nvs_get_u8("cnc_conn", SETTINGS_CNC_XPORT_DEFAULT)));
    }
    const bool warn = modulus_recipe_battery_blocks_cycle();
    qs_status_card(panel, sbuf, modulus_recipe_shift_text(), warn);

    qs_build_macros(panel);
}

static void qs_build_material(lv_obj_t *panel)
{
    qs_section_title(panel, "Material presets");
    lv_obj_t *hint = lv_label_create(panel);
    lv_label_set_text(hint, "Feed / spindle defaults + Zigbee scene + mist");
    lv_obj_set_style_text_color(hint, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(hint, MOD_UI_FONT_BODY_M, 0);

    lv_obj_t *rec = lv_obj_create(panel);
    lv_obj_remove_style_all(rec);
    lv_obj_set_size(rec, lv_pct(100), LV_SIZE_CONTENT);
    qs_disable_scroll(rec);
    lv_obj_set_flex_flow(rec, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(rec, MOD_UI_SPACE_SM, 0);
    const uint8_t cur_r = modulus_recipe_get();
    for (uint8_t i = 0; i < MODULUS_RECIPE_COUNT; i++) {
        const bool sel = i == cur_r;
        lv_obj_t *b = lv_button_create(rec);
        lv_obj_set_size(b, lv_pct(31), 56);
        lv_obj_set_style_radius(b, MOD_UI_SHAPE_FULL, 0);
        lv_obj_set_style_shadow_width(b, 0, 0);
        lv_obj_set_style_bg_color(b,
                                  sel ? modulus_ui_color_primary_container()
                                      : modulus_ui_color_surface_container_high(),
                                  0);
        lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
        lv_obj_set_style_border_width(b, sel ? 0 : 1, 0);
        lv_obj_set_style_border_color(b, modulus_ui_color_outline_variant(), 0);
        modulus_ui_apply_pressed_state_layer_color(
            b, sel ? modulus_ui_color_on_primary_container() : modulus_ui_color_on_surface());
        lv_obj_t *l = lv_label_create(b);
        lv_label_set_text(l, modulus_recipe_name(i));
        lv_obj_set_style_text_color(l,
                                    sel ? modulus_ui_color_on_primary_container()
                                        : modulus_ui_color_on_surface_variant(),
                                    0);
        lv_obj_set_style_text_font(l, MOD_UI_FONT_LABEL_L, 0);
        lv_obj_center(l);
        lv_obj_add_event_cb(b, qs_recipe_cb, LV_EVENT_SHORT_CLICKED, (void *)(uintptr_t)i);
    }
}

/* -- Terminal tab: MDI line + scrollback + live controller messages ------ */

/* Scrollback persists across sheet opens/tab switches (static, no heap).
 * Console lines are drained from the Zig ring by the refresh timer whenever
 * the sheet exists (any tab), so nothing is missed while browsing Devices. */
#define QS_TERM_LOG_CAP 3072
static char s_term_log[QS_TERM_LOG_CAP];
static size_t s_term_len;
static lv_obj_t *s_term_ta;    /* readonly scrollback textarea (NULL off-tab) */
static lv_obj_t *s_term_input; /* one-line MDI input */

static void qs_term_append(const char *line, size_t n, bool tx)
{
    const size_t need = n + 3; /* "> " + line + \n worst case */
    if (need >= sizeof(s_term_log)) {
        return;
    }
    if (s_term_len + need >= sizeof(s_term_log)) {
        /* Drop the oldest half at a line boundary — keeps recent context. */
        size_t cut = s_term_len / 2;
        while (cut < s_term_len && s_term_log[cut] != '\n') {
            cut++;
        }
        cut = (cut < s_term_len) ? cut + 1 : s_term_len;
        memmove(s_term_log, s_term_log + cut, s_term_len - cut);
        s_term_len -= cut;
    }
    if (tx) {
        s_term_log[s_term_len++] = '>';
        s_term_log[s_term_len++] = ' ';
    }
    memcpy(s_term_log + s_term_len, line, n);
    s_term_len += n;
    s_term_log[s_term_len++] = '\n';
    s_term_log[s_term_len] = '\0';
}

static void qs_term_drain(void)
{
    uint8_t dir = 0;
    uint8_t line[100];
    bool got = false;
    int32_t n;
    while ((n = modulus_zig_console_pop(&dir, line, sizeof(line) - 1)) >= 0) {
        if (n > 0) {
            qs_term_append((const char *)line, (size_t)n, dir == 1);
            got = true;
        }
    }
    if (got && s_term_ta) {
        lv_textarea_set_text(s_term_ta, s_term_log);
        lv_textarea_set_cursor_pos(s_term_ta, LV_TEXTAREA_CURSOR_LAST); /* stick to tail */
    }
}

static void qs_term_send_cb(lv_event_t *e)
{
    (void)e;
    if (!s_term_input) {
        return;
    }
    const char *txt = lv_textarea_get_text(s_term_input);
    const size_t n = txt ? strlen(txt) : 0;
    if (n == 0 || n > 120) {
        return;
    }
    modulus_zig_cmd_send_gcode((const uint8_t *)txt, n); /* TX echo via console tap */
    lv_textarea_set_text(s_term_input, "");
    modulus_audio_play_ui(1);
}

static void qs_term_kb_cb(lv_event_t *e)
{
    /* READY (keyboard check) sends; CANCEL closes. */
    lv_obj_t *kb = lv_event_get_target(e);
    if (lv_event_get_code(e) == LV_EVENT_READY) {
        qs_term_send_cb(NULL);
    }
    lv_obj_add_flag(kb, LV_OBJ_FLAG_HIDDEN);
    qs_term_set_lift(kb, false);
}

static void qs_term_focus_cb(lv_event_t *e)
{
    lv_obj_t *kb = lv_event_get_user_data(e);
    if (!kb) {
        return;
    }
    if (lv_event_get_code(e) == LV_EVENT_FOCUSED) {
        lv_keyboard_set_textarea(kb, s_term_input);
        lv_obj_remove_flag(kb, LV_OBJ_FLAG_HIDDEN);
        /* Ensure kb has a real height before lifting the sheet. */
        lv_obj_update_layout(kb);
        qs_term_set_lift(kb, true);
    } else if (lv_event_get_code(e) == LV_EVENT_DEFOCUSED) {
        lv_obj_add_flag(kb, LV_OBJ_FLAG_HIDDEN);
        qs_term_set_lift(kb, false);
    }
}

static void qs_term_input_delete_cb(lv_event_t *e)
{
    lv_obj_t *kb = lv_event_get_user_data(e);
    qs_term_set_lift(NULL, false);
    if (kb) {
        lv_obj_delete(kb);
    }
    s_term_input = NULL;
    s_term_ta = NULL; /* deleted alongside as a sibling in the same clean */
}

static void qs_build_terminal(lv_obj_t *panel)
{
    /* Scrollback (readonly, newest pinned). */
    s_term_ta = lv_textarea_create(panel);
    lv_obj_set_size(s_term_ta, lv_pct(100), 240);
    modulus_ui_apply_textarea_theme(s_term_ta, true);
    lv_textarea_set_text(s_term_ta, s_term_len ? s_term_log : "(no traffic yet)\n");
    lv_textarea_set_cursor_pos(s_term_ta, LV_TEXTAREA_CURSOR_LAST);
    lv_obj_add_state(s_term_ta, LV_STATE_DISABLED); /* readonly: no kb focus */

    /* Input row: textarea + Send. */
    lv_obj_t *row = lv_obj_create(panel);
    lv_obj_remove_style_all(row);
    lv_obj_set_size(row, lv_pct(100), LV_SIZE_CONTENT);
    qs_disable_scroll(row);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(row, MOD_UI_SPACE_SM, 0);

    s_term_input = lv_textarea_create(row);
    lv_textarea_set_one_line(s_term_input, true);
    lv_textarea_set_placeholder_text(s_term_input, "MDI / $ command");
    lv_obj_set_flex_grow(s_term_input, 1);
    lv_obj_set_style_min_height(s_term_input, MOD_UI_TOUCH_MIN, 0);
    modulus_ui_apply_textarea_theme(s_term_input, false);

    lv_obj_t *send = lv_button_create(row);
    lv_obj_set_size(send, 96, MOD_UI_TOUCH_MIN);
    lv_obj_set_style_radius(send, MOD_UI_SHAPE_SM, 0);
    lv_obj_set_style_bg_color(send, modulus_ui_color_primary_container(), 0);
    lv_obj_set_style_bg_opa(send, LV_OPA_COVER, 0);
    lv_obj_set_style_shadow_width(send, 0, 0);
    modulus_ui_apply_pressed_state_layer_color(send, modulus_ui_color_on_primary_container());
    lv_obj_t *sl = lv_label_create(send);
    lv_label_set_text(sl, "Send");
    lv_obj_set_style_text_color(sl, modulus_ui_color_on_primary_container(), 0);
    lv_obj_center(sl);
    lv_obj_add_event_cb(send, qs_term_send_cb, LV_EVENT_SHORT_CLICKED, NULL);

    /* Keyboard: hidden until the input focuses; check = send, X = close. */
    lv_obj_t *kb = lv_keyboard_create(lv_layer_top());
    settings_modal_kb_configure_text(kb);
    lv_obj_add_flag(kb, LV_OBJ_FLAG_HIDDEN);
    lv_obj_add_event_cb(kb, qs_term_kb_cb, LV_EVENT_READY, NULL);
    lv_obj_add_event_cb(kb, qs_term_kb_cb, LV_EVENT_CANCEL, NULL);
    lv_obj_add_event_cb(s_term_input, qs_term_focus_cb, LV_EVENT_FOCUSED, kb);
    lv_obj_add_event_cb(s_term_input, qs_term_focus_cb, LV_EVENT_DEFOCUSED, kb);
    /* Sheet teardown deletes s_body children, but kb lives on layer_top:
     * tie its lifetime (and our static pointers) to the input's DELETE. */
    lv_obj_add_event_cb(s_term_input, qs_term_input_delete_cb, LV_EVENT_DELETE, kb);

    qs_term_drain(); /* pick up anything queued since last look */
}

/* -- Probe tab: pin indicator, cycle settings, one-tap probe cycles ------ */
#include "qs_probe_tab.inc"

static void qs_build_body(void)
{
    if (!s_body) {
        return;
    }
    s_term_ta = NULL; /* clean deletes them; delete-cb also NULLs on that path */
    s_term_input = NULL;
    lv_obj_clean(s_body);
    switch (modulus_nvs_get_u8("qs_tab", 0)) {
    case 1:
        qs_build_devices(s_body);
        break;
    case 2:
        qs_build_terminal(s_body);
        break;
    case 3:
        qs_build_probe(s_body);
        break;
    case 4:
        qs_build_material(s_body);
        break;
    default:
        qs_build_system(s_body);
        break;
    }
}

static void qs_refresh_cb(lv_timer_t *t)
{
    (void)t;
    /* Console ring is small (32 lines) — drain every tick regardless of tab
     * so scrollback misses nothing; the textarea updates only when visible. */
    qs_term_drain();
    qs_probe_tick();
    /* Live device state (reports/sensor reads) redraws the Devices tab only. */
    const uint32_t gen = modulus_wireless_zigbee_state_gen();
    if (gen != s_seen_gen) {
        s_seen_gen = gen;
        if (modulus_nvs_get_u8("qs_tab", 0) == 1) {
            qs_body_rebuild_deferred();
        }
    }
}

void modulus_ui_show_quick_settings(void)
{
    if (s_sheet) {
        return;
    }
    modulus_ui_pause_dashboard_refresh();

    s_sheet = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(s_sheet);
    lv_obj_set_size(s_sheet, lv_pct(100), lv_pct(100));
    qs_disable_scroll(s_sheet);
    modulus_ui_apply_overlay_scrim(s_sheet);
    lv_obj_add_flag(s_sheet, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(s_sheet, hide_quick_cb, LV_EVENT_CLICKED, NULL);

    lv_obj_t *panel = lv_obj_create(s_sheet);
    s_panel = panel;
    lv_obj_remove_style_all(panel);
    lv_obj_set_width(panel, lv_pct(100));
    lv_obj_set_height(panel, LV_SIZE_CONTENT);
    lv_obj_set_style_min_height(panel, 360, 0);
    lv_obj_set_style_max_height(panel, 640, 0);
    lv_obj_align(panel, LV_ALIGN_BOTTOM_MID, 0, 0);
    qs_disable_scroll(panel);
    lv_obj_set_style_bg_color(panel, modulus_ui_color_surface_container(), 0);
    lv_obj_set_style_bg_opa(panel, LV_OPA_COVER, 0);
    /* Top corners only — bottom sheet sits flush to panel edge. */
    lv_obj_set_style_radius(panel, MOD_UI_SHAPE_SHEET, 0);
    lv_obj_set_style_border_width(panel, 1, 0);
    lv_obj_set_style_border_side(panel, LV_BORDER_SIDE_TOP, 0);
    lv_obj_set_style_border_color(panel, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_pad_left(panel, MOD_UI_SPACE_MD, 0);
    lv_obj_set_style_pad_right(panel, MOD_UI_SPACE_MD, 0);
    lv_obj_set_style_pad_bottom(panel, MOD_UI_SPACE_MD, 0);
    lv_obj_set_style_pad_top(panel, MOD_UI_SPACE_XS, 0);
    lv_obj_set_flex_flow(panel, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(panel, MOD_UI_SPACE_SM, 0);
    lv_obj_add_flag(panel, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(panel, panel_click_cb, LV_EVENT_CLICKED, NULL);

    qs_drag_handle(panel);

    /* Header: tonal strip + segmented tabs + settings icon. */
    lv_obj_t *hdr = lv_obj_create(panel);
    lv_obj_remove_style_all(hdr);
    lv_obj_set_size(hdr, lv_pct(100), 56);
    qs_disable_scroll(hdr);
    lv_obj_set_style_bg_color(hdr, modulus_ui_color_surface_container_high(), 0);
    lv_obj_set_style_bg_opa(hdr, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(hdr, MOD_UI_SHAPE_MD, 0);
    lv_obj_set_style_pad_hor(hdr, MOD_UI_SPACE_SM, 0);
    lv_obj_set_flex_flow(hdr, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(hdr, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_CENTER);
    static const char *const k_tabs[] = {"System", "Devices", "Terminal", "Probe", "Material"};
    lv_obj_t *tabs = modulus_ui_segmented_create(hdr, k_tabs, 5, 108, qs_tab_cb, NULL);
    if (tabs) {
        uint8_t sel = modulus_nvs_get_u8("qs_tab", 0);
        if (sel > 4) {
            sel = 0;
        }
        modulus_ui_segmented_set_selected(tabs, sel);
    }
    lv_obj_t *gear = lv_button_create(hdr);
    lv_obj_remove_style_all(gear);
    lv_obj_set_size(gear, 48, 48);
    lv_obj_set_style_radius(gear, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_bg_color(gear, modulus_ui_color_secondary_container(), 0);
    lv_obj_set_style_bg_opa(gear, LV_OPA_COVER, 0);
    modulus_ui_apply_pressed_state_layer_color(gear, modulus_ui_color_on_secondary_container());
    lv_obj_t *gl = modulus_ui_icon_create(gear, MOD_UI_ICON_GEAR, MOD_UI_ICON_SZ_24);
    modulus_ui_icon_recolor(gl, modulus_ui_color_on_secondary_container());
    lv_obj_center(gl);
    lv_obj_add_event_cb(gear, open_settings_cb, LV_EVENT_SHORT_CLICKED, NULL);
    modulus_ui_bind_press_morph(gear, MOD_UI_SHAPE_FULL, MOD_UI_SHAPE_MD);

    s_body = lv_obj_create(panel);
    lv_obj_remove_style_all(s_body);
    lv_obj_set_width(s_body, lv_pct(100));
    lv_obj_set_height(s_body, LV_SIZE_CONTENT);
    /* Cap body so Probe/Devices scroll instead of growing past the sheet. */
    lv_obj_set_style_max_height(s_body, 420, 0);
    lv_obj_add_flag(s_body, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_scroll_dir(s_body, LV_DIR_VER);
    lv_obj_set_scrollbar_mode(s_body, LV_SCROLLBAR_MODE_AUTO);
    lv_obj_remove_flag(s_body, LV_OBJ_FLAG_SCROLL_ELASTIC);
    lv_obj_remove_flag(s_body, LV_OBJ_FLAG_SCROLL_MOMENTUM);
    lv_obj_set_flex_flow(s_body, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(s_body, MOD_UI_SPACE_SM, 0);
    qs_build_body();

    s_seen_gen = modulus_wireless_zigbee_state_gen();
    s_qs_refresh = lv_timer_create(qs_refresh_cb, 200, NULL);
    modulus_ui_motion_sheet_enter(panel, MOD_UI_MOTION_SHEET_SLIDE_PX);
}

static void qs_sheet_exit_ready(lv_anim_t *a)
{
    lv_obj_t *sheet = lv_anim_get_user_data(a);
    if (sheet) {
        lv_obj_delete(sheet);
    }
    modulus_ui_resume_dashboard_refresh();
}

void modulus_ui_hide_quick_settings(void)
{
    if (!s_sheet) {
        return;
    }
    s_qs_drag = false;
    if (s_qs_refresh) {
        lv_timer_delete(s_qs_refresh);
        s_qs_refresh = NULL;
    }
    qs_body_rebuild_cancel();
    s_detail = NULL;
    s_detail_idx = -1;
    s_body = NULL;

    lv_obj_t *sheet = s_sheet;
    lv_obj_t *panel = s_panel;
    s_sheet = NULL;
    s_panel = NULL;

    if (panel && sheet && modulus_ui_motion_smooth()) {
        lv_obj_remove_flag(sheet, LV_OBJ_FLAG_CLICKABLE);
        modulus_ui_motion_sheet_exit(panel, MOD_UI_MOTION_SHEET_SLIDE_PX, qs_sheet_exit_ready,
                                     sheet);
        return;
    }
    lv_obj_delete(sheet);
    modulus_ui_resume_dashboard_refresh();
}

bool modulus_ui_quick_settings_visible(void)
{
    return s_sheet != NULL;
}

void modulus_ui_quick_settings_theme_refresh(void)
{
    if (!s_sheet) {
        return;
    }
    /* Rebuilding from the current palette is simpler and safer than walking
     * the widget tree re-tinting each class (the old walk missed tiles). */
    modulus_ui_apply_overlay_scrim(s_sheet);
    lv_obj_t *panel = lv_obj_get_child(s_sheet, 0);
    if (panel) {
        lv_obj_set_style_bg_color(panel, modulus_ui_color_surface_container_low(), 0);
    }
    qs_close_detail();
    qs_body_rebuild_deferred();
}
