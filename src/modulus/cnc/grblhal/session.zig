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
