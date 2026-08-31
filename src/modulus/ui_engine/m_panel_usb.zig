//! M-Panel USB Drive — G-code file manager (active when USB host detects a device).

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const icons_phosphor = @import("icons_phosphor.zig");
const usb_volume = @import("usb_volume.zig");
const tool_chrome = @import("m_panel_tool.zig");

const card_w: i32 = 1180;
const card_h: i32 = 600;
const row_h: i32 = tokens.Logical.touch_min;
const row_gap: i32 = tokens.Space.sm;
const btn_size = tokens.ButtonSize.m;

pub const Ctx = struct {
    catalog: *const usb_volume.Catalog,
    usb_ready: bool = false,
    scroll_px: i32 = 0,
};

pub const Hit = enum {
    none,
    scrim,
    back,
    exit,
    row,
    view,
    load,
    rename,
    delete,
    eject,
};

pub const Layout = struct {
    header: tool_chrome.Header = .{},
    list_view: geom.Rect = .{},
    rows: [usb_volume.max_files]geom.Rect = [_]geom.Rect{.{}} ** usb_volume.max_files,
    row_n: u8 = 0,
    view: geom.Rect = .{},
    load: geom.Rect = .{},
    eject: geom.Rect = .{},
    rename: geom.Rect = .{},
    delete: geom.Rect = .{},
    scroll_max: i32 = 0,
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

fn contentH(row_n: u8) i32 {
    if (row_n == 0) return row_h;
    return @as(i32, @intCast(row_n)) * (row_h + row_gap) - row_gap;
}

pub fn scrollMax(row_n: u8, view_h: i32) i32 {
    return @max(0, contentH(row_n) - view_h);
}

fn paintRow(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    r: geom.Rect,
    name: []const u8,
    selected: bool,
) void {
    const fill = if (selected) theme.secondary_container else theme.surface_container_high;
    widgets.fillRoundRect(logical, r, tokens.Shape.md, fill);
    if (!selected) widgets.strokeRoundRect(logical, r, tokens.Shape.md, theme.outline_variant, 1);
    const fg = if (selected) theme.on_secondary_container else theme.on_surface;
    const hh = font.faceHeight(font.faceForRole(.body_m));
    icons_phosphor.draw(logical, r.x + tokens.Space.md, r.y + @divTrunc(r.h - icons_phosphor.size, 2), .usb, fg);
    font.drawTextRole(logical, r.x + tokens.Space.md + icons_phosphor.size + tokens.Space.sm, r.y + @divTrunc(r.h - hh, 2), name, fg, .body_m);
}

pub fn paint(logical: *fb.LogicalFb, theme: tokens.Theme, ctx: Ctx, enter_t: f32) Layout {
    widgets.fillScrim(logical, theme);
    const card = cardGeom(enter_t);
    widgets.fillRoundRect(logical, card, tokens.Shape.dialog, theme.elev(3));

    var lay: Layout = .{};
    lay.header = tool_chrome.headerChrome(card);
    tool_chrome.paintBackToPanel(logical, theme, lay.header.back);
    const title_x = lay.header.back.x + lay.header.back.w + tokens.Space.sm;
    tool_chrome.paintTitle(logical, theme, title_x, lay.header.back.y, "USB Drive");
    tool_chrome.paintExit(logical, theme, lay.header.exit);

    const pad = tokens.Space.lg;
    const footer_h = btn_size.height() + tokens.Space.md;
    const body_top = lay.header.back.y + lay.header.back.h + tokens.Space.md;
    lay.list_view = .{
        .x = card.x + pad,
        .y = body_top,
        .w = card.w - pad * 2,
        .h = card.y + card.h - pad - footer_h - body_top,
    };
    lay.row_n = ctx.catalog.count;
    lay.scroll_max = scrollMax(lay.row_n, lay.list_view.h);
    const scroll = std.math.clamp(ctx.scroll_px, 0, lay.scroll_max);

    // Clip the scrolling list only. NOT `defer` — defer releases at function
    // exit, which left the footer buttons below clipped away and invisible.
    logical.setClip(lay.list_view);

    if (!ctx.usb_ready) {
        font.drawTextRole(logical, lay.list_view.x + tokens.Space.sm, lay.list_view.y + tokens.Space.sm, "Insert a USB drive (Type-A host).", theme.on_surface_variant, .body_m);
    } else if (ctx.catalog.ejected) {
        font.drawTextRole(logical, lay.list_view.x + tokens.Space.sm, lay.list_view.y + tokens.Space.sm, "Ejected - safe to remove the drive.", theme.on_surface_variant, .body_m);
    } else if (lay.row_n == 0) {
        font.drawTextRole(logical, lay.list_view.x + tokens.Space.sm, lay.list_view.y + tokens.Space.sm, "No G-code files on drive.", theme.on_surface_variant, .body_m);
    } else {
        var i: u8 = 0;
        while (i < lay.row_n) : (i += 1) {
            const row_y = lay.list_view.y + @as(i32, @intCast(i)) * (row_h + row_gap) - scroll;
            const r: geom.Rect = .{ .x = lay.list_view.x, .y = row_y, .w = lay.list_view.w, .h = row_h };
            if (geom.Rect.intersect(r, lay.list_view).isEmpty()) {
                lay.rows[i] = .{};
            } else {
                lay.rows[i] = r;
                paintRow(logical, theme, r, ctx.catalog.nameSlice(i), i == ctx.catalog.selected);
            }
        }
    }

    const btn_y = card.y + card.h - pad - btn_size.height();
    logical.setClip(null); // footer sits below list_view — must be unclipped
    const del_w = btnWidth("Delete");
    const ren_w = btnWidth("Rename");
    const view_w = btnWidth("View");
    const eject_w = btnWidth("Safe eject");
    const load_w = btnWidth("Load");
    lay.delete = .{ .x = card.x + pad, .y = btn_y, .w = del_w, .h = btn_size.height() };
    lay.rename = .{ .x = lay.delete.x + del_w + tokens.Space.sm, .y = btn_y, .w = ren_w, .h = btn_size.height() };
    lay.view = .{ .x = lay.rename.x + ren_w + tokens.Space.sm, .y = btn_y, .w = view_w, .h = btn_size.height() };
    lay.load = .{ .x = card.x + card.w - pad - load_w, .y = btn_y, .w = load_w, .h = btn_size.height() };
    lay.eject = .{ .x = lay.load.x - tokens.Space.sm - eject_w, .y = btn_y, .w = eject_w, .h = btn_size.height() };

    const vol_ready = ctx.catalog.volumeReady(ctx.usb_ready);
    const has_sel = vol_ready and ctx.catalog.selected < ctx.catalog.count;
    if (vol_ready) {
        widgets.drawDangerTonalButton(logical, lay.delete, "Delete", theme);
        widgets.drawTonalButton(logical, lay.rename, "Rename", theme);
    } else {
        widgets.drawButton(logical, lay.delete, "Delete", .danger_tonal, .disabled, theme);
        widgets.drawButton(logical, lay.rename, "Rename", .tonal, .disabled, theme);
    }
    if (has_sel) {
        widgets.drawTonalButton(logical, lay.view, "View", theme);
        widgets.drawFilledButton(logical, lay.load, "Load", theme);
    } else {
        widgets.drawButton(logical, lay.view, "View", .tonal, .disabled, theme);
        widgets.drawButton(logical, lay.load, "Load", .filled, .disabled, theme);
    }
    const can_eject = ctx.usb_ready and !ctx.catalog.ejected;
    if (can_eject) {
        widgets.drawTonalButton(logical, lay.eject, "Safe eject", theme);
    } else {
        widgets.drawButton(logical, lay.eject, "Safe eject", .tonal, .disabled, theme);
    }
    return lay;
}

pub fn hit(layout: Layout, x: i32, y: i32) struct { kind: Hit, index: u8 } {
    if (tool_chrome.hitBack(layout.header, x, y)) return .{ .kind = .back, .index = 0 };
    if (tool_chrome.hitExit(layout.header, x, y)) return .{ .kind = .exit, .index = 0 };
    if (tool_chrome.hitScrim(layout.header, x, y)) return .{ .kind = .scrim, .index = 0 };
    if (layout.load.contains(x, y)) return .{ .kind = .load, .index = 0 };
    if (layout.view.contains(x, y)) return .{ .kind = .view, .index = 0 };
    if (layout.eject.contains(x, y)) return .{ .kind = .eject, .index = 0 };
    if (layout.delete.contains(x, y)) return .{ .kind = .delete, .index = 0 };
    if (layout.rename.contains(x, y)) return .{ .kind = .rename, .index = 0 };
    var i: u8 = 0;
    while (i < layout.row_n) : (i += 1) {
        if (!layout.rows[i].isEmpty() and layout.rows[i].contains(x, y)) return .{ .kind = .row, .index = i };
    }
    return .{ .kind = .none, .index = 0 };
}

test "usb layout actions meet touch_min" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    var cat: usb_volume.Catalog = .{};
    cat.refresh(true);
    const lay = paint(&logical, tokens.Theme.industrialTealDark(), .{ .catalog = &cat, .usb_ready = true, .scroll_px = 0 }, 1);
    try std.testing.expect(lay.load.h >= tokens.Logical.touch_min);
    try std.testing.expect(lay.view.h >= tokens.Logical.touch_min);
}

test "usb footer buttons do not overlap and sit below the list" {
    const t = std.testing;
    const gpa = t.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    var cat: usb_volume.Catalog = .{};
    cat.refresh(true);
    const lay = paint(&logical, tokens.Theme.industrialTealDark(), .{ .catalog = &cat, .usb_ready = true, .scroll_px = 0 }, 1);

    // Regression: `defer logical.setClip(null)` released the clip only at
    // function exit, so the whole footer was painted into the clipped-out
    // region and was invisible while still being tappable.
    const list_bottom = lay.list_view.y + lay.list_view.h;
    for ([_]geom.Rect{ lay.delete, lay.rename, lay.view, lay.eject, lay.load }) |b| {
        try t.expect(b.y >= list_bottom);
        try t.expect(b.w > 0 and b.h >= tokens.Logical.touch_min);
    }
    // Left group must not run into the right group.
    try t.expect(lay.view.x + lay.view.w < lay.eject.x);
    try t.expect(lay.eject.x + lay.eject.w < lay.load.x);
}
