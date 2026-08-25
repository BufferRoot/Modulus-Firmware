#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint8_t state;
    uint8_t connected;
    uint8_t session;
    uint8_t mpg_active;
    uint8_t jog_mode;
    uint8_t step_size;
    float wpos_x;
    float wpos_y;
    float wpos_z;
    float wpos_a;
    float wpos_b;
    float wpos_c;
    float feed_rate;
    uint8_t feed_ovr;
    uint8_t spindle_ovr;
    uint8_t rapid_ovr;
    uint8_t wcs;
    uint8_t tool_number;
    uint8_t active_axis;
    uint8_t units_mm;
    uint32_t spindle_rpm;
    float mpos_x;
    float mpos_y;
    float mpos_z;
    float mpos_a;
    float mpos_b;
    float mpos_c;
    uint8_t homing_block;
    uint8_t accessories; /* grblHAL A tag: S/C/M/F bits — quick-button active state */
    float sd_percent; /* job progress 0..100 when streaming */
    uint32_t line_number;
    uint8_t sd_streaming;
    uint8_t alarm_code;
    char sd_file[32]; /* basename from SD:pct,path — empty if unknown */
} modulus_cnc_status_t;

void modulus_zig_fill_cnc_status(modulus_cnc_status_t *out);

void modulus_ui_init(void);
void modulus_ui_show_boot_screen(void);
void modulus_ui_arm_boot_transition(void);
void modulus_ui_show_dashboard(void);
void modulus_ui_show_pin_lock(void);
void modulus_ui_hide_pin_lock(void);
bool modulus_ui_pin_lock_visible(void);
void modulus_ui_update_dashboard(const modulus_cnc_status_t *status);
void modulus_ui_on_deep_sleep(void);
void modulus_ui_on_wake(void);
void modulus_ui_on_cnc_status_event(void);
void modulus_ui_show_settings(void);
void modulus_ui_hide_settings(void);
bool modulus_ui_settings_open(void);
void modulus_ui_show_quick_settings(void);
void modulus_ui_hide_quick_settings(void);
void modulus_ui_show_power_menu(void);
void modulus_ui_hide_power_menu(void);

/** Current CPU core id (for AMP fences; wraps esp_cpu_get_core_id). */
unsigned modulus_amp_core_id(void);

#ifdef __cplusplus
}
#endif
