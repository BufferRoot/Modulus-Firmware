//! M-Panel SD Card — organized folder browser (logs, backups, macros, …).

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const icons_phosphor = @import("icons_phosphor.zig");
const sd_volume = @import("sd_volume.zig");
const tool_chrome = @import("m_panel_tool.zig");
const expr = @import("widgets_expressive.zig");

const card_w: i32 = 1180;
const card_h: i32 = 600;
const row_h: i32 = tokens.Logical.touch_min;
const row_gap: i32 = tokens.Space.sm;
const btn_size = tokens.ButtonSize.m;
const chip_h: i32 = tokens.Logical.touch_min;
const chip_gap: i32 = tokens.Space.xs;
const max_folder_cols: i32 = 3;
const min_chip_w: i32 = 220;
const cap_label = "Free space";
const footer_overflow_msg = "Some actions hidden - footer full";

/// Adaptive folder chip columns (2-3) from content width.
pub fn folderCols(content_w: i32) i32 {
    const cols = @divTrunc(content_w + chip_gap, min_chip_w + chip_gap);
    return @max(2, @min(max_folder_cols, cols));
}

fn folderRows(cols: i32) i32 {
    return @divTrunc(@as(i32, @intCast(sd_volume.folders.len)) + cols - 1, cols);
}

pub const Ctx = struct {
    catalog: *const sd_volume.Catalog,
    sd_mounted: bool = false,
    sd_failed: bool = false,
    capacity: []const u8 = "--",
    scroll_px: i32 = 0,
    /// Frame phase 0..1 — indeterminate bars (mount/format).
    anim_t: f32 = 0,
    busy: bool = false,
};

pub const Hit = enum {
    none,
    scrim,
    back,
    exit,
    folder,
    row,
    mount,
    format,
    backup,
    restore,
    export_log,
    clear_cache,
    delete,
};

pub const Layout = struct {
    header: tool_chrome.Header = .{},
    mount: geom.Rect = .{},
    folders: [sd_volume.folders.len]geom.Rect = [_]geom.Rect{.{}} ** sd_volume.folders.len,
    list_view: geom.Rect = .{},
    rows: [sd_volume.max_entries]geom.Rect = [_]geom.Rect{.{}} ** sd_volume.max_entries,
    row_n: u8 = 0,
    backup: geom.Rect = .{},
    restore: geom.Rect = .{},
    export_log: geom.Rect = .{},
    clear_cache: geom.Rect = .{},
    format: geom.Rect = .{},
    delete: geom.Rect = .{},
    scroll_max: i32 = 0,
    show_backup: bool = false,
    show_restore: bool = false,
    show_export_log: bool = false,
    show_clear_cache: bool = false,
    show_format: bool = false,
    folder_cols: u8 = 3,
    footer_overflow: bool = false,
};

pub const footer_overflow_message = footer_overflow_msg;

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

fn paintCapacity(logical: *fb.LogicalFb, theme: tokens.Theme, x: i32, y: i32, capacity: []const u8) i32 {
    const lh = tokens.TypeRole.label_m.lineHeight();
    const bh = tokens.TypeRole.body_l.lineHeight();
    const row = @max(lh, bh);
    const ty = y + @divTrunc(row - lh, 2);
    font.drawTextRole(logical, x, ty, cap_label, theme.on_surface_variant, .label_m);
    const lw = font.textWidthStr(cap_label, .label_m);
    const by = y + @divTrunc(row - bh, 2);
    font.drawTextRole(logical, x + lw + tokens.Space.sm, by, capacity, theme.on_surface, .body_l);
    return row;
}

fn paintRow(logical: *fb.LogicalFb, theme: tokens.Theme, r: geom.Rect, name: []const u8, selected: bool) void {
    const fill = if (selected) theme.secondary_container else theme.surface_container_high;
    widgets.fillRoundRect(logical, r, tokens.Shape.md, fill);
    if (!selected) widgets.strokeRoundRect(logical, r, tokens.Shape.md, theme.outline_variant, 1);
    const fg = if (selected) theme.on_secondary_container else theme.on_surface;
    const hh = font.faceHeight(font.faceForRole(.body_l));
    icons_phosphor.draw(logical, r.x + tokens.Space.md, r.y + @divTrunc(r.h - icons_phosphor.size, 2), .hard_drives, fg);
    font.drawTextRole(logical, r.x + tokens.Space.md + icons_phosphor.size + tokens.Space.sm, r.y + @divTrunc(r.h - hh, 2), name, fg, .body_l);
}

