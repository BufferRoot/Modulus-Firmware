//! M3 Expressive component paints (host). Spec subset from m3.material.io.
//! Full Material Web / Compose catalogs are reference only — paint, don't port frameworks.

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const color = @import("color.zig");

pub fn drawOutlinedButton(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, theme: tokens.Theme) void {
    widgets.drawButton(logical, r, label, .outlined, .enabled, theme);
}

pub fn drawTextButton(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, theme: tokens.Theme) void {
    widgets.drawButton(logical, r, label, .text, .enabled, theme);
}

pub fn drawIconButton(logical: *fb.LogicalFb, cx: i32, cy: i32, filled: bool, theme: tokens.Theme) void {
    drawIconButtonState(logical, cx, cy, if (filled) .filled else .outlined, .enabled, false, theme);
}

pub fn drawIconButtonState(
    logical: *fb.LogicalFb,
    cx: i32,
    cy: i32,
    style: widgets.IconButtonStyle,
    state: widgets.ButtonState,
    selected: bool,
    theme: tokens.Theme,
) void {
    const r: geom.Rect = .{ .x = cx - 20, .y = cy - 20, .w = 40, .h = 40 };
    widgets.drawIconButton(logical, r, style, state, selected, theme);
}

pub fn iconButtonHit(cx: i32, cy: i32) geom.Rect {
    return tokens.Logical.touchHit(cx, cy);
}

pub fn drawElevatedButton(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, theme: tokens.Theme) void {
    widgets.drawButton(logical, r, label, .elevated, .enabled, theme);
}

pub fn drawOutlineChip(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, theme: tokens.Theme) void {
    widgets.fillRoundRect(logical, r, @divTrunc(r.h, 2), theme.elev(1));
    widgets.strokeRoundRect(logical, .{ .x = r.x + 1, .y = r.y + 1, .w = r.w - 2, .h = r.h - 2 }, @divTrunc(r.h, 2) - 1, theme.outline, 1);
    const tw = font.textWidthStr(label, .label_l);
    font.drawTextRole(logical, r.x + @divTrunc(r.w - tw, 2), r.y + @divTrunc(r.h - font.faceHeight(.ui16), 2), label, theme.on_surface, .label_l);
}

/// Small count badge (top-right of an anchor).
pub fn drawBadge(logical: *fb.LogicalFb, ax: i32, ay: i32, count: u8, theme: tokens.Theme) void {
    const r: i32 = 10;
    const cx = ax + 10;
    const cy = ay - 4;
    widgets.drawCircleButton(logical, cx, cy, r, theme.err);
    if (count == 0) return;
    var buf: [3]u8 = undefined;
    const s = if (count > 9) "9+" else std.fmt.bufPrint(&buf, "{d}", .{count}) catch "?";
    const tw = font.textWidth(s.len, 1);
    font.drawText(logical, cx - @divTrunc(tw, 2), cy - 4, s, theme.on_error, 1);
}

/// Morph between circle (t=0) and diamond (t=1) — Core-0 cheap, no heap.
pub fn drawShapeMorph(logical: *fb.LogicalFb, cx: i32, cy: i32, radius: i32, t: f32, c: color.Rgb565) void {
    const u = std.math.clamp(t, 0, 1);
    if (u < 0.08) {
        widgets.drawCircleButton(logical, cx, cy, radius, c);
        return;
    }
    if (u > 0.92) {
        drawShapeDemo(logical, cx - radius, cy - radius, radius * 2, .diamond, c);
        return;
    }
    // Mid: squircle-ish — circle with diamond inset scaled by t
    widgets.drawCircleButton(logical, cx, cy, radius, c);
    const inset = @as(i32, @intFromFloat(@as(f32, @floatFromInt(radius)) * (1.0 - u * 0.55)));
    if (inset > 2) drawShapeDemo(logical, cx - inset, cy - inset, inset * 2, .diamond, c);
}

pub fn drawFab(logical: *fb.LogicalFb, r: geom.Rect, theme: tokens.Theme) void {
    const ink = widgets.drawButtonSurface(logical, r, .primary_container, .enabled, theme, 0, 0, 0);
    const cx = r.x + @divTrunc(r.w, 2);
    const cy = r.y + @divTrunc(r.h, 2);
    logical.fillRect(.{ .x = cx - 8, .y = cy - 2, .w = 16, .h = 4 }, ink);
    logical.fillRect(.{ .x = cx - 2, .y = cy - 8, .w = 4, .h = 16 }, ink);
}

