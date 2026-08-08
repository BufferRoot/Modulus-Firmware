#pragma once

#include "ui_shim.h"
#include "ui_icons.h"
#include "cnc_cmd_exports.h"

#include <lvgl.h>

bool modulus_ui_is_dark_mode(void);
const char *modulus_ui_accent_name(uint8_t idx);
uint8_t modulus_ui_get_accent(void);
void modulus_ui_theme_apply(void);
/** Runtime WCAG AA spot-check of active palette (surface + primary + semantics). */
bool modulus_ui_theme_contrast_ok(void);
void modulus_ui_set_dashboard_refresh_hz(uint8_t refr_hz);
void modulus_ui_dashboard_set_left_handed(bool left);
void modulus_ui_dashboard_config_changed(void);
lv_color_t modulus_ui_color_surface(void);
lv_color_t modulus_ui_color_primary(void);
lv_color_t modulus_ui_color_on_primary(void);
lv_color_t modulus_ui_color_accent(void);
lv_color_t modulus_ui_color_on_accent(void);
lv_color_t modulus_ui_color_cycle(void);
lv_color_t modulus_ui_color_hold(void);
lv_color_t modulus_ui_color_home_all(void);
lv_color_t modulus_ui_color_surface_dim(void);
lv_color_t modulus_ui_color_on_surface(void);
lv_color_t modulus_ui_color_on_surface_variant(void);
lv_color_t modulus_ui_color_outline(void);
lv_color_t modulus_ui_color_outline_variant(void);

/* MD3 + Expressive shape tokens (dp on 1280x720 Tab5 panel) */
#define MOD_UI_SHAPE_XS        4
#define MOD_UI_SHAPE_SM        8
#define MOD_UI_SHAPE_MD        12
#define MOD_UI_SHAPE_LG        16
#define MOD_UI_SHAPE_LG_INC    20  /* large-increased */
#define MOD_UI_SHAPE_XL        28
#define MOD_UI_SHAPE_XXL       32  /* extra-large-increased */
#define MOD_UI_SHAPE_XXXL      48  /* extra-extra-large */
#define MOD_UI_SHAPE_FULL      9999
#define MOD_UI_SHAPE_CARD      MOD_UI_SHAPE_MD
#define MOD_UI_SHAPE_DIALOG    MOD_UI_SHAPE_XL
#define MOD_UI_SHAPE_SHEET     MOD_UI_SHAPE_XXXL

/* MD3 8dp spacing grid */
#define MOD_UI_SPACE_XS  4
#define MOD_UI_SPACE_SM  8
#define MOD_UI_SPACE_MD  16
#define MOD_UI_SPACE_LG  24
#define MOD_UI_SPACE_XL  32

/* Tonal elevation → surface step (no shadows by default) */
#define MOD_UI_ELEV_0 modulus_ui_color_surface()
#define MOD_UI_ELEV_1 modulus_ui_color_surface_container_low()
#define MOD_UI_ELEV_2 modulus_ui_color_surface_container()
#define MOD_UI_ELEV_3 modulus_ui_color_surface_container_high()
#define MOD_UI_ELEV_4 modulus_ui_color_surface_container_highest()

/* Opaque full-screen scrim — LV_OPA_COVER only; never translucent under Tab5
 * sw_rotate (compositing WDT). Intentional fork from MD3 32% black scrim. */
#define MOD_UI_SCRIM_OPA LV_OPA_COVER
#define MOD_UI_TOUCH_MIN 48

/* Dialog width tokens (dp @ 1280 landscape) */
#define MOD_UI_DIALOG_W_COMPACT  420
#define MOD_UI_DIALOG_W_STANDARD 520
#define MOD_UI_DIALOG_W_WIDE     600
#define MOD_UI_DIALOG_W_XWIDE    720
#define MOD_UI_CONTENT_MAX_W     960

/* MD3 state layer — 12% content opacity on press (no per-tick invalidation) */
#define MOD_UI_STATE_LAYER_PRESSED 31

