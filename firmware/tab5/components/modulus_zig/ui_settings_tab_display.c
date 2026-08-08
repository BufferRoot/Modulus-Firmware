#include "ui_settings_priv.h"
#include "ui_settings_common.h"
#include "ui_internal.h"
#include "display_shim.h"
#include "touch_shim.h"
#include "nvs_shim.h"
#include "imu_shim.h"

#include <stdio.h>
#include <string.h>

static bool s_theme_ref_exp = false;

static const char k_accent_opts[] =
    "Industrial Teal\n"
    "Cyber-Industrial\n"
    "Nocturnal Safety\n"
    "Deep Sea\n"
    "Steel & Ruby\n"
    "Electric Orchid\n"
    "Tactical Sage\n"
    "Nordic White\n"
    "Monochrome Pro";

static void bright_label_set(lv_obj_t *vl, uint8_t val)
{
    if (!vl) {
        return;
    }
    char buf[8];
    snprintf(buf, sizeof(buf), "%u%%", val);
    modulus_ui_label_set_text_if_changed(vl, buf);
}

static void display_reset_cb(void)
{
    modulus_nvs_set_u8("bright", 100);
    modulus_nvs_set_u8("refr_hz", 0);
    modulus_nvs_set_u8("darkmode", 1);
    modulus_nvs_set_u8("accent", 0);
    modulus_nvs_set_u8("flip", 0);
    modulus_nvs_set_u8("lefty", 0);
    modulus_nvs_set_u8("touch_glove", 0);
    modulus_nvs_set_u8("wake_motion", 0);
    modulus_nvs_set_u8("smooth_anim", 1);
    modulus_nvs_set_u8("sw_icons", 1);
    modulus_nvs_set_u8("motion_scheme", 0);
    modulus_nvs_set_u8("ui_contrast", 0);
    modulus_display_set_brightness(100);
    modulus_display_set_flip(false);
    modulus_touch_set_glove_mode(false);
    modulus_imu_set_wake_on_motion(false);
    modulus_ui_dashboard_set_left_handed(false);
    modulus_ui_set_dashboard_refresh_hz(0);
    modulus_ui_theme_apply();
    modulus_ui_settings_build_display_tab();
}

static void bright_cb(lv_event_t *e)
{
    const lv_event_code_t code = lv_event_get_code(e);
    if (code != LV_EVENT_VALUE_CHANGED && code != LV_EVENT_RELEASED) {
        return;
    }
    lv_obj_t *s = lv_event_get_target(e);
    const uint8_t v = (uint8_t)lv_slider_get_value(s);
    modulus_display_set_brightness(v);
    bright_label_set(lv_obj_get_user_data(s), v);
    if (code == LV_EVENT_RELEASED) {
        modulus_nvs_set_u8("bright", v);
    }
}

static void dark_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    modulus_nvs_set_u8("darkmode", on ? 1 : 0);
    modulus_ui_theme_apply();
}

static void accent_cb(lv_event_t *e)
{
    uint8_t idx = (uint8_t)lv_dropdown_get_selected(lv_event_get_target(e));
    if (idx >= 9) {
        idx = 0;
    }
    modulus_nvs_set_u8("accent", idx);
    modulus_ui_theme_apply();
}

static void glove_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    modulus_touch_set_glove_mode(on);
}

static void flip_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    modulus_nvs_set_u8("flip", on ? 1 : 0);
    modulus_display_set_flip(on);
}

static void lefty_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    modulus_nvs_set_u8("lefty", on ? 1 : 0);
    modulus_ui_dashboard_set_left_handed(on);
}

static void refr_cb(lv_event_t *e)
{
    const uint8_t idx = modulus_ui_segmented_get_selected(lv_event_get_target(e));
    modulus_ui_set_dashboard_refresh_hz(idx);
}

static void smooth_anim_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    modulus_nvs_set_u8("smooth_anim", on ? 1 : 0);
    lv_obj_t *panel = modulus_ui_settings_panel();
    if (panel) {
        settings_tune_scroll_container(panel);
    }
}

