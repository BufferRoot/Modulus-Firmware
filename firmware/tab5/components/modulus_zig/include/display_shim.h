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

#ifdef __cplusplus
}
#endif
