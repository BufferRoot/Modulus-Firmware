//! C ABI exports for ESP-IDF `firmware/tab5` link.

const std = @import("std");
const build_options = @import("build_options");
const device_runtime = @import("device_runtime.zig");
const device_ui_mod = @import("../ui/device_ui.zig");
const abi_guard = @import("abi_guard.zig");
const console_log_mod = @import("../cnc/console_log.zig");
const ota_mod = @import("ota.zig");

/// Keep in sync with `core/modulus.zig`.
const version_cstr: [*:0]const u8 = "2.0";

const zig_toolchain_version_storage = @import("builtin").zig_version_string ++ "\x00";

/// Bump when device ABI wiring changes (22 = bool exports → c_int 0/1).
pub const abi_epoch: u32 = 22;

inline fn boolCi(v: bool) c_int {
    return @import("abi_bool.zig").asCInt(v);
}

export fn modulus_zig_version() [*:0]const u8 {
    return version_cstr;
}

export fn modulus_zig_toolchain_version() [*:0]const u8 {
    return zig_toolchain_version_storage.ptr;
}

export fn modulus_zig_abi_epoch() u32 {
    return abi_epoch;
}

export fn modulus_zig_boot() void {
    device_runtime.boot();
}

export fn modulus_zig_boot_ok() c_int {
    return boolCi(device_runtime.isBootOk());
}

export fn modulus_zig_system_tick(tick_ms: u32) void {
    device_runtime.systemTick(tick_ms);
}

export fn modulus_zig_system_task_spawned() c_int {
    return boolCi(device_runtime.isSystemTaskSpawned());
}

export fn modulus_zig_event_dispatch_spawned() c_int {
    return boolCi(device_runtime.isEventDispatchSpawned());
}

test "firmware: abi exports version" {
    try std.testing.expectEqualStrings("2.0", std.mem.span(modulus_zig_version()));
    try std.testing.expect(std.mem.span(modulus_zig_toolchain_version()).len > 0);
    try std.testing.expectEqual(@as(u32, 22), modulus_zig_abi_epoch());
}

test "firmware: abi ota stub honest" {
    try std.testing.expectEqual(@as(c_int, 0), modulus_zig_ota_available());
    try std.testing.expectEqualStrings("Not implemented", std.mem.span(modulus_zig_ota_status_text()));
}

export fn modulus_zig_serial_rx(data: [*]const u8, len: usize) void {
    if (!abi_guard.isNonNull(data) or len == 0) return;
    const n = abi_guard.clampSerialLen(len);
    device_runtime.feedSerial(data[0..n]);
}

export fn modulus_zig_transport_on_connect() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.transportConnected();
}

export fn modulus_zig_transport_on_disconnect() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.transportDisconnected();
}

export fn modulus_zig_fill_cnc_status(out: *device_ui_mod.CncStatus) void {
    if (comptime !build_options.device_nvs) return;
    if (!abi_guard.isNonNull(out)) return;
    device_runtime.fillCncStatus(out);
}

export fn modulus_zig_cmd_cycle_start() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdCycleStart();
}

export fn modulus_zig_cmd_feed_hold() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdFeedHold();
}

export fn modulus_zig_cmd_home_all() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdHomeAll();
}

export fn modulus_zig_cmd_reset() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdReset();
}

export fn modulus_zig_cmd_unlock() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdUnlock();
}

export fn modulus_zig_cmd_stop() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdStop();
}

export fn modulus_zig_cmd_mpg_toggle() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdMpgToggle();
}

export fn modulus_zig_mpg_remote() u8 {
    if (comptime !build_options.device_nvs) return 0;
    return device_runtime.mpgRemote();
}

export fn modulus_zig_set_jog_mode(mode: u8) void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.setJogMode(mode);
}

export fn modulus_zig_reload_machine_limits() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.reloadMachineLimits();
}

export fn modulus_zig_envelope_pull_apply() u8 {
    if (comptime !build_options.device_nvs) return 0;
    return device_runtime.applyDumpEnvelope();
}

export fn modulus_zig_cmd_send_gcode(data: [*]const u8, len: usize) void {
    if (comptime !build_options.device_nvs) return;
    if (!abi_guard.isNonNull(data) or len == 0) return;
    device_runtime.sendGcode(data[0..len]);
}

export fn modulus_zig_console_pop(dir_out: *u8, out: [*]u8, cap: usize) i32 {
    if (comptime !build_options.device_nvs) return -1;
    if (!abi_guard.isNonNull(dir_out) or !abi_guard.isNonNull(out) or cap == 0) return -1;
    return console_log_mod.pop(dir_out, out[0..cap]);
}

