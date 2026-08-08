//! MMBP line parser — bridge responses to `MachineStatus`.

const std = @import("std");
const parse_util = @import("../grblhal/parse_util.zig");
const cnc_state = @import("../cnc_state.zig");
const parse_event = @import("parse_event.zig");

pub const ParseEvent = parse_event.ParseEvent;
pub const line_buf_max = 256;

pub const Parser = struct {
    status: cnc_state.MachineStatus = .{},
    flood_on: bool = false,
    mist_on: bool = false,
    /// Last STATUS line had ESTOP=1 (session should lock).
    estop_active: bool = false,

    pub fn init() Parser {
        return .{};
    }

    pub fn parseLine(self: *Parser, line: []const u8) ParseEvent {
        if (line.len == 0) return .none;
        if (std.mem.startsWith(u8, line, "HELLO ACK")) return .hello_ack;
        if (std.mem.eql(u8, line, "HELLO NAK")) return .hello_nak;
        if (std.mem.startsWith(u8, line, "STATUS")) return parseStatus(self, line);
        if (std.mem.startsWith(u8, line, "POS")) return parsePos(self, line);
        if (std.mem.startsWith(u8, line, "OVR")) return parseOvr(self, line);
        if (std.mem.eql(u8, line, "OK")) return .ok;
        if (std.mem.startsWith(u8, line, "ERR")) return .err;
        return .none;
    }

    fn parseStatus(self: *Parser, line: []const u8) ParseEvent {
        // First token after STATUS is the machine word — avoid "RUN" inside other keys.
        var it = std.mem.splitScalar(u8, line, ' ');
        _ = it.next(); // STATUS
        if (it.next()) |tok| {
            if (std.mem.eql(u8, tok, "RUN") or std.mem.eql(u8, tok, "RUNNING")) {
                self.status.state = .run;
            } else if (std.mem.eql(u8, tok, "HOLD") or std.mem.eql(u8, tok, "PAUSED")) {
                self.status.state = .hold;
            } else if (std.mem.eql(u8, tok, "JOG") or std.mem.eql(u8, tok, "JOGGING")) {
                self.status.state = .jog;
            } else if (std.mem.eql(u8, tok, "HOME") or std.mem.eql(u8, tok, "HOMING")) {
                self.status.state = .home;
            } else if (std.mem.eql(u8, tok, "ALARM")) {
                self.status.state = .alarm;
            } else {
                self.status.state = .idle;
            }
        } else {
            self.status.state = .idle;
        }

        self.estop_active = tokenEq(line, "ESTOP=1");
        if (self.estop_active) self.status.state = .alarm;

        if (parseKeyVal(line, "SPINDLE_RPM=")) |rpm| {
            const irpm: u32 = @intFromFloat(@max(0, @min(rpm, 999999)));
            self.status.spindle_speed = irpm;
            self.status.spindle_actual = irpm;
        }
        if (parseKeyValU8(line, "SPINDLE_DIR=")) |dir| {
            self.status.spindle_dir = switch (dir) {
                1 => .cw,
                2 => .ccw,
                else => .stop,
            };
        } else if (tokenEq(line, "SPINDLE_DIR=CW") or tokenEq(line, "SPINDLE=CW")) {
            self.status.spindle_dir = .cw;
            if (self.status.spindle_speed == 0) self.status.spindle_speed = 1;
        } else if (tokenEq(line, "SPINDLE_DIR=CCW") or tokenEq(line, "SPINDLE=CCW")) {
            self.status.spindle_dir = .ccw;
            if (self.status.spindle_speed == 0) self.status.spindle_speed = 1;
        } else if (tokenEq(line, "SPINDLE_DIR=OFF") or tokenEq(line, "SPINDLE=OFF")) {
            self.status.spindle_dir = .stop;
            self.status.spindle_speed = 0;
            self.status.spindle_actual = 0;
        }
        return .status;
    }

    fn parsePos(self: *Parser, line: []const u8) ParseEvent {
        const rest = if (line.len > 4) line[4..] else "";
        if (std.mem.indexOf(u8, rest, "X=")) |_| {
            self.status.mpos.x = parseKeyVal(rest, "X=") orelse self.status.mpos.x;
            self.status.mpos.y = parseKeyVal(rest, "Y=") orelse self.status.mpos.y;
            self.status.mpos.z = parseKeyVal(rest, "Z=") orelse self.status.mpos.z;
            if (parseKeyVal(rest, "WX=")) |wx| {
                self.status.wpos.x = wx;
                self.status.wpos.y = parseKeyVal(rest, "WY=") orelse self.status.wpos.y;
                self.status.wpos.z = parseKeyVal(rest, "WZ=") orelse self.status.wpos.z;
            } else {
                self.status.wpos = self.status.mpos;
            }
        } else {
            var it = std.mem.splitScalar(u8, rest, ' ');
            if (it.next()) |tok| self.status.mpos.x = std.fmt.parseFloat(f32, tok) catch self.status.mpos.x;
            if (it.next()) |tok| self.status.mpos.y = std.fmt.parseFloat(f32, tok) catch self.status.mpos.y;
            if (it.next()) |tok| self.status.mpos.z = std.fmt.parseFloat(f32, tok) catch self.status.mpos.z;
            self.status.wpos = self.status.mpos;
        }
        return .pos;
    }

    fn parseOvr(self: *Parser, line: []const u8) ParseEvent {
        if (parseKeyValU8(line, "FEED=")) |pct| self.status.overrides.feed = pct;
        if (parseKeyValU8(line, "SPINDLE=")) |pct| self.status.overrides.spindle = pct;
        if (parseKeyValU8(line, "RAPID=")) |pct| self.status.overrides.rapid = pct;
        return .ovr;
    }

    fn tokenEq(line: []const u8, needle: []const u8) bool {
        return std.mem.indexOf(u8, line, needle) != null;
    }

    fn parseKeyVal(line: []const u8, key: []const u8) ?f32 {
        if (std.mem.indexOf(u8, line, key)) |idx| {
            const start = idx + key.len;
            var end = start;
            while (end < line.len and line[end] != ' ') : (end += 1) {}
            return std.fmt.parseFloat(f32, line[start..end]) catch null;
        }
        return null;
    }

    fn parseKeyValU8(line: []const u8, key: []const u8) ?u8 {
        if (std.mem.indexOf(u8, line, key)) |idx| {
            const start = idx + key.len;
            var end = start;
            while (end < line.len and line[end] != ' ') : (end += 1) {}
            return parse_util.parseU8(line[start..end]);
        }
        return null;
    }
};

