//! grblHAL session FSM states.

pub const SessionState = enum(u8) {
    disconnected = 0,
    wait_banner,
    querying,
    configuring,
    ready,
    locked,
    mpg_blocked,
};

pub const response_timeout_ms: u32 = 3000;

/// Response window while the machine is executing someone else's program.
///
/// grblHAL services the stream that owns the controller. When a PC sender is
/// running a job, MPG-port status replies go sparse or stop for seconds at a
/// time, and the normal 3 s window declared a link failure every single time a
/// job started. The controller is demonstrably alive — it is just not talking
/// to us — so widen the window rather than dropping the session.
///
/// Still bounded: a genuinely dead link is caught, just later. The DRO holds
/// its last values during the gap, which is correct — those are the last
/// readings we actually received.
pub const busy_response_timeout_ms: u32 = 30000;

/// True when the controller is executing and may legitimately stop answering
/// the passive MPG port.
pub fn stateIsBusy(state: @import("../cnc_state.zig").MachineState) bool {
    return switch (state) {
        .run, .hold, .jog, .home, .door, .tool => true,
        else => false,
    };
}
pub const wait_banner_ms: u32 = 500;
pub const query_retry_ms: u32 = 500;
pub const max_query_retries: u8 = 10;

pub const AlarmCode = enum(u8) {
    none = 0,
    hard_limit = 1,
    soft_limit = 2,
    e_stop = 10,
};

pub fn alarmLocksController(code: u8) bool {
    // Any non-zero alarm locks the session so unlock/reset TX paths stay armed.
    return code != 0;
}
