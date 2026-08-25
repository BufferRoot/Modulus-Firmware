//! Jog mode & increment card widget (dashboard center).
//! MD3: tonal card, segmented button group, filter-style incr tiles.

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const expr = @import("widgets_expressive.zig");
const form = @import("settings_form.zig");
const color = @import("color.zig");

pub const mode_count: usize = 3;
pub const incr_count: usize = 4;

pub const mode_labels = [_][]const u8{ "Step", "Cont", "Velo" };

pub const incr_labels = [_]struct { value: []const u8, mult: []const u8 }{
    .{ .value = "0.001", .mult = "x1" },
    .{ .value = "0.01", .mult = "x10" },
    .{ .value = "0.10", .mult = "x100" },
    .{ .value = "1", .mult = "x1000" },
};

pub const mult_labels = [_][]const u8{ "x1", "x10", "x100", "x1000" };

pub const State = struct {
    mode: usize = 2, // Velo (matches reference)
    incr: usize = 1, // 0.01 / x10
    /// Optional override values (null = use incr_labels defaults).
    value_overrides: [incr_count]?[]const u8 = .{ null, null, null, null },

    pub fn clampMode(m: usize) usize {
        return @min(m, mode_count - 1);
    }

    pub fn clampIncr(i: usize) usize {
        return @min(i, incr_count - 1);
    }

    pub fn valueAt(self: State, i: usize) []const u8 {
        if (i >= incr_count) return "?";
        if (self.value_overrides[i]) |v| return v;
        return incr_labels[i].value;
    }
};

pub const HitKind = enum { none, mode, incr };

pub const Hit = struct {
    kind: HitKind = .none,
    index: usize = 0,
};

/// LVGL `ui_widget_jog.c`: pad_all LG, pad_row MD, header+seg 48, chips 72.
/// 24 + 48 + 16 + 72 + 24 = 184.
pub const card_h: i32 = 184;
const inner: i32 = tokens.Space.lg; // MOD_UI_SPACE_LG
const header_h: i32 = tokens.Logical.touch_min; // segment TOUCH_MIN (header set 36 but seg is 48)
const seg_w: i32 = 232; // 3×76 + track pad 2×2
const seg_h: i32 = tokens.Logical.touch_min;
const gap: i32 = tokens.Space.sm + tokens.Space.xs; // chip pad_column SM+XS = 12
const row_gap: i32 = tokens.Space.md; // pad_row MD
const incr_h: i32 = 72;
const incr_rad: i32 = tokens.Shape.lg; // unselected chip MOD_UI_SHAPE_LG
/// LVGL BODY_M = Montserrat 14 → Zig `.body_s` (ui14).
const title_role: tokens.TypeRole = .body_s;
/// LVGL DISPLAY_S = Montserrat 24 → `.display_s` (ui22 bake).
const value_role: tokens.TypeRole = .display_s;
/// LVGL LABEL_M = Montserrat 12 → `.label_m` (ui14).
const mult_role: tokens.TypeRole = .label_m;

const Layout = struct {
    seg: geom.Rect,
    row_y: i32,
    row_h: i32,
    cell_w: i32,
};

fn layout(bounds: geom.Rect) Layout {
    const title = "Jog mode & increment";
    const title_w = font.textWidthStr(title, title_role);
    const zone_x = bounds.x + inner + title_w + tokens.Space.sm;
    const zone_w = bounds.w - inner * 2 - title_w - tokens.Space.sm;
    const seg_x = zone_x + @divTrunc(@max(0, zone_w - seg_w), 2);
    const seg: geom.Rect = .{
        .x = seg_x,
        .y = bounds.y + @divTrunc(inner + header_h - seg_h, 2),
        .w = seg_w,
        .h = seg_h,
    };
    const row_y = bounds.y + inner + header_h + row_gap;
    const row_h = incr_h;
    const cell_w = @divTrunc(bounds.w - inner * 2 - gap * @as(i32, @intCast(incr_count - 1)), @as(i32, @intCast(incr_count)));
    return .{ .seg = seg, .row_y = row_y, .row_h = row_h, .cell_w = cell_w };
}

/// Expand visual rect to ≥48dp touch without changing paint size.
fn touchExpand(r: geom.Rect) geom.Rect {
    const min = tokens.Logical.touch_min;
    var out = r;
    if (out.h < min) {
        const d = min - out.h;
        out.y -= @divTrunc(d, 2);
        out.h = min;
    }
    if (out.w < min) {
        const d = min - out.w;
        out.x -= @divTrunc(d, 2);
        out.w = min;
    }
    return out;
}

pub fn paint(logical: *fb.LogicalFb, bounds: geom.Rect, theme: tokens.Theme, state: State) void {
    const mode = State.clampMode(state.mode);
    const incr = State.clampIncr(state.incr);
    const rad = tokens.Shape.md; // card = medium
    const lay = layout(bounds);

    widgets.fillRoundRect(logical, bounds, rad, theme.elev(2));

    const title = "Jog mode & increment";
    const title_y = bounds.y + @divTrunc(inner + header_h - font.faceHeight(font.faceForRole(title_role)), 2);
    font.drawTextRole(logical, bounds.x + inner, title_y, title, theme.on_surface_variant, title_role);

    // Discrete segment index — spring morph looked like Step↔Velo thrash when
    // multi-clicks raced the pill across Cont.
    expr.drawButtonGroupF(logical, lay.seg, &mode_labels, @floatFromInt(mode), theme);

    var i: usize = 0;
    while (i < incr_count) : (i += 1) {
        const cell: geom.Rect = .{
            .x = bounds.x + inner + @as(i32, @intCast(i)) * (lay.cell_w + gap),
            .y = lay.row_y,
            .w = lay.cell_w,
            .h = lay.row_h,
        };
        // Discrete selected fill — spring morph left both chips looking "on".
        paintIncrCell(logical, cell, state.valueAt(i), mult_labels[i], if (i == incr) 1 else 0, i == incr, theme);
    }
}

