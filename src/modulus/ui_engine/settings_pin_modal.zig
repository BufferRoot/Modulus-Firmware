//! Security PIN overlays — Set/Change (dual field) + Clear (LVGL + MD3).

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");

pub const Kind = enum { none, set, clear };

pub const Hit = enum { none, close, cancel, save, field1, field2 };

pub const Layout = struct {
    card: geom.Rect = .{},
    close: geom.Rect = .{},
    cancel: geom.Rect = .{},
    save: geom.Rect = .{},
    field1: geom.Rect = .{},
    field2: geom.Rect = .{},
};

const close_sz: i32 = tokens.Logical.touch_min;
const hit_h: i32 = tokens.Logical.touch_min;
const btn_size = tokens.ButtonSize.m;

fn paintCloseIconBtn(logical: *fb.LogicalFb, theme: tokens.Theme, r: geom.Rect) void {
    widgets.drawTonalCloseButton(logical, r, theme);
}

fn btnWidth(label: []const u8) i32 {
    const tw = font.textWidthStr(label, .label_l);
    return @max(tokens.Logical.touch_min, tw + btn_size.padX() * 2);
}

fn cardGeom(w0: i32, h0: i32, enter_t: f32) geom.Rect {
    const t = std.math.clamp(enter_t, 0, 1);
    const card_w: i32 = @intFromFloat(@as(f32, @floatFromInt(w0)) * (0.88 + 0.12 * t));
    const card_h: i32 = @intFromFloat(@as(f32, @floatFromInt(h0)) * (0.88 + 0.12 * t));
    return .{
        .x = @divTrunc(tokens.Logical.width - card_w, 2),
        .y = tokens.Space.xl + tokens.Space.sm, // 40dp — room for number pad
        .w = card_w,
        .h = card_h,
    };
}

fn contentHeight(two: bool) i32 {
    const title_h = font.faceHeight(font.faceForRole(.title_l));
    const body_h = font.faceHeight(font.faceForRole(.body_m));
    const label_h = font.faceHeight(font.faceForRole(.label_m));
    const field_block = label_h + tokens.Space.xs + hit_h;
    const n: i32 = if (two) 2 else 1;
    const field_gaps = if (n > 1) (n - 1) * tokens.Space.md else 0;
    return tokens.Space.md + title_h + tokens.Space.sm + body_h + tokens.Space.md +
        n * field_block + field_gaps + tokens.Space.lg + btn_size.height() + tokens.Space.lg;
}

pub fn maskDots(len: usize, buf: []u8) []const u8 {
    const n = @min(len, buf.len);
    @memset(buf[0..n], '*');
    return buf[0..n];
}

pub fn paint(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    kind: Kind,
    title: []const u8,
    field1: []const u8,
    field2: []const u8,
    focus: u8,
    field1_err: bool,
    field2_err: bool,
    status: []const u8,
    status_err: bool,
    enter_t: f32,
) Layout {
    widgets.fillScrim(logical, theme);
    const two = kind == .set;
    const card = cardGeom(520, contentHeight(two), enter_t);
    // Tonal elev(3) only — no decorative stroke (MD3 dialog).
    widgets.fillRoundRect(logical, card, tokens.Shape.dialog, theme.elev(3));
    var lay: Layout = .{ .card = card };

    var y = card.y + tokens.Space.md;
    const title_h = font.faceHeight(font.faceForRole(.title_l));
    font.drawTextRole(logical, card.x + tokens.Space.lg, y, title, theme.on_surface, .title_l);
    lay.close = .{
        .x = card.x + card.w - close_sz - tokens.Space.md,
        .y = y + @divTrunc(title_h - close_sz, 2),
        .w = close_sz,
        .h = close_sz,
    };
    paintCloseIconBtn(logical, theme, lay.close);
    y += title_h + tokens.Space.sm;

    const status_c = if (status_err) theme.err else theme.on_surface_variant;
    const body_h = font.faceHeight(font.faceForRole(.body_m));
    font.drawTextRole(logical, card.x + tokens.Space.lg, y, if (status.len > 0) status else " ", status_c, .body_m);
    y += body_h + tokens.Space.md;

    const label_h = font.faceHeight(font.faceForRole(.label_m));
    const lab1: []const u8 = if (two) "New PIN (4-8 digits)" else "Current PIN";
    font.drawTextRole(logical, card.x + tokens.Space.lg, y, lab1, theme.on_surface_variant, .label_m);
    y += label_h + tokens.Space.xs;
    lay.field1 = .{ .x = card.x + tokens.Space.lg, .y = y, .w = card.w - tokens.Space.lg * 2, .h = hit_h };
    widgets.drawOutlinedTextField(logical, lay.field1, field1, "****", focus == 0, true, field1_err, theme);
    y += hit_h;

    if (two) {
        y += tokens.Space.md;
        font.drawTextRole(logical, card.x + tokens.Space.lg, y, "Confirm PIN", theme.on_surface_variant, .label_m);
        y += label_h + tokens.Space.xs;
        lay.field2 = .{ .x = card.x + tokens.Space.lg, .y = y, .w = card.w - tokens.Space.lg * 2, .h = hit_h };
        widgets.drawOutlinedTextField(logical, lay.field2, field2, "****", focus == 1, true, field2_err, theme);
    }

    const btn_h = btn_size.height();
    const btn_y = card.y + card.h - btn_h - tokens.Space.lg;
    const cancel_lab = "Cancel";
    const save_lab: []const u8 = if (kind == .clear) "Clear" else "Save";
    const cw = btnWidth(cancel_lab);
    const sw = btnWidth(save_lab);
    lay.cancel = .{ .x = card.x + tokens.Space.lg, .y = btn_y, .w = cw, .h = btn_h };
    widgets.drawTonalButton(logical, lay.cancel, cancel_lab, theme);
    lay.save = .{ .x = card.x + card.w - sw - tokens.Space.lg, .y = btn_y, .w = sw, .h = btn_h };
    if (kind == .clear) {
        widgets.drawDangerTonalButton(logical, lay.save, save_lab, theme);
    } else {
        widgets.drawFilledButton(logical, lay.save, save_lab, theme);
    }
    return lay;
}

pub fn hit(lay: Layout, kind: Kind, x: i32, y: i32) Hit {
    if (lay.close.contains(x, y) or lay.cancel.contains(x, y)) return .close;
    if (lay.save.contains(x, y)) return .save;
    if (lay.field1.contains(x, y)) return .field1;
    if (kind == .set and lay.field2.contains(x, y)) return .field2;
    if (!lay.card.contains(x, y)) return .close;
    return .none;
}

test "pin modal set has confirm field" {
    var logical = try fb.LogicalFb.alloc(std.testing.allocator);
    defer logical.deinit(std.testing.allocator);
    const theme = tokens.Theme.industrialTealDark();
    const lay = paint(&logical, theme, .set, "Set PIN", "****", "", 0, false, false, "", false, 1);
    try std.testing.expect(!lay.field2.isEmpty());
    try std.testing.expect(hit(lay, .set, lay.field2.x + 4, lay.field2.y + 4) == .field2);
}

test "pin modal buttons use ButtonSize.m height" {
    var logical = try fb.LogicalFb.alloc(std.testing.allocator);
    defer logical.deinit(std.testing.allocator);
    const theme = tokens.Theme.industrialTealDark();
    const lay = paint(&logical, theme, .set, "Set PIN", "", "", 0, false, false, "", false, 1);
    try std.testing.expectEqual(btn_size.height(), lay.save.h);
    try std.testing.expectEqual(btn_size.height(), lay.cancel.h);
}
