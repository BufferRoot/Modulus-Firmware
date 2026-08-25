//! Modulus System settings — modal two-pane (matches Tab5 LVGL reference).
//! Flat preference list + inset dividers; search lives in the left rail.

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const icons_phosphor = @import("icons_phosphor.zig");
const color = @import("color.zig");
const motion = @import("motion.zig");
const expr = @import("widgets_expressive.zig");

/// Bound for one settings paint pass — Engine sets before content paint.
var bound_phys: ?*const motion.Physics = null;
var bound_pool: ?*motion.WidgetPool = null;
var bound_sw_icons: bool = true;
var bound_advanced: bool = false;
/// Last Essentials/Advanced toggle row (engine hit-tests).
pub var mode_toggle_hit: geom.Rect = .{};

pub fn bindWidgetMotion(phys: *const motion.Physics, pool: *motion.WidgetPool) void {
    bound_phys = phys;
    bound_pool = pool;
}

pub fn unbindWidgetMotion() void {
    bound_phys = null;
    bound_pool = null;
}

pub fn bindSwitchIcons(icons: bool) void {
    bound_sw_icons = icons;
}

pub fn bindAdvanced(advanced: bool) void {
    bound_advanced = advanced;
    mode_toggle_hit = .{};
}

pub fn isAdvanced() bool {
    return bound_advanced;
}

/// Essentials ↔ Advanced — first control on every settings tab.
pub fn paintModeToggle(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    advanced: bool,
) geom.Rect {
    paintSection(logical, theme, cur, scroll, "View");
    paintNote(logical, theme, cur, scroll, if (advanced)
        "Showing all controls"
    else
        "Common controls only");
    const r = paintToggle(logical, theme, cur, scroll, "Advanced settings", advanced);
    mode_toggle_hit = r;
    return r;
}

fn switchT(label: []const u8, on: bool) f32 {
    if (bound_pool) |pool| {
        if (bound_phys) |phys| return pool.sampleBool(phys.*, motion.hashLabel(label), on);
    }
    return if (on) 1 else 0;
}

fn sliderT(label: []const u8, norm: f32) f32 {
    // Finger-synced — spring lag made drag feel choppy vs Jog. Instant track.
    _ = label;
    return std.math.clamp(norm, 0, 1);
}

fn segmentT(label: []const u8, selected: usize) f32 {
    // Discrete like Jog — spring pill thrash felt choppy on multi-tap.
    _ = label;
    return @floatFromInt(selected);
}

/// Unbounded spring sample (segment index, pulse 0..1, progress). Do not clamp —
/// jog/catalog group indices are >1; clamping hid selection past slot 0.
pub fn sampleWidget(label: []const u8, target: f32) f32 {
    if (bound_pool) |pool| {
        if (bound_phys) |phys| return pool.sample(phys.*, motion.hashLabel(label), target);
    }
    return target;
}

pub fn sampleWidgetBool(label: []const u8, on: bool) f32 {
    return switchT(label, on);
}

pub fn pulseWidget(label: []const u8) void {
    if (bound_pool) |pool| {
        if (bound_phys) |phys| pool.pulse(phys.*, motion.hashLabel(label));
    }
}

pub const win_x: i32 = 40;
pub const win_y: i32 = 32;
pub const win_w: i32 = 1200;
pub const win_h: i32 = 656;
pub const title_h: i32 = 52;
pub const search_h: i32 = tokens.Logical.touch_min; // MD3 ≥48dp touch
pub const cat_item_h: i32 = 52;
pub const content_top: i32 = win_y + title_h;
pub const content_bottom: i32 = win_y + win_h - 12;
pub const row_h: i32 = 56;
pub const section_h: i32 = 40;
pub const note_h: i32 = 26;

/// Live shell geometry — call `syncLayout` before paint/hit (rail vs compact).
pub var rail_w: i32 = 300;
pub var cat_list_top: i32 = win_y + title_h + 12 + search_h + 12;
pub var content_x: i32 = win_x + 300 + 28;
pub var content_w: i32 = 816;

/// MD3: medium+ → nav rail; compact → single-pane (hub list / detail content).
pub fn syncLayout(use_rail: bool) void {
    if (use_rail) {
        rail_w = 300;
        content_x = win_x + rail_w + 28;
        const avail = win_w - rail_w - 56;
        const max = tokens.WindowSizeClass.large.contentMaxWidth() - tokens.Space.lg * 2;
        content_w = @min(avail, max);
    } else {
        // Dropping the rail frees 300 px, so size the column to the dialog we
        // actually have. Forcing MD3 `compact` here left half the window empty.
        rail_w = 0;
        const avail = win_w - tokens.Space.lg * 2;
        const cls = tokens.WindowSizeClass.fromWidth(avail);
        content_w = @min(avail, cls.contentMaxWidth() - cls.margin() * 2);
        content_x = win_x + @divTrunc(win_w - content_w, 2);
    }
    cat_list_top = win_y + title_h + 12 + search_h + 12;
}

pub fn useRail() bool {
    return rail_w > 0;
}

pub const Cursor = struct {
    y: i32 = 0,
};

pub fn windowRect() geom.Rect {
    return .{ .x = win_x, .y = win_y, .w = win_w, .h = win_h };
}

pub fn titleBarRect() geom.Rect {
    return .{ .x = win_x, .y = win_y, .w = win_w, .h = title_h };
}

pub fn railRect() geom.Rect {
    if (rail_w <= 0) return .{};
    return .{ .x = win_x, .y = win_y + title_h, .w = rail_w, .h = win_h - title_h };
}

pub fn searchRect() geom.Rect {
    const w = if (rail_w > 0) rail_w - 32 else win_w - 32;
    return .{
        .x = win_x + 16,
        .y = win_y + title_h + 12,
        .w = w,
        .h = search_h,
    };
}

pub fn closeHitRect() geom.Rect {
    return tokens.Logical.touchHit(win_x + win_w - 28, win_y + @divTrunc(title_h, 2));
}

/// Compact detail: back control in title (left of gear slot).
pub fn backHitRect() geom.Rect {
    return .{ .x = win_x + 8, .y = win_y + 4, .w = tokens.Logical.touch_min, .h = title_h - 8 };
}

/// Right pane (or full body when rail_w=0).
pub fn contentPaneRect() geom.Rect {
    return .{
        .x = win_x + rail_w,
        .y = win_y + title_h,
        .w = win_w - rail_w,
        .h = win_h - title_h,
    };
}

/// Category list band (rail or compact hub full width).
pub fn categoryListWidth() i32 {
    return if (rail_w > 0) rail_w else win_w;
}