pub fn drawExtendedFab(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, theme: tokens.Theme) void {
    const ink = widgets.drawButtonSurface(logical, r, .primary_container, .enabled, theme, 0, 0, 0);
    logical.fillRect(.{ .x = r.x + 20, .y = r.y + @divTrunc(r.h, 2) - 2, .w = 14, .h = 4 }, ink);
    logical.fillRect(.{ .x = r.x + 25, .y = r.y + @divTrunc(r.h, 2) - 7, .w = 4, .h = 14 }, ink);
    font.drawTextRole(logical, r.x + 48, r.y + @divTrunc(r.h - 16, 2), label, ink, .emph_label_l);
}

pub fn drawFabMenuItem(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, theme: tokens.Theme) void {
    widgets.fillRoundRect(logical, r, tokens.Shape.lg, theme.elev(3));
    font.drawTextRole(logical, r.x + 16, r.y + @divTrunc(r.h - 12, 2), label, theme.on_surface, .label_l);
}

/// Connected button group (Expressive) — shared track, selected = primary container.
pub fn drawButtonGroup(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    labels: []const []const u8,
    selected: usize,
    theme: tokens.Theme,
) void {
    drawButtonGroupF(logical, r, labels, @floatFromInt(selected), theme);
}

pub fn drawButtonGroupF(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    labels: []const []const u8,
    selected_f: f32,
    theme: tokens.Theme,
) void {
    widgets.drawSegmentedF(logical, r, labels, selected_f, theme);
}

/// Split button: primary action + chevron menu.
pub fn drawSplitButton(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, theme: tokens.Theme) void {
    const menu_w: i32 = 48;
    const main: geom.Rect = .{ .x = r.x, .y = r.y, .w = r.w - menu_w - 4, .h = r.h };
    const menu: geom.Rect = .{ .x = r.x + r.w - menu_w, .y = r.y, .w = menu_w, .h = r.h };
    widgets.drawFilledButton(logical, main, label, theme);
    widgets.drawButton(logical, menu, "", .filled, .enabled, theme);
    widgets.drawChevronDown(logical, menu.x + @divTrunc(menu.w, 2), menu.y + @divTrunc(menu.h, 2), 6, theme.on_primary);
}

/// MD3 linear track height (dp). Job strip + catalog determinate bars.
pub const linear_track_h: i32 = 4;
/// Stop indicator radius (MD3 linear end cue; matches LVGL k_stop_r).
pub const linear_stop_r: i32 = 5;
const wave_amp: f32 = 4;
const wave_len: f32 = 36;
const indet_seg_pct: i32 = 28;

/// Determinate linear progress — primary active on tonal track (catalog / settings).
pub fn drawLinearProgress(logical: *fb.LogicalFb, r: geom.Rect, progress: f32, theme: tokens.Theme) void {
    drawLinearProgressTinted(logical, r, progress, theme, theme.primary, theme.primary_container);
}

/// Solid linear with gap + stop + container underlay (no wave).
pub fn drawLinearProgressTinted(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    progress: f32,
    theme: tokens.Theme,
    active: color.Rgb565,
    container: color.Rgb565,
) void {
    const rad = @divTrunc(r.h, 2);
    widgets.fillRoundRect(logical, r, rad, theme.surface_container_highest);
    const t = std.math.clamp(progress, 0, 1);
    if (t <= 0) return;

    var fw = @max(r.h, @as(i32, @intFromFloat(@as(f32, @floatFromInt(r.w)) * t)));
    if (t > 0.02 and t < 0.98 and fw > 8) fw -= 2;
    if (fw > r.w) fw = r.w;

    const under: geom.Rect = .{ .x = r.x, .y = r.y - 1, .w = fw, .h = r.h + 2 };
    widgets.fillRoundRect(logical, under, @divTrunc(under.h, 2), container);
    widgets.fillRoundRect(logical, .{ .x = r.x, .y = r.y, .w = fw, .h = r.h }, rad, active);

    if (fw > 4) {
        const cx = r.x + fw;
        const cy = r.y + @divTrunc(r.h, 2);
        widgets.drawCircleButton(logical, cx, cy, linear_stop_r + 2, theme.surface_container_highest);
        widgets.drawCircleButton(logical, cx, cy, linear_stop_r, active);
    }
}

