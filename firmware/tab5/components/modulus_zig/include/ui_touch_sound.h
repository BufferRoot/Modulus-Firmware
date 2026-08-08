#pragma once

#include <lvgl.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Register global pointer-indev touch tone callbacks (C++ ui_manager parity). */
void modulus_ui_touch_sound_register(void);

/** Skip UI_TICK for obj and ancestors (LV_OBJ_FLAG_USER_1). */
void modulus_ui_suppress_touch_tick(lv_obj_t *obj);

/** Play UI_TICK on CLICKED — dashboard buttons without indev CLICKED. */
void modulus_ui_add_click_feedback(lv_obj_t *obj);

#ifdef __cplusplus
}
#endif
