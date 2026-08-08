//! MMBP engine TX helpers.

const cmd = @import("cmd.zig");

pub fn sendHello(eng: anytype) void {
    var buf: [48]u8 = undefined;
    const n = cmd.hello(&buf);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendStatusPoll(eng: anytype) void {
    inline for (.{ cmd.getStatus, cmd.getPos, cmd.getOvr }) |builder| {
        var buf: [24]u8 = undefined;
        const n = builder(&buf);
        if (n > 0) eng.send(buf[0..n]);
    }
}

pub fn axisDir(axis: u8, positive: bool) ?[3]u8 {
    return switch (axis) {
        'X', 'x' => if (positive) .{ 'X', '+', 0 } else .{ 'X', '-', 0 },
        'Y', 'y' => if (positive) .{ 'Y', '+', 0 } else .{ 'Y', '-', 0 },
        'Z', 'z' => if (positive) .{ 'Z', '+', 0 } else .{ 'Z', '-', 0 },
        'A', 'a' => if (positive) .{ 'A', '+', 0 } else .{ 'A', '-', 0 },
        'B', 'b' => if (positive) .{ 'B', '+', 0 } else .{ 'B', '-', 0 },
        'C', 'c' => if (positive) .{ 'C', '+', 0 } else .{ 'C', '-', 0 },
        else => null,
    };
}

pub fn sendUnlock(eng: anytype) void {
    var buf: [24]u8 = undefined;
    const n = cmd.cmdUnlock(&buf);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendReset(eng: anytype) void {
    var buf: [24]u8 = undefined;
    const n = cmd.cmdReset(&buf);
    if (n > 0) eng.send(buf[0..n]);
    eng.state = .locked;
}

pub fn sendGcode(eng: anytype, line: []const u8) void {
    var buf: [128]u8 = undefined;
    const n = cmd.cmdMdi(&buf, line);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendHome(eng: anytype, axis: u8) void {
    var buf: [24]u8 = undefined;
    const n = if (axis == 0)
        cmd.cmdHomeAll(&buf)
    else
        cmd.cmdHomeAxis(&buf, axis);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendJog(eng: anytype, axis: u8, distance: f32, feed_rate: f32, incremental: bool, _: bool) void {
    const positive = distance >= 0;
    const ad = axisDir(axis, positive) orelse return;
    const dir = ad[0..2];
    var buf: [64]u8 = undefined;
    const dist = if (positive) distance else -distance;
    const n = if (incremental)
        cmd.cmdJogIncr(&buf, dir, dist, feed_rate)
    else
        cmd.cmdJogCont(&buf, dir, feed_rate);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendJogCancel(eng: anytype) void {
    const axes = [_]u8{ 'X', 'Y', 'Z' };
    for (axes) |axis| {
        var buf: [24]u8 = undefined;
        const n = cmd.cmdJogStop(&buf, axis);
        if (n > 0) eng.send(buf[0..n]);
    }
}

pub fn sendFeedOverridePct(eng: anytype, pct: u8) void {
    var buf: [32]u8 = undefined;
    const n = cmd.cmdFeedOverride(&buf, pct);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendSpindleOverridePct(eng: anytype, pct: u8) void {
    var buf: [32]u8 = undefined;
    const n = cmd.cmdSpindleOverride(&buf, pct);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendCycleStart(eng: anytype) void {
    var buf: [24]u8 = undefined;
    const n = cmd.cmdCycleStart(&buf);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendFeedHold(eng: anytype) void {
    var buf: [24]u8 = undefined;
    const n = cmd.cmdFeedHold(&buf);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendStop(eng: anytype) void {
    var buf: [24]u8 = undefined;
    const n = cmd.cmdStop(&buf);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendCoolantFloodToggle(eng: anytype) void {
    eng.parser.flood_on = !eng.parser.flood_on;
    var buf: [24]u8 = undefined;
    const n = cmd.cmdFlood(&buf, eng.parser.flood_on);
    if (n > 0) eng.send(buf[0..n]);
    eng.parser.status.coolant_on = eng.parser.flood_on;
}

pub fn sendCoolantMistToggle(eng: anytype) void {
    eng.parser.mist_on = !eng.parser.mist_on;
    var buf: [24]u8 = undefined;
    const n = cmd.cmdMist(&buf, eng.parser.mist_on);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendSpindleStopToggle(eng: anytype) void {
    var buf: [24]u8 = undefined;
    const n = cmd.cmdSpindleStop(&buf);
    if (n > 0) eng.send(buf[0..n]);
}
