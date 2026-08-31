//! Feed / Spindle / Rapid override cards — MD3 tonal ± / Reset.
//! Dashboard shows exactly two cards; slot pick lives in Dashboard prefs.

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const icons_phosphor = @import("icons_phosphor.zig");

pub const Which = enum(u8) { feed = 0, spindle = 1, rapid = 2 };

pub const State = struct {
    feed_pct: u8 = 100,
    spindle_pct: u8 = 100,
    rapid_pct: u8 = 100,
    feed_vis: f32 = 100,
    spindle_vis: f32 = 100,
    rapid_vis: f32 = 100,
};

pub const HitKind = enum { none, plus, minus, reset, fab };

pub const Hit = struct {
    kind: HitKind = .none,
    which: Which = .feed,
};

pub const pct_min: u8 = 10;
pub const pct_max: u8 = 200;

/// grblHAL rapid levels only — ± cycles 25 ↔ 50 ↔ 100; reset → 100.
pub const rapid_levels = [_]u8{ 25, 50, 100 };

pub fn clampWhich(v: u8) Which {
    return switch (v) {
        1 => .spindle,
        2 => .rapid,
        else => .feed,
    };
}

pub fn titleOf(which: Which) []const u8 {
    return switch (which) {
        .feed => "Feed override",
        .spindle => "Spindle override",
        .rapid => "Rapid override",
    };
}

pub fn pressKey(which: Which, kind: HitKind) []const u8 {
    return switch (kind) {
        .plus => switch (which) {
            .feed => "ovr.feed.plus",
            .spindle => "ovr.spindle.plus",
            .rapid => "ovr.rapid.plus",
        },
        .minus => switch (which) {
            .feed => "ovr.feed.minus",
            .spindle => "ovr.spindle.minus",
            .rapid => "ovr.rapid.minus",
        },
        .reset, .none, .fab => switch (which) {
            .feed => "ovr.feed.reset",
            .spindle => "ovr.spindle.reset",
            .rapid => "ovr.rapid.reset",
        },
    };
}

/// Feed/spindle ±10; rapid steps discrete levels. Zero delta = reset-to-100.
pub fn stepPct(which: Which, cur: u8, delta: i8) u8 {
    if (which == .rapid) return stepRapid(cur, delta);
    if (delta == 0) return 100;
    const raw = @as(i16, cur) + @as(i16, delta);
    return @intCast(std.math.clamp(raw, @as(i16, pct_min), @as(i16, pct_max)));
}

pub fn stepRapid(cur: u8, delta: i8) u8 {
    if (delta == 0) return 100;
    const idx: usize = blk: {
        if (cur <= 25) break :blk 0;
        if (cur <= 50) break :blk 1;
        break :blk 2;
    };
    if (delta > 0) {
        return rapid_levels[@min(idx + 1, rapid_levels.len - 1)];
    }
    return rapid_levels[if (idx == 0) 0 else idx - 1];
}

/// Ensure left ≠ right; if collision, pick next unused which for `other`.
pub fn coercePair(left: Which, right: Which) [2]Which {
    if (left != right) return .{ left, right };
    const next: Which = switch (left) {
        .feed => .spindle,
        .spindle => .rapid,
        .rapid => .feed,
    };
    return .{ left, next };
}

const inner: i32 = tokens.Space.md;
const gap: i32 = tokens.Space.lg;
const btn_r: i32 = 34;
const reset_h: i32 = 44;
const icon_px: i32 = 32;
/// MD3 large FAB — sits in the card gap, overlaps both panels at the % row.
const fab_d: i32 = 96;
const fab_ring: i32 = 5;
const pct_role: tokens.TypeRole = .display_m;
const title_role: tokens.TypeRole = .body_s;

const CardLay = struct {
    title_y: i32,
    plus: geom.Rect,
    minus: geom.Rect,
    pct_y: i32,
    reset: geom.Rect,
};