pub fn contentRect() geom.Rect {
    return .{
        .x = content_x,
        .y = content_top,
        .w = content_w,
        .h = content_bottom - content_top,
    };
}

pub fn contentViewH() i32 {
    return content_bottom - content_top;
}

fn rowY(cur_y: i32, scroll: i32) i32 {
    return content_top + cur_y - scroll;
}

fn visibleRow(logical: *const fb.LogicalFb, y: i32, h: i32) bool {
    // Full row must fit in content pane — partial tops/bottoms leave divider ghosts.
    if (y < content_top) return false;
    if (y + h > content_bottom) return false;
    if (h <= 0) return false;
    // Damage-band clip (settings morph): skip draw when the row misses the clip.
    if (logical.clip) |cl| {
        return !geom.Rect.intersect(cl, .{ .x = content_x, .y = y, .w = content_w, .h = h }).isEmpty();
    }
    return true;
}

fn paintRowDivider(logical: *fb.LogicalFb, r: geom.Rect, theme: tokens.Theme) void {
    // MD3 list: inset divider under label column (keep trailing control clear).
    const inset = tokens.Space.md;
    const w = @max(0, r.w - inset);
    if (w <= 0) return;
    logical.fillRect(.{ .x = r.x + inset, .y = r.y + r.h - 1, .w = w, .h = 1 }, theme.outline_variant);
}

pub fn paintSection(logical: *fb.LogicalFb, theme: tokens.Theme, cur: *Cursor, scroll: i32, title: []const u8) void {
    const y = rowY(cur.y, scroll);
    cur.y += section_h;
    if (!visibleRow(logical, y, section_h)) return;
    font.drawTextRole(logical, content_x, y + 14, title, theme.on_surface_variant, .title_s);
}

pub fn paintNote(logical: *fb.LogicalFb, theme: tokens.Theme, cur: *Cursor, scroll: i32, text: []const u8) void {
    const y = rowY(cur.y, scroll);
    cur.y += note_h;
    if (!visibleRow(logical, y, note_h)) return;
    font.drawTextRole(logical, content_x, y + 4, text, theme.on_surface_variant, .body_s);
}

pub fn paintToggle(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    label: []const u8,
    on: bool,
) geom.Rect {
    return paintToggleState(logical, theme, cur, scroll, label, on, true);
}

pub fn paintToggleState(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    label: []const u8,
    on: bool,
    enabled: bool,
) geom.Rect {
    const y = rowY(cur.y, scroll);
    const r: geom.Rect = .{ .x = content_x, .y = y, .w = content_w, .h = row_h };
    cur.y += row_h;
    if (!visibleRow(logical, y, row_h)) return r;
    const fg = if (enabled) theme.on_surface else theme.on_surface_variant;
    font.drawTextRole(logical, r.x, r.y + 18, label, fg, .body_l);
    const sx = widgets.switchTrailingX(r.x, r.w);
    const sy = r.y + @divTrunc(r.h - widgets.switch_h, 2);
    widgets.drawSwitch(logical, sx, sy, switchT(label, on), theme, bound_sw_icons, enabled);
    paintRowDivider(logical, r, theme);
    return r;
}

pub fn paintSegment(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    label: []const u8,
    labels: []const []const u8,
    selected: usize,
) geom.Rect {
    const y = rowY(cur.y, scroll);
    const r: geom.Rect = .{ .x = content_x, .y = y, .w = content_w, .h = row_h };
    cur.y += row_h;
    if (!visibleRow(logical, y, row_h)) return r;
    font.drawTextRole(logical, r.x, r.y + 18, label, theme.on_surface, .body_l);
    const seg = segmentControlRect(r);
    widgets.drawSegmentedF(logical, seg, labels, segmentT(label, selected), theme);
    paintRowDivider(logical, r, theme);
    return r;
}

pub fn segmentControlRect(row: geom.Rect) geom.Rect {
    const seg_w: i32 = @min(420, @divTrunc(row.w * 55, 100));
    return .{
        .x = row.x + row.w - seg_w,
        .y = row.y + @divTrunc(row.h - 40, 2),
        .w = seg_w,
        .h = 40,
    };
}

pub fn segmentIndexAt(row: geom.Rect, n: usize, x: i32, y: i32) ?usize {
    const seg = segmentControlRect(row);
    if (!seg.contains(x, y) or n == 0) return null;
    const sw = @divTrunc(seg.w, @as(i32, @intCast(n)));
    const idx = @divTrunc(x - seg.x, sw);
    if (idx < 0 or idx >= @as(i32, @intCast(n))) return null;
    return @intCast(idx);
}

pub fn paintSlider(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    label: []const u8,
    value: u32,
    vmin: u32,
    vmax: u32,
) geom.Rect {
    return paintSliderUnit(logical, theme, cur, scroll, label, value, vmin, vmax, "");
}

pub fn paintSliderUnit(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    label: []const u8,
    value: u32,
    vmin: u32,
    vmax: u32,
    unit: []const u8,
) geom.Rect {
    const y = rowY(cur.y, scroll);
    const r: geom.Rect = .{ .x = content_x, .y = y, .w = content_w, .h = row_h };
    cur.y += row_h;
    if (!visibleRow(logical, y, row_h)) return r;
    font.drawTextRole(logical, r.x, r.y + 18, label, theme.on_surface, .body_l);
    var vbuf: [28]u8 = undefined;
    const vs = if (unit.len == 0)
        stdFmt(&vbuf, value)
    else
        (std.fmt.bufPrint(&vbuf, "{d} {s}", .{ value, unit }) catch stdFmt(&vbuf, value));
    const vtw = font.textWidthStr(vs, .label_l);
    font.drawTextRole(logical, r.x + r.w - vtw, r.y + 18, vs, theme.primary, .label_l);

    const tr = sliderTrackRect(r);
    if (tr.w > 40) {
        const span = @max(1, vmax -| vmin);
        const norm = @min(1.0, @as(f32, @floatFromInt(value -| vmin)) / @as(f32, @floatFromInt(span)));
        const t = sliderT(label, norm);
        // Discrete ticks when span fits a short stop set (encoder-style ints).
        const ticks: u32 = if (span >= 1 and span <= 16) span + 1 else 0;
        widgets.drawContinuousSlider(logical, tr, t, theme, ticks);
    }
    paintRowDivider(logical, r, theme);
    return r;
}

/// Track geometry for drag hit-testing (matches paintSlider).
pub fn sliderTrackRect(row: geom.Rect) geom.Rect {
    return widgets.sliderTrackInRow(row);
}

