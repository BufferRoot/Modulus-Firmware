//! LinuxCNC linuxcncrsh session engine — line assembly + status FSM.

const std = @import("std");
const parser = @import("parser.zig");
const lc_session = @import("session.zig");
const engine_poll = @import("engine_poll.zig");
const engine_send = @import("engine_send.zig");
const cnc_state = @import("../cnc_state.zig");
const settings_dump_mod = @import("../settings_dump.zig");

pub const SendFn = *const fn (data: []const u8) bool;
pub const ParseEvent = parser.ParseEvent;
pub const SessionState = lc_session.SessionState;

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
    enable_done: bool = false,
    query_retry_count: u8 = 0,
    tick_ms: u32 = 0,
    last_event: ParseEvent = .none,
    settings_dump: ?*settings_dump_mod.SettingsDump = null,
    /// Remaining INI replies expected for envelope pull (0 = idle).
    ini_pull_left: u8 = 0,

    pub fn init(send_fn: ?SendFn) Engine {
        var e: Engine = .{};
        e.send_fn = send_fn;
        e.parser.status.state = .disconnected;
        return e;
    }

    pub fn setSendFn(self: *Engine, send_fn: ?SendFn) void {
        self.send_fn = send_fn;
    }

    pub fn setProtocol(_: *Engine, _: anytype) void {}

    pub fn setPasswords(self: *Engine, connect_pw: []const u8, enable_pw: []const u8) void {
        self.parser.setPasswords(connect_pw, enable_pw);
    }

    pub fn onConnect(self: *Engine, tick_ms: u32) void {
        self.state = .wait_banner;
        self.connect_ms = tick_ms;
        self.last_response_ms = tick_ms;
        self.line_pos = 0;
        self.hello_done = false;
        self.enable_done = false;
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
                self.state = .configuring;
                engine_send.sendHandshakeSetup(self);
            },
            .hello_nak => self.onDisconnect(),
            .enable_on => {
                self.enable_done = true;
                self.state = .querying;
                self.query_retry_count = 0;
                engine_send.sendStatusPoll(self);
                self.last_query_ms = self.tick_ms;
            },
            .enable_off => {
                self.enable_done = false;
                if (self.state == .ready or self.state == .querying or self.state == .locked) {
                    self.state = .configuring;
                }
            },
            .estop_on => self.state = .locked,
            .estop_off => {
                if (self.state == .locked) {
                    self.state = if (self.enable_done) .ready else .configuring;
                }
            },
            .program_status, .abs_act_pos, .rel_act_pos, .feed_override, .spindle_override, .spindle, .joint_homed => {
                if (self.state == .querying) {
                    self.query_retry_count = 0;
                    self.state = .ready;
                }
            },
            .ini => self.onIniLine(),
            .err => if (self.settings_dump) |cap| cap.onError(),
            else => {},
        }
    }

    fn onIniLine(self: *Engine) void {
        const cap = self.settings_dump orelse return;
        if (!self.parser.ini_ok) return;
        const sec = std.mem.sliceTo(&self.parser.ini_section, 0);
        const key = std.mem.sliceTo(&self.parser.ini_key, 0);
        const v = self.parser.ini_value;
        var line_buf: [48]u8 = undefined;
        // Map INI → synthetic $$ lines so applyDumpEnvelope stays shared.
        // Velocities: LinuxCNC often units/sec → pendant mm/min (*60).
        const synth: ?[]const u8 = blk: {
            if (std.ascii.eqlIgnoreCase(sec, "TRAJ") and std.ascii.eqlIgnoreCase(key, "MAX_LINEAR_VELOCITY")) {
                const mm_min: u32 = @intFromFloat(@min(v * 60.0, 20000.0));
                break :blk std.fmt.bufPrint(&line_buf, "$110={d}", .{mm_min}) catch null;
            }
            if (std.ascii.eqlIgnoreCase(sec, "AXIS_X") and std.ascii.eqlIgnoreCase(key, "MAX_VELOCITY")) {
                const mm_min: u32 = @intFromFloat(@min(v * 60.0, 20000.0));
                break :blk std.fmt.bufPrint(&line_buf, "$110={d}", .{mm_min}) catch null;
            }
            if (std.ascii.eqlIgnoreCase(sec, "AXIS_Y") and std.ascii.eqlIgnoreCase(key, "MAX_VELOCITY")) {
                const mm_min: u32 = @intFromFloat(@min(v * 60.0, 20000.0));
                break :blk std.fmt.bufPrint(&line_buf, "$111={d}", .{mm_min}) catch null;
            }
            if (std.ascii.eqlIgnoreCase(sec, "AXIS_Z") and std.ascii.eqlIgnoreCase(key, "MAX_VELOCITY")) {
                const mm_min: u32 = @intFromFloat(@min(v * 60.0, 20000.0));
                break :blk std.fmt.bufPrint(&line_buf, "$112={d}", .{mm_min}) catch null;
            }
            if (std.ascii.eqlIgnoreCase(sec, "AXIS_X") and std.ascii.eqlIgnoreCase(key, "MAX_LIMIT")) {
                const mm: u32 = @intFromFloat(@min(@abs(v), 2000.0));
                break :blk std.fmt.bufPrint(&line_buf, "$130={d}", .{mm}) catch null;
            }
            if (std.ascii.eqlIgnoreCase(sec, "AXIS_Y") and std.ascii.eqlIgnoreCase(key, "MAX_LIMIT")) {
                const mm: u32 = @intFromFloat(@min(@abs(v), 2000.0));
                break :blk std.fmt.bufPrint(&line_buf, "$131={d}", .{mm}) catch null;
            }
            if (std.ascii.eqlIgnoreCase(sec, "AXIS_Z") and std.ascii.eqlIgnoreCase(key, "MAX_LIMIT")) {
                const mm: u32 = @intFromFloat(@min(@abs(v), 1000.0));
                break :blk std.fmt.bufPrint(&line_buf, "$132={d}", .{mm}) catch null;
            }
            if (std.ascii.eqlIgnoreCase(sec, "AXIS_A") and std.ascii.eqlIgnoreCase(key, "MAX_LIMIT")) {
                const deg: u32 = @intFromFloat(@min(@abs(v), 7200.0));
                break :blk std.fmt.bufPrint(&line_buf, "$133={d}", .{deg}) catch null;
            }
            if (std.ascii.eqlIgnoreCase(sec, "AXIS_B") and std.ascii.eqlIgnoreCase(key, "MAX_LIMIT")) {
                const deg: u32 = @intFromFloat(@min(@abs(v), 7200.0));
                break :blk std.fmt.bufPrint(&line_buf, "$134={d}", .{deg}) catch null;
            }
            if (std.ascii.eqlIgnoreCase(sec, "AXIS_C") and std.ascii.eqlIgnoreCase(key, "MAX_LIMIT")) {
                const deg: u32 = @intFromFloat(@min(@abs(v), 7200.0));
                break :blk std.fmt.bufPrint(&line_buf, "$135={d}", .{deg}) catch null;
            }
            if (std.ascii.eqlIgnoreCase(sec, "SPINDLE_0") and std.ascii.eqlIgnoreCase(key, "MAX_FORWARD_VELOCITY")) {
                const rpm: u32 = @intFromFloat(@min(@abs(v), 60000.0));
                break :blk std.fmt.bufPrint(&line_buf, "$30={d}", .{rpm}) catch null;
            }
            break :blk null;
        };
        if (synth) |s| _ = cap.appendLine(s);
        self.ini_pull_left -|= 1;
        if (self.ini_pull_left == 0) {
            cap.onOk();
            self.settings_dump = null;
        }
    }

    /// Begin INI envelope pull (11 queries). Caller arms settings_dump first.
    pub fn beginIniEnvelopePull(self: *Engine) void {
        self.ini_pull_left = 11;
        engine_send.sendIniEnvelopePoll(self);
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
            self.enable_done = false;
        }
    }

    pub fn sendReset(self: *Engine) void {
        engine_send.sendReset(self);
    }

    pub fn sendGcode(self: *Engine, line: []const u8) void {
        // Track S word for commanded RPM display (no encoder RPM over linuxcncrsh).
        if (std.mem.indexOfScalar(u8, line, 'S') orelse std.mem.indexOfScalar(u8, line, 's')) |si| {
            var end = si + 1;
            while (end < line.len and (line[end] == ' ' or line[end] == '\t')) : (end += 1) {}
            const start = end;
            while (end < line.len and ((line[end] >= '0' and line[end] <= '9') or line[end] == '.')) : (end += 1) {}
            if (end > start) {
                if (std.fmt.parseFloat(f32, line[start..end])) |f| {
                    if (f > 0) self.parser.noteCommandedRpm(@intFromFloat(@min(f, 99999.0)));
                } else |_| {}
            }
        }
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

    pub fn sendSingleStepToggle(self: *Engine) void {
        engine_send.sendSingleStepToggle(self);
    }

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