/// Job-strip linear — LVGL `ui_job_progress` expressive: underlay + wave + stop.
/// `progress < 0` → indeterminate sliding segment (~28%); `phase` advances wave / slide.
pub fn drawJobProgressBar(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    progress: f32,
    phase: f32,
    theme: tokens.Theme,
    active: color.Rgb565,
    container: color.Rgb565,
) void {
    const rad = @divTrunc(r.h, 2);
    const mid_y = r.y + @divTrunc(r.h, 2);
    widgets.fillRoundRect(logical, r, rad, theme.surface_container_highest);

    const indet = progress < 0;
    var seg_x1: i32 = undefined;
    var seg_x2: i32 = undefined;
    if (indet) {
        const seg_w = @max(r.h * 2, @divTrunc(r.w * indet_seg_pct, 100));
        const travel = 1.0 + @as(f32, @floatFromInt(seg_w)) / @as(f32, @floatFromInt(r.w));
        var t = phase * 0.12;
        t -= @floor(t / travel) * travel;
        if (t < 0) t += travel;
        seg_x1 = r.x + @as(i32, @intFromFloat((t - @as(f32, @floatFromInt(seg_w)) / @as(f32, @floatFromInt(r.w))) * @as(f32, @floatFromInt(r.w))));
        seg_x2 = seg_x1 + seg_w;
        if (seg_x1 < r.x) seg_x1 = r.x;
        if (seg_x2 > r.x + r.w) seg_x2 = r.x + r.w;
    } else {
        const t = std.math.clamp(progress, 0, 1);
        if (t <= 0) return;
        seg_x1 = r.x;
        seg_x2 = r.x + @max(r.h, @as(i32, @intFromFloat(@as(f32, @floatFromInt(r.w)) * t)));
        if (t > 0.02 and t < 0.98 and seg_x2 > r.x + 8) seg_x2 -= 2;
        if (seg_x2 > r.x + r.w) seg_x2 = r.x + r.w;
    }
    if (seg_x2 <= seg_x1 + 2) return;

    const under: geom.Rect = .{ .x = seg_x1, .y = r.y - 1, .w = seg_x2 - seg_x1, .h = r.h + 2 };
    widgets.fillRoundRect(logical, under, @divTrunc(under.h, 2), container);
    paintWave(logical, seg_x1, seg_x2, mid_y, r.x, phase, active);

    if (!indet and seg_x2 > r.x + 4) {
        widgets.drawCircleButton(logical, seg_x2, mid_y, linear_stop_r + 2, theme.surface_container_highest);
        widgets.drawCircleButton(logical, seg_x2, mid_y, linear_stop_r, active);
    }
}

fn paintWave(logical: *fb.LogicalFb, x0: i32, x1: i32, mid_y: i32, track_x: i32, phase: f32, c: color.Rgb565) void {
    var prev_x = x0;
    var prev_y = mid_y;
    var x = x0 + 2;
    while (x <= x1) : (x += 2) {
        const t = @as(f32, @floatFromInt(x - track_x)) / wave_len + phase;
        const y = mid_y + @as(i32, @intFromFloat(@sin(t * std.math.pi * 2.0) * wave_amp));
        paintThickSeg(logical, prev_x, prev_y, x, y, c);
        prev_x = x;
        prev_y = y;
    }
}

fn paintThickSeg(logical: *fb.LogicalFb, x0: i32, y0: i32, x1: i32, y1: i32, c: color.Rgb565) void {
    const dx = x1 - x0;
    const dy = y1 - y0;
    const steps: i32 = @max(1, @max(@as(i32, @intCast(@abs(dx))), @as(i32, @intCast(@abs(dy)))));
    var i: i32 = 0;
    while (i <= steps) : (i += 1) {
        const px = x0 + @divTrunc(dx * i, steps);
        const py = y0 + @divTrunc(dy * i, steps);
        logical.fillRect(.{ .x = px - 1, .y = py - 1, .w = 3, .h = 3 }, c);
    }
}

