//! DRO column widget — 3…6 axis cards (MD3 tonal cards + 8dp grid).
//! Two-row content: letter+ACTIVE | work+M | MM | HOME/ZERO tonal actions.

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const icons_phosphor = @import("icons_phosphor.zig");
const form = @import("settings_form.zig");

pub const min_axes: u8 = 2;
pub const max_axes: u8 = 6;

pub const axis_labels = [_][]const u8{ "X", "Y", "Z", "A", "B", "C" };

pub const State = struct {
    /// Visible axes (clamped to [min_axes, max_axes]).
    axis_count: u8 = 3,
    selected: usize = 0,
    unit_mm: bool = true,
    /// µm (mm×1000), indexed 0..axis_count-1.
    work_um: [max_axes]i32 = .{0} ** max_axes,
    mach_um: [max_axes]i32 = .{0} ** max_axes,
    /// 0→1 selection emphasis (engine spring).
    select_fx: f32 = 1,
    /// Pressed control for state-layer (cleared by engine on release).
    pressed: Hit = .{},
    /// Vertical scroll when axis stack taller than column (px).
    scroll_px: i32 = 0,

    pub fn clampCount(n: u8) u8 {
        return @max(min_axes, @min(max_axes, n));
    }

    pub fn setAxisCount(self: *State, n: u8) void {
        self.axis_count = clampCount(n);
        if (self.selected >= self.axis_count) self.selected = self.axis_count - 1;
        if (self.axis_count <= 4) {
            self.scroll_px = 0;
        } else {
            self.clampScroll(1 << 20);
        }
    }

    pub fn clampScroll(self: *State, bounds_h: i32) void {
        if (self.axis_count <= 4) {
            self.scroll_px = 0;
            return;
        }
        self.scroll_px = snapScrollPx(self.scroll_px, scrollMax(self.axis_count, bounds_h), self.axis_count);
    }

    pub fn nudgeScroll(self: *State, dy: i32, bounds_h: i32) void {
        if (self.axis_count <= 4) return;
        const stride = cardStride(self.axis_count);
        const max_s = scrollMax(self.axis_count, bounds_h);
        if (dy > 0) self.scroll_px -= stride;
        if (dy < 0) self.scroll_px += stride;
        if (self.scroll_px > max_s - @divTrunc(stride, 2)) self.scroll_px = max_s;
        if (self.scroll_px < @divTrunc(stride, 2)) self.scroll_px = 0;
        self.clampScroll(bounds_h);
    }

    pub fn ensureSelectedVisible(self: *State, bounds_h: i32) void {
        if (self.axis_count <= 4) return;
        const ch = preferredCardH(self.axis_count);
        const stride = cardStride(self.axis_count);
        const y0 = @as(i32, @intCast(self.selected)) * stride;
        const y1 = y0 + ch;
        if (y0 < self.scroll_px) self.scroll_px = y0;
        if (y1 > self.scroll_px + bounds_h) self.scroll_px = y1 - bounds_h;
        self.clampScroll(bounds_h);
    }
};

pub const HitKind = enum { none, select, home, zero };

pub const Hit = struct {
    kind: HitKind = .none,
    axis: usize = 0,
};

const gap: i32 = tokens.Space.sm;
const rad: i32 = tokens.Shape.card;
/// LVGL card pad = SPACE_MD (16).
const pad: i32 = tokens.Space.md;
const letter_col_w: i32 = 52; // fits Montserrat 44 axis letter + "Active" under
const btn_gap: i32 = tokens.Space.xs; // LVGL right_col pad_row XS
const pos_pad_l: i32 = tokens.Space.sm;
const row_gap: i32 = tokens.Space.xs;
const icon_px: i32 = 24; // MOD_UI_ICON_SZ_24
const action_rad: i32 = tokens.Shape.md; // MOD_UI_SHAPE_MD
const action_label_role: tokens.TypeRole = .body_s; // BODY_M = 14

fn compact(n: u8) bool {
    return State.clampCount(n) >= 5;
}

