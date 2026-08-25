#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

bool modulus_display_init(uint32_t stripe_lines, bool flipped, uint8_t brightness_pct);
bool modulus_display_is_ready(void);
/** Tab5 has no ambient light sensor; SC2356 is not used as a light proxy (C++ parity). */
bool modulus_display_has_ambient_light_sensor(void);
void modulus_display_set_brightness(uint8_t percent);
void modulus_display_backlight_off(void);
void modulus_display_backlight_on(void);
void modulus_display_lock(void);
void modulus_display_unlock(void);
/** Zig UI owns MIPI; LVGL timers/invalidation suspended. */
void modulus_display_zig_takeover(void);
bool modulus_display_zig_owns(void);
/** Resume dim/sleep/idle-lock timer after Zig takeover (was paused). */
void modulus_display_resume_activity_monitor(void);
void modulus_display_set_flip(bool flipped);
void modulus_display_set_timeouts(uint16_t dim_sec, uint16_t sleep_sec);
void modulus_display_start_activity_monitor(void);
void modulus_display_refresh_activity_monitor(void);
void modulus_display_note_user_activity(void);
bool modulus_display_is_sleeping(void);
bool modulus_display_wake_hold_active(void);
int64_t modulus_display_sleep_start_us(void);
struct _lv_display_t;
typedef struct _lv_display_t lv_display_t;
lv_display_t *modulus_display_get_lvgl(void);

/* P4 PPA (Pixel Processing Accelerator) rotate — replaces the CPU transpose.
 * esp_lvgl_port used this via CONFIG_LVGL_PORT_ENABLE_PPA; the Zig engine owns
 * the scanout directly, so it drives the SRM engine itself. */
bool modulus_ppa_init(void);
bool modulus_ppa_available(void);
/** Rotate one landscape block into the portrait scanout. Blocking; RGB565 only.
 *  `flipped` selects 270 instead of 90 (Flip display 180). Returns false on any
 *  rejection so the caller can fall back to the CPU path. */
bool modulus_ppa_rotate_block(const void *src, void *dst, uint32_t dst_bytes,
                              uint32_t src_w, uint32_t src_h,
                              uint32_t dst_w, uint32_t dst_h,
                              uint32_t bx, uint32_t by, uint32_t bw, uint32_t bh,
                              bool flipped);

/* Zig freestanding imports — `c_int` 0/1 (Zig #35373); wrap bool C helpers. */
int modulus_ppa_init_zi(void);
int modulus_ppa_rotate_block_zi(const void *src, void *dst, uint32_t dst_bytes,
                                uint32_t src_w, uint32_t src_h,
                                uint32_t dst_w, uint32_t dst_h,
                                uint32_t bx, uint32_t by, uint32_t bw, uint32_t bh,
                                int flipped);

#ifdef __cplusplus
}
#endif
