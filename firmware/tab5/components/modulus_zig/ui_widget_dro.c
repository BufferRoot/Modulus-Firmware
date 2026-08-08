#include "ui_internal.h"
#include "ui_widget_dro_priv.h"
#include "ui_zero_confirm.h"
#include "ui_confirm_policy.h"
#include "ui_axes_preset.h"
#include "cnc_cmd_exports.h"
#include "nvs_shim.h"

extern void modulus_zig_fill_cnc_status(modulus_cnc_status_t *out);

#include <stdio.h>
#include <stdint.h>
#include <string.h>

#define DRO_MAX_AXES 6
#define DRO_NO_SCROLL(o) lv_obj_remove_flag((o), LV_OBJ_FLAG_SCROLLABLE)

typedef struct {
    lv_obj_t *container;
    lv_obj_t *scroll;
    dro_axis_t axes[DRO_MAX_AXES];
    uint8_t axis_count;
} dro_widget_t;

static dro_widget_t s_dro = {};
static uint8_t s_active_axis = 0xFF;

static void dro_set_active_highlight(uint8_t axis_idx)
{
    if (!s_dro.container || axis_idx == s_active_axis) {
        return;
    }
    s_active_axis = axis_idx;
    for (int i = 0; i < (int)s_dro.axis_count; i++) {
        dro_axis_t *ac = &s_dro.axes[i];
        const bool active = ((uint8_t)i == axis_idx);
        modulus_ui_label_set_text_if_changed(ac->lbl_active, active ? "Active" : "");
        const lv_opa_t border_opa = active ? LV_OPA_COVER : LV_OPA_TRANSP;
        if (lv_obj_get_style_border_opa(ac->card, 0) != border_opa) {
            lv_obj_set_style_border_opa(ac->card, border_opa, 0);
        }
    }
}

static uint8_t dro_axis_count(void)
{
    uint8_t n = modulus_ui_axes_visible_count(modulus_nvs_get_u8("cnc_axes", 1));
    if (n < 1) {
        n = 1;
    }
    if (n > DRO_MAX_AXES) {
        n = DRO_MAX_AXES;
    }
    return n;
}

static void dro_layout_metrics(uint8_t n, int *min_card_h, int *btn_w, int *btn_h)
{
    /* Compact cards when 5–6 axes so more fit before scroll; still scrollable. */
    const bool compact = (n >= 5);
    *min_card_h = compact ? 112 : 128;
    *btn_w = compact ? 80 : 100;
    *btn_h = compact ? 40 : 48;
}

