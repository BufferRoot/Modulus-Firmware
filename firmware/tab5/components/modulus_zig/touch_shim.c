/*
 * Tab5 touch HAL — glove-friendly contact threshold on BSP LVGL indev.
 * Port of C++ hal_touch.cpp (ST7123/GT911 strength filter + I2C coex).
 */
#include "touch_shim.h"
#include "i2c_coex_shim.h"
#include "nvs_shim.h"

#include <bsp/m5stack_tab5.h>
#include <bsp/touch.h>
#include <esp_lcd_touch.h>
#include <esp_log.h>
#include <esp_timer.h>
#if !CONFIG_MODULUS_ZIG_UI_ENGINE
#include <lvgl.h>
#endif
#include <stdint.h>

static const char *TAG = "modulus_touch";

#if !CONFIG_MODULUS_ZIG_UI_ENGINE
/* Prefix of esp_lvgl_port's private lvgl_port_touch_ctx_t. Only the LVGL
 * build still needs it; under ZIG_UI we own the handle from bsp_touch_new(). */
typedef struct {
    esp_lcd_touch_handle_t handle;
    lv_indev_t *indev;
    struct {
        float x;
        float y;
    } scale;
} touch_port_ctx_t;

static bool s_tracking = false;
static lv_indev_state_t s_last_state = LV_INDEV_STATE_RELEASED;
static lv_point_t s_last_point = {0, 0};
#endif /* !CONFIG_MODULUS_ZIG_UI_ENGINE */

static bool s_glove = false;
static bool s_hooked = false;
/* The one esp_lcd_touch handle: bsp_touch_new() under ZIG_UI, adopted from the
 * LVGL indev otherwise. */
static esp_lcd_touch_handle_t s_touch;
static float s_scale_x = 1.0f;
static float s_scale_y = 1.0f;

/* Zig scanout path state. Deliberately separate from the LVGL indev state
 * above: that one holds *panel* (portrait 720x1280) coords, this one holds
 * *logical* (landscape 1280x720) coords. They were one pair of statics, and
 * esp_lvgl_port calls lv_indev_read() straight from its task on every touch
 * IRQ — pausing the indev timer does not stop it — so the LVGL callback kept
 * overwriting the shared point with portrait coords. Every Zig poll that fell
 * back to the last sample then returned a portrait point as if it were
 * logical: a tap in the jog/override column came out with x < 420 and landed
 * on the DRO (axis select, Home, Zero). */
static bool s_zig_owns = false;
static bool s_zig_tracking = false;
static bool s_zig_pressed = false;
static struct {
    int32_t x;
    int32_t y;
} s_zig_point = {0, 0};
/** Last poll that saw real contact — release is time-gated, not poll-gated. */
static int64_t s_last_contact_us = 0;

enum {
    k_min_strength_normal = 5,
    k_min_strength_glove = 1,
    k_read_period_ms = 10, /* ~100 Hz input sampling; render stays at 33 ms */
    k_scroll_limit_px = 6, /* px before drag becomes scroll (reduces tap-steal) */
    /* Contact must be absent this long before a press becomes a release.
     * Must be a duration, not a poll count: the Zig UI task polls twice per
     * frame plus once per blit band, so a 2-poll guard could expire in tens of
     * microseconds and every dropped ST7123 sample became a finger-up. Each
     * phantom up fired a click while the finger was still down (override + ran
     * to 200%, jog mode thrashed, quick buttons flashed). */
    k_release_hold_ms = 60,
    /* Render-path coex wait. This read runs in the LVGL indev timer on Core 0;
     * a long wait here stalls rendering. The miss path holds the last sample
     * (no dropped press), so a short wait trades a rare bit of touch lag under
     * bus contention for a bounded worst-case render stall (was 15 ms ≈ half a
     * frame). Tune against on-device contention if touches feel missed. */
    k_touch_bus_wait_ms = 5,
};

/* --- LVGL-free panel->logical mapping (migration step 1 of 2) --------------
 *
 * Inverse of `fb.zig blitRotated`, which is the only thing that decides where a
 * logical pixel lands on the panel:
 *
 *   90 CW (normal):  logical (lx,ly) -> panel (ly, LOGICAL_W-1-lx)
 *   270  (flipped):  logical (lx,ly) -> panel (PANEL_W-1-ly, lx)
 *
 * Inverting the normal case gives  lx = LOGICAL_W-1-py,  ly = px.
 *
 * `Engine.mapPointer` owns the 180 flip, so — exactly like the LVGL path this
 * replaced — we always apply the 90 mapping here and never the flipped one.
 *
 * VERIFIED on device 2026-08-29 (ELF 56fd6651): A/B'd against
 * lv_display_rotate_point over a corner + column walk, 0 mismatches, and the
 * port reported `scale 1.000/1.000, lvgl res 1280x720`. The LVGL rotate call
 * and the lv_display_* resolution getters are now gone from this path. */