/// Longest Home/Zero label at body_s — drives compact button width.
fn actionLabelW() i32 {
    return font.textWidthStr("Home", .body_s);
}

fn actionContentW() i32 {
    // pad | icon24 | gap | label | pad — LVGL ICON_SZ_24.
    return tokens.Space.sm + icon_px + tokens.Space.xs + actionLabelW() + tokens.Space.sm;
}

fn btnW(n: u8) i32 {
    // LVGL: compact 80 / else 100.
    return if (compact(n)) 80 else 100;
}

fn btnH(n: u8) i32 {
    // LVGL: compact 40 / else 48.
    return if (compact(n)) 40 else 48;
}

pub fn preferredCardH(axis_count: u8) i32 {
    // LVGL min_card_h 128 / 112 compact.
    return if (compact(axis_count)) 112 else 128;
}

pub fn cardStride(axis_count: u8) i32 {
    return preferredCardH(axis_count) + gap;
}

pub fn contentHeight(axis_count: u8) i32 {
    const n: i32 = State.clampCount(axis_count);
    if (n <= 0) return 0;
    return n * preferredCardH(axis_count) + (n - 1) * gap;
}

/// LVGL scrolls when axis_count > 4.
pub fn scrollMax(axis_count: u8, bounds_h: i32) i32 {
    if (State.clampCount(axis_count) <= 4) return 0;
    return @max(0, contentHeight(axis_count) - bounds_h);
}

fn snapScrollPx(scroll_px: i32, max_s: i32, axis_count: u8) i32 {
    const stride = cardStride(axis_count);
    if (stride <= 0 or max_s <= 0) return std.math.clamp(scroll_px, 0, max_s);
    if (scroll_px <= 0) return 0;
    if (scroll_px >= max_s) return max_s;
    const snapped = @divTrunc(scroll_px + @divTrunc(stride, 2), stride) * stride;
    return std.math.clamp(snapped, 0, max_s);
}

pub fn cardHeightFor(bounds_h: i32, axis_count: u8) i32 {
    const n = State.clampCount(axis_count);
    if (n > 4) return preferredCardH(n);
    return rowHeight(bounds_h, n);
}

/// Bounds = full DRO column. Scroll when >4 axes; else cards size to fit.
pub fn paint(logical: *fb.LogicalFb, bounds: geom.Rect, theme: tokens.Theme, state: State) void {
    const n = State.clampCount(state.axis_count);
    const card_h = cardHeightFor(bounds.h, n);
    const scroll = if (n > 4)
        snapScrollPx(state.scroll_px, scrollMax(n, bounds.h), n)
    else
        @as(i32, 0);

    const prev_clip = logical.clip;
    logical.setClip(bounds);
    defer logical.setClip(prev_clip);

    if (scroll != 0 or n > 4) {
        logical.fillRect(bounds, theme.surface);
    }

    var i: usize = 0;
    while (i < n) : (i += 1) {
        const card: geom.Rect = .{
            .x = bounds.x,
            .y = bounds.y + @as(i32, @intCast(i)) * (card_h + gap) - scroll,
            .w = bounds.w,
            .h = card_h,
        };
        const visible = geom.Rect.intersect(card, bounds);
        if (visible.isEmpty()) continue;
        logical.setClip(if (prev_clip) |pc| geom.Rect.intersect(visible, pc) else visible);
        paintRow(logical, card, theme, state, i);
    }
}

pub fn rowHeight(total_h: i32, axis_count: u8) i32 {
    const n: i32 = State.clampCount(axis_count);
    const gaps = gap * @max(0, n - 1);
    return @max(preferredCardH(axis_count), @divTrunc(total_h - gaps, n));
}

