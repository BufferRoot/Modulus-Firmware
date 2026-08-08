#pragma once

#include "ui_internal.h"

typedef enum {
    PWR_CONFIRM_RESTART = 0,
    PWR_CONFIRM_SHUTDOWN,
} pwr_confirm_kind_t;

typedef struct {
    lv_obj_t *overlay;
    lv_obj_t *card;
    lv_obj_t *row_restart;
    lv_obj_t *row_shutdown;
} modulus_pwr_menu_t;

void modulus_pwr_show_confirm(pwr_confirm_kind_t kind, const char *title,
                              const char *body, const char *confirm_label,
                              bool destructive);
void modulus_pwr_hide_confirm(void);

void modulus_pwr_build_header(lv_obj_t *card);
lv_obj_t *modulus_pwr_section_title(lv_obj_t *parent, const char *text);
/* MD3 tonal action button (label + hint line). Destructive = error container. */
lv_obj_t *modulus_pwr_action_button(lv_obj_t *parent, const char *label,
                                    const char *hint, bool destructive,
                                    lv_event_cb_t cb);
void modulus_pwr_row_set_disabled(lv_obj_t *row, bool disabled);

void modulus_pwr_create_menu(modulus_pwr_menu_t *out, lv_event_cb_t hide_overlay_cb,
                             lv_event_cb_t card_click_cb, lv_event_cb_t reset_cb,
                             lv_event_cb_t unlock_cb,
                             lv_event_cb_t restart_cb, lv_event_cb_t shutdown_cb);
void modulus_pwr_update_device_rows(lv_obj_t *row_restart, lv_obj_t *row_shutdown,
                                    bool busy);
