#pragma once

#include "ui_icons.h"

#include <lvgl.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    UI_QBTN_SPINDLE_CW = 0,
    UI_QBTN_SPINDLE_CCW,
    UI_QBTN_COOLANT,
    UI_QBTN_FAN,
    UI_QBTN_ZERO_ALL,
    UI_QBTN_MACRO,
    UI_QBTN_MIST,
    UI_QBTN_OFF,
    /* Custom aux / G-code buttons (NVS cnc_mac0..3). Keep OFF=7 for NVS compat. */
    UI_QBTN_USER0,
    UI_QBTN_USER1,
    UI_QBTN_USER2,
    UI_QBTN_USER3,
    /** Append-only — do not insert before OFF/USER (NVS assign ids). */
    UI_QBTN_SINGLE_STEP,
    UI_QBTN_ASSIGN_COUNT,
};

/** @deprecated Use UI_QBTN_ASSIGN_COUNT — kept for older call sites. */
#define UI_QBTN_COUNT UI_QBTN_ASSIGN_COUNT

#define UI_QBTN_MAX_SLOTS 4
#define UI_QBTN_USER_SLOTS 4

typedef struct {
    int slot;
    uint8_t assign;
} ui_qbtn_entry_t;

typedef struct {
    bool interactive;
    lv_event_cb_t click_cb;
    lv_obj_t *btn_by_slot[UI_QBTN_MAX_SLOTS];
    lv_obj_t *lbl_by_slot[UI_QBTN_MAX_SLOTS];
    lv_obj_t *icon_by_slot[UI_QBTN_MAX_SLOTS];
    int32_t panel_w;
    /** >0: fixed preview height (avoids lv_pct(100) collapse in modal). 0: live dashboard. */
    int32_t container_h;
} ui_qbtn_build_opts_t;

uint8_t ui_qbtn_slot_assign(int slot);
int ui_qbtn_collect_entries(ui_qbtn_entry_t *out, int max_out);
int ui_qbtn_active_count(void);

bool ui_qbtn_is_user(uint8_t assign);
int ui_qbtn_user_macro_slot(uint8_t assign);
bool ui_qbtn_user_latched(uint8_t assign);
void ui_qbtn_assign_label(uint8_t assign, char *buf, size_t buf_len);
void ui_qbtn_icon_label(uint8_t assign, modulus_ui_icon_id_t *icon_out, const char **text_out);
bool ui_qbtn_fire_user(uint8_t assign);
void ui_qbtn_build_grid(lv_obj_t *container, const ui_qbtn_entry_t *entries, int active_count,
                        ui_qbtn_build_opts_t *opts);
void ui_qbtn_build_preview(lv_obj_t *container, int32_t height);

#ifdef __cplusplus
}
#endif
