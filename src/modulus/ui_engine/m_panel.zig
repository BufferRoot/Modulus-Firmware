//! M-Panel — MD3 launcher grid from the override FAB (5×2 viewport, scrollable).
//! Append one `tools` entry per feature; each opens its own full-screen tool window.

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const icons_phosphor = @import("icons_phosphor.zig");
const color = @import("color.zig");

pub const ToolId = enum(u8) {
    terminal = 0,
    usb = 1,
    probe = 2,
    sd = 3,
    zigbee = 4,
    c6_update = 5,
};

pub const Tool = struct {
    label: []const u8,
    icon: icons_phosphor.Id,
    requires_usb: bool = false,
};

/// ponytail: add one row per tool window as features land.
pub const tools = [_]Tool{
    .{ .label = "Terminal", .icon = .clipboard_text },
    .{ .label = "USB Drive", .icon = .usb, .requires_usb = true },
    .{ .label = "Probe", .icon = .arrow_down },
    .{ .label = "SD Card", .icon = .hard_drives },
    .{ .label = "Zigbee", .icon = .broadcast },
    .{ .label = "C6 Update", .icon = .cpu },
};

pub fn toolEnabled(index: u8, usb_host: bool) bool {
    if (index >= tools.len) return false;
    return !tools[index].requires_usb or usb_host;
}

pub const cols: i32 = 5;
pub const visible_rows: i32 = 2;
const icon_px: i32 = 32;
const tile_h: i32 = 88;
const gap: i32 = tokens.Space.sm;
const close_sz: i32 = tokens.Logical.touch_min;
const card_w: i32 = 1000;
const card_h: i32 = 400;
const title_h: i32 = tokens.Space.lg + 32;

pub const Hit = enum {
    none,
    scrim,
    close,
    tile,
};

pub const HitInfo = struct {
    kind: Hit = .none,
    /// Tool index when `kind == .tile`.
    index: u8 = 0,
};

pub const Layout = struct {
    card: geom.Rect = .{},
    close: geom.Rect = .{},
    view: geom.Rect = .{},
    tiles: [32]geom.Rect = [_]geom.Rect{.{}} ** 32,
    tile_n: u8 = 0,
    scroll_max: i32 = 0,
};

pub const ToolLayout = struct {
    card: geom.Rect = .{},
    back: geom.Rect = .{},
};

fn cardGeom(enter_t: f32) geom.Rect {
    const t = std.math.clamp(enter_t, 0, 1);
    const w: i32 = @intFromFloat(@as(f32, @floatFromInt(card_w)) * (0.88 + 0.12 * t));
    const h: i32 = @intFromFloat(@as(f32, @floatFromInt(card_h)) * (0.88 + 0.12 * t));
    return .{
        .x = @divTrunc(tokens.Logical.width - w, 2),
        .y = @divTrunc(tokens.Logical.height - h, 2),
        .w = w,
        .h = h,
    };
}

fn tileW(card: geom.Rect) i32 {
    const pad = tokens.Space.lg;
    const avail = card.w - pad * 2 - gap * (cols - 1);
    return @divTrunc(avail, cols);
}

fn rowCount() i32 {
    const n = tools.len;
    if (n == 0) return visible_rows;
    return @divTrunc(n + @as(usize, @intCast(cols)) - 1, @as(usize, @intCast(cols)));
}

pub fn contentH() i32 {
    return rowCount() * (tile_h + gap) - gap;
}

pub fn viewH(card: geom.Rect) i32 {
    return card.h - title_h - tokens.Space.md;
}

pub fn scrollMax(card: geom.Rect) i32 {
    return @max(0, contentH() - viewH(card));
}

fn tileRect(card: geom.Rect, col: i32, row: i32, scroll: i32) geom.Rect {
    const pad = tokens.Space.lg;
    const tw = tileW(card);
    const y0 = card.y + title_h;
    return .{
        .x = card.x + pad + col * (tw + gap),
        .y = y0 + row * (tile_h + gap) - scroll,
        .w = tw,
        .h = tile_h,
    };
}

