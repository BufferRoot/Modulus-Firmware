#include "ui_shim.h"
#include "ui_internal.h"
#include "ui_touch_sound.h"
#include "security_shim.h"
#include "display_shim.h"
#include "ui_settings_priv.h"
#include "nvs_shim.h"
#include "ui_zero_confirm.h"
#include "ui_job_progress.h"
#include "ui_state_modal.h"
#include <esp_log.h>
#include "sdkconfig.h"
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
static const char *TAG = "modulus_ui";
extern void modulus_zig_fill_cnc_status(modulus_cnc_status_t *out);
static lv_timer_t *s_refresh_tmr = NULL;
static bool s_dashboard_loaded = false;
static uint32_t s_refresh_period_cached = 0;
void modulus_ui_set_refresh_period_ms(uint32_t ms)
{
    if (s_refresh_tmr) {
        s_refresh_period_cached = ms;
        lv_timer_set_period(s_refresh_tmr, ms);
    }
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
    if (!s_refresh_tmr) {
        return;
    }
    const uint32_t ms = adaptive_refresh_ms(st);
    if (ms != s_refresh_period_cached) {
        s_refresh_period_cached = ms;
        lv_timer_set_period(s_refresh_tmr, ms);
    }
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
    if (s_refresh_tmr) {
        modulus_cnc_status_t st = {};
        modulus_zig_fill_cnc_status(&st);
        maybe_update_refresh_period(&st);
    }
}

static void refresh_cb(lv_timer_t *timer)
{
    (void)timer;
    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    maybe_update_refresh_period(&st);
    modulus_ui_dashboard_update(&st);
}

void modulus_ui_on_cnc_status_event(void)
{
    /* F-D1: dashboard refresh is timer-driven only (33–50 ms). Status events from
     * Core 1 must not lv_async_call into LVGL — that duplicated timer work and
     * violated LVGL thread safety (F-C1 / forensic C1). */
    modulus_ui_settings_cnc_on_status_event();
}

void modulus_ui_init(void)
{
    ESP_LOGI(TAG, "UI manager init");
    /* Touch: boot `touch_init` phase after i2c_coex (hooks.zig / touch_shim.c). */
    modulus_ui_theme_apply();
    modulus_ui_touch_sound_register();
}

void modulus_ui_show_boot_screen(void)
{
    ESP_LOGI(TAG, "Show boot screen");
    modulus_ui_boot_create();
}

void modulus_ui_arm_boot_transition(void)
{
    ESP_LOGI(TAG, "Arm boot -> dashboard transition");
    modulus_ui_boot_arm_transition();
}

void modulus_ui_show_dashboard(void)
{
    ESP_LOGI(TAG, "Show dashboard");
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
}

void modulus_ui_show_pin_lock(void)
{
    modulus_ui_pin_show();
}

void modulus_ui_hide_pin_lock(void)
{
    modulus_ui_pin_hide();
}

bool modulus_ui_pin_lock_visible(void)
{
    return modulus_ui_pin_visible();
}

void modulus_ui_update_dashboard(const modulus_cnc_status_t *status)
{
    modulus_ui_dashboard_update(status);
}

void modulus_ui_on_deep_sleep(void)
{
    if (s_refresh_tmr) {
        lv_timer_pause(s_refresh_tmr);
    }
    modulus_display_backlight_off();
}

void modulus_ui_on_wake(void)
{
    if (s_refresh_tmr) {
        lv_timer_resume(s_refresh_tmr);
    }
    modulus_display_backlight_on();
}

void modulus_ui_pause_dashboard_refresh(void)
{
    if (s_refresh_tmr) {
        lv_timer_pause(s_refresh_tmr);
    }
    modulus_ui_job_progress_pause_wave();
}

void modulus_ui_resume_dashboard_refresh(void)
{
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
}

void modulus_ui_show_settings(void)
{
    if (modulus_ui_settings_visible()) {
        return;
    }
    modulus_ui_pause_dashboard_refresh();
    modulus_ui_settings_show();
}

void modulus_ui_hide_settings(void)
{
    if (!modulus_ui_settings_visible()) {
        return;
    }
    /* Resume happens in settings_hide / settings_exit_ready after overlay gone. */
    modulus_ui_settings_hide();
}

bool modulus_ui_settings_open(void)
{
    return modulus_ui_settings_visible();
}