fn paintRow(logical: *fb.LogicalFb, card: geom.Rect, theme: tokens.Theme, state: State, axis: usize) void {
    const selected = axis == state.selected;
    const fx = if (selected) @max(0, @min(1, state.select_fx)) else 0;
    // Inset ring stays inside card — outward ring was clipped by column scissor (L/R missing).
    const ring: i32 = if (selected) 2 + @as(i32, @intFromFloat(fx * 2)) else 0;

    if (selected) {
        widgets.fillRoundRect(logical, card, rad, theme.primary);
        const inner: geom.Rect = .{
            .x = card.x + ring,
            .y = card.y + ring,
            .w = card.w - ring * 2,
            .h = card.h - ring * 2,
        };
        if (inner.w > 0 and inner.h > 0) {
            widgets.fillRoundRect(logical, inner, @max(tokens.Shape.xs, rad - ring), theme.secondary_container);
        }
    } else {
        widgets.fillRoundRect(logical, card, rad, theme.elev(2));
    }

    if (state.pressed.kind != .none and state.pressed.axis == axis) {
        widgets.drawStateLayer(logical, card, rad, theme, tokens.StateLayer.press);
    }

    const on = if (selected) theme.on_secondary_container else theme.on_surface;
    const on_var = if (selected) theme.on_secondary_container else theme.on_surface_variant;

    var wbuf: [24]u8 = undefined;
    const work = formatSignedMm3(&wbuf, state.work_um[axis]);
    var mbuf: [32]u8 = undefined;
    const mach = formatMachMm3(&mbuf, state.mach_um[axis]);
    var mline: [40]u8 = undefined;
    const ml = std.fmt.bufPrint(&mline, "M: {s}", .{mach}) catch mach;

    const body: geom.Rect = .{
        .x = card.x + ring,
        .y = card.y + ring,
        .w = card.w - ring * 2,
        .h = card.h - ring * 2,
    };

    // Work: Montserrat Regular ~32 (ui36) — Bold 36 overflowed MM lane.
    const work_h = font.faceHeight(.ui36);
    const mach_h = font.faceHeight(.ui22);
    const block_h = work_h + row_gap + mach_h;
    const top = body.y + @divTrunc(body.h - block_h, 2);
    const work_y = top;
    const mach_y = work_y + work_h + row_gap;

    const n = State.clampCount(state.axis_count);
    const letter = axis_labels[axis];
    const letter_x = body.x + pad;
    const value_x = body.x + pad + letter_col_w + pos_pad_l;
    const letter_h = font.faceHeight(.dro40);
    // Letter column: axis glyph + Active under (LVGL flex column).
    const letter_y = body.y + @divTrunc(body.h - (letter_h + tokens.Space.xs + font.faceHeight(font.faceForRole(.label_m))), 2);
    font.drawTextFace(logical, letter_x, letter_y, letter, on, .dro40);
    if (selected) {
        const letter_w = font.textWidthFace(letter, .dro40);
        const active_w = font.textWidthStr("Active", .label_m);
        const active_x = letter_x + @divTrunc(letter_w - active_w, 2);
        font.drawTextRoleTracked(logical, active_x, letter_y + letter_h + tokens.Space.xs, "Active", theme.primary, .label_m, 1, false);
    }

    const home_r, const zero_r = actionRects(body, n);
    // Unit sits in right column top row (beside HOME). Tracking=2 matches draw.
    const unit = if (state.unit_mm) "MM" else "IN";
    const unit_track: i32 = 2;
    const unit_w = font.textWidthStr(unit, .label_m) + unit_track * @as(i32, @intCast(unit.len -| 1));
    const unit_h = font.faceHeight(font.faceForRole(.label_m));
    const unit_x = home_r.x - unit_w - tokens.Space.sm;
    // LVGL: pos_col flex-grow stops at right_col — clip work/mach so digits never cover MM/IN.
    const lane_r: i32 = unit_x - tokens.Space.sm;
    const lane_w = @max(0, lane_r - value_x);
    if (lane_w > 0) {
        const lane: geom.Rect = .{ .x = value_x, .y = body.y, .w = lane_w, .h = body.h };
        const prev_clip = logical.clip;
        logical.setClip(if (prev_clip) |pc| geom.Rect.intersect(lane, pc) else lane);
        font.drawTextFace(logical, value_x, work_y, work, on, .ui36);
        font.drawTextRole(logical, value_x, mach_y, ml, on_var, .title_m);
        logical.setClip(prev_clip);
    }

    font.drawTextRoleTracked(
        logical,
        unit_x,
        home_r.y + @divTrunc(home_r.h - unit_h, 2),
        unit,
        on_var,
        .label_m,
        unit_track,
        false,
    );

    const home_pressed = state.pressed.kind == .home and state.pressed.axis == axis;
    const zero_pressed = state.pressed.kind == .zero and state.pressed.axis == axis;
    var home_key_buf: [16]u8 = undefined;
    const home_key = std.fmt.bufPrint(&home_key_buf, "dro.home.{d}", .{axis}) catch "dro.home";
    var zero_key_buf: [16]u8 = undefined;
    const zero_key = std.fmt.bufPrint(&zero_key_buf, "dro.zero.{d}", .{axis}) catch "dro.zero";
    const home_t = @max(if (home_pressed) @as(f32, 1) else 0, form.sampleWidget(home_key, 0));
    const zero_t = @max(if (zero_pressed) @as(f32, 1) else 0, form.sampleWidget(zero_key, 0));
    drawTonalAction(logical, home_r, .house, "Home", theme, home_t);
    drawTonalAction(logical, zero_r, .zero, "Zero", theme, zero_t);
}

