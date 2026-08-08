#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* C++ widget_dro: confirm only when MachineState::Run (state == 2). */
bool modulus_ui_zero_needs_confirm(uint8_t machine_state);
bool modulus_ui_zero_confirm_visible(void);

void modulus_ui_zero_axis_request(uint8_t axis_idx, uint8_t machine_state);
void modulus_ui_zero_all_request(uint8_t machine_state);

#ifdef __cplusplus
}
#endif