fn cardLay(card: geom.Rect) CardLay {
    const cx = card.x + @divTrunc(card.w, 2);
    const title_h = font.faceHeight(font.faceForRole(title_role));
    const title_y = card.y + inner;
    const title_bot = title_y + title_h;
    const reset = resetRect(card);
    const pct_h = font.faceHeight(font.faceForRole(pct_role));
    const btn_d = btn_r * 2;
    const pad = tokens.Space.sm;

    const band_top = title_bot + pad;
    const band_bot = reset.y - pad;
    const band_h = @max(btn_d * 2 + pct_h + pad * 2, band_bot - band_top);

    var up_cy = band_top + @divTrunc(band_h, 6);
    const pct_cy = band_top + @divTrunc(band_h, 2);
    var down_cy = band_bot - @divTrunc(band_h, 6);
    const min_gap = btn_d + pad;
    if (down_cy - up_cy < min_gap) {
        const mid = @divTrunc(band_top + band_bot, 2);
        up_cy = mid - @divTrunc(min_gap, 2);
        down_cy = mid + @divTrunc(min_gap, 2);
    }
    const pct_y = pct_cy - @divTrunc(pct_h, 2);

    return .{
        .title_y = title_y,
        .plus = .{ .x = cx - btn_r, .y = up_cy - btn_r, .w = btn_d, .h = btn_d },
        .minus = .{ .x = cx - btn_r, .y = down_cy - btn_r, .w = btn_d, .h = btn_d },
        .pct_y = pct_y,
        .reset = reset,
    };
}

fn visOf(state: State, which: Which) f32 {
    return switch (which) {
        .feed => state.feed_vis,
        .spindle => state.spindle_vis,
        .rapid => state.rapid_vis,
    };
}

pub fn paintPair(logical: *fb.LogicalFb, bounds: geom.Rect, theme: tokens.Theme, state: State, slots: [2]Which) void {
    const pair = coercePair(slots[0], slots[1]);
    const card_w = @divTrunc(bounds.w - gap, 2);
    paintCard(logical, .{
        .x = bounds.x,
        .y = bounds.y,
        .w = card_w,
        .h = bounds.h,
    }, theme, titleOf(pair[0]), visOf(state, pair[0]), pair[0]);
    paintCard(logical, .{
        .x = bounds.x + card_w + gap,
        .y = bounds.y,
        .w = card_w,
        .h = bounds.h,
    }, theme, titleOf(pair[1]), visOf(state, pair[1]), pair[1]);
    // After cards so the FAB overlaps the seam (placeholder — no action yet).
    paintFabPlaceholder(logical, bounds, theme);
}

/// Centered on the override pair, vertically on the % readout (mock FAB location).
pub fn fabRect(bounds: geom.Rect) geom.Rect {
    const card_w = @divTrunc(bounds.w - gap, 2);
    const left: geom.Rect = .{ .x = bounds.x, .y = bounds.y, .w = card_w, .h = bounds.h };
    const lay = cardLay(left);
    const pct_h = font.faceHeight(font.faceForRole(pct_role));
    const cy = lay.pct_y + @divTrunc(pct_h, 2);
    const cx = bounds.x + @divTrunc(bounds.w, 2);
    return .{
        .x = cx - @divTrunc(fab_d, 2),
        .y = cy - @divTrunc(fab_d, 2),
        .w = fab_d,
        .h = fab_d,
    };
}

fn paintFabPlaceholder(logical: *fb.LogicalFb, bounds: geom.Rect, theme: tokens.Theme) void {
    const r = fabRect(bounds);
    const cx = r.x + @divTrunc(r.w, 2);
    const cy = r.y + @divTrunc(r.h, 2);
    const rad = @divTrunc(fab_d, 2);
    // MD3 surface FAB: elev(3) container + on_surface icon (recessive vs primary_container).
    // Outer ring = surface so seam clears card elev(2) without shadow.
    widgets.drawCircleButton(logical, cx, cy, rad, theme.surface);
    widgets.drawCircleButton(logical, cx, cy, rad - fab_ring, theme.elev(3));
    icons_phosphor.drawCenteredScaled(logical, cx, cy, .cards_three, theme.on_surface, 40);
}

