#pragma once

#include "ui_shim.h"
#include <lvgl.h>

#ifdef __cplusplus
extern "C" {
#endif

void modulus_ui_job_progress_create(lv_obj_t *parent);
void modulus_ui_job_progress_update(const modulus_cnc_status_t *st);
void modulus_ui_job_progress_theme_refresh(void);
bool modulus_ui_job_progress_visible(void);
/** Pause/resume indeterminate wave timer (overlay open / dashboard pause). */
void modulus_ui_job_progress_pause_wave(void);
void modulus_ui_job_progress_resume_wave(void);

#ifdef __cplusplus
}
#endif