/* MD3 typography roles -> Montserrat tiers enabled in sdkconfig */
#define MOD_UI_FONT_DISPLAY_L  &lv_font_montserrat_44
#define MOD_UI_FONT_DISPLAY_M  &lv_font_montserrat_36
#define MOD_UI_FONT_DISPLAY_S  &lv_font_montserrat_24
#define MOD_UI_FONT_HEADLINE_L &lv_font_montserrat_28
#define MOD_UI_FONT_HEADLINE_M &lv_font_montserrat_22
#define MOD_UI_FONT_HEADLINE_S &lv_font_montserrat_16
#define MOD_UI_FONT_TITLE_L    &lv_font_montserrat_24
#define MOD_UI_FONT_TITLE_M    &lv_font_montserrat_22
#define MOD_UI_FONT_TITLE_S    &lv_font_montserrat_18
#define MOD_UI_FONT_BODY_L     &lv_font_montserrat_16
#define MOD_UI_FONT_BODY_M     &lv_font_montserrat_14
#define MOD_UI_FONT_BODY_S     &lv_font_montserrat_12
#define MOD_UI_FONT_LABEL_L    &lv_font_montserrat_14
#define MOD_UI_FONT_LABEL_M    &lv_font_montserrat_12
#define MOD_UI_FONT_CAPTION    MOD_UI_FONT_LABEL_L
#define MOD_UI_FONT_SPLASH     &lv_font_montserrat_44

/* grblHAL machine states (C++ MachineState / bar_state_name) */
enum {
    MOD_UI_MACH_IDLE = 1,
    MOD_UI_MACH_RUN  = 2,
    MOD_UI_MACH_HOLD = 3,
    MOD_UI_MACH_JOG  = 4,
};
lv_color_t modulus_ui_color_error(void);
lv_color_t modulus_ui_color_on_error(void);
lv_color_t modulus_ui_color_success(void);
lv_color_t modulus_ui_color_warning(void);
lv_color_t modulus_ui_color_neutral(void);
lv_color_t modulus_ui_color_inverse_surface(void);
lv_color_t modulus_ui_color_on_cycle(void);
lv_color_t modulus_ui_color_on_hold(void);
lv_color_t modulus_ui_color_on_home(void);
lv_color_t modulus_ui_color_icon_chrome(void);
lv_color_t modulus_ui_color_on_tinted_btn(void);
lv_color_t modulus_ui_color_primary_container(void);
lv_color_t modulus_ui_color_on_primary_container(void);
lv_color_t modulus_ui_color_tertiary(void);
lv_color_t modulus_ui_color_on_tertiary(void);
lv_color_t modulus_ui_color_surface_container_lowest(void);
lv_color_t modulus_ui_color_surface_container_low(void);
lv_color_t modulus_ui_color_surface_container(void);
lv_color_t modulus_ui_color_surface_container_high(void);
lv_color_t modulus_ui_color_surface_container_highest(void);
lv_color_t modulus_ui_color_scrim(void);
lv_color_t modulus_ui_color_secondary(void);
lv_color_t modulus_ui_color_on_secondary(void);
lv_color_t modulus_ui_color_secondary_container(void);
lv_color_t modulus_ui_color_on_secondary_container(void);
lv_color_t modulus_ui_color_tertiary_container(void);
lv_color_t modulus_ui_color_on_tertiary_container(void);
lv_color_t modulus_ui_color_error_container(void);
lv_color_t modulus_ui_color_on_error_container(void);
lv_color_t modulus_ui_color_inverse_on_surface(void);
lv_color_t modulus_ui_color_inverse_primary(void);
lv_color_t modulus_ui_color_surface_bright(void);
lv_color_t modulus_ui_color_semantic_stop(void);
lv_color_t modulus_ui_color_semantic_resume(void);
lv_color_t modulus_ui_color_semantic_power(void);

/* Industrial semantic colors — accent-independent contrast */
#define MOD_UI_COLOR_SEMANTIC_CYCLE  modulus_ui_color_cycle()
#define MOD_UI_COLOR_SEMANTIC_HOLD   modulus_ui_color_hold()
#define MOD_UI_COLOR_SEMANTIC_HOME   modulus_ui_color_home_all()
#define MOD_UI_COLOR_SEMANTIC_STOP   modulus_ui_color_semantic_stop()
#define MOD_UI_COLOR_SEMANTIC_RESUME modulus_ui_color_semantic_resume()
#define MOD_UI_COLOR_SEMANTIC_POWER  modulus_ui_color_semantic_power()

lv_color_t modulus_ui_color_opaque_scrim(void);