export fn modulus_zig_probe_pin() u8 {
    if (comptime !build_options.device_nvs) return 0;
    return device_runtime.probePin();
}

export fn modulus_zig_probe_start(cycle: u8) u8 {
    if (comptime !build_options.device_nvs) return 0;
    return if (device_runtime.probeStart(cycle)) @as(u8, 1) else 0;
}

export fn modulus_zig_probe_cancel() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.probeCancel();
}

export fn modulus_zig_probe_busy() u8 {
    if (comptime !build_options.device_nvs) return 0;
    return if (device_runtime.probeBusy()) @as(u8, 1) else 0;
}

export fn modulus_zig_set_wcs(idx: u8) void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.setWcs(idx);
}

export fn modulus_zig_set_units_mm(mm: u8) void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.setUnitsMm(mm != 0);
}

export fn modulus_zig_set_step_size(idx: u8) void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.setStepSize(idx);
}

export fn modulus_zig_cmd_feed_override(delta: i8) void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdFeedOverride(delta);
}

export fn modulus_zig_cmd_spindle_override(delta: i8) void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdSpindleOverride(delta);
}

export fn modulus_zig_cmd_home_axis(axis_idx: u8) void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdHomeAxis(axis_idx);
}

export fn modulus_zig_cmd_zero_axis(axis_idx: u8) void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdZeroAxis(axis_idx);
}

export fn modulus_zig_cmd_zero_all() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdZeroAll();
}

export fn modulus_zig_cycle_wcs() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cycleWcs();
}

export fn modulus_zig_set_active_axis(axis_idx: u8) void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.setActiveAxis(axis_idx);
}

export fn modulus_zig_cmd_spindle_toggle() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdSpindleToggle();
}

export fn modulus_zig_cmd_spindle_cw() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdSpindleCw();
}

export fn modulus_zig_cmd_spindle_ccw() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdSpindleCcw();
}

export fn modulus_zig_cmd_run_macro() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdRunMacro();
}

export fn modulus_zig_limits_reload() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.limitsReload();
}

export fn modulus_zig_settings_dump_begin() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.settingsDumpBegin();
}

export fn modulus_zig_settings_dump_cancel() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.settingsDumpCancel();
}

export fn modulus_zig_settings_dump_ready() c_int {
    if (comptime !build_options.device_nvs) return 0;
    return boolCi(device_runtime.settingsDumpReady());
}

export fn modulus_zig_settings_dump_failed() c_int {
    if (comptime !build_options.device_nvs) return 0;
    return boolCi(device_runtime.settingsDumpFailed());
}

export fn modulus_zig_settings_dump_copy(dst: [*]u8, cap: usize) usize {
    if (comptime !build_options.device_nvs) return 0;
    if (!abi_guard.isNonNull(dst) or cap == 0) return 0;
    // Copy straight into the caller's buffer — the previous 8 KiB stack
    // intermediate here, plus the caller's own 8 KiB stack buffer, exceeded
    // the 16 KiB taskLVGL stack (overflow when the grbl-dump modal fired).
    const use = @min(cap, @import("../cnc/settings_dump.zig").dump_buf_max);
    return device_runtime.settingsDumpCopy(dst[0..use]);
}

export fn modulus_zig_sync_envelope() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.syncEnvelopeToController();
}

export fn modulus_zig_maint_reset_counters() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.maintResetCounters();
}

export fn modulus_zig_maint_flush() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.maintFlush();
}

export fn modulus_zig_cmd_coolant_toggle() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdCoolantToggle();
}

export fn modulus_zig_cmd_mist_toggle() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdMistToggle();
}

export fn modulus_zig_cmd_fan_toggle() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdFanToggle();
}

export fn modulus_zig_cmd_single_step() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.cmdSingleStep();
}

export fn modulus_zig_transport_reinit() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.transportReinit();
}

export fn modulus_zig_transport_espnow_attach() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.transportAttachEspNow();
}

export fn modulus_zig_encoder_reload_settings() void {
    if (comptime !build_options.device_nvs) return;
    device_runtime.encoderReloadSettings();
}

export fn modulus_zig_active_transport() u8 {
    if (comptime !build_options.device_nvs) return 0xFF;
    return device_runtime.activeTransport();
}

export fn modulus_zig_factory_reset() c_int {
    if (comptime !build_options.device_nvs) return -1;
    return device_runtime.factoryReset();
}

export fn modulus_zig_ota_available() c_int {
    return boolCi(ota_mod.available());
}

export fn modulus_zig_ota_status_text() [*:0]const u8 {
    return ota_mod.statusText();
}
