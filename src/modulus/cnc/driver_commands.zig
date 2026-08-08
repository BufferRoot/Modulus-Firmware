//! CNC driver command surface — motion, spindle, overrides, settings dump.

const std = @import("std");
const cnc_config = @import("cnc_config.zig");
const cnc_state = @import("cnc_state.zig");
const envelope = @import("envelope.zig");
const settings_keys = @import("../core/settings_keys.zig");
const driver_ops = @import("driver_ops.zig");
const gating = @import("driver_gating.zig");

pub fn cmdCycleStart(drv: anytype) void {
    if (gating.isReady(drv)) {
        drv.engine.sendCycleStart();
    } else {
        gating.lockSnapshot(drv);
        defer gating.unlockSnapshot(drv);
        drv.snapshot.state = if (drv.snapshot.state == .run) .idle else .run;
    }
}

pub fn cmdFeedHold(drv: anytype) void {
    if (gating.isReady(drv)) {
        drv.engine.sendFeedHold();
    } else {
        gating.lockSnapshot(drv);
        defer gating.unlockSnapshot(drv);
        drv.snapshot.state = if (drv.snapshot.state == .hold) .idle else .hold;
    }
}

pub fn cmdHome(drv: anytype, axis: u8) void {
    if (gating.canSendCommands(drv)) drv.engine.sendHome(axis);
}

pub fn cmdHomeAxis(drv: anytype, axis_idx: u8) void {
    const letter = cnc_state.activeAxisLetter(@enumFromInt(axis_idx)) orelse return;
    if (gating.canSendCommands(drv)) drv.engine.sendHome(letter);
}

pub fn cmdZeroAxis(drv: anytype, axis_idx: u8) void {
    // Match C++ widget_dro: send while linked. Use canSendCommands (not isReady)
    // so MPG / mpg_blocked still zeros — isReady silently no-op'd the DRO buttons.
    if (!gating.canSendCommands(drv)) return;
    if (drv.status().state == .disconnected) return;
    const letter = cnc_state.activeAxisLetter(@enumFromInt(axis_idx)) orelse return;
    var buf: [24]u8 = undefined;
    const line = std.fmt.bufPrint(&buf, "G10 L20 P0 {c}0", .{letter}) catch return;
    driver_ops.sendGcodeClamped(drv, line);
}

pub fn cmdZeroAll(drv: anytype) void {
    if (!gating.canSendCommands(drv)) return;
    driver_ops.sendGcodeClamped(drv, "G10 L20 P0 X0 Y0 Z0");
}

pub fn cycleWcs(drv: anytype) void {
    gating.lockSnapshot(drv);
    const cur = @intFromEnum(drv.snapshot.wcs);
    const next_idx = (cur + 1) % @intFromEnum(cnc_state.WCS._count);
    const wcs: cnc_state.WCS = @enumFromInt(next_idx);
    drv.snapshot.wcs = wcs;
    gating.unlockSnapshot(drv);
    if (drv.store) |s| s.persistU8(settings_keys.cnc_wcs, @intCast(next_idx));
    if (gating.isReady(drv)) driver_ops.sendGcodeClamped(drv, cnc_state.wcsStr(wcs));
}

pub fn setActiveAxis(drv: anytype, axis_idx: u8) void {
    if (axis_idx >= @intFromEnum(cnc_state.ActiveAxis.off)) return;
    gating.lockSnapshot(drv);
    defer gating.unlockSnapshot(drv);
    drv.snapshot.active_axis = @enumFromInt(axis_idx);
}

pub fn cmdUnlock(drv: anytype) void {
    // Always TX $X while linked. Soft-reset leaves wait_banner where Grbl ignores $X
    // until welcome — arm pending_unlock so $X fires after reboot.
    if (gating.isConnected(drv)) {
        const sess = drv.engine.session();
        if (sess == .wait_banner or sess == .querying or sess == .configuring) {
            drv.engine.requestUnlockAfterWelcome();
        }
        // Immediate attempt (works when locked/ready/alarm). Text unlock is `$X\n`.
        drv.engine.sendUnlock();
        return;
    }
    gating.lockSnapshot(drv);
    defer gating.unlockSnapshot(drv);
    drv.snapshot.state = .idle;
}

