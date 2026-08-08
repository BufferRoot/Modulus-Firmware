//! ExtEncoder NVS load + detent math.

const std = @import("std");
const cnc_state = @import("../../cnc/cnc_state.zig");
const settings_keys = @import("../../core/settings_keys.zig");
const settings_store = @import("../../core/settings_store.zig");

pub fn loadEncdivFromStore(store: *const settings_store.Store) u8 {
    var v = store.getU8(settings_keys.cnc_encdiv, 2);
    if (v < 1) v = 1;
    if (v > 16) v = 16;
    return v;
}

pub fn loadJogspdFromStore(store: *const settings_store.Store) u16 {
    const base = store.getU16(settings_keys.cnc_jogspd, 1000);
    return std.math.clamp(base, 100, 10000);
}

pub fn loadContPctFromStore(store: *const settings_store.Store) u8 {
    const pct = store.getU8(settings_keys.cnc_contpct, 100);
    return std.math.clamp(pct, 10, 200);
}

pub fn accumulateDelta(remainder: *i32, raw_delta: i32, encdiv: i32) i32 {
    if (raw_delta == 0) return 0;
    remainder.* = remainder.* +| raw_delta;
    const div: i32 = if (encdiv < 1) 1 else encdiv;
    const steps = @divTrunc(remainder.*, div);
    remainder.* -= steps * div;
    return steps;
}

pub fn jogFeedForStep(jogspd: u16, step: cnc_state.StepSize) f32 {
    const base = jogspd;
    const ratios = [_]f32{ 1.0, 5.0, 15.0, 30.0 };
    const idx = @intFromEnum(step);
    if (idx >= ratios.len) return @as(f32, @floatFromInt(base));
    return @as(f32, @floatFromInt(base)) * ratios[idx];
}

const k_default_increments = [_]f32{ 0.001, 0.01, 0.1, 1.0 };

/// Parse NVS `cnc_incr` (four comma-separated mm values) — C++ widget_jog parity.
pub fn loadIncrementsFromStore(store: *const settings_store.Store, out: *[4]f32) void {
    out.* = k_default_increments;
    var buf: [64]u8 = undefined;
    @memset(&buf, 0);
    if (!store.getStr(settings_keys.cnc_incr, &buf)) return;
    const end = std.mem.indexOfScalar(u8, &buf, 0) orelse buf.len;
    var it = std.mem.tokenizeAny(u8, buf[0..end], ",");
    var i: usize = 0;
    while (it.next()) |tok| {
        if (i >= 4) break;
        const trimmed = std.mem.trim(u8, tok, " \t");
        const v = std.fmt.parseFloat(f32, trimmed) catch k_default_increments[i];
        out[i] = if (v > 0) v else k_default_increments[i];
        i += 1;
    }
}

pub fn incrementForStep(incs: *const [4]f32, step: cnc_state.StepSize) f32 {
    const idx = @intFromEnum(step);
    if (idx >= 4) return incs[1];
    return incs[idx];
}

test "hal: accumulate delta encdiv" {
    var rem: i32 = 0;
    try std.testing.expectEqual(@as(i32, 2), accumulateDelta(&rem, 4, 2));
    try std.testing.expectEqual(@as(i32, 0), rem);
}

test "hal: load custom cnc_incr for handwheel" {
    var store = settings_store.Store.init(std.testing.allocator);
    defer store.deinit();
    try store.setStr(settings_keys.cnc_incr, "0.005,0.05,0.5,2.0");
    var incs: [4]f32 = undefined;
    loadIncrementsFromStore(&store, &incs);
    try std.testing.expectEqual(@as(f32, 0.005), incs[0]);
    try std.testing.expectEqual(@as(f32, 2.0), incs[3]);
    try std.testing.expectEqual(@as(f32, 0.05), incrementForStep(&incs, .step_0_01));
}
