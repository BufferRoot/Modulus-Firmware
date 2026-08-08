//! Mach3/Mach4 MMBP session engine — line assembly + status FSM.

const std = @import("std");
const parser = @import("parser.zig");
const mach_session = @import("session.zig");
const engine_poll = @import("engine_poll.zig");
const engine_send = @import("engine_send.zig");
const cnc_state = @import("../cnc_state.zig");
const settings_dump_mod = @import("../settings_dump.zig");

pub const SendFn = *const fn (data: []const u8) bool;
pub const ParseEvent = parser.ParseEvent;
pub const SessionState = mach_session.SessionState;

pub const Engine = struct {
    send_fn: ?SendFn = null,
    parser: parser.Parser = parser.Parser.init(),
    state: SessionState = .disconnected,
    connect_ms: u32 = 0,
    last_poll_ms: u32 = 0,
    last_query_ms: u32 = 0,
    last_response_ms: u32 = 0,
    poll_interval_ms: u16 = 250,
    line_buf: [parser.line_buf_max]u8 = undefined,
    line_pos: usize = 0,
    hello_done: bool = false,
    query_retry_count: u8 = 0,
    tick_ms: u32 = 0,
    last_event: ParseEvent = .none,
    settings_dump: ?*settings_dump_mod.SettingsDump = null,

    pub fn init(send_fn: ?SendFn) Engine {
        var e: Engine = .{};
        e.send_fn = send_fn;
        e.parser.status.state = .disconnected;
        return e;
    }

    pub fn setSendFn(self: *Engine, send_fn: ?SendFn) void {
        self.send_fn = send_fn;
    }

    pub fn onConnect(self: *Engine, tick_ms: u32) void {
        self.state = .wait_banner;
        self.connect_ms = tick_ms;
        self.last_response_ms = tick_ms;
        self.line_pos = 0;
        self.hello_done = false;
        self.query_retry_count = 0;
        self.parser.status.state = .idle;
        engine_send.sendHello(self);
    }

    pub fn onDisconnect(self: *Engine) void {
        self.state = .disconnected;
        self.parser.status.state = .disconnected;
        self.query_retry_count = 0;
    }

    pub fn feed(self: *Engine, data: []const u8, response_tick_ms: ?u32) void {
        if (response_tick_ms) |t| self.tick_ms = t;
        for (data) |byte| {
            const c: u8 = byte;
            if (c == '\r') continue;
            if (c == '\n') {
                if (self.line_pos > 0) {
                    self.processLine();
                    self.line_pos = 0;
                }
                continue;
            }
            if (self.line_pos < self.line_buf.len - 1) {
                self.line_buf[self.line_pos] = c;
                self.line_pos += 1;
            } else {
                self.line_pos = 0;
            }
        }
    }

    fn processLine(self: *Engine) void {
        const line = self.line_buf[0..self.line_pos];
        const evt = self.parser.parseLine(line);
        self.last_event = evt;
        if (evt != .none) self.last_response_ms = self.tick_ms;

        switch (evt) {
            .hello_ack => {
                self.hello_done = true;
                self.state = .querying;
                self.query_retry_count = 0;
                engine_send.sendStatusPoll(self);
                self.last_query_ms = self.tick_ms;
            },
            .hello_nak => self.onDisconnect(),
            .status => {
                if (self.parser.estop_active) {
                    self.state = .locked;
                } else if (self.state == .querying or self.state == .configuring or self.state == .locked) {
                    self.query_retry_count = 0;
                    self.state = .ready;
                }
            },
            .pos, .ovr => {
                if (self.state == .querying or self.state == .configuring) {
                    self.query_retry_count = 0;
                    self.state = .ready;
                }
            },
            .ok => {
                // Unlock path: CMD UNLOCK → OK while configuring → ready.
                if (self.state == .configuring or self.state == .locked) {
                    self.state = .ready;
                }
            },
            .err => if (self.settings_dump) |cap| cap.onError(),
            else => {},
        }
    }

    pub fn poll(self: *Engine, tick_ms: u32) void {
        engine_poll.poll(self, tick_ms);
    }

    pub fn setPollInterval(self: *Engine, ms: u16) void {
        self.poll_interval_ms = ms;
    }

    pub fn session(self: *const Engine) SessionState {
        return self.state;
    }

    pub fn status(self: *const Engine) cnc_state.MachineStatus {
        return self.parser.status;
    }

    pub fn sendFeedHold(self: *Engine) void {
        engine_send.sendFeedHold(self);
    }

    pub fn sendCycleStart(self: *Engine) void {
        engine_send.sendCycleStart(self);
    }

    pub fn sendJog(self: *Engine, axis: u8, distance: f32, feed_rate: f32, incremental: bool, metric: bool) void {
        engine_send.sendJog(self, axis, distance, feed_rate, incremental, metric);
    }

    pub fn sendJogCancel(self: *Engine) void {
        engine_send.sendJogCancel(self);
    }

    pub fn sendHome(self: *Engine, axis: u8) void {
        engine_send.sendHome(self, axis);
    }

    pub fn sendUnlock(self: *Engine) void {
        engine_send.sendUnlock(self);
        if (self.state == .locked) {
            self.state = .configuring;
            self.connect_ms = self.tick_ms;
        }
    }

    pub fn sendReset(self: *Engine) void {
        engine_send.sendReset(self);
    }

    pub fn sendGcode(self: *Engine, line: []const u8) void {
        engine_send.sendGcode(self, line);
    }

    pub fn sendFeedOverride(self: *Engine, delta_pct: i8) void {
        applyOverrideDelta(self, true, delta_pct);
    }

    pub fn sendRapidOverride(_: *Engine, _: u8) void {}

    pub fn sendSpindleOverride(self: *Engine, delta_pct: i8) void {
        applyOverrideDelta(self, false, delta_pct);
    }

    fn applyOverrideDelta(self: *Engine, is_feed: bool, delta_pct: i8) void {
        var val = if (is_feed) self.parser.status.overrides.feed else self.parser.status.overrides.spindle;
        if (delta_pct == 0) {
            val = 100;
        } else {
            const sum = @as(i16, val) + @as(i16, delta_pct);
            val = @intCast(std.math.clamp(sum, @as(i16, 10), @as(i16, 200)));
        }
        if (is_feed) {
            engine_send.sendFeedOverridePct(self, val);
            self.parser.status.overrides.feed = val;
        } else {
            engine_send.sendSpindleOverridePct(self, val);
            self.parser.status.overrides.spindle = val;
        }
    }

    pub fn sendSpindleStopToggle(self: *Engine) void {
        engine_send.sendSpindleStopToggle(self);
    }

    pub fn sendCoolantFloodToggle(self: *Engine) void {
        engine_send.sendCoolantFloodToggle(self);
    }

    pub fn sendCoolantMistToggle(self: *Engine) void {
        engine_send.sendCoolantMistToggle(self);
    }

    pub fn sendFanToggle(_: *Engine) void {}

    pub fn sendSingleStepToggle(_: *Engine) void {}

    pub fn sendMpgToggle(_: *Engine) void {}

    pub fn sendStop(self: *Engine) void {
        engine_send.sendStop(self);
    }

    pub fn send(self: *Engine, data: []const u8) void {
        if (self.send_fn) |fn_ptr| _ = fn_ptr(data);
    }

    pub fn sendFeedOverridePct(self: *Engine, pct: u8) void {
        engine_send.sendFeedOverridePct(self, pct);
    }

    pub fn sendSpindleOverridePct(self: *Engine, pct: u8) void {
        engine_send.sendSpindleOverridePct(self, pct);
    }
};

test {
    _ = @import("engine_tests.zig");
}