fn paintCard(logical: *fb.LogicalFb, r: geom.Rect, theme: tokens.Theme, title: []const u8, pct: f32, which: Which) void {
    const form = @import("settings_form.zig");
    widgets.fillRoundRect(logical, r, tokens.Shape.md, theme.elev(2));
    const cx = r.x + @divTrunc(r.w, 2);
    const lay = cardLay(r);

    const tw = font.textWidthStr(title, title_role);
    font.drawTextRole(logical, cx - @divTrunc(tw, 2), lay.title_y, title, theme.on_surface, title_role);

    const plus_press = form.sampleWidget(pressKey(which, .plus), 0);
    const minus_press = form.sampleWidget(pressKey(which, .minus), 0);
    const reset_press = form.sampleWidget(pressKey(which, .reset), 0);

    const plus_cx = lay.plus.x + btn_r;
    const plus_cy = lay.plus.y + btn_r;
    const plus_bg = if (plus_press > 0.05) theme.secondary_container else theme.elev(3);
    widgets.fillRoundRect(logical, lay.plus, tokens.Shape.full, plus_bg);
    icons_phosphor.drawCenteredScaled(logical, plus_cx, plus_cy, .arrow_up, theme.on_surface_variant, icon_px);

    const minus_cx = lay.minus.x + btn_r;
    const minus_cy = lay.minus.y + btn_r;
    const minus_bg = if (minus_press > 0.05) theme.secondary_container else theme.elev(3);
    widgets.fillRoundRect(logical, lay.minus, tokens.Shape.full, minus_bg);
    icons_phosphor.drawCenteredScaled(logical, minus_cx, minus_cy, .arrow_down, theme.on_surface_variant, icon_px);

    var buf: [8]u8 = undefined;
    const shown: u32 = @intFromFloat(@round(std.math.clamp(pct, 0, 200)));
    const t = std.fmt.bufPrint(&buf, "{d}%", .{shown}) catch "?";
    const nw = font.textWidthStr(t, pct_role);
    font.drawTextRole(logical, cx - @divTrunc(nw, 2), lay.pct_y, t, theme.on_surface, pct_role);

    const reset_bg = if (reset_press > 0.08) theme.secondary_container else theme.elev(3);
    widgets.fillRoundRect(logical, lay.reset, tokens.Shape.full, reset_bg);
    const rst = "Reset";
    const rtw = font.textWidthStr(rst, title_role);
    font.drawTextRole(
        logical,
        lay.reset.x + @divTrunc(lay.reset.w - rtw, 2),
        lay.reset.y + @divTrunc(lay.reset.h - font.faceHeight(font.faceForRole(title_role)), 2),
        rst,
        theme.on_surface,
        title_role,
    );
}

fn resetRect(card: geom.Rect) geom.Rect {
    const rw = @max(120, card.w - tokens.Space.lg * 2);
    return .{
        .x = card.x + @divTrunc(card.w - rw, 2),
        .y = card.y + card.h - inner - reset_h,
        .w = rw,
        .h = reset_h,
    };
}

fn cardAt(bounds: geom.Rect, slot: u1) geom.Rect {
    const card_w = @divTrunc(bounds.w - gap, 2);
    return if (slot == 0)
        .{ .x = bounds.x, .y = bounds.y, .w = card_w, .h = bounds.h }
    else
        .{ .x = bounds.x + card_w + gap, .y = bounds.y, .w = card_w, .h = bounds.h };
}

fn touchSlab(card: geom.Rect, r: geom.Rect, grow_y: i32) geom.Rect {
    return .{
        .x = card.x + inner,
        .y = r.y - grow_y,
        .w = card.w - inner * 2,
        .h = r.h + grow_y * 2,
    };
}

const slab_grow: i32 = tokens.Space.md;

pub fn hitTest(bounds: geom.Rect, x: i32, y: i32, slots: [2]Which) Hit {
    if (fabRect(bounds).contains(x, y)) return .{ .kind = .fab, .which = .feed };
    if (!bounds.contains(x, y)) return .{};
    const pair = coercePair(slots[0], slots[1]);
    for (pair, 0..) |which, si| {
        const card = cardAt(bounds, @intCast(si));
        if (!card.contains(x, y)) continue;
        const lay = cardLay(card);
        if (touchSlab(card, lay.reset, slab_grow).contains(x, y)) return .{ .kind = .reset, .which = which };
        if (touchSlab(card, lay.minus, slab_grow).contains(x, y)) return .{ .kind = .minus, .which = which };
        if (touchSlab(card, lay.plus, slab_grow).contains(x, y)) return .{ .kind = .plus, .which = which };
        return .{};
    }
    return .{};
}

test "pair hit feed plus" {
    const bounds: geom.Rect = .{ .x = 0, .y = 0, .w = 400, .h = 360 };
    const slots = [_]Which{ .feed, .spindle };
    const feed = cardAt(bounds, 0);
    const p = cardLay(feed).plus;
    const hit = hitTest(bounds, p.x + btn_r, p.y + btn_r, slots);
    try std.testing.expect(hit.kind == .plus);
    try std.testing.expect(hit.which == .feed);
}