/// Right-side value label — tap opens number pad.
pub fn sliderValueHit(row: geom.Rect, x: i32, y: i32) bool {
    if (!row.contains(x, y)) return false;
    return x >= row.x + row.w - widgets.slider_value_w;
}

/// Finger drag: whole row except value label (tap value → number pad).
pub fn sliderDragHit(row: geom.Rect, x: i32, y: i32) bool {
    if (!row.contains(x, y)) return false;
    if (sliderValueHit(row, x, y)) return false;
    return true;
}

pub fn sliderValueAt(row: geom.Rect, vmin: u32, vmax: u32, x: i32) u32 {
    const tr = sliderTrackRect(row);
    const track_w = @max(1, tr.w);
    const local = std.math.clamp(x - tr.x, 0, track_w);
    const span = vmax -| vmin;
    const t = @as(f32, @floatFromInt(local)) / @as(f32, @floatFromInt(track_w));
    // Round to nearest; small spans stay step-1 discrete.
    const raw = @as(u32, @intFromFloat(t * @as(f32, @floatFromInt(span)) + 0.5));
    return vmin + @min(span, raw);
}

pub fn paintDropdown(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    label: []const u8,
    value: []const u8,
) geom.Rect {
    return paintDropdownState(logical, theme, cur, scroll, label, value, true);
}

pub fn paintDropdownState(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    label: []const u8,
    value: []const u8,
    enabled: bool,
) geom.Rect {
    const y = rowY(cur.y, scroll);
    const r: geom.Rect = .{ .x = content_x, .y = y, .w = content_w, .h = row_h };
    cur.y += row_h;
    if (!visibleRow(logical, y, row_h)) return r;
    const fg = if (enabled) theme.on_surface else theme.on_surface_variant;
    font.drawTextRole(logical, r.x + tokens.Space.sm, r.y + 18, label, fg, .body_l);
    const tw = font.textWidthStr(value, .label_l);
    const box_h: i32 = 40;
    const box_w = @max(120, tw + 48);
    const box: geom.Rect = .{
        .x = r.x + r.w - box_w,
        .y = r.y + @divTrunc(r.h - box_h, 2),
        .w = box_w,
        .h = box_h,
    };
    // Menu trigger: outlined field chrome; value + chevron painted with trailing room.
    widgets.drawOutlinedTextField(logical, box, "", "", false, enabled, false, theme);
    font.drawTextRole(logical, box.x + tokens.Space.md, box.y + @divTrunc(box_h - font.faceHeight(font.faceForRole(.label_l)), 2), value, fg, .label_l);
    widgets.drawChevronDown(logical, box.x + box.w - 16, box.y + @divTrunc(box.h, 2), 5, theme.on_surface_variant);
    paintRowDivider(logical, r, theme);
    return r;
}

/// Two-line list item (MD3): primary + supporting text; trailing switch optional.
pub fn paintTwoLine(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    title: []const u8,
    support: []const u8,
    toggle: ?bool,
) geom.Rect {
    const h: i32 = 72;
    const y = rowY(cur.y, scroll);
    const r: geom.Rect = .{ .x = content_x, .y = y, .w = content_w, .h = h };
    cur.y += h;
    if (!visibleRow(logical, y, h)) return r;
    font.drawTextRole(logical, r.x, r.y + 14, title, theme.on_surface, .body_l);
    font.drawTextRole(logical, r.x, r.y + 40, support, theme.on_surface_variant, .body_s);
    if (toggle) |on| {
        const sx = widgets.switchTrailingX(r.x, r.w);
        const sy = r.y + @divTrunc(h - widgets.switch_h, 2);
        widgets.drawSwitch(logical, sx, sy, switchT(title, on), theme, bound_sw_icons, true);
    }
    paintRowDivider(logical, r, theme);
    return r;
}

/// Horizontal MD3 filter chips. `selected == null` → none highlighted (nav hub).
/// Height = touch_min; wraps to a second row if needed. Drawn on surface-container band.
pub fn paintChipRow(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    labels: []const []const u8,
    selected: ?usize,
) geom.Rect {
    const pad = tokens.Space.sm;
    const y0 = rowY(cur.y, scroll);
    const h: i32 = tokens.Logical.touch_min;
    const gap = tokens.Space.sm;
    var x = content_x + pad;
    var y = y0 + pad;
    var rows: i32 = 1;
    const inner_w = content_w - pad * 2;
    // Measure wrap first for band height.
    {
        var mx = content_x + pad;
        var mrows: i32 = 1;
        for (labels) |lab| {
            const tw = font.textWidthStr(lab, .label_l);
            const cw = @max(tokens.Logical.touch_min, tw + tokens.Space.md * 2);
            if (mx > content_x + pad and mx + cw > content_x + pad + inner_w) {
                mx = content_x + pad;
                mrows += 1;
            }
            mx += cw + gap;
        }
        const band_h = mrows * h + (mrows - 1) * gap + pad * 2;
        const band: geom.Rect = .{ .x = content_x, .y = y0, .w = content_w, .h = band_h };
        if (visibleRow(logical, y0, band_h)) {
            widgets.fillRoundRect(logical, band, tokens.Shape.md, theme.surface_container);
        }
    }
    for (labels, 0..) |lab, i| {
        const tw = font.textWidthStr(lab, .label_l);
        const cw = @max(tokens.Logical.touch_min, tw + tokens.Space.md * 2);
        if (x > content_x + pad and x + cw > content_x + pad + inner_w) {
            x = content_x + pad;
            y += h + gap;
            rows += 1;
        }
        const chip: geom.Rect = .{ .x = x, .y = y, .w = cw, .h = h };
        if (visibleRow(logical, y, h)) {
            const on = if (selected) |s| s == i else false;
            widgets.drawFilterChip(logical, chip, lab, on, theme);
        }
        x += cw + gap;
    }
    const total_h = rows * h + (rows - 1) * gap + pad * 2;
    const r: geom.Rect = .{ .x = content_x, .y = y0, .w = content_w, .h = total_h };
    cur.y += total_h + tokens.Space.md;
    return r;
}

