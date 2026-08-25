//! Machine string overlays — name + service notes (LVGL modal parity + MD3).

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");

pub const Kind = enum { none, name, svc_nt };

pub const Hit = enum { none, close, cancel, save, field };

pub const Layout = struct {
    card: geom.Rect = .{},
    close: geom.Rect = .{},
    cancel: geom.Rect = .{},
    save: geom.Rect = .{},
    field: geom.Rect = .{},
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
        .y = tokens.Space.xl + tokens.Space.sm,
        .w = card_w,
        .h = card_h,
    };
}

pub fn titleFor(kind: Kind) []const u8 {
    return switch (kind) {
        .name => "Machine name",
        .svc_nt => "Service notes",
        .none => "",
    };
}

pub fn hintFor(kind: Kind) []const u8 {
    return switch (kind) {
        .name => "Display name on status and exports.",
        .svc_nt => "Short note (grease, belts, etc.)",
        .none => "",
    };
}

pub fn paint(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    kind: Kind,
    value: []const u8,
    focused: bool,
    field_err: bool,
    status: []const u8,
    status_err: bool,
    enter_t: f32,
) Layout {
    widgets.fillScrim(logical, theme);
    const title_h = font.faceHeight(font.faceForRole(.title_l));
    const body_h = font.faceHeight(font.faceForRole(.body_m));
    const status_slot = body_h + tokens.Space.xs;
    const card_h = tokens.Space.md + title_h + tokens.Space.sm + body_h + tokens.Space.sm + status_slot + tokens.Space.md + hit_h + tokens.Space.lg + btn_size.height() + tokens.Space.lg;
    const card = cardGeom(520, card_h, enter_t);
    widgets.fillRoundRect(logical, card, tokens.Shape.dialog, theme.elev(3));
    var lay: Layout = .{ .card = card };

    var y = card.y + tokens.Space.md;
    font.drawTextRole(logical, card.x + tokens.Space.lg, y, titleFor(kind), theme.on_surface, .title_l);
    lay.close = .{
        .x = card.x + card.w - close_sz - tokens.Space.md,
        .y = y + @divTrunc(title_h - close_sz, 2),
        .w = close_sz,
        .h = close_sz,
    };
    paintCloseIconBtn(logical, theme, lay.close);
    y += title_h + tokens.Space.sm;

    font.drawTextRole(logical, card.x + tokens.Space.lg, y, hintFor(kind), theme.on_surface_variant, .body_m);
    y += body_h + tokens.Space.sm;

    const status_c = if (status_err) theme.err else theme.on_surface_variant;
    font.drawTextRole(logical, card.x + tokens.Space.lg, y, if (status.len > 0) status else " ", status_c, .body_m);
    y += status_slot + tokens.Space.md;

    lay.field = .{ .x = card.x + tokens.Space.lg, .y = y, .w = card.w - tokens.Space.lg * 2, .h = hit_h };
    const ph: []const u8 = if (kind == .name) "My CNC" else "e.g. greased X rails";
    widgets.drawOutlinedTextField(logical, lay.field, value, ph, focused, true, field_err, theme);

    const btn_h = btn_size.height();
    const btn_y = card.y + card.h - btn_h - tokens.Space.lg;
    const cw = btnWidth("Cancel");
    const sw = btnWidth("Save");
    lay.cancel = .{ .x = card.x + tokens.Space.lg, .y = btn_y, .w = cw, .h = btn_h };
    widgets.drawTonalButton(logical, lay.cancel, "Cancel", theme);
    lay.save = .{ .x = card.x + card.w - sw - tokens.Space.lg, .y = btn_y, .w = sw, .h = btn_h };
    widgets.drawFilledButton(logical, lay.save, "Save", theme);
    return lay;
}

pub fn hit(lay: Layout, x: i32, y: i32) Hit {
    if (lay.close.contains(x, y) or lay.cancel.contains(x, y)) return .close;
    if (lay.save.contains(x, y)) return .save;
    if (lay.field.contains(x, y)) return .field;
    if (!lay.card.contains(x, y)) return .close;
    return .none;
}

test "mach string modal field hit" {
    var logical = try fb.LogicalFb.alloc(std.testing.allocator);
    defer logical.deinit(std.testing.allocator);
    const theme = tokens.Theme.industrialTealDark();
    const lay = paint(&logical, theme, .name, "Shop mill", true, false, "", false, 1);
    try std.testing.expect(hit(lay, lay.field.x + 4, lay.field.y + 4) == .field);
}
