//! LinuxCNC engine TX helpers.

const std = @import("std");
const cmd = @import("cmd.zig");

pub fn sendHello(eng: anytype) void {
    var buf: [64]u8 = undefined;
    const pw = std.mem.sliceTo(&eng.parser.connect_pw, 0);
    const n = cmd.hello(&buf, pw);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendHandshakeSetup(eng: anytype) void {
    inline for (.{
        cmd.setEchoOff,
        cmd.setVerboseOff,
        cmd.setTeleopOn,
        cmd.setModeManual,
    }) |builder| {
        var buf: [48]u8 = undefined;
        const n = builder(&buf);
        if (n > 0) eng.send(buf[0..n]);
    }
    var buf: [48]u8 = undefined;
    const en = cmd.setEnable(&buf, std.mem.sliceTo(&eng.parser.enable_pw, 0));
    if (en > 0) eng.send(buf[0..en]);
    const ge = cmd.getEnable(&buf);
    if (ge > 0) eng.send(buf[0..ge]);
}

pub fn sendStatusPoll(eng: anytype) void {
    inline for (.{
        cmd.getEstop,
        cmd.getProgramStatus,
        cmd.getAbsActPos,
        cmd.getRelActPos,
        cmd.getFeedOverride,
        cmd.getSpindleOverride,
        cmd.getSpindle,
        cmd.getJointHomed,
    }) |builder| {
        var buf: [32]u8 = undefined;
        const n = builder(&buf);
        if (n > 0) eng.send(buf[0..n]);
    }
}

/// Envelope pull via linuxcncrsh `get ini` — synthesizes Grbl-like `$nn=` for applyDumpEnvelope.
pub fn sendIniEnvelopePoll(eng: anytype) void {
    const queries = [_]struct { []const u8, []const u8 }{
        .{ "TRAJ", "MAX_LINEAR_VELOCITY" },
        .{ "AXIS_X", "MAX_VELOCITY" },
        .{ "AXIS_Y", "MAX_VELOCITY" },
        .{ "AXIS_Z", "MAX_VELOCITY" },
        .{ "AXIS_X", "MAX_LIMIT" },
        .{ "AXIS_Y", "MAX_LIMIT" },
        .{ "AXIS_Z", "MAX_LIMIT" },
        .{ "AXIS_A", "MAX_LIMIT" },
        .{ "AXIS_B", "MAX_LIMIT" },
        .{ "AXIS_C", "MAX_LIMIT" },
        .{ "SPINDLE_0", "MAX_FORWARD_VELOCITY" },
    };
    for (queries) |q| {
        var buf: [64]u8 = undefined;
        const n = cmd.getIni(&buf, q[0], q[1]);
        if (n > 0) eng.send(buf[0..n]);
    }
}

pub fn sendUnlock(eng: anytype) void {
    inline for (.{ cmd.setEstopOff, cmd.setMachineOn, cmd.setModeManual }) |builder| {
        var buf: [32]u8 = undefined;
        const n = builder(&buf);
        if (n > 0) eng.send(buf[0..n]);
    }
}

pub fn sendReset(eng: anytype) void {
    var buf: [24]u8 = undefined;
    const n = cmd.setEstopOn(&buf);
    if (n > 0) eng.send(buf[0..n]);
    eng.state = .locked;
}

pub fn sendGcode(eng: anytype, line: []const u8) void {
    var buf: [128]u8 = undefined;
    const n = cmd.setMdi(&buf, line);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn axisJoint(axis: u8) ?u8 {
    return switch (axis) {
        'X', 'x' => 0,
        'Y', 'y' => 1,
        'Z', 'z' => 2,
        'A', 'a' => 3,
        'B', 'b' => 4,
        'C', 'c' => 5,
        else => null,
    };
}

pub fn sendHome(eng: anytype, axis: u8) void {
    var buf: [24]u8 = undefined;
    const n = if (axis == 0)
        cmd.setHomeAll(&buf)
    else if (axisJoint(axis)) |joint|
        cmd.setHomeJoint(&buf, joint)
    else
        0;
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendJog(eng: anytype, axis: u8, distance: f32, feed_rate: f32, incremental: bool, _: bool) void {
    var buf: [64]u8 = undefined;
    const n = if (incremental)
        cmd.setJogIncr(&buf, axis, feed_rate, distance)
    else
        cmd.setJogCont(&buf, axis, feed_rate);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendJogCancel(eng: anytype) void {
    const axes = [_]u8{ 'X', 'Y', 'Z' };
    for (axes) |axis| {
        var buf: [24]u8 = undefined;
        const n = cmd.setJogStop(&buf, axis);
        if (n > 0) eng.send(buf[0..n]);
    }
}

pub fn sendFeedOverridePct(eng: anytype, pct: u8) void {
    var buf: [32]u8 = undefined;
    const n = cmd.setFeedOverride(&buf, pct);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendSpindleOverridePct(eng: anytype, pct: u8) void {
    var buf: [32]u8 = undefined;
    const n = cmd.setSpindleOverride(&buf, pct);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendCycleStart(eng: anytype) void {
    var buf: [24]u8 = undefined;
    const ma = cmd.setModeAuto(&buf);
    if (ma > 0) eng.send(buf[0..ma]);
    const n = cmd.setResume(&buf);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendFeedHold(eng: anytype) void {
    var buf: [24]u8 = undefined;
    const n = cmd.setPause(&buf);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendStop(eng: anytype) void {
    var buf: [24]u8 = undefined;
    const n = cmd.setAbort(&buf);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendSingleStepToggle(eng: anytype) void {
    var buf: [24]u8 = undefined;
    const ma = cmd.setModeAuto(&buf);
    if (ma > 0) eng.send(buf[0..ma]);
    const n = cmd.setStep(&buf);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendCoolantFloodToggle(eng: anytype) void {
    eng.parser.flood_on = !eng.parser.flood_on;
    var buf: [24]u8 = undefined;
    const n = cmd.setFlood(&buf, eng.parser.flood_on);
    if (n > 0) eng.send(buf[0..n]);
    eng.parser.status.coolant_on = eng.parser.flood_on;
}

pub fn sendCoolantMistToggle(eng: anytype) void {
    eng.parser.mist_on = !eng.parser.mist_on;
    var buf: [24]u8 = undefined;
    const n = cmd.setMist(&buf, eng.parser.mist_on);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendSpindleStopToggle(eng: anytype) void {
    var buf: [24]u8 = undefined;
    const n = cmd.setSpindleOff(&buf);
    if (n > 0) eng.send(buf[0..n]);
}
