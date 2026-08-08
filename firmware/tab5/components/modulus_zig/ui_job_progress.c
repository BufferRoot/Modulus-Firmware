#include "ui_job_progress.h"
#include "ui_internal.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

enum {
    k_state_run = 2,
    k_state_hold = 3,
    k_strip_h = 60,
    k_wave_h = 20,
    k_wave_amp = 4,
    k_wave_len = 36,
    k_track_h = 4,
    k_stop_r = 5,
    k_indet_seg = 28, /* % of track width for indeterminate segment */
};

static lv_obj_t *s_strip = NULL;
static lv_obj_t *s_name = NULL;
static lv_obj_t *s_pct_chip = NULL;
static lv_obj_t *s_pct = NULL;
static lv_obj_t *s_time = NULL;
static lv_obj_t *s_wave = NULL;
static lv_timer_t *s_wave_tmr = NULL;
static uint32_t s_t0_ms = 0;
static float s_pct_at_t0 = 0.f;
static uint8_t s_was_active = 0;
static float s_progress = 0.f; /* 0..1 determinate; <0 indeterminate */
static float s_phase = 0.f;
static uint8_t s_visible = 0;
static uint8_t s_hold = 0;

static lv_color_t indicator_color(void)
{
    return s_hold ? modulus_ui_color_hold() : modulus_ui_color_primary();
}

static lv_color_t indicator_container_color(void)
{
    return s_hold ? modulus_ui_color_tertiary_container() : modulus_ui_color_primary_container();
}

static lv_color_t on_indicator_container_color(void)
{
    return s_hold ? modulus_ui_color_on_tertiary_container() : modulus_ui_color_on_primary_container();
}

static void apply_pct_chip_theme(void)
{
    if (!s_pct_chip || !s_pct) {
        return;
    }
    lv_obj_set_style_bg_color(s_pct_chip, indicator_container_color(), 0);
    lv_obj_set_style_text_color(s_pct, on_indicator_container_color(), 0);
}

static void fmt_mmss(char *out, size_t n, uint32_t sec)
{
    const uint32_t m = sec / 60;
    const uint32_t s = sec % 60;
    snprintf(out, n, "%lu:%02lu", (unsigned long)m, (unsigned long)s);
}