fn drawTonalAction(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    icon: icons_phosphor.Id,
    label: []const u8,
    theme: tokens.Theme,
    press_t: f32,
) void {
    // LVGL dro_action_btn: surface_container_high, SHAPE_MD, chrome icon 24, BODY_M.
    widgets.fillRoundRect(logical, r, action_rad, theme.elev(3));
    if (press_t > 0.05) {
        widgets.fillRoundRect(logical, r, action_rad, theme.secondary_container);
    }
    const fg = theme.on_surface;
    const chrome = theme.on_surface_variant;
    const ix = r.x + tokens.Space.sm;
    icons_phosphor.drawCenteredScaled(
        logical,
        ix + @divTrunc(icon_px, 2),
        r.y + @divTrunc(r.h, 2),
        icon,
        chrome,
        icon_px,
    );
    const ty = r.y + @divTrunc(r.h - font.faceHeight(font.faceForRole(action_label_role)), 2);
    font.drawTextRole(logical, ix + icon_px + tokens.Space.xs, ty, label, fg, action_label_role);
}

pub fn formatSignedMm3(buf: []u8, um: i32) []const u8 {
    const neg = um < 0;
    const abs_v: u32 = @intCast(if (neg) -um else um);
    const whole = abs_v / 1000;
    const frac = abs_v % 1000;
    // Zig 0.16: `{d:0>3}` on i32 inserts '+'; use u32 after we own the sign.
    if (neg) {
        return std.fmt.bufPrint(buf, "-{d}.{d:0>3}", .{ whole, frac }) catch "0.000";
    }
    return std.fmt.bufPrint(buf, "+{d}.{d:0>3}", .{ whole, frac }) catch "+0.000";
}

/// Machine coords: keep '-' only (no leading '+').
pub fn formatMachMm3(buf: []u8, um: i32) []const u8 {
    const neg = um < 0;
    const abs_v: u32 = @intCast(if (neg) -um else um);
    const whole = abs_v / 1000;
    const frac = abs_v % 1000;
    if (neg) {
        return std.fmt.bufPrint(buf, "-{d}.{d:0>3}", .{ whole, frac }) catch "0.000";
    }
    return std.fmt.bufPrint(buf, "{d}.{d:0>3}", .{ whole, frac }) catch "0.000";
}

