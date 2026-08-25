//! Bitmap text via baked Noto Sans A8 cells (+ optional 8x8 fallback).
//! System-wide MD3 font size: `setUserScale` shifts TypeRole → Face mapping.

const color = @import("color.zig");
const fb = @import("fb.zig");
const noto = @import("font_noto.zig");
const tokens = @import("tokens.zig");

pub const Face = noto.Face;

/// 0=Small 1=Default 2=Large 3=Largest (Android / MD3 accessibility style).
var g_user_scale: u8 = 1;

pub fn setUserScale(scale: u8) void {
    g_user_scale = @min(scale, 3);
}

pub fn userScale() u8 {
    return g_user_scale;
}

fn sizeTier(face: Face) u8 {
    return switch (face) {
        .ui14, .ui14m => 0,
        .ui16, .ui16b => 1,
        .ui22 => 2,
        .ui28 => 3,
        .ui36 => 4,
        .dro40 => 5,
    };
}

fn faceAtTier(tier: i32) Face {
    return switch (@max(0, @min(5, tier))) {
        0 => .ui14,
        1 => .ui16,
        2 => .ui22,
        3 => .ui28,
        4 => .ui36,
        else => .dro40,
    };
}

fn applyUserScale(base: Face) Face {
    const delta: i32 = switch (g_user_scale) {
        0 => -1,
        2 => 1,
        3 => 2,
        else => 0,
    };
    return faceAtTier(@as(i32, sizeTier(base)) + delta);
}

pub fn faceForRole(role: tokens.TypeRole) Face {
    // Size from MD3 role; emph picks Medium/Bold bake at same px (not size bump / double-stroke).
    const base: Face = switch (role) {
        .display_l, .emph_display_l => .dro40,
        .display_m, .emph_display_m => .ui36,
        // DISPLAY_S = Montserrat 24 → closest bake ui22; HEADLINE_L/M = 28/22.
        .display_s, .emph_display_s => .ui22,
        .headline_l, .emph_headline_l => .ui28,
        .headline_m, .emph_headline_m => .ui22,
        .headline_s, .emph_headline_s, .title_l, .emph_title_l, .title_m, .emph_title_m => .ui22,
        .title_s, .emph_title_s, .body_l, .emph_body_l, .body_m, .emph_body_m, .label_l, .emph_label_l => .ui16,
        .body_s, .emph_body_s, .label_m, .emph_label_m, .label_s, .emph_label_s => .ui14,
    };
    const scaled = applyUserScale(base);
    if (!role.emphasized()) return scaled;
    return switch (scaled) {
        .ui14 => .ui14m,
        .ui16 => .ui16b,
        .ui14m, .ui16b, .ui22, .ui28, .ui36, .dro40 => scaled,
    };
}

pub fn drawTextFaceTracked(
    logical: *fb.LogicalFb,
    x: i32,
    y: i32,
    text: []const u8,
    fg: color.Rgb565,
    face: Face,
    tracking: i32,
    bold: bool,
) void {
    var cx = x;
    var cy = y;
    const lh = faceHeight(face);
    for (text) |ch| {
        if (ch == '\n') {
            cx = x;
            cy += lh;
            continue;
        }
        drawCharFace(logical, cx, cy, ch, fg, face);
        if (bold) drawCharFace(logical, cx + 1, cy, ch, fg, face);
        cx += @as(i32, noto.advanceOf(face, ch)) + tracking;
    }
}

pub fn drawTextRole(
    logical: *fb.LogicalFb,
    x: i32,
    y: i32,
    text: []const u8,
    fg: color.Rgb565,
    role: tokens.TypeRole,
) void {
    drawTextFaceTracked(
        logical,
        x,
        y,
        text,
        fg,
        faceForRole(role),
        role.trackingPx(),
        role.boldPass(),
    );
}

