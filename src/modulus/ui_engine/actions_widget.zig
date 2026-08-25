//! Right-rail actions: Cycle/Stop + sync, Hold/Resume, quick grid 1–4, Home all.
//! Quick tiles fill leftover rail height with count-adaptive layout:
//! 1=full, 2=side-by-side vertical, 3=tall left + stacked right, 4=2×2.

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const color = @import("color.zig");
const icons_phosphor = @import("icons_phosphor.zig");
const form = @import("settings_form.zig");

pub const max_quick: u8 = 4;
pub const min_quick: u8 = 1;

/// Match grblHAL A-tag / `cnc/grblhal/rt.accessory` / LVGL `k_acc_*`.
pub const Acc = struct {
    pub const spindle_cw: u8 = 1 << 0;
    pub const spindle_ccw: u8 = 1 << 1;
    pub const mist: u8 = 1 << 2;
    pub const flood: u8 = 1 << 3;
};

/// Catalog of assignable quick actions (LVGL `UI_QBTN_*` subset + host LED).
pub const QuickId = enum(u8) {
    spindle_cw,
    spindle_ccw,
    coolant,
    fan,
    zero_all,
    macro,
    mist,
    off,
    user0,
    user1,
    user2,
    user3,
    single_step,
    led,

    /// Snackbar / settings single-line name.
    pub fn label(self: QuickId) []const u8 {
        return switch (self) {
            .spindle_cw => "Spindle CW",
            .spindle_ccw => "Spindle CCW",
            .coolant => "Coolant",
            .fan => "Fan",
            .zero_all => "Zero all",
            .macro => "Macro",
            .mist => "Mist",
            .off => "Hidden",
            .user0 => "USER 0",
            .user1 => "USER 1",
            .user2 => "USER 2",
            .user3 => "USER 3",
            .single_step => "Step",
            .led => "LED",
        };
    }

    /// Dashboard tile face — multiline like LVGL `ui_qbtn_icon_label` (fits narrow cells).
    pub fn faceLabel(self: QuickId) []const u8 {
        return switch (self) {
            .spindle_cw => "SPINDLE\nCW",
            .spindle_ccw => "SPINDLE\nCCW",
            .coolant => "Coolant",
            .fan => "Fan",
            .zero_all => "ZERO\nALL",
            .macro => "Macro",
            .mist => "Mist",
            .off => "Hidden",
            .user0 => "USER 0",
            .user1 => "USER 1",
            .user2 => "USER 2",
            .user3 => "USER 3",
            .single_step => "Step",
            .led => "LED",
        };
    }

    pub fn icon(self: QuickId) icons_phosphor.Id {
        return switch (self) {
            .spindle_cw, .spindle_ccw => .spindle,
            .coolant => .coolant,
            .fan => .fan,
            .zero_all => .lightning,
            .macro => .play,
            .mist => .mist,
            .off => .stop,
            .user0, .user1, .user2, .user3 => .gear,
            .single_step => .pause,
            .led => .scroll,
        };
    }
};

/// CNC accessory view for quick-button active style (LVGL `qbtn_assign_active`).
pub const AccView = struct {
    accessories: u8 = 0,
    connected: bool = true,
    fan_on: bool = false,
};

pub fn isAssignActive(id: QuickId, acc: AccView, latched: bool) bool {
    if (!acc.connected) return false;
    return switch (id) {
        .spindle_cw => (acc.accessories & Acc.spindle_cw) != 0,
        .spindle_ccw => (acc.accessories & Acc.spindle_ccw) != 0,
        .mist => (acc.accessories & Acc.mist) != 0,
        .coolant => (acc.accessories & Acc.flood) != 0,
        .fan => acc.fan_on,
        .zero_all, .off => false,
        .led, .macro, .single_step, .user0, .user1, .user2, .user3 => latched,
    };
}

pub const MachinePhase = enum { idle, run, hold };