pub fn hitTest(bounds: geom.Rect, state: State, x: i32, y: i32) Hit {
    // Caller should strict-gate panel bounds; still reject padded false hits here.
    if (!bounds.containsStrict(x, y)) return .{};
    const n = State.clampCount(state.axis_count);
    const card_h = cardHeightFor(bounds.h, n);
    const scroll = if (n > 4)
        snapScrollPx(state.scroll_px, scrollMax(n, bounds.h), n)
    else
        @as(i32, 0);
    const local_y = y - bounds.y + scroll;
    if (local_y < 0) return .{};
    const stride = card_h + gap;
    const idx_i = @divTrunc(local_y, stride);
    if (idx_i < 0 or idx_i >= n) return .{};
    if (@rem(local_y, stride) >= card_h) return .{};
    const axis: usize = @intCast(idx_i);
    const card: geom.Rect = .{
        .x = bounds.x,
        .y = bounds.y + @as(i32, @intCast(axis)) * stride - scroll,
        .w = bounds.w,
        .h = card_h,
    };
    if (geom.Rect.intersect(card, bounds).isEmpty()) return .{};
    const selected = axis == state.selected;
    const fx = if (selected) @max(0, @min(1, state.select_fx)) else 0;
    const ring: i32 = if (selected) 2 + @as(i32, @intFromFloat(fx * 2)) else 0;
    const body: geom.Rect = .{
        .x = card.x + ring,
        .y = card.y + ring,
        .w = card.w - ring * 2,
        .h = card.h - ring * 2,
    };
    const home_r, const zero_r = actionRects(body, n);
    // Expand hits to ≥48dp — compact cards shrink paint to 40px.
    if (touchExpandAction(home_r).contains(x, y)) return .{ .kind = .home, .axis = axis };
    if (touchExpandAction(zero_r).contains(x, y)) return .{ .kind = .zero, .axis = axis };
    return .{ .kind = .select, .axis = axis };
}

fn touchExpandAction(r: geom.Rect) geom.Rect {
    const min_h: i32 = tokens.ButtonSize.m.height(); // 48
    const pad_y: i32 = if (r.h >= min_h) 2 else @divTrunc(min_h - r.h + 1, 2);
    const pad_x: i32 = 4;
    return .{
        .x = r.x - pad_x,
        .y = r.y - pad_y,
        .w = r.w + pad_x * 2,
        .h = r.h + pad_y * 2,
    };
}

fn actionRects(card: geom.Rect, axis_count: u8) struct { geom.Rect, geom.Rect } {
    const bw = btnW(axis_count);
    var bh = btnH(axis_count);
    const need = bh * 2 + btn_gap + tokens.Space.sm;
    if (card.h < need) {
        bh = @max(tokens.ButtonSize.xs.height(), @divTrunc(card.h - btn_gap - tokens.Space.sm, 2));
    }
    const pair_h = bh * 2 + btn_gap;
    const bx = card.x + card.w - bw - pad;
    const by = card.y + @divTrunc(card.h - pair_h, 2);
    return .{
        .{ .x = bx, .y = by, .w = bw, .h = bh },
        .{ .x = bx, .y = by + bh + btn_gap, .w = bw, .h = bh },
    };
}

/// Settings control: "Visible axes" segmented 2|3|4|5|6.
pub fn paintAxisCountPicker(logical: *fb.LogicalFb, r: geom.Rect, theme: tokens.Theme, count: u8) void {
    font.drawTextRole(logical, r.x, r.y - 22, "Visible axes", theme.on_surface_variant, .label_m);
    const labels = [_][]const u8{ "2", "3", "4", "5", "6" };
    const sel: usize = if (count >= min_axes and count <= max_axes) count - min_axes else 1;
    widgets.drawSegmented(logical, r, &labels, sel, theme);
}

pub fn hitAxisCountPicker(r: geom.Rect, x: i32, y: i32) ?u8 {
    if (!r.contains(x, y)) return null;
    const seg_w = @divTrunc(r.w, 5);
    const idx = @divTrunc(x - r.x, seg_w);
    if (idx < 0 or idx > 4) return null;
    return min_axes + @as(u8, @intCast(idx));
}

test "row height shrinks with more axes" {
    const h3 = rowHeight(600, 3);
    const h6 = rowHeight(600, 6);
    try std.testing.expect(h3 > h6);
}

