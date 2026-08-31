//! M-Panel Probe — Z-plate probe (`settings_extra_modals.probe` parity).

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const tool_chrome = @import("m_panel_tool.zig");

const card_w: i32 = 1180;
const card_h: i32 = 600;
const field_h: i32 = tokens.Logical.touch_min;
const btn_size = tokens.ButtonSize.m;

pub const Ctx = struct {
    plate_mm: []const u8 = "1.0",
    busy: bool = false,
    plate_focused: bool = false,
};

pub const Hit = enum {
    none,
    scrim,
    back,
    exit,
    plate,
    start,
};

pub const Layout = struct {
    header: tool_chrome.Header = .{},
    plate: geom.Rect = .{},
    start: geom.Rect = .{},
};

fn cardGeom(enter_t: f32) geom.Rect {
    const t = std.math.clamp(enter_t, 0, 1);
    const w: i32 = @intFromFloat(@as(f32, @floatFromInt(card_w)) * (0.92 + 0.08 * t));
    const h: i32 = @intFromFloat(@as(f32, @floatFromInt(card_h)) * (0.92 + 0.08 * t));
    return .{
        .x = @divTrunc(tokens.Logical.width - w, 2),
        .y = @divTrunc(tokens.Logical.height - h, 2),
        .w = w,
        .h = h,
    };
}

fn btnWidth(label: []const u8) i32 {
    const tw = font.textWidthStr(label, .label_l);
    return @max(tokens.Logical.touch_min, tw + btn_size.padX() * 2);
}

pub fn paint(logical: *fb.LogicalFb, theme: tokens.Theme, ctx: Ctx, enter_t: f32) Layout {
    widgets.fillScrim(logical, theme);
    const card = cardGeom(enter_t);
    widgets.fillRoundRect(logical, card, tokens.Shape.dialog, theme.elev(3));

    var lay: Layout = .{};
    lay.header = tool_chrome.headerChrome(card);
    tool_chrome.paintBackToPanel(logical, theme, lay.header.back);
    const title_x = lay.header.back.x + lay.header.back.w + tokens.Space.sm;
    tool_chrome.paintTitle(logical, theme, title_x, lay.header.back.y, "Probe");
    tool_chrome.paintExit(logical, theme, lay.header.exit);

    const pad = tokens.Space.lg;
    const body_top = lay.header.back.y + lay.header.back.h + tokens.Space.lg;
    const x = card.x + pad;
    const row_w = card.w - pad * 2;

    font.drawTextRole(logical, x, body_top, "Z-plate thickness and probe cycle.", theme.on_surface_variant, .body_m);
    var y = body_top + font.faceHeight(font.faceForRole(.body_m)) + tokens.Space.lg;

    font.drawTextRole(logical, x, y, "Plate thickness", theme.on_surface_variant, .label_m);
    y += font.faceHeight(font.faceForRole(.label_m)) + tokens.Space.xs;
    lay.plate = .{ .x = x, .y = y, .w = row_w, .h = field_h };
    widgets.drawOutlinedTextField(
        logical,
        lay.plate,
        ctx.plate_mm,
        "e.g. 1.0 mm",
        false,
        ctx.plate_focused,
        false,
        theme,
    );
    y += field_h + tokens.Space.lg;

    font.drawTextRole(logical, x, y, "Status", theme.on_surface_variant, .label_m);
    y += font.faceHeight(font.faceForRole(.label_m)) + tokens.Space.xs;
    const status: []const u8 = if (ctx.busy) "Probing plate..." else "Ready";
    const status_c = if (ctx.busy) theme.primary else theme.on_surface;
    font.drawTextRole(logical, x, y, status, status_c, .body_m);

    const btn_y = card.y + card.h - pad - btn_size.height();
    const start_w = btnWidth(if (ctx.busy) "Busy" else "Start probe");
    lay.start = .{ .x = card.x + card.w - pad - start_w, .y = btn_y, .w = start_w, .h = btn_size.height() };
    if (ctx.busy) {
        widgets.drawButton(logical, lay.start, "Busy", .filled, .disabled, theme);
    } else {
        widgets.drawFilledButton(logical, lay.start, "Start probe", theme);
    }
    return lay;
}

pub fn hit(layout: Layout, x: i32, y: i32) Hit {
    if (tool_chrome.hitBack(layout.header, x, y)) return .back;
    if (tool_chrome.hitExit(layout.header, x, y)) return .exit;
    if (tool_chrome.hitScrim(layout.header, x, y)) return .scrim;
    if (layout.start.contains(x, y)) return .start;
    if (layout.plate.contains(x, y)) return .plate;
    return .none;
}

test "probe controls meet touch_min" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const lay = paint(&logical, tokens.Theme.industrialTealDark(), .{ .plate_mm = "1.0" }, 1);
    try std.testing.expect(lay.plate.h >= tokens.Logical.touch_min);
    try std.testing.expect(lay.start.h >= tokens.Logical.touch_min);
    try std.testing.expect(lay.header.exit.w >= tokens.Logical.touch_min);
}
