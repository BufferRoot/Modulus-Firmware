//! Masso Link session timing.

pub const SessionState = @import("../grblhal/session.zig").SessionState;

pub const handshake_timeout_ms: u32 = 5000;
pub const response_timeout_ms: u32 = 5000;
pub const keepalive_ms: u16 = 1000;