pub fn cmdReset(drv: anytype) void {
    if (gating.isConnected(drv)) {
        // Soft reset (0x18). Arm $X after welcome for alarm recovery only.
        drv.engine.requestUnlockAfterWelcome();
        drv.engine.sendReset();
        return;
    }
    gating.lockSnapshot(drv);
    defer gating.unlockSnapshot(drv);
    drv.snapshot.state = .idle;
}

/// End / cancel job — soft reset (0x18). Same byte as Ctrl-X; aborts streamed jobs.
pub fn cmdStop(drv: anytype) void {
    if (gating.isConnected(drv)) {
        // Do not arm pending $X — this is cancel, not alarm clear.
        drv.engine.sendReset();
        gating.lockSnapshot(drv);
        defer gating.unlockSnapshot(drv);
        drv.snapshot.state = .idle;
        drv.snapshot.sd_streaming = false;
        drv.snapshot.sd_percent = 0;
        drv.snapshot.line_number = 0;
        return;
    }
}

pub fn cmdSendGcode(drv: anytype, line: []const u8) void {
    // Match custom quick buttons / ZERO: allow under mpg_blocked.
    if (!gating.canSendCommands(drv) or line.len == 0) return;
    driver_ops.sendGcodeClamped(drv, line);
}

pub fn cmdProbeStart(drv: anytype, cycle: @import("probe_engine.zig").Cycle) bool {
    if (!gating.canSendCommands(drv)) return false;
    gating.lockSnapshot(drv);
    const idle = drv.snapshot.state == .idle;
    gating.unlockSnapshot(drv);
    if (!idle or drv.probe.busy()) return false;
    const cfg = @import("probe_engine.zig").Config.fromStore(drv.store);
    return drv.probe.start(cycle, cfg, drv);
}

pub fn cmdProbeCancel(drv: anytype) void {
    drv.probe.cancel();
}

pub fn probeBusy(drv: anytype) bool {
    return drv.probe.busy();
}

pub fn cmdRequestSettingsDump(drv: anytype) void {
    // Always arm the capture so the UI modal sees ready/failed (never hangs).
    drv.settings_dump.begin();
    drv.engine.setSettingsDump(&drv.settings_dump);

    // Match DRO/home: allow while mpg_blocked. $$ is Grbl-family only.
    if (!gating.canSendCommands(drv)) {
        drv.settings_dump.onError();
        drv.engine.setSettingsDump(null);
        return;
    }
    const proto: cnc_config.Protocol = blk: {
        if (drv.store) |s| {
            const idx = s.getU8(settings_keys.cnc_proto, cnc_config.k_default_cnc_proto);
            break :blk if (idx < @intFromEnum(cnc_config.Protocol._count))
                @enumFromInt(idx)
            else
                .grblhal;
        }
        break :blk drv.engine.active;
    };
    if (!cnc_config.supportsSettingsDump(proto)) {
        drv.settings_dump.onError();
        drv.engine.setSettingsDump(null);
        return;
    }
    if (proto == .linux_cnc) {
        drv.engine.lcnc.beginIniEnvelopePull();
        return;
    }
    driver_ops.sendGcodeClamped(drv, "$$");
}

pub fn settingsDumpCancel(drv: anytype) void {
    drv.settings_dump.cancel();
    drv.engine.setSettingsDump(null);
}

pub fn settingsDumpReady(drv: anytype) bool {
    return drv.settings_dump.complete;
}

pub fn settingsDumpFailed(drv: anytype) bool {
    return drv.settings_dump.failed;
}

pub fn settingsDumpCopy(drv: anytype, dst: []u8) usize {
    const text = drv.settings_dump.text();
    const n = @min(text.len, dst.len);
    if (n > 0) @memcpy(dst[0..n], text[0..n]);
    return n;
}

fn dumpSettingU16(text: []const u8, comptime num: []const u8, lo: u16, hi: u16) ?u16 {
    var it = std.mem.tokenizeAny(u8, text, "\r\n");
    while (it.next()) |line| {
        if (!std.mem.startsWith(u8, line, "$" ++ num ++ "=")) continue;
        const val_str = line["$".len + num.len + "=".len ..];
        const f = std.fmt.parseFloat(f32, std.mem.trim(u8, val_str, " ")) catch return null;
        if (f < 0) return null;
        const v: u32 = @intFromFloat(@min(f, 65535.0));
        return @intCast(std.math.clamp(v, lo, hi));
    }
    return null;
}

