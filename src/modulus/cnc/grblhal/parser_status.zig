//! grblHAL `<...>` status report token parsing.

const std = @import("std");
const str_util = @import("../../core/str_util.zig");
const parse_util = @import("parse_util.zig");
const cnc_state = @import("../cnc_state.zig");
const rt = @import("rt.zig");
const probe_parse = @import("probe_parse.zig");

const StateTag = struct {
    name: []const u8,
    state: cnc_state.MachineState,
    sub_field: enum { none, run, hold, door, alarm },
};
const state_tags = [_]StateTag{
    .{ .name = "Idle",  .state = .idle,  .sub_field = .none  },
    .{ .name = "Run",   .state = .run,   .sub_field = .run   },
    .{ .name = "Hold",  .state = .hold,  .sub_field = .hold  },
    .{ .name = "Jog",   .state = .jog,   .sub_field = .none  },
    .{ .name = "Alarm", .state = .alarm, .sub_field = .alarm },
    .{ .name = "Door",  .state = .door,  .sub_field = .door  },
    .{ .name = "Check", .state = .check, .sub_field = .none  },
    .{ .name = "Home",  .state = .home,  .sub_field = .none  },
    .{ .name = "Sleep", .state = .sleep, .sub_field = .none  },
    .{ .name = "Tool",  .state = .tool,  .sub_field = .none  },
};

const StatusTag = enum { mpos, wpos, wco, fs, f, ov, pn, bf, ln, wcs, h, mpg, a, d, sc, tlr, sd, in, fw, tool, percent, prb };
const status_tag_map = std.StaticStringMap(StatusTag).initComptime(.{
    .{ "MPos", .mpos }, .{ "WPos", .wpos }, .{ "WCO", .wco },
    .{ "FS", .fs },     .{ "F", .f },       .{ "Ov", .ov },
    .{ "Pn", .pn },     .{ "Bf", .bf },     .{ "Ln", .ln },
    .{ "WCS", .wcs },   .{ "H", .h },       .{ "MPG", .mpg },
    .{ "A", .a },       .{ "D", .d },       .{ "Sc", .sc },
    .{ "TLR", .tlr },   .{ "SD", .sd },     .{ "In", .in },
    .{ "FW", .fw },     .{ "T", .tool },    .{ "Percent", .percent },
    .{ "PRB", .prb },
});

pub fn parseStatusReport(p: anytype, data: []const u8) void {
    var parts = std.mem.splitScalar(u8, data, '|');
    var first = true;
    var saw_mpos = false;
    var saw_wpos = false;
    // grblHAL omits |Pn: entirely when no pins are asserted — absence means
    // "all released". Without this reset the last asserted bits (probe,
    // limits, door) latch forever, which broke any live pin indicator.
    p.status.pin_state = 0;
    while (parts.next()) |token| {
        if (first) {
            first = false;
            parseStateToken(p, token);
            continue;
        }
        if (std.mem.indexOfScalar(u8, token, ':')) |colon| {
            const tag = token[0..colon];
            const val = token[colon + 1 ..];
            if (status_tag_map.get(tag)) |t| switch (t) {
                .mpos => { parsePosition(val, &p.status.mpos); saw_mpos = true; },
                .wpos => { parsePosition(val, &p.status.wpos); saw_wpos = true; },
                .wco  => parsePosition(val, &p.status.wco),
                .fs, .f => parseFeedSpeed(p, val),
                .ov   => parseOverrides(p, val),
                .pn   => parsePins(p, val),
                .bf   => parseBuffer(p, val),
                .ln   => p.status.line_number = parse_util.parseU32(val) orelse 0,
                .wcs  => parseWcs(p, val),
                .h    => parseHoming(p, val),
                .mpg  => p.status.mpg_remote = (parse_util.parseU8(val) orelse 0) != 0,
                .a    => parseAccessories(p, val),
                .d    => p.status.diameter_mode = (parse_util.parseU8(val) orelse 0) != 0,
                .sc   => parseScaledAxes(p, val),
                .tlr  => p.status.tlr_set = (parse_util.parseU8(val) orelse 0) != 0,
                .sd   => parseSdTag(p, val),
                .percent => parsePercentTag(p, val),
                .prb => _ = probe_parse.applyProbeBody(&p.status, val),
                .in   => p.status.last_input_result = parse_util.parseI16(val) orelse 0,
                .fw   => str_util.copy(&p.ctrl_info.firmware, val),
                .tool => p.status.tool_number = parse_util.parseU8(val) orelse 0,
            };
        }
    }
    if (saw_mpos) deriveWorkFromMachine(p) else if (saw_wpos) deriveMachineFromWork(p);
    deriveLegacyFields(p);
}

