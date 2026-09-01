//! M-Panel C6 Update — guarded ESP-Hosted slave OTA from the SD-card root.

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const tool_chrome = @import("m_panel_tool.zig");

pub const max_files = 8;
pub const name_len = 96;

pub const Phase = enum(u8) { idle, ready, armed, flashing, success, failed };
pub const Action = enum(u8) { refresh, select, check, flash, restart };

pub const State = struct {
    phase: Phase = .idle,
    file_count: u8 = 0,
    selected: u8 = 0,
    progress: u8 = 0,
    c6_connected: bool = false,
    version: [24]u8 = .{0} ** 24,
    version_len: u8 = 0,
    files: [max_files][name_len]u8 = [_][name_len]u8{.{0} ** name_len} ** max_files,
    file_lens: [max_files]u8 = .{0} ** max_files,
    status: [160]u8 = .{0} ** 160,
    status_len: u8 = 0,

    pub fn statusText(self: *const State) []const u8 { return self.status[0..self.status_len]; }
    pub fn versionText(self: *const State) []const u8 { return self.version[0..self.version_len]; }
    pub fn fileText(self: *const State, i: usize) []const u8 {
        if (i >= self.file_count) return "";
        return self.files[i][0..self.file_lens[i]];
    }
};

pub const Hit = enum { none, scrim, back, exit, refresh, row, check, flash, restart };
pub const HitInfo = struct { kind: Hit = .none, index: u8 = 0 };
pub const Layout = struct {
    header: tool_chrome.Header = .{},
    refresh: geom.Rect = .{},
    rows: [max_files]geom.Rect = [_]geom.Rect{.{}} ** max_files,
    row_n: u8 = 0,
    check: geom.Rect = .{},
    flash: geom.Rect = .{},
    restart: geom.Rect = .{},
};

fn cardGeom(t0: f32) geom.Rect {
    const t = std.math.clamp(t0, 0, 1);
    const w: i32 = @intFromFloat(1220.0 * (0.92 + 0.08 * t));
    const h: i32 = @intFromFloat(650.0 * (0.92 + 0.08 * t));
    return .{ .x = @divTrunc(tokens.Logical.width - w, 2), .y = @divTrunc(tokens.Logical.height - h, 2), .w = w, .h = h };
}

fn drawDisabled(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, theme: tokens.Theme) void {
    widgets.drawButton(logical, r, label, .filled, .disabled, theme);
}

