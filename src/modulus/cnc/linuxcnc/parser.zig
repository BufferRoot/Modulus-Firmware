//! LinuxCNC linuxcncrsh line parser — HELLO/GET responses to `MachineStatus`.

const std = @import("std");
const parse_util = @import("../grblhal/parse_util.zig");
const cnc_state = @import("../cnc_state.zig");
const parse_event = @import("parse_event.zig");
const session = @import("session.zig");
const str_util = @import("../../core/str_util.zig");

pub const ParseEvent = parse_event.ParseEvent;
pub const line_buf_max = 256;

pub const Parser = struct {
    status: cnc_state.MachineStatus = .{},
    connect_pw: [16]u8 = undefined,
    enable_pw: [16]u8 = undefined,
    flood_on: bool = false,
    mist_on: bool = false,
    /// Last MDI `S` word — linuxcncrsh has no encoder RPM get.
    commanded_rpm: u32 = 0,
    /// Last INI pull fields for dump synthesis.
    ini_section: [24]u8 = .{0} ** 24,
    ini_key: [32]u8 = .{0} ** 32,
    ini_value: f32 = 0,
    ini_ok: bool = false,

    pub fn init() Parser {
        var p: Parser = .{};
        str_util.copy(&p.connect_pw, session.k_default_connect_pw);
        str_util.copy(&p.enable_pw, session.k_default_enable_pw);
        return p;
    }

    pub fn setPasswords(self: *Parser, connect_pw: []const u8, enable_pw: []const u8) void {
        str_util.copy(&self.connect_pw, connect_pw);
        str_util.copy(&self.enable_pw, enable_pw);
    }

    pub fn noteCommandedRpm(self: *Parser, rpm: u32) void {
        self.commanded_rpm = rpm;
        if (self.status.spindle_dir != .stop) applyCommandedRpm(self);
    }

    pub fn parseLine(self: *Parser, line: []const u8) ParseEvent {
        if (line.len == 0) return .none;
        if (std.mem.startsWith(u8, line, "HELLO ACK")) return .hello_ack;
        if (std.mem.eql(u8, line, "HELLO NAK")) return .hello_nak;
        if (std.mem.startsWith(u8, line, "ENABLE ON")) return .enable_on;
        if (std.mem.startsWith(u8, line, "ENABLE OFF")) return .enable_off;
        if (std.mem.startsWith(u8, line, "ESTOP ON")) {
            self.status.state = .alarm;
            return .estop_on;
        }
        if (std.mem.startsWith(u8, line, "ESTOP OFF")) {
            if (self.status.state == .alarm) self.status.state = .idle;
            return .estop_off;
        }
        if (std.mem.startsWith(u8, line, "MACHINE ON")) return .machine_on;
        if (std.mem.startsWith(u8, line, "MACHINE OFF")) return .machine_off;
        if (std.mem.startsWith(u8, line, "MODE MANUAL")) return .mode_manual;
        if (std.mem.startsWith(u8, line, "PROGRAM_STATUS")) return parseProgramStatus(self, line);
        if (std.mem.startsWith(u8, line, "ABS_ACT_POS")) return parseAbsActPos(self, line);
        if (std.mem.startsWith(u8, line, "REL_ACT_POS")) return parseRelActPos(self, line);
        if (std.mem.startsWith(u8, line, "FEED_OVERRIDE")) return parseFeedOverride(self, line);
        if (std.mem.startsWith(u8, line, "SPINDLE_OVERRIDE")) return parseSpindleOverride(self, line);
        if (std.mem.startsWith(u8, line, "SPINDLE ")) return parseSpindle(self, line);
        if (std.mem.eql(u8, line, "FORWARD") or std.mem.eql(u8, line, "REVERSE") or
            std.mem.eql(u8, line, "OFF") or std.mem.eql(u8, line, "INCREASE") or
            std.mem.eql(u8, line, "DECREASE") or std.mem.eql(u8, line, "CONSTANT"))
        {
            return parseSpindleToken(self, line);
        }
        if (std.mem.startsWith(u8, line, "JOINT_HOMED")) return parseJointHomed(self, line);
        if (std.mem.startsWith(u8, line, "INI ")) return parseIni(self, line);
        if (std.mem.startsWith(u8, line, "SET ACK")) return .set_ack;
        if (std.mem.startsWith(u8, line, "ERROR")) return .err;
        return .none;
    }

    fn parseProgramStatus(self: *Parser, line: []const u8) ParseEvent {
        if (std.mem.endsWith(u8, line, "RUNNING")) {
            self.status.state = .run;
        } else if (std.mem.endsWith(u8, line, "PAUSED")) {
            self.status.state = .hold;
        } else {
            self.status.state = .idle;
        }
        return .program_status;
    }

    fn parseAbsActPos(self: *Parser, line: []const u8) ParseEvent {
        var it = std.mem.splitScalar(u8, line, ' ');
        _ = it.next();
        if (it.next()) |tok| self.status.mpos.x = std.fmt.parseFloat(f32, tok) catch self.status.mpos.x;
        if (it.next()) |tok| self.status.mpos.y = std.fmt.parseFloat(f32, tok) catch self.status.mpos.y;
        if (it.next()) |tok| self.status.mpos.z = std.fmt.parseFloat(f32, tok) catch self.status.mpos.z;
        return .abs_act_pos;
    }

    fn parseRelActPos(self: *Parser, line: []const u8) ParseEvent {
        var it = std.mem.splitScalar(u8, line, ' ');
        _ = it.next();
        if (it.next()) |tok| self.status.wpos.x = std.fmt.parseFloat(f32, tok) catch self.status.wpos.x;
        if (it.next()) |tok| self.status.wpos.y = std.fmt.parseFloat(f32, tok) catch self.status.wpos.y;
        if (it.next()) |tok| self.status.wpos.z = std.fmt.parseFloat(f32, tok) catch self.status.wpos.z;
        return .rel_act_pos;
    }

    fn parsePct(tok: []const u8) u8 {
        if (parse_util.parseU8(tok)) |v| return v;
        const f = std.fmt.parseFloat(f32, tok) catch return 100;
        const clamped = std.math.clamp(f, 0.0, 255.0);
        return @intFromFloat(@round(clamped));
    }

    fn parseFeedOverride(self: *Parser, line: []const u8) ParseEvent {
        if (std.mem.lastIndexOfScalar(u8, line, ' ')) |sp| {
            self.status.overrides.feed = parsePct(line[sp + 1 ..]);
        }
        return .feed_override;
    }

    fn parseSpindleOverride(self: *Parser, line: []const u8) ParseEvent {
        if (std.mem.lastIndexOfScalar(u8, line, ' ')) |sp| {
            self.status.overrides.spindle = parsePct(line[sp + 1 ..]);
            if (self.status.spindle_dir != .stop) applyCommandedRpm(self);
        }
        return .spindle_override;
    }

    fn parseSpindle(self: *Parser, line: []const u8) ParseEvent {
        var it = std.mem.splitScalar(u8, line, ' ');
        _ = it.next();
        if (it.next()) |tok| return parseSpindleToken(self, tok);
        return .spindle;
    }

    fn parseSpindleToken(self: *Parser, tok: []const u8) ParseEvent {
        if (std.ascii.eqlIgnoreCase(tok, "forward") or std.ascii.eqlIgnoreCase(tok, "increase") or
            std.ascii.eqlIgnoreCase(tok, "constant"))
        {
            self.status.spindle_dir = .cw;
            applyCommandedRpm(self);
        } else if (std.ascii.eqlIgnoreCase(tok, "reverse") or std.ascii.eqlIgnoreCase(tok, "decrease")) {
            self.status.spindle_dir = .ccw;
            applyCommandedRpm(self);
        } else {
            self.status.spindle_dir = .stop;
            self.status.spindle_speed = 0;
            self.status.spindle_actual = 0;
        }
        return .spindle;
    }

    fn applyCommandedRpm(self: *Parser) void {
        if (self.commanded_rpm == 0) {
            self.status.spindle_speed = 1;
            self.status.spindle_actual = 1;
            return;
        }
        const ovr = @as(u32, self.status.overrides.spindle);
        const rpm = (self.commanded_rpm * ovr) / 100;
        self.status.spindle_speed = rpm;
        self.status.spindle_actual = rpm;
        self.status.spindle_target = self.commanded_rpm;
    }

    fn parseJointHomed(self: *Parser, line: []const u8) ParseEvent {
        var it = std.mem.splitScalar(u8, line, ' ');
        _ = it.next();
        var axes: u8 = 0;
        var idx: u8 = 0;
        var any = false;
        var all_yes = true;
        while (it.next()) |tok| {
            if (idx >= 8) break;
            const yes = std.ascii.eqlIgnoreCase(tok, "YES") or std.ascii.eqlIgnoreCase(tok, "HOMED");
            const no = std.ascii.eqlIgnoreCase(tok, "NO") or std.ascii.eqlIgnoreCase(tok, "NOT");
            if (!yes and !no) continue;
            if (yes) {
                axes |= @as(u8, 1) << @intCast(idx);
                any = true;
            } else {
                all_yes = false;
            }
            idx += 1;
        }
        if (idx == 0) {
            if (std.mem.indexOf(u8, line, "YES") != null) {
                self.status.homed = true;
                self.status.homed_axes = 0x07;
            } else {
                self.status.homed = false;
                self.status.homed_axes = 0;
            }
        } else {
            self.status.homed_axes = axes;
            self.status.homed = any and ((axes & 0x07) == 0x07 or all_yes);
        }
        return .joint_homed;
    }

    fn parseIni(self: *Parser, line: []const u8) ParseEvent {
        self.ini_ok = false;
        var it = std.mem.splitScalar(u8, line, ' ');
        _ = it.next();
        const sec = it.next() orelse return .ini;
        const key = it.next() orelse return .ini;
        const val = it.next() orelse return .ini;
        str_util.copy(&self.ini_section, sec);
        str_util.copy(&self.ini_key, key);
        self.ini_value = std.fmt.parseFloat(f32, val) catch return .ini;
        self.ini_ok = true;
        return .ini;
    }
};

