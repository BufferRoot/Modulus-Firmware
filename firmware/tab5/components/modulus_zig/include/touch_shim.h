#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void modulus_touch_init(void);
void modulus_touch_set_glove_mode(bool enabled);

/** Poll raw touch during deep-sleep loop (no LVGL). */
bool modulus_touch_poll_pressed(void);

#ifdef __cplusplus
}
#endif