pub fn paint(logical: *fb.LogicalFb, theme: tokens.Theme, state: *const State, enter_t: f32) Layout {
    widgets.fillScrim(logical, theme);
    const card = cardGeom(enter_t);
    widgets.fillRoundRect(logical, card, tokens.Shape.dialog, theme.elev(3));
    var lay: Layout = .{};
    lay.header = tool_chrome.headerChrome(card);
    tool_chrome.paintBackToPanel(logical, theme, lay.header.back);
    tool_chrome.paintTitle(logical, theme, lay.header.back.x + lay.header.back.w + tokens.Space.sm, lay.header.back.y, "C6 Firmware Update");
    tool_chrome.paintExit(logical, theme, lay.header.exit);

    const x = card.x + tokens.Space.lg;
    const right = card.x + card.w - tokens.Space.lg;
    var y = lay.header.back.y + lay.header.back.h + tokens.Space.md;
    const link = if (state.c6_connected) "ESP-Hosted/SDIO connected" else "C6 not connected";
    font.drawTextRole(logical, x, y, link, if (state.c6_connected) theme.primary else theme.on_error_container, .body_m);
    if (state.version_len != 0) font.drawTextRole(logical, x + 270, y, state.versionText(), theme.on_surface_variant, .body_m);
    lay.refresh = .{ .x = right - 190, .y = y - 10, .w = 190, .h = 60 };
    widgets.drawTonalButton(logical, lay.refresh, "Refresh SD", theme);
    y += tokens.Logical.touch_min + tokens.Space.sm;

    const row_h: i32 = 54;
    const row_gap: i32 = 6;
    lay.row_n = @min(state.file_count, 6);
    var i: u8 = 0;
    while (i < lay.row_n) : (i += 1) {
        const r: geom.Rect = .{ .x = x, .y = y, .w = right - x, .h = row_h };
        lay.rows[i] = r;
        const selected = i == state.selected;
        widgets.fillRoundRect(logical, r, tokens.Shape.md, if (selected) theme.secondary_container else theme.surface_container_low);
        if (!selected) widgets.strokeRoundRect(logical, r, tokens.Shape.md, theme.outline_variant, 1);
        font.drawTextRole(logical, r.x + tokens.Space.md, r.y + 16, state.fileText(i), if (selected) theme.on_secondary_container else theme.on_surface, .body_m);
        y += row_h + row_gap;
    }
    if (lay.row_n == 0) font.drawTextRole(logical, x, y + 8, "No C6 .bin files available in the SD card root.", theme.on_surface_variant, .body_m);

    const status_y = card.y + card.h - 150;
    font.drawTextRole(logical, x, status_y, state.statusText(), if (state.phase == .failed) theme.on_error_container else theme.on_surface_variant, .body_m);
    const bar: geom.Rect = .{ .x = x, .y = status_y + 27, .w = right - x, .h = 10 };
    widgets.fillRoundRect(logical, bar, 5, theme.surface_container_high);
    if (state.progress > 0) {
        const fill: geom.Rect = .{ .x = bar.x, .y = bar.y, .w = @divTrunc(bar.w * state.progress, 100), .h = bar.h };
        widgets.fillRoundRect(logical, fill, 5, theme.primary);
    }

    const action_h: i32 = 64;
    const action_w: i32 = 230;
    const by = card.y + card.h - tokens.Space.lg - action_h;
    lay.check = .{ .x = x, .y = by, .w = action_w, .h = action_h };
    lay.flash = .{ .x = x + action_w + tokens.Space.md, .y = by, .w = action_w, .h = action_h };
    lay.restart = .{ .x = right - action_w, .y = by, .w = action_w, .h = action_h };
    const can_check = state.file_count > 0 and state.phase != .flashing;
    if (can_check) widgets.drawFilledButton(logical, lay.check, "1. Check image", theme) else drawDisabled(logical, lay.check, "1. Check image", theme);
    if (state.phase == .armed) widgets.drawDangerButton(logical, lay.flash, "2. Flash C6", theme) else drawDisabled(logical, lay.flash, "2. Flash C6", theme);
    if (state.phase == .success) widgets.drawFilledButton(logical, lay.restart, "3. Restart", theme) else drawDisabled(logical, lay.restart, "3. Restart", theme);
    return lay;
}

pub fn hit(layout: Layout, x: i32, y: i32) HitInfo {
    if (tool_chrome.hitBack(layout.header, x, y)) return .{ .kind = .back };
    if (tool_chrome.hitExit(layout.header, x, y)) return .{ .kind = .exit };
    if (tool_chrome.hitScrim(layout.header, x, y)) return .{ .kind = .scrim };
    if (layout.refresh.contains(x, y)) return .{ .kind = .refresh };
    var i: u8 = 0;
    while (i < layout.row_n) : (i += 1) if (layout.rows[i].contains(x, y)) return .{ .kind = .row, .index = i };
    if (layout.check.contains(x, y)) return .{ .kind = .check };
    if (layout.flash.contains(x, y)) return .{ .kind = .flash };
    if (layout.restart.contains(x, y)) return .{ .kind = .restart };
    return .{};
}

test "C6 OTA buttons meet minimum touch size" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    var state: State = .{};
    state.file_count = 1;
    const lay = paint(&logical, tokens.Theme.industrialTealDark(), &state, 1);
    try std.testing.expect(lay.check.h >= tokens.Logical.touch_min);
    try std.testing.expect(lay.flash.h >= tokens.Logical.touch_min);
    try std.testing.expect(lay.restart.h >= tokens.Logical.touch_min);
    try std.testing.expect(lay.refresh.h >= tokens.Logical.touch_min);
    try std.testing.expect(lay.rows[0].h >= tokens.Logical.touch_min);
}