/// Compact visible quick tiles — `.off` slots are hidden (LVGL `ui_qbtn_collect_entries`).
pub const ActiveQuick = struct {
    /// Visual index → original arrange slot (0..3).
    slots: [max_quick]u8 = .{0} ** max_quick,
    n: u8 = 0,
};

pub const State = struct {
    phase: MachinePhase = .idle,
    /// How many arrange slots considered (1…4). `.off` within that range are skipped.
    quick_count: u8 = 4,
    /// Slot definitions (first quick_count used).
    quick: [max_quick]QuickId = .{ .spindle_cw, .coolant, .fan, .zero_all },
    /// Latch for non-accessory assigns (LED / macro / USER / step). Fan uses AccView.fan_on.
    quick_on: [max_quick]bool = .{ false, false, false, false },

    pub fn clampQuickCount(n: u8) u8 {
        return @max(min_quick, @min(max_quick, n));
    }

    pub fn setQuickCount(self: *State, n: u8) void {
        self.quick_count = clampQuickCount(n);
    }

    /// Non-`.off` assigns in slot order — drives layout 1/2/3/4 and hit mapping.
    pub fn collectActive(self: State) ActiveQuick {
        var out: ActiveQuick = .{};
        const lim = clampQuickCount(self.quick_count);
        var i: u8 = 0;
        while (i < lim) : (i += 1) {
            if (self.quick[i] == .off) continue;
            out.slots[out.n] = i;
            out.n += 1;
        }
        return out;
    }

    pub fn toggleLatch(self: *State, index: usize) void {
        if (index >= clampQuickCount(self.quick_count)) return;
        self.quick_on[index] = !self.quick_on[index];
    }

    pub fn isQuickOn(self: State, index: usize, acc: AccView) bool {
        if (index >= clampQuickCount(self.quick_count)) return false;
        if (self.quick[index] == .off) return false;
        return isAssignActive(self.quick[index], acc, self.quick_on[index]);
    }

    pub fn isRunning(self: State) bool {
        return self.phase == .run;
    }

    pub fn isHeld(self: State) bool {
        return self.phase == .hold;
    }
};

pub const HitKind = enum { none, cycle, sync, hold, home, quick };

pub const Hit = struct {
    kind: HitKind = .none,
    quick_index: usize = 0,
};

/// Match Tab5 LVGL `ui_widget_actions.c`: wide=112, home=96, pad_row=MD, split=72×112.
/// Heights are CNC/LVGL overrides of MD3 ButtonSize.xl (64) — keep parity with device UI.
/// Quick grid flex-grows into leftover (do not inflate Cycle/Hold/Home).
const gap: i32 = tokens.Space.md; // MOD_UI_SPACE_MD
const sync_w: i32 = 72;
const primary_h: i32 = 112; // k_wide_h
const home_h: i32 = 96; // k_home_h
const min_quick_row: i32 = 56;
/// LVGL wide/home/split: ICON_SZ_32; quick grid: ICON_SZ_24.
const icon_wide: i32 = 32;
const icon_quick: i32 = 24;
/// LVGL quick: SHAPE_XL (28) idle; BODY_M label (regular weight, not title/bold).
const quick_rad: i32 = tokens.Shape.xl;
const label_role: tokens.TypeRole = .title_m;
const quick_label_role: tokens.TypeRole = .body_m;
const quick_label_pad: i32 = tokens.Space.sm;

const RailLay = struct {
    cycle: geom.Rect,
    sync: geom.Rect,
    hold: geom.Rect,
    quick: geom.Rect,
    home: geom.Rect,
    quick_row_h: i32,
};