pub fn drawCircularProgress(logical: *fb.LogicalFb, cx: i32, cy: i32, radius: i32, progress: f32, theme: tokens.Theme) void {
    const t = std.math.clamp(progress, 0, 1);
    const stroke: i32 = 4;
    widgets.drawCircleButton(logical, cx, cy, radius, theme.surface_container_highest);
    widgets.drawCircleButton(logical, cx, cy, radius - stroke, theme.elev(0));
    const steps: i32 = @max(1, @as(i32, @intFromFloat(t * 48)));
    const mid_r = @as(f32, @floatFromInt(radius)) - @as(f32, @floatFromInt(stroke)) / 2;
    var i: i32 = 0;
    while (i < steps) : (i += 1) {
        const ang = @as(f32, @floatFromInt(i)) / 48.0 * std.math.pi * 2.0 - std.math.pi / 2.0;
        const px = cx + @as(i32, @intFromFloat(@cos(ang) * mid_r));
        const py = cy + @as(i32, @intFromFloat(@sin(ang) * mid_r));
        logical.fillRect(.{ .x = px - 1, .y = py - 1, .w = 3, .h = 3 }, theme.primary);
    }
}

/// Loading indicator — indeterminate linear (sliding active segment).
pub fn drawLoadingIndicator(logical: *fb.LogicalFb, r: geom.Rect, phase: f32, theme: tokens.Theme) void {
    drawJobProgressBar(logical, r, -1, phase * 8, theme, theme.primary, theme.primary_container);
}

pub fn drawToolbar(logical: *fb.LogicalFb, r: geom.Rect, theme: tokens.Theme) void {
    widgets.fillRoundRect(logical, r, tokens.Shape.toolbar, theme.elev(3));
    // Icon slots
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        const cx = r.x + 36 + i * 56;
        const cy = r.y + @divTrunc(r.h, 2);
        widgets.drawCircleButton(logical, cx, cy, 16, theme.secondary_container);
    }
}

pub fn drawAppBar(logical: *fb.LogicalFb, r: geom.Rect, title: []const u8, theme: tokens.Theme) void {
    logical.fillRect(r, theme.elev(2));
    font.drawTextRole(logical, r.x + tokens.Space.md, r.y + @divTrunc(r.h - 20, 2), title, theme.on_surface, .emph_title_l);
    // Trailing icon buttons
    drawIconButton(logical, r.x + r.w - 40, r.y + @divTrunc(r.h, 2), false, theme);
    drawIconButton(logical, r.x + r.w - 88, r.y + @divTrunc(r.h, 2), false, theme);
}

pub fn drawNavBar(logical: *fb.LogicalFb, r: geom.Rect, labels: []const []const u8, selected: usize, theme: tokens.Theme) void {
    logical.fillRect(r, theme.elev(2));
    if (labels.len == 0) return;
    const slot = @divTrunc(r.w, @as(i32, @intCast(labels.len)));
    for (labels, 0..) |lab, i| {
        const sx = r.x + @as(i32, @intCast(i)) * slot;
        const sel = i == selected;
        if (sel) {
            widgets.fillRoundRect(logical, .{ .x = sx + 16, .y = r.y + 8, .w = slot - 32, .h = 28 }, 14, theme.secondary_container);
        }
        const tw = font.textWidth(lab.len, 1);
        font.drawText(logical, sx + @divTrunc(slot - tw, 2), r.y + 40, lab, if (sel) theme.on_secondary_container else theme.on_surface_variant, 1);
    }
}

pub fn drawNavRail(logical: *fb.LogicalFb, r: geom.Rect, labels: []const []const u8, selected: usize, theme: tokens.Theme) void {
    logical.fillRect(r, theme.elev(2));
    for (labels, 0..) |lab, i| {
        const y = r.y + 16 + @as(i32, @intCast(i)) * 72;
        widgets.drawNavItem(logical, r.x, y, r.w, lab, i == selected, theme);
    }
}

