//! Shared M-Panel tool chrome — back to grid + exit to dashboard.

const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");

pub const back_label = "M-Panel";
pub const exit_sz: i32 = tokens.Logical.touch_min;

pub const Header = struct {
    card: geom.Rect = .{},
    back: geom.Rect = .{},
    exit: geom.Rect = .{},
};

pub fn backWidth() i32 {
    const tw = font.textWidthStr(back_label, .label_l);
    return @max(tokens.Logical.touch_min, tw + tokens.Space.md * 2 + 16);
}

/// Tonal back control — returns to M-Panel grid (not dashboard).
pub fn paintBackToPanel(logical: *fb.LogicalFb, theme: tokens.Theme, r: geom.Rect) void {
    widgets.fillRoundRect(logical, r, tokens.Shape.full, theme.surface_container);
    const hh = font.faceHeight(font.faceForRole(.label_l));
    const y = r.y + @divTrunc(r.h - hh, 2);
    font.drawTextRole(logical, r.x + tokens.Space.sm, y, "<", theme.on_surface, .label_l);
    font.drawTextRole(logical, r.x + tokens.Space.sm + 14, y, back_label, theme.on_surface, .label_l);
}

pub fn paintExit(logical: *fb.LogicalFb, theme: tokens.Theme, r: geom.Rect) void {
    widgets.drawTonalCloseButton(logical, r, theme);
}

pub fn paintTitle(logical: *fb.LogicalFb, theme: tokens.Theme, x: i32, y: i32, title: []const u8) void {
    const th = font.faceHeight(font.faceForRole(.title_l));
    font.drawTextRole(logical, x, y + @divTrunc(tokens.Logical.touch_min - th, 2), title, theme.on_surface, .title_l);
}

pub fn headerChrome(card: geom.Rect) Header {
    const title_y = card.y + tokens.Space.md;
    const bw = backWidth();
    const th = font.faceHeight(font.faceForRole(.title_l));
    return .{
        .card = card,
        .back = .{
            .x = card.x + tokens.Space.md,
            .y = title_y,
            .w = bw,
            .h = tokens.Logical.touch_min,
        },
        .exit = .{
            .x = card.x + card.w - exit_sz - tokens.Space.md,
            .y = title_y + @divTrunc(th - exit_sz, 2),
            .w = exit_sz,
            .h = exit_sz,
        },
    };
}

pub fn headerBack(card: geom.Rect, _: []const u8) Header {
    return headerChrome(card);
}

pub fn hitBack(h: Header, x: i32, y: i32) bool {
    return h.back.contains(x, y);
}

pub fn hitExit(h: Header, x: i32, y: i32) bool {
    return h.exit.contains(x, y);
}

pub fn hitScrim(h: Header, x: i32, y: i32) bool {
    return !h.card.contains(x, y);
}

test "tool chrome meets touch_min" {
    const card: geom.Rect = .{ .x = 50, .y = 60, .w = 1180, .h = 600 };
    const h = headerChrome(card);
    try std.testing.expect(backWidth() >= tokens.Logical.touch_min);
    try std.testing.expect(h.exit.w >= tokens.Logical.touch_min);
    try std.testing.expect(h.exit.h >= tokens.Logical.touch_min);
}

const std = @import("std");
