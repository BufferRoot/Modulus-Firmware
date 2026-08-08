//! grblHAL engine TX helpers — realtime command + gcode assembly.

const cmd = @import("cmd.zig");
const cnc_config = @import("../cnc_config.zig");

pub fn requestInfo(eng: anytype) void {
    var buf: [8]u8 = undefined;
    const n = cmd.systemInfo(&buf, true);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn requestStatus(eng: anytype, full: bool) void {
    var buf: [1]u8 = undefined;
    const n = if (@import("../cnc_config.zig").usesClassicRealtime(eng.protocol))
        cmd.classicStatusQuery(&buf)
    else
        cmd.statusQuery(&buf, full);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn requestEnumerations(eng: anytype) void {
    var buf: [16]u8 = undefined;
    inline for (.{
        cmd.enumAlarms,
        cmd.enumErrors,
        cmd.enumSettings,
        cmd.enumGroups,
    }) |builder| {
        const n = builder(&buf);
        if (n > 0) eng.send(buf[0..n]);
    }
}

pub fn sendFeedHold(eng: anytype) void {
    var buf: [1]u8 = undefined;
    _ = cmd.feedHold(&buf);
    eng.send(&buf);
}

pub fn sendCycleStart(eng: anytype) void {
    var buf: [1]u8 = undefined;
    _ = cmd.cycleStart(&buf);
    eng.send(&buf);
}

pub fn sendJog(eng: anytype, axis: u8, distance: f32, feed_rate: f32, incremental: bool, metric: bool) void {
    var buf: [64]u8 = undefined;
    const n = cmd.jog(&buf, axis, distance, feed_rate, incremental, metric);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendJogCancel(eng: anytype) void {
    var buf: [1]u8 = undefined;
    if (cmd.jogCancel(&buf) > 0) eng.send(&buf);
}

pub fn sendHome(eng: anytype, axis: u8) void {
    var buf: [8]u8 = undefined;
    // Per-axis homing ($HX/$HY/...) exists in grblHAL and FluidNC; stock
    // Grbl 1.1 only supports the full $H cycle, so fall back to homing all.
    const per_axis = axis != 0 and eng.protocol != .classic_grbl;
    const n = if (per_axis) cmd.homeAxis(&buf, axis) else cmd.homeAll(&buf);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendReset(eng: anytype) void {
    var buf: [1]u8 = undefined;
    if (cmd.softReset(&buf) > 0) eng.send(&buf);
    eng.welcome_received = false;
    eng.enums_requested = false;
    eng.state = .wait_banner;
    eng.connect_ms = eng.tick_ms;
}

pub fn requestUnlockAfterWelcome(eng: anytype) void {
    eng.pending_unlock = true;
}

pub fn sendUnlock(eng: anytype) void {
    // Direct `$X\n` — do not route through gcode() (would double-newline).
    var buf: [8]u8 = undefined;
    const n = cmd.unlock(&buf);
    if (n > 0) eng.send(buf[0..n]);
    // Stay .locked until status leaves Alarm — engine promotes to .ready.
    // Kick a status poll so Clear Alarm feedback reaches the UI quickly.
    requestStatus(eng, true);
}

pub fn sendGcode(eng: anytype, line: []const u8) void {
    var buf: [128]u8 = undefined;
    const n = cmd.gcode(&buf, line);
    if (n > 0) eng.send(buf[0..n]);
}

pub fn sendFeedOverride(eng: anytype, delta_pct: i8) void {
    var buf: [1]u8 = undefined;
    buf[0] = cmd.feedOverrideByte(delta_pct);
    eng.send(&buf);
}

pub fn sendRapidOverride(eng: anytype, pct: u8) void {
    var buf: [1]u8 = undefined;
    buf[0] = cmd.rapidOverrideByte(pct);
    eng.send(&buf);
}

pub fn sendSpindleOverride(eng: anytype, delta_pct: i8) void {
    var buf: [1]u8 = undefined;
    buf[0] = cmd.spindleOverrideByte(delta_pct);
    eng.send(&buf);
}

pub fn sendSpindleStopToggle(eng: anytype) void {
    var buf: [1]u8 = undefined;
    if (cmd.spindleStopToggle(&buf) > 0) eng.send(&buf);
}

pub fn sendCoolantFloodToggle(eng: anytype) void {
    var buf: [1]u8 = undefined;
    if (cmd.coolantFloodToggle(&buf) > 0) eng.send(&buf);
}

pub fn sendCoolantMistToggle(eng: anytype) void {
    var buf: [1]u8 = undefined;
    if (cmd.coolantMistToggle(&buf) > 0) eng.send(&buf);
}

pub fn sendFanToggle(eng: anytype) void {
    var buf: [1]u8 = undefined;
    if (cmd.fanToggle(&buf) > 0) eng.send(&buf);
}

pub fn sendSingleStepToggle(eng: anytype) void {
    var buf: [1]u8 = undefined;
    if (cmd.singleStepToggle(&buf) > 0) eng.send(&buf);
}

pub fn sendMpgToggle(eng: anytype) void {
    var buf: [1]u8 = undefined;
    if (cmd.mpgToggle(&buf) > 0) eng.send(&buf);
}

pub fn sendStop(eng: anytype) void {
    var buf: [1]u8 = undefined;
    if (cmd.stop(&buf) > 0) eng.send(&buf);
}

pub fn requestParserState(eng: anytype) void {
    // grblHAL: realtime 0x83. Classic Grbl / FluidNC: text `$G\n` (0x83 unknown there).
    if (cnc_config.usesClassicRealtime(eng.protocol)) {
        var buf: [4]u8 = undefined;
        const n = cmd.parserStateText(&buf);
        if (n > 0) eng.send(buf[0..n]);
        return;
    }
    var buf: [1]u8 = undefined;
    if (cmd.parserStateReq(&buf) > 0) eng.send(&buf);
}
