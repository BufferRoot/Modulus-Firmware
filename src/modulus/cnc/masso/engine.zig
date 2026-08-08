//! Masso Link UDP session engine — binary datagrams (not line protocol).

const std = @import("std");
const parser_mod = @import("parser.zig");
const packet = @import("packet.zig");
const masso_session = @import("session.zig");
const cnc_state = @import("../cnc_state.zig");

pub const SendFn = *const fn (data: []const u8) bool;
pub const ParseEvent = parser_mod.ParseEvent;
pub const SessionState = masso_session.SessionState;

pub const Engine = struct {
    send_fn: ?SendFn = null,
    parser: parser_mod.Parser = parser_mod.Parser.init(),
    state: SessionState = .disconnected,
    connect_ms: u32 = 0,
    last_poll_ms: u32 = 0,
    last_response_ms: u32 = 0,
    tick_ms: u32 = 0,
    last_event: ParseEvent = .none,
    /// 0 = no check; else must match config packet serial (digits from masso_sn).
    expected_serial: u16 = 0,

    pub fn init(send_fn: ?SendFn) Engine {
        var e: Engine = .{};
        e.send_fn = send_fn;
        e.parser.status.state = .disconnected;
        return e;
    }

    pub fn setSendFn(self: *Engine, send_fn: ?SendFn) void {
        self.send_fn = send_fn;
    }

    pub fn setExpectedSerial(self: *Engine, sn: u16) void {
        self.expected_serial = sn;
    }

    pub fn onConnect(self: *Engine, tick_ms: u32) void {
        self.state = .wait_banner;
        self.connect_ms = tick_ms;
        self.last_response_ms = tick_ms;
        self.tick_ms = tick_ms;
        self.last_poll_ms = 0;
        self.parser = parser_mod.Parser.init();
        self.parser.status.state = .idle;
        self.sendVersion();
        self.sendConfig();
    }

    pub fn onDisconnect(self: *Engine) void {
        self.state = .disconnected;
        self.parser.status.state = .disconnected;
    }

    /// Feed one UDP datagram (not byte stream).
    pub fn feed(self: *Engine, data: []const u8, response_tick_ms: ?u32) void {
        if (response_tick_ms) |t| self.tick_ms = t;
        const evt = self.parser.parsePacket(data, self.tick_ms);
        self.last_event = evt;
        if (evt == .none or evt == .bad_crc) return;
        self.last_response_ms = self.tick_ms;
        switch (evt) {
            .version, .config => {
                if (evt == .config and self.expected_serial != 0 and
                    self.parser.serial_num != self.expected_serial)
                {
                    self.onDisconnect();
                    return;
                }
                if (self.parser.version_ok and self.parser.config_ok) {
                    self.state = .ready;
                    // Immediate status poll — don't wait first keepalive interval.
                    self.sendStatus();
                    self.last_poll_ms = self.tick_ms;
                } else {
                    self.state = .configuring;
                }
            },
            .status => {
                if (self.state == .configuring or self.state == .wait_banner or self.state == .querying) {
                    self.state = .ready;
                }
            },
            else => {},
        }
    }

    pub fn poll(self: *Engine, tick_ms: u32) void {
        self.tick_ms = tick_ms;
        if (self.state == .disconnected) return;
        if (self.state == .wait_banner or self.state == .configuring) {
            if (tick_ms -% self.connect_ms >= masso_session.handshake_timeout_ms) {
                self.onDisconnect();
            }
            return;
        }
        if (self.state == .ready) {
            if (self.last_response_ms > 0 and
                tick_ms -% self.last_response_ms >= masso_session.response_timeout_ms)
            {
                self.onDisconnect();
                return;
            }
            if (tick_ms -% self.last_poll_ms >= masso_session.keepalive_ms) {
                self.sendStatus();
                self.last_poll_ms = tick_ms;
            }
        }
    }

    pub fn session(self: *const Engine) SessionState {
        return self.state;
    }

    pub fn status(self: *const Engine) cnc_state.MachineStatus {
        return self.parser.status;
    }

    pub fn send(self: *Engine, data: []const u8) void {
        if (self.send_fn) |fn_ptr| _ = fn_ptr(data);
    }

    fn sendVersion(self: *Engine) void {
        var buf: [16]u8 = undefined;
        const n = packet.buildVersionReq(&buf);
        if (n > 0) self.send(buf[0..n]);
    }

    fn sendConfig(self: *Engine) void {
        var buf: [16]u8 = undefined;
        const n = packet.buildConfigReq(&buf);
        if (n > 0) self.send(buf[0..n]);
    }

    fn sendStatus(self: *Engine) void {
        var buf: [16]u8 = undefined;
        const n = packet.buildStatusReq(&buf);
        if (n > 0) self.send(buf[0..n]);
    }

    // Link has no jog/gcode in RE'd protocol — no-ops keep protocol_engine compile.
    // Honest UX: UI disables MPG via gating.canJog when active==.masso.
    pub fn sendFeedHold(_: *Engine) void {}
    pub fn sendCycleStart(_: *Engine) void {}
    pub fn sendJog(_: *Engine, _: u8, _: f32, _: f32, _: bool, _: bool) void {}
    pub fn sendJogCancel(_: *Engine) void {}
    pub fn sendHome(_: *Engine, _: u8) void {}
    pub fn sendUnlock(_: *Engine) void {}
    pub fn sendReset(self: *Engine) void {
        self.state = .locked;
        self.parser.status.state = .alarm;
    }
    pub fn sendGcode(_: *Engine, _: []const u8) void {}
    pub fn sendFeedOverride(_: *Engine, _: i8) void {}
    pub fn sendRapidOverride(_: *Engine, _: u8) void {}
    pub fn sendSpindleOverride(_: *Engine, _: i8) void {}
    pub fn sendSpindleStopToggle(_: *Engine) void {}
    pub fn sendCoolantFloodToggle(_: *Engine) void {}
    pub fn sendCoolantMistToggle(_: *Engine) void {}
    pub fn sendFanToggle(_: *Engine) void {}
    pub fn sendSingleStepToggle(_: *Engine) void {}
    pub fn sendMpgToggle(_: *Engine) void {}
    pub fn sendStop(_: *Engine) void {}
    pub fn sendFeedOverridePct(_: *Engine, _: u8) void {}
    pub fn sendSpindleOverridePct(_: *Engine, _: u8) void {}
};

