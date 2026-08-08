/*
 * Tab5 touch HAL — glove-friendly contact threshold on BSP LVGL indev.
 * Port of C++ hal_touch.cpp (ST7123/GT911 strength filter + I2C coex).
 */
#include "touch_shim.h"
#include "i2c_coex_shim.h"
#include "nvs_shim.h"

#include <bsp/m5stack_tab5.h>
#include <esp_lcd_touch.h>
#include <esp_log.h>
#include <lvgl.h>

static const char *TAG = "modulus_touch";

typedef struct {
    esp_lcd_touch_handle_t handle;
    lv_indev_t *indev;
    struct {
        float x;
        float y;
    } scale;
} touch_port_ctx_t;

static bool s_glove = false;
static bool s_hooked = false;
static bool s_tracking = false;
static lv_indev_state_t s_last_state = LV_INDEV_STATE_RELEASED;
static lv_point_t s_last_point = {0, 0};

enum {
    k_min_strength_normal = 5,
    k_min_strength_glove = 1,
    k_read_period_ms = 10, /* ~100 Hz input sampling; render stays at 33 ms */
    k_scroll_limit_px = 6, /* px before drag becomes scroll (reduces tap-steal) */
    /* Render-path coex wait. This read runs in the LVGL indev timer on Core 0;
     * a long wait here stalls rendering. The miss path holds the last sample
     * (no dropped press), so a short wait trades a rare bit of touch lag under
     * bus contention for a bounded worst-case render stall (was 15 ms ≈ half a
     * frame). Tune against on-device contention if touches feel missed. */
    k_touch_bus_wait_ms = 5,
};

static void modulus_touch_read(lv_indev_t *indev, lv_indev_data_t *data)
{
    touch_port_ctx_t *ctx = lv_indev_get_driver_data(indev);
    if (!ctx || !ctx->handle) {
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

void modulus_touch_init(void)
{
    if (s_hooked) {
        return;
    }

    lv_indev_t *indev = bsp_display_get_input_dev();
    if (!indev) {
        ESP_LOGW(TAG, "No BSP touch indev — glove mode inactive");
        return;
    }

    s_glove = modulus_nvs_get_u8("touch_glove", 0) != 0;
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
}

void modulus_touch_set_glove_mode(bool enabled)
{
    s_glove = enabled;
    modulus_nvs_set_u8("touch_glove", enabled ? 1 : 0);
    ESP_LOGI(TAG, "Glove mode %s (min contact strength %u)",
             enabled ? "ON" : "OFF",
             (unsigned)(enabled ? k_min_strength_glove : k_min_strength_normal));
}

bool modulus_touch_poll_pressed(void)
{
    lv_indev_t *indev = bsp_display_get_input_dev();
    if (!indev) {
        return false;
    }
    touch_port_ctx_t *ctx = lv_indev_get_driver_data(indev);
    if (!ctx || !ctx->handle) {
        return false;
    }
    if (!modulus_i2c_coex_lock(15)) {
        return false;
    }
    uint8_t touch_cnt = 0;
    esp_lcd_touch_point_data_t touch_data[1] = {0};
    esp_lcd_touch_read_data(ctx->handle);
    esp_lcd_touch_get_data(ctx->handle, touch_data, &touch_cnt, 1);
    modulus_i2c_coex_unlock();
    if (touch_cnt == 0) {
        return false;
    }
    const uint16_t min_str = s_glove ? k_min_strength_glove : k_min_strength_normal;
    return touch_data[0].strength >= min_str;
}