fn paintIncrCell(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    value: []const u8,
    mult: []const u8,
    select_t: f32,
    selected: bool,
    theme: tokens.Theme,
) void {
    const t = std.math.clamp(select_t, 0, 1);
    const a: u8 = @intFromFloat(t * 255);
    const fill = color.blendRgb565(theme.elev(3), theme.secondary_container, a);
    // Discrete ink — spring-blended text washed out on elev(3) mid-morph (looked "gone").
    const fg = if (selected) theme.on_secondary_container else theme.on_surface;
    const muted = if (selected) theme.on_secondary_container else theme.on_surface_variant;
    widgets.fillRoundRect(logical, r, incr_rad, fill);

    const vh = font.faceHeight(font.faceForRole(value_role));
    const mh = font.faceHeight(font.faceForRole(mult_role));
    const stack = vh + tokens.Space.xs + mh;
    const y0 = r.y + @divTrunc(r.h - stack, 2);
    const vw = font.textWidthStr(value, value_role);
    font.drawTextRole(logical, r.x + @divTrunc(r.w - vw, 2), y0, value, fg, value_role);
    const mw = font.textWidthStr(mult, mult_role);
    font.drawTextRole(logical, r.x + @divTrunc(r.w - mw, 2), y0 + vh + tokens.Space.xs, mult, muted, mult_role);
}

pub fn hitTest(bounds: geom.Rect, x: i32, y: i32) Hit {
    if (!bounds.contains(x, y)) return .{};
    const lay = layout(bounds);

    const mode_hit = touchExpand(lay.seg);
    if (mode_hit.contains(x, y)) {
        const n = @as(i32, @intCast(mode_count));
        // Match drawSegmented equal slices (remainder-safe).
        const rel = x - lay.seg.x;
        const idx = if (lay.seg.w <= 0) @as(i32, 0) else @divTrunc(rel * n, lay.seg.w);
        if (idx >= 0 and idx < n) {
            return .{ .kind = .mode, .index = @intCast(idx) };
        }
        return .{};
    }

    if (y < lay.row_y or y >= lay.row_y + lay.row_h) return .{};

    const local = x - (bounds.x + inner);
    if (local < 0) return .{};
    const stride = lay.cell_w + gap;
    const idx = @divTrunc(local, stride);
    const within = @rem(local, stride);
    if (idx >= 0 and idx < @as(i32, @intCast(incr_count)) and within < lay.cell_w) {
        const cell: geom.Rect = .{
            .x = bounds.x + inner + idx * stride,
            .y = lay.row_y,
            .w = lay.cell_w,
            .h = lay.row_h,
        };
        if (touchExpand(cell).contains(x, y)) {
            return .{ .kind = .incr, .index = @intCast(idx) };
        }
    }
    return .{};
}

test "jog preferred height fits header and row" {
    try std.testing.expectEqual(@as(i32, 184), card_h);
    try std.testing.expect(card_h >= inner * 2 + header_h + row_gap + incr_h);
    try std.testing.expect(@rem(inner, 8) == 0);
}

test "hit picks mode and incr" {
    const bounds: geom.Rect = .{ .x = 100, .y = 100, .w = 480, .h = card_h };
    const lay = layout(bounds);
    const mode_hit = hitTest(bounds, lay.seg.x + 10, lay.seg.y + 10);
    try std.testing.expect(mode_hit.kind == .mode);
    try std.testing.expect(mode_hit.index == 0);

    const incr_hit = hitTest(bounds, bounds.x + inner + lay.cell_w + gap + 4, lay.row_y + 20);
    try std.testing.expect(incr_hit.kind == .incr);
    try std.testing.expect(incr_hit.index == 1);
}

test "mode segment centered in title remainder" {
    const bounds: geom.Rect = .{ .x = 0, .y = 0, .w = 500, .h = card_h };
    const lay = layout(bounds);
    const title_w = font.textWidthStr("Jog mode & increment", title_role);
    const zone_x = inner + title_w + tokens.Space.sm;
    const zone_w = bounds.w - inner * 2 - title_w - tokens.Space.sm;
    const expect_x = zone_x + @divTrunc(@max(0, zone_w - seg_w), 2);
    try std.testing.expect(lay.seg.x == expect_x);
    try std.testing.expectEqual(seg_w, lay.seg.w);
    try std.testing.expectEqual(incr_h, lay.row_h);
}

test "mode touch target at least 48dp" {
    const bounds: geom.Rect = .{ .x = 0, .y = 0, .w = 500, .h = card_h };
    const lay = layout(bounds);
    const hit = touchExpand(lay.seg);
    try std.testing.expect(hit.h >= tokens.Logical.touch_min);
}
