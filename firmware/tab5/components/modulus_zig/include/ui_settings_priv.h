#pragma once

#include "ui_internal.h"

#include <lvgl.h>
#include <stdbool.h>
#include <stdint.h>

/* Tab indices — must match k_tabs[] order in ui_settings.c. */
enum {
    MOD_UI_SETTINGS_TAB_CNC = 0,
    MOD_UI_SETTINGS_TAB_DASHBOARD = 1,
    MOD_UI_SETTINGS_TAB_DISPLAY = 2,
    MOD_UI_SETTINGS_TAB_AUDIO = 3,
    MOD_UI_SETTINGS_TAB_WIRELESS = 4,
    MOD_UI_SETTINGS_TAB_POWER = 5,
    MOD_UI_SETTINGS_TAB_SECURITY = 6,
    MOD_UI_SETTINGS_TAB_MACHINE = 7,
    MOD_UI_SETTINGS_TAB_STORAGE = 8,
    MOD_UI_SETTINGS_TAB_SYSTEM = 9,
    MOD_UI_SETTINGS_TAB_COUNT = 10,
};

/* Active content panel (set by the shell on tab switch). */
lv_obj_t *modulus_ui_settings_panel(void);
void modulus_ui_settings_set_content_panel(lv_obj_t *panel);
/* Cached panel slot for tab idx (lazy-create; safe from any tab context). */
lv_obj_t *modulus_ui_settings_tab_panel(int idx);
void modulus_ui_settings_note_tab_built(int idx);

/* Scroll tuning — lv_obj_create defaults include elastic+momentum+chain. */
void settings_tune_scroll_container(lv_obj_t *obj);
void settings_tune_sidebar_scroll(lv_obj_t *obj);
void settings_bind_menu_click(lv_obj_t *obj, lv_event_cb_t cb, void *user_data);
void settings_no_scroll(lv_obj_t *obj);

/* Status accent colors (mapped to M3 success/warning in ui_theme.c). */
#define SETTINGS_STATUS_OK    0
#define SETTINGS_STATUS_WARN  1
#define SETTINGS_STATUS_ERR   2
#define SETTINGS_STATUS_DIM   3
lv_color_t modulus_settings_status_color(int kind);
/* CNC transport idx 0..7; active=false -> muted on_surface_variant. */
lv_color_t modulus_settings_cnc_transport_color(uint8_t idx, bool active);

/* M3-style content helpers — mirror the C++ screen_settings_common.cpp set.
 * Every row is full-width, 48 px tall, with a hairline bottom divider. */
lv_obj_t *settings_row_base(lv_obj_t *parent, int height, bool clickable);
lv_obj_t *settings_row_label(lv_obj_t *row, const char *text);
void settings_section(lv_obj_t *parent, const char *title, const char *subtitle);
void settings_note(lv_obj_t *parent, const char *text);
lv_obj_t *settings_detail_row(lv_obj_t *parent, const char *label, const char *value);
lv_obj_t *settings_action_row(lv_obj_t *parent, const char *label, const char *value);
lv_obj_t *settings_destructive_row(lv_obj_t *parent, const char *label, const char *value);
lv_obj_t *settings_toggle_row(lv_obj_t *parent, const char *label, bool on);
lv_obj_t *settings_slider_row(lv_obj_t *parent, const char *label,
                              int32_t val, int32_t min_v, int32_t max_v);
lv_obj_t *settings_dropdown_row(lv_obj_t *parent, const char *label,
                                const char *options, uint16_t selected);
/* MD3 segmented buttons for 2-5 mutually exclusive instant-effect options.
 * Emits LV_EVENT_VALUE_CHANGED on the returned track; read the new value in
 * the callback with modulus_ui_segmented_get_selected(lv_event_get_target(e)).
 * Prefer this over settings_dropdown_row for small option sets — dropdowns
 * hide options and need two precise taps. */
lv_obj_t *settings_segmented_row(lv_obj_t *parent, const char *label,
                                 const char *const *labels, uint8_t count,
                                 uint8_t selected, lv_coord_t seg_w);
lv_obj_t *settings_text_input_row(lv_obj_t *parent, const char *label,
                                  const char *text, int max_len,
                                  const char *accepted);

/* Tab builders (one per sidebar entry). */
void modulus_ui_settings_build_cnc_tab(void);
void modulus_ui_settings_cnc_tab_stop_timer(void);
void modulus_ui_settings_cnc_tab_pause_activity(void);
void modulus_ui_settings_cnc_tab_resume_activity(void);
void modulus_ui_settings_cnc_on_status_event(void);
void modulus_ui_settings_build_dashboard_tab(void);
void modulus_ui_settings_dashboard_tab_stop(void);
void modulus_ui_settings_build_display_tab(void);
void modulus_ui_settings_build_audio_tab(void);
void modulus_ui_settings_audio_tab_pause_activity(void);
void modulus_ui_settings_build_wireless_tab(void);
void modulus_ui_settings_wireless_tab_stop_timer(void);
void modulus_ui_settings_wireless_tab_pause_activity(void);
void modulus_ui_settings_wireless_tab_resume_activity(void);
void modulus_ui_settings_build_power_tab(void);
void modulus_ui_settings_power_tab_stop_timer(void);
void modulus_ui_settings_power_tab_pause_activity(void);
void modulus_ui_settings_power_tab_resume_activity(void);
void modulus_ui_settings_build_security_tab(void);
void modulus_ui_settings_build_machine_tab(void);
void modulus_ui_settings_machine_tab_stop_timer(void);
void modulus_ui_settings_machine_tab_pause_activity(void);
void modulus_ui_settings_build_storage_tab(void);
void modulus_ui_settings_storage_tab_stop_timer(void);
void modulus_ui_settings_storage_tab_pause_activity(void);
void modulus_ui_settings_storage_tab_resume_activity(void);
void modulus_ui_settings_build_system_tab(void);
void modulus_ui_settings_system_tab_stop_timer(void);
void modulus_ui_settings_system_tab_pause_activity(void);
void modulus_ui_settings_system_tab_resume_activity(void);
void modulus_ui_settings_system_tab_refresh(void);
void modulus_ui_settings_wireless_open_espnow(void);