/// Label + trailing exclusive radio options (MD3). Returns full row hit rect.
pub fn paintRadioRow(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    label: []const u8,
    options: []const []const u8,
    selected: usize,
) geom.Rect {
    const y = rowY(cur.y, scroll);
    const r: geom.Rect = .{ .x = content_x, .y = y, .w = content_w, .h = row_h };
    cur.y += row_h;
    if (!visibleRow(logical, y, row_h)) return r;
    font.drawTextRole(logical, r.x, r.y + 18, label, theme.on_surface, .body_l);
    // Pack options from the right.
    var x = r.x + r.w;
    var i: isize = @intCast(options.len);
    while (i > 0) {
        i -= 1;
        const idx: usize = @intCast(i);
        const lab = options[idx];
        const tw = font.textWidthStr(lab, .label_m);
        const slot_w = 28 + tw + tokens.Space.sm;
        x -= slot_w;
        const cy = r.y + @divTrunc(r.h, 2);
        const on = selected == idx;
        expr.drawRadio(logical, x + 12, cy, on, theme);
        font.drawTextRole(logical, x + 28, r.y + 18, lab, if (on) theme.on_surface else theme.on_surface_variant, .label_m);
        x -= tokens.Space.sm;
    }
    paintRowDivider(logical, r, theme);
    return r;
}

/// Index of radio option under x (same packing as paintRadioRow).
pub fn radioIndexAt(row: geom.Rect, options: []const []const u8, x: i32) ?usize {
    var cx = row.x + row.w;
    var i: isize = @intCast(options.len);
    while (i > 0) {
        i -= 1;
        const idx: usize = @intCast(i);
        const tw = font.textWidthStr(options[idx], .label_m);
        const slot_w = 28 + tw + tokens.Space.sm;
        cx -= slot_w;
        if (x >= cx and x < cx + slot_w) return idx;
        cx -= tokens.Space.sm;
    }
    return null;
}

/// Trailing checkbox list item (multi-select prefs).
pub fn paintCheckbox(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    label: []const u8,
    checked: bool,
) geom.Rect {
    const y = rowY(cur.y, scroll);
    const r: geom.Rect = .{ .x = content_x, .y = y, .w = content_w, .h = row_h };
    cur.y += row_h;
    if (!visibleRow(logical, y, row_h)) return r;
    font.drawTextRole(logical, r.x, r.y + 18, label, theme.on_surface, .body_l);
    const bx = r.x + r.w - 24 - tokens.Space.md;
    const by = r.y + @divTrunc(r.h - 24, 2);
    expr.drawCheckbox(logical, bx, by, checked, theme);
    paintRowDivider(logical, r, theme);
    return r;
}

pub fn chipIndexAt(row: geom.Rect, labels: []const []const u8, x: i32) ?usize {
    return chipIndexAtXY(row, labels, x, row.y + tokens.Space.sm);
}

/// 2D chip hit (supports wrapped paintChipRow).
pub fn chipIndexAtXY(row: geom.Rect, labels: []const []const u8, x: i32, y: i32) ?usize {
    const h: i32 = tokens.Logical.touch_min;
    const gap = tokens.Space.sm;
    const pad = tokens.Space.sm;
    var cx = row.x + pad;
    var cy = row.y + pad;
    const inner_w = row.w - pad * 2;
    for (labels, 0..) |lab, i| {
        const tw = font.textWidthStr(lab, .label_l);
        const cw = @max(tokens.Logical.touch_min, tw + tokens.Space.md * 2);
        if (cx > row.x + pad and cx + cw > row.x + pad + inner_w) {
            cx = row.x + pad;
            cy += h + gap;
        }
        if (x >= cx and x < cx + cw and y >= cy and y < cy + h) return i;
        cx += cw + gap;
    }
    return null;
}

test "chipIndexAt picks middle chip" {
    const labs = [_][]const u8{ "Wi-Fi", "BT", "ESP-NOW" };
    const row: geom.Rect = .{ .x = 100, .y = 50, .w = 400, .h = 48 };
    const pad = tokens.Space.sm;
    const first = chipIndexAt(row, &labs, 100 + pad + 8) orelse return error.Miss;
    try std.testing.expectEqual(@as(usize, 0), first);
    const tw0 = @max(tokens.Logical.touch_min, font.textWidthStr(labs[0], .label_l) + tokens.Space.md * 2) + tokens.Space.sm;
    const second = chipIndexAt(row, &labs, 100 + pad + tw0 + 4) orelse return error.Miss;
    try std.testing.expectEqual(@as(usize, 1), second);
    try std.testing.expect(chipIndexAt(row, &labs, 99) == null);
}

test "radioIndexAt picks last option" {
    const opts = [_][]const u8{ "Never", "Always", "Running" };
    const row: geom.Rect = .{ .x = 100, .y = 40, .w = 700, .h = 56 };
    const last = radioIndexAt(row, &opts, row.x + row.w - 8) orelse return error.Miss;
    try std.testing.expectEqual(@as(usize, 2), last);
}

pub fn paintAction(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    label: []const u8,
    detail: []const u8,
) geom.Rect {
    return paintActionStateTone(logical, theme, cur, scroll, label, detail, true, .muted);
}

pub fn paintActionAccent(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    label: []const u8,
    detail: []const u8,
) geom.Rect {
    return paintActionStateTone(logical, theme, cur, scroll, label, detail, true, .accent);
}

pub fn paintDestructiveAction(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    label: []const u8,
    detail: []const u8,
) geom.Rect {
    return paintActionStateTone(logical, theme, cur, scroll, label, detail, true, .destructive);
}

pub fn paintActionState(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    label: []const u8,
    detail: []const u8,
    enabled: bool,
    destructive: bool,
) geom.Rect {
    const tone: DetailTone = if (destructive) .destructive else .muted;
    return paintActionStateTone(logical, theme, cur, scroll, label, detail, enabled, tone);
}

const DetailTone = enum { muted, accent, destructive };

fn paintActionStateTone(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    label: []const u8,
    detail: []const u8,
    enabled: bool,
    tone: DetailTone,
) geom.Rect {
    const y = rowY(cur.y, scroll);
    const r: geom.Rect = .{ .x = content_x, .y = y, .w = content_w, .h = row_h };
    cur.y += row_h;
    if (!visibleRow(logical, y, row_h)) return r;
    const fg = if (!enabled)
        theme.on_surface_variant
    else if (tone == .destructive)
        theme.err
    else
        theme.on_surface;
    const det_fg = if (!enabled)
        theme.on_surface_variant
    else switch (tone) {
        .destructive => theme.err,
        .accent => theme.primary,
        .muted => theme.on_surface_variant,
    };

    const mid_y = r.y + @divTrunc(r.h, 2);
    const label_h = font.faceHeight(font.faceForRole(.body_l));
    font.drawTextRole(logical, r.x, mid_y - @divTrunc(label_h, 2), label, fg, .body_l);

    // Trailing: detail + caret share row midline; Space.md between text and icon.
    const icon_end_pad = tokens.Space.md;
    const text_icon_gap = tokens.Space.md;
    const caret_cx = r.x + r.w - icon_end_pad - @divTrunc(icons_phosphor.size, 2);
    const trail_reserve: i32 = if (enabled)
        icon_end_pad + icons_phosphor.size + text_icon_gap
    else
        icon_end_pad;

    if (detail.len > 0) {
        const tw = font.textWidthStr(detail, .label_l);
        const det_h = font.faceHeight(font.faceForRole(.label_l));
        font.drawTextRole(logical, r.x + r.w - trail_reserve - tw, mid_y - @divTrunc(det_h, 2), detail, det_fg, .label_l);
    }
    if (enabled) {
        icons_phosphor.drawCentered(logical, caret_cx, mid_y, .caret_right, theme.on_surface_variant);
    }
    paintRowDivider(logical, r, theme);
    return r;
}

