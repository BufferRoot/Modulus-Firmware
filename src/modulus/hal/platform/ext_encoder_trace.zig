//! Device serial trace for handwheel — no-op on host.

const std = @import("std");
const build_options = @import("build_options");
const cnc_state = @import("../../cnc/cnc_state.zig");
const consts = @import("ext_encoder_const.zig");
const state_mod = @import("ext_encoder_state.zig");
const idf_ext = if (build_options.device_nvs)
    @import("idf_ext_encoder.zig")
else
    struct {};

pub fn wheelBlock(st: cnc_state.MachineStatus, axis: u8) u8 {
    if (!st.mpg_active) return @intFromEnum(consts.WheelBlock.mpg_off);
    if (axis == 0) return @intFromEnum(consts.WheelBlock.no_axis);
    if (st.state != .idle and st.state != .jog) return @intFromEnum(consts.WheelBlock.bad_state);
    return @intFromEnum(consts.WheelBlock.session);
}

pub fn wheel(
    enc: *state_mod.ExtEncoder,
    delta: i32,
    mpg_active: bool,
    axis: u8,
    state_u8: u8,
    jog_steps: i32,
    jog_mm: f32,
    block_code: u8,
) void {
    if (!build_options.device_nvs) return;
    idf_ext.traceWheel(enc.count, delta, mpg_active, axis, state_u8, jog_steps, jog_mm, block_code);
}

pub fn status(enc: *state_mod.ExtEncoder) void {
    if (!build_options.device_nvs) return;
    idf_ext.traceStatus(enc.connected, enc.fw_version);
}

test "hal: ext encoder wheel block codes" {
    const st = cnc_state.MachineStatus{ .mpg_active = false, .state = .idle };
    try std.testing.expectEqual(@intFromEnum(consts.WheelBlock.mpg_off), wheelBlock(st, 'X'));
    const armed = cnc_state.MachineStatus{ .mpg_active = true, .state = .run };
    try std.testing.expectEqual(@intFromEnum(consts.WheelBlock.bad_state), wheelBlock(armed, 'X'));
}
