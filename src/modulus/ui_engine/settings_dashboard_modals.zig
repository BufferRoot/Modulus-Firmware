//! Dashboard settings overlays — increments (pad), WCS, macros, arrange (LVGL + MD3).

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const icons_phosphor = @import("icons_phosphor.zig");
const prefs_mod = @import("settings_prefs.zig");
const actions_widget = @import("actions_widget.zig");

pub const Kind = enum { none, wcs, macro, arrange };

pub const WcsHit = enum { none, close, lock0, lock1, lock2, lock3, lock4, lock5, name0, name1, name2, name3, name4, name5 };

pub const MacroHit = enum { none, close, name, on_code, off_code, save, delete };

pub const ArrangeHit = enum {
    none,
    close,
    slot0,
    slot1,
    slot2,
    slot3,
    pick,
};

pub const WcsLayout = struct {
    card: geom.Rect = .{},
    close: geom.Rect = .{},
    lock: [6]geom.Rect = [_]geom.Rect{.{}} ** 6,
    name: [6]geom.Rect = [_]geom.Rect{.{}} ** 6,
};

pub const MacroLayout = struct {
    card: geom.Rect = .{},
    close: geom.Rect = .{},
    cancel: geom.Rect = .{},
    name: geom.Rect = .{},
    on_code: geom.Rect = .{},
    off_code: geom.Rect = .{},
    save: geom.Rect = .{},
    delete: geom.Rect = .{},
};

pub const ArrangeLayout = struct {
    card: geom.Rect = .{},
    close: geom.Rect = .{},
    /// Scrollable list viewport (pick mode).
    list_view: geom.Rect = .{},
    slot: [4]geom.Rect = [_]geom.Rect{.{}} ** 4,
    picks: [16]geom.Rect = [_]geom.Rect{.{}} ** 16,
    pick_n: u8 = 0,
    pick_ids: [16]actions_widget.QuickId = [_]actions_widget.QuickId{.off} ** 16,
    /// Max scroll_px for pick list (0 when slots view or short list).
    scroll_max: i32 = 0,
};

const close_sz: i32 = tokens.Logical.touch_min;
const hit_h: i32 = tokens.Logical.touch_min;
const row_gap: i32 = tokens.Space.sm; // 8dp spacing system
const btn_size = tokens.ButtonSize.m;

fn paintCloseX(logical: *fb.LogicalFb, theme: tokens.Theme, r: geom.Rect) void {
    widgets.drawTonalCloseButton(logical, r, theme);
}

fn paintDialogCard(logical: *fb.LogicalFb, theme: tokens.Theme, card: geom.Rect) void {
    // MD3 dialog: tonal elev(3) only — outline is for text fields, not the surface.
    widgets.fillRoundRect(logical, card, tokens.Shape.dialog, theme.elev(3));
}

fn cardGeom(w0: i32, h0: i32, enter_t: f32) geom.Rect {
    const t = std.math.clamp(enter_t, 0, 1);
    const card_w: i32 = @intFromFloat(@as(f32, @floatFromInt(w0)) * (0.88 + 0.12 * t));
    const card_h: i32 = @intFromFloat(@as(f32, @floatFromInt(h0)) * (0.88 + 0.12 * t));
    return .{
        .x = @divTrunc(tokens.Logical.width - card_w, 2),
        .y = @divTrunc(tokens.Logical.height - card_h, 2),
        .w = card_w,
        .h = card_h,
    };
}

fn paintDestructiveFilled(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, theme: tokens.Theme) void {
    widgets.drawDangerTonalButton(logical, r, label, theme);
}

fn btnWidth(label: []const u8) i32 {
    const tw = font.textWidthStr(label, .label_l);
    return @max(tokens.Logical.touch_min, tw + btn_size.padX() * 2);
}

