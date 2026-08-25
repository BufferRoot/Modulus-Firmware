/*
 * Tab5 display BSP bridge — MIPI-DSI 1280×720 via espressif/m5stack_tab5 + LVGL port.
 * Mirrors C++ hal_display.cpp init path (stripe buffer, Core 0 LVGL task).
 */
#include "display_shim.h"
#include "imu_shim.h"
#include "security_shim.h"
#include "touch_shim.h"
#include "ui_engine_flush.h"

#include <esp_check.h>
#include <esp_heap_caps.h>
#include <esp_log.h>
#include <esp_timer.h>
#include <bsp/m5stack_tab5.h>
#include <esp_lvgl_port.h>
#include <lvgl.h>
#include "sdkconfig.h"
#include "tab5_pi4ioe.h"

static const char *TAG = "modulus_display";

static lv_display_t *s_disp = NULL;
static bool s_ready = false;
static uint8_t s_brightness = 100;
static uint8_t s_pre_dim_bright = 100;
static bool s_dimmed = false;
static bool s_sleeping = false;
static uint16_t s_dim_timeout = 0;
static uint16_t s_sleep_timeout = 0;
static int64_t s_wake_hold_until_us = 0;
static int64_t s_sleep_start_us = 0;
static bool s_zig_owns = false;
static esp_timer_handle_t s_activity_esp = NULL;
static int64_t s_last_activity_us = 0;

static const int64_t k_wake_hold_us = 30LL * 1000000LL;

static bool wake_hold_active(void)
{
    return s_wake_hold_until_us != 0 && esp_timer_get_time() < s_wake_hold_until_us;
}

static uint32_t effective_inactive_ms(void)
{
    if (wake_hold_active()) {
        return 0;
    }
    if (s_wake_hold_until_us != 0) {
        s_wake_hold_until_us = 0;
    }
    if (s_zig_owns || s_disp == NULL) {
        const int64_t now = esp_timer_get_time();
        if (s_last_activity_us == 0) {
            s_last_activity_us = now;
        }
        const int64_t dt = now - s_last_activity_us;
        return dt > 0 ? (uint32_t)(dt / 1000) : 0;
    }
    return lv_display_get_inactive_time(s_disp);
}

static void wake_from_idle(void)
{
    s_wake_hold_until_us = esp_timer_get_time() + k_wake_hold_us;
    s_last_activity_us = esp_timer_get_time();
    if (s_disp && !s_zig_owns) {
        lv_display_trigger_activity(s_disp);
    }

    const uint8_t restore = s_pre_dim_bright;
    const bool was_sleeping = s_sleeping;
    if (was_sleeping) {
        modulus_security_on_sleep_wake(s_sleep_start_us);
        s_sleeping = false;
        s_dimmed = false;
        bsp_display_backlight_on();
        bsp_display_brightness_set((int)restore);
        s_brightness = restore;
    } else if (s_dimmed) {
        s_dimmed = false;
        bsp_display_brightness_set((int)restore);
        s_brightness = restore;
    }
}

static void activity_check_cb(void *arg)
{
    (void)arg;
    if (!s_ready) {
        return;
    }

    const uint32_t inactive_ms = effective_inactive_ms();

    if (!s_sleeping) {
        modulus_security_idle_lock_tick(inactive_ms);
    }

    if (modulus_imu_wake_on_motion() && !modulus_imu_is_ready() && !modulus_imu_is_init_running()) {
        modulus_imu_ensure_bringup();
    }

    if (modulus_imu_wake_on_motion() && (s_dimmed || s_sleeping) && !modulus_imu_is_init_running()) {
        if (modulus_imu_poll_motion_wake()) {
            ESP_LOGI(TAG, "Display woken by BMI270 motion");
            wake_from_idle();
            return;
        }
    }

    if (s_sleep_timeout > 0 && inactive_ms >= (uint32_t)s_sleep_timeout * 1000) {
        if (!s_sleeping) {
            s_sleep_start_us = esp_timer_get_time();
            s_sleeping = true;
            if (!s_dimmed) {
                s_pre_dim_bright = s_brightness;
            }
            s_dimmed = true;
            bsp_display_backlight_off();
            ESP_LOGI(TAG, "Display sleeping after %u sec inactivity", s_sleep_timeout);
        }
        return;
    }

    if (s_dim_timeout > 0 && inactive_ms >= (uint32_t)s_dim_timeout * 1000) {
        if (!s_dimmed) {
            s_dimmed = true;
            s_pre_dim_bright = s_brightness;
            bsp_display_brightness_set(5);
            ESP_LOGI(TAG, "Display dimmed after %u sec inactivity", s_dim_timeout);
        }
        return;
    }
    /* Wake only via note_user_activity / IMU — not on every timer tick while dimmed. */
}

