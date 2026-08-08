//! ExtEncoder STEP/CONT jog dispatch — grblHAL $J= pacing.

const std = @import("std");
const build_options = @import("build_options");
const cnc_state = @import("../../cnc/cnc_state.zig");
const driver = @import("../../cnc/driver.zig");
const consts = @import("ext_encoder_const.zig");
const util = @import("ext_encoder_util.zig");
const trace = @import("ext_encoder_trace.zig");
const state_mod = @import("ext_encoder_state.zig");

pub const ExtEncoder = state_mod.ExtEncoder;

/// STEP: one increment per queued detent, capped per poll.
/// Honors coalesce window (coal_ms) so fast spins merge before $J= drain.
pub fn drainStep(enc: *ExtEncoder, d: *driver.Driver, axis: u8, st: cnc_state.MachineStatus, now_ms: u32) void {
    if (enc.pending_steps == 0) return;
    if (enc.coal_ms > 0 and enc.coal_start_ms != 0) {
        const age = now_ms -% enc.coal_start_ms;
        if (age < enc.coal_ms) return;
    }
    const step = util.incrementForStep(&enc.increments, st.step_size);
    const feed = util.jogFeedForStep(enc.jogspd, st.step_size);
    var sent: u8 = 0;
    while (enc.pending_steps != 0 and sent < consts.step_drain_per_poll) : (sent += 1) {
        const dist = if (enc.pending_steps > 0) step else -step;
        d.cmdJog(axis, dist, feed);
        enc.jog_active = true;
        enc.pending_steps += if (enc.pending_steps > 0) @as(i32, -1) else 1;
    }
    enc.last_jog_send_ms = now_ms;
    if (enc.pending_steps == 0) enc.coal_start_ms = 0;
    if (build_options.device_nvs and sent > 0) {
        trace.wheel(enc, 0, true, axis, @intFromEnum(st.state), @as(i32, sent), step, 0);
    }
}

/// CONT / VELO: velocity-scaled jog with ramp-up and jog-cancel brake on
/// sharp slowdown.
/// - CONT: base feed = jogspd × step-size ratio, scaled by the user's
///   "CONT speed rate %" (contpct).
/// - VELO: base feed = jogspd only — wheel velocity alone determines the
///   commanded feed (contpct intentionally not applied).
pub fn dispatchCont(
    enc: *ExtEncoder,
    d: *driver.Driver,
    axis: u8,
    raw_delta: i32,
    st: cnc_state.MachineStatus,
    dt_ms: u32,
    state_u8: u8,
    now_ms: u32,
) void {
    const encdiv = enc.encdiv;
    if (encdiv < 1 or raw_delta == 0) return;

    const sign: i32 = if (raw_delta > 0) 1 else -1;
    const abs_counts: i32 = if (raw_delta > 0) raw_delta else -raw_delta;

    if (enc.last_cont_sign != 0 and sign != enc.last_cont_sign) {
        d.cmdJogCancel();
        enc.jog_active = false;
        enc.cont_feed = 0;
    }
    enc.last_cont_sign = sign;

    const detents = util.accumulateDelta(&enc.pulse_remainder, raw_delta, @as(i32, encdiv));
    if (detents == 0) {
        trace.wheel(enc, raw_delta, true, axis, state_u8, 0, 0, @intFromEnum(consts.WheelBlock.substep));
        return;
    }

    const velo = st.jog_mode == .velo;
    const step = util.incrementForStep(&enc.increments, st.step_size);
    var base_feed = if (velo)
        @as(f32, @floatFromInt(enc.jogspd))
    else
        util.jogFeedForStep(enc.jogspd, st.step_size) *
            (@as(f32, @floatFromInt(enc.contpct)) / 100.0);
    if (base_feed < 1.0) base_feed = 1.0;
    const distance = @as(f32, @floatFromInt(detents)) * step;

    const dps = (@as(f32, @floatFromInt(abs_counts)) / @as(f32, @floatFromInt(encdiv))) *
        (1000.0 / @as(f32, @floatFromInt(dt_ms)));
    var vel_factor = dps / consts.cont_vel_ref_dps;
    if (vel_factor < consts.cont_min_vel_factor) vel_factor = consts.cont_min_vel_factor;

    var target_feed = std.math.clamp(base_feed * vel_factor, 100.0, consts.cont_feed_max);

    if (enc.jog_active and enc.cont_feed > 0 and target_feed < enc.cont_feed * consts.cont_brake_ratio) {
        d.cmdJogCancel();
        enc.jog_active = false;
    }
    if (enc.cont_feed > 0 and target_feed > enc.cont_feed * consts.cont_feed_ramp) {
        target_feed = enc.cont_feed * consts.cont_feed_ramp;
    }

    enc.cont_feed = target_feed;
    if (enc.last_jog_send_ms != 0) {
        const since = now_ms -% enc.last_jog_send_ms;
        const min_iv = if (enc.coal_ms > 0) @as(u32, enc.coal_ms) else consts.cont_min_interval_ms;
        if (since < min_iv) {
            trace.wheel(enc, raw_delta, true, axis, state_u8, detents, distance, 0);
            return;
        }
    }
    d.cmdJog(axis, distance, enc.cont_feed);
    enc.jog_active = true;
    enc.last_jog_send_ms = now_ms;

    trace.wheel(enc, raw_delta, true, axis, state_u8, detents, distance, 0);
}