/* MD3 disabled content — per-leaf opacity, not parent group opa (LVGL WDT safe) */
#define MOD_UI_DISABLED_CONTENT_OPA 38

/* MD3 motion durations (ms) — translate/radius only, no full-screen opacity fades */
#define MOD_UI_MOTION_ENTER_MS        400
#define MOD_UI_MOTION_EXIT_MS         200
#define MOD_UI_MOTION_UTIL_MS         300
#define MOD_UI_MOTION_SETTINGS_MS     120
#define MOD_UI_MOTION_MORPH_MS        180
#define MOD_UI_MOTION_DIALOG_OFFSET   24
#define MOD_UI_MOTION_SHEET_SLIDE_PX  320

/** NVS `motion_scheme`: 0 = standard (default), 1 = expressive (springier). */
bool modulus_ui_motion_smooth(void);
bool modulus_ui_motion_expressive(void);
uint32_t modulus_ui_motion_spatial_ms(bool enter);
void modulus_ui_anim_translate_y(lv_obj_t *obj, lv_coord_t from, lv_coord_t to, uint32_t duration_ms,
                                bool decelerate, lv_anim_ready_cb_t ready_cb, void *user_data);
void modulus_ui_morph_radius(lv_obj_t *obj, lv_coord_t to_radius, uint32_t duration_ms);
/** Rest → press radius morph on PRESSED / RELEASED / PRESS_LOST. */
void modulus_ui_bind_press_morph(lv_obj_t *obj, lv_coord_t rest_r, lv_coord_t press_r);
void modulus_ui_motion_sheet_enter(lv_obj_t *panel, lv_coord_t slide_px);
void modulus_ui_motion_sheet_exit(lv_obj_t *panel, lv_coord_t slide_px, lv_anim_ready_cb_t ready_cb,
                                  void *user_data);
void modulus_ui_motion_dialog_enter(lv_obj_t *card);
void modulus_ui_motion_dialog_exit(lv_obj_t *card, lv_anim_ready_cb_t ready_cb, void *user_data);
void modulus_ui_motion_settings_enter(lv_obj_t *card);

void modulus_ui_apply_switch_theme(lv_obj_t *sw);
void modulus_ui_snackbar_show(const char *message, uint32_t duration_ms);
void modulus_ui_snackbar_show_action(const char *message, const char *action_label,
                                     uint32_t duration_ms, lv_event_cb_t action_cb,
                                     void *user_data);
/** duration_ms == 0 on show is sticky; hide clears sticky or transient. */
void modulus_ui_snackbar_hide(void);
bool modulus_ui_snackbar_is_sticky(void);

enum {
    MOD_UI_ICON_BTN_STANDARD = 0,
    MOD_UI_ICON_BTN_TONAL = 1,
    MOD_UI_ICON_BTN_OUTLINED = 2,
};
lv_obj_t *modulus_ui_icon_button_create(lv_obj_t *parent, modulus_ui_icon_id_t id, int variant,
                                        lv_event_cb_t cb, void *user_data);
lv_obj_t *modulus_ui_icon_button_create_sz(lv_obj_t *parent, modulus_ui_icon_id_t id,
                                           modulus_ui_icon_size_t sz, int variant,
                                           lv_event_cb_t cb, void *user_data);
lv_obj_t *modulus_ui_dialog_header(lv_obj_t *card, const char *title, lv_event_cb_t close_cb,
                                   void *user_data);
void modulus_ui_dialog_scrim_bind_dismiss(lv_obj_t *scrim, lv_event_cb_t cb, void *user_data);
/** Null *scrim_slot immediately; animate card exit then delete overlay. */
void modulus_ui_dialog_scrim_hide_animated(lv_obj_t **scrim_slot);
/** Focus ring uses outline (not outline-variant) for encoder/keyboard focus. */
void modulus_ui_apply_focus_ring(lv_obj_t *obj);
lv_obj_t *modulus_ui_linear_progress_create(lv_obj_t *parent);
void modulus_ui_linear_progress_set(lv_obj_t *bar, int32_t pct);
lv_obj_t *modulus_ui_list_item_create(lv_obj_t *parent, modulus_ui_icon_id_t leading,
                                      const char *primary, const char *supporting,
                                      lv_event_cb_t cb, void *user_data);
