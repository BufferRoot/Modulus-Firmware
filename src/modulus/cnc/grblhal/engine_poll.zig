//! grblHAL engine periodic poll — banner wait, status query, timeout disconnect.

const cmd = @import("cmd.zig");
const engine_send = @import("engine_send.zig");
const gh_session = @import("session.zig");
const cnc_config = @import("../cnc_config.zig");

/// Parser-state ($G via RT 0x83) poll period — keeps tool_number current from
/// T words without meaningful serial load (1 request byte / short [GC:] reply).
const parser_state_poll_ms: u32 = 2000;

fn statusQueryByte(protocol: cnc_config.Protocol, full: bool) u8 {
    var buf: [1]u8 = undefined;
    const n = if (cnc_config.usesClassicRealtime(protocol))
        cmd.classicStatusQuery(&buf)
    else
        cmd.statusQuery(&buf, full);
    return if (n > 0) buf[0] else 0;
}

pub fn poll(eng: anytype, tick_ms: u32) void {
    eng.tick_ms = tick_ms;
    if (eng.state == .disconnected) {
        @branchHint(.unlikely);
        return;
    }

    if (eng.state == .wait_banner) {
        if (tick_ms -% eng.connect_ms >= gh_session.wait_banner_ms and !eng.welcome_received) {
            const byte = statusQueryByte(eng.protocol, true);
            if (byte != 0) eng.send(&.{byte});
            eng.state = .querying;
            eng.last_query_ms = tick_ms;
        }
        return;
    }

    if (eng.state == .querying) {
        if (tick_ms -% eng.last_query_ms >= gh_session.query_retry_ms) {
            if (eng.query_retry_count >= gh_session.max_query_retries) {
                eng.onDisconnect();
                return;
            }
            eng.query_retry_count += 1;
            const byte = statusQueryByte(eng.protocol, true);
            if (byte != 0) eng.send(&.{byte});
            eng.last_query_ms = tick_ms;
        }
        return;
    }

    if (eng.state == .ready or eng.state == .locked or eng.state == .mpg_blocked) {
        if (eng.last_response_ms > 0 and
            tick_ms -% eng.last_response_ms >= gh_session.response_timeout_ms)
        {
            @branchHint(.unlikely);
            eng.onDisconnect();
            return;
        }
    }

    if (eng.state == .ready) {
        @branchHint(.likely);
        if (tick_ms -% eng.last_poll_ms >= eng.poll_interval_ms) {
            const byte = statusQueryByte(eng.protocol, false);
            if (byte != 0) eng.send(&.{byte});
            eng.last_poll_ms = tick_ms;
        }
        // Keep tool_number (and modal F/S) current from G-code T words via $G / 0x83.
        // grblHAL also pushes |T:n| on tool change in status reports (parsed separately).
        if (cnc_config.usesGrblEngine(eng.protocol) and
            tick_ms -% eng.last_gc_ms >= parser_state_poll_ms)
        {
            engine_send.requestParserState(eng);
            eng.last_gc_ms = tick_ms;
        }
        return;
    }

    if (eng.state == .locked) {
        if (tick_ms -% eng.last_poll_ms >= 1000) {
            const byte = statusQueryByte(eng.protocol, true);
            if (byte != 0) eng.send(&.{byte});
            eng.last_poll_ms = tick_ms;
        }
        return;
    }

    if (eng.state == .mpg_blocked) {
        if (tick_ms -% eng.last_poll_ms >= 500) {
            const byte = statusQueryByte(eng.protocol, false);
            if (byte != 0) eng.send(&.{byte});
            eng.last_poll_ms = tick_ms;
        }
        if (cnc_config.usesGrblEngine(eng.protocol) and
            tick_ms -% eng.last_gc_ms >= parser_state_poll_ms)
        {
            engine_send.requestParserState(eng);
            eng.last_gc_ms = tick_ms;
        }
    }
}