fn parseStateToken(p: anytype, token: []const u8) void {
    var name = token;
    var sub: u8 = 0;
    if (std.mem.indexOfScalar(u8, token, ':')) |colon| {
        name = token[0..colon];
        sub = parse_util.parseU8(token[colon + 1 ..]) orelse 0;
    }

    inline for (state_tags) |tag| {
        if (std.mem.eql(u8, name, tag.name)) {
            p.status.state = tag.state;
            switch (tag.sub_field) {
                .none => {},
                .run => p.status.run_substate = sub,
                .hold => p.status.hold_substate = sub,
                .door => p.status.door_substate = sub,
                .alarm => p.status.alarm_code = sub,
            }
            return;
        }
    }
}

fn parseSdTag(p: anytype, val: []const u8) void {
    if (std.mem.indexOfScalar(u8, val, ',')) |comma| {
        p.status.sd_streaming = true;
        p.status.sd_percent = std.fmt.parseFloat(f32, val[0..comma]) catch 0;
        const path = val[comma + 1 ..];
        @memset(&p.status.sd_file, 0);
        // Prefer basename after last '/' or '\'.
        var base = path;
        if (std.mem.lastIndexOfScalar(u8, path, '/')) |i| base = path[i + 1 ..];
        if (std.mem.lastIndexOfScalar(u8, base, '\\')) |i| base = base[i + 1 ..];
        const n = @min(base.len, p.status.sd_file.len - 1);
        @memcpy(p.status.sd_file[0..n], base[0..n]);
    } else if (std.mem.eql(u8, val, "Pending")) {
        p.status.sd_streaming = true;
    } else if (std.mem.indexOfScalar(u8, val, '.') != null) {
        // Percent-only: `SD:45.5` (no filename). Bare ints stay SD card state.
        if (std.fmt.parseFloat(f32, val)) |pct| {
            p.status.sd_streaming = true;
            p.status.sd_percent = pct;
        } else |_| {}
    } else {
        p.status.sd_state = parse_util.parseU8(val) orelse 0;
        p.status.sd_streaming = false;
        @memset(&p.status.sd_file, 0);
    }
}

fn parsePercentTag(p: anytype, val: []const u8) void {
    // FluidNC job progress: `|Percent:45.5|`
    if (std.fmt.parseFloat(f32, val)) |pct| {
        p.status.sd_percent = pct;
        if (pct > 0) p.status.sd_streaming = true;
    } else |_| {}
}

fn parseScaledAxes(p: anytype, val: []const u8) void {
    p.status.scaled_axes = 0;
    for (val) |c| {
        const idx: i8 = switch (c) {
            'X'...'Z' => @intCast(c - 'X'),
            'A'...'C' => @intCast(c - 'A' + 3),
            'U' => 6,
            'V' => 7,
            else => -1,
        };
        if (idx >= 0) p.status.scaled_axes |= @as(u8, 1) << @intCast(idx);
    }
}

fn parsePosition(val: []const u8, pos: *cnc_state.Position) void {
    var iter = std.mem.splitScalar(u8, val, ',');
    const fields = [_]*f32{ &pos.x, &pos.y, &pos.z, &pos.a, &pos.b, &pos.c };
    var i: usize = 0;
    while (iter.next()) |part| : (i += 1) {
        if (i >= fields.len) break;
        fields[i].* = std.fmt.parseFloat(f32, part) catch 0;
    }
}