/// MD3 expressive tint — warm left → cool right (reference launcher strip).
fn tileFill(theme: tokens.Theme, col: i32) color.Rgb565 {
    const t: u8 = @intFromFloat(@round(@as(f32, @floatFromInt(col)) / @as(f32, @floatFromInt(cols - 1)) * 255.0));
    return color.blendRgb565(theme.tertiary_container, theme.secondary_container, t);
}

fn paintClose(logical: *fb.LogicalFb, theme: tokens.Theme, r: geom.Rect) void {
    widgets.drawTonalCloseButton(logical, r, theme);
}

fn paintTile(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    icon: icons_phosphor.Id,
    label: []const u8,
    fill: color.Rgb565,
    theme: tokens.Theme,
    enabled: bool,
) void {
    widgets.fillRoundRect(logical, r, tokens.Shape.lg, if (enabled) fill else theme.surface_container_low);
    if (!enabled) widgets.strokeRoundRect(logical, r, tokens.Shape.lg, theme.outline_variant, 1);
    const ink = if (enabled) theme.on_surface else theme.on_surface_variant;
    icons_phosphor.draw(logical, r.x + @divTrunc(r.w - icon_px, 2), r.y + 14, icon, ink);
    if (label.len != 0) {
        const tw = font.textWidthStr(label, .label_m);
        font.drawTextRole(logical, r.x + @divTrunc(r.w - tw, 2), r.y + 52, label, ink, .label_m);
    }
}

fn paintEmptySlot(logical: *fb.LogicalFb, r: geom.Rect, theme: tokens.Theme) void {
    widgets.fillRoundRect(logical, r, tokens.Shape.lg, theme.surface_container_low);
    widgets.strokeRoundRect(logical, r, tokens.Shape.lg, theme.outline_variant, 1);
}

pub fn paint(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    scroll_px: i32,
    enter_t: f32,
    usb_host: bool,
) Layout {
    widgets.fillScrim(logical, theme);
    const card = cardGeom(enter_t);
    widgets.fillRoundRect(logical, card, tokens.Shape.dialog, theme.elev(3));

    var lay: Layout = .{ .card = card };
    const title_y = card.y + tokens.Space.md;
    font.drawTextRole(logical, card.x + tokens.Space.lg, title_y, "M-Panel", theme.on_surface, .title_l);
    const th = font.faceHeight(font.faceForRole(.title_l));
    lay.close = .{
        .x = card.x + card.w - close_sz - tokens.Space.md,
        .y = title_y + @divTrunc(th - close_sz, 2),
        .w = close_sz,
        .h = close_sz,
    };
    paintClose(logical, theme, lay.close);

    const y0 = card.y + title_h;
    lay.view = .{
        .x = card.x + tokens.Space.lg,
        .y = y0,
        .w = card.w - tokens.Space.lg * 2,
        .h = viewH(card),
    };
    lay.scroll_max = scrollMax(card);
    const scroll = std.math.clamp(scroll_px, 0, lay.scroll_max);

    logical.setClip(lay.view);
    defer logical.setClip(null);

    if (tools.len == 0) {
        var row: i32 = 0;
        while (row < visible_rows) : (row += 1) {
            var col: i32 = 0;
            while (col < cols) : (col += 1) {
                const r = tileRect(card, col, row, scroll);
                if (row == 0 and col == 2) {
                    const hint = "Tools appear here";
                    paintTile(logical, r, .cards_three, hint, theme.surface_container, theme, true);
                } else {
                    paintEmptySlot(logical, r, theme);
                }
            }
        }
        return lay;
    }

    var i: usize = 0;
    while (i < tools.len and lay.tile_n < lay.tiles.len) : (i += 1) {
        const row: i32 = @intCast(@divTrunc(i, @as(usize, @intCast(cols))));
        const col: i32 = @intCast(@rem(i, @as(usize, @intCast(cols))));
        const r = tileRect(card, col, row, scroll);
        lay.tiles[lay.tile_n] = r;
        lay.tile_n += 1;
        const tool = tools[i];
        const enabled = toolEnabled(@intCast(i), usb_host);
        paintTile(logical, r, tool.icon, tool.label, tileFill(theme, col), theme, enabled);
    }
    return lay;
}