fn railLay(bounds: geom.Rect, n: u8) RailLay {
    const nn = @min(n, max_quick);
    const rows: i32 = switch (nn) {
        0, 1, 2 => 1,
        else => 2,
    };

    const y0 = bounds.y;
    const cycle: geom.Rect = .{
        .x = bounds.x,
        .y = y0,
        .w = bounds.w - sync_w - tokens.Space.xs, // LVGL pad_column XS between cycle + split
        .h = primary_h,
    };
    const sync: geom.Rect = .{
        .x = bounds.x + bounds.w - sync_w,
        .y = y0,
        .w = sync_w,
        .h = primary_h,
    };
    const hold: geom.Rect = .{
        .x = bounds.x,
        .y = y0 + primary_h + gap,
        .w = bounds.w,
        .h = primary_h,
    };
    const home: geom.Rect = .{
        .x = bounds.x,
        .y = bounds.y + bounds.h - home_h,
        .w = bounds.w,
        .h = home_h,
    };
    const quick_y = hold.y + hold.h + gap;
    const quick_bot = home.y - gap;
    const avail = @max(0, quick_bot - quick_y);
    const grid_h: i32 = if (nn == 0)
        0
    else
        @max(min_quick_row * rows + gap * @max(0, rows - 1), avail);
    const quick: geom.Rect = .{
        .x = bounds.x,
        .y = quick_y,
        .w = bounds.w,
        .h = grid_h,
    };
    const quick_row_h = if (nn == 0)
        0
    else
        @max(min_quick_row, @divTrunc(grid_h - gap * @max(0, rows - 1), rows));
    return .{ .cycle = cycle, .sync = sync, .hold = hold, .quick = quick, .home = home, .quick_row_h = quick_row_h };
}

pub fn paint(logical: *fb.LogicalFb, bounds: geom.Rect, theme: tokens.Theme, state: State, acc: AccView) void {
    const active = state.collectActive();
    const lay = railLay(bounds, active.n);

    // CNC color-lock: Cycle green / Hold orange / Stop dark red / Home dark blue.
    const cycle_run = state.phase == .run;
    const cycle_label: []const u8 = if (cycle_run) "Stop Cycle" else "Cycle start";
    const cycle_icon: icons_phosphor.Id = if (cycle_run) .stop else .play;
    const cycle_kind: widgets.ButtonKind = if (cycle_run) .stop else .cycle;
    paintStackedPill(logical, lay.cycle, cycle_label, cycle_icon, cycle_kind, theme, form.sampleWidget("act.cycle.p", 0));

    {
        const sync_st: widgets.ButtonState = if (form.sampleWidget("act.sync.p", 0) > 0.05) .pressed else .enabled;
        const ink = widgets.drawButtonSurface(logical, lay.sync, .primary_container, sync_st, theme, 0, 0, 0);
        icons_phosphor.drawCenteredScaled(
            logical,
            lay.sync.x + @divTrunc(lay.sync.w, 2),
            lay.sync.y + @divTrunc(lay.sync.h, 2),
            .spindle,
            ink,
            icon_wide,
        );
    }

    const hold_resume = state.phase == .hold;
    const hold_label: []const u8 = if (hold_resume) "Feed Resume" else "Feed hold";
    const hold_icon: icons_phosphor.Id = if (hold_resume) .play else .pause;
    const hold_kind: widgets.ButtonKind = if (hold_resume) .feed_resume else .hold;
    paintStackedPill(logical, lay.hold, hold_label, hold_icon, hold_kind, theme, form.sampleWidget("act.hold.p", 0));

    paintQuickGrid(logical, lay.quick, theme, state, active, acc);

    {
        const home_st: widgets.ButtonState = if (form.sampleWidget("act.home.p", 0) > 0.05) .pressed else .enabled;
        const ink = widgets.drawButtonSurface(logical, lay.home, .home, home_st, theme, 0, 0, 0);
        const htw = font.textWidthStr("Home all", label_role);
        const icon_gap = tokens.Space.sm;
        const total_w = icon_wide + icon_gap + htw;
        const hx = lay.home.x + @divTrunc(lay.home.w - total_w, 2);
        const cy = lay.home.y + @divTrunc(lay.home.h, 2);
        icons_phosphor.drawCenteredScaled(logical, hx + @divTrunc(icon_wide, 2), cy, .house, ink, icon_wide);
        font.drawTextRole(
            logical,
            hx + icon_wide + icon_gap,
            lay.home.y + @divTrunc(lay.home.h - font.faceHeight(font.faceForRole(label_role)), 2),
            "Home all",
            ink,
            label_role,
        );
    }
}

