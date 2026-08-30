#include "ui_shim.h"
#include "ui_internal.h"
#include "ui_touch_sound.h"
#include "security_shim.h"
#include "display_shim.h"
#include "ui_engine_flush.h"
#include "ui_settings_priv.h"
#include "nvs_shim.h"
#include "ui_zero_confirm.h"
#include "ui_job_progress.h"
#include "ui_state_modal.h"
#include <esp_log.h>
#include <esp_timer.h>
#include <esp_cpu.h>
#include "sdkconfig.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

/* Fail fast if sdkconfig drifts from sdkconfig.defaults — builtin TLSF exhausts
 * under 1280×720 sw_rotate and pins taskLVGL -> IDLE0 WDT (~5 s). */
#if defined(CONFIG_LV_USE_BUILTIN_MALLOC) && CONFIG_LV_USE_BUILTIN_MALLOC
#error "Tab5 requires CONFIG_LV_USE_CLIB_MALLOC=y (LV_USE_BUILTIN_MALLOC breaks sw_rotate UI)"
#endif
#if !defined(CONFIG_LV_USE_CLIB_MALLOC) || !CONFIG_LV_USE_CLIB_MALLOC
#error "Tab5 requires CONFIG_LV_USE_CLIB_MALLOC=y for PSRAM-backed LVGL heap"
#endif
#if !CONFIG_SPIRAM_USE_MALLOC
#error "Tab5 requires CONFIG_SPIRAM_USE_MALLOC=y so LVGL layers use PSRAM"
#endif
#if CONFIG_MODULUS_ZIG_UI_ENGINE
#if defined(CONFIG_LV_USE_PERF_MONITOR) && CONFIG_LV_USE_PERF_MONITOR
#error "Zig UI: disable CONFIG_LV_USE_PERF_MONITOR (use System FPS HUD)"
#endif
#if defined(CONFIG_LV_USE_SYSMON) && CONFIG_LV_USE_SYSMON
#error "Zig UI: disable CONFIG_LV_USE_SYSMON"
#endif
#endif
static const char *TAG = "modulus_ui";
extern void modulus_zig_fill_cnc_status(modulus_cnc_status_t *out);
#if !CONFIG_MODULUS_ZIG_UI_ENGINE
/* LVGL refresh timer — the Zig engine paces itself in zig_ui_task. */
static lv_timer_t *s_refresh_tmr = NULL;
#endif
static bool s_dashboard_loaded = false;
static uint32_t s_refresh_period_cached = 0;

unsigned modulus_amp_core_id(void)
{
    return (unsigned)esp_cpu_get_core_id();
}

#if CONFIG_MODULUS_ZIG_UI_ENGINE
extern int modulus_zig_ui_boot(void);
extern void modulus_zig_ui_frame(void);
extern void modulus_zig_ui_arm_boot_hold(void);
extern void modulus_zig_ui_install_late(void);
static TaskHandle_t s_zig_ui_task;
static volatile uint32_t s_zig_ui_polls;

static void zig_ui_task(void *arg)
{
    (void)arg;
    ESP_LOGI(TAG, "zig_ui task start (Core 0)");
#if !CONFIG_FREERTOS_UNICORE
    if (modulus_amp_core_id() != 0) {
        ESP_LOGE(TAG, "AMP fence: zig_ui on core %u (expected 0)", modulus_amp_core_id());
    }
#endif
    modulus_display_zig_takeover();
    if (!modulus_zig_ui_boot()) {
        ESP_LOGE(TAG, "modulus_zig_ui_boot failed");
        vTaskDelete(NULL);
        return;
    }
    /* Splash already on scanout — light panel, then start the 3 s hold. */
    modulus_display_backlight_on();
    modulus_zig_ui_arm_boot_hold();
    ESP_LOGI(TAG, "zig_ui boot frame flushed (%u px)",
             (unsigned)modulus_ui_engine_flush_last_px());
    /* Touch is sampled once per iteration, so this period is also the input
     * sample period: at 33 ms a quick tap could land and lift inside one
     * window and never be seen. 10 ms matches the LVGL indev rate this
     * replaced (CONFIG_FREERTOS_HZ=1000, so one tick == 1 ms).
     *
     * vTaskDelayUntil, not vTaskDelay: a relative delay made the period
     * `paint + remainder`, so a 25 ms render frame stretched the 3-poll render
     * cadence from 30 ms to ~45 ms and made it breathe with paint cost. The
     * absolute deadline keeps the sample rate phase-locked and returns
     * immediately when a long frame already overran it. */
    TickType_t last_wake = xTaskGetTickCount();
    const TickType_t period = pdMS_TO_TICKS(10);
    for (;;) {
        modulus_zig_ui_frame();
        s_zig_ui_polls++;
        const TickType_t now = xTaskGetTickCount();
        if ((TickType_t)(now - last_wake) >= period) {
            /* Frame overran its slot. Plain vTaskDelayUntil would return
             * immediately here and keep returning until it caught up the
             * missed deadlines — zig_ui then never blocks, IDLE0 never runs
             * and the task WDT fires. Resync and yield a tick instead, so
             * every iteration blocks at least once. */
            last_wake = now;
            vTaskDelay(1);
        } else {
            vTaskDelayUntil(&last_wake, period);
        }
    }
}

