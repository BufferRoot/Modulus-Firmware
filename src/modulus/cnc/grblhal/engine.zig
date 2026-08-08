//! grblHAL session engine — line assembly, parser, session FSM.

const parser = @import("parser.zig");
const gh_session = @import("session.zig");
const engine_poll = @import("engine_poll.zig");
const engine_send = @import("engine_send.zig");
const cnc_config = @import("../cnc_config.zig");
const cnc_state = @import("../cnc_state.zig");
const console_log = @import("../console_log.zig");
const settings_dump_mod = @import("../settings_dump.zig");

pub const SendFn = *const fn (data: []const u8) bool;
pub const ParseEvent = parser.ParseEvent;

pub const Engine = struct {
    send_fn: ?SendFn = null,
    parser: parser.Parser = parser.Parser.init(),
    state: gh_session.SessionState = .disconnected,
    connect_ms: u32 = 0,
    last_poll_ms: u32 = 0,
    /// Last parser-state ($G / 0x83) request — keeps tool_number live from T words.
    last_gc_ms: u32 = 0,
    last_query_ms: u32 = 0,
    last_response_ms: u32 = 0,
    poll_interval_ms: u16 = 100,
    line_buf: [parser.line_buf_max]u8 = undefined,
    line_pos: usize = 0,
    welcome_received: bool = false,
    enums_requested: bool = false,
    lines_dropped: u32 = 0,
    query_retry_count: u8 = 0,
    tick_ms: u32 = 0,
    last_event: ParseEvent = .none,
    settings_dump: ?*settings_dump_mod.SettingsDump = null,
    protocol: cnc_config.Protocol = .grblhal,
    /// After soft-reset welcome, TX `$X` once (hard-limit unlock path).
    pending_unlock: bool = false,

    pub fn init(send_fn: ?SendFn) Engine {
        var e: Engine = .{};
        e.send_fn = send_fn;
        e.parser.status.state = .disconnected;
        return e;
    }

    pub fn setSendFn(self: *Engine, send_fn: ?SendFn) void {
        self.send_fn = send_fn;
    }

    pub fn setProtocol(self: *Engine, protocol: cnc_config.Protocol) void {
        self.protocol = protocol;
    }

    fn isClassicGrbl(self: *const Engine) bool {
        return cnc_config.usesClassicRealtime(self.protocol);
    }

    pub fn onConnect(self: *Engine, tick_ms: u32) void {
        self.state = .wait_banner;
        self.connect_ms = tick_ms;
        self.last_response_ms = tick_ms;
        self.line_pos = 0;
        self.welcome_received = false;
        self.enums_requested = false;
        self.query_retry_count = 0;
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
                self.lines_dropped += 1;
                self.line_pos = 0;
            }
        }
    }

    fn processLine(self: *Engine) void {
        const line = self.line_buf[0..self.line_pos];
        console_log.pushRx(line); // terminal tap (status spam filtered inside)
        const evt = self.parser.parseLine(line);
        self.last_event = evt;
        if (evt != .none) {
            self.last_response_ms = self.tick_ms;
        }

        switch (evt) {
            .welcome => {
                self.welcome_received = true;
                if (self.pending_unlock) {
                    self.pending_unlock = false;
                    engine_send.sendUnlock(self);
                }
                if (self.state == .wait_banner or self.state == .querying) {
                    self.query_retry_count = 0;
                    if (self.isClassicGrbl()) {
                        self.state = .querying;
                        engine_send.requestStatus(self, true);
                    } else {
                        self.state = .configuring;
                        engine_send.requestInfo(self);
                    }
                }
            },
            .status_report => {
                const was_querying = self.state == .querying;
                if (self.parser.status.mpg_remote and self.state != .mpg_blocked) {
                    self.state = .mpg_blocked;
                } else if (!self.parser.status.mpg_remote and self.state == .mpg_blocked) {
                    self.state = .ready;
                }
                if (was_querying) {
                    self.query_retry_count = 0;
                    if (self.parser.status.state == .alarm and
                        gh_session.alarmLocksController(self.parser.status.alarm_code))
                    {
                        self.state = .locked;
                    } else if (self.isClassicGrbl()) {
                        self.state = .ready;
                    } else {
                        self.state = .configuring;
                        engine_send.requestInfo(self);
                    }
                } else if (self.parser.status.state == .alarm) {
                    if (gh_session.alarmLocksController(self.parser.status.alarm_code)) {
                        self.state = .locked;
                    }
                } else if (self.state == .locked and self.parser.status.state != .alarm) {
                    // $X cleared alarm — resume ready without waiting for a second handshake.
                    self.state = .ready;
                }
            },
            .alarm => {
                if (gh_session.alarmLocksController(self.parser.last_alarm)) {
                    self.state = .locked;
                }
                if (self.settings_dump) |cap| cap.onError();
            },
            .ok => {
                if (self.settings_dump) |cap| cap.onOk();
                if (self.state == .configuring) {
                    if (!self.enums_requested and self.parser.ctrl_info.caps.enums) {
                        engine_send.requestEnumerations(self);
                        self.enums_requested = true;
                    } else {
                        self.state = .ready;
                    }
                }
            },
            .info_response => {},
            .setting => {
                if (self.settings_dump) |cap| _ = cap.appendLine(line);
            },
            .err => {
                if (self.settings_dump) |cap| cap.onError();
            },
            else => {},
        }
    }

    pub fn poll(self: *Engine, tick_ms: u32) void {
        engine_poll.poll(self, tick_ms);
    }

    pub fn setPollInterval(self: *Engine, ms: u16) void {
        self.poll_interval_ms = ms;
    }

    pub fn session(self: *const Engine) gh_session.SessionState {
        return self.state;
    }

    pub fn status(self: *const Engine) cnc_state.MachineStatus {
        return self.parser.status;
    }

    pub fn requestInfo(self: *Engine) void {
        engine_send.requestInfo(self);
    }

    pub fn requestEnumerations(self: *Engine) void {
        engine_send.requestEnumerations(self);
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
    }

    pub fn requestUnlockAfterWelcome(self: *Engine) void {
        engine_send.requestUnlockAfterWelcome(self);
    }

    pub fn sendReset(self: *Engine) void {
        engine_send.sendReset(self);
    }

    pub fn sendGcode(self: *Engine, line: []const u8) void {
        engine_send.sendGcode(self, line);
    }

    pub fn sendFeedOverride(self: *Engine, delta_pct: i8) void {
        engine_send.sendFeedOverride(self, delta_pct);
    }

    pub fn sendRapidOverride(self: *Engine, pct: u8) void {
        engine_send.sendRapidOverride(self, pct);
    }

    pub fn sendSpindleOverride(self: *Engine, delta_pct: i8) void {
        engine_send.sendSpindleOverride(self, delta_pct);
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

    pub fn sendFanToggle(self: *Engine) void {
        engine_send.sendFanToggle(self);
    }

    pub fn sendSingleStepToggle(self: *Engine) void {
        engine_send.sendSingleStepToggle(self);
    }

    pub fn sendMpgToggle(self: *Engine) void {
        engine_send.sendMpgToggle(self);
    }

    pub fn sendStop(self: *Engine) void {
        engine_send.sendStop(self);
    }

    pub fn requestParserState(self: *Engine) void {
        engine_send.requestParserState(self);
    }

    pub fn send(self: *Engine, data: []const u8) void {
        console_log.pushTx(data); // terminal tap ('?' polls filtered inside)
        if (self.send_fn) |fn_ptr| _ = fn_ptr(data);
    }
};

test {
    _ = @import("engine_tests.zig");
}
