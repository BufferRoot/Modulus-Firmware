#pragma once

#include <lvgl.h>

#ifdef __cplusplus
extern "C" {
#endif

void settings_modal_kb_configure_text(lv_obj_t *kb);
void settings_modal_kb_configure_number(lv_obj_t *kb);

/** Keep dialog card above docked keyboard; enable vertical scroll so Cancel/Save stay reachable. */
void settings_modal_fit_card_above_kb(lv_obj_t *card);

/** Shared keyboard for in-page textareas (search, settings_text_input_row). */
void settings_shell_kb_bind_textarea(lv_obj_t *ta);
void settings_shell_kb_hide(void);
void settings_shell_kb_theme_refresh(void);

#ifdef __cplusplus
}
#endif
