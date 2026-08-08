#pragma once

#include <lvgl.h>

typedef struct {
    lv_obj_t *card;
    lv_obj_t *lbl_axis;
    lv_obj_t *lbl_active;
    lv_obj_t *lbl_work;
    lv_obj_t *lbl_unit;
    lv_obj_t *lbl_mach;
    lv_obj_t *btn_home;
    lv_obj_t *btn_zero;
} dro_axis_t;

void dro_build_axis_card(lv_obj_t *container, dro_axis_t *ac, int axis_idx, bool units_mm,
                         bool visible, int min_card_h, int btn_w, int btn_h,
                         lv_event_cb_t axis_cb, lv_event_cb_t home_cb, lv_event_cb_t zero_cb);
void dro_set_btn_enabled(lv_obj_t *btn, bool enabled);