lv_obj_t *modulus_ui_menu_show(lv_obj_t *anchor, const char *const *labels, uint8_t count,
                               lv_event_cb_t item_cb, void *user_data);
void modulus_ui_menu_hide(void);
void modulus_ui_tooltip_show(lv_obj_t *anchor, const char *text);
void modulus_ui_tooltip_bind_longpress(lv_obj_t *obj, const char *text);
void modulus_ui_touch_ensure_min(lv_obj_t *obj);

typedef struct {
    lv_obj_t *track;
    lv_obj_t *segments[8];
    uint8_t count;
    uint8_t selected;
    lv_event_cb_t user_cb;
    void *user_data;
} modulus_ui_segmented_t;

typedef struct {
    lv_obj_t *row;
    lv_obj_t *segments[8];
    uint8_t count;
    uint8_t selected;
    lv_event_cb_t user_cb;
} modulus_ui_chip_group_t;

lv_obj_t *modulus_ui_segmented_create(lv_obj_t *parent, const char *const *labels, uint8_t count,
                                      lv_coord_t seg_w, lv_event_cb_t cb, void *user_data);
void modulus_ui_segmented_set_selected(lv_obj_t *track, uint8_t idx);
uint8_t modulus_ui_segmented_get_selected(lv_obj_t *track);
lv_obj_t *modulus_ui_segmented_get_segment(lv_obj_t *track, uint8_t idx);

lv_obj_t *modulus_ui_filter_chip_group_create(lv_obj_t *parent, lv_coord_t seg_h,
                                              lv_event_cb_t cb);
lv_obj_t *modulus_ui_filter_chip_add(lv_obj_t *group, const char *label, void *user_data);
lv_obj_t *modulus_ui_filter_chip_add_stacked(lv_obj_t *group, const char *primary, const char *secondary,
                                             void *user_data);
void modulus_ui_filter_chip_set_selected(lv_obj_t *group, uint8_t idx);
uint8_t modulus_ui_filter_chip_get_selected(lv_obj_t *group);

void modulus_ui_row_set_content_enabled(lv_obj_t *row, bool enabled);
void modulus_ui_settings_row_set_enabled(lv_obj_t *row, lv_obj_t *ctrl, bool enabled);
void modulus_ui_obj_set_disabled_style(lv_obj_t *obj, bool enabled);
void modulus_ui_label_set_text_if_changed(lv_obj_t *lbl, const char *text);
void modulus_ui_label_set_text_cached(lv_obj_t *lbl, char *cache, size_t cache_len,
                                    const char *text);
lv_obj_t *modulus_ui_flex_row_create(lv_obj_t *parent, lv_coord_t h, bool space_between);
void modulus_ui_apply_overlay_scrim(lv_obj_t *obj);
void modulus_ui_apply_pressed_state_layer(lv_obj_t *obj);
void modulus_ui_apply_pressed_state_layer_color(lv_obj_t *obj, lv_color_t layer_color);
void modulus_ui_apply_keyboard_theme(lv_obj_t *kb);
void modulus_ui_apply_textarea_theme(lv_obj_t *ta, bool readonly);
void modulus_ui_apply_slider_theme(lv_obj_t *sl);
void modulus_ui_apply_dropdown_theme(lv_obj_t *dd);
void modulus_ui_keyboards_theme_refresh(void);
void settings_cnc_masso_kb_theme_refresh(void);
void settings_dashboard_kb_theme_refresh(void);
void settings_wireless_inline_kb_theme_refresh(void);
void settings_machine_svc_kb_theme_refresh(void);
void modulus_ui_cnc_profiles_kb_theme_refresh(void);
void modulus_ui_touch_scroll_tune(void);
lv_obj_t *modulus_ui_filled_button_create(lv_obj_t *parent, lv_coord_t w, lv_coord_t h);
lv_obj_t *modulus_ui_tonal_button_create(lv_obj_t *parent, lv_coord_t w, lv_coord_t h);
lv_obj_t *modulus_ui_dialog_card_create(lv_obj_t *parent, lv_coord_t w, lv_coord_t h);
void modulus_ui_dialog_card_apply(lv_obj_t *card);
lv_obj_t *modulus_ui_dialog_scrim_create(void);
void modulus_ui_dialog_theme_refresh(lv_obj_t *scrim);
lv_obj_t *modulus_ui_dialog_title(lv_obj_t *card, const char *text);
lv_obj_t *modulus_ui_dialog_supporting(lv_obj_t *card, const char *text);
lv_obj_t *modulus_ui_dialog_actions(lv_obj_t *card, bool end_align);
lv_obj_t *modulus_ui_dialog_action_btn(lv_obj_t *row, const char *label, int kind,
                                       lv_event_cb_t cb, void *user_data);
