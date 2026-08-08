#include "ui_internal.h"
#include "nvs_shim.h"
#include "cnc_cmd_exports.h"

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    lv_obj_t *card;
    lv_obj_t *mode_seg;
    lv_obj_t *inc_group;
    lv_obj_t *inc_val[4];
} jog_widget_t;

static jog_widget_t s_jog = {};
static uint8_t s_jog_cached_mode = 0xFF;
static uint8_t s_jog_cached_step = 0xFF;
static const float k_def_inc[4] = {0.001f, 0.01f, 0.1f, 1.0f};
static const char *const k_mult_lbl[4] = {"x1", "x10", "x100", "x1000"};

#define JOG_NO_SCROLL(o) lv_obj_remove_flag((o), LV_OBJ_FLAG_SCROLLABLE)

static void load_increments(float out[4])
{
    char buf[64];
    if (!modulus_nvs_get_str("cnc_incr", buf, sizeof(buf))) {
        strncpy(buf, "0.001,0.01,0.1,1.0", sizeof(buf) - 1);
    }
    int n = 0;
    char *ctx = NULL;
    for (char *t = strtok_r(buf, ",", &ctx); t && n < 4; t = strtok_r(NULL, ",", &ctx)) {
        float v = strtof(t, NULL);
        out[n] = (v > 0.0f) ? v : k_def_inc[n];
        n++;
    }
    while (n < 4) {
        out[n] = k_def_inc[n];
        n++;
    }
}

static void format_inc(float val, char *buf, size_t len)
{
    if (val >= 1.0f) {
        snprintf(buf, len, "%.0f", val);
    } else if (val >= 0.01f) {
        snprintf(buf, len, "%.2f", val);
    } else {
        snprintf(buf, len, "%.3f", val);
    }
}

static void mode_seg_cb(lv_event_t *e)
{
    lv_obj_t *btn = lv_event_get_target(e);
    lv_obj_t *track = lv_obj_get_parent(btn);
    modulus_zig_set_jog_mode(modulus_ui_segmented_get_selected(track));
}

static void inc_chip_cb(lv_event_t *e)
{
    lv_obj_t *btn = lv_event_get_target(e);
    modulus_zig_set_step_size((uint8_t)(uintptr_t)lv_obj_get_user_data(btn));
}

void modulus_ui_jog_create(lv_obj_t *parent)
{
    lv_obj_t *card = lv_obj_create(parent);
    s_jog.card = card;
    JOG_NO_SCROLL(card);
    lv_obj_set_style_bg_color(card, modulus_ui_color_surface_container_low(), 0);
    lv_obj_set_style_radius(card, MOD_UI_SHAPE_CARD, 0);
    lv_obj_set_style_border_width(card, 0, 0);
    lv_obj_set_style_pad_all(card, MOD_UI_SPACE_LG, 0);
    lv_obj_set_width(card, lv_pct(100));
    lv_obj_set_height(card, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(card, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(card, MOD_UI_SPACE_MD, 0);

    lv_obj_t *hdr = modulus_ui_flex_row_create(card, 36, true);
    lv_obj_t *title = lv_label_create(hdr);
    lv_label_set_text(title, "Jog mode & increment");
    lv_obj_set_style_text_color(title, modulus_ui_color_on_surface_variant(), 0);
    lv_obj_set_style_text_font(title, MOD_UI_FONT_BODY_M, 0);

    static const char *const k_mode_lbl[] = {"Step", "Cont", "Velo"};
    s_jog.mode_seg = modulus_ui_segmented_create(hdr, k_mode_lbl, 3, 76, mode_seg_cb, NULL);

    s_jog.inc_group = modulus_ui_filter_chip_group_create(card, 72, inc_chip_cb);
    float inc[4];
    load_increments(inc);
    for (int i = 0; i < 4; i++) {
        char buf[12];
        format_inc(inc[i], buf, sizeof(buf));
        lv_obj_t *chip = modulus_ui_filter_chip_add_stacked(s_jog.inc_group, buf, k_mult_lbl[i],
                                                            (void *)(uintptr_t)i);
        if (chip) {
            s_jog.inc_val[i] = lv_obj_get_child(chip, 0);
        }
    }

    const uint8_t saved_jmode = modulus_nvs_get_u8("cnc_jmode", 0);
    const uint8_t jmode = saved_jmode <= 2 ? saved_jmode : 0;
    modulus_zig_set_jog_mode(jmode);
    modulus_ui_segmented_set_selected(s_jog.mode_seg, jmode);
    s_jog_cached_mode = jmode;
}

void modulus_ui_jog_theme_refresh(void)
{
    if (!s_jog.card) {
        return;
    }
    lv_obj_t *hdr = lv_obj_get_child(s_jog.card, 0);
    if (hdr) {
        lv_obj_t *title = lv_obj_get_child(hdr, 0);
        if (title) {
            lv_obj_set_style_text_color(title, modulus_ui_color_on_surface_variant(), 0);
        }
    }
    if (s_jog.mode_seg) {
        lv_obj_set_style_bg_color(s_jog.mode_seg, modulus_ui_color_surface_container_high(), 0);
        modulus_ui_segmented_set_selected(s_jog.mode_seg, s_jog_cached_mode == 0xFF ? 0 : s_jog_cached_mode);
    }
    lv_obj_set_style_bg_color(s_jog.card, modulus_ui_color_surface_container_low(), 0);
    if (s_jog.inc_group) {
        modulus_ui_filter_chip_set_selected(s_jog.inc_group,
                                            s_jog_cached_step == 0xFF ? 0 : s_jog_cached_step);
    }
}

void modulus_ui_jog_apply_config(void)
{
    if (!s_jog.inc_group) {
        return;
    }
    float inc[4];
    load_increments(inc);
    for (int i = 0; i < 4; i++) {
        if (!s_jog.inc_val[i]) {
            continue;
        }
        char buf[12];
        format_inc(inc[i], buf, sizeof(buf));
        modulus_ui_label_set_text_if_changed(s_jog.inc_val[i], buf);
    }
}

void modulus_ui_jog_invalidate(void)
{
    s_jog_cached_mode = 0xFF;
    s_jog_cached_step = 0xFF;
}

void modulus_ui_jog_update(const modulus_cnc_status_t *st)
{
    if (!st || !s_jog.mode_seg) {
        return;
    }
    if (st->jog_mode == s_jog_cached_mode && st->step_size == s_jog_cached_step) {
        return;
    }
    s_jog_cached_mode = st->jog_mode;
    s_jog_cached_step = st->step_size;

    modulus_ui_segmented_set_selected(s_jog.mode_seg, st->jog_mode <= 2 ? st->jog_mode : 0);
    if (s_jog.inc_group) {
        modulus_ui_filter_chip_set_selected(s_jog.inc_group, st->step_size);
    }
}