static void motion_scheme_cb(lv_event_t *e)
{
    const uint8_t idx = modulus_ui_segmented_get_selected(lv_event_get_target(e));
    modulus_nvs_set_u8("motion_scheme", idx != 0 ? 1 : 0);
}

static void contrast_cb(lv_event_t *e)
{
    const uint8_t idx = modulus_ui_segmented_get_selected(lv_event_get_target(e));
    modulus_nvs_set_u8("ui_contrast", idx > 2 ? 0 : idx);
    modulus_ui_theme_apply();
}

static void wake_motion_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    modulus_imu_set_wake_on_motion(on);
}

static void sw_icons_cb(lv_event_t *e)
{
    const bool on = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
    modulus_nvs_set_u8("sw_icons", on ? 1 : 0);
    modulus_ui_settings_theme_refresh();
}

static void format_color_hex(lv_color_t c, char *buf, size_t len)
{
    snprintf(buf, len, "#%02X%02X%02X", (unsigned)c.red, (unsigned)c.green, (unsigned)c.blue);
}

void modulus_ui_settings_build_display_tab(void)
{
    lv_obj_t *p = modulus_ui_settings_tab_panel(MOD_UI_SETTINGS_TAB_DISPLAY);
    if (!p) {
        return;
    }
    lv_obj_clean(p);

    settings_section(p, "Brightness", NULL);
    {
        const uint8_t cur_bright = modulus_nvs_get_u8("bright", 80);
        lv_obj_t *b = settings_slider_row(p, "Brightness", cur_bright, 5, 100);
        lv_obj_add_event_cb(b, bright_cb, LV_EVENT_VALUE_CHANGED, NULL);
        lv_obj_add_event_cb(b, bright_cb, LV_EVENT_RELEASED, NULL);
        bright_label_set(lv_obj_get_user_data(b), cur_bright);
    }

    settings_section(p, "Theme", NULL);
    lv_obj_t *dk = settings_toggle_row(p, "Dark mode", modulus_nvs_get_u8("darkmode", 1) != 0);
    lv_obj_add_event_cb(dk, dark_cb, LV_EVENT_VALUE_CHANGED, NULL);
    {
        uint8_t acc_idx = modulus_nvs_get_u8("accent", 0);
        if (acc_idx >= 9) {
            acc_idx = 0;
        }
        lv_obj_t *acc = settings_dropdown_row(p, "Accent", k_accent_opts, acc_idx);
        lv_obj_add_event_cb(acc, accent_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }
    {
        static const char *const k_contrast[] = {"Standard", "Medium", "High"};
        uint8_t cidx = modulus_nvs_get_u8("ui_contrast", 0);
        if (cidx > 2) {
            cidx = 0;
        }
        lv_obj_t *ct = settings_segmented_row(p, "Contrast", k_contrast, 3, cidx, 100);
        lv_obj_add_event_cb(ct, contrast_cb, LV_EVENT_VALUE_CHANGED, NULL);
        settings_note(p, "Raises outline and secondary text contrast for bright shops.");
    }
    if (!modulus_ui_theme_contrast_ok()) {
        settings_note(p, "Contrast check failed for this accent - try another or raise contrast.");
    }

    settings_section(p, "Touch", NULL);
    lv_obj_t *gf = settings_toggle_row(p, "Glove-friendly touch",
                                       modulus_nvs_get_u8("touch_glove", 0) != 0);
    lv_obj_add_event_cb(gf, glove_cb, LV_EVENT_VALUE_CHANGED, NULL);

    settings_section(p, "Motion", NULL);
    lv_obj_t *wm = settings_toggle_row(p, "Wake on motion",
                                       modulus_nvs_get_u8("wake_motion", 0) != 0);
    lv_obj_add_event_cb(wm, wake_motion_cb, LV_EVENT_VALUE_CHANGED, NULL);
    lv_obj_t *si = settings_toggle_row(p, "Switch check icons",
                                       modulus_nvs_get_u8("sw_icons", 1) != 0);
    lv_obj_add_event_cb(si, sw_icons_cb, LV_EVENT_VALUE_CHANGED, NULL);
    settings_note(p, "Phosphor check on toggles when enabled; plain knob when off.");

    settings_section(p, "Orientation", NULL);
    lv_obj_t *fl = settings_toggle_row(p, "Flip display", modulus_nvs_get_u8("flip", 0) != 0);
    lv_obj_add_event_cb(fl, flip_cb, LV_EVENT_VALUE_CHANGED, NULL);
    lv_obj_t *lf = settings_toggle_row(p, "Left-handed layout", modulus_nvs_get_u8("lefty", 0) != 0);
    lv_obj_add_event_cb(lf, lefty_cb, LV_EVENT_VALUE_CHANGED, NULL);

    settings_link_tab_row(p, "Power & sleep", "", 5);

    settings_section(p, "Performance", NULL);
    {
        uint8_t ridx = modulus_nvs_get_u8("refr_hz", 0);
        if (ridx > 2) {
            ridx = 2;
        }
        static const char *const k_refr[] = {"Fastest", "Balanced", "Power saver"};
        lv_obj_t *r = settings_segmented_row(p, "Dashboard refresh", k_refr, 3, ridx, 108);
        lv_obj_add_event_cb(r, refr_cb, LV_EVENT_VALUE_CHANGED, NULL);
    }
    lv_obj_t *sm = settings_toggle_row(p, "Smooth animations",
                                       modulus_nvs_get_u8("smooth_anim", 1) != 0);
    lv_obj_add_event_cb(sm, smooth_anim_cb, LV_EVENT_VALUE_CHANGED, NULL);
    {
        static const char *const k_scheme[] = {"Standard", "Expressive"};
        const uint8_t sch = modulus_nvs_get_u8("motion_scheme", 0) != 0 ? 1 : 0;
        lv_obj_t *ms = settings_segmented_row(p, "Motion style", k_scheme, 2, sch, 120);
        lv_obj_add_event_cb(ms, motion_scheme_cb, LV_EVENT_VALUE_CHANGED, NULL);
        settings_note(p, "Expressive uses springier sheet/dialog motion and shape morph on controls.");
    }

    settings_expandable_link(p, "Show theme reference", "Hide theme reference",
                             &s_theme_ref_exp, modulus_ui_settings_build_display_tab);
    if (s_theme_ref_exp) {
        settings_detail_row(p, "Panel", "1280 x 720 MIPI-DSI");
        settings_detail_row(p, "Backlight", "PWM via BSP (GPIO22)");
        {
            char rot_buf[40];
            const bool flipped = modulus_nvs_get_u8("flip", 0) != 0;
            snprintf(rot_buf, sizeof(rot_buf), "%s (180 deg flip %s)",
                     flipped ? "Flipped" : "Normal", flipped ? "on" : "off");
            settings_detail_row(p, "Rotation", rot_buf);
        }
        settings_detail_row(p, "Color mode", modulus_ui_is_dark_mode() ? "Dark" : "Light");
        settings_detail_row(p, "Accent theme", modulus_ui_accent_name(modulus_ui_get_accent()));
        {
            char tok_buf[16];
            format_color_hex(modulus_ui_color_primary(), tok_buf, sizeof(tok_buf));
            settings_detail_row(p, "Token primary", tok_buf);
            format_color_hex(modulus_ui_color_surface(), tok_buf, sizeof(tok_buf));
            settings_detail_row(p, "Token surface", tok_buf);
            format_color_hex(modulus_ui_color_on_surface(), tok_buf, sizeof(tok_buf));
            settings_detail_row(p, "Token on-surface", tok_buf);
            format_color_hex(modulus_ui_color_error(), tok_buf, sizeof(tok_buf));
            settings_detail_row(p, "Token error", tok_buf);
            format_color_hex(modulus_ui_color_success(), tok_buf, sizeof(tok_buf));
            settings_detail_row(p, "Token success", tok_buf);
        }
    }

    static settings_reset_ctx_t reset_ctx = {
        .title = "Reset display defaults?",
        .body = "Restores brightness, orientation, theme, touch, and refresh.",
        .fn = display_reset_cb,
    };
    settings_reset_row(p, "Reset display & theme", &reset_ctx);
    modulus_ui_settings_note_tab_built(MOD_UI_SETTINGS_TAB_DISPLAY);
}
