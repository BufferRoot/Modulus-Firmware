//! ExtEncoder poll helpers — device maintain, gating, polarity, jog abort.

const build_options = @import("build_options");
const cnc_state = @import("../../cnc/cnc_state.zig");
const driver = @import("../../cnc/driver.zig");
const consts = @import("ext_encoder_const.zig");
const util = @import("ext_encoder_util.zig");
const trace = @import("ext_encoder_trace.zig");
const state_mod = @import("ext_encoder_state.zig");
const idf_ext = if (build_options.device_nvs)
    @import("idf_ext_encoder.zig")
else
    struct {};

/// Device I2C maintain — false when poll should stop (disconnect handled).
pub fn maintainDevice(enc: *state_mod.ExtEncoder) bool {
    if (!build_options.device_nvs) return enc.connected;

    const was_connected = enc.connected;
    _ = idf_ext.maintain(&enc.connected, &enc.count, &enc.fw_version);
    trace.status(enc);
    if (was_connected and !enc.connected) {
        enc.onDisconnect();
        return false;
    }
    if (!was_connected and enc.connected) {
        enc.last_count = enc.count;
        enc.resetJogMotion();
    }
    return enc.connected;
}

pub fn pollDtMs(enc: *state_mod.ExtEncoder, now_ms: u32) u32 {
    const dt_ms = now_ms -% enc.last_poll_ms;
    enc.last_poll_ms = now_ms;
    if (dt_ms == 0 or dt_ms > 1000) return consts.nominal_poll_ms;
    return dt_ms;
}

pub fn onJogModeChange(enc: *state_mod.ExtEncoder, d: *driver.Driver, st: cnc_state.MachineStatus) void {
    if (st.jog_mode == enc.last_jog_mode) return;
    cancelJog(enc, d);
    enc.resetJogMotion();
    enc.last_jog_mode = st.jog_mode;
}

pub fn canJog(st: cnc_state.MachineStatus, axis: u8, d: *driver.Driver) bool {
    return st.mpg_active and axis != 0 and
        (st.state == .idle or st.state == .jog) and d.canJog();
}

pub fn cancelJog(enc: *state_mod.ExtEncoder, d: *driver.Driver) void {
    if (!enc.jog_active) return;
    d.cmdJogCancel();
    enc.jog_active = false;
}

pub fn handleBlocked(
    enc: *state_mod.ExtEncoder,
    d: *driver.Driver,
    st: cnc_state.MachineStatus,
    axis: u8,
    state_u8: u8,
    delta: i32,
) void {
    if (delta != 0) {
        trace.wheel(enc, delta, st.mpg_active, axis, state_u8, 0, 0, trace.wheelBlock(st, axis));
    }
    cancelJog(enc, d);
    enc.resetJogMotion();
}

pub fn polarizedDelta(delta: i32, mpgpol: u8, active_axis: cnc_state.ActiveAxis) i32 {
    const axis_bit: u8 = @intFromEnum(active_axis);
    if (axis_bit >= 6 or (mpgpol & (@as(u8, 1) << @intCast(axis_bit))) == 0) return delta;
    return -delta;
}

pub fn queueStepDetents(
    enc: *state_mod.ExtEncoder,
    jog_delta: i32,
    raw_delta: i32,
    axis: u8,
    state_u8: u8,
) void {
    const steps = util.accumulateDelta(&enc.pulse_remainder, jog_delta, @as(i32, enc.encdiv));
    if (steps != 0) {
        if (enc.pending_steps == 0) enc.coal_start_ms = enc.last_poll_ms;
        enc.pending_steps += steps;
        enc.clampPending();
    }
    const block: u8 = if (steps == 0) @intFromEnum(consts.WheelBlock.substep) else 0;
    trace.wheel(enc, raw_delta, true, axis, state_u8, steps, 0, block);
}

pub fn releaseOnWheelStop(
    enc: *state_mod.ExtEncoder,
    d: *driver.Driver,
    cont: bool,
    st: cnc_state.MachineStatus,
    axis: u8,
    state_u8: u8,
    now_ms: u32,
) void {
    if (enc.last_wheel_move_ms != 0 and
        now_ms -% enc.last_wheel_move_ms < consts.wheel_stop_quiet_ms)
    {
        trace.wheel(enc, 0, st.mpg_active, axis, state_u8, 0, 0, 0);
        return;
    }

    // Once the operator stops turning, never drain a stale STEP backlog.
    // Abort the controller jog and discard unsent distance.
    enc.pending_steps = 0;
    enc.pulse_remainder = 0;
    enc.coal_start_ms = 0;
    if (cont) {
        enc.cont_feed = 0;
        enc.last_cont_sign = 0;
    }
    cancelJog(enc, d);
    trace.wheel(enc, 0, st.mpg_active, axis, state_u8, 0, 0, 0);
}