/// MD3 nav back — parent title, no caret; tonal strip.
pub fn paintBackRow(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    parent: []const u8,
) geom.Rect {
    const h: i32 = tokens.Logical.touch_min;
    const y = rowY(cur.y, scroll);
    const r: geom.Rect = .{ .x = content_x, .y = y, .w = content_w, .h = h };
    cur.y += h + tokens.Space.xs;
    if (!visibleRow(logical, y, h)) return r;
    widgets.fillRoundRect(logical, r, tokens.Shape.sm, theme.surface_container);
    // ponytail: no caret_left asset — ASCII "<" + parent title.
    font.drawTextRole(logical, r.x + tokens.Space.md, r.y + @divTrunc(h - font.faceHeight(font.faceForRole(.title_m)), 2), "<", theme.on_surface, .title_m);
    font.drawTextRole(logical, r.x + tokens.Space.md + 22, r.y + @divTrunc(h - font.faceHeight(font.faceForRole(.title_m)), 2), parent, theme.on_surface, .title_m);
    return r;
}

/// Tappable two-line list item (primary + supporting + caret).
pub fn paintTwoLineAction(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    title: []const u8,
    support: []const u8,
) geom.Rect {
    const h: i32 = 72;
    const y = rowY(cur.y, scroll);
    const r: geom.Rect = .{ .x = content_x, .y = y, .w = content_w, .h = h };
    cur.y += h;
    if (!visibleRow(logical, y, h)) return r;
    font.drawTextRole(logical, r.x, r.y + 14, title, theme.on_surface, .body_l);
    font.drawTextRole(logical, r.x, r.y + 40, support, theme.on_surface_variant, .body_s);
    const caret_cx = r.x + r.w - tokens.Space.md - @divTrunc(icons_phosphor.size, 2);
    icons_phosphor.drawCentered(logical, caret_cx, r.y + @divTrunc(h, 2), .caret_right, theme.on_surface_variant);
    paintRowDivider(logical, r, theme);
    return r;
}

/// MD3 linear progress under an action (e.g. Pull from controller).
pub fn paintProgressTrack(logical: *fb.LogicalFb, theme: tokens.Theme, cur: *Cursor, scroll: i32, progress: f32) void {
    const track_h: i32 = 4;
    const pad_y = tokens.Space.xs;
    const y = rowY(cur.y, scroll);
    cur.y += track_h + pad_y + tokens.Space.sm;
    if (!visibleRow(logical, y, track_h + pad_y)) return;
    expr.drawLinearProgress(logical, .{ .x = content_x, .y = y + pad_y, .w = content_w, .h = track_h }, progress, theme);
}

pub const StatusKind = enum { ok, warn, err, dim };

pub fn paintHealthStrip(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    labels: *const [5][]const u8,
    kinds: *const [5]StatusKind,
) [5]geom.Rect {
    const y = rowY(cur.y, scroll);
    const h: i32 = 48;
    const gap: i32 = tokens.Space.xs + tokens.Space.xs / 2;
    const chip_w = @divTrunc(content_w - gap * 4, 5);
    cur.y += h + tokens.Space.md;
    var out: [5]geom.Rect = [_]geom.Rect{.{}} ** 5;
    if (!visibleRow(logical, y, h)) {
        var i: usize = 0;
        while (i < 5) : (i += 1) {
            out[i] = .{ .x = content_x + @as(i32, @intCast(i)) * (chip_w + gap), .y = y, .w = chip_w, .h = h };
        }
        return out;
    }
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const chip: geom.Rect = .{
            .x = content_x + @as(i32, @intCast(i)) * (chip_w + gap),
            .y = y,
            .w = chip_w,
            .h = h,
        };
        out[i] = chip;
        const bg = switch (kinds[i]) {
            .ok => theme.secondary_container,
            .err => theme.error_container,
            .warn, .dim => theme.surface_container_high,
        };
        const fg = switch (kinds[i]) {
            .ok => theme.on_secondary_container,
            .err => theme.on_error_container,
            .warn, .dim => theme.on_surface_variant,
        };
        widgets.fillRoundRect(logical, chip, tokens.Shape.full, bg);
        if (kinds[i] == .dim or kinds[i] == .warn) {
            widgets.strokeRoundRect(logical, chip, tokens.Shape.full, theme.outline_variant, 1);
        }
        const tw = font.textWidthStr(labels[i], .label_m);
        const th = font.faceHeight(font.faceForRole(.label_m));
        font.drawTextRole(logical, chip.x + @divTrunc(chip.w - tw, 2), chip.y + @divTrunc(chip.h - th, 2), labels[i], fg, .label_m);
    }
    return out;
}

pub fn paintDeviceCard(logical: *fb.LogicalFb, theme: tokens.Theme, cur: *Cursor, scroll: i32, ver: []const u8) void {
    const y = rowY(cur.y, scroll);
    const h: i32 = 88;
    const r: geom.Rect = .{ .x = content_x, .y = y, .w = content_w, .h = h };
    cur.y += h + tokens.Space.sm;
    if (!visibleRow(logical, y, h)) return;
    widgets.fillRoundRect(logical, r, tokens.Shape.md, theme.surface_container_highest);
    widgets.strokeRoundRect(logical, r, tokens.Shape.md, theme.outline_variant, 1);
    logical.fillRect(.{ .x = r.x + tokens.Space.md, .y = r.y + 12, .w = 4, .h = 64 }, theme.primary);
    const tile: geom.Rect = .{ .x = r.x + tokens.Space.md + 12, .y = r.y + 12, .w = 64, .h = 64 };
    widgets.fillRoundRect(logical, tile, tokens.Shape.md, theme.primary_container);
    icons_phosphor.draw(logical, tile.x + 16, tile.y + 16, .gear, theme.on_primary_container);
    font.drawTextRole(logical, tile.x + 76, r.y + 18, "Modulus OS", theme.on_surface, .title_m);
    font.drawTextRole(logical, tile.x + 76, r.y + 44, "M5Stack Tab5 | ESP32-P4 + C6", theme.on_surface_variant, .body_m);
    font.drawTextRole(logical, tile.x + 76, r.y + 64, "Hardware by M5Stack", theme.on_surface_variant, .label_m);
    const pw = font.textWidthStr(ver, .label_l) + tokens.Space.md * 2;
    const pill: geom.Rect = .{
        .x = r.x + r.w - pw - tokens.Space.md,
        .y = r.y + @divTrunc(h - 32, 2),
        .w = pw,
        .h = 32,
    };
    widgets.fillRoundRect(logical, pill, tokens.Shape.full, theme.secondary_container);
    const vw = font.textWidthStr(ver, .label_l);
    const vh = font.faceHeight(font.faceForRole(.label_l));
    font.drawTextRole(logical, pill.x + @divTrunc(pill.w - vw, 2), pill.y + @divTrunc(pill.h - vh, 2), ver, theme.on_secondary_container, .label_l);
}

