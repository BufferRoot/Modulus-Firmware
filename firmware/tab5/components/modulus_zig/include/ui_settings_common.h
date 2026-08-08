#pragma once

#include <lvgl.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Cross-tab navigation (settings shell must be open). */
void modulus_ui_settings_select_tab(int idx);

/* Generic destructive/action confirm overlay (MD3 scrim @ 60%, pause-gated). */
typedef void (*settings_confirm_fn)(void);
void settings_confirm_hide(void);
void settings_confirm_theme_refresh(void);
void settings_confirm_show(const char *title, const char *body,
                           const char *confirm_label, bool destructive,
                           settings_confirm_fn on_confirm,
                           settings_confirm_fn on_cancel);

/* Extra row types matching C++ screen_settings_common. */
lv_obj_t *settings_back_row(lv_obj_t *parent, const char *title, lv_event_cb_t cb);
lv_obj_t *settings_coming_soon_row(lv_obj_t *parent, const char *label);
lv_obj_t *settings_not_implemented_row(lv_obj_t *parent, const char *label,
                                       const char *status);
lv_obj_t *settings_link_tab_row(lv_obj_t *parent, const char *label,
                                const char *value, int target_tab);
typedef struct {
    const char *title;
    const char *body;
    settings_confirm_fn fn;
} settings_reset_ctx_t;

lv_obj_t *settings_reset_row(lv_obj_t *parent, const char *label,
                             settings_reset_ctx_t *ctx);

/* Expandable reference block — toggles *expanded flag and calls rebuild_fn. */
typedef void (*settings_rebuild_fn)(void);
lv_obj_t *settings_expandable_link(lv_obj_t *parent, const char *show_label,
                                   const char *hide_label, bool *expanded,
                                   settings_rebuild_fn rebuild_fn);

const char *settings_baud_str(uint8_t idx);

#define SETTINGS_CNC_TRANSPORT_COUNT 8
#define SETTINGS_CNC_XPORT_DEFAULT   4
#define SETTINGS_CNC_XPORT_OFF       255

#define SETTINGS_CNC_PROTOCOL_COUNT 6
#define SETTINGS_CNC_PROTO_DEFAULT  0
#define SETTINGS_CNC_PROTO_GRBL       1
#define SETTINGS_CNC_PROTO_FLUIDNC    2
#define SETTINGS_CNC_PROTO_LINUXCNC   3
#define SETTINGS_CNC_PROTO_MACH3      4
#define SETTINGS_CNC_PROTO_MASSO      5

const char *settings_cnc_transport_name(uint8_t idx);
const char *settings_cnc_transport_dropdown_opts(void);
const char *settings_cnc_protocol_name(uint8_t idx);
const char *settings_cnc_protocol_dropdown_opts(void);
bool settings_cnc_protocol_implemented(uint8_t idx);
/** True when Settings browser ($$) / envelope pull apply (Grbl-family). */
bool settings_cnc_protocol_supports_dump(uint8_t idx);
bool settings_cnc_protocol_supports_envelope_paste(uint8_t idx);
/** Preferred transport index for MCS (UI hint). */
uint8_t settings_cnc_protocol_preferred_transport(uint8_t idx);

#define SETTINGS_MACRO_SLOTS 4
/** Load custom button. `icon_out` may be NULL (defaults MOD_UI_ICON_SCROLL when unset). */
bool settings_macro_slot_load(uint8_t slot, char *name, size_t name_len,
                              char *on, size_t on_len, char *off, size_t off_len,
                              uint8_t *icon_out);
bool settings_macro_slot_save(uint8_t slot, const char *name, const char *on, const char *off,
                              uint8_t icon);
void settings_macro_slot_clear(uint8_t slot);
int settings_macro_slot_first_free(void);

#ifdef __cplusplus
}
#endif