enum {
    k_panel_w = 720,
    k_panel_h = 1280,
    k_logical_w = 1280,
    k_logical_h = 720,
};

static void panel_to_logical(int32_t px, int32_t py, int32_t *lx, int32_t *ly)
{
    *lx = (int32_t)k_logical_w - 1 - py;
    *ly = px;
}

#if !CONFIG_MODULUS_ZIG_UI_ENGINE
static void modulus_touch_read(lv_indev_t *indev, lv_indev_data_t *data)
{
    touch_port_ctx_t *ctx = lv_indev_get_driver_data(indev);
    if (!ctx || !ctx->handle) {
        data->state = LV_INDEV_STATE_RELEASED;
        return;
    }

    if (s_zig_owns) {
        /* Zig polls the controller itself; a second reader here only adds I2C
         * contention (dropped samples read as finger-up → phantom clicks). */
        data->state = LV_INDEV_STATE_RELEASED;
        return;
    }

    if (!modulus_i2c_coex_lock(k_touch_bus_wait_ms)) {
        /* Transient bus contention (encoder probe, battery sample, IMU) —
         * hold the last real sample instead of faking a finger-up, which
         * cancels the active gesture and kills in-progress scrolls. */
        data->state = s_last_state;
        data->point = s_last_point;
        return;
    }

    uint8_t touch_cnt = 0;
    esp_lcd_touch_point_data_t touch_data[1] = {0};

    esp_lcd_touch_read_data(ctx->handle);
    esp_lcd_touch_get_data(ctx->handle, touch_data, &touch_cnt, 1);
    modulus_i2c_coex_unlock();

    if (touch_cnt > 0) {
        const uint16_t min_str = s_glove ? k_min_strength_glove : k_min_strength_normal;
        /* Hysteresis: the strength gate filters NEW presses only (hover/palm
         * rejection). Once a press is tracked, keep it until the panel reports
         * no contact — per-frame strength dips while the finger moves would
         * otherwise cancel scrolls (felt as "must press hard to scroll"). */
        if (!s_tracking && touch_data[0].strength < min_str) {
            data->state = LV_INDEV_STATE_RELEASED;
            s_last_state = LV_INDEV_STATE_RELEASED;
            return;
        }
        s_tracking = true;
        data->state = LV_INDEV_STATE_PRESSED;
        data->point.x = (lv_coord_t)(ctx->scale.x * touch_data[0].x);
        data->point.y = (lv_coord_t)(ctx->scale.y * touch_data[0].y);
        s_last_state = data->state;
        s_last_point = data->point;
        return;
    }

    s_tracking = false;
    s_last_state = LV_INDEV_STATE_RELEASED;
    data->state = LV_INDEV_STATE_RELEASED;
}
#endif /* !CONFIG_MODULUS_ZIG_UI_ENGINE */

void modulus_touch_init(void)
{
    if (s_hooked) {
        return;
    }
    s_glove = modulus_nvs_get_u8("touch_glove", 0) != 0;
#if CONFIG_MODULUS_ZIG_UI_ENGINE
    /* No LVGL indev to hook — the Zig UI polls via modulus_touch_poll_for_zig
     * and the handle comes from modulus_touch_create_handle(). */
    s_hooked = true;
    ESP_LOGI(TAG, "Touch HAL ready (glove=%d, min_str %u/%u, zig poll)",
             s_glove, (unsigned)k_min_strength_glove, (unsigned)k_min_strength_normal);
#else
    lv_indev_t *indev = bsp_display_get_input_dev();
    if (!indev) {
        ESP_LOGW(TAG, "No BSP touch indev — glove mode inactive");
        return;
    }

    lv_indev_set_read_cb(indev, modulus_touch_read);
    lv_indev_set_scroll_limit(indev, k_scroll_limit_px);

    /* Indev timer inherits LV_DEF_REFR_PERIOD (33 ms = 30 Hz) — too coarse for
     * smooth drag tracking. Sample input at ~66 Hz; rendering stays at 33 ms.
     * The read itself is a ~1-2 ms GT911 I2C transaction, safe at this rate. */
    lv_timer_t *read_timer = lv_indev_get_read_timer(indev);
    if (read_timer) {
        lv_timer_set_period(read_timer, k_read_period_ms);
    }

    s_hooked = true;
    ESP_LOGI(TAG, "Touch HAL ready (glove=%d, min_str %u/%u, read %ums, scroll_lim %upx)",
             s_glove, (unsigned)k_min_strength_glove, (unsigned)k_min_strength_normal,
             (unsigned)k_read_period_ms, (unsigned)k_scroll_limit_px);
#endif
}

