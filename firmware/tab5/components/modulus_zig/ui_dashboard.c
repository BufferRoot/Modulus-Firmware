#include "ui_internal.h"
#include "ui_shim.h"
#include "ui_job_progress.h"
#include "ui_state_modal.h"
#include "nvs_shim.h"

#include <stdio.h>

static lv_obj_t *s_scr = NULL;
static lv_obj_t *s_main_row = NULL;
static lv_obj_t *s_dro_panel = NULL;

void modulus_ui_dashboard_create(void)
{
    if (s_scr) {
        return;
    }

    s_scr = lv_obj_create(NULL);
    lv_obj_set_size(s_scr, lv_pct(100), lv_pct(100));
    lv_obj_set_style_bg_color(s_scr, modulus_ui_color_surface_dim(), 0);
    lv_obj_set_style_bg_opa(s_scr, LV_OPA_COVER, 0);
    lv_obj_set_style_pad_all(s_scr, 0, 0);
    lv_obj_set_flex_flow(s_scr, LV_FLEX_FLOW_COLUMN);
    lv_obj_remove_flag(s_scr, LV_OBJ_FLAG_SCROLLABLE);

    modulus_ui_status_bar_create(s_scr);
    modulus_ui_job_progress_create(s_scr);

    lv_obj_t *main = lv_obj_create(s_scr);
    s_main_row = main;
    lv_obj_remove_style_all(main);
    lv_obj_set_width(main, lv_pct(100));
    lv_obj_set_flex_grow(main, 1);
    lv_obj_set_style_pad_all(main, MOD_UI_SPACE_LG, 0);
    lv_obj_set_flex_flow(main,
                         modulus_nvs_get_u8("lefty", 0) != 0 ? LV_FLEX_FLOW_ROW_REVERSE
                                                             : LV_FLEX_FLOW_ROW);
    lv_obj_set_style_pad_column(main, MOD_UI_SPACE_LG, 0);
    lv_obj_remove_flag(main, LV_OBJ_FLAG_SCROLLABLE);

    s_dro_panel = lv_obj_create(main);
    lv_obj_remove_style_all(s_dro_panel);
    lv_obj_set_width(s_dro_panel, 420);
    lv_obj_set_height(s_dro_panel, lv_pct(100));
    lv_obj_remove_flag(s_dro_panel, LV_OBJ_FLAG_SCROLLABLE);
    modulus_ui_dro_create(s_dro_panel);

    lv_obj_t *center = lv_obj_create(main);
    lv_obj_remove_style_all(center);
    lv_obj_remove_flag(center, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_flex_grow(center, 1);
    lv_obj_set_height(center, lv_pct(100));
    lv_obj_set_flex_flow(center, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_style_pad_row(center, MOD_UI_SPACE_LG, 0);
    modulus_ui_jog_create(center);
    modulus_ui_overrides_create(center);

    lv_obj_t *actions_col = lv_obj_create(main);
    lv_obj_remove_style_all(actions_col);
    lv_obj_set_width(actions_col, 280);
    lv_obj_set_height(actions_col, lv_pct(100));
    lv_obj_remove_flag(actions_col, LV_OBJ_FLAG_SCROLLABLE);
    modulus_ui_actions_create(actions_col);
}

lv_obj_t *modulus_ui_dashboard_screen(void)
{
    return s_scr;
}

void modulus_ui_dashboard_set_left_handed(bool left)
{
    if (!s_main_row) {
        return;
    }
    lv_obj_set_flex_flow(s_main_row, left ? LV_FLEX_FLOW_ROW_REVERSE : LV_FLEX_FLOW_ROW);
}

void modulus_ui_dashboard_config_changed(void)
{
    modulus_ui_jog_apply_config();
    modulus_ui_dro_apply_config();
    modulus_ui_actions_rebuild();
    modulus_ui_jog_invalidate();
    modulus_ui_status_bar_invalidate();

    modulus_cnc_status_t st = {};
    modulus_zig_fill_cnc_status(&st);
    modulus_ui_status_bar_update(&st);
    modulus_ui_jog_update(&st);
    modulus_ui_dro_update(&st);
}

void modulus_ui_dashboard_theme_refresh(void)
{
    if (!s_scr) {
        return;
    }
    lv_obj_set_style_bg_color(s_scr, modulus_ui_color_surface_dim(), 0);
    modulus_ui_job_progress_theme_refresh();
    modulus_ui_state_modal_theme_refresh();
}

void modulus_ui_dashboard_update(const modulus_cnc_status_t *st)
{
    if (!s_scr || !st) {
        return;
    }
    modulus_ui_status_bar_update(st);
    modulus_ui_job_progress_update(st);
    modulus_ui_jog_update(st);
    modulus_ui_dro_update(st);
    modulus_ui_overrides_update(st);
    modulus_ui_actions_update(st);
    modulus_ui_state_modal_update(st);
}