/// Pull work envelope FROM a completed `$$` dump into pendant NVS:
/// min($110,$111,$112) -> cnc_mxfeed, $30 -> cnc_mxrpm,
/// $130/$131/$132 -> cnc_tr_x/y/z, $133/$134/$135 -> cnc_tr_a/b/c.
/// Returns the number of settings applied; forces a limits reload when > 0.
pub fn applyDumpEnvelope(drv: anytype) u8 {
    if (!drv.settings_dump.complete) return 0;
    return applyEnvelopeText(drv, drv.settings_dump.text());
}

/// Apply `$nn=` (or bare KEY=) lines into pendant NVS — shared by $$ dump and paste.
pub fn applyEnvelopeText(drv: anytype, text: []const u8) u8 {
    var applied: u8 = 0;
    const s = drv.store orelse return 0;
    var feed: ?u16 = null;
    inline for (.{ "110", "111", "112" }) |num| {
        if (dumpSettingU16(text, num, 100, 20000)) |v| {
            feed = if (feed) |f| @min(f, v) else v;
        }
    }
    if (feed) |v| {
        s.persistU16(settings_keys.cnc_mxfeed, v);
        applied += 1;
    }
    if (dumpSettingU16(text, "30", 1000, 60000)) |v| {
        s.persistU16(settings_keys.cnc_mxrpm, v);
        applied += 1;
    }
    if (dumpSettingU16(text, "130", 50, 2000)) |v| {
        s.persistU16(settings_keys.cnc_tr_x, v);
        applied += 1;
    }
    if (dumpSettingU16(text, "131", 50, 2000)) |v| {
        s.persistU16(settings_keys.cnc_tr_y, v);
        applied += 1;
    }
    if (dumpSettingU16(text, "132", 10, 1000)) |v| {
        s.persistU16(settings_keys.cnc_tr_z, v);
        applied += 1;
    }
    if (dumpSettingU16(text, "133", 1, 7200)) |v| {
        s.persistU16(settings_keys.cnc_tr_a, v);
        applied += 1;
    }
    if (dumpSettingU16(text, "134", 1, 7200)) |v| {
        s.persistU16(settings_keys.cnc_tr_b, v);
        applied += 1;
    }
    if (dumpSettingU16(text, "135", 1, 7200)) |v| {
        s.persistU16(settings_keys.cnc_tr_c, v);
        applied += 1;
    }
    if (applied > 0) {
        drv.limits_loaded = false;
        drv.reloadLimits();
    }
    return applied;
}

test "cnc: applyDumpEnvelope parses $$ dump values" {
    const text = "$30=18000.000\r\n$110=4000.000\r\n$111=3500.000\r\n$112=4000.000\r\n$130=610.000\r\n$131=305.5\r\n$132=95.000\r\n";
    try std.testing.expectEqual(@as(?u16, 4000), dumpSettingU16(text, "110", 100, 20000));
    try std.testing.expectEqual(@as(?u16, 18000), dumpSettingU16(text, "30", 1000, 60000));
    try std.testing.expectEqual(@as(?u16, 610), dumpSettingU16(text, "130", 50, 2000));
    try std.testing.expectEqual(@as(?u16, 305), dumpSettingU16(text, "131", 50, 2000));
    try std.testing.expectEqual(@as(?u16, 95), dumpSettingU16(text, "132", 10, 1000));
    // $30 must not match $130's prefix, and absent keys return null.
    try std.testing.expectEqual(@as(?u16, null), dumpSettingU16(text, "999", 100, 20000));
    // Clamps into the pendant's slider ranges.
    try std.testing.expectEqual(@as(?u16, 20000), dumpSettingU16("$110=90000\n", "110", 100, 20000));
}

test "cnc: applyDumpEnvelope takes min axis max-rate" {
    // Ponytail check: $111 slower than $110/$112 → feed cap is 3500.
    const text = "$110=5000\n$111=3500\n$112=4800\n$30=12000\n";
    var feed: ?u16 = null;
    inline for (.{ "110", "111", "112" }) |num| {
        if (dumpSettingU16(text, num, 100, 20000)) |v| {
            feed = if (feed) |f| @min(f, v) else v;
        }
    }
    try std.testing.expectEqual(@as(?u16, 3500), feed);
}