extern uint32_t modulus_zig_dirty_merge_all_count(void);
extern uint32_t modulus_zig_last_dirty_px(void);

/* Health line lives on its own task: a ~100 char ESP_LOGI at 115200 baud
 * blocks ~9 ms, which inside the frame loop dropped a frame every 5 s.
 * NOTE: only visible at log level >= Info; storage_shim restores NVS `loglvl`
 * during boot, so a device set to Warning shows nothing here. */
static void zig_ui_health_task(void *arg)
{
    TaskHandle_t ui = (TaskHandle_t)arg;
    uint32_t last_polls = 0;
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(5000));
        const uint32_t polls = s_zig_ui_polls;
        ESP_LOGI(TAG, "zig_ui %lu polls (%lu/s), dirty %lu px, merge-all %lu, stack hwm %u",
                 (unsigned long)polls,
                 (unsigned long)((polls - last_polls) / 5u),
                 (unsigned long)modulus_zig_last_dirty_px(),
                 (unsigned long)modulus_zig_dirty_merge_all_count(),
                 (unsigned)uxTaskGetStackHighWaterMark(ui));
        last_polls = polls;
    }
}
#endif

void modulus_ui_set_refresh_period_ms(uint32_t ms)
{
#if CONFIG_MODULUS_ZIG_UI_ENGINE
    /* Zig paces itself; keep the cached value for the settings readout. */
    s_refresh_period_cached = ms;
#else
    if (s_refresh_tmr) {
        s_refresh_period_cached = ms;
        lv_timer_set_period(s_refresh_tmr, ms);
    }
#endif
}

static uint32_t refresh_ms_from_hz(uint8_t hz_idx)
{
    /* Minimum 33 ms — 16 ms dashboard tick pinned taskLVGL on Core 0 (IDLE0 WDT)
     * under 1280x720 sw_rotate even with CLIB+PSRAM heap. Matches CONFIG_LV_DEF_REFR_PERIOD=33. */
    switch (hz_idx) {
    case 0:
        return 33;
    case 1:
        return 40;
    default:
        return 50;
    }
}

static bool machine_is_dashboard_idle(const modulus_cnc_status_t *st)
{
    return st->connected == 0 || st->state == MOD_UI_MACH_IDLE;
}

static bool machine_needs_motion_refresh(uint8_t state)
{
    return state == MOD_UI_MACH_RUN || state == MOD_UI_MACH_HOLD || state == MOD_UI_MACH_JOG;
}
/* F3: idle-adaptive refresh — 50 ms when Idle/offline, 33 ms when Run/Hold/Jog. */
static uint32_t adaptive_refresh_ms(const modulus_cnc_status_t *st)
{
    const uint32_t user = refresh_ms_from_hz(modulus_nvs_get_u8("refr_hz", 0));
    if (machine_is_dashboard_idle(st)) {
        return user < 50 ? 50 : user;
    }
    if (machine_needs_motion_refresh(st->state)) {
        return 33;
    }
    return user;
}

static void maybe_update_refresh_period(const modulus_cnc_status_t *st)
{
#if CONFIG_MODULUS_ZIG_UI_ENGINE
    (void)st;
#else
    if (!s_refresh_tmr) {
        return;
    }
    const uint32_t ms = adaptive_refresh_ms(st);
    if (ms != s_refresh_period_cached) {
        s_refresh_period_cached = ms;
        lv_timer_set_period(s_refresh_tmr, ms);
    }
#endif
}