/// Title row + close; returns y after title (before support / body).
fn paintTitleRow(logical: *fb.LogicalFb, theme: tokens.Theme, card: geom.Rect, title: []const u8, close_out: *geom.Rect) i32 {
    const title_h = font.faceHeight(font.faceForRole(.title_l));
    const y = card.y + tokens.Space.md;
    font.drawTextRole(logical, card.x + tokens.Space.lg, y, title, theme.on_surface, .title_l);
    close_out.* = .{
        .x = card.x + card.w - close_sz - tokens.Space.md,
        .y = y + @divTrunc(title_h - close_sz, 2),
        .w = close_sz,
        .h = close_sz,
    };
    paintCloseX(logical, theme, close_out.*);
    return y + title_h + tokens.Space.sm;
}

fn paintSupport(logical: *fb.LogicalFb, theme: tokens.Theme, x: i32, y: i32, text: []const u8) i32 {
    font.drawTextRole(logical, x, y, text, theme.on_surface_variant, .body_s);
    return y + font.faceHeight(font.faceForRole(.body_s)) + tokens.Space.md;
}

pub fn paintWcs(logical: *fb.LogicalFb, theme: tokens.Theme, dash: *const prefs_mod.DashboardPrefs, enter_t: f32) WcsLayout {
    widgets.fillScrim(logical, theme);
    const card = cardGeom(640, 560, enter_t);
    paintDialogCard(logical, theme, card);
    var lay: WcsLayout = .{ .card = card };
    var y = paintTitleRow(logical, theme, card, "WCS lock & names", &lay.close);
    y = paintSupport(logical, theme, card.x + tokens.Space.lg, y, "Locked WCS asks before change on status bar.");

    const row_h: i32 = hit_h + row_gap;
    const pad = tokens.Space.lg;
    const name_w = card.w - pad * 2 - widgets.switch_w - tokens.Space.md - 48;
    var i: usize = 0;
    while (i < 6) : (i += 1) {
        const row_y = y + @as(i32, @intCast(i)) * row_h;
        const locked = (dash.wcs_lock & (@as(u8, 1) << @intCast(i))) != 0;
        const sw_x = card.x + pad;
        const sw_y = row_y + @divTrunc(hit_h - widgets.switch_h, 2);
        widgets.drawSwitchBool(logical, sw_x, sw_y, locked, theme);
        lay.lock[i] = widgets.switchHitRect(sw_x, sw_y);

        const lab = dash.wcsDisplayLabel(i);
        const lh = font.faceHeight(font.faceForRole(.body_m));
        const lab_x = sw_x + widgets.switch_w + tokens.Space.md;
        font.drawTextRole(logical, lab_x, row_y + @divTrunc(hit_h - lh, 2), lab, theme.on_surface, .body_m);

        lay.name[i] = .{
            .x = card.x + card.w - pad - name_w,
            .y = row_y,
            .w = name_w,
            .h = hit_h,
        };
        widgets.drawOutlinedTextField(logical, lay.name[i], dash.wcsNameSlice(i), "Rename", false, true, false, theme);
    }
    return lay;
}

pub fn hitWcs(lay: WcsLayout, x: i32, y: i32) WcsHit {
    if (lay.close.contains(x, y)) return .close;
    inline for (0..6) |i| {
        if (lay.lock[i].contains(x, y)) {
            return switch (i) {
                0 => .lock0,
                1 => .lock1,
                2 => .lock2,
                3 => .lock3,
                4 => .lock4,
                else => .lock5,
            };
        }
        if (lay.name[i].contains(x, y)) {
            return switch (i) {
                0 => .name0,
                1 => .name1,
                2 => .name2,
                3 => .name3,
                4 => .name4,
                else => .name5,
            };
        }
    }
    if (!lay.card.contains(x, y)) return .close;
    return .none;
}