test {
    var p = Parser.init();
    try std.testing.expectEqual(parse_event.ParseEvent.hello_ack, p.parseLine("HELLO ACK EMCNETSVR 1.1"));
    try std.testing.expectEqual(parse_event.ParseEvent.abs_act_pos, p.parseLine("ABS_ACT_POS 1.5 2.0 -0.5"));
    try std.testing.expectEqual(@as(f32, 1.5), p.status.mpos.x);
    _ = p.parseLine("REL_ACT_POS 10 20 30");
    try std.testing.expectEqual(@as(f32, 10), p.status.wpos.x);
    _ = p.parseLine("PROGRAM_STATUS RUNNING");
    try std.testing.expectEqual(cnc_state.MachineState.run, p.status.state);
    _ = p.parseLine("FEED_OVERRIDE 110.5");
    try std.testing.expectEqual(@as(u8, 111), p.status.overrides.feed);
    p.noteCommandedRpm(12000);
    _ = p.parseLine("SPINDLE FORWARD");
    try std.testing.expectEqual(cnc_state.SpindleState.cw, p.status.spindle_dir);
    try std.testing.expectEqual(@as(u32, 12000), p.status.spindle_speed);
    _ = p.parseLine("JOINT_HOMED YES YES YES NO");
    try std.testing.expect(p.status.homed);
    try std.testing.expectEqual(@as(u8, 0x07), p.status.homed_axes & 0x07);
    try std.testing.expectEqual(parse_event.ParseEvent.ini, p.parseLine("INI TRAJ MAX_LINEAR_VELOCITY 50.0"));
    try std.testing.expect(p.ini_ok);
    try std.testing.expectEqual(@as(f32, 50.0), p.ini_value);
}