static void wave_draw_cb(lv_event_t *e)
{
    if (lv_event_get_code(e) != LV_EVENT_DRAW_MAIN) {
        return;
    }
    lv_obj_t *obj = lv_event_get_target(e);
    lv_layer_t *layer = lv_event_get_layer(e);
    if (!obj || !layer) {
        return;
    }

    lv_area_t coords;
    lv_obj_get_coords(obj, &coords);
    const int32_t w = lv_area_get_width(&coords);
    const int32_t h = lv_area_get_height(&coords);
    if (w < 16 || h < 8) {
        return;
    }

    const int32_t mid_y = (coords.y1 + coords.y2) / 2;
    const int32_t track_y1 = mid_y - k_track_h / 2;
    const int32_t track_y2 = track_y1 + k_track_h - 1;
    const lv_color_t track_c = modulus_ui_color_surface_container_highest();
    const lv_color_t ind_c = indicator_color();
    const lv_color_t fill_c = indicator_container_color();

    /* MD3 track — full-width tonal pill (shape: full). */
    {
        lv_draw_rect_dsc_t track;
        lv_draw_rect_dsc_init(&track);
        track.bg_color = track_c;
        track.bg_opa = LV_OPA_COVER;
        track.radius = LV_RADIUS_CIRCLE;
        lv_area_t a = {
            .x1 = coords.x1,
            .y1 = track_y1,
            .x2 = coords.x2,
            .y2 = track_y2,
        };
        lv_draw_rect(layer, &track, &a);
    }

    const bool indet = s_progress < 0.f;
    int32_t seg_x1;
    int32_t seg_x2;
    if (indet) {
        /* Sliding segment (~28% width) for indeterminate linear progress. */
        const int32_t seg_w = (w * k_indet_seg) / 100;
        const float travel = 1.f + (float)seg_w / (float)w;
        float t = s_phase * 0.12f;
        t -= (float)(int)(t / travel) * travel;
        if (t < 0.f) {
            t += travel;
        }
        seg_x1 = coords.x1 + (int32_t)((t - (float)seg_w / (float)w) * (float)w);
        seg_x2 = seg_x1 + seg_w;
        if (seg_x1 < coords.x1) {
            seg_x1 = coords.x1;
        }
        if (seg_x2 > coords.x2) {
            seg_x2 = coords.x2;
        }
    } else {
        float prog = s_progress;
        if (prog > 1.f) {
            prog = 1.f;
        }
        if (prog < 0.f) {
            prog = 0.f;
        }
        seg_x1 = coords.x1;
        seg_x2 = coords.x1 + (int32_t)((float)w * prog);
        /* MD3 gap before track end while incomplete. */
        if (prog > 0.02f && prog < 0.98f && seg_x2 > coords.x1 + 8) {
            seg_x2 -= 2;
        }
    }

    if (seg_x2 <= seg_x1 + 2) {
        return;
    }

    /* Tonal active underlay (primary/tertiary container) — depth without shadow. */
    {
        lv_draw_rect_dsc_t fill;
        lv_draw_rect_dsc_init(&fill);
        fill.bg_color = fill_c;
        fill.bg_opa = LV_OPA_70;
        fill.radius = LV_RADIUS_CIRCLE;
        lv_area_t a = {
            .x1 = seg_x1,
            .y1 = track_y1 - 1,
            .x2 = seg_x2,
            .y2 = track_y2 + 1,
        };
        lv_draw_rect(layer, &fill, &a);
    }

    /* Expressive wavy active indicator along the filled span. */
    lv_draw_line_dsc_t wave_dsc;
    lv_draw_line_dsc_init(&wave_dsc);
    wave_dsc.color = ind_c;
    wave_dsc.opa = LV_OPA_COVER;
    wave_dsc.width = 3;
    wave_dsc.round_start = 1;
    wave_dsc.round_end = 1;

    const float amp = (float)k_wave_amp;
    const float wl = (float)k_wave_len;
    int32_t prev_x = seg_x1;
    int32_t prev_y = mid_y;
    for (int32_t x = seg_x1 + 2; x <= seg_x2; x += 2) {
        const float t = (float)(x - coords.x1) / wl + s_phase;
        const int32_t y = mid_y + (int32_t)(sinf(t * 2.f * (float)M_PI) * amp);
        wave_dsc.p1.x = prev_x;
        wave_dsc.p1.y = prev_y;
        wave_dsc.p2.x = x;
        wave_dsc.p2.y = y;
        lv_draw_line(layer, &wave_dsc);
        prev_x = x;
        prev_y = y;
    }

    /* Stop indicator — filled disc + outline ring (MD3 linear end cue). */
    if (!indet && seg_x2 > coords.x1 + 4) {
        const int32_t cx = seg_x2;
        const int32_t cy = mid_y;
        {
            lv_draw_rect_dsc_t ring;
            lv_draw_rect_dsc_init(&ring);
            ring.bg_color = modulus_ui_color_surface_container_highest();
            ring.bg_opa = LV_OPA_COVER;
            ring.radius = LV_RADIUS_CIRCLE;
            lv_area_t a = {
                .x1 = cx - k_stop_r - 2,
                .y1 = cy - k_stop_r - 2,
                .x2 = cx + k_stop_r + 2,
                .y2 = cy + k_stop_r + 2,
            };
            lv_draw_rect(layer, &ring, &a);
        }
        {
            lv_draw_rect_dsc_t stop;
            lv_draw_rect_dsc_init(&stop);
            stop.bg_color = ind_c;
            stop.bg_opa = LV_OPA_COVER;
            stop.radius = LV_RADIUS_CIRCLE;
            lv_area_t a = {
                .x1 = cx - k_stop_r,
                .y1 = cy - k_stop_r,
                .x2 = cx + k_stop_r,
                .y2 = cy + k_stop_r,
            };
            lv_draw_rect(layer, &stop, &a);
        }
    }
}

static void wave_tick(lv_timer_t *t)
{
    (void)t;
    if (!s_wave || !s_was_active) {
        return;
    }
    /* Animate only indeterminate — determinate fill already tracks %; avoid
     * continuous full-width redraw on Core 0 during long jobs (WDT risk). */
    if (s_progress < 0.f) {
        s_phase += 0.10f;
        if (s_phase > 100.f) {
            s_phase -= 100.f;
        }
        lv_obj_invalidate(s_wave);
    }
}

static void set_progress(float pct, bool determinate)
{
    float next;
    if (determinate) {
        float p = pct;
        if (p < 0.f) {
            p = 0.f;
        }
        if (p > 100.f) {
            p = 100.f;
        }
        next = p / 100.f;
    } else {
        next = -1.f;
    }
    if (next == s_progress) {
        return;
    }
    s_progress = next;
    if (s_wave) {
        lv_obj_invalidate(s_wave);
    }
}

bool modulus_ui_job_progress_visible(void)
{
    return s_visible != 0;
}