pub fn drawShapeDemo(logical: *fb.LogicalFb, x: i32, y: i32, size: i32, kind: tokens.Shape.Kind, c: color.Rgb565) void {
    const r: geom.Rect = .{ .x = x, .y = y, .w = size, .h = size };
    switch (kind) {
        .circle => widgets.drawCircleButton(logical, x + @divTrunc(size, 2), y + @divTrunc(size, 2), @divTrunc(size, 2), c),
        .pill => widgets.fillRoundRect(logical, .{ .x = x, .y = y + @divTrunc(size, 4), .w = size, .h = @divTrunc(size, 2) }, tokens.Shape.full, c),
        .square => logical.fillRect(r, c),
        .rounded => widgets.fillRoundRect(logical, r, tokens.Shape.md, c),
        .cookie => widgets.fillRoundRect(logical, r, tokens.Shape.lg_inc, c),
        .diamond => {
            const mid = @divTrunc(size, 2);
            var row: i32 = 0;
            while (row < size) : (row += 1) {
                const dist = if (row < mid) mid - row else row - mid;
                const w = size - dist * 2;
                if (w > 0) logical.fillRect(.{ .x = x + dist, .y = y + row, .w = w, .h = 1 }, c);
            }
        },
        .arch => {
            widgets.drawCircleButton(logical, x + @divTrunc(size, 2), y + @divTrunc(size, 2), @divTrunc(size, 2), c);
            logical.fillRect(.{ .x = x, .y = y + @divTrunc(size, 2), .w = size, .h = @divTrunc(size, 2) }, c);
        },
        .clam => {
            widgets.fillRoundRect(logical, .{ .x = x, .y = y + @divTrunc(size, 3), .w = size, .h = @divTrunc(size * 2, 3) }, tokens.Shape.xl, c);
            widgets.drawCircleButton(logical, x + @divTrunc(size, 2), y + @divTrunc(size, 3), @divTrunc(size, 3), c);
        },
        .soft_burst => {
            widgets.drawCircleButton(logical, x + @divTrunc(size, 2), y + @divTrunc(size, 2), @divTrunc(size, 2), c);
            var i: i32 = 0;
            while (i < 6) : (i += 1) {
                const ang = @as(f32, @floatFromInt(i)) / 6.0 * std.math.pi * 2.0;
                const px = x + @divTrunc(size, 2) + @as(i32, @intFromFloat(@cos(ang) * @as(f32, @floatFromInt(@divTrunc(size, 2)))));
                const py = y + @divTrunc(size, 2) + @as(i32, @intFromFloat(@sin(ang) * @as(f32, @floatFromInt(@divTrunc(size, 2)))));
                widgets.drawCircleButton(logical, px, py, 6, c);
            }
        },
        .slanted => {
            var row: i32 = 0;
            while (row < size) : (row += 1) {
                const inset = @divTrunc(row * size, size * 4);
                logical.fillRect(.{ .x = x + inset, .y = y + row, .w = size - inset * 2, .h = 1 }, c);
            }
        },
    }
}

/// Menu surface with items (MD3 menu).
pub const menu_item_h: i32 = 44;
pub const menu_pad: i32 = 8;
pub const menu_max_visible: usize = 8;
/// MD3 menu min width (112dp). Cap keeps list-row anchors from stretching the popup.
pub const menu_min_w: i32 = 112;
pub const menu_max_w: i32 = 280;
const menu_label_inset: i32 = 20;

/// Intrinsic menu width from labels — not the full settings row width.
pub fn menuContentWidth(items: []const []const u8) i32 {
    var max_tw: i32 = 0;
    for (items) |lab| {
        max_tw = @max(max_tw, font.textWidthStr(lab, .body_m));
    }
    const raw = max_tw + menu_label_inset * 2;
    return @min(menu_max_w, @max(menu_min_w, raw));
}

/// Popup width for an anchor: content-sized; compact anchors may grow to fit labels.
pub fn menuPopupWidth(anchor_w: i32, items: []const []const u8) i32 {
    const content = menuContentWidth(items);
    // Wide list-row anchors (settings action rows) must not drive width.
    if (anchor_w > menu_max_w) return content;
    return @min(menu_max_w, @max(content, @min(anchor_w, menu_max_w)));
}

pub fn drawMenu(logical: *fb.LogicalFb, r: geom.Rect, items: []const []const u8, selected: usize, theme: tokens.Theme) void {
    drawMenuScrolled(logical, r, items, selected, 0, theme);
}