fn paintFolderChip(logical: *fb.LogicalFb, theme: tokens.Theme, r: geom.Rect, label: []const u8, active: bool) void {
    const fill = if (active) theme.secondary_container else theme.surface_container;
    widgets.fillRoundRect(logical, r, tokens.Shape.full, fill);
    if (!active) widgets.strokeRoundRect(logical, r, tokens.Shape.full, theme.outline_variant, 1);
    const fg = if (active) theme.on_secondary_container else theme.on_surface_variant;
    const tw = font.textWidthStr(label, .label_m);
    const th = font.faceHeight(font.faceForRole(.label_m));
    font.drawTextRole(logical, r.x + @divTrunc(r.w - tw, 2), r.y + @divTrunc(r.h - th, 2), label, fg, .label_m);
}

fn paintListChrome(logical: *fb.LogicalFb, theme: tokens.Theme, view: geom.Rect) void {
    widgets.fillRoundRect(logical, view, tokens.Shape.md, theme.surface_container_low);
    widgets.strokeRoundRect(logical, view, tokens.Shape.md, theme.outline_variant, 1);
}

fn paintBusyBar(logical: *fb.LogicalFb, theme: tokens.Theme, r: geom.Rect, anim_t: f32) void {
    const bar: geom.Rect = .{
        .x = r.x,
        .y = r.y + r.h - tokens.Space.md - tokens.Space.xs,
        .w = r.w,
        .h = tokens.Space.xs,
    };
    expr.drawLoadingIndicator(logical, bar, anim_t * 8.0, theme);
}

const FooterBtn = struct {
    label: []const u8,
    rect: geom.Rect = .{},
    kind: enum { delete, export_log, clear_cache, backup, restore, format },
    variant: enum { filled, tonal, danger_tonal, disabled_delete, disabled_tonal },
};

fn layoutFooter(
    card: geom.Rect,
    pad: i32,
    ctx: Ctx,
    lay: *Layout,
) [6]FooterBtn {
    const btn_y = card.y + card.h - pad - btn_size.height();
    const left = card.x + pad;
    const right = card.x + card.w - pad;
    const gap = tokens.Space.sm;
    const ready = ctx.catalog.volumeReady(ctx.sd_mounted);
    lay.footer_overflow = false;

    lay.show_backup = ready and ctx.catalog.folder == .backups;
    lay.show_restore = ready and ctx.catalog.folder == .backups;
    lay.show_export_log = ready and ctx.catalog.folder == .logs;
    lay.show_clear_cache = ready and ctx.catalog.folder == .cache;
    lay.show_format = ctx.sd_mounted;

    var specs: [6]FooterBtn = undefined;
    var spec_n: u8 = 0;

    var right_x = right;
    if (lay.show_format) {
        const w = btnWidth("Format");
        right_x -= w;
        specs[spec_n] = .{ .label = "Format", .kind = .format, .variant = .danger_tonal, .rect = .{ .x = right_x, .y = btn_y, .w = w, .h = btn_size.height() } };
        spec_n += 1;
        right_x -= gap;
    }
    if (lay.show_restore) {
        const w = btnWidth("Restore");
        right_x -= w;
        const can = ctx.catalog.selected < ctx.catalog.count;
        specs[spec_n] = .{
            .label = "Restore",
            .kind = .restore,
            .variant = if (can) .tonal else .disabled_tonal,
            .rect = .{ .x = right_x, .y = btn_y, .w = w, .h = btn_size.height() },
        };
        spec_n += 1;
        right_x -= gap;
    }
    const pack_limit = right_x;

    var x = left;
    const del_w = btnWidth("Delete");
    const del_on = ready and ctx.catalog.selected < ctx.catalog.count;
    specs[spec_n] = .{
        .label = "Delete",
        .kind = .delete,
        .variant = if (del_on) .danger_tonal else .disabled_delete,
        .rect = .{ .x = x, .y = btn_y, .w = del_w, .h = btn_size.height() },
    };
    spec_n += 1;
    x += del_w + gap;

    if (lay.show_export_log) {
        const w = btnWidth("Export log");
        if (x + w <= pack_limit) {
            specs[spec_n] = .{ .label = "Export log", .kind = .export_log, .variant = .tonal, .rect = .{ .x = x, .y = btn_y, .w = w, .h = btn_size.height() } };
            spec_n += 1;
            x += w + gap;
        } else {
            lay.show_export_log = false;
            lay.footer_overflow = true;
        }
    }
    if (lay.show_clear_cache) {
        const w = btnWidth("Clear cache");
        if (x + w <= pack_limit) {
            specs[spec_n] = .{ .label = "Clear cache", .kind = .clear_cache, .variant = .tonal, .rect = .{ .x = x, .y = btn_y, .w = w, .h = btn_size.height() } };
            spec_n += 1;
            x += w + gap;
        } else {
            lay.show_clear_cache = false;
            lay.footer_overflow = true;
        }
    }
    if (lay.show_backup) {
        const w = btnWidth("Backup");
        if (x + w <= pack_limit) {
            specs[spec_n] = .{ .label = "Backup", .kind = .backup, .variant = .filled, .rect = .{ .x = x, .y = btn_y, .w = w, .h = btn_size.height() } };
            spec_n += 1;
        } else {
            lay.show_backup = false;
            lay.footer_overflow = true;
        }
    }

    const empty: FooterBtn = .{ .label = "", .kind = .delete, .variant = .tonal };
    var out: [6]FooterBtn = [_]FooterBtn{empty} ** 6;
    var i: u8 = 0;
    while (i < spec_n) : (i += 1) out[i] = specs[i];
    return out;
}