pub fn cmdSyncEnvelopeToController(drv: anytype) void {
    // Match pull/dump: allow while mpg_blocked.
    if (!gating.canSendCommands(drv)) return;
    if (drv.store) |s| {
        const idx = s.getU8(settings_keys.cnc_proto, cnc_config.k_default_cnc_proto);
        const proto: cnc_config.Protocol = if (idx < @intFromEnum(cnc_config.Protocol._count))
            @enumFromInt(idx)
        else
            .grblhal;
        if (!cnc_config.usesGrblEngine(proto)) return;
    }
    drv.reloadLimits();
    drv.sync_pending = false;
    drv.sync_line_count = 0;
    drv.sync_line_next = 0;

    const max_feed = drv.limits.max_feed_rate;
    const rpm = drv.limits.max_spindle;
    inline for (0..3) |i| {
        const n: u16 = @intCast(110 + i);
        const written = std.fmt.bufPrint(&drv.sync_lines[drv.sync_line_count], "${d}={d}", .{ n, max_feed }) catch return;
        drv.sync_line_lens[drv.sync_line_count] = @intCast(written.len);
        drv.sync_line_count += 1;
    }
    const written30 = std.fmt.bufPrint(&drv.sync_lines[drv.sync_line_count], "$30={d}", .{rpm}) catch return;
    drv.sync_line_lens[drv.sync_line_count] = @intCast(written30.len);
    drv.sync_line_count += 1;

    drv.sync_pending = true;
    drv.sync_line_next = 1;
    const session = @import("driver_session.zig");
    driver_ops.sendGcodeClamped(drv, session.syncLine(drv, 0));
}

pub fn cmdEstop(drv: anytype) void {
    if (gating.isConnected(drv)) {
        drv.engine.sendReset();
    } else {
        gating.lockSnapshot(drv);
        defer gating.unlockSnapshot(drv);
        drv.snapshot.state = .alarm;
    }
}

pub fn cmdRapidOverride(drv: anytype, pct: u8) void {
    if (gating.isReady(drv)) {
        drv.engine.sendRapidOverride(pct);
    } else {
        gating.lockSnapshot(drv);
        defer gating.unlockSnapshot(drv);
        drv.snapshot.overrides.rapid = pct;
    }
}

pub fn cmdJog(drv: anytype, axis: u8, distance: f32, feed_rate: f32) void {
    if (!gating.canJogInternal(drv)) return;
    drv.reloadLimits();
    gating.lockSnapshot(drv);
    const metric = drv.snapshot.units_mm;
    const mpos = drv.snapshot.mpos;
    const homed = drv.snapshot.homed;
    gating.unlockSnapshot(drv);
    const dist = envelope.clampJogDistance(mpos, axis, distance, homed, drv.soft_limits) orelse return;
    if (dist == 0) return;
    const capped = envelope.clampJogFeedRate(feed_rate, drv.limits);
    drv.engine.sendJog(axis, dist, capped, true, metric);
}

pub fn cmdJogCancel(drv: anytype) void {
    if (gating.canJogInternal(drv)) drv.engine.sendJogCancel();
}

pub fn cmdFeedOverride(drv: anytype, delta: i8) void {
    driver_ops.applyOverrideDelta(drv, true, delta);
}

pub fn cmdSpindleOverride(drv: anytype, delta: i8) void {
    driver_ops.applyOverrideDelta(drv, false, delta);
}

pub fn cmdSpindleToggle(drv: anytype) void {
    if (gating.isReady(drv)) drv.engine.sendSpindleStopToggle();
}

fn spindleCmdRpm(drv: anytype) u32 {
    drv.reloadLimits();
    gating.lockSnapshot(drv);
    defer gating.unlockSnapshot(drv);
    var rpm = drv.snapshot.spindle_speed;
    if (rpm == 0) rpm = drv.snapshot.spindle_target;
    if (rpm == 0) rpm = 1000;
    const pct = drv.snapshot.overrides.spindle;
    const effective: u32 = @trunc(
        @as(f32, @floatFromInt(rpm)) * @as(f32, @floatFromInt(pct)) / 100.0,
    );
    const cap = drv.limits.max_spindle;
    if (cap == 0) return @max(effective, 1);
    return @max(@min(effective, cap), 1);
}