static uint32_t refresh_period_ms(void)
{
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    return adaptive_refresh_ms(&st);
}

void modulus_ui_set_dashboard_refresh_hz(uint8_t refr_hz)
{
    if (refr_hz > 2) {
        refr_hz = 2;
    }
    modulus_nvs_set_u8("refr_hz", refr_hz);
#if !CONFIG_MODULUS_ZIG_UI_ENGINE
    if (s_refresh_tmr) {
        modulus_cnc_status_t st = {};
        modulus_zig_fill_cnc_status(&st);
        maybe_update_refresh_period(&st);
    }
#endif
}

#if !CONFIG_MODULUS_ZIG_UI_ENGINE
static void refresh_cb(lv_timer_t *timer)
{
    (void)timer;
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    maybe_update_refresh_period(&st);
    modulus_ui_dashboard_update(&st);
}
#endif

void modulus_ui_on_cnc_status_event(void)
{
#if !CONFIG_MODULUS_ZIG_UI_ENGINE
    /* F-D1: dashboard refresh is timer-driven only (33–50 ms). Status events from
     * Core 1 must not lv_async_call into LVGL — that duplicated timer work and
     * violated LVGL thread safety (F-C1 / forensic C1). */
    modulus_ui_settings_cnc_on_status_event();
#endif
}

void modulus_ui_init(void)
{
    ESP_LOGI(TAG, "UI manager init");
#if CONFIG_MODULUS_ZIG_UI_ENGINE
    /* Zig Engine owns theme / touch tick; LVGL widget tree not linked. */
#else
    /* Touch: boot `touch_init` phase after i2c_coex (hooks.zig / touch_shim.c). */
    modulus_ui_theme_apply();
    modulus_ui_touch_sound_register();
#endif
}

void modulus_ui_show_boot_screen(void)
{
    ESP_LOGI(TAG, "Show boot screen");
#if CONFIG_MODULUS_ZIG_UI_ENGINE
    if (s_zig_ui_task) {
        return;
    }
    /* 64 KiB: settings shell + CNC tab paint; 40 KiB overflowed (stack protect).
     * FB on PSRAM via c_allocator — stack is call depth / locals only. */
    BaseType_t ok = xTaskCreatePinnedToCore(
        zig_ui_task, "zig_ui", 65536, NULL, 5, &s_zig_ui_task, 0);
    if (ok == pdPASS) {
        /* Prio 1: never preempts zig_ui (5) or sys_task; UART blocking here
         * costs nothing. Core 0 so it cannot land on the CNC core. */
        (void)xTaskCreatePinnedToCore(zig_ui_health_task, "zig_ui_hp", 3072,
                                      s_zig_ui_task, 1, NULL, 0);
    }
    if (ok != pdPASS) {
        ESP_LOGE(TAG, "zig_ui task create failed");
        s_zig_ui_task = NULL;
    }
    /* Do NOT block here for modulus_zig_ui_is_ready — that forced install()
     * (storage/I2C/wireless) before boot i2c_coex/storage_init and crashed
     * on settings. Backlight stays off until zig_ui lights after splash. */
#else
    modulus_ui_boot_create();
#endif
}

void modulus_ui_arm_boot_transition(void)
{
    ESP_LOGI(TAG, "Arm boot -> dashboard transition");
#if CONFIG_MODULUS_ZIG_UI_ENGINE
    /* Boot HAL finished (i2c_coex + storage) — safe for deferred Zig bring-up. */
    modulus_zig_ui_install_late();
#else
    modulus_ui_boot_arm_transition();
#endif
}

