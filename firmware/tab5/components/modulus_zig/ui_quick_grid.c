#include "ui_quick_grid.h"
#include "ui_settings_common.h"
#include "ui_internal.h"
#include "nvs_shim.h"
#include "cnc_cmd_exports.h"

#include <stdio.h>
#include <string.h>

#define QGRID_NO_SCROLL(o) lv_obj_remove_flag((o), LV_OBJ_FLAG_SCROLLABLE)

static void qgrid_disable_scroll(lv_obj_t *obj)
{
    QGRID_NO_SCROLL(obj);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLL_ELASTIC);
    lv_obj_remove_flag(obj, LV_OBJ_FLAG_SCROLL_MOMENTUM);
    lv_obj_set_scrollbar_mode(obj, LV_SCROLLBAR_MODE_OFF);
}

static const uint8_t k_qbtn_defaults[UI_QBTN_MAX_SLOTS] = {0, 2, 3, 4};
static bool s_user_latched[UI_QBTN_USER_SLOTS];
static char s_user_lbl[UI_QBTN_USER_SLOTS][20];

static const char *qbtn_key(int slot)
{
    static const char *const keys[UI_QBTN_MAX_SLOTS] = {"cnc_qbtn0", "cnc_qbtn1", "cnc_qbtn2",
                                                         "cnc_qbtn3"};
    if (slot < 0 || slot >= UI_QBTN_MAX_SLOTS) {
        return keys[0];
    }
    return keys[slot];
}

bool ui_qbtn_is_user(uint8_t assign)
{
    return assign >= UI_QBTN_USER0 && assign <= UI_QBTN_USER3;
}

int ui_qbtn_user_macro_slot(uint8_t assign)
{
    if (!ui_qbtn_is_user(assign)) {
        return -1;
    }
    return (int)(assign - UI_QBTN_USER0);
}

uint8_t ui_qbtn_slot_assign(int slot)
{
    if (slot < 0 || slot >= UI_QBTN_MAX_SLOTS) {
        return UI_QBTN_OFF;
    }
    uint8_t v = modulus_nvs_get_u8(qbtn_key(slot), k_qbtn_defaults[slot]);
    if (v >= UI_QBTN_ASSIGN_COUNT) {
        v = k_qbtn_defaults[slot];
    }
    if (ui_qbtn_is_user(v)) {
        const int mac = ui_qbtn_user_macro_slot(v);
        char name[16], on[64], off[64];
        if (mac < 0 ||
            !settings_macro_slot_load((uint8_t)mac, name, sizeof(name), on, sizeof(on), off,
                                      sizeof(off), NULL)) {
            return UI_QBTN_OFF;
        }
    }
    return v;
}

int ui_qbtn_collect_entries(ui_qbtn_entry_t *out, int max_out)
{
    int count = 0;
    for (int i = 0; i < UI_QBTN_MAX_SLOTS && count < max_out; i++) {
        const uint8_t assign = ui_qbtn_slot_assign(i);
        if (assign == UI_QBTN_OFF) {
            continue;
        }
        out[count].slot = i;
        out[count].assign = assign;
        count++;
    }
    return count;
}

int ui_qbtn_active_count(void)
{
    ui_qbtn_entry_t tmp[UI_QBTN_MAX_SLOTS];
    return ui_qbtn_collect_entries(tmp, UI_QBTN_MAX_SLOTS);
}