pub fn paintMacro(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    title: []const u8,
    name: []const u8,
    on_code: []const u8,
    off_code: []const u8,
    is_edit: bool,
    enter_t: f32,
) MacroLayout {
    widgets.fillScrim(logical, theme);
    const card = cardGeom(560, 440, enter_t);
    paintDialogCard(logical, theme, card);
    var lay: MacroLayout = .{ .card = card };
    var y = paintTitleRow(logical, theme, card, title, &lay.close);
    y = paintSupport(
        logical,
        theme,
        card.x + tokens.Space.lg,
        y,
        "ON = M64 P0, OFF = M65 P0 (toggle). Leave OFF blank for one-shot.",
    );

    const field_gap: i32 = hit_h + tokens.Space.md + font.faceHeight(font.faceForRole(.label_m)) + tokens.Space.xs;
    const labels = [_][]const u8{ "Button name", "G-code ON / pressed", "G-code OFF (optional)" };
    const vals = [_][]const u8{ name, on_code, off_code };
    const placeholders = [_][]const u8{ "e.g. Air blast", "M8", "M9" };
    const rects = [_]*geom.Rect{ &lay.name, &lay.on_code, &lay.off_code };
    for (labels, 0..) |lab, i| {
        const row_y = y + @as(i32, @intCast(i)) * field_gap;
        font.drawTextRole(logical, card.x + tokens.Space.lg, row_y, lab, theme.on_surface_variant, .label_m);
        const field_y = row_y + font.faceHeight(font.faceForRole(.label_m)) + tokens.Space.xs;
        rects[i].* = .{ .x = card.x + tokens.Space.lg, .y = field_y, .w = card.w - tokens.Space.lg * 2, .h = hit_h };
        widgets.drawOutlinedTextField(logical, rects[i].*, vals[i], placeholders[i], false, true, false, theme);
    }

    const btn_h = @max(btn_size.height(), hit_h);
    const btn_y = card.y + card.h - btn_h - tokens.Space.lg;
    var x_left = card.x + tokens.Space.lg;
    if (is_edit) {
        const dw = btnWidth("Delete");
        lay.delete = .{ .x = x_left, .y = btn_y, .w = dw, .h = btn_h };
        paintDestructiveFilled(logical, lay.delete, "Delete", theme);
        x_left += dw + tokens.Space.sm;
    }
    const cw = btnWidth("Cancel");
    lay.cancel = .{ .x = x_left, .y = btn_y, .w = cw, .h = btn_h };
    widgets.drawTonalButton(logical, lay.cancel, "Cancel", theme);

    const sw = btnWidth("Save");
    lay.save = .{ .x = card.x + card.w - sw - tokens.Space.lg, .y = btn_y, .w = sw, .h = btn_h };
    widgets.drawFilledButton(logical, lay.save, "Save", theme);
    return lay;
}

pub fn hitMacro(lay: MacroLayout, x: i32, y: i32) MacroHit {
    if (lay.close.contains(x, y) or lay.cancel.contains(x, y)) return .close;
    if (lay.save.contains(x, y)) return .save;
    if (!lay.delete.isEmpty() and lay.delete.contains(x, y)) return .delete;
    if (lay.name.contains(x, y)) return .name;
    if (lay.on_code.contains(x, y)) return .on_code;
    if (lay.off_code.contains(x, y)) return .off_code;
    if (!lay.card.contains(x, y)) return .close;
    return .none;
}

const k_builtin = [_]actions_widget.QuickId{
    .spindle_cw, .spindle_ccw, .coolant, .fan, .zero_all, .mist, .single_step, .off,
};