fn paintFooterBtn(logical: *fb.LogicalFb, theme: tokens.Theme, b: FooterBtn) void {
    if (b.rect.isEmpty()) return;
    switch (b.variant) {
        .filled => widgets.drawFilledButton(logical, b.rect, b.label, theme),
        .tonal => widgets.drawTonalButton(logical, b.rect, b.label, theme),
        .danger_tonal => widgets.drawDangerTonalButton(logical, b.rect, b.label, theme),
        .disabled_delete => widgets.drawButton(logical, b.rect, b.label, .danger_tonal, .disabled, theme),
        .disabled_tonal => widgets.drawButton(logical, b.rect, b.label, .tonal, .disabled, theme),
    }
}

fn storeFooterRects(lay: *Layout, specs: *const [6]FooterBtn) void {
    const inline_format = lay.format;
    lay.delete = .{};
    lay.export_log = .{};
    lay.clear_cache = .{};
    lay.backup = .{};
    lay.restore = .{};
    lay.format = .{};
    for (specs.*) |b| {
        if (b.label.len == 0) break;
        switch (b.kind) {
            .delete => lay.delete = b.rect,
            .export_log => lay.export_log = b.rect,
            .clear_cache => lay.clear_cache = b.rect,
            .backup => lay.backup = b.rect,
            .restore => lay.restore = b.rect,
            .format => lay.format = b.rect,
        }
    }
    if (!inline_format.isEmpty() and lay.format.isEmpty()) lay.format = inline_format;
}