pub fn paintDetail(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    label: []const u8,
    value: []const u8,
) void {
    paintDetailStatus(logical, theme, cur, scroll, label, value, null);
}

pub fn paintDetailStatus(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    cur: *Cursor,
    scroll: i32,
    label: []const u8,
    value: []const u8,
    kind: ?StatusKind,
) void {
    const y = rowY(cur.y, scroll);
    const r: geom.Rect = .{ .x = content_x, .y = y, .w = content_w, .h = row_h - 4 };
    cur.y += row_h - 4;
    if (!visibleRow(logical, y, r.h)) return;
    font.drawTextRole(logical, r.x, r.y + 16, label, theme.on_surface, .body_l);
    const fg = if (kind) |k| switch (k) {
        .ok => theme.secondary,
        .warn => theme.tertiary,
        .err => theme.err,
        .dim => theme.on_surface_variant,
    } else theme.on_surface_variant;
    const tw = font.textWidthStr(value, .body_m);
    font.drawTextRole(logical, r.x + r.w - tw, r.y + 16, value, fg, .body_m);
    paintRowDivider(logical, r, theme);
}

// --- Power menu: MD3 Expressive sheet (LVGL parity) ---

pub const power_card_w: i32 = 640;
pub const power_pad: i32 = tokens.Space.lg;
pub const power_pad_bottom: i32 = tokens.Space.md;
pub const power_hdr_h: i32 = 80;
pub const power_tile_h: i32 = 72;
pub const power_gap: i32 = tokens.Space.sm;
pub const power_sec_h: i32 = 40;
pub const power_close_sz: i32 = tokens.Logical.touch_min;

pub const PowerConfirm = enum {
    none,
    restart,
    shutdown,
    factory,
    language,
    eject_sd,
    import_settings,
    mach_reset,
    maint_reset,
    power_reset,
    display_reset,
    dashboard_reset,
    cnc_reset,
    clear_pin,
    wireless_reset,
    wcs_change,
    dash_cycle,
    dash_spin,
    dash_zero,
    dash_home,
    dash_mac,
    dash_zero_all,
    mach_push,
    mach_slim,
    pin_boot_on,
    pin_slp_on,
};

pub const PowerLayout = struct {
    card: geom.Rect = .{},
    close: geom.Rect = .{},
    reset: geom.Rect = .{},
    unlock: geom.Rect = .{},
    restart: geom.Rect = .{},
    shutdown: geom.Rect = .{},
    confirm_ok: geom.Rect = .{},
    confirm_cancel: geom.Rect = .{},
    confirm_card: geom.Rect = .{},
};

fn powerCardH() i32 {
    return power_hdr_h + power_pad + (power_sec_h + power_tile_h) * 2 + power_gap + power_pad_bottom;
}

pub fn powerWindowRect() geom.Rect {
    const h = powerCardH();
    return .{
        .x = @divTrunc(tokens.Logical.width - power_card_w, 2),
        .y = @divTrunc(tokens.Logical.height - h, 2),
        .w = power_card_w,
        .h = h,
    };
}

/// `enter_t` 0..1 — emphasized decelerate container transform (MD3 dialog enter).
pub fn paintPowerMenu(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    busy: bool,
    enter_t: f32,
) PowerLayout {
    var lay: PowerLayout = .{};
    const t = std.math.clamp(enter_t, 0, 1);
    const base = powerWindowRect();
    const scale = 0.92 + 0.08 * t;
    const cw: i32 = @intFromFloat(@as(f32, @floatFromInt(base.w)) * scale);
    const ch: i32 = @intFromFloat(@as(f32, @floatFromInt(base.h)) * scale);
    lay.card = .{
        .x = base.x + @divTrunc(base.w - cw, 2),
        .y = base.y + @divTrunc(base.h - ch, 2),
        .w = cw,
        .h = ch,
    };

    widgets.fillRoundRect(logical, lay.card, tokens.Shape.dialog, theme.elev(1));
    widgets.strokeRoundRect(logical, lay.card, tokens.Shape.dialog, theme.outline_variant, 1);

    const hdr: geom.Rect = .{ .x = lay.card.x, .y = lay.card.y, .w = lay.card.w, .h = power_hdr_h };
    // LVGL parity: hdr = surface_container_high (elev 3).
    widgets.fillRoundRect(logical, .{ .x = hdr.x, .y = hdr.y, .w = hdr.w, .h = power_hdr_h }, tokens.Shape.dialog, theme.elev(3));
    logical.fillRect(.{ .x = hdr.x, .y = hdr.y + power_hdr_h - 16, .w = hdr.w, .h = 16 }, theme.elev(3));
    logical.fillRect(.{ .x = hdr.x, .y = hdr.y + power_hdr_h - 1, .w = hdr.w, .h = 1 }, theme.outline_variant);

    icons_phosphor.draw(logical, hdr.x + tokens.Space.xl, hdr.y + @divTrunc(power_hdr_h - 24, 2), .power, theme.err);
    font.drawTextRole(logical, hdr.x + tokens.Space.xl + 36, hdr.y + @divTrunc(power_hdr_h - 22, 2), "Power menu", theme.on_surface, .title_l);

    lay.close = .{
        .x = hdr.x + hdr.w - power_close_sz - tokens.Space.lg,
        .y = hdr.y + @divTrunc(power_hdr_h - power_close_sz, 2),
        .w = power_close_sz,
        .h = power_close_sz,
    };
    widgets.drawTonalCloseButton(logical, lay.close, theme);

    var y = lay.card.y + power_hdr_h + power_pad;
    const body_x = lay.card.x + power_pad;
    const body_w = lay.card.w - power_pad * 2;
    const tile_w = @divTrunc(body_w - power_gap, 2);

    font.drawTextRole(logical, body_x + tokens.Space.md, y + 8, "Machine control", theme.on_surface, .title_m);
    y += power_sec_h;
    lay.reset = .{ .x = body_x, .y = y, .w = tile_w, .h = power_tile_h };
    lay.unlock = .{ .x = body_x + tile_w + power_gap, .y = y, .w = tile_w, .h = power_tile_h };
    paintPowerTile(logical, theme, lay.reset, "Reset CNC", "Soft reset (Ctrl-X)", false, false);
    paintPowerTile(logical, theme, lay.unlock, "Clear alarm", "Unlock ($X)", false, false);
    y += power_tile_h + power_gap;

    font.drawTextRole(logical, body_x + tokens.Space.md, y + 8, "Device power", theme.on_surface, .title_m);
    y += power_sec_h;
    lay.restart = .{ .x = body_x, .y = y, .w = tile_w, .h = power_tile_h };
    lay.shutdown = .{ .x = body_x + tile_w + power_gap, .y = y, .w = tile_w, .h = power_tile_h };
    const restart_hint: []const u8 = if (busy) "Stop program first" else "Reboot now";
    const shutdown_hint: []const u8 = if (busy) "Stop program first" else "Power off";
    paintPowerTile(logical, theme, lay.restart, "Restart device", restart_hint, false, busy);
    paintPowerTile(logical, theme, lay.shutdown, "Shut down device", shutdown_hint, true, busy);
    return lay;
}