fn paintStackedPill(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    label: []const u8,
    icon: icons_phosphor.Id,
    kind: widgets.ButtonKind,
    theme: tokens.Theme,
    press_t: f32,
) void {
    const st: widgets.ButtonState = if (press_t > 0.05) .pressed else .enabled;
    const ink = widgets.drawButtonSurface(logical, r, kind, st, theme, 0, 0, 0);
    // LVGL wide: ICON_SZ_32 + TITLE_M, stacked, pad_row XS.
    const lh = font.faceHeight(font.faceForRole(label_role));
    const stack = icon_wide + tokens.Space.xs + lh;
    const y0 = r.y + @divTrunc(r.h - stack, 2);
    icons_phosphor.drawCenteredScaled(
        logical,
        r.x + @divTrunc(r.w, 2),
        y0 + @divTrunc(icon_wide, 2),
        icon,
        ink,
        icon_wide,
    );
    const tw = font.textWidthStr(label, label_role);
    font.drawTextRole(
        logical,
        r.x + @divTrunc(r.w - tw, 2),
        y0 + icon_wide + tokens.Space.xs,
        label,
        ink,
        label_role,
    );
}

fn pickQuickLabelRole(lab: []const u8, max_w: i32) tokens.TypeRole {
    // Prefer LVGL BODY_M (`quick_label_role`); step down so longest line stays inside the tile.
    const candidates = [_]tokens.TypeRole{ quick_label_role, .body_s, .label_s };
    for (candidates) |r| {
        if (font.textWidthStr(lab, r) <= max_w) return r;
    }
    return .label_s;
}

fn paintQuickLabel(
    logical: *fb.LogicalFb,
    cell: geom.Rect,
    lab: []const u8,
    fg: color.Rgb565,
    role: tokens.TypeRole,
    y0: i32,
) void {
    const face = font.faceForRole(role);
    const lh = font.faceHeight(face);
    var line_start: usize = 0;
    var ly = y0;
    var i: usize = 0;
    while (i <= lab.len) : (i += 1) {
        if (i != lab.len and lab[i] != '\n') continue;
        const line = lab[line_start..i];
        const tw = font.textWidthStr(line, role);
        const tx = cell.x + @divTrunc(cell.w - tw, 2);
        font.drawTextRole(logical, tx, ly, line, fg, role);
        ly += lh;
        line_start = i + 1;
    }
}