pub fn paint(logical: *fb.LogicalFb, theme: tokens.Theme, ctx: Ctx, enter_t: f32) Layout {
    widgets.fillScrim(logical, theme);
    const card = cardGeom(enter_t);
    widgets.fillRoundRect(logical, card, tokens.Shape.dialog, theme.elev(3));
    widgets.strokeRoundRect(logical, card, tokens.Shape.dialog, theme.outline_variant, 1);

    var lay: Layout = .{};
    lay.header = tool_chrome.headerChrome(card);
    tool_chrome.paintBackToPanel(logical, theme, lay.header.back);
    const title_x = lay.header.back.x + lay.header.back.w + tokens.Space.sm;
    tool_chrome.paintTitle(logical, theme, title_x, lay.header.back.y, "SD Card");
    tool_chrome.paintExit(logical, theme, lay.header.exit);

    const pad = tokens.Space.lg;
    const cap_y = lay.header.back.y + lay.header.back.h + tokens.Space.sm;
    const cap_h = paintCapacity(logical, theme, card.x + pad, cap_y, ctx.capacity);

    const content_w = card.w - pad * 2;
    const folder_top = cap_y + cap_h + tokens.Space.sm;
    const cols_i = folderCols(content_w);
    lay.folder_cols = @intCast(cols_i);
    const chip_w = @divTrunc(content_w - chip_gap * (cols_i - 1), cols_i);
    var fi: usize = 0;
    while (fi < sd_volume.folders.len) : (fi += 1) {
        const row = fi / @as(usize, @intCast(cols_i));
        const col = fi % @as(usize, @intCast(cols_i));
        lay.folders[fi] = .{
            .x = card.x + pad + @as(i32, @intCast(col)) * (chip_w + chip_gap),
            .y = folder_top + @as(i32, @intCast(row)) * (chip_h + chip_gap),
            .w = chip_w,
            .h = chip_h,
        };
        const active = @intFromEnum(ctx.catalog.folder) == fi;
        paintFolderChip(logical, theme, lay.folders[fi], sd_volume.folders[fi].label, active);
    }
    const folder_row_n = folderRows(cols_i);
    const folder_block_h = folder_row_n * chip_h + (folder_row_n - 1) * chip_gap;
    const div_y = folder_top + folder_block_h + tokens.Space.sm;
    logical.fillRect(.{ .x = card.x + pad, .y = div_y, .w = card.w - pad * 2, .h = 1 }, theme.outline_variant);

    const footer_h = btn_size.height() + tokens.Space.md;
    const body_top = div_y + tokens.Space.sm;
    lay.list_view = .{
        .x = card.x + pad,
        .y = body_top,
        .w = card.w - pad * 2,
        .h = card.y + card.h - pad - footer_h - body_top,
    };
    lay.row_n = ctx.catalog.count;
    lay.scroll_max = scrollMax(lay.row_n, lay.list_view.h);
    const scroll = std.math.clamp(ctx.scroll_px, 0, lay.scroll_max);

    paintListChrome(logical, theme, lay.list_view);
    logical.setClip(lay.list_view);
    // NOT defer — that releases at function exit, leaving the footer
    // controls below the list clipped away and invisible.

    if (!ctx.sd_mounted) {
        const hint: []const u8 = if (ctx.sd_failed)
            "Mount failed - card may need FAT32 format."
        else
            "Insert SD card and tap Mount.";
        const hint_c = if (ctx.sd_failed) theme.err else theme.on_surface_variant;
        font.drawTextRole(logical, lay.list_view.x + tokens.Space.sm, lay.list_view.y + tokens.Space.sm, hint, hint_c, .body_l);
        if (ctx.busy) paintBusyBar(logical, theme, lay.list_view, ctx.anim_t);

        const mount_label: []const u8 = if (ctx.busy) "Mounting..." else "Mount";
        const mw = btnWidth(mount_label);
        var total_w = mw;
        var fw: i32 = 0;
        if (ctx.sd_failed and !ctx.busy) {
            fw = btnWidth("Format");
            total_w += tokens.Space.sm + fw;
        }
        const start_x = lay.list_view.x + @divTrunc(lay.list_view.w - total_w, 2);
        const mount_y = lay.list_view.y + lay.list_view.h - row_h - tokens.Space.md;
        lay.mount = .{ .x = start_x, .y = mount_y, .w = mw, .h = row_h };
        if (ctx.busy) {
            widgets.drawButton(logical, lay.mount, mount_label, .filled, .disabled, theme);
        } else {
            widgets.drawFilledButton(logical, lay.mount, mount_label, theme);
        }
        if (ctx.sd_failed and !ctx.busy) {
            lay.format = .{ .x = start_x + mw + tokens.Space.sm, .y = mount_y, .w = fw, .h = row_h };
            widgets.drawDangerTonalButton(logical, lay.format, "Format", theme);
        }
    } else if (lay.row_n == 0) {
        font.drawTextRole(logical, lay.list_view.x + tokens.Space.sm, lay.list_view.y + tokens.Space.sm, "Folder empty.", theme.on_surface_variant, .body_l);
        if (ctx.busy) paintBusyBar(logical, theme, lay.list_view, ctx.anim_t);
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
        if (ctx.busy) paintBusyBar(logical, theme, lay.list_view, ctx.anim_t);
    }

    logical.setClip(null); // footer sits below list_view — must be unclipped
    const footer_specs = layoutFooter(card, pad, ctx, &lay);
    storeFooterRects(&lay, &footer_specs);
    for (footer_specs) |b| {
        if (b.label.len == 0) break;
        paintFooterBtn(logical, theme, b);
    }
    return lay;
}

