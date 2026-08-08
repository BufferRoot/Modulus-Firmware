//! grblHAL line parser — status reports, ok/error/alarm, welcome banner.

const std = @import("std");
const str_util = @import("../../core/str_util.zig");
const parse_util = @import("parse_util.zig");
const bracket = @import("bracket.zig");
const capabilities = @import("capabilities.zig");
const cnc_state = @import("../cnc_state.zig");
const parse_event = @import("parse_event.zig");
const parser_status = @import("parser_status.zig");

pub const line_buf_max = 256;
pub const ParseEvent = parse_event.ParseEvent;

pub const Parser = struct {
    status: cnc_state.MachineStatus = .{},
    ctrl_info: capabilities.ControllerInfo = .{},
    last_error: u8 = 0,
    last_alarm: u8 = 0,
    last_setting_id: u16 = 0,
    last_setting_val: [64]u8 = [_]u8{0} ** 64,
    last_msg: [128]u8 = [_]u8{0} ** 128,
    welcome_ver: [16]u8 = undefined,

    pub fn init() Parser {
        var p: Parser = .{};
        p.welcome_ver[0] = 0;
        return p;
    }

    pub fn parseLine(self: *Parser, line: []const u8) ParseEvent {
        if (line.len == 0) return .none;

        if (line.len >= 2 and line[0] == '<' and line[line.len - 1] == '>') {
            parser_status.parseStatusReport(self, line[1 .. line.len - 1]);
            return .status_report;
        }

        if (line.len >= 2 and line[0] == '[' and line[line.len - 1] == ']') {
            var ctx = bracket.Context{
                .status = &self.status,
                .ctrl_info = &self.ctrl_info,
                .last_msg = &self.last_msg,
            };
            return bracket.parseBracketMessage(&ctx, line[1 .. line.len - 1]);
        }

        if (line.len == 2 and std.mem.eql(u8, line, "ok")) return .ok;

        if (line.len >= 6 and std.mem.startsWith(u8, line, "error:")) {
            self.last_error = parse_util.parseU8(line[6..]) orelse 0;
            return .err;
        }

        if (line.len >= 6 and std.mem.startsWith(u8, line, "ALARM:")) {
            self.last_alarm = parse_util.parseU8(line[6..]) orelse 0;
            self.status.alarm_code = self.last_alarm;
            self.status.state = .alarm;
            return .alarm;
        }

        if (std.mem.startsWith(u8, line, "Grbl")) {
            parseWelcome(self, line);
            return .welcome;
        }

        if (line[0] == '$' and line.len > 2) {
            if (std.mem.indexOfScalar(u8, line, '=')) |eq| {
                self.last_setting_id = parse_util.parseU16(line[1..eq]) orelse 0;
                str_util.copy(&self.last_setting_val, line[eq + 1 ..]);
                return .setting;
            }
        }

        return .none;
    }

    fn parseWelcome(self: *Parser, line: []const u8) void {
        var start: usize = 4;
        if (line.len > 4 and line[4] == 'H') {
            if (std.mem.indexOfScalar(u8, line, ' ')) |sp| start = sp + 1;
        }
        if (start >= line.len) return;
        const rest = line[start..];
        const end = std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len;
        const copy_len = @min(end, self.welcome_ver.len - 1);
        @memcpy(self.welcome_ver[0..copy_len], rest[0..copy_len]);
        self.welcome_ver[copy_len] = 0;
    }
};

test {
    _ = @import("parser_tests.zig");
    _ = @import("parser_fuzz.zig");
}
