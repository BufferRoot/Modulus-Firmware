//! Modulus Mach Bridge Protocol (MMBP) session timing.

pub const SessionState = @import("../grblhal/session.zig").SessionState;

pub const response_timeout_ms: u32 = 5000;
pub const handshake_timeout_ms: u32 = 3000;
pub const query_retry_ms: u32 = 500;
pub const max_query_retries: u8 = 10;

pub const k_default_port: u16 = 7878;
pub const k_client_name = "modulus-tab5";
pub const k_client_version = "1.0";