void modulus_ui_dro_apply_config(void)
{
    if (!s_dro.container || !s_dro.scroll) {
        return;
    }
    s_dro.axis_count = dro_axis_count();
    const bool mm = modulus_nvs_get_u8("cnc_unit", 1) != 0;
    int min_card_h = 128;
    int btn_w = 100;
    int btn_h = 48;
    dro_layout_metrics(s_dro.axis_count, &min_card_h, &btn_w, &btn_h);

    /* >4 axes: enable vertical scroll so B/C (and A on 5-axis) stay reachable. */
    if (s_dro.axis_count > 4) {
        lv_obj_add_flag(s_dro.scroll, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_set_scroll_dir(s_dro.scroll, LV_DIR_VER);
        lv_obj_set_scrollbar_mode(s_dro.scroll, LV_SCROLLBAR_MODE_AUTO);
    } else {
        lv_obj_scroll_to_y(s_dro.scroll, 0, LV_ANIM_OFF);
        DRO_NO_SCROLL(s_dro.scroll);
        lv_obj_set_scrollbar_mode(s_dro.scroll, LV_SCROLLBAR_MODE_OFF);
    }

    for (int i = 0; i < DRO_MAX_AXES; i++) {
        dro_axis_t *ac = &s_dro.axes[i];
        if (!ac->card) {
            continue;
        }
        const bool visible = i < (int)s_dro.axis_count;
        if (visible) {
            lv_obj_remove_flag(ac->card, LV_OBJ_FLAG_HIDDEN);
            lv_obj_set_style_min_height(ac->card, min_card_h, 0);
            if (ac->btn_home) {
                lv_obj_set_size(ac->btn_home, btn_w, btn_h);
            }
            if (ac->btn_zero) {
                lv_obj_set_size(ac->btn_zero, btn_w, btn_h);
            }
        } else {
            lv_obj_add_flag(ac->card, LV_OBJ_FLAG_HIDDEN);
        }
        if (ac->lbl_unit) {
            modulus_ui_label_set_text_if_changed(ac->lbl_unit, mm ? "MM" : "IN");
        }
    }
}

static void axis_click_cb(lv_event_t *e)
{
    const uint8_t idx = (uint8_t)(uintptr_t)lv_event_get_user_data(e);
    dro_set_active_highlight(idx);
    modulus_zig_set_active_axis(idx);
}

static void home_axis_apply(void *user)
{
    modulus_zig_cmd_home_axis((uint8_t)(uintptr_t)user);
}

static void home_click_cb(lv_event_t *e)
{
    lv_event_stop_bubbling(e);
    const uint8_t axis = (uint8_t)(uintptr_t)lv_event_get_user_data(e);
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    modulus_ui_cnf_request(MOD_CNF_ACT_HOME, st.state, "Home axis?",
                           "Axis will run a homing cycle.", home_axis_apply,
                           (void *)(uintptr_t)axis);
}

static void zero_click_cb(lv_event_t *e)
{
    lv_event_stop_bubbling(e);
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    modulus_ui_zero_axis_request((uint8_t)(uintptr_t)lv_event_get_user_data(e), st.state);
}

void modulus_ui_dro_create(lv_obj_t *parent)
{
    s_dro.axis_count = dro_axis_count();
    s_dro.container = lv_obj_create(parent);
    lv_obj_remove_style_all(s_dro.container);
    lv_obj_set_size(s_dro.container, lv_pct(100), lv_pct(100));
    lv_obj_set_flex_flow(s_dro.container, LV_FLEX_FLOW_COLUMN);
    DRO_NO_SCROLL(s_dro.container);

    s_dro.scroll = lv_obj_create(s_dro.container);
    lv_obj_remove_style_all(s_dro.scroll);
    lv_obj_set_width(s_dro.scroll, lv_pct(100));
    lv_obj_set_flex_grow(s_dro.scroll, 1);
    lv_obj_set_style_min_height(s_dro.scroll, 0, 0);
    lv_obj_set_flex_flow(s_dro.scroll, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(s_dro.scroll, MOD_UI_SPACE_SM, 0);
    if (s_dro.axis_count > 4) {
        lv_obj_add_flag(s_dro.scroll, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_set_scroll_dir(s_dro.scroll, LV_DIR_VER);
        lv_obj_set_scrollbar_mode(s_dro.scroll, LV_SCROLLBAR_MODE_AUTO);
    } else {
        DRO_NO_SCROLL(s_dro.scroll);
        lv_obj_set_scrollbar_mode(s_dro.scroll, LV_SCROLLBAR_MODE_OFF);
    }

    const bool mm = modulus_nvs_get_u8("cnc_unit", 1) != 0;
    int min_card_h = 128;
    int btn_w = 100;
    int btn_h = 48;
    dro_layout_metrics(s_dro.axis_count, &min_card_h, &btn_w, &btn_h);

    for (int i = 0; i < DRO_MAX_AXES; i++) {
        dro_build_axis_card(s_dro.scroll, &s_dro.axes[i], i, mm, i < (int)s_dro.axis_count,
                            min_card_h, btn_w, btn_h, axis_click_cb, home_click_cb, zero_click_cb);
    }
}

static void dro_recolor_btn_icon(lv_obj_t *btn)
{
    if (!btn) {
        return;
    }
    lv_obj_t *ico = lv_obj_get_child(btn, 0);
    if (ico) {
        modulus_ui_icon_recolor(ico, modulus_ui_color_icon_chrome());
    }
}

void modulus_ui_dro_theme_refresh(void)
{
    if (!s_dro.container) {
        return;
    }
    for (int i = 0; i < (int)s_dro.axis_count; i++) {
        dro_axis_t *ac = &s_dro.axes[i];
        if (!ac->card) {
            continue;
        }
        lv_obj_set_style_bg_color(ac->card, modulus_ui_color_surface_container_low(), 0);
        lv_obj_set_style_border_color(ac->card, modulus_ui_color_primary(), 0);
        if (ac->lbl_axis) {
            lv_obj_set_style_text_color(ac->lbl_axis, modulus_ui_color_on_surface(), 0);
        }
        if (ac->lbl_active) {
            lv_obj_set_style_text_color(ac->lbl_active, modulus_ui_color_primary(), 0);
        }
        if (ac->lbl_work) {
            lv_obj_set_style_text_color(ac->lbl_work, modulus_ui_color_on_surface(), 0);
        }
        if (ac->lbl_unit) {
            lv_obj_set_style_text_color(ac->lbl_unit, modulus_ui_color_on_surface_variant(), 0);
        }
        if (ac->lbl_mach) {
            lv_obj_set_style_text_color(ac->lbl_mach, modulus_ui_color_on_surface_variant(), 0);
        }
        if (ac->btn_home) {
            lv_obj_set_style_bg_color(ac->btn_home, modulus_ui_color_surface_container_high(), 0);
            dro_recolor_btn_icon(ac->btn_home);
        }
        if (ac->btn_zero) {
            lv_obj_set_style_bg_color(ac->btn_zero, modulus_ui_color_surface_container_high(), 0);
            dro_recolor_btn_icon(ac->btn_zero);
        }
    }
}

void modulus_ui_dro_update(const modulus_cnc_status_t *st)
{
    if (!s_dro.container || !st) {
        return;
    }
    /* Cached state — skip LVGL invalidations when the dashboard tick
     * outruns the data source (this is what keeps taskLVGL yielding). */
    static float s_wpos[DRO_MAX_AXES] = {0};
    static float s_mpos[DRO_MAX_AXES] = {0};
    static int8_t s_units_mm = -1;
    static int8_t s_home_ok = -1;
    static int8_t s_zero_ok = -1;

    const float wpos[DRO_MAX_AXES] = {
        st->wpos_x, st->wpos_y, st->wpos_z, st->wpos_a, st->wpos_b, st->wpos_c,
    };
    const float mpos[DRO_MAX_AXES] = {
        st->mpos_x, st->mpos_y, st->mpos_z, st->mpos_a, st->mpos_b, st->mpos_c,
    };
    const bool home_ok = (st->homing_block == 0);
    const bool zero_ok = (st->connected != 0 && st->state != 5);
    const bool units_changed = ((int8_t)st->units_mm != s_units_mm);

    if (st->active_axis != s_active_axis) {
        dro_set_active_highlight(st->active_axis);
    }

    char buf[24];
    const bool masso = (modulus_nvs_get_u8("cnc_proto", 0) == 5); /* SETTINGS_CNC_PROTO_MASSO */
    for (int i = 0; i < (int)s_dro.axis_count; i++) {
        dro_axis_t *ac = &s_dro.axes[i];
        if (masso) {
            if (wpos[i] != s_wpos[i] || mpos[i] != s_mpos[i]) {
                s_wpos[i] = wpos[i];
                s_mpos[i] = mpos[i];
                modulus_ui_label_set_text_if_changed(ac->lbl_work, "---");
                modulus_ui_label_set_text_if_changed(ac->lbl_mach, "M: ---");
            }
        } else {
            if (wpos[i] != s_wpos[i]) {
                s_wpos[i] = wpos[i];
                snprintf(buf, sizeof(buf), "%+.3f", wpos[i]);
                modulus_ui_label_set_text_if_changed(ac->lbl_work, buf);
            }
            if (mpos[i] != s_mpos[i]) {
                s_mpos[i] = mpos[i];
                snprintf(buf, sizeof(buf), "M: %+.3f", mpos[i]);
                modulus_ui_label_set_text_if_changed(ac->lbl_mach, buf);
            }
        }
        if (units_changed) {
            modulus_ui_label_set_text_if_changed(ac->lbl_unit, st->units_mm ? "MM" : "IN");
        }
    }

    if ((int8_t)home_ok != s_home_ok || (int8_t)zero_ok != s_zero_ok) {
        for (int i = 0; i < (int)s_dro.axis_count; i++) {
            dro_set_btn_enabled(s_dro.axes[i].btn_home, home_ok);
            dro_set_btn_enabled(s_dro.axes[i].btn_zero, zero_ok);
        }
        s_home_ok = (int8_t)home_ok;
        s_zero_ok = (int8_t)zero_ok;
    }

    s_units_mm = (int8_t)st->units_mm;
}