pub fn drawTextRoleTracked(
    logical: *fb.LogicalFb,
    x: i32,
    y: i32,
    text: []const u8,
    fg: color.Rgb565,
    role: tokens.TypeRole,
    tracking: i32,
    bold: bool,
) void {
    drawTextFaceTracked(logical, x, y, text, fg, faceForRole(role), tracking, bold);
}

/// Widest line (newline-separated). Used for centering / fit checks.
pub fn textWidthStr(text: []const u8, role: tokens.TypeRole) i32 {
    const face = faceForRole(role);
    const track = role.trackingPx();
    var max_w: i32 = 0;
    var line_w: i32 = 0;
    for (text) |ch| {
        if (ch == '\n') {
            max_w = @max(max_w, line_w);
            line_w = 0;
            continue;
        }
        line_w += @as(i32, noto.advanceOf(face, ch)) + track;
    }
    max_w = @max(max_w, line_w);
    if (role.boldPass() and text.len > 0) max_w += 1;
    return max_w;
}

pub fn textLineCount(text: []const u8) u8 {
    if (text.len == 0) return 0;
    var n: u8 = 1;
    for (text) |ch| {
        if (ch == '\n') n +|= 1;
    }
    return n;
}

pub fn textBlockHeight(text: []const u8, role: tokens.TypeRole) i32 {
    const n = textLineCount(text);
    if (n == 0) return 0;
    const lh = faceHeight(faceForRole(role));
    return @as(i32, n) * lh;
}

pub fn drawCharFace(logical: *fb.LogicalFb, x: i32, y: i32, ch: u8, fg: color.Rgb565, face: Face) void {
    if (ch < noto.first_code or ch > noto.last_code) return;
    const sz = noto.cellSize(face);
    const atlas = noto.atlasPtr(face);
    const gi: usize = ch - noto.first_code;
    const cell = @as(usize, sz.w) * @as(usize, sz.h);
    const base = gi * cell;
    var row: u8 = 0;
    while (row < sz.h) : (row += 1) {
        var col: u8 = 0;
        while (col < sz.w) : (col += 1) {
            const a = atlas[base + @as(usize, row) * @as(usize, sz.w) + @as(usize, col)];
            if (a == 0) continue;
            const px = x + @as(i32, col);
            const py = y + @as(i32, row);
            if (a >= 240) {
                logical.put(px, py, fg);
            } else {
                logical.blendAt(px, py, fg, a);
            }
        }
    }
}

pub fn drawTextFace(logical: *fb.LogicalFb, x: i32, y: i32, text: []const u8, fg: color.Rgb565, face: Face) void {
    var cx = x;
    for (text) |ch| {
        if (ch == '\n') {
            cx = x;
            continue;
        }
        drawCharFace(logical, cx, y, ch, fg, face);
        cx += @as(i32, noto.advanceOf(face, ch));
    }
}

pub fn textWidthFace(text: []const u8, face: Face) i32 {
    var w: i32 = 0;
    for (text) |ch| {
        if (ch == '\n') continue;
        w += @as(i32, noto.advanceOf(face, ch));
    }
    return w;
}

pub fn faceHeight(face: Face) i32 {
    return noto.cellSize(face).h;
}

/// Legacy scale API — maps to nearest Noto face (ignores scale).
pub fn drawChar(logical: *fb.LogicalFb, x: i32, y: i32, ch: u8, fg: color.Rgb565, scale: u8) void {
    _ = scale;
    drawCharFace(logical, x, y, ch, fg, .ui14);
}

pub fn drawText(logical: *fb.LogicalFb, x: i32, y: i32, text: []const u8, fg: color.Rgb565, scale: u8) void {
    const face: Face = if (scale >= 3) .ui22 else if (scale >= 2) .ui16 else .ui14;
    drawTextFace(logical, x, y, text, fg, face);
}

pub fn drawTextGap(
    logical: *fb.LogicalFb,
    x: i32,
    y: i32,
    text: []const u8,
    fg: color.Rgb565,
    scale: u8,
    gap: i32,
) void {
    _ = gap;
    drawText(logical, x, y, text, fg, scale);
}

