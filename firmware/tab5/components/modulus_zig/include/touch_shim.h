#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void modulus_touch_init(void);
void modulus_touch_set_glove_mode(bool enabled);

/** Pause LVGL indev timer — Zig owns the touch poll while it owns scanout. */
void modulus_touch_pause_for_zig(void);

/** Poll raw touch during deep-sleep loop (no LVGL). */
bool modulus_touch_poll_pressed(void);

/** Adopt the BSP's esp_lcd_touch handle from the LVGL indev and remove the
 *  indev. Non-ZIG_UI path only. */
bool modulus_touch_adopt_handle(void);

/** ZIG_UI: create the sole esp_lcd_touch handle via bsp_touch_new().
 *  Called from modulus_display_init; no LVGL indev exists in that build. */
bool modulus_touch_create_handle(void);

/** Zig UI: landscape logical coords (1280×720). Panel→logical via LVGL ROT_90. */
void modulus_touch_poll_for_zig(int32_t *x, int32_t *y, int *pressed);

#ifdef __cplusplus
}
#endif