static bool activity_monitor_needed(void)
{
    return s_dim_timeout > 0 || s_sleep_timeout > 0 || modulus_security_idle_lock_enabled();
}

static void ensure_activity_timer(void)
{
    if (!s_ready || !activity_monitor_needed()) {
        return;
    }
    if (s_activity_esp) {
        return;
    }
    const esp_timer_create_args_t args = {
        .callback = &activity_check_cb,
        .name = "disp_act",
    };
    if (esp_timer_create(&args, &s_activity_esp) != ESP_OK) {
        ESP_LOGE(TAG, "activity esp_timer create failed");
        s_activity_esp = NULL;
        return;
    }
    if (s_last_activity_us == 0) {
        s_last_activity_us = esp_timer_get_time();
    }
    esp_timer_start_periodic(s_activity_esp, 500000); // 500 ms
}

void modulus_display_refresh_activity_monitor(void)
{
    if (!s_ready) {
        return;
    }
    if (activity_monitor_needed()) {
        ensure_activity_timer();
        return;
    }
    if (s_activity_esp) {
        esp_timer_stop(s_activity_esp);
        esp_timer_delete(s_activity_esp);
        s_activity_esp = NULL;
    }
}

bool modulus_display_init(uint32_t stripe_lines, bool flipped, uint8_t brightness_pct)
{
    if (s_ready) {
        return true;
    }

    ESP_LOGI(TAG, "Initializing Tab5 display (BSP + LVGL)");

    ESP_RETURN_ON_FALSE(bsp_i2c_init() == ESP_OK, false, TAG, "bsp_i2c_init failed");

    i2c_master_bus_handle_t i2c_bus = bsp_i2c_get_handle();
    ESP_RETURN_ON_FALSE(tab5_pi4ioe_init(i2c_bus), false, TAG, "PI4IOE init failed");

    lvgl_port_cfg_t lvgl_cfg = ESP_LVGL_PORT_INIT_CONFIG();
#if CONFIG_MODULUS_ZIG_UI_ENGINE
    /* Zig owns paint — thin LVGL port only for BSP panel bind / flush ctx. */
    lvgl_cfg.task_stack = 8192;
    lvgl_cfg.task_max_sleep_ms = 1000;
    lvgl_cfg.timer_period_ms = 50;
#else
    /* 16 KiB overflowed under 1280×720 sw_rotate when Quick Settings /
     * wireless pages ran lv_obj_clean+rebuild inside input handlers (Zigbee
     * tile tap + 1 Hz state refresh) — stack guard fault after IDLE0 WDT. */
    lvgl_cfg.task_stack = 24576;
    lvgl_cfg.task_max_sleep_ms = 33;
#endif
    lvgl_cfg.task_priority = 5;
    /* ESP_LVGL_PORT_INIT_CONFIG defaults task_affinity to -1 (any core) —
     * pin to Core 0 so taskLVGL never migrates onto Core 1 and competes with
     * sys_task/serial_rx (sovereign-core contract: Core 0 = UI, Core 1 = CNC). */
    lvgl_cfg.task_affinity = 0;

#if CONFIG_MODULUS_ZIG_UI_ENGINE
    /* Minimal DMA stripe — Zig paints the DPI FB directly; LVGL buf only for bind. */
    const uint32_t stripe = (stripe_lines > 0 && stripe_lines < 40) ? stripe_lines : 24;
    bsp_display_cfg_t cfg = {
        .lvgl_port_cfg = lvgl_cfg,
        .buffer_size = BSP_LCD_H_RES * stripe,
        .double_buffer = false,
        .flags = {
            .buff_dma = true,
            .buff_spiram = true,
            .sw_rotate = true,
        },
    };
#else
    const uint32_t stripe = (stripe_lines > 0) ? stripe_lines : 120;
    bsp_display_cfg_t cfg = {
        .lvgl_port_cfg = lvgl_cfg,
        .buffer_size = BSP_LCD_H_RES * stripe,
        .double_buffer = true,
        .flags = {
            .buff_dma = true,
            /* PSRAM: buf1+buf2+PPA rotation scratch (~506 KiB) — internal DMA cannot fit at init. */
            .buff_spiram = true,
            /* sw_rotate=true + CONFIG_LVGL_PORT_ENABLE_PPA → PPA SRM rotate on flush (not CPU). */
            .sw_rotate = true,
        },
    };
#endif

    s_disp = bsp_display_start_with_config(&cfg);
    if (s_disp == NULL) {
        ESP_LOGE(TAG, "bsp_display_start_with_config failed");
        return false;
    }

    if (!bsp_display_lock(0)) {
        ESP_LOGE(TAG, "bsp_display_lock failed after start");
        return false;
    }

    lv_display_set_rotation(s_disp, flipped ? LV_DISPLAY_ROTATION_270 : LV_DISPLAY_ROTATION_90);
    /* Backlight deferred to display_unlock — first LVGL frame paints before panel lights. */
    if (brightness_pct > 100) {
        brightness_pct = 100;
    }
    bsp_display_brightness_set((int)brightness_pct);
    s_brightness = brightness_pct;
    s_pre_dim_bright = brightness_pct;

    s_ready = true;
    const size_t internal_free = heap_caps_get_free_size(MALLOC_CAP_INTERNAL);
    const size_t psram_free = heap_caps_get_free_size(MALLOC_CAP_SPIRAM);
    const size_t internal_largest = heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL);
    const size_t psram_largest = heap_caps_get_largest_free_block(MALLOC_CAP_SPIRAM);
    ESP_LOGI(TAG, "Display ready (stripe=%lu lines, PSRAM DMA, rotation=%s, PPA=%s)",
             (unsigned long)stripe, flipped ? "270°" : "90°",
#if defined(CONFIG_LVGL_PORT_ENABLE_PPA) && CONFIG_LVGL_PORT_ENABLE_PPA
             "on"
#else
             "off"
#endif
    );
    ESP_LOGI(TAG, "Heap after display init: internal free=%u KiB (max blk %u), PSRAM free=%u KiB (max blk %u)",
             (unsigned)(internal_free / 1024), (unsigned)(internal_largest / 1024),
             (unsigned)(psram_free / 1024), (unsigned)(psram_largest / 1024));
    /* Bind the DPI scanout buffer the Zig engine paints into. */
    modulus_ui_engine_flush_try_bind_from_lvgl(s_disp);