void modulus_ui_job_progress_create(lv_obj_t *parent)
{
    if (s_strip || !parent) {
        return;
    }

    s_strip = lv_obj_create(parent);
    lv_obj_remove_style_all(s_strip);
    lv_obj_set_width(s_strip, lv_pct(100));
    lv_obj_set_height(s_strip, k_strip_h);
    /* Tonal surface + top outline — elevation via tone, not shadow. */
    lv_obj_set_style_bg_color(s_strip, modulus_ui_color_surface_container_low(), 0);
    lv_obj_set_style_bg_opa(s_strip, LV_OPA_COVER, 0);
    lv_obj_set_style_border_side(s_strip, LV_BORDER_SIDE_TOP, 0);
    lv_obj_set_style_border_width(s_strip, 1, 0);
    lv_obj_set_style_border_color(s_strip, modulus_ui_color_outline_variant(), 0);
    lv_obj_set_style_pad_hor(s_strip, MOD_UI_SPACE_MD, 0);
    lv_obj_set_style_pad_ver(s_strip, MOD_UI_SPACE_SM, 0);
    lv_obj_set_flex_flow(s_strip, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(s_strip, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_row(s_strip, MOD_UI_SPACE_XS, 0);
    lv_obj_remove_flag(s_strip, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(s_strip, LV_OBJ_FLAG_HIDDEN);

    lv_obj_t *row = lv_obj_create(s_strip);
    lv_obj_remove_style_all(row);
    lv_obj_set_width(row, lv_pct(100));
    lv_obj_set_height(row, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(row, LV_FLEX_ALIGN_SPACE_BETWEEN, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(row, MOD_UI_SPACE_SM, 0);

    s_name = lv_label_create(row);
    lv_obj_set_style_text_font(s_name, MOD_UI_FONT_LABEL_L, 0);
    lv_obj_set_style_text_color(s_name, modulus_ui_color_on_surface(), 0);
    lv_label_set_long_mode(s_name, LV_LABEL_LONG_CLIP);
    lv_obj_set_flex_grow(s_name, 1);
    lv_label_set_text(s_name, "");

    lv_obj_t *right = lv_obj_create(row);
    lv_obj_remove_style_all(right);
    lv_obj_set_size(right, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_set_flex_flow(right, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(right, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_column(right, MOD_UI_SPACE_SM, 0);

    /* Percent / line as MD3 tonal assist chip. */
    s_pct_chip = lv_obj_create(right);
    lv_obj_remove_style_all(s_pct_chip);
    lv_obj_set_height(s_pct_chip, 28);
    lv_obj_set_width(s_pct_chip, LV_SIZE_CONTENT);
    lv_obj_set_style_bg_opa(s_pct_chip, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(s_pct_chip, MOD_UI_SHAPE_FULL, 0);
    lv_obj_set_style_pad_hor(s_pct_chip, MOD_UI_SPACE_SM + MOD_UI_SPACE_XS, 0);
    lv_obj_set_style_pad_ver(s_pct_chip, MOD_UI_SPACE_XS, 0);
    lv_obj_set_flex_flow(s_pct_chip, LV_FLEX_FLOW_ROW);
    lv_obj_set_flex_align(s_pct_chip, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_remove_flag(s_pct_chip, LV_OBJ_FLAG_SCROLLABLE);

    s_pct = lv_label_create(s_pct_chip);
    lv_obj_set_style_text_font(s_pct, MOD_UI_FONT_LABEL_L, 0);
    lv_label_set_text(s_pct, "");
    apply_pct_chip_theme();

    s_time = lv_label_create(right);
    lv_obj_set_style_text_font(s_time, MOD_UI_FONT_BODY_M, 0);
    lv_obj_set_style_text_color(s_time, modulus_ui_color_on_surface_variant(), 0);
    lv_label_set_text(s_time, "");

    s_wave = lv_obj_create(s_strip);
    lv_obj_remove_style_all(s_wave);
    lv_obj_set_width(s_wave, lv_pct(100));
    lv_obj_set_height(s_wave, k_wave_h);
    lv_obj_set_style_bg_opa(s_wave, LV_OPA_TRANSP, 0);
    lv_obj_remove_flag(s_wave, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(s_wave, LV_OBJ_FLAG_OVERFLOW_VISIBLE);
    lv_obj_add_event_cb(s_wave, wave_draw_cb, LV_EVENT_DRAW_MAIN, NULL);
}

void modulus_ui_job_progress_update(const modulus_cnc_status_t *st)
{
    if (!s_strip || !st) {
        return;
    }

    const bool streaming = st->sd_streaming != 0;
    const bool running = (st->state == k_state_run) || (st->state == k_state_hold);
    const bool has_pct = st->sd_percent > 0.05f;
    const bool has_line = st->line_number != 0;
    /* Sender-streamed jobs (external gcode sender over its own link) carry no
     * |SD: element — no %, filename, or total. Show the strip anyway with
     * elapsed + line number; %/ETA/filename genuinely don't exist on the wire
     * for those jobs (they live in the sender), not a parsing gap. */
    const bool active = streaming || running;
    const uint8_t hold = (st->state == k_state_hold) ? 1 : 0;

    if (!active) {
        if (s_was_active) {
            lv_obj_add_flag(s_strip, LV_OBJ_FLAG_HIDDEN);
            if (s_wave_tmr) {
                lv_timer_delete(s_wave_tmr);
                s_wave_tmr = NULL;
            }
            /* Dashboard hide path — job-complete cue also runs from zb_auto_poll. */
            s_was_active = 0;
            s_visible = 0;
            s_t0_ms = 0;
            s_hold = 0;
            modulus_ui_actions_rebuild();
        }
        return;
    }

    if (!s_was_active) {
        lv_obj_remove_flag(s_strip, LV_OBJ_FLAG_HIDDEN);
        s_was_active = 1;
        s_visible = 1;
        s_t0_ms = lv_tick_get();
        s_pct_at_t0 = st->sd_percent;
        if (!s_wave_tmr) {
            s_wave_tmr = lv_timer_create(wave_tick, 40, NULL);
        }
        modulus_ui_actions_rebuild();
    }

    if (hold != s_hold) {
        s_hold = hold;
        apply_pct_chip_theme();
        if (s_wave) {
            lv_obj_invalidate(s_wave);
        }
    }

    static char s_name_cache[40];
    static char s_pct_cache[24];
    static char s_time_cache[40];

    const char *file = st->sd_file[0] ? st->sd_file
                     : (streaming || has_pct ? "SD job" : "External job");
    if (strcmp(s_name_cache, file) != 0) {
        snprintf(s_name_cache, sizeof(s_name_cache), "%s", file);
        modulus_ui_label_set_text_if_changed(s_name, s_name_cache);
    }

    char pct_buf[24];
    if (has_pct) {
        if (hold) {
            snprintf(pct_buf, sizeof(pct_buf), "HOLD %.0f%%", (double)st->sd_percent);
        } else {
            snprintf(pct_buf, sizeof(pct_buf), "%.0f%%", (double)st->sd_percent);
        }
        set_progress(st->sd_percent, true);
    } else {
        if (hold) {
            snprintf(pct_buf, sizeof(pct_buf), "Hold");
        } else if (has_line) {
            snprintf(pct_buf, sizeof(pct_buf), "Ln %lu", (unsigned long)st->line_number);
        } else {
            snprintf(pct_buf, sizeof(pct_buf), "...");
        }
        set_progress(0.f, false);
    }
    if (strcmp(s_pct_cache, pct_buf) != 0) {
        snprintf(s_pct_cache, sizeof(s_pct_cache), "%s", pct_buf);
        modulus_ui_label_set_text_if_changed(s_pct, s_pct_cache);
    }

    const uint32_t elapsed_s = lv_tick_elaps(s_t0_ms) / 1000;
    char el_buf[16];
    char eta_buf[16];
    fmt_mmss(el_buf, sizeof(el_buf), elapsed_s);

    char time_buf[40];
    if (has_pct && st->sd_percent > 1.f && st->sd_percent < 99.5f) {
        const float gained = st->sd_percent - s_pct_at_t0;
        if (gained > 0.5f && elapsed_s > 2) {
            const float rem = 100.f - st->sd_percent;
            const uint32_t eta_s = (uint32_t)((rem / gained) * (float)elapsed_s);
            fmt_mmss(eta_buf, sizeof(eta_buf), eta_s);
            snprintf(time_buf, sizeof(time_buf), "%s · ETA %s", el_buf, eta_buf);
        } else {
            snprintf(time_buf, sizeof(time_buf), "%s", el_buf);
        }
    } else {
        snprintf(time_buf, sizeof(time_buf), "%s", el_buf);
    }
    if (strcmp(s_time_cache, time_buf) != 0) {
        snprintf(s_time_cache, sizeof(s_time_cache), "%s", time_buf);
        modulus_ui_label_set_text_if_changed(s_time, s_time_cache);
    }
}

void modulus_ui_job_progress_theme_refresh(void)
{
    if (!s_strip) {
        return;
    }
    lv_obj_set_style_bg_color(s_strip, modulus_ui_color_surface_container_low(), 0);
    lv_obj_set_style_border_color(s_strip, modulus_ui_color_outline_variant(), 0);
    if (s_name) {
        lv_obj_set_style_text_color(s_name, modulus_ui_color_on_surface(), 0);
    }
    apply_pct_chip_theme();
    if (s_time) {
        lv_obj_set_style_text_color(s_time, modulus_ui_color_on_surface_variant(), 0);
    }
    if (s_wave) {
        lv_obj_invalidate(s_wave);
    }
}

void modulus_ui_job_progress_pause_wave(void)
{
    if (s_wave_tmr) {
        lv_timer_pause(s_wave_tmr);
    }
}

void modulus_ui_job_progress_resume_wave(void)
{
    if (s_wave_tmr && s_was_active) {
        lv_timer_resume(s_wave_tmr);
    }
}