test "touch targets meet 48dp" {
    try std.testing.expect(btnH(3) >= tokens.Logical.touch_min);
    try std.testing.expect(preferredCardH(3) >= btnH(3) * 2 + btn_gap);
}

test "Home/Zero button sizes match LVGL compact/full" {
    // LVGL dro_layout_metrics: compact 80×40, else 100×48.
    try std.testing.expectEqual(@as(i32, 80), btnW(5));
    try std.testing.expectEqual(@as(i32, 40), btnH(5));
    try std.testing.expectEqual(@as(i32, 100), btnW(3));
    try std.testing.expectEqual(@as(i32, 48), btnH(3));
    try std.testing.expect(btnW(3) >= actionContentW());
}

test "signed format always has sign" {
    var buf: [24]u8 = undefined;
    const p = formatSignedMm3(&buf, 1250);
    try std.testing.expect(p[0] == '+');
    var buf2: [24]u8 = undefined;
    const n = formatSignedMm3(&buf2, -500);
    try std.testing.expect(n[0] == '-');
}

test "mach format omits leading plus" {
    var buf: [24]u8 = undefined;
    const p = formatMachMm3(&buf, 1250);
    try std.testing.expect(p[0] != '+');
    var buf2: [24]u8 = undefined;
    const n = formatMachMm3(&buf2, -500);
    try std.testing.expect(n[0] == '-');
}

test "negative um has no plus after decimal" {
    var buf: [24]u8 = undefined;
    const s = formatSignedMm3(&buf, -910585);
    try std.testing.expectEqualStrings("-910.585", s);
    var buf2: [24]u8 = undefined;
    const m = formatMachMm3(&buf2, -910585);
    try std.testing.expectEqualStrings("-910.585", m);
}

test "scroll exposes overflow axes" {
    try std.testing.expect(scrollMax(4, preferredCardH(4)) == 0);
    try std.testing.expect(scrollMax(5, preferredCardH(5) * 2) > 0);
    const view_h = preferredCardH(6) * 2 + gap;
    const max_s = scrollMax(6, view_h);
    try std.testing.expect(max_s == contentHeight(6) - view_h);
    var st: State = .{ .axis_count = 6, .scroll_px = 0 };
    st.nudgeScroll(-1, view_h);
    try std.testing.expect(st.scroll_px > 0);
    st.scroll_px = max_s;
    st.clampScroll(view_h);
    try std.testing.expect(st.scroll_px == max_s);
    const c_y = 5 * cardStride(6) - st.scroll_px;
    try std.testing.expect(c_y >= 0);
    try std.testing.expect(c_y + preferredCardH(6) <= view_h);
    st.setAxisCount(4);
    try std.testing.expect(st.scroll_px == 0);
}

test "lvgl font roles map work/mach/letter" {
    try std.testing.expect(font.faceForRole(.display_m) == .ui36);
    try std.testing.expect(font.faceForRole(.title_m) == .ui22);
    try std.testing.expect(font.faceForRole(.display_l) == .dro40);
    try std.testing.expect(font.faceForRole(.body_m) == .ui16);
    try std.testing.expect(font.faceForRole(.display_s) == .ui22);
    try std.testing.expectEqual(@as(i32, 100), btnW(3));
    try std.testing.expectEqual(@as(i32, 80), btnW(5));
}

test "value lane reserved left of unit" {
    const body: geom.Rect = .{ .x = 0, .y = 0, .w = 380, .h = 128 };
    const home_r, _ = actionRects(body, 3);
    const unit_w = font.textWidthStr("MM", .label_m) + 2;
    const unit_x = home_r.x - unit_w - tokens.Space.sm;
    const value_x = body.x + pad + letter_col_w + pos_pad_l;
    const lane = unit_x - tokens.Space.sm - value_x;
    try std.testing.expect(lane > 0);
    // Typical DRO work string must fit without mid-glyph clip (Regular 32 bake).
    try std.testing.expect(font.textWidthFace("-910.585", .ui36) <= lane);
}
