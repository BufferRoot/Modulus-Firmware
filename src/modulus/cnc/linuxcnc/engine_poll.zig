//! LinuxCNC engine periodic poll — handshake timeout + status refresh.

const engine_send = @import("engine_send.zig");
const lc_session = @import("session.zig");

pub fn poll(eng: anytype, tick_ms: u32) void {
    eng.tick_ms = tick_ms;
    if (eng.state == .disconnected) return;

    if (eng.state == .wait_banner) {
        if (tick_ms -% eng.connect_ms >= lc_session.handshake_timeout_ms and !eng.hello_done) {
            eng.onDisconnect();
        }
        return;
    }

    if (eng.state == .configuring) {
        if (tick_ms -% eng.connect_ms >= lc_session.handshake_timeout_ms and !eng.enable_done) {
            eng.onDisconnect();
        }
        return;
    }

    if (eng.state == .querying) {
        if (tick_ms -% eng.last_query_ms >= lc_session.query_retry_ms) {
            if (eng.query_retry_count >= lc_session.max_query_retries) {
                eng.onDisconnect();
                return;
            }
            eng.query_retry_count += 1;
            engine_send.sendStatusPoll(eng);
            eng.last_query_ms = tick_ms;
        }
        return;
    }

    if (eng.state == .ready or eng.state == .locked) {
        if (eng.last_response_ms > 0 and
            tick_ms -% eng.last_response_ms >= lc_session.response_timeout_ms)
        {
            eng.onDisconnect();
            return;
        }
        // Keep polling while locked (estop) so ESTOP OFF / status keep the link alive.
        if (tick_ms -% eng.last_poll_ms >= eng.poll_interval_ms) {
            engine_send.sendStatusPoll(eng);
            eng.last_poll_ms = tick_ms;
        }
    }
}
