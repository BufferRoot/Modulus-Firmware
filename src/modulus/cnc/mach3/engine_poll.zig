//! MMBP engine periodic poll — handshake timeout + status refresh.

const engine_send = @import("engine_send.zig");
const mach_session = @import("session.zig");
const stream_poll = @import("../stream_poll.zig");

pub fn poll(eng: anytype, tick_ms: u32) void {
    stream_poll.poll(eng, tick_ms, .{
        .handshake_timeout_ms = mach_session.handshake_timeout_ms,
        .query_retry_ms = mach_session.query_retry_ms,
        .max_query_retries = mach_session.max_query_retries,
        .response_timeout_ms = mach_session.response_timeout_ms,
    }, .ready_like, engine_send.sendStatusPoll);
}