pub fn drawMenuScrolled(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    items: []const []const u8,
    selected: usize,
    first: usize,
    theme: tokens.Theme,
) void {
    // MD3 menu: Shape.menu (8dp), elevation 2.
    widgets.fillRoundRect(logical, r, tokens.Shape.menu, theme.elev(2));
    widgets.strokeRoundRect(logical, r, tokens.Shape.menu, theme.outline_variant, 1);
    var row: usize = 0;
    var i = first;
    while (i < items.len) : (i += 1) {
        const y = r.y + menu_pad + @as(i32, @intCast(row)) * menu_item_h;
        if (y + menu_item_h > r.y + r.h) break;
        if (i == selected) {
            widgets.fillRoundRect(logical, .{ .x = r.x + 8, .y = y, .w = r.w - 16, .h = menu_item_h - 4 }, tokens.Shape.xs, theme.secondary_container);
        }
        font.drawTextRole(logical, r.x + menu_label_inset, y + 12, items[i], if (i == selected) theme.on_secondary_container else theme.on_surface, .body_m);
        row += 1;
    }
    // Scroll affordance when more items below
    if (first + row < items.len) {
        widgets.drawChevronDown(logical, r.x + @divTrunc(r.w, 2), r.y + r.h - 10, 4, theme.on_surface_variant);
    }
    if (first > 0) {
        widgets.drawChevronUp(logical, r.x + @divTrunc(r.w, 2), r.y + 6, 4, theme.on_surface_variant);
    }
}

pub fn menuIndexAt(r: geom.Rect, first: usize, item_count: usize, y: i32) ?usize {
    if (y < r.y + menu_pad or y >= r.y + r.h) return null;
    const row: i32 = @divTrunc(y - r.y - menu_pad, menu_item_h);
    if (row < 0) return null;
    const idx = first + @as(usize, @intCast(row));
    if (idx >= item_count) return null;
    return idx;
}

test "menuIndexAt with scroll offset" {
    const r: geom.Rect = .{ .x = 10, .y = 100, .w = 200, .h = menu_pad * 2 + menu_item_h * 3 };
    try std.testing.expectEqual(@as(usize, 0), menuIndexAt(r, 0, 9, 100 + menu_pad + 2).?);
    try std.testing.expectEqual(@as(usize, 2), menuIndexAt(r, 0, 9, 100 + menu_pad + menu_item_h * 2 + 2).?);
    try std.testing.expectEqual(@as(usize, 5), menuIndexAt(r, 3, 9, 100 + menu_pad + menu_item_h * 2 + 2).?);
    try std.testing.expect(menuIndexAt(r, 0, 9, 50) == null);
}

test "menu popup width ignores fat list-row anchors" {
    const labs = [_][]const u8{ "Teal", "Amber", "Rose" };
    const fat_row: i32 = 900;
    const w = menuPopupWidth(fat_row, &labs);
    try std.testing.expect(w <= menu_max_w);
    try std.testing.expect(w >= menu_min_w);
    try std.testing.expect(w < fat_row / 2);
    // Compact anchor can grow to fit labels but stays capped.
    const compact = menuPopupWidth(80, &labs);
    try std.testing.expect(compact >= menu_min_w);
    try std.testing.expect(compact <= menu_max_w);
}

/// Ripple stand-in — expanding circle at press point (effects spring drives t 0..1).
pub fn drawRipple(logical: *fb.LogicalFb, cx: i32, cy: i32, max_r: i32, t: f32, theme: tokens.Theme) void {
    const u = std.math.clamp(t, 0, 1);
    const rad: i32 = @max(2, @as(i32, @intFromFloat(@as(f32, @floatFromInt(max_r)) * u)));
    const a: u8 = @intFromFloat(50.0 * (1.0 - u));
    var y: i32 = -rad;
    while (y <= rad) : (y += 1) {
        var x: i32 = -rad;
        while (x <= rad) : (x += 1) {
            if (x * x + y * y <= rad * rad) {
                logical.blendAt(cx + x, cy + y, theme.on_surface, a);
            }
        }
    }
}