enum {
    MOD_UI_DIALOG_BTN_TONAL = 0,
    MOD_UI_DIALOG_BTN_FILLED = 1,
    MOD_UI_DIALOG_BTN_DESTRUCTIVE = 2,
    MOD_UI_DIALOG_BTN_TEXT = 3,
};
void modulus_ui_style_filled_button(lv_obj_t *btn);
void modulus_ui_style_tonal_button(lv_obj_t *btn);
void modulus_ui_touch_expand(lv_obj_t *obj, lv_coord_t pad);
void modulus_ui_bind_menu_click(lv_obj_t *obj, lv_event_cb_t cb, void *user_data);
void settings_modals_theme_refresh(void);
void settings_time_modal_theme_refresh(void);

void modulus_ui_dashboard_theme_refresh(void);
void modulus_ui_status_bar_theme_refresh(void);
void modulus_ui_actions_theme_refresh(void);
void modulus_ui_job_progress_create(lv_obj_t *parent);
void modulus_ui_job_progress_update(const modulus_cnc_status_t *status);
void modulus_ui_job_progress_theme_refresh(void);
bool modulus_ui_job_progress_visible(void);
void modulus_ui_state_modal_update(const modulus_cnc_status_t *status);
void modulus_ui_state_modal_theme_refresh(void);
bool modulus_ui_state_modal_visible(void);
void modulus_ui_dro_theme_refresh(void);
void modulus_ui_jog_theme_refresh(void);
void modulus_ui_overrides_theme_refresh(void);
void modulus_ui_settings_theme_refresh(void);
void modulus_ui_quick_settings_theme_refresh(void);
void modulus_ui_pin_theme_refresh(void);
void modulus_ui_power_menu_theme_refresh(void);
void modulus_ui_wireless_theme_refresh(void);

void modulus_ui_boot_create(void);
void modulus_ui_boot_arm_transition(void);
void modulus_ui_status_bar_create(lv_obj_t *parent);
void modulus_ui_status_bar_update(const modulus_cnc_status_t *status);
void modulus_ui_status_bar_invalidate(void);
void modulus_ui_jog_create(lv_obj_t *parent);
void modulus_ui_jog_update(const modulus_cnc_status_t *status);
void modulus_ui_jog_apply_config(void);
void modulus_ui_jog_invalidate(void);
void modulus_ui_actions_create(lv_obj_t *parent);
void modulus_ui_actions_rebuild(void);
void modulus_ui_actions_update(const modulus_cnc_status_t *status);
void modulus_ui_dro_create(lv_obj_t *parent);
void modulus_ui_dro_update(const modulus_cnc_status_t *status);
void modulus_ui_dro_apply_config(void);
void modulus_ui_overrides_create(lv_obj_t *parent);
void modulus_ui_overrides_update(const modulus_cnc_status_t *status);
void modulus_ui_settings_show(void);
void modulus_ui_settings_hide(void);
void modulus_ui_settings_select_tab(int idx);
bool modulus_ui_settings_visible(void);
void modulus_ui_show_settings(void);
void modulus_ui_hide_settings(void);
void modulus_ui_pause_dashboard_refresh(void);
void modulus_ui_resume_dashboard_refresh(void);
void modulus_ui_show_quick_settings(void);
void modulus_ui_hide_quick_settings(void);
bool modulus_ui_quick_settings_visible(void);
void modulus_ui_prewarm_power_menu(void);
void modulus_ui_show_power_menu(void);
void modulus_ui_hide_power_menu(void);
bool modulus_ui_power_menu_visible(void);
void modulus_ui_dashboard_create(void);
void modulus_ui_dashboard_update(const modulus_cnc_status_t *status);
void modulus_ui_pin_show(void);
void modulus_ui_pin_hide(void);
bool modulus_ui_pin_visible(void);
lv_obj_t *modulus_ui_dashboard_screen(void);