void ui_qbtn_assign_label(uint8_t assign, char *buf, size_t buf_len)
{
    if (!buf || buf_len == 0) {
        return;
    }
    buf[0] = '\0';
    if (ui_qbtn_is_user(assign)) {
        const int mac = ui_qbtn_user_macro_slot(assign);
        char name[16], on[64], off[64];
        if (mac >= 0 &&
            settings_macro_slot_load((uint8_t)mac, name, sizeof(name), on, sizeof(on), off,
                                     sizeof(off), NULL)) {
            strncpy(buf, name, buf_len - 1);
            buf[buf_len - 1] = '\0';
            return;
        }
        strncpy(buf, "Custom", buf_len - 1);
        buf[buf_len - 1] = '\0';
        return;
    }
    const char *lit = "---";
    switch (assign) {
    case UI_QBTN_SPINDLE_CW:
        lit = "Spindle CW";
        break;
    case UI_QBTN_SPINDLE_CCW:
        lit = "Spindle CCW";
        break;
    case UI_QBTN_COOLANT:
        lit = "Coolant";
        break;
    case UI_QBTN_FAN:
        lit = "Fan";
        break;
    case UI_QBTN_ZERO_ALL:
        lit = "Zero all";
        break;
    case UI_QBTN_MACRO:
        lit = "Macro (legacy)";
        break;
    case UI_QBTN_MIST:
        lit = "Mist";
        break;
    case UI_QBTN_SINGLE_STEP:
        lit = "Single step";
        break;
    case UI_QBTN_OFF:
        lit = "Off (hidden)";
        break;
    default:
        break;
    }
    strncpy(buf, lit, buf_len - 1);
    buf[buf_len - 1] = '\0';
}

void ui_qbtn_icon_label(uint8_t assign, modulus_ui_icon_id_t *icon_out, const char **text_out)
{
    if (ui_qbtn_is_user(assign)) {
        const int mac = ui_qbtn_user_macro_slot(assign);
        *icon_out = MOD_UI_ICON_SCROLL;
        if (mac >= 0 && mac < UI_QBTN_USER_SLOTS) {
            char name[16], on[64], off[64];
            uint8_t icon = (uint8_t)MOD_UI_ICON_SCROLL;
            if (settings_macro_slot_load((uint8_t)mac, name, sizeof(name), on, sizeof(on), off,
                                         sizeof(off), &icon)) {
                *icon_out = (modulus_ui_icon_id_t)icon;
                /* Button face: short uppercase-ish label */
                snprintf(s_user_lbl[mac], sizeof(s_user_lbl[mac]), "%.12s", name);
                *text_out = s_user_lbl[mac];
                return;
            }
        }
        *text_out = "Custom";
        return;
    }
    switch (assign) {
    case UI_QBTN_SPINDLE_CW:
        *icon_out = MOD_UI_ICON_SPINDLE;
        *text_out = "SPINDLE\nCW";
        break;
    case UI_QBTN_SPINDLE_CCW:
        *icon_out = MOD_UI_ICON_SPINDLE_CCW;
        *text_out = "SPINDLE\nCCW";
        break;
    case UI_QBTN_COOLANT:
        *icon_out = MOD_UI_ICON_COOLANT;
        *text_out = "Coolant";
        break;
    case UI_QBTN_FAN:
        *icon_out = MOD_UI_ICON_FAN;
        *text_out = "Fan";
        break;
    case UI_QBTN_ZERO_ALL:
        *icon_out = MOD_UI_ICON_CROSSHAIR;
        *text_out = "ZERO\nALL";
        break;
    case UI_QBTN_MACRO:
        *icon_out = MOD_UI_ICON_SCROLL;
        *text_out = "Macro";
        break;
    case UI_QBTN_MIST:
        *icon_out = MOD_UI_ICON_CLOUD_FOG;
        *text_out = "Mist";
        break;
    case UI_QBTN_SINGLE_STEP:
        *icon_out = MOD_UI_ICON_SINGLE_STEP;
        *text_out = "Step";
        break;
    default:
        *icon_out = MOD_UI_ICON_CNC;
        *text_out = "---";
        break;
    }
}

bool ui_qbtn_fire_user(uint8_t assign)
{
    const int mac = ui_qbtn_user_macro_slot(assign);
    if (mac < 0 || mac >= UI_QBTN_USER_SLOTS) {
        return false;
    }
    char name[16], on[64], off[64];
    if (!settings_macro_slot_load((uint8_t)mac, name, sizeof(name), on, sizeof(on), off,
                                  sizeof(off), NULL)) {
        return false;
    }
    const char *cmd = on;
    if (off[0] != '\0') {
        s_user_latched[mac] = !s_user_latched[mac];
        cmd = s_user_latched[mac] ? on : off;
    }
    if (cmd[0] == '\0') {
        return false;
    }
    modulus_zig_cmd_send_gcode((const uint8_t *)cmd, strlen(cmd));
    return true;
}