fn paintListRow(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    r: geom.Rect,
    headline: []const u8,
    support: []const u8,
    selected: bool,
    trailing_caret: bool,
) void {
    const fill = if (selected) theme.secondary_container else theme.surface_container_high;
    widgets.fillRoundRect(logical, r, tokens.Shape.md, fill);
    if (!selected) widgets.strokeRoundRect(logical, r, tokens.Shape.md, theme.outline_variant, 1);
    const fg = if (selected) theme.on_secondary_container else theme.on_surface;
    const muted = if (selected) theme.on_secondary_container else theme.on_surface_variant;
    const hh = font.faceHeight(font.faceForRole(.body_m));
    if (support.len == 0 or r.h < hit_h + 8) {
        if (support.len > 0 and !selected) {
            var buf: [48]u8 = undefined;
            const lab = std.fmt.bufPrint(&buf, "{s} - {s}", .{ headline, support }) catch headline;
            font.drawTextRole(logical, r.x + 16, r.y + @divTrunc(r.h - hh, 2), lab, fg, .body_m);
        } else {
            font.drawTextRole(logical, r.x + 16, r.y + @divTrunc(r.h - hh, 2), headline, fg, .body_m);
        }
    } else {
        font.drawTextRole(logical, r.x + 16, r.y + 8, headline, fg, .body_m);
        font.drawTextRole(logical, r.x + 16, r.y + 8 + hh + 2, support, muted, .label_m);
    }
    if (selected) {
        const ah = font.faceHeight(font.faceForRole(.label_m));
        font.drawTextRole(logical, r.x + r.w - 72, r.y + @divTrunc(r.h - ah, 2), "Active", theme.primary, .label_m);
    } else if (trailing_caret) {
        icons_phosphor.drawCentered(logical, r.x + r.w - 24, r.y + @divTrunc(r.h, 2), .caret_right, theme.on_surface_variant);
    }
}

fn collectArrangePicks(dash: *const prefs_mod.DashboardPrefs, lay: *ArrangeLayout) void {
    var n: u8 = 0;
    for (k_builtin) |id| {
        if (n >= lay.picks.len) break;
        lay.pick_ids[n] = id;
        n += 1;
    }
    for (dash.macros, 0..) |m, mi| {
        if (!m.occupied() or n >= lay.picks.len) continue;
        lay.pick_ids[n] = switch (mi) {
            0 => .user0,
            1 => .user1,
            2 => .user2,
            else => .user3,
        };
        n += 1;
    }
    lay.pick_n = n;
}

pub fn paintArrange(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    dash: *const prefs_mod.DashboardPrefs,
    pick_slot: i8,
    scroll_px: i32,
    enter_t: f32,
) ArrangeLayout {
    widgets.fillScrim(logical, theme);
    const card = cardGeom(600, 520, enter_t);
    paintDialogCard(logical, theme, card);
    var lay: ArrangeLayout = .{ .card = card };
    const title: []const u8 = if (pick_slot >= 0) "Choose action" else "Arrange on dashboard";
    var y = paintTitleRow(logical, theme, card, title, &lay.close);

    const pad = tokens.Space.lg;
    const row_step = hit_h + row_gap + 4;
    const footer = tokens.Space.md;

    if (pick_slot < 0) {
        y = paintSupport(logical, theme, card.x + pad, y, "Tap a slot to assign built-in or custom.");
        var i: usize = 0;
        while (i < 4) : (i += 1) {
            const row_y = y + @as(i32, @intCast(i)) * row_step;
            lay.slot[i] = .{ .x = card.x + pad, .y = row_y, .w = card.w - pad * 2, .h = hit_h + 4 };
            var hbuf: [24]u8 = undefined;
            const head = std.fmt.bufPrint(&hbuf, "Slot {d}", .{i + 1}) catch "Slot";
            paintListRow(logical, theme, lay.slot[i], head, dash.quickAssignLabel(dash.quick[i]), false, true);
        }
    } else {
        collectArrangePicks(dash, &lay);
        const view_top = y;
        const view_bottom = card.y + card.h - footer;
        lay.list_view = .{ .x = card.x + pad, .y = view_top, .w = card.w - pad * 2, .h = view_bottom - view_top };
        const content_h = @as(i32, @intCast(lay.pick_n)) * row_step;
        lay.scroll_max = @max(0, content_h - lay.list_view.h);
        const scroll = std.math.clamp(scroll_px, 0, lay.scroll_max);

        logical.setClip(lay.list_view);
        defer logical.setClip(null);

        var i: u8 = 0;
        while (i < lay.pick_n) : (i += 1) {
            const row_y = view_top + @as(i32, @intCast(i)) * row_step - scroll;
            const id = lay.pick_ids[i];
            const r: geom.Rect = .{ .x = card.x + pad, .y = row_y, .w = card.w - pad * 2, .h = hit_h };
            // Keep hit rects only when intersecting the viewport.
            if (geom.Rect.intersect(r, lay.list_view).isEmpty()) {
                lay.picks[i] = .{};
            } else {
                lay.picks[i] = r;
                const sel = dash.quick[@intCast(pick_slot)] == id;
                const support: []const u8 = if (id == .off) "Hide slot" else "";
                paintListRow(logical, theme, r, dash.quickAssignLabel(id), support, sel, false);
            }
        }
    }
    return lay;
}