fn paintQuickGrid(logical: *fb.LogicalFb, area: geom.Rect, theme: tokens.Theme, state: State, active: ActiveQuick, acc: AccView) void {
    if (active.n == 0 or area.h <= 0) return;
    var i: usize = 0;
    while (i < active.n) : (i += 1) {
        const slot = active.slots[i];
        const cell = quickCell(area, active.n, i);
        const id = state.quick[slot];
        const on = state.isQuickOn(slot, acc);
        var key_buf: [16]u8 = undefined;
        const key = std.fmt.bufPrint(&key_buf, "act.q.{d}", .{slot}) catch "act.q";
        const active_t = form.sampleWidgetBool(key, on);
        var press_key_buf: [20]u8 = undefined;
        const press_key = std.fmt.bufPrint(&press_key_buf, "act.q.{d}.p", .{slot}) catch "act.q.p";
        const pulse = form.sampleWidget(press_key, 0);
        const is_on = active_t > 0.5;
        // LVGL: surface_container_high / primary_container; SHAPE_XL; ICON 24/32; BODY_M.
        const bg = if (is_on) theme.primary_container else theme.elev(3);
        const fg = if (is_on) theme.primary else theme.on_surface_variant;
        widgets.fillRoundRect(logical, cell, quick_rad, bg);
        if (pulse > 0.05) {
            widgets.fillRoundRect(logical, cell, quick_rad, color.blendRgb565(bg, fg, 40));
        }
        const lab = id.faceLabel();
        const max_tw = @max(8, cell.w - quick_label_pad * 2);
        const role = pickQuickLabelRole(lab, max_tw);
        // Tall cells (1-btn / 2-btn / left of 3) use 32px icons like Cycle/Hold.
        const ic: i32 = if (cell.h >= 100) icon_wide else icon_quick;
        const text_h = font.textBlockHeight(lab, role);
        const stack = ic + tokens.Space.xs + text_h;
        const y0 = cell.y + @divTrunc(cell.h - stack, 2);
        icons_phosphor.drawCenteredScaled(
            logical,
            cell.x + @divTrunc(cell.w, 2),
            y0 + @divTrunc(ic, 2),
            id.icon(),
            fg,
            ic,
        );
        paintQuickLabel(logical, cell, lab, fg, role, y0 + ic + tokens.Space.xs);
    }
}

fn quickRowH(area: geom.Rect, n: u8) i32 {
    const rows: i32 = switch (State.clampQuickCount(n)) {
        1, 2 => 1,
        else => 2,
    };
    return @divTrunc(area.h - gap * @max(0, rows - 1), rows);
}

/// Adaptive layout by assign count (matches LVGL `ui_qbtn_build_grid`):
/// 1 = full area; 2 = side-by-side vertical; 3 = tall left + stacked right; 4 = 2×2.
pub fn quickCell(area: geom.Rect, n: u8, index: usize) geom.Rect {
    const i: i32 = @intCast(index);
    const nn = State.clampQuickCount(n);
    const rh = quickRowH(area, nn);
    return switch (nn) {
        1 => .{ .x = area.x, .y = area.y, .w = area.w, .h = area.h },
        2 => blk: {
            const cw = @divTrunc(area.w - gap, 2);
            break :blk .{
                .x = area.x + i * (cw + gap),
                .y = area.y,
                .w = cw,
                .h = area.h,
            };
        },
        3 => blk: {
            const cw = @divTrunc(area.w - gap, 2);
            const half_h = @divTrunc(area.h - gap, 2);
            if (i == 0) {
                // Large vertical on the left — full quick-area height.
                break :blk .{ .x = area.x, .y = area.y, .w = cw, .h = area.h };
            }
            // Two smaller stacked on the right (slot 1 top, slot 2 bottom).
            const row: i32 = i - 1;
            break :blk .{
                .x = area.x + cw + gap,
                .y = area.y + row * (half_h + gap),
                .w = cw,
                .h = half_h,
            };
        },
        else => blk: {
            const cw = @divTrunc(area.w - gap, 2);
            const col = @rem(i, 2);
            const row = @divTrunc(i, 2);
            break :blk .{
                .x = area.x + col * (cw + gap),
                .y = area.y + row * (rh + gap),
                .w = cw,
                .h = rh,
            };
        },
    };
}

pub fn hitTest(bounds: geom.Rect, state: State, x: i32, y: i32) Hit {
    if (!bounds.contains(x, y)) return .{};
    const active = state.collectActive();
    const lay = railLay(bounds, active.n);
    if (lay.cycle.contains(x, y)) return .{ .kind = .cycle };
    if (lay.sync.contains(x, y)) return .{ .kind = .sync };
    if (lay.hold.contains(x, y)) return .{ .kind = .hold };
    if (lay.home.contains(x, y)) return .{ .kind = .home };

    var i: usize = 0;
    while (i < active.n) : (i += 1) {
        if (quickCell(lay.quick, active.n, i).contains(x, y)) {
            return .{ .kind = .quick, .quick_index = active.slots[i] };
        }
    }
    return .{};
}

