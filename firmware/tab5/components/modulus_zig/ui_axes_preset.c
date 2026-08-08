#include "ui_axes_preset.h"

uint8_t modulus_ui_axes_preset_normalize(uint8_t raw)
{
    if (raw <= 4) {
        return raw;
    }
    /* Legacy Zig firmware stored visible axis count (2-6) instead of preset. */
    if (raw >= 2 && raw <= 6) {
        return (uint8_t)(raw - 2);
    }
    return 2;
}

uint8_t modulus_ui_axes_visible_count(uint8_t raw_preset)
{
    static const uint8_t k_counts[] = {2, 3, 4, 5, 6};
    const uint8_t preset = modulus_ui_axes_preset_normalize(raw_preset);
    return k_counts[preset < 5 ? preset : 2];
}