test {
    _ = @import("crc.zig");
    _ = @import("packet.zig");
    _ = @import("parser.zig");
}

test "masso: sendJog remains no-op" {
    var e = Engine.init(null);
    e.onConnect(0);
    e.sendJog('X', 1.0, 100.0, false, false);
    e.sendJogCancel();
    try std.testing.expect(e.state == .wait_banner or e.state == .configuring or e.state == .ready);
}

test "masso: expected serial mismatch disconnects" {
    var e = Engine.init(null);
    e.setExpectedSerial(9999);
    e.onConnect(0);
    var cfg: [8]u8 = .{0} ** 8;
    cfg[2] = 0x03;
    cfg[3] = 0x00;
    cfg[4] = 0x03;
    cfg[5] = 0x39; // LE 12345
    cfg[6] = 0x30;
    const c = @import("crc.zig").crc16Ccitt(cfg[2..]);
    cfg[0] = @truncate(c);
    cfg[1] = @truncate(c >> 8);
    var ver: [5]u8 = .{0} ** 5;
    ver[2] = 0x03;
    ver[3] = 0x00;
    ver[4] = 0x02;
    const cv = @import("crc.zig").crc16Ccitt(ver[2..]);
    ver[0] = @truncate(cv);
    ver[1] = @truncate(cv >> 8);
    e.feed(&ver, 1);
    e.feed(&cfg, 2);
    try std.testing.expectEqual(SessionState.disconnected, e.session());
}

test "masso: matching serial goes ready" {
    var e = Engine.init(null);
    e.setExpectedSerial(12345);
    e.onConnect(0);
    var ver: [5]u8 = .{0} ** 5;
    ver[2] = 0x03;
    ver[3] = 0x00;
    ver[4] = 0x02;
    const cv = @import("crc.zig").crc16Ccitt(ver[2..]);
    ver[0] = @truncate(cv);
    ver[1] = @truncate(cv >> 8);
    var cfg: [8]u8 = .{0} ** 8;
    cfg[2] = 0x03;
    cfg[3] = 0x00;
    cfg[4] = 0x03;
    cfg[5] = 0x39;
    cfg[6] = 0x30;
    const c = @import("crc.zig").crc16Ccitt(cfg[2..]);
    cfg[0] = @truncate(c);
    cfg[1] = @truncate(c >> 8);
    e.feed(&ver, 1);
    e.feed(&cfg, 2);
    try std.testing.expectEqual(SessionState.ready, e.session());
}
