//! Driver gcode send + override helpers — keeps `driver.zig` under size budget.

const std = @import("std");
const envelope = @import("envelope.zig");
const engine_mod = @import("protocol_engine.zig");

pub const Engine = engine_mod.Engine;

pub const override_pct_min: u8 = 10;
pub const override_pct_max: u8 = 200;

pub fn clampOverridePct(pct: u8) u8 {
    return std.math.clamp(pct, override_pct_min, override_pct_max);
}

fn addOverrideDelta(val: u8, delta: i8) u8 {
    const sum = @addWithOverflow(@as(i16, val), @as(i16, delta));
    const raw: i16 = if (sum[1] != 0) blk: {
        break :blk if (delta > 0) @as(i16, override_pct_max) else override_pct_min;
    } else sum[0];
    return @intCast(std.math.clamp(raw, override_pct_min, override_pct_max));
}

pub fn sendGcodeClamped(drv: anytype, line: []const u8) void {
    drv.reloadLimits();
    var buf: [128]u8 = undefined;
    const out = envelope.clampGcodeSpindle(line, &buf, drv.limits.max_spindle) orelse line;
    drv.engine.sendGcode(out);
}

pub fn applyOverridePct(eng: *Engine, feed: bool, target_pct: u8) void {
    const pct = clampOverridePct(target_pct);
    if (feed) eng.sendFeedOverridePct(pct) else eng.sendSpindleOverridePct(pct);
}

pub fn applyOverrideDelta(drv: anytype, feed: bool, delta: i8) void {
    drv.reloadLimits();
    if (drv.isReady()) {
        drv.lockSnapshot();
        // FS/RPM in status are usually *actual* (already × override). Recover programmed base
        // so envelope clamp does not pin override at 100% while cutting near max feed.
        const cur_ovr = if (feed) drv.snapshot.overrides.feed else drv.snapshot.overrides.spindle;
        const reported_feed = drv.snapshot.feed_rate;
        const reported_rpm = @as(f32, @floatFromInt(drv.snapshot.spindle_speed));
        const base_feed = if (cur_ovr > 0 and reported_feed > 0.0)
            reported_feed * 100.0 / @as(f32, @floatFromInt(cur_ovr))
        else
            reported_feed;
        const base_rpm = if (cur_ovr > 0 and reported_rpm > 0.0)
            reported_rpm * 100.0 / @as(f32, @floatFromInt(cur_ovr))
        else
            reported_rpm;
        var val = cur_ovr;
        drv.unlockSnapshot();
        if (delta == 0) {
            val = 100;
        } else {
            val = addOverrideDelta(val, delta);
        }
        if (feed) {
            val = envelope.clampFeedOverridePct(base_feed, val, drv.limits.max_feed_rate);
            applyOverridePct(&drv.engine, true, val);
        } else {
            val = envelope.clampSpindleOverridePct(base_rpm, val, drv.limits.max_spindle);
            applyOverridePct(&drv.engine, false, val);
        }
        drv.lockSnapshot();
        defer drv.unlockSnapshot();
        if (feed) drv.snapshot.overrides.feed = val else drv.snapshot.overrides.spindle = val;
        return;
    }
    drv.lockSnapshot();
    defer drv.unlockSnapshot();
    if (feed) {
        const cur = drv.snapshot.overrides.feed;
        const reported = drv.snapshot.feed_rate;
        const base_feed = if (cur > 0 and reported > 0.0)
            reported * 100.0 / @as(f32, @floatFromInt(cur))
        else
            reported;
        var val = cur;
        if (delta == 0) val = 100 else val = addOverrideDelta(val, delta);
        val = envelope.clampFeedOverridePct(base_feed, val, drv.limits.max_feed_rate);
        drv.snapshot.overrides.feed = val;
    } else {
        const cur = drv.snapshot.overrides.spindle;
        const reported = @as(f32, @floatFromInt(drv.snapshot.spindle_speed));
        const base_rpm = if (cur > 0 and reported > 0.0)
            reported * 100.0 / @as(f32, @floatFromInt(cur))
        else
            reported;
        var val = cur;
        if (delta == 0) val = 100 else val = addOverrideDelta(val, delta);
        val = envelope.clampSpindleOverridePct(base_rpm, val, drv.limits.max_spindle);
        drv.snapshot.overrides.spindle = val;
    }
}

test "cnc: override delta clamps on overflow" {
    try std.testing.expectEqual(@as(u8, 200), addOverrideDelta(195, 10));
    try std.testing.expectEqual(@as(u8, 10), addOverrideDelta(15, -10));
}

test "cnc: feed override de-scales actual FS before envelope clamp" {
    // Actual FS 5000 at 100% with max 5000 must still allow 110% against programmed 5000…
    // programmed = 5000; 110% → 5500 > max → clamp to 100. With wrong base (=actual) same.
    // Actual FS 4000 at 100%, max 5000 → 120% ok.
    try std.testing.expectEqual(@as(u8, 120), envelope.clampFeedOverridePct(4000.0, 120, 5000));
    // Actual 4800 already at 120% ovr → programmed 4000; request 150 → clamp to 125.
    const programmed = 4800.0 * 100.0 / 120.0;
    try std.testing.expectEqual(@as(u8, 125), envelope.clampFeedOverridePct(programmed, 150, 5000));
}