test "pair hit spindle reset" {
    const bounds: geom.Rect = .{ .x = 0, .y = 0, .w = 400, .h = 360 };
    const slots = [_]Which{ .feed, .spindle };
    const spin = cardAt(bounds, 1);
    const r = resetRect(spin);
    const hit = hitTest(bounds, r.x + @divTrunc(r.w, 2), r.y + @divTrunc(r.h, 2), slots);
    try std.testing.expect(hit.kind == .reset);
    try std.testing.expect(hit.which == .spindle);
}

test "rapid slot hit" {
    const bounds: geom.Rect = .{ .x = 0, .y = 0, .w = 400, .h = 360 };
    const slots = [_]Which{ .feed, .rapid };
    const rapid = cardAt(bounds, 1);
    const p = cardLay(rapid).plus;
    const hit = hitTest(bounds, p.x + btn_r, p.y + btn_r, slots);
    try std.testing.expect(hit.which == .rapid);
    try std.testing.expect(hit.kind == .plus);
}

test "coercePair keeps distinct cards" {
    try std.testing.expectEqualSlices(Which, &coercePair(.feed, .feed), &[_]Which{ .feed, .spindle });
    try std.testing.expectEqualSlices(Which, &coercePair(.rapid, .rapid), &[_]Which{ .rapid, .feed });
}

test "plus and minus never overlap" {
    const bounds: geom.Rect = .{ .x = 0, .y = 0, .w = 400, .h = 280 };
    const feed = cardAt(bounds, 0);
    const lay = cardLay(feed);
    try std.testing.expect(lay.plus.y + lay.plus.h <= lay.minus.y);
    try std.testing.expect(lay.minus.y + lay.minus.h <= lay.reset.y);
}

test "stepPct clamps like the grblHAL driver" {
    try std.testing.expectEqual(@as(u8, 110), stepPct(.feed, 100, 10));
    try std.testing.expectEqual(@as(u8, 90), stepPct(.feed, 100, -10));
    try std.testing.expectEqual(@as(u8, 100), stepPct(.feed, 175, 0));
    try std.testing.expectEqual(pct_max, stepPct(.feed, 195, 10));
    try std.testing.expectEqual(pct_min, stepPct(.feed, 15, -10));
}

test "stepRapid cycles 25/50/100" {
    try std.testing.expectEqual(@as(u8, 100), stepRapid(50, 0));
    try std.testing.expectEqual(@as(u8, 50), stepRapid(25, 10));
    try std.testing.expectEqual(@as(u8, 100), stepRapid(50, 10));
    try std.testing.expectEqual(@as(u8, 100), stepRapid(100, 10));
    try std.testing.expectEqual(@as(u8, 50), stepRapid(100, -10));
    try std.testing.expectEqual(@as(u8, 25), stepRapid(50, -10));
    try std.testing.expectEqual(@as(u8, 25), stepRapid(25, -10));
}

test "md3 touch and spacing tokens" {
    try std.testing.expectEqual(@as(i32, 44), reset_h);
    try std.testing.expect(reset_h + slab_grow * 2 >= tokens.Logical.touch_min);
    try std.testing.expect(btn_r * 2 >= tokens.Logical.touch_min);
    try std.testing.expectEqual(@as(i32, 68), btn_r * 2);
    try std.testing.expect(@rem(inner, 8) == 0);
    try std.testing.expect(@rem(gap, 8) == 0);
}

test "fab placeholder sits on % row between cards" {
    const bounds: geom.Rect = .{ .x = 0, .y = 0, .w = 400, .h = 360 };
    const fab = fabRect(bounds);
    try std.testing.expectEqual(fab_d, fab.w);
    try std.testing.expectEqual(fab_d, fab.h);
    try std.testing.expectEqual(bounds.x + @divTrunc(bounds.w, 2), fab.x + @divTrunc(fab.w, 2));
    const left = cardAt(bounds, 0);
    const lay = cardLay(left);
    const pct_cy = lay.pct_y + @divTrunc(font.faceHeight(font.faceForRole(pct_role)), 2);
    try std.testing.expectEqual(pct_cy, fab.y + @divTrunc(fab.h, 2));
    // Overlaps the seam (wider than gap).
    try std.testing.expect(fab.w > gap);
}

test "fab hit on seam" {
    const bounds: geom.Rect = .{ .x = 0, .y = 0, .w = 400, .h = 360 };
    const fab = fabRect(bounds);
    const hit = hitTest(bounds, fab.x + @divTrunc(fab.w, 2), fab.y + @divTrunc(fab.h, 2), .{ .feed, .spindle });
    try std.testing.expect(hit.kind == .fab);
}