pub fn hitArrange(lay: ArrangeLayout, pick_slot: i8, x: i32, y: i32) struct { hit: ArrangeHit, pick_i: u8 } {
    if (lay.close.contains(x, y)) return .{ .hit = .close, .pick_i = 0 };
    if (pick_slot < 0) {
        inline for (0..4) |i| {
            if (lay.slot[i].contains(x, y)) {
                return .{
                    .hit = switch (i) {
                        0 => .slot0,
                        1 => .slot1,
                        2 => .slot2,
                        else => .slot3,
                    },
                    .pick_i = 0,
                };
            }
        }
    } else {
        var i: u8 = 0;
        while (i < lay.pick_n) : (i += 1) {
            if (!lay.picks[i].isEmpty() and lay.picks[i].contains(x, y)) return .{ .hit = .pick, .pick_i = i };
        }
    }
    if (!lay.card.contains(x, y)) return .{ .hit = .close, .pick_i = 0 };
    return .{ .hit = .none, .pick_i = 0 };
}

test "dashboard modals: arrange builtins listed" {
    var logical = try fb.LogicalFb.alloc(std.testing.allocator);
    defer logical.deinit(std.testing.allocator);
    const theme = tokens.Theme.industrialTealDark();
    const dash: prefs_mod.DashboardPrefs = .{};
    const lay = paintArrange(&logical, theme, &dash, 0, 0, 1);
    try std.testing.expect(lay.pick_n >= k_builtin.len);
}

test "dashboard modals: macro has cancel" {
    var logical = try fb.LogicalFb.alloc(std.testing.allocator);
    defer logical.deinit(std.testing.allocator);
    const theme = tokens.Theme.industrialTealDark();
    const lay = paintMacro(&logical, theme, "Add quick button", "", "", "", false, 1);
    try std.testing.expect(!lay.cancel.isEmpty());
    try std.testing.expect(hitMacro(lay, lay.cancel.x + 4, lay.cancel.y + 4) == .close);
}

test "dashboard modals: arrange scroll exposes late rows" {
    var logical = try fb.LogicalFb.alloc(std.testing.allocator);
    defer logical.deinit(std.testing.allocator);
    const theme = tokens.Theme.industrialTealDark();
    var dash: prefs_mod.DashboardPrefs = .{};
    // Fill macros so the pick list is long.
    inline for (0..4) |i| {
        prefs_mod.MacroSlot.setField(&dash.macros[i].name, "M");
        prefs_mod.MacroSlot.setField(&dash.macros[i].on, "M8");
    }
    const top = paintArrange(&logical, theme, &dash, 0, 0, 1);
    try std.testing.expect(top.scroll_max > 0);
    const scrolled = paintArrange(&logical, theme, &dash, 0, top.scroll_max, 1);
    try std.testing.expect(!scrolled.picks[scrolled.pick_n - 1].isEmpty());
}
