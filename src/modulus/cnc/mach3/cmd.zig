//! MMBP outbound command builders — zero alloc.

const std = @import("std");
const session = @import("session.zig");

fn fmtLen(buf: []u8, comptime fmt: []const u8, args: anytype) usize {
    const written = std.fmt.bufPrint(buf, fmt, args) catch return 0;
    return written.len;
}

pub fn hello(buf: []u8) usize {
    return fmtLen(buf, "HELLO {s} {s}\n", .{ session.k_client_name, session.k_client_version });
}

pub fn getStatus(buf: []u8) usize {
    return fmtLen(buf, "GET STATUS\n", .{});
}

pub fn getPos(buf: []u8) usize {
    return fmtLen(buf, "GET POS\n", .{});
}

pub fn getOvr(buf: []u8) usize {
    return fmtLen(buf, "GET OVR\n", .{});
}

pub fn cmdCycleStart(buf: []u8) usize {
    return fmtLen(buf, "CMD CYCLE_START\n", .{});
}

pub fn cmdFeedHold(buf: []u8) usize {
    return fmtLen(buf, "CMD FEED_HOLD\n", .{});
}

pub fn cmdStop(buf: []u8) usize {
    return fmtLen(buf, "CMD STOP\n", .{});
}

pub fn cmdReset(buf: []u8) usize {
    return fmtLen(buf, "CMD RESET\n", .{});
}

pub fn cmdUnlock(buf: []u8) usize {
    return fmtLen(buf, "CMD UNLOCK\n", .{});
}

pub fn cmdHomeAll(buf: []u8) usize {
    return fmtLen(buf, "CMD HOME -1\n", .{});
}

pub fn cmdHomeAxis(buf: []u8, axis: u8) usize {
    return fmtLen(buf, "CMD HOME {c}\n", .{axis});
}

pub fn cmdMdi(buf: []u8, line: []const u8) usize {
    if (line.len + 10 > buf.len) return 0;
    return fmtLen(buf, "CMD MDI {s}\n", .{line});
}

pub fn cmdJogIncr(buf: []u8, axis_dir: []const u8, distance: f32, feed: f32) usize {
    return fmtLen(buf, "CMD JOG {s} {d:.4} {d:.4}\n", .{ axis_dir, distance, feed });
}

pub fn cmdJogCont(buf: []u8, axis_dir: []const u8, feed: f32) usize {
    return fmtLen(buf, "CMD JOG_CONT {s} {d:.4}\n", .{ axis_dir, feed });
}

pub fn cmdJogStop(buf: []u8, axis: u8) usize {
    return fmtLen(buf, "CMD JOG_STOP {c}\n", .{axis});
}

pub fn cmdFeedOverride(buf: []u8, pct: u8) usize {
    return fmtLen(buf, "CMD FEED_OVR {d}\n", .{pct});
}

pub fn cmdSpindleOverride(buf: []u8, pct: u8) usize {
    return fmtLen(buf, "CMD SPINDLE_OVR {d}\n", .{pct});
}

pub fn cmdFlood(buf: []u8, on: bool) usize {
    return fmtLen(buf, "CMD FLOOD {s}\n", .{if (on) "ON" else "OFF"});
}

pub fn cmdMist(buf: []u8, on: bool) usize {
    return fmtLen(buf, "CMD MIST {s}\n", .{if (on) "ON" else "OFF"});
}

pub fn cmdSpindleStop(buf: []u8) usize {
    return fmtLen(buf, "CMD SPINDLE STOP\n", .{});
}
