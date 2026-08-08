//! grblHAL outbound command builders — zero alloc, caller buffer.

const std = @import("std");
const rt = @import("rt.zig");

fn fmtLen(buf: []u8, comptime fmt: []const u8, args: anytype) usize {
    const written = std.fmt.bufPrint(buf, fmt, args) catch return 0;
    return written.len;
}

pub fn jog(buf: []u8, axis: u8, distance: f32, feed: f32, incremental: bool, metric: bool) usize {
    if (buf.len < 32) return 0;
    return fmtLen(buf, "$J={s} {s} {c}{d:.4} F{d:.1}\n", .{
        if (incremental) "G91" else "G90",
        if (metric) "G21" else "G20",
        axis,
        distance,
        feed,
    });
}

pub fn jogCancel(buf: []u8) usize {
    if (buf.len < 1) return 0;
    buf[0] = rt.JOG_CANCEL;
    return 1;
}

pub fn homeAll(buf: []u8) usize {
    return fmtLen(buf, "$H\n", .{});
}

pub fn homeAxis(buf: []u8, axis: u8) usize {
    return fmtLen(buf, "$H{c}\n", .{axis});
}

pub fn unlock(buf: []u8) usize {
    return fmtLen(buf, "$X\n", .{});
}

pub fn softReset(buf: []u8) usize {
    if (buf.len < 1) return 0;
    buf[0] = rt.SOFT_RESET;
    return 1;
}

pub fn cycleStart(buf: []u8) usize {
    if (buf.len < 1) return 0;
    buf[0] = rt.CYCLE_START_ALT;
    return 1;
}

pub fn feedHold(buf: []u8) usize {
    if (buf.len < 1) return 0;
    buf[0] = rt.FEED_HOLD_ALT;
    return 1;
}

pub fn statusQuery(buf: []u8, full: bool) usize {
    if (buf.len < 1) return 0;
    buf[0] = if (full) rt.FULL_STATUS_REQ else rt.STATUS_QUERY_ALT;
    return 1;
}

/// Stock Grbl 1.1 status poll — literal `?` (not grblHAL 0x80/0x87).
pub fn classicStatusQuery(buf: []u8) usize {
    if (buf.len < 1) return 0;
    buf[0] = '?';
    return 1;
}

pub fn systemInfo(buf: []u8, extended: bool) usize {
    if (extended) return fmtLen(buf, "$I+\n", .{});
    return fmtLen(buf, "$I\n", .{});
}

pub fn feedOverrideByte(delta_pct: i8) u8 {
    if (delta_pct == 0) return rt.FEED_OVR_RESET;
    if (delta_pct >= 10) return rt.FEED_OVR_INC_10;
    if (delta_pct <= -10) return rt.FEED_OVR_DEC_10;
    if (delta_pct > 0) return rt.FEED_OVR_INC_1;
    return rt.FEED_OVR_DEC_1;
}

pub fn rapidOverrideByte(pct: u8) u8 {
    if (pct <= 25) return rt.RAPID_OVR_25;
    if (pct <= 50) return rt.RAPID_OVR_50;
    return rt.RAPID_OVR_RESET;
}

pub fn spindleOverrideByte(delta_pct: i8) u8 {
    if (delta_pct == 0) return rt.SPINDLE_OVR_RESET;
    if (delta_pct >= 10) return rt.SPINDLE_OVR_INC_10;
    if (delta_pct <= -10) return rt.SPINDLE_OVR_DEC_10;
    if (delta_pct > 0) return rt.SPINDLE_OVR_INC_1;
    return rt.SPINDLE_OVR_DEC_1;
}

pub fn mpgToggle(buf: []u8) usize {
    if (buf.len < 1) return 0;
    buf[0] = rt.MPG_MODE_TOGGLE;
    return 1;
}

pub fn gcode(buf: []u8, line: []const u8) usize {
    if (line.len + 1 > buf.len) return 0;
    @memcpy(buf[0..line.len], line);
    buf[line.len] = '\n';
    return line.len + 1;
}