void modulus_touch_set_glove_mode(bool enabled)
{
    s_glove = enabled;
    modulus_nvs_set_u8("touch_glove", enabled ? 1 : 0);
    ESP_LOGI(TAG, "Glove mode %s (min contact strength %u)",
             enabled ? "ON" : "OFF",
             (unsigned)(enabled ? k_min_strength_glove : k_min_strength_normal));
}

void modulus_touch_pause_for_zig(void)
{
    s_zig_owns = true;
#if !CONFIG_MODULUS_ZIG_UI_ENGINE
    lv_indev_t *indev = bsp_display_get_input_dev();
    if (!indev) {
        return;
    }
    lv_timer_t *read_timer = lv_indev_get_read_timer(indev);
    if (read_timer) {
        lv_timer_pause(read_timer);
    }
#endif
}

bool modulus_touch_poll_pressed(void)
{
    esp_lcd_touch_handle_t h = s_touch;
#if !CONFIG_MODULUS_ZIG_UI_ENGINE
    /* Pre-takeover wake path: handle still lives in the LVGL indev ctx. */
    if (!h) {
        lv_indev_t *indev = bsp_display_get_input_dev();
        if (!indev) {
            return false;
        }
        touch_port_ctx_t *ctx = lv_indev_get_driver_data(indev);
        if (!ctx || !ctx->handle) {
            return false;
        }
        h = ctx->handle;
    }
#endif
    if (!h) {
        return false;
    }
    if (!modulus_i2c_coex_lock(15)) {
        return false;
    }
    uint8_t touch_cnt = 0;
    esp_lcd_touch_point_data_t touch_data[1] = {0};
    esp_lcd_touch_read_data(h);
    esp_lcd_touch_get_data(h, touch_data, &touch_cnt, 1);
    modulus_i2c_coex_unlock();
    if (touch_cnt == 0) {
        return false;
    }
    const uint16_t min_str = s_glove ? k_min_strength_glove : k_min_strength_normal;
    return touch_data[0].strength >= min_str;
}

/* --- LVGL-free touch handle (migration step 2 of 2) ------------------------
 *
 * The Zig poll path used to fetch the touch handle and X/Y scale out of
 * esp_lvgl_port's PRIVATE touch_port_ctx_t via lv_indev_get_driver_data() —
 * the same hand-copied-struct hazard as the display bind.
 *
 * We do NOT call bsp_touch_new() to get our own: the BSP already created one
 * inside bsp_display_start_with_config, and a second handle would mean two
 * drivers talking to the same I2C touch controller. Instead we adopt the
 * existing handle and then remove the indev. lvgl_port_remove_touch() deletes
 * only the lv_indev, unregisters the INT callback and frees its ctx — it does
 * NOT delete the esp_lcd_touch handle, which the BSP still owns. Verified in
 * esp_lvgl_port/src/lvgl9/esp_lvgl_port_touch.c.
 *
 * scale defaults to 1 in lvgl_port_add_touch and measured 1.000/1.000 on Tab5
 * (touch and panel are both 720x1280); carried anyway for variants. */
static bool s_adopted;

/* ZIG_UI: create the one touch handle ourselves. There is no LVGL indev to
 * adopt from any more — display_shim uses bsp_display_new_with_handles()
 * instead of bsp_display_start_with_config(), so nothing else opens the
 * controller and there is no second driver to collide with. */
bool modulus_touch_create_handle(void)
{
    if (s_adopted) {
        return s_touch != NULL;
    }
    s_adopted = true;
    const bsp_touch_config_t cfg = {0};
    const esp_err_t err = bsp_touch_new(&cfg, &s_touch);
    if (err != ESP_OK || s_touch == NULL) {
        ESP_LOGE(TAG, "bsp_touch_new failed: %s", esp_err_to_name(err));
        s_touch = NULL;
        return false;
    }
    s_scale_x = 1.0f;
    s_scale_y = 1.0f;
    ESP_LOGI(TAG, "touch handle created %p (scale 1.000/1.000, no LVGL indev)",
             (void *)s_touch);
    return true;
}

