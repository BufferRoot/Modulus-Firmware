#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void modulus_ui_cnc_profile_save_slot(uint8_t slot, const char *name);
void modulus_ui_cnc_profile_activate(uint8_t slot);
void modulus_ui_cnc_profile_clear(uint8_t slot);
void modulus_ui_cnc_profile_rename(uint8_t slot, const char *name);
void modulus_ui_cnc_profile_rename_show(uint8_t slot);
bool modulus_ui_cnc_profile_name(uint8_t slot, char *out, size_t out_len);
void modulus_ui_cnc_profile_boot_apply(void);
void modulus_ui_cnc_profiles_modal_show(void);
void modulus_ui_cnc_profiles_modal_hide(void);

#ifdef __cplusplus
}
#endif
