#pragma once

#include "ui_shim.h"

#ifdef __cplusplus
extern "C" {
#endif

/** HOLD blocking modal; ALARM uses sticky snackbar (no overlay). */
void modulus_ui_state_modal_update(const modulus_cnc_status_t *st);
void modulus_ui_state_modal_hide(void);
void modulus_ui_state_modal_theme_refresh(void);
bool modulus_ui_state_modal_visible(void);

#ifdef __cplusplus
}
#endif