pub fn hit(layout: Layout, x: i32, y: i32, usb_host: bool) HitInfo {
    if (layout.close.contains(x, y)) return .{ .kind = .close };
    if (!layout.card.contains(x, y)) return .{ .kind = .scrim };
    if (!layout.view.contains(x, y)) return .{ .kind = .none };
    var i: u8 = 0;
    while (i < layout.tile_n) : (i += 1) {
        if (layout.tiles[i].contains(x, y)) {
            if (!toolEnabled(i, usb_host)) return .{ .kind = .none };
            return .{ .kind = .tile, .index = i };
        }
    }
    return .{ .kind = .none };
}

fn toolCardGeom(enter_t: f32) geom.Rect {
    const t = std.math.clamp(enter_t, 0, 1);
    const base_h = card_h + 80;
    const w: i32 = @intFromFloat(@as(f32, @floatFromInt(card_w)) * (0.92 + 0.08 * t));
    const h: i32 = @intFromFloat(@as(f32, @floatFromInt(base_h)) * (0.92 + 0.08 * t));
    return .{
        .x = @divTrunc(tokens.Logical.width - w, 2),
        .y = @divTrunc(tokens.Logical.height - h, 2),
        .w = w,
        .h = h,
    };
}

pub fn paintTool(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    tool_index: usize,
    enter_t: f32,
) ToolLayout {
    widgets.fillScrim(logical, theme);
    const card2 = toolCardGeom(enter_t);
    widgets.fillRoundRect(logical, card2, tokens.Shape.dialog, theme.elev(3));

    var lay: ToolLayout = .{ .card = card2 };
    const title_y = card2.y + tokens.Space.md;
    const label = if (tool_index < tools.len) tools[tool_index].label else "Tool";
    lay.back = .{
        .x = card2.x + tokens.Space.md,
        .y = title_y,
        .w = close_sz,
        .h = close_sz,
    };
    widgets.drawTonalCloseButton(logical, lay.back, theme);
    font.drawTextRole(
        logical,
        card2.x + tokens.Space.lg + close_sz,
        title_y + @divTrunc(close_sz - font.faceHeight(font.faceForRole(.title_l)), 2),
        label,
        theme.on_surface,
        .title_l,
    );
    const body_y = title_y + close_sz + tokens.Space.lg;
    font.drawTextRole(
        logical,
        card2.x + tokens.Space.lg,
        body_y,
        "Tool window scaffold - add feature UI here.",
        theme.on_surface_variant,
        .body_m,
    );
    return lay;
}

pub fn hitTool(layout: ToolLayout, x: i32, y: i32) bool {
    return layout.back.contains(x, y) or !layout.card.contains(x, y);
}

test "m-panel grid is 5 columns" {
    const bounds: geom.Rect = .{ .x = 0, .y = 0, .w = card_w, .h = card_h };
    const tw = tileW(bounds);
    const r0 = tileRect(bounds, 0, 0, 0);
    const r1 = tileRect(bounds, 1, 0, 0);
    try std.testing.expectEqual(r0.w, tw);
    try std.testing.expectEqual(r1.x - r0.x, tw + gap);
}

test "scroll max grows with tools" {
    const card = cardGeom(1);
    try std.testing.expectEqual(@as(i32, 0), scrollMax(card));
}

test "hit tile index" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();
    const lay = paint(&logical, theme, 0, 1, true);
    if (lay.tile_n > 0) {
        const r = lay.tiles[0];
        const h = hit(lay, r.x + @divTrunc(r.w, 2), r.y + @divTrunc(r.h, 2), true);
        try std.testing.expect(h.kind == .tile);
        try std.testing.expectEqual(@as(u8, 0), h.index);
    }
}