#if CONFIG_MODULUS_ZIG_UI_ENGINE
    if (!modulus_ui_engine_flush_ready()) {
        ESP_LOGE(TAG, "BSP panel/DPI bind failed — Zig UI cannot paint");
        bsp_display_unlock();
        s_ready = false;
        s_disp = NULL;
        return false;
    }
    if (!modulus_ui_engine_flush_dual()) {
        ESP_LOGW(TAG, "BSP gave single DPI FB — expect tear; want CONFIG_BSP_LCD_DPI_BUFFER_NUMS≥2");
    } else {
        ESP_LOGI(TAG, "BSP dual DPI FB ready — Zig tear-free flip path");
    }
#endif
    modulus_display_refresh_activity_monitor();
    /* Lock held — Zig boot calls unlock at display_unlock phase. */
    return true;
}

bool modulus_display_is_ready(void)
{
    return s_ready;
}

bool modulus_display_has_ambient_light_sensor(void)
{
    return false;
}

void modulus_display_set_brightness(uint8_t percent)
{
    if (!s_ready) {
        return;
    }
    if (percent > 100) {
        percent = 100;
    }
    bsp_display_brightness_set((int)percent);
    s_brightness = percent;
}

void modulus_display_backlight_off(void)
{
    if (!s_ready) {
        return;
    }
    bsp_display_backlight_off();
}

