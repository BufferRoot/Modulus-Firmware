//! ExtEncoder constants — I2C map and handwheel jog tuning (hal_ext_encoder.cpp parity).

pub const i2c_addr: u8 = 0x59;
pub const reg_encoder_count: u8 = 0x00;
pub const reg_reset: u8 = 0x30;
pub const reg_fw_version: u8 = 0xFE;

/// Why wheel delta did not produce a jog line (serial trace block_code).
pub const WheelBlock = enum(u8) {
    none = 0,
    mpg_off = 1,
    no_axis = 2,
    bad_state = 3,
    session = 4,
    substep = 5,
};

/// STEP: bounded detent queue so a fast spin buffers instead of flooding grblHAL.
pub const step_queue_max: i32 = 128;
/// STEP: max $J= lines per poll.
pub const step_drain_per_poll: u8 = 8;
/// CONT: detents/sec that maps to 1x the step's base feed.
pub const cont_vel_ref_dps: f32 = 10.0;
/// CONT: max feed increase ratio per poll (smooth acceleration ramp-up).
pub const cont_feed_ramp: f32 = 2.0;
/// CONT: brake when feed falls below this fraction of smoothed feed.
pub const cont_brake_ratio: f32 = 0.55;
/// CONT: floor on the velocity factor so a slow turn still creeps.
pub const cont_min_vel_factor: f32 = 0.25;
/// CONT: ceiling on smoothed feed state (mm/min); envelope clamp still applies in cmdJog.
pub const cont_feed_max: f32 = 10000.0;
/// CONT: min ms between successive $J= commands (tick-rate throttle).
pub const cont_min_interval_ms: u32 = 20;
/// Default STEP coalesce window (ms) — merge detents before drain.
pub const default_coal_ms: u8 = 20;
/// Default max pending STEP detents (NVS override).
pub const default_pend_max: u8 = 32;
/// Fallback poll period (ms) when measured dt is unusable.
pub const nominal_poll_ms: u32 = 20;