pub fn cmdSpindleCw(drv: anytype) void {
    if (!gating.isReady(drv)) return;
    var buf: [32]u8 = undefined;
    const rpm = spindleCmdRpm(drv);
    const line = std.fmt.bufPrint(&buf, "M3 S{d}", .{rpm}) catch return;
    driver_ops.sendGcodeClamped(drv, line);
}

pub fn cmdSpindleCcw(drv: anytype) void {
    if (!gating.isReady(drv)) return;
    if (drv.store) |s| {
        if (!s.getBool(settings_keys.cnc_spcw, true)) return;
    }
    var buf: [32]u8 = undefined;
    const rpm = spindleCmdRpm(drv);
    const line = std.fmt.bufPrint(&buf, "M4 S{d}", .{rpm}) catch return;
    driver_ops.sendGcodeClamped(drv, line);
}

pub fn cmdRunMacro(drv: anytype) void {
    if (!gating.isReady(drv)) return;
    var buf: [settings_keys.cnc_macro_max_len + 1]u8 = undefined;
    @memset(&buf, 0);
    const line: []const u8 = blk: {
        if (drv.store) |s| {
            if (s.getStr(settings_keys.cnc_macro, &buf) and buf[0] != 0) {
                const end = std.mem.indexOfScalar(u8, &buf, 0) orelse buf.len;
                break :blk buf[0..end];
            }
        }
        break :blk "M5";
    };
    driver_ops.sendGcodeClamped(drv, line);
}

pub fn cmdCoolantToggle(drv: anytype) void {
    if (gating.isReady(drv)) drv.engine.sendCoolantFloodToggle();
}

pub fn cmdMistToggle(drv: anytype) void {
    if (gating.isReady(drv)) drv.engine.sendCoolantMistToggle();
}

pub fn cmdFanToggle(drv: anytype) void {
    if (gating.isReady(drv)) drv.engine.sendFanToggle();
}

pub fn cmdSingleStep(drv: anytype) void {
    if (gating.isReady(drv)) drv.engine.sendSingleStepToggle();
}

pub fn cmdMpgToggle(drv: anytype) void {
    gating.lockSnapshot(drv);
    const want = !drv.snapshot.mpg_active;
    const remote = drv.snapshot.mpg_remote;
    drv.mpg_local_armed = want;
    drv.mpg_user_wants_off = !want;
    drv.snapshot.mpg_active = want;
    gating.unlockSnapshot(drv);
    if (gating.isConnected(drv) and want != remote) {
        drv.engine.sendMpgToggle();
    }
}

pub fn setJogMode(drv: anytype, mode: cnc_state.JogMode) void {
    gating.lockSnapshot(drv);
    defer gating.unlockSnapshot(drv);
    drv.snapshot.jog_mode = mode;
    if (drv.store) |s| s.persistU8(settings_keys.cnc_jmode, @intFromEnum(mode));
}

pub fn setUnitsMm(drv: anytype, mm: bool) void {
    gating.lockSnapshot(drv);
    drv.snapshot.units_mm = mm;
    gating.unlockSnapshot(drv);
    if (drv.store) |s| s.persistBool(settings_keys.cnc_unit, mm);
    if (!gating.isReady(drv)) return;
    if (drv.store) |s| {
        const idx = s.getU8(settings_keys.cnc_proto, cnc_config.k_default_cnc_proto);
        const proto: cnc_config.Protocol = if (idx < @intFromEnum(cnc_config.Protocol._count))
            @enumFromInt(idx)
        else
            .grblhal;
        if (!cnc_config.usesGrblEngine(proto)) return;
    }
    driver_ops.sendGcodeClamped(drv, if (mm) "$13=0" else "$13=1");
}

pub fn setStepSize(drv: anytype, size: cnc_state.StepSize) void {
    if (@intFromEnum(size) >= @intFromEnum(cnc_state.StepSize._count)) return;
    gating.lockSnapshot(drv);
    defer gating.unlockSnapshot(drv);
    drv.snapshot.step_size = size;
}

pub fn setWcs(drv: anytype, w: cnc_state.WCS) void {
    const wcs = if (@intFromEnum(w) >= @intFromEnum(cnc_state.WCS._count)) cnc_state.WCS.g54 else w;
    gating.lockSnapshot(drv);
    drv.snapshot.wcs = wcs;
    gating.unlockSnapshot(drv);
    if (gating.isReady(drv)) driver_ops.sendGcodeClamped(drv, cnc_state.wcsStr(wcs));
}