void modulus_ui_show_dashboard(void)
{
    ESP_LOGI(TAG, "Show dashboard");
#if CONFIG_MODULUS_ZIG_UI_ENGINE
    /* Zig Engine paints dashboard after boot. */
    return;
#else
    if (!s_dashboard_loaded) {
        modulus_ui_dashboard_create();
        modulus_ui_prewarm_power_menu();
        s_dashboard_loaded = true;
    }
    lv_obj_t *dash = modulus_ui_dashboard_screen();
    if (dash) {
        /* Plain load, NOT a fade: a screen-fade animates full-screen opacity,
         * forcing LVGL to composite the whole 1280x720 tree into an intermediate
         * layer under sw_rotate. With the 64 KB LVGL pool that thrashes the TLSF
         * allocator (lv_draw_dispatch_layer/buf_malloc) and pins taskLVGL on
         * Core 0 -> IDLE0 WDT. Same full-screen-layer class the rules ban for
         * transform_scale. */
        lv_screen_load(dash);
        lv_obj_invalidate(dash);
    }
    if (!s_refresh_tmr) {
        s_refresh_period_cached = refresh_period_ms();
        s_refresh_tmr = lv_timer_create(refresh_cb, s_refresh_period_cached, NULL);
    } else {
        s_refresh_period_cached = refresh_period_ms();
        lv_timer_set_period(s_refresh_tmr, s_refresh_period_cached);
        lv_timer_resume(s_refresh_tmr);
    }
    if (modulus_security_is_locked() && !modulus_ui_pin_visible()) {
        modulus_ui_show_pin_lock();
    }
#endif
}

void modulus_ui_show_pin_lock(void)
{
#if CONFIG_MODULUS_ZIG_UI_ENGINE
    /* Zig Engine Screen.pin — no LVGL pin lock. */
#else
    modulus_ui_pin_show();
#endif
}

void modulus_ui_hide_pin_lock(void)
{
#if CONFIG_MODULUS_ZIG_UI_ENGINE
#else
    modulus_ui_pin_hide();
#endif
}

bool modulus_ui_pin_lock_visible(void)
{
#if CONFIG_MODULUS_ZIG_UI_ENGINE
    return false;
#else
    return modulus_ui_pin_visible();
#endif
}

void modulus_ui_update_dashboard(const modulus_cnc_status_t *status)
{
#if CONFIG_MODULUS_ZIG_UI_ENGINE
    (void)status;
#else
    modulus_ui_dashboard_update(status);
#endif
}

void modulus_ui_on_deep_sleep(void)
{
#if !CONFIG_MODULUS_ZIG_UI_ENGINE
    if (s_refresh_tmr) {
        lv_timer_pause(s_refresh_tmr);
    }
#endif
    modulus_display_backlight_off();
}

void modulus_ui_on_wake(void)
{
#if !CONFIG_MODULUS_ZIG_UI_ENGINE
    if (s_refresh_tmr) {
        lv_timer_resume(s_refresh_tmr);
    }
#endif
    modulus_display_backlight_on();
}

void modulus_ui_pause_dashboard_refresh(void)
{
#if CONFIG_MODULUS_ZIG_UI_ENGINE
#else
    if (s_refresh_tmr) {
        lv_timer_pause(s_refresh_tmr);
    }
    modulus_ui_job_progress_pause_wave();
#endif
}

void modulus_ui_resume_dashboard_refresh(void)
{
#if CONFIG_MODULUS_ZIG_UI_ENGINE
#else
    if (!s_refresh_tmr || !s_dashboard_loaded) {
        return;
    }
    if (modulus_ui_settings_visible() || modulus_ui_quick_settings_visible() ||
        modulus_ui_power_menu_visible() || modulus_ui_zero_confirm_visible() ||
        modulus_ui_pin_visible() || modulus_ui_state_modal_visible()) {
        return;
    }
    s_refresh_period_cached = refresh_period_ms();
    lv_timer_set_period(s_refresh_tmr, s_refresh_period_cached);
    lv_timer_resume(s_refresh_tmr);
    modulus_ui_job_progress_resume_wave();
#endif
}

void modulus_ui_show_settings(void)
{
#if CONFIG_MODULUS_ZIG_UI_ENGINE
#else
    if (modulus_ui_settings_visible()) {
        return;
    }
    modulus_ui_pause_dashboard_refresh();
    modulus_ui_settings_show();
#endif
}

void modulus_ui_hide_settings(void)
{
#if CONFIG_MODULUS_ZIG_UI_ENGINE
#else
    if (!modulus_ui_settings_visible()) {
        return;
    }
    /* Resume happens in settings_hide / settings_exit_ready after overlay gone. */
    modulus_ui_settings_hide();
#endif
}

bool modulus_ui_settings_open(void)
{
#if CONFIG_MODULUS_ZIG_UI_ENGINE
    return false;
#else
    return modulus_ui_settings_visible();
#endif
}