void modulus_display_backlight_on(void)
{
    if (!s_ready) {
        return;
    }
    bsp_display_backlight_on();
}

void modulus_display_lock(void)
{
    if (!s_ready) {
        return;
    }
    (void)bsp_display_lock(0);
}

void modulus_display_unlock(void)
{
    if (!s_ready) {
        return;
    }
    bsp_display_unlock();
#if CONFIG_MODULUS_ZIG_UI_ENGINE
    /* Zig paints splash then lights the panel in zig_ui_task. Unlock must not
     * turn on backlight over an empty LVGL screen (white flash before splash). */
    (void)s_zig_owns;
    return;
#else
    if (s_zig_owns) {
        /* Zig owns MIPI — do not kick LVGL refr. */
        bsp_display_backlight_on();
        return;
    }
    /* First frame after early boot splash — LVGL task was blocked on lock until now. */
    if (s_disp && bsp_display_lock(0)) {
        lv_obj_t *scr = lv_screen_active();
        if (scr) {
            lv_obj_invalidate(scr);
        }
        lv_refr_now(s_disp);
        bsp_display_backlight_on();
        bsp_display_unlock();
    }
#endif
}

bool modulus_display_zig_owns(void)
{
    return s_zig_owns;
}

void modulus_display_zig_takeover(void)
{
    if (!s_ready || s_zig_owns) {
        return;
    }
    s_zig_owns = true;
    s_last_activity_us = esp_timer_get_time();
    /* Zig polls touch via modulus_touch_poll_for_zig; stop LVGL's indev
     * timer so the two paths don't fight over the I2C bus. */
    modulus_touch_pause_for_zig();
    /* Stop LVGL tick timer — Zig owns scanout; taskLVGL then mostly sleeps. */
    if (lvgl_port_stop() != ESP_OK) {
        ESP_LOGW(TAG, "lvgl_port_stop failed (non-fatal)");
    }
    /* Activity monitor is esp_timer — keep running under Zig ownership. */
    modulus_display_refresh_activity_monitor();
    ESP_LOGI(TAG, "Zig UI engine owns scanout (LVGL tick stopped)");
}

void modulus_display_resume_activity_monitor(void)
{
    if (!s_ready) {
        return;
    }
    s_last_activity_us = esp_timer_get_time();
    modulus_display_refresh_activity_monitor();
}

void modulus_display_set_flip(bool flipped)
{
    if (!s_ready || s_disp == NULL) {
        return;
    }
    if (!bsp_display_lock(0)) {
        return;
    }
    lv_display_set_rotation(s_disp, flipped ? LV_DISPLAY_ROTATION_270 : LV_DISPLAY_ROTATION_90);
    if (!s_zig_owns) {
        lv_obj_invalidate(lv_screen_active());
        lv_obj_invalidate(lv_layer_top());
    }
    bsp_display_unlock();
}

void modulus_display_set_timeouts(uint16_t dim_sec, uint16_t sleep_sec)
{
    s_dim_timeout = dim_sec;
    s_sleep_timeout = sleep_sec;
    modulus_display_refresh_activity_monitor();
}

void modulus_display_start_activity_monitor(void)
{
    modulus_display_refresh_activity_monitor();
}

void modulus_display_note_user_activity(void)
{
    s_last_activity_us = esp_timer_get_time();
    if (s_disp && !s_zig_owns) {
        lv_display_trigger_activity(s_disp);
    }
    if (s_sleeping || s_dimmed) {
        wake_from_idle();
    }
}

bool modulus_display_is_sleeping(void)
{
    return s_sleeping;
}

bool modulus_display_wake_hold_active(void)
{
    return wake_hold_active();
}

int64_t modulus_display_sleep_start_us(void)
{
    return s_sleep_start_us;
}

lv_display_t *modulus_display_get_lvgl(void)
{
    return s_disp;
}