/// Settings: quick-button count 1|2|3|4.
pub fn paintQuickCountPicker(logical: *fb.LogicalFb, r: geom.Rect, theme: tokens.Theme, count: u8) void {
    font.drawText(logical, r.x, r.y - 22, "Quick buttons", theme.on_surface_variant, 1);
    const labels = [_][]const u8{ "1", "2", "3", "4" };
    const sel: usize = State.clampQuickCount(count) - min_quick;
    widgets.drawSegmented(logical, r, &labels, sel, theme);
}

pub fn hitQuickCountPicker(r: geom.Rect, x: i32, y: i32) ?u8 {
    if (!r.contains(x, y)) return null;
    const seg_w = @divTrunc(r.w, 4);
    const idx = @divTrunc(x - r.x, seg_w);
    if (idx < 0 or idx > 3) return null;
    return min_quick + @as(u8, @intCast(idx));
}

test "quick cell 1 fills area height" {
    const area: geom.Rect = .{ .x = 0, .y = 0, .w = 200, .h = 80 };
    const c = quickCell(area, 1, 0);
    try std.testing.expect(c.w == 200 and c.h == 80);
}

test "quick cell 2 side-by-side full height" {
    const area: geom.Rect = .{ .x = 10, .y = 20, .w = 200 + gap, .h = 160 };
    const c0 = quickCell(area, 2, 0);
    const c1 = quickCell(area, 2, 1);
    try std.testing.expectEqual(area.h, c0.h);
    try std.testing.expectEqual(area.h, c1.h);
    try std.testing.expectEqual(@as(i32, 100), c0.w);
    try std.testing.expectEqual(c0.x + c0.w + gap, c1.x);
}

test "quick cell 3 tall left and stacked right" {
    const area: geom.Rect = .{ .x = 0, .y = 0, .w = 200 + gap, .h = 160 + gap };
    const left = quickCell(area, 3, 0);
    const r0 = quickCell(area, 3, 1);
    const r1 = quickCell(area, 3, 2);
    try std.testing.expectEqual(area.h, left.h);
    try std.testing.expectEqual(@as(i32, 100), left.w);
    try std.testing.expectEqual(left.x + left.w + gap, r0.x);
    try std.testing.expectEqual(r0.x, r1.x);
    try std.testing.expectEqual(@as(i32, 80), r0.h);
    try std.testing.expectEqual(r0.y + r0.h + gap, r1.y);
    try std.testing.expect(r0.h + gap + r1.h == area.h);
}

test "quick cell 4 fills 2x2 area" {
    const area: geom.Rect = .{ .x = 0, .y = 0, .w = 212, .h = 140 };
    const c0 = quickCell(area, 4, 0);
    const c3 = quickCell(area, 4, 3);
    try std.testing.expect(c0.h == @divTrunc(140 - gap, 2));
    try std.testing.expect(c0.w > c0.h or c0.h <= 90);
    try std.testing.expect(c3.x > 0 and c3.y > 0);
}

test "off slots compact out of layout" {
    var st: State = .{
        .quick_count = 4,
        .quick = .{ .spindle_cw, .off, .fan, .zero_all },
    };
    const a = st.collectActive();
    try std.testing.expectEqual(@as(u8, 3), a.n);
    try std.testing.expectEqual(@as(u8, 0), a.slots[0]);
    try std.testing.expectEqual(@as(u8, 2), a.slots[1]);
    try std.testing.expectEqual(@as(u8, 3), a.slots[2]);

    const bounds: geom.Rect = .{ .x = 1000, .y = 80, .w = 260, .h = 600 };
    const lay = railLay(bounds, a.n);
    const left = quickCell(lay.quick, a.n, 0);
    try std.testing.expectEqual(lay.quick.h, left.h); // 3-btn: tall left

    // Hit on visual cell 0 maps to slot 0; visual cell 1 → slot 2 (skipped off).
    const hx = left.x + 8;
    const hy = left.y + 8;
    const hit0 = hitTest(bounds, st, hx, hy);
    try std.testing.expect(hit0.kind == .quick);
    try std.testing.expectEqual(@as(usize, 0), hit0.quick_index);

    const r0 = quickCell(lay.quick, a.n, 1);
    const hit1 = hitTest(bounds, st, r0.x + 8, r0.y + 8);
    try std.testing.expect(hit1.kind == .quick);
    try std.testing.expectEqual(@as(usize, 2), hit1.quick_index);
}