#if !CONFIG_MODULUS_ZIG_UI_ENGINE
bool modulus_touch_adopt_handle(void)
{
    if (s_adopted) {
        return s_touch != NULL;
    }
    lv_indev_t *indev = bsp_display_get_input_dev();
    if (!indev) {
        ESP_LOGW(TAG, "no LVGL indev to adopt — touch unavailable");
        s_adopted = true;
        return false;
    }
    touch_port_ctx_t *ctx = lv_indev_get_driver_data(indev);
    if (!ctx || !ctx->handle) {
        ESP_LOGE(TAG, "lvgl_port touch ctx invalid — touch unavailable");
        s_adopted = true;
        return false;
    }

    s_touch = ctx->handle;
    s_scale_x = (ctx->scale.x != 0.0f) ? ctx->scale.x : 1.0f;
    s_scale_y = (ctx->scale.y != 0.0f) ? ctx->scale.y : 1.0f;
    s_adopted = true;

    /* Must run while the LVGL port task is alive: remove_touch takes
     * lvgl_port_lock(0). Called from modulus_display_zig_takeover before
     * lvgl_port_stop(). */
    const esp_err_t rm = lvgl_port_remove_touch(indev);
    if (rm != ESP_OK) {
        ESP_LOGW(TAG, "lvgl_port_remove_touch: %s", esp_err_to_name(rm));
    }
    ESP_LOGI(TAG, "touch handle adopted %p (scale %.3f/%.3f), LVGL indev removed",
             (void *)s_touch, (double)s_scale_x, (double)s_scale_y);
    return true;
}
#endif /* !CONFIG_MODULUS_ZIG_UI_ENGINE */

void modulus_touch_poll_for_zig(int32_t *x, int32_t *y, int *pressed)
{
    if (x) {
        *x = -1;
    }
    if (y) {
        *y = -1;
    }
    if (pressed) {
        *pressed = 0;
    }

    if (!s_touch) {
        return;
    }
    if (!modulus_i2c_coex_lock(k_touch_bus_wait_ms)) {
        /* Hold last sample under contention (same as LVGL read path). */
        if (pressed) {
            *pressed = (s_zig_pressed) ? 1 : 0;
        }
        if (x) {
            *x = s_zig_point.x;
        }
        if (y) {
            *y = s_zig_point.y;
        }
        return;
    }

    uint8_t touch_cnt = 0;
    esp_lcd_touch_point_data_t touch_data[1] = {0};
    esp_lcd_touch_read_data(s_touch);
    esp_lcd_touch_get_data(s_touch, touch_data, &touch_cnt, 1);
    modulus_i2c_coex_unlock();

    if (touch_cnt == 0) {
        if (s_zig_pressed &&
            (esp_timer_get_time() - s_last_contact_us) < (k_release_hold_ms * 1000)) {
            /* Hold last point — dropped samples must not end the gesture. */
            if (pressed) {
                *pressed = 1;
            }
            if (x) {
                *x = s_zig_point.x;
            }
            if (y) {
                *y = s_zig_point.y;
            }
            return;
        }
        s_zig_tracking = false;
        s_zig_pressed = false;
        return;
    }

    /* Zig path: accept any contact the controller reports (strength≥1). The
     * LVGL indev gate (min 5) drops light taps — felt as missed presses. */
    if (!s_zig_tracking && touch_data[0].strength < 1) {
        return;
    }
    s_zig_tracking = true;
    s_last_contact_us = esp_timer_get_time();

    /* Panel-native coords. scale measured 1.000/1.000 on Tab5 (touch and panel
     * are both 720x1280); honoured anyway in case a variant differs. */
    const int32_t px = (int32_t)(s_scale_x * (float)touch_data[0].x);
    const int32_t py = (int32_t)(s_scale_y * (float)touch_data[0].y);

    int32_t lx = 0;
    int32_t ly = 0;
    panel_to_logical(px, py, &lx, &ly);

    if (lx < 0) {
        lx = 0;
    } else if (lx >= (int32_t)k_logical_w) {
        lx = (int32_t)k_logical_w - 1;
    }
    if (ly < 0) {
        ly = 0;
    } else if (ly >= (int32_t)k_logical_h) {
        ly = (int32_t)k_logical_h - 1;
    }

    s_zig_pressed = true;
    s_zig_point.x = lx;
    s_zig_point.y = ly;
    if (pressed) {
        *pressed = 1;
    }
    if (x) {
        *x = lx;
    }
    if (y) {
        *y = ly;
    }
}
