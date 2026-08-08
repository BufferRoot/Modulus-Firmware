//! Work envelope clamp helpers — host-testable; used by `driver.zig`.

const std = @import("std");
const cnc_config = @import("cnc_config.zig");
const cnc_state = @import("cnc_state.zig");

pub const SoftLimits = cnc_config.SoftLimits;

pub fn loadLimits(store: ?*@import("../core/settings_store.zig").Store) cnc_config.MachineLimits {
    var lim = cnc_config.MachineLimits{};
    if (store) |s| {
        const keys = @import("../core/settings_keys.zig");
        lim.max_feed_rate = s.getU16(keys.cnc_mxfeed, lim.max_feed_rate);
        lim.max_spindle = s.getU16(keys.cnc_mxrpm, lim.max_spindle);
        lim.default_jog = s.getU16(keys.cnc_jogspd, lim.default_jog);
        if (lim.default_jog == 0) lim.default_jog = 1000;
        if (lim.max_feed_rate == 0) lim.max_feed_rate = 5000;
        if (lim.max_spindle == 0) lim.max_spindle = 24000;
        if (lim.max_spindle < 1000) lim.max_spindle = 1000;
        if (lim.max_spindle > 60000) lim.max_spindle = 60000;
    }
    return lim;
}

pub fn loadSoftLimits(store: ?*@import("../core/settings_store.zig").Store) SoftLimits {
    var soft: SoftLimits = .{};
    if (store) |s| {
        const keys = @import("../core/settings_keys.zig");
        soft.enabled = s.getBool(keys.cnc_slim, false);
        soft.max_x = @floatFromInt(s.getU16(keys.cnc_tr_x, 300));
        soft.max_y = @floatFromInt(s.getU16(keys.cnc_tr_y, 300));
        soft.max_z = @floatFromInt(s.getU16(keys.cnc_tr_z, 100));
        soft.max_a = @floatFromInt(s.getU16(keys.cnc_tr_a, 360));
        soft.max_b = @floatFromInt(s.getU16(keys.cnc_tr_b, 360));
        soft.max_c = @floatFromInt(s.getU16(keys.cnc_tr_c, 360));
    }
    return soft;
}

fn axisMachinePos(mpos: cnc_state.Position, axis: u8) ?f32 {
    return switch (axis) {
        0 => mpos.x,
        1 => mpos.y,
        2 => mpos.z,
        3 => mpos.a,
        4 => mpos.b,
        5 => mpos.c,
        else => null,
    };
}

fn axisMaxTravel(soft: SoftLimits, axis: u8) ?f32 {
    return switch (axis) {
        0 => if (soft.max_x > 0) soft.max_x else null,
        1 => if (soft.max_y > 0) soft.max_y else null,
        2 => if (soft.max_z > 0) soft.max_z else null,
        3 => if (soft.max_a > 0) soft.max_a else null,
        4 => if (soft.max_b > 0) soft.max_b else null,
        5 => if (soft.max_c > 0) soft.max_c else null,
        else => null,
    };
}

/// Clamp incremental jog distance to stay within pendant soft limits.
/// Returns null when the move is fully blocked.
pub fn clampJogDistance(
    mpos: cnc_state.Position,
    axis: u8,
    distance: f32,
    homed: bool,
    soft: SoftLimits,
) ?f32 {
    if (!soft.enabled or !homed or distance == 0) return distance;
    const pos = axisMachinePos(mpos, axis) orelse return distance;
    const max_tr = axisMaxTravel(soft, axis) orelse return distance;
    const target = pos + distance;
    if (target >= 0 and target <= max_tr) return distance;
    const clamped: f32 = if (target < 0) -pos else max_tr - pos;
    if ((distance > 0 and clamped <= 0) or (distance < 0 and clamped >= 0)) return null;
    return clamped;
}

pub fn clampJogFeedRate(requested: f32, limits: cnc_config.MachineLimits) f32 {
    const jog_cap = @as(f32, @floatFromInt(limits.default_jog));
    const feed_cap = @as(f32, @floatFromInt(limits.max_feed_rate));
    var cap = @min(jog_cap, feed_cap);
    if (cap <= 0.0) cap = 1.0;
    return @min(@max(requested, 0.0), cap);
}

fn clampOverridePct(base: f32, pct: u8, max_val: u16) u8 {
    const clamped = std.math.clamp(pct, 10, 200);
    if (base <= 0.0 or max_val == 0) return clamped;
    const max_f = @as(f32, @floatFromInt(max_val));
    const effective = base * @as(f32, @floatFromInt(clamped)) / 100.0;
    if (effective <= max_f) return clamped;
    return @as(u8, @intCast(@min(200, @max(10, @as(i32, @trunc(
        max_f * 100.0 / base,
    ))))));
}

pub fn clampFeedOverridePct(base_feed: f32, pct: u8, max_feed: u16) u8 {
    return clampOverridePct(base_feed, pct, max_feed);
}

pub fn clampSpindleOverridePct(base_rpm: f32, pct: u8, max_rpm: u16) u8 {
    return clampOverridePct(base_rpm, pct, max_rpm);
}