pub fn textWidth(len: usize, scale: u8) i32 {
    // Approximate for layout that only knows length (chips etc.)
    const face: Face = if (scale >= 3) .ui22 else if (scale >= 2) .ui16 else .ui14;
    const avg: i32 = @divTrunc(@as(i32, noto.cellSize(face).w) * 3, 4);
    return @as(i32, @intCast(len)) * avg;
}

pub fn textWidthRole(len: usize, role: tokens.TypeRole) i32 {
    const face = faceForRole(role);
    const avg: i32 = @divTrunc(@as(i32, noto.cellSize(face).w) * 3, 4);
    return @as(i32, @intCast(len)) * avg;
}

/// DRO digits — Noto Medium 40px.
pub fn drawDro(logical: *fb.LogicalFb, x: i32, y: i32, text: []const u8, fg: color.Rgb565, scale: u8) void {
    _ = scale;
    drawTextFace(logical, x, y, text, fg, .dro40);
}

pub fn droWidth(len: usize, scale: u8) i32 {
    _ = scale;
    // Approximate; prefer droWidthStr when string known.
    return @as(i32, @intCast(len)) * @as(i32, noto.dro40_advance[0]);
}

pub fn droWidthStr(text: []const u8) i32 {
    return textWidthFace(text, .dro40);
}

pub fn droHeight(scale: u8) i32 {
    _ = scale;
    return noto.dro40_cell_h;
}

test "noto draws glyph" {
    const std = @import("std");
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const fg = color.Rgb565.fromHex(0xFFFFFF);
    drawTextFace(&logical, 10, 10, "A", fg, .ui16);
    var found = false;
    var yy: i32 = 10;
    while (yy < 40) : (yy += 1) {
        var xx: i32 = 10;
        while (xx < 40) : (xx += 1) {
            if (logical.get(xx, yy).toU16() == fg.toU16()) found = true;
        }
    }
    try std.testing.expect(found);
}

test "proportional advances not monospace" {
    const std = @import("std");
    const adv_i = noto.advanceOf(.ui14, 'i');
    const adv_w = noto.advanceOf(.ui14, 'W');
    try std.testing.expect(adv_i < adv_w);
    // Width is sum of advances (left-aligned bake), not cell_w * len.
    try std.testing.expectEqual(
        @as(i32, adv_i) + adv_w,
        textWidthFace("iW", .ui14),
    );
    try std.testing.expect(textWidthFace("iW", .ui14) < @as(i32, noto.ui14_cell_w) * 2);
}

test "user font scale bumps TypeRole faces" {
    const std = @import("std");
    setUserScale(1);
    try std.testing.expectEqual(Face.ui14, faceForRole(.body_s));
    try std.testing.expectEqual(Face.ui16, faceForRole(.body_m));
    setUserScale(0);
    try std.testing.expectEqual(Face.ui14, faceForRole(.body_m)); // small: ui16 -> ui14
    setUserScale(2);
    try std.testing.expectEqual(Face.ui16, faceForRole(.body_s)); // large: ui14 -> ui16
    setUserScale(3);
    try std.testing.expectEqual(Face.ui22, faceForRole(.body_s)); // largest: ui14 -> ui22
    setUserScale(1); // restore default for other tests
}

test "dro digits render" {
    const std = @import("std");
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const fg = color.Rgb565.fromHex(0xFFFFFF);
    drawDro(&logical, 8, 8, "-910.585", fg, 1);
    var found = false;
    var yy: i32 = 8;
    while (yy < 8 + droHeight(1)) : (yy += 1) {
        var xx: i32 = 8;
        while (xx < 8 + droWidthStr("-910.585")) : (xx += 1) {
            if (logical.get(xx, yy).toU16() != 0) found = true;
        }
    }
    try std.testing.expect(found);
}