pub fn spindleStopToggle(buf: []u8) usize {
    if (buf.len < 1) return 0;
    buf[0] = rt.SPINDLE_STOP_TOG;
    return 1;
}

pub fn coolantFloodToggle(buf: []u8) usize {
    if (buf.len < 1) return 0;
    buf[0] = rt.COOLANT_FLOOD_TOG;
    return 1;
}

pub fn coolantMistToggle(buf: []u8) usize {
    if (buf.len < 1) return 0;
    buf[0] = rt.COOLANT_MIST_TOG;
    return 1;
}

pub fn fanToggle(buf: []u8) usize {
    if (buf.len < 1) return 0;
    buf[0] = rt.FAN0_TOGGLE;
    return 1;
}

pub fn singleStepToggle(buf: []u8) usize {
    if (buf.len < 1) return 0;
    buf[0] = rt.SINGLE_STEP_TOGGLE;
    return 1;
}

pub fn stop(buf: []u8) usize {
    if (buf.len < 1) return 0;
    buf[0] = rt.STOP;
    return 1;
}

pub fn parserStateReq(buf: []u8) usize {
    if (buf.len < 1) return 0;
    buf[0] = rt.PARSER_STATE_REQ;
    return 1;
}

/// Classic Grbl / FluidNC — text `$G` (0x83 is grblHAL-only).
pub fn parserStateText(buf: []u8) usize {
    return fmtLen(buf, "$G\n", .{});
}

pub fn enumAlarms(buf: []u8) usize {
    return fmtLen(buf, "$EA\n", .{});
}

pub fn enumErrors(buf: []u8) usize {
    return fmtLen(buf, "$EE\n", .{});
}

pub fn enumSettings(buf: []u8) usize {
    return fmtLen(buf, "$ES\n", .{});
}

pub fn enumGroups(buf: []u8) usize {
    return fmtLen(buf, "$EG\n", .{});
}

test "cnc: cmd enumeration builders" {
    var b: [8]u8 = undefined;
    try std.testing.expectEqualStrings("$EA\n", b[0..enumAlarms(&b)]);
    try std.testing.expectEqualStrings("$EE\n", b[0..enumErrors(&b)]);
    try std.testing.expectEqualStrings("$ES\n", b[0..enumSettings(&b)]);
    try std.testing.expectEqualStrings("$EG\n", b[0..enumGroups(&b)]);
    try std.testing.expectEqual(rt.STOP, blk: {
        var s: [1]u8 = undefined;
        _ = stop(&s);
        break :blk s[0];
    });
    try std.testing.expectEqual(rt.PARSER_STATE_REQ, blk: {
        var s: [1]u8 = undefined;
        _ = parserStateReq(&s);
        break :blk s[0];
    });
}

test "cnc: cmd rt override bytes" {
    try std.testing.expectEqual(rt.FEED_OVR_RESET, feedOverrideByte(0));
    try std.testing.expectEqual(rt.FEED_OVR_INC_10, feedOverrideByte(10));
    try std.testing.expectEqual(rt.FEED_OVR_DEC_1, feedOverrideByte(-1));
    try std.testing.expectEqual(rt.RAPID_OVR_25, rapidOverrideByte(20));
    try std.testing.expectEqual(rt.SPINDLE_OVR_INC_1, spindleOverrideByte(1));
    try std.testing.expectEqual(rt.MPG_MODE_TOGGLE, blk: {
        var b: [1]u8 = undefined;
        _ = mpgToggle(&b);
        break :blk b[0];
    });
    try std.testing.expectEqual(rt.COOLANT_MIST_TOG, blk: {
        var b: [1]u8 = undefined;
        _ = coolantMistToggle(&b);
        break :blk b[0];
    });
    try std.testing.expectEqual(rt.FAN0_TOGGLE, blk: {
        var b: [1]u8 = undefined;
        _ = fanToggle(&b);
        break :blk b[0];
    });
    try std.testing.expectEqual(rt.SINGLE_STEP_TOGGLE, blk: {
        var b: [1]u8 = undefined;
        _ = singleStepToggle(&b);
        break :blk b[0];
    });
}
