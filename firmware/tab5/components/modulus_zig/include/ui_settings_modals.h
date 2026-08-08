#pragma once

#include <stdint.h>
#include <lvgl.h>

#ifdef __cplusplus
extern "C" {
#endif

void settings_transport_modal_show(uint8_t conn_idx);
void settings_transport_modal_hide(void);
void settings_pin_modal_show_set(void);
void settings_pin_modal_show_change(void);
void settings_pin_modal_show_clear(void);
void settings_pin_modal_hide(void);
void settings_incr_modal_show(void);
void settings_incr_modal_hide(void);
void settings_macro_modal_show(void);
void settings_macro_modal_hide(void);
/** slot < 0 = add to first free; else edit that custom button. */
void settings_macro_slot_modal_show(int8_t slot);
void settings_macro_slot_modal_hide(void);
void settings_mach_name_modal_show(void);
void settings_mach_name_modal_hide(void);
void settings_qbtn_modal_show(void);
void settings_qbtn_modal_hide(void);
void settings_grbl_dump_modal_show(void);
void settings_grbl_dump_modal_hide(void);
void settings_wcs_modal_show(void);
void settings_wcs_modal_hide(void);
void settings_mpg_modal_show(void);
void settings_mpg_modal_hide(void);
void settings_maint_modal_show(void);
void settings_maint_modal_hide(void);
void settings_wl_adv_modal_show(int kind);
void settings_wl_adv_modal_hide(void);
void settings_wl_adv_modal_open_cb(lv_event_t *e);
void settings_idle_lock_modal_show(void);
void settings_idle_lock_modal_hide(void);
void settings_probe_modal_show(void);
void settings_probe_modal_hide(void);

#ifdef __cplusplus
}
#endif
