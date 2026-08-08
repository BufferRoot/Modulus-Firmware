#pragma once

#include <stdint.h>

/* NVS `cnc_axes` stores C++ AxesPreset enum (0=XY .. 4=XYZABC). Legacy Zig builds
 * wrote axis counts 2-6; normalize before use. */
uint8_t modulus_ui_axes_preset_normalize(uint8_t raw);
uint8_t modulus_ui_axes_visible_count(uint8_t raw_preset);
