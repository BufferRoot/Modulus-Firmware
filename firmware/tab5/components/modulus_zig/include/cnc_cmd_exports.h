#pragma once

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void modulus_zig_cmd_cycle_start(void);
void modulus_zig_cmd_feed_hold(void);
void modulus_zig_cmd_home_all(void);
void modulus_zig_cmd_reset(void);
void modulus_zig_cmd_unlock(void);
void modulus_zig_cmd_stop(void);
void modulus_zig_cmd_mpg_toggle(void);
uint8_t modulus_zig_mpg_remote(void);
void modulus_zig_set_jog_mode(uint8_t mode);
void modulus_zig_reload_machine_limits(void);
uint8_t modulus_zig_envelope_pull_apply(void);
void modulus_zig_cmd_send_gcode(const uint8_t *data, size_t len);
/* Terminal console tap: pop one line (dir 0=rx from controller, 1=tx to it).
 * Returns line length or -1 when empty — drain until -1 each UI tick. */
int32_t modulus_zig_console_pop(uint8_t *dir_out, uint8_t *out, size_t cap);
/* Probe input pin from the last status report (|Pn:P): 1=triggered, 0=open. */
uint8_t modulus_zig_probe_pin(void);
/* PRB: probe engine — multi-touch cycles with coordinate readback (grblHAL). */
uint8_t modulus_zig_probe_start(uint8_t cycle);
void modulus_zig_probe_cancel(void);
uint8_t modulus_zig_probe_busy(void);
#define MODULUS_PROBE_Z_PLATE     0
#define MODULUS_PROBE_EDGE_X_NEG  1
#define MODULUS_PROBE_EDGE_Y_NEG  2
#define MODULUS_PROBE_CENTER      3
#define MODULUS_PROBE_EDGE_180_X  4
#define MODULUS_PROBE_TOOL_SETTER 5
void modulus_zig_set_wcs(uint8_t idx);
void modulus_zig_set_units_mm(uint8_t mm);
void modulus_zig_set_step_size(uint8_t idx);
void modulus_zig_cmd_feed_override(int8_t delta);
void modulus_zig_cmd_spindle_override(int8_t delta);
void modulus_zig_cmd_rapid_override(uint8_t pct);
void modulus_zig_cmd_home_axis(uint8_t axis_idx);
void modulus_zig_cmd_zero_axis(uint8_t axis_idx);
void modulus_zig_cmd_zero_all(void);
void modulus_zig_cycle_wcs(void);
void modulus_zig_set_active_axis(uint8_t axis_idx);
void modulus_zig_cmd_spindle_toggle(void);
void modulus_zig_cmd_spindle_cw(void);
void modulus_zig_cmd_spindle_ccw(void);
void modulus_zig_cmd_run_macro(void);
void modulus_zig_cmd_coolant_toggle(void);
void modulus_zig_cmd_mist_toggle(void);
void modulus_zig_cmd_fan_toggle(void);
void modulus_zig_cmd_single_step(void);
void modulus_zig_transport_reinit(void);
/** Wire Zig CNC send path after C-layer ESP-NOW transport is already open. */
void modulus_zig_transport_espnow_attach(void);
/** Reload handwheel NVS cache (encdiv, mpgpol, jogspd) after settings writes. */
void modulus_zig_encoder_reload_settings(void);
/** Reload work-envelope limits after Machine tab NVS writes. */
void modulus_zig_limits_reload(void);
/** grbl $$ settings dump for on-device browser. */
void modulus_zig_settings_dump_begin(void);
void modulus_zig_settings_dump_cancel(void);
/** 1 = ready / failed (c_int — Zig/RISC-V bool ABI). */
int modulus_zig_settings_dump_ready(void);
int modulus_zig_settings_dump_failed(void);
size_t modulus_zig_settings_dump_copy(char *dst, size_t cap);
/** Push max feed ($110-$112) and max spindle ($30) to controller. */
void modulus_zig_sync_envelope(void);

/** Reset pendant maintenance meters (travel / spindle / run) and clear warn latches. */
void modulus_zig_maint_reset_counters(void);
void modulus_zig_maint_flush(void);

/** Active `cnc_conn` transport index, or 0xFF when stopped. */
uint8_t modulus_zig_active_transport(void);

#ifdef __cplusplus
}
#endif
