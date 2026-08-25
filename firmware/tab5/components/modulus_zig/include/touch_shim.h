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

/** Zig UI: landscape logical coords (1280×720). Panel→logical via LVGL ROT_90. */
void modulus_touch_poll_for_zig(int32_t *x, int32_t *y, int *pressed);

#ifdef __cplusplus
}
#endif