fn parseFeedSpeed(p: anytype, val: []const u8) void {
    var iter = std.mem.splitScalar(u8, val, ',');
    if (iter.next()) |f| p.status.feed_rate = std.fmt.parseFloat(f32, f) catch 0;
    if (iter.next()) |s| p.status.spindle_speed = parse_util.parseU32(s) orelse 0;
    if (iter.next()) |a| p.status.spindle_actual = parse_util.parseU32(a) orelse 0;
}

fn parsePins(p: anytype, val: []const u8) void {
    p.status.pin_state = 0;
    for (val) |c| p.status.pin_state |= rt.pin.fromChar(c);
}

fn parseBuffer(p: anytype, val: []const u8) void {
    var iter = std.mem.splitScalar(u8, val, ',');
    if (iter.next()) |b| p.status.buf_plan = parse_util.parseU16(b) orelse 0;
    if (iter.next()) |r| p.status.buf_rx = parse_util.parseU16(r) orelse 0;
}

fn parseHoming(p: anytype, val: []const u8) void {
    var iter = std.mem.splitScalar(u8, val, ',');
    if (iter.next()) |h| p.status.homed = (parse_util.parseU8(h) orelse 0) != 0;
    if (iter.next()) |m| p.status.homed_axes = parse_util.parseU8(m) orelse 0;
}

fn parseWcs(p: anytype, val: []const u8) void {
    if (val.len < 2 or val[0] != 'G') return;
    const dot = std.mem.indexOfScalar(u8, val, '.');
    const major_str = if (dot) |d| val[1..d] else val[1..];
    const major = parse_util.parseU16(major_str) orelse return;
    const minor: u16 = if (dot) |d| (parse_util.parseU16(val[d + 1 ..]) orelse 0) else 0;
    p.status.wcs = switch (major) {
        54 => .g54,
        55 => .g55,
        56 => .g56,
        57 => .g57,
        58 => .g58,
        59 => switch (minor) {
            0 => .g59,
            1 => .g59_1,
            2 => .g59_2,
            3 => .g59_3,
            else => p.status.wcs,
        },
        else => p.status.wcs,
    };
}

fn posVec(pos: anytype) @Vector(6, f32) {
    return .{ pos.x, pos.y, pos.z, pos.a, pos.b, pos.c };
}

fn vecToPos(r: @Vector(6, f32)) cnc_state.Position {
    return .{ .x = r[0], .y = r[1], .z = r[2], .a = r[3], .b = r[4], .c = r[5] };
}

fn deriveWorkFromMachine(p: anytype) void {
    p.status.wpos = vecToPos(posVec(p.status.mpos) - posVec(p.status.wco));
}

fn deriveMachineFromWork(p: anytype) void {
    p.status.mpos = vecToPos(posVec(p.status.wpos) + posVec(p.status.wco));
}

fn parseOverrides(p: anytype, val: []const u8) void {
    var iter = std.mem.splitScalar(u8, val, ',');
    if (iter.next()) |f| p.status.overrides.feed = parse_util.parseU8(f) orelse 100;
    if (iter.next()) |r| p.status.overrides.rapid = parse_util.parseU8(r) orelse 100;
    if (iter.next()) |s| p.status.overrides.spindle = parse_util.parseU8(s) orelse 100;
}

fn parseAccessories(p: anytype, val: []const u8) void {
    p.status.accessories = 0;
    for (val) |c| p.status.accessories |= rt.accessory.fromChar(c);
}

fn deriveLegacyFields(p: anytype) void {
    p.status.coolant_on = (p.status.accessories & rt.accessory.COOLANT_FLOOD) != 0 or
        (p.status.accessories & rt.accessory.COOLANT_MIST) != 0;
    if (p.status.accessories & rt.accessory.SPINDLE_CW != 0) {
        p.status.spindle_dir = .cw;
    } else if (p.status.accessories & rt.accessory.SPINDLE_CCW != 0) {
        p.status.spindle_dir = .ccw;
    } else {
        p.status.spindle_dir = .stop;
    }
}
