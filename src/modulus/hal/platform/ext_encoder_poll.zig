//! ExtEncoder Core 1 poll — orchestrates maintain, gating, STEP/CONT dispatch.

const cnc_state = @import("../../cnc/cnc_state.zig");
const jog = @import("ext_encoder_jog.zig");
const ops = @import("ext_encoder_poll_ops.zig");
const state_mod = @import("ext_encoder_state.zig");

pub fn run(enc: *state_mod.ExtEncoder, now_ms: u32) void {
    if (enc.drv == null or enc.store == null) return;
    if (!ops.maintainDevice(enc)) return;

    const d = enc.drv.?;
    const dt_ms = ops.pollDtMs(enc, now_ms);
    const delta = blk: {
        @setRuntimeSafety(false);
        break :blk enc.count -% enc.last_count;
    };
    enc.last_count = enc.count;

    const st = d.status();
    const axis: u8 = cnc_state.activeAxisLetter(st.active_axis) orelse 0;
    const state_u8: u8 = @intFromEnum(st.state);
    const cont = st.jog_mode != .step; // CONT and VELO both use velocity dispatch

    ops.onJogModeChange(enc, d, st);

    // A mode change resets motion accumulators. Record this sample afterwards
    // so the stop timer still starts from the count that initiated the jog.
    if (delta != 0) enc.last_wheel_move_ms = now_ms;

    if (!ops.canJog(st, axis, d)) {
        ops.handleBlocked(enc, d, st, axis, state_u8, delta);
        return;
    }

    const jog_delta = ops.polarizedDelta(delta, enc.mpgpol, st.active_axis);

    if (delta != 0) {
        if (cont) {
            jog.dispatchCont(enc, d, axis, jog_delta, st, dt_ms, state_u8, now_ms);
        } else {
            ops.queueStepDetents(enc, jog_delta, delta, axis, state_u8);
        }
    }

    if (delta == 0) {
        ops.releaseOnWheelStop(enc, d, cont, st, axis, state_u8, now_ms);
    }

    // Stop handling must run before draining STEP commands. Once the wheel is
    // quiet, releaseOnWheelStop discards any backlog instead of feeding it to
    // the controller after the operator has let go of the wheel.
    if (!cont and enc.pending_steps != 0) {
        jog.drainStep(enc, d, axis, st, now_ms);
    }
}