fn paintPowerTile(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    r: geom.Rect,
    label: []const u8,
    hint: []const u8,
    destructive: bool,
    disabled: bool,
) void {
    const bg = if (disabled)
        (if (destructive) theme.error_container else theme.surface_container)
    else if (destructive)
        theme.err
    else
        theme.surface_container_high;
    const fg = if (disabled)
        (if (destructive) theme.on_error_container else theme.on_surface_variant)
    else if (destructive)
        theme.on_error
    else
        theme.on_surface;
    const hint_a: u8 = if (destructive) 204 else 178;
    const hint_fg = if (disabled) fg else color.blendRgb565(bg, fg, hint_a);

    widgets.fillRoundRect(logical, r, tokens.Shape.lg_inc, bg);
    const lw = font.textWidthStr(label, .body_l);
    const hw = font.textWidthStr(hint, .label_m);
    const lh = font.faceHeight(font.faceForRole(.body_l));
    const hh = font.faceHeight(font.faceForRole(.label_m));
    const block = lh + 2 + hh;
    const ty = r.y + @divTrunc(r.h - block, 2);
    font.drawTextRole(logical, r.x + @divTrunc(r.w - lw, 2), ty, label, fg, .body_l);
    font.drawTextRole(logical, r.x + @divTrunc(r.w - hw, 2), ty + lh + 2, hint, hint_fg, .label_m);
}