pub fn hit(layout: Layout, x: i32, y: i32) struct { kind: Hit, index: u8 } {
    if (tool_chrome.hitBack(layout.header, x, y)) return .{ .kind = .back, .index = 0 };
    if (tool_chrome.hitExit(layout.header, x, y)) return .{ .kind = .exit, .index = 0 };
    if (tool_chrome.hitScrim(layout.header, x, y)) return .{ .kind = .scrim, .index = 0 };
    if (!layout.mount.isEmpty() and layout.mount.contains(x, y)) return .{ .kind = .mount, .index = 0 };
    if (!layout.format.isEmpty() and layout.format.contains(x, y)) return .{ .kind = .format, .index = 0 };
    var fi: u8 = 0;
    while (fi < sd_volume.folders.len) : (fi += 1) {
        if (layout.folders[fi].contains(x, y)) return .{ .kind = .folder, .index = fi };
    }
    if (!layout.backup.isEmpty() and layout.backup.contains(x, y)) return .{ .kind = .backup, .index = 0 };
    if (!layout.restore.isEmpty() and layout.restore.contains(x, y)) return .{ .kind = .restore, .index = 0 };
    if (!layout.export_log.isEmpty() and layout.export_log.contains(x, y)) return .{ .kind = .export_log, .index = 0 };
    if (!layout.clear_cache.isEmpty() and layout.clear_cache.contains(x, y)) return .{ .kind = .clear_cache, .index = 0 };
    if (!layout.delete.isEmpty() and layout.delete.contains(x, y)) return .{ .kind = .delete, .index = 0 };
    var i: u8 = 0;
    while (i < layout.row_n) : (i += 1) {
        if (!layout.rows[i].isEmpty() and layout.rows[i].contains(x, y)) return .{ .kind = .row, .index = i };
    }
    return .{ .kind = .none, .index = 0 };
}

test "sd panel controls meet touch_min" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    var cat: sd_volume.Catalog = .{};
    cat.refresh(true);
    const lay = paint(&logical, tokens.Theme.industrialTealDark(), .{
        .catalog = &cat,
        .sd_mounted = true,
        .capacity = "14 GB free",
        .scroll_px = 0,
    }, 1);
    try std.testing.expect(lay.header.exit.w >= tokens.Logical.touch_min);
    try std.testing.expect(lay.folders[0].h >= tokens.Logical.touch_min);
    try std.testing.expect(lay.delete.h >= tokens.Logical.touch_min);
    try std.testing.expect(lay.backup.h >= tokens.Logical.touch_min);
}

test "sd footer packs without overlapping restore" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    var cat: sd_volume.Catalog = .{};
    cat.folder = .backups;
    cat.refresh(true);
    const lay = paint(&logical, tokens.Theme.industrialTealDark(), .{
        .catalog = &cat,
        .sd_mounted = true,
        .capacity = "14 GB free",
        .scroll_px = 0,
    }, 1);
    if (!lay.restore.isEmpty() and !lay.delete.isEmpty()) {
        try std.testing.expect(lay.delete.x + lay.delete.w + tokens.Space.sm <= lay.restore.x);
    }
}

test "sd folder cols adapt to width" {
    try std.testing.expectEqual(@as(i32, 3), folderCols(1132));
    try std.testing.expectEqual(@as(i32, 2), folderCols(500));
}

test "sd list viewport has height when mounted" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    var cat: sd_volume.Catalog = .{};
    cat.refresh(true);
    const lay = paint(&logical, tokens.Theme.industrialTealDark(), .{
        .catalog = &cat,
        .sd_mounted = true,
        .capacity = "14 GB free",
        .scroll_px = 0,
    }, 1);
    try std.testing.expect(lay.list_view.h > 0);
    try std.testing.expectEqual(@as(u8, 3), lay.folder_cols);
}

test "sd mount failed shows inline format" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    var cat: sd_volume.Catalog = .{};
    const lay = paint(&logical, tokens.Theme.industrialTealDark(), .{
        .catalog = &cat,
        .sd_failed = true,
        .capacity = "--",
        .scroll_px = 0,
    }, 1);
    try std.testing.expect(!lay.mount.isEmpty());
    try std.testing.expect(!lay.format.isEmpty());
    try std.testing.expect(lay.format.h >= tokens.Logical.touch_min);
}
