//! LinuxCNC linuxcncrsh outbound command builders — zero alloc.

const std = @import("std");
const session = @import("session.zig");

fn fmtLen(buf: []u8, comptime fmt: []const u8, args: anytype) usize {
    const written = std.fmt.bufPrint(buf, fmt, args) catch return 0;
    return written.len;
}

pub fn hello(buf: []u8, connect_pw: []const u8) usize {
    return fmtLen(buf, "hello {s} {s} {s}\n", .{
        connect_pw,
        session.k_client_name,
        session.k_client_version,
    });
}

pub fn setEchoOff(buf: []u8) usize {
    return fmtLen(buf, "set echo off\n", .{});
}

pub fn setVerboseOff(buf: []u8) usize {
    return fmtLen(buf, "set verbose off\n", .{});
}

pub fn setEnable(buf: []u8, enable_pw: []const u8) usize {
    return fmtLen(buf, "set enable {s}\n", .{enable_pw});
}

pub fn setTeleopOn(buf: []u8) usize {
    return fmtLen(buf, "set teleop_enable on\n", .{});
}

pub fn setModeManual(buf: []u8) usize {
    return fmtLen(buf, "set mode manual\n", .{});
}

pub fn setModeAuto(buf: []u8) usize {
    return fmtLen(buf, "set mode auto\n", .{});
}

pub fn setModeMdi(buf: []u8) usize {
    return fmtLen(buf, "set mode mdi\n", .{});
}

pub fn setStep(buf: []u8) usize {
    return fmtLen(buf, "set step\n", .{});
}

pub fn setOptionalStop(buf: []u8, on: bool) usize {
    return fmtLen(buf, "set optional_stop {s}\n", .{if (on) "on" else "off"});
}

pub fn setEstopOff(buf: []u8) usize {
    return fmtLen(buf, "set estop off\n", .{});
}

pub fn setMachineOn(buf: []u8) usize {
    return fmtLen(buf, "set machine on\n", .{});
}

pub fn setEstopOn(buf: []u8) usize {
    return fmtLen(buf, "set estop on\n", .{});
}

pub fn getEnable(buf: []u8) usize {
    return fmtLen(buf, "get enable\n", .{});
}

pub fn getEstop(buf: []u8) usize {
    return fmtLen(buf, "get estop\n", .{});
}

pub fn getProgramStatus(buf: []u8) usize {
    return fmtLen(buf, "get program_status\n", .{});
}

pub fn getAbsActPos(buf: []u8) usize {
    return fmtLen(buf, "get abs_act_pos\n", .{});
}

pub fn getFeedOverride(buf: []u8) usize {
    return fmtLen(buf, "get feed_override\n", .{});
}

pub fn getSpindleOverride(buf: []u8) usize {
    return fmtLen(buf, "get spindle_override\n", .{});
}

pub fn getSpindle(buf: []u8) usize {
    return fmtLen(buf, "get spindle\n", .{});
}

pub fn getRelActPos(buf: []u8) usize {
    return fmtLen(buf, "get rel_act_pos\n", .{});
}

pub fn getJointHomed(buf: []u8) usize {
    return fmtLen(buf, "get joint_homed\n", .{});
}

pub fn getIni(buf: []u8, section: []const u8, key: []const u8) usize {
    return fmtLen(buf, "get ini {s} {s}\n", .{ section, key });
}

pub fn setPause(buf: []u8) usize {
    return fmtLen(buf, "set pause\n", .{});
}

pub fn setResume(buf: []u8) usize {
    return fmtLen(buf, "set resume\n", .{});
}

pub fn setAbort(buf: []u8) usize {
    return fmtLen(buf, "set abort\n", .{});
}

pub fn setHomeJoint(buf: []u8, joint: u8) usize {
    return fmtLen(buf, "set home {d}\n", .{joint});
}

pub fn setHomeAll(buf: []u8) usize {
    return fmtLen(buf, "set home -1\n", .{});
}

pub fn setMdi(buf: []u8, line: []const u8) usize {
    if (line.len + 12 > buf.len) return 0;
    return fmtLen(buf, "set mdi {s}\n", .{line});
}

pub fn setJogIncr(buf: []u8, axis: u8, speed: f32, increment: f32) usize {
    return fmtLen(buf, "set jog_incr {c} {d:.4} {d:.4}\n", .{ axis, speed, increment });
}

pub fn setJogCont(buf: []u8, axis: u8, speed: f32) usize {
    return fmtLen(buf, "set jog {c} {d:.4}\n", .{ axis, speed });
}

pub fn setJogStop(buf: []u8, axis: u8) usize {
    return fmtLen(buf, "set jog_stop {c}\n", .{axis});
}

pub fn setFeedOverride(buf: []u8, pct: u8) usize {
    return fmtLen(buf, "set feed_override {d}\n", .{pct});
}

pub fn setSpindleOverride(buf: []u8, pct: u8) usize {
    return fmtLen(buf, "set spindle_override {d}\n", .{pct});
}

pub fn setFlood(buf: []u8, on: bool) usize {
    return fmtLen(buf, "set flood {s}\n", .{if (on) "on" else "off"});
}

pub fn setMist(buf: []u8, on: bool) usize {
    return fmtLen(buf, "set mist {s}\n", .{if (on) "on" else "off"});
}

pub fn setSpindleOff(buf: []u8) usize {
    return fmtLen(buf, "set spindle off\n", .{});
}

test "linuxcnc cmd: auto step builders" {
    var buf: [48]u8 = undefined;
    try std.testing.expectEqualStrings("set mode auto\n", buf[0..setModeAuto(&buf)]);
    try std.testing.expectEqualStrings("set step\n", buf[0..setStep(&buf)]);
    try std.testing.expectEqualStrings("set optional_stop on\n", buf[0..setOptionalStop(&buf, true)]);
}