pub fn paintPowerConfirm(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    kind: PowerConfirm,
    enter_t: f32,
) struct { ok: geom.Rect, cancel: geom.Rect, card: geom.Rect } {
    const title: []const u8 = switch (kind) {
        .none => "",
        .restart => "Restart device?",
        .shutdown => "Shut down device?",
        .factory => "Factory reset?",
        .language => "Apply language?",
        .eject_sd => "Eject SD card?",
        .import_settings => "Import settings?",
        .mach_reset => "Reset machine settings?",
        .maint_reset => "Reset maintenance counters?",
        .power_reset => "Reset power settings?",
        .display_reset => "Reset display settings?",
        .dashboard_reset => "Reset dashboard settings?",
        .cnc_reset => "Reset CNC connection?",
        .clear_pin => "Clear PIN?",
        .wireless_reset => "Reset network settings?",
        .wcs_change => "Change locked WCS?",
        .dash_cycle => "Cycle start?",
        .dash_spin => "Start spindle?",
        .dash_zero => "Zero axis?",
        .dash_home => "Home all axes?",
        .dash_mac => "Run macro?",
        .dash_zero_all => "Zero all axes?",
        .mach_push => "Push envelope to controller?",
        .mach_slim => "Change soft limits?",
        .pin_boot_on => "Require PIN after boot?",
        .pin_slp_on => "Require PIN after sleep?",
    };
    const line1: []const u8 = switch (kind) {
        .none => "",
        .restart => "Device reboots immediately.",
        .shutdown => "Device powers off.",
        .factory => "Erases all settings. No undo.",
        .language => "UI strings refresh after apply.",
        .eject_sd => "Unmount before removing the card.",
        .import_settings => "Replace current prefs from SD JSON.",
        .mach_reset => "Restores work envelope and soft limits.",
        .maint_reset => "Clears travel, spindle time, and run time.",
        .power_reset => "Restores display sleep, system sleep, rails,",
        .display_reset => "Restores brightness, orientation, theme, touch,",
        .dashboard_reset => "Restores jog, axes, WCS, units, quick buttons,",
        .cnc_reset => "Restores RS-485 defaults and reconnects",
        .clear_pin => "Removes PIN and disables boot and wake lock.",
        .wireless_reset => "Clears wireless flags and disables radios.",
        .wcs_change => "This work coordinate system is locked.",
        .dash_cycle => "Starts or resumes the program.",
        .dash_spin => "Spindle starts.",
        .dash_zero => "Work coordinate for this axis goes to zero.",
        .dash_home => "Machine runs homing cycle.",
        .dash_mac => "Sends the quick macro G-code line.",
        .dash_zero_all => "All work coordinates go to zero.",
        .mach_push => "Sends max feed, RPM, travel, and soft limits.",
        .mach_slim => "Soft limits block motion past the envelope.",
        .pin_boot_on => "Enter PIN after every reboot.",
        .pin_slp_on => "Enter PIN when waking from sleep.",
    };
    const line2: []const u8 = switch (kind) {
        .none => "",
        .restart => "Unsaved work may be lost.",
        .shutdown => "Use the power button to turn it back on.",
        .factory => "Device restarts after erase.",
        .language => "",
        .eject_sd => "Safe to remove after eject completes.",
        .import_settings => "PIN hash and Wi-Fi password stay local.",
        .mach_reset => "Maintenance counters reset too.",
        .maint_reset => "No undo.",
        .power_reset => "and battery behavior.",
        .display_reset => "and refresh.",
        .dashboard_reset => "and handwheel tuning.",
        .cnc_reset => "transport.",
        .clear_pin => "Enter current PIN next.",
        .wireless_reset => "Saved SSID stub cleared on host.",
        .wcs_change => "Cycles to next WCS.",
        .dash_cycle, .dash_spin, .dash_zero, .dash_home, .dash_mac, .dash_zero_all => "",
        .mach_push => "Connect controller first.",
        .mach_slim => "Wrong values can stop mid-cut travel.",
        .pin_boot_on, .pin_slp_on => "Remember your PIN before enabling.",
    };
    const confirm_label: []const u8 = switch (kind) {
        .none => "",
        .restart => "Restart",
        .shutdown => "Power off",
        .factory => "Erase & reset",
        .language => "Apply",
        .eject_sd => "Eject",
        .import_settings => "Import",
        .mach_reset => "Reset",
        .maint_reset => "Clear",
        .power_reset => "Reset",
        .display_reset => "Reset",
        .dashboard_reset => "Reset",
        .cnc_reset => "Reset",
        .clear_pin => "Clear",
        .wireless_reset => "Reset",
        .wcs_change => "Change",
        .dash_cycle => "Start",
        .dash_spin => "Start",
        .dash_zero, .dash_zero_all => "Zero",
        .dash_home => "Home",
        .dash_mac => "Run",
        .mach_push => "Push",
        .mach_slim => "Change",
        .pin_boot_on, .pin_slp_on => "Enable",
    };
    const destructive = kind == .shutdown or kind == .factory or kind == .mach_reset or kind == .maint_reset or kind == .power_reset or kind == .display_reset or kind == .dashboard_reset or kind == .cnc_reset or kind == .clear_pin or kind == .wireless_reset or kind == .mach_slim;
    const t = std.math.clamp(enter_t, 0, 1);

    widgets.fillScrim(logical, theme);

    const card_w0: i32 = 420;
    const card_h0: i32 = 280;
    const card_w: i32 = @intFromFloat(@as(f32, @floatFromInt(card_w0)) * (0.88 + 0.12 * t));
    const card_h: i32 = @intFromFloat(@as(f32, @floatFromInt(card_h0)) * (0.88 + 0.12 * t));
    const card: geom.Rect = .{
        .x = @divTrunc(tokens.Logical.width - card_w, 2),
        .y = @divTrunc(tokens.Logical.height - card_h, 2),
        .w = card_w,
        .h = card_h,
    };
    widgets.fillRoundRect(logical, card, tokens.Shape.dialog, theme.elev(3));

    const icon_c = if (destructive) theme.err else theme.primary;
    icons_phosphor.draw(logical, card.x + @divTrunc(card.w - 24, 2), card.y + tokens.Space.lg, .power, icon_c);

    const tw = font.textWidthStr(title, .title_l);
    font.drawTextRole(logical, card.x + @divTrunc(card.w - tw, 2), card.y + 56, title, theme.on_surface, .title_l);
    const b1w = font.textWidthStr(line1, .body_m);
    font.drawTextRole(logical, card.x + @divTrunc(card.w - b1w, 2), card.y + 96, line1, theme.on_surface_variant, .body_m);
    const b2w = font.textWidthStr(line2, .body_m);
    font.drawTextRole(logical, card.x + @divTrunc(card.w - b2w, 2), card.y + 120, line2, theme.on_surface_variant, .body_m);

    const btn_h = tokens.ButtonSize.m.height();
    const btn_w: i32 = 148;
    const cancel: geom.Rect = .{
        .x = card.x + card.w - btn_w * 2 - tokens.Space.sm - tokens.Space.lg,
        .y = card.y + card.h - btn_h - tokens.Space.lg,
        .w = btn_w,
        .h = btn_h,
    };
    const ok: geom.Rect = .{
        .x = card.x + card.w - btn_w - tokens.Space.lg,
        .y = cancel.y,
        .w = btn_w,
        .h = btn_h,
    };

    widgets.drawTonalButton(logical, cancel, "Cancel", theme);
    if (destructive) {
        widgets.drawDangerButton(logical, ok, confirm_label, theme);
    } else {
        widgets.drawFilledButton(logical, ok, confirm_label, theme);
    }
    return .{ .ok = ok, .cancel = cancel, .card = card };
}

test "power card fits LVGL sections" {
    const win = powerWindowRect();
    try std.testing.expect(win.w == 640);
    try std.testing.expect(win.h >= power_hdr_h + power_tile_h * 2);
    try std.testing.expect(power_close_sz >= tokens.Logical.touch_min);
    try std.testing.expect(power_tile_h >= tokens.Logical.touch_min);
}

test "power tile roles pair (dark + light)" {
    inline for (.{ tokens.Theme.industrialTealDark(), tokens.Theme.industrialTealLight() }) |th| {
        try std.testing.expect(color.contrastRatio(th.on_error.toHex(), th.err.toHex()) >= 2.5);
        try std.testing.expect(color.contrastRatio(th.on_error_container.toHex(), th.error_container.toHex()) >= 2.5);
        try std.testing.expect(color.contrastRatio(th.on_surface.toHex(), th.elev(1).toHex()) >= 2.5);
        try std.testing.expect(color.contrastRatio(th.on_surface.toHex(), th.elev(3).toHex()) >= 2.5);
        try std.testing.expect(color.contrastRatio(th.on_primary.toHex(), th.primary.toHex()) >= 2.5);
        try std.testing.expect(color.contrastRatio(th.on_secondary_container.toHex(), th.secondary_container.toHex()) >= 2.5);
    }
}

test "power elev ladder matches MD3 dialog steps" {
    const th = tokens.Theme.industrialTealDark();
    try std.testing.expect(th.elev(1).toU16() == th.surface_container_low.toU16());
    try std.testing.expect(th.elev(2).toU16() == th.surface_container.toU16());
    try std.testing.expect(th.elev(3).toU16() == th.surface_container_high.toU16());
}

test "syncLayout rail vs compact" {
    syncLayout(true);
    try std.testing.expect(useRail());
    try std.testing.expect(rail_w == 300);
    try std.testing.expect(content_x == win_x + rail_w + 28);
    syncLayout(false);
    try std.testing.expect(!useRail());
    try std.testing.expect(rail_w == 0);
    // Rail gone → wider, centred column (not the MD3 compact 584 px cap).
    try std.testing.expect(content_w > 840);
    try std.testing.expect(content_x + content_w <= win_x + win_w);
    try std.testing.expect(content_x - win_x == win_x + win_w - (content_x + content_w));
    try std.testing.expect(categoryListWidth() == win_w);
    try std.testing.expect(searchRect().w == win_w - 32);
    syncLayout(true); // leave rail default for other module tests
}

fn stdFmt(buf: []u8, value: u32) []const u8 {
    return std.fmt.bufPrint(buf, "{d}", .{value}) catch "?";
}
