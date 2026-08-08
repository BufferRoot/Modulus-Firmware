#include "ui_settings_wireless_kb.h"
#include "ui_settings_priv.h"
#include "nvs_shim.h"

void wl_configure_connect_keyboard(lv_obj_t *kb)
{
    const bool full = modulus_nvs_get_u8("kb_full", 1) != 0;
    if (full) {
        lv_obj_set_size(kb, lv_pct(100), lv_pct(48));
        lv_obj_align(kb, LV_ALIGN_BOTTOM_MID, 0, 0);
    } else {
        lv_obj_set_size(kb, 560, 220);
        lv_obj_align(kb, LV_ALIGN_BOTTOM_MID, 0, -20);
    }
    modulus_ui_apply_keyboard_theme(kb);
}