test "quick face labels fit narrow half-cell without bold title" {
    const half_w: i32 = 122; // ~rail 260 / 2 minus gap
    const max_tw = half_w - quick_label_pad * 2;
    const lab = QuickId.spindle_ccw.faceLabel();
    try std.testing.expect(std.mem.indexOfScalar(u8, lab, '\n') != null);
    const role = pickQuickLabelRole(lab, max_tw);
    try std.testing.expect(role != .title_m and role != .emph_title_m);
    try std.testing.expect(!role.emphasized());
    try std.testing.expect(font.textWidthStr(lab, role) <= max_tw);
}

test "rail matches LVGL fixed heights" {
    const bounds: geom.Rect = .{ .x = 0, .y = 100, .w = 260, .h = 500 };
    const lay = railLay(bounds, 4);
    try std.testing.expect(lay.cycle.h == 112);
    try std.testing.expect(lay.hold.h == 112);
    try std.testing.expect(lay.home.h == 96);
    try std.testing.expect(lay.sync.w == 72);
    try std.testing.expect(lay.cycle.y == bounds.y);
    try std.testing.expect(lay.home.y + lay.home.h == bounds.y + bounds.h);
    // Quick flexes into leftover between hold and home.
    try std.testing.expect(lay.quick.y == lay.hold.y + lay.hold.h + gap);
    try std.testing.expect(lay.quick.y + lay.quick.h + gap == lay.home.y);
}

test "rail gaps are 16dp" {
    try std.testing.expect(gap == tokens.Space.md);
}

test "assign active follows accessories bits" {
    const acc_on: AccView = .{ .accessories = Acc.spindle_cw | Acc.flood | Acc.mist, .connected = true };
    try std.testing.expect(isAssignActive(.spindle_cw, acc_on, false));
    try std.testing.expect(isAssignActive(.coolant, acc_on, false));
    try std.testing.expect(isAssignActive(.mist, acc_on, false));
    try std.testing.expect(!isAssignActive(.spindle_ccw, acc_on, false));
    try std.testing.expect(!isAssignActive(.spindle_cw, .{ .connected = false, .accessories = Acc.spindle_cw }, false));
    try std.testing.expect(isAssignActive(.fan, .{ .fan_on = true }, false));
    try std.testing.expect(isAssignActive(.led, .{}, true));
    try std.testing.expect(!isAssignActive(.zero_all, .{}, true));
}

test "QuickId catalog covers LVGL UI_QBTN assigns" {
    try std.testing.expect(@typeInfo(QuickId).@"enum".fields.len >= 14);
}

test "md3 action role pairs contrast" {
    const t = tokens.Theme.industrialTealDark();
    try std.testing.expect(color.contrastRatio(t.on_cycle.toHex(), t.cycle.toHex()) >= 2.5);
    try std.testing.expect(color.contrastRatio(t.on_hold.toHex(), t.hold.toHex()) >= 2.5);
    try std.testing.expect(color.contrastRatio(t.on_home.toHex(), t.home.toHex()) >= 2.5);
    try std.testing.expect(color.contrastRatio(t.on_stop.toHex(), t.stop.toHex()) >= 2.5);
    try std.testing.expect(color.contrastRatio(t.on_feed_resume.toHex(), t.feed_resume.toHex()) >= 2.5);
}