bool ui_qbtn_user_latched(uint8_t assign)
{
    const int mac = ui_qbtn_user_macro_slot(assign);
    if (mac < 0 || mac >= UI_QBTN_USER_SLOTS) {
        return false;
    }
    return s_user_latched[mac];
}

static void populate_cell(lv_obj_t *parent, uint8_t assign, int slot, int32_t w, int32_t cell_h,
                          ui_qbtn_build_opts_t *opts)
{
    modulus_ui_icon_id_t icon_id = MOD_UI_ICON_CNC;
    const char *label = "---";
    ui_qbtn_icon_label(assign, &icon_id, &label);

    lv_obj_t *btn = lv_obj_create(parent);
    lv_obj_remove_style_all(btn);
    qgrid_disable_scroll(btn);
    lv_obj_set_width(btn, w);
    if (cell_h > 0) {
        lv_obj_set_height(btn, cell_h);
    } else {
        lv_obj_set_height(btn, lv_pct(100));
        if (w == lv_pct(50) || w == lv_pct(100)) {
            lv_obj_set_flex_grow(btn, 1);
        }
    }
    lv_obj_set_style_bg_color(btn, modulus_ui_color_surface_container_high(), 0);
    lv_obj_set_style_bg_opa(btn, LV_OPA_COVER, 0);
    /* Full pill clips when job strip shrinks the column — use LG radius when compact. */
    const bool compact = modulus_ui_job_progress_visible();
    lv_obj_set_style_radius(btn, compact ? MOD_UI_SHAPE_LG : MOD_UI_SHAPE_XL, 0);
    lv_obj_set_style_clip_corner(btn, true, 0);
    lv_obj_set_flex_flow(btn, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(btn, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_all(btn, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_pad_row(btn, MOD_UI_SPACE_XS, 0);

    if (opts->interactive && opts->click_cb) {
        lv_obj_add_flag(btn, LV_OBJ_FLAG_CLICKABLE);
        modulus_ui_apply_pressed_state_layer(btn);
        lv_obj_add_event_cb(btn, opts->click_cb, LV_EVENT_CLICKED, (void *)(intptr_t)assign);
    }

    lv_obj_t *icon = modulus_ui_icon_create(btn, icon_id, MOD_UI_ICON_SZ_24);
    modulus_ui_icon_recolor(icon, modulus_ui_color_icon_chrome());
    lv_obj_t *lbl = lv_label_create(btn);
    lv_label_set_text(lbl, label);
    lv_obj_set_style_text_color(lbl, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(lbl, MOD_UI_FONT_BODY_M, 0);
    lv_obj_set_style_text_align(lbl, LV_TEXT_ALIGN_CENTER, 0);

    if (slot >= 0 && slot < UI_QBTN_MAX_SLOTS) {
        opts->btn_by_slot[slot] = btn;
        opts->lbl_by_slot[slot] = lbl;
        opts->icon_by_slot[slot] = icon;
    }
}

void ui_qbtn_build_grid(lv_obj_t *container, const ui_qbtn_entry_t *entries, int active_count,
                        ui_qbtn_build_opts_t *opts)
{
    if (!container || active_count <= 0 || !opts) {
        return;
    }

    const int32_t fixed_h = opts->container_h;
    lv_obj_clean(container);
    lv_obj_remove_style_all(container);
    lv_obj_set_width(container, lv_pct(100));
    if (fixed_h > 0) {
        lv_obj_set_height(container, fixed_h);
        lv_obj_set_flex_grow(container, 0);
    } else {
        lv_obj_set_flex_grow(container, 1);
    }
    qgrid_disable_scroll(container);

    const int32_t half_w = lv_pct(50);
    const int32_t full_w = lv_pct(100);
    const int32_t panel_w = opts->panel_w > 0 ? opts->panel_w : 280;
    const int32_t grid_cell_w = (panel_w - 8) / 2;
    /* Preview: explicit px heights. Live dashboard: 0 => lv_pct(100). */
    const int32_t row_h = fixed_h > 0 ? (fixed_h - 16) : 0;
    const int32_t half_row_h = fixed_h > 0 ? (row_h - 8) / 2 : 0;
    const int32_t wrap_h = fixed_h > 0 ? (row_h - 8) / 2
                                       : (modulus_ui_job_progress_visible() ? 64 : 80);

    if (active_count == 1) {
        lv_obj_set_flex_flow(container, LV_FLEX_FLOW_COLUMN);
        populate_cell(container, entries[0].assign, entries[0].slot, full_w, row_h, opts);
        return;
    }
    if (active_count == 2) {
        lv_obj_set_flex_flow(container, LV_FLEX_FLOW_ROW);
        lv_obj_set_style_pad_column(container, MOD_UI_SPACE_SM, 0);
        for (int i = 0; i < 2; i++) {
            populate_cell(container, entries[i].assign, entries[i].slot, half_w, row_h, opts);
        }
        return;
    }
    if (active_count == 3) {
        lv_obj_set_flex_flow(container, LV_FLEX_FLOW_ROW);
        lv_obj_set_style_pad_column(container, MOD_UI_SPACE_SM, 0);
        populate_cell(container, entries[0].assign, entries[0].slot, half_w, row_h, opts);
        lv_obj_t *right = lv_obj_create(container);
        lv_obj_remove_style_all(right);
        qgrid_disable_scroll(right);
        lv_obj_set_width(right, half_w);
        if (fixed_h > 0) {
            lv_obj_set_height(right, row_h);
        } else {
            lv_obj_set_height(right, lv_pct(100));
            lv_obj_set_flex_grow(right, 1);
        }
        lv_obj_set_flex_flow(right, LV_FLEX_FLOW_COLUMN);
        lv_obj_set_style_pad_row(right, MOD_UI_SPACE_SM, 0);
        populate_cell(right, entries[1].assign, entries[1].slot, full_w, half_row_h, opts);
        populate_cell(right, entries[2].assign, entries[2].slot, full_w, half_row_h, opts);
        return;
    }

    lv_obj_set_flex_flow(container, LV_FLEX_FLOW_ROW_WRAP);
    lv_obj_set_flex_align(container, LV_FLEX_ALIGN_SPACE_EVENLY, LV_FLEX_ALIGN_CENTER,
                          LV_FLEX_ALIGN_SPACE_EVENLY);
    lv_obj_set_style_pad_column(container, MOD_UI_SPACE_SM, 0);
    lv_obj_set_style_pad_row(container, MOD_UI_SPACE_SM, 0);
    for (int i = 0; i < active_count; i++) {
        populate_cell(container, entries[i].assign, entries[i].slot, grid_cell_w, wrap_h, opts);
    }
}

void ui_qbtn_build_preview(lv_obj_t *container, int32_t height)
{
    if (!container) {
        return;
    }

    ui_qbtn_entry_t entries[UI_QBTN_MAX_SLOTS];
    const int active = ui_qbtn_collect_entries(entries, UI_QBTN_MAX_SLOTS);

    lv_obj_clean(container);
    lv_obj_remove_style_all(container);
    lv_obj_set_width(container, lv_pct(100));
    lv_obj_set_height(container, height);
    lv_obj_set_style_bg_color(container, modulus_ui_color_surface_container_low(), 0);
    lv_obj_set_style_bg_opa(container, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(container, MOD_UI_SHAPE_MD, 0);
    lv_obj_set_style_pad_all(container, MOD_UI_SPACE_SM, 0);
    qgrid_disable_scroll(container);

    if (active == 0) {
        lv_obj_t *lbl = lv_label_create(container);
        lv_label_set_text(lbl, "No buttons (all slots Off)");
        lv_obj_set_style_text_color(lbl, modulus_ui_color_on_surface_variant(), 0);
        lv_obj_center(lbl);
        return;
    }

    ui_qbtn_build_opts_t opts = {
        .interactive = false,
        .click_cb = NULL,
        .panel_w = 480,
        .container_h = height,
    };
    ui_qbtn_build_grid(container, entries, active, &opts);
    /* build_grid wipe styles — restore chrome + height so preview is not a sliver. */
    lv_obj_set_width(container, lv_pct(100));
    lv_obj_set_height(container, height);
    lv_obj_set_style_bg_color(container, modulus_ui_color_surface_container_low(), 0);
    lv_obj_set_style_bg_opa(container, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(container, MOD_UI_SHAPE_MD, 0);
    lv_obj_set_style_pad_all(container, MOD_UI_SPACE_SM, 0);
}