test {
    var p = Parser.init();
    try std.testing.expectEqual(parse_event.ParseEvent.hello_ack, p.parseLine("HELLO ACK Mach3"));
    try std.testing.expectEqual(parse_event.ParseEvent.pos, p.parseLine("POS X=1.5 Y=2.0 Z=-0.5"));
    try std.testing.expectEqual(@as(f32, 1.5), p.status.mpos.x);
    _ = p.parseLine("STATUS RUN ENABLED=1 ESTOP=0");
    try std.testing.expectEqual(cnc_state.MachineState.run, p.status.state);
    // "OVERRUN" must not force RUN via substring match
    _ = p.parseLine("STATUS IDLE ENABLED=1 ESTOP=0 NOTES=OVERRUN");
    try std.testing.expectEqual(cnc_state.MachineState.idle, p.status.state);
    _ = p.parseLine("STATUS IDLE ENABLED=0 ESTOP=1");
    try std.testing.expect(p.estop_active);
    try std.testing.expectEqual(cnc_state.MachineState.alarm, p.status.state);
    _ = p.parseLine("STATUS IDLE SPINDLE_RPM=2400 SPINDLE_DIR=CW");
    try std.testing.expectEqual(@as(u32, 2400), p.status.spindle_speed);
    try std.testing.expectEqual(cnc_state.SpindleState.cw, p.status.spindle_dir);
}