pub fn clampSpindleRpm(requested: f32, max_rpm: u16) f32 {
    if (max_rpm == 0) return @max(requested, 0.0);
    const cap = @as(f32, @floatFromInt(max_rpm));
    return @min(@max(requested, 0.0), cap);
}

/// Rewrite `line` into `buf`, clamping any G-code S-word to `max_rpm`.
/// Settings lines (`$…`) pass through unchanged. Returns null if `buf` is too small.
pub fn clampGcodeSpindle(line: []const u8, buf: []u8, max_rpm: u16) ?[]const u8 {
    if (line.len > buf.len) return null;
    if (line.len == 0) return line;
    if (line[0] == '$') {
        @memcpy(buf[0..line.len], line);
        return buf[0..line.len];
    }

    var out_len: usize = 0;
    var i: usize = 0;
    while (i < line.len) {
        if (line[i] == ';') {
            const rest = line[i..];
            if (out_len + rest.len > buf.len) return null;
            @memcpy(buf[out_len..][0..rest.len], rest);
            return buf[0 .. out_len + rest.len];
        }
        if (line[i] == '(') {
            var j = i + 1;
            while (j < line.len and line[j] != ')') : (j += 1) {}
            if (j < line.len) j += 1;
            const seg = line[i..j];
            if (out_len + seg.len > buf.len) return null;
            @memcpy(buf[out_len..][0..seg.len], seg);
            out_len += seg.len;
            i = j;
            continue;
        }

        const at_word = i == 0 or std.ascii.isWhitespace(line[i - 1]);
        if (at_word and i + 1 < line.len and (line[i] == 'S' or line[i] == 's')) {
            const c = line[i + 1];
            if (c == '.' or c == '-' or std.ascii.isDigit(c)) {
                var j = i + 1;
                if (line[j] == '-') j += 1;
                while (j < line.len and (std.ascii.isDigit(line[j]) or line[j] == '.')) : (j += 1) {}
                const num_str = line[i + 1 .. j];
                const rpm = std.fmt.parseFloat(f32, num_str) catch null;
                if (rpm) |raw| {
                    const clamped = clampSpindleRpm(raw, max_rpm);
                    const had_frac = std.mem.indexOfScalar(u8, num_str, '.') != null;
                    const prefix = line[i .. i + 1];
                    const written = if (had_frac)
                        std.fmt.bufPrint(buf[out_len..], "{s}{d:.3}", .{ prefix, clamped }) catch return null
                    else
                        std.fmt.bufPrint(buf[out_len..], "{s}{d:.0}", .{ prefix, clamped }) catch return null;
                    out_len += written.len;
                    i = j;
                    continue;
                }
            }
        }

        buf[out_len] = line[i];
        out_len += 1;
        i += 1;
    }
    return buf[0..out_len];
}

test "envelope: jog feed capped by jog and max feed" {
    const lim = cnc_config.MachineLimits{ .max_feed_rate = 5000, .default_jog = 1000 };
    try std.testing.expectEqual(@as(f32, 800.0), clampJogFeedRate(800.0, lim));
    try std.testing.expectEqual(@as(f32, 1000.0), clampJogFeedRate(3000.0, lim));
}

test "envelope: feed override capped by max feed" {
    try std.testing.expectEqual(@as(u8, 100), clampFeedOverridePct(4000.0, 100, 5000));
    try std.testing.expectEqual(@as(u8, 125), clampFeedOverridePct(4000.0, 150, 5000));
}

test "envelope: spindle override capped by max rpm" {
    try std.testing.expectEqual(@as(u8, 100), clampSpindleOverridePct(12000.0, 100, 24000));
    try std.testing.expectEqual(@as(u8, 100), clampSpindleOverridePct(24000.0, 150, 24000));
}

test "envelope: spindle rpm and S-word clamp" {
    try std.testing.expectEqual(@as(f32, 24000.0), clampSpindleRpm(30000.0, 24000));
    var buf: [64]u8 = undefined;
    const out = clampGcodeSpindle("M3 S30000", &buf, 24000).?;
    try std.testing.expectEqualStrings("M3 S24000", out);
    const pass = clampGcodeSpindle("$30=24000", &buf, 12000).?;
    try std.testing.expectEqualStrings("$30=24000", pass);
}

test "envelope: soft limit clamps jog at boundary" {
    const soft: SoftLimits = .{ .enabled = true, .max_x = 300, .max_y = 300, .max_z = 100, .max_a = 360 };
    const mpos = cnc_state.Position{ .x = 295, .y = 0, .z = 0 };
    try std.testing.expectEqual(@as(?f32, 5), clampJogDistance(mpos, 0, 10, true, soft));
    try std.testing.expectEqual(@as(?f32, 10), clampJogDistance(mpos, 0, 10, false, soft));
    try std.testing.expectEqual(@as(?f32, -5), clampJogDistance(cnc_state.Position{ .x = 5 }, 0, -10, true, soft));
    try std.testing.expectEqual(@as(?f32, 10), clampJogDistance(.{ .a = 350 }, 3, 20, true, soft));
}
