//! Shared handshake/query/ready poll for Telnet-style engines (LinuxCNC / Mach3).

pub const Timeouts = struct {
    handshake_timeout_ms: u32,
    query_retry_ms: u32,
    max_query_retries: u8,
    response_timeout_ms: u32,
};

/// `configuring` as its own handshake phase (LinuxCNC) vs treated like ready (Mach3).
pub const Configuring = enum { handshake, ready_like };

pub fn poll(
    eng: anytype,
    tick_ms: u32,
    timeouts: Timeouts,
    comptime configuring: Configuring,
    send_status: anytype,
) void {
    eng.tick_ms = tick_ms;
    if (eng.state == .disconnected) return;

    if (eng.state == .wait_banner) {
        if (tick_ms -% eng.connect_ms >= timeouts.handshake_timeout_ms and !eng.hello_done) {
            eng.onDisconnect();
        }
        return;
    }

    if (comptime configuring == .handshake) {
        if (eng.state == .configuring) {
            if (tick_ms -% eng.connect_ms >= timeouts.handshake_timeout_ms and !eng.enable_done) {
                eng.onDisconnect();
            }
            return;
        }
    }

    if (eng.state == .querying) {
        if (tick_ms -% eng.last_query_ms >= timeouts.query_retry_ms) {
            if (eng.query_retry_count >= timeouts.max_query_retries) {
                eng.onDisconnect();
                return;
            }
            eng.query_retry_count += 1;
            send_status(eng);
            eng.last_query_ms = tick_ms;
        }
        return;
    }

    const in_ready = if (comptime configuring == .ready_like)
        (eng.state == .ready or eng.state == .locked or eng.state == .configuring)
    else
        (eng.state == .ready or eng.state == .locked);

    if (in_ready) {
        if (eng.last_response_ms > 0 and
            tick_ms -% eng.last_response_ms >= timeouts.response_timeout_ms)
        {
            eng.onDisconnect();
            return;
        }
        if (tick_ms -% eng.last_poll_ms >= eng.poll_interval_ms) {
            send_status(eng);
            eng.last_poll_ms = tick_ms;
        }
    }
}