pub fn drawCheckbox(logical: *fb.LogicalFb, x: i32, y: i32, checked: bool, theme: tokens.Theme) void {
    const box: geom.Rect = .{ .x = x, .y = y, .w = 24, .h = 24 };
    const rad = tokens.Shape.xs;
    if (checked) {
        widgets.fillRoundRect(logical, box, rad, theme.primary);
        // Simple check: two strokes on on_primary.
        var i: i32 = 0;
        while (i < 5) : (i += 1) {
            logical.put(x + 5 + i, y + 12 + @divTrunc(i, 2), theme.on_primary);
            logical.put(x + 5 + i, y + 13 + @divTrunc(i, 2), theme.on_primary);
        }
        i = 0;
        while (i < 9) : (i += 1) {
            logical.put(x + 9 + i, y + 14 - i, theme.on_primary);
            logical.put(x + 9 + i, y + 15 - i, theme.on_primary);
        }
    } else {
        widgets.fillRoundRect(logical, box, rad, theme.surface_container_highest);
        widgets.strokeRoundRect(logical, box, rad, theme.outline, 2);
    }
}

pub fn drawRadio(logical: *fb.LogicalFb, cx: i32, cy: i32, selected: bool, theme: tokens.Theme) void {
    const outer: geom.Rect = .{ .x = cx - 12, .y = cy - 12, .w = 24, .h = 24 };
    widgets.fillRoundRect(logical, outer, 12, theme.surface_container_highest);
    widgets.strokeRoundRect(logical, outer, 12, if (selected) theme.primary else theme.outline, if (selected) 2 else 2);
    if (selected) widgets.drawCircleButton(logical, cx, cy, 6, theme.primary);
}

pub fn drawTooltip(logical: *fb.LogicalFb, anchor_x: i32, anchor_y: i32, text: []const u8, theme: tokens.Theme) void {
    const tw = font.textWidthStr(text, .label_m);
    const pad: i32 = 12;
    const r: geom.Rect = .{
        .x = anchor_x - @divTrunc(tw, 2) - pad,
        .y = anchor_y - 40,
        .w = tw + pad * 2,
        .h = 32,
    };
    widgets.fillRoundRect(logical, r, tokens.Shape.xs, theme.inverse_surface);
    font.drawTextRole(logical, r.x + pad, r.y + 8, text, theme.inverse_on_surface, .label_m);
}

pub fn drawListItem(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    label: []const u8,
    selected: bool,
    theme: tokens.Theme,
) void {
    if (selected) {
        widgets.fillRoundRect(logical, .{ .x = r.x + 4, .y = r.y + 2, .w = r.w - 8, .h = r.h - 4 }, tokens.Shape.md, theme.secondary_container);
    }
    font.drawTextRole(logical, r.x + 56, r.y + @divTrunc(r.h - 16, 2), label, if (selected) theme.on_secondary_container else theme.on_surface, .body_l);
    widgets.drawChevronRight(logical, r.x + r.w - 24, r.y + @divTrunc(r.h, 2), 6, theme.on_surface_variant);
}

pub fn drawSlider(logical: *fb.LogicalFb, r: geom.Rect, value: f32, theme: tokens.Theme) void {
    widgets.drawSlider(logical, r, value, theme);
}

test "expressive fab paints" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.expressiveVibrantDark();
    logical.clear(theme.surface);
    drawFab(&logical, .{ .x = 40, .y = 40, .w = 56, .h = 56 }, theme);
    try std.testing.expect(logical.get(68, 68).toU16() != theme.surface.toU16());
}

test "linear progress stop and gap" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();
    logical.clear(theme.surface);
    const r: geom.Rect = .{ .x = 40, .y = 40, .w = 200, .h = linear_track_h };
    drawLinearProgress(&logical, r, 0.5, theme);
    try std.testing.expect(logical.get(50, 41).toU16() == theme.primary.toU16() or
        logical.get(50, 41).toU16() == theme.primary_container.toU16());
    try std.testing.expectEqual(theme.surface_container_highest.toU16(), logical.get(230, 41).toU16());
}

test "job progress bar indeterminate paints segment" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();
    logical.clear(theme.surface);
    const r: geom.Rect = .{ .x = 40, .y = 40, .w = 400, .h = linear_track_h };
    drawJobProgressBar(&logical, r, -1, 3.0, theme, theme.primary, theme.primary_container);
    var found = false;
    var x: i32 = 40;
    while (x < 440) : (x += 4) {
        const p = logical.get(x, 41).toU16();
        if (p == theme.primary.toU16() or p == theme.primary_container.toU16()) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}
