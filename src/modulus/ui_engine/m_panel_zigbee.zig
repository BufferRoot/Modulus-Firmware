//! M-Panel Zigbee — full zigbee2mqtt-style device cards + permit join.

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const icons_phosphor = @import("icons_phosphor.zig");
const color = @import("color.zig");
const settings_prefs = @import("settings_prefs.zig");
const zb_purpose = @import("zb_purpose.zig");
const zb_exposes = @import("zb_exposes.zig");
const tool_chrome = @import("m_panel_tool.zig");
const expr = @import("widgets_expressive.zig");

pub const max_devices: usize = 8;
const card_w: i32 = 1180;
const card_h: i32 = 600;
const grid_gap: i32 = tokens.Space.md;
const min_tile_w: i32 = 360;
const max_grid_cols: i32 = 3;
const btn_size = tokens.ButtonSize.m;
const row_h: i32 = zb_exposes.row_h;

pub const Ctx = struct {
    wireless: *const settings_prefs.WirelessPrefs,
    scroll_px: i32 = 0,
    /// Frame phase 0..1 for indeterminate affordances (permit join bar).
    anim_t: f32 = 0,
    /// Open dropdown: dev index + field; dev=0xff closed.
    menu_dev: u8 = 0xff,
    menu_field: zb_exposes.Field = .none,
};

pub const HitSlot = struct {
    field: zb_exposes.Field = .none,
    rect: geom.Rect = .{},
    aux: u16 = 0,
};

pub const CardLayout = struct {
    outer: geom.Rect = .{},
    slots: [28]HitSlot = [_]HitSlot{.{}} ** 28,
    slot_n: u8 = 0,
    exposes_link: geom.Rect = .{},
    identify: geom.Rect = .{},
    remove: geom.Rect = .{},
};

pub const Hit = struct {
    kind: Kind = .none,
    dev: u8 = 0,
    field: zb_exposes.Field = .none,
    aux: u16 = 0,
};

pub const Kind = enum {
    none,
    scrim,
    back,
    exit,
    permit_join,
    refresh,
    join_hub,
    toggle,
    slider,
    child_lock,
    dropdown,
    color_xy,
    cover,
    identify,
    remove,
    exposes,
};

pub const Layout = struct {
    header: tool_chrome.Header = .{},
    permit: geom.Rect = .{},
    refresh: geom.Rect = .{},
    join: geom.Rect = .{},
    view: geom.Rect = .{},
    cards: [max_devices]CardLayout = [_]CardLayout{.{}} ** max_devices,
    card_n: u8 = 0,
    scroll_max: i32 = 0,
    grid_cols: u8 = 2,
    menu_anchor: geom.Rect = .{},
};

fn gridCols(view_w: i32) i32 {
    const cols = @divTrunc(view_w + grid_gap, min_tile_w + grid_gap);
    return @max(1, @min(max_grid_cols, cols));
}

fn gridRows(card_n: u8, cols: i32) i32 {
    return @divTrunc(@as(i32, @intCast(card_n)) + cols - 1, cols);
}

fn accumulateRowHeights(w: *const settings_prefs.WirelessPrefs, card_n: u8, cols: i32, row_heights: *[4]i32) void {
    @memset(row_heights, 0);
    var i: u8 = 0;
    while (i < card_n) : (i += 1) {
        const rh = zb_exposes.cardBodyHeight(w.zbSnap(i));
        const gr: usize = @intCast(@divTrunc(@as(i32, @intCast(i)), cols));
        if (gr < 4 and rh > row_heights[gr]) row_heights[gr] = rh;
    }
}

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

pub fn devCount(w: *const settings_prefs.WirelessPrefs) u8 {
    return @intCast(@min(if (w.live_zb_n > 0) w.live_zb_n else w.zb_dev_n, max_devices));
}

fn pushSlot(lay: *CardLayout, field: zb_exposes.Field, r: geom.Rect, aux: u16) void {
    if (lay.slot_n >= lay.slots.len) return;
    lay.slots[lay.slot_n] = .{ .field = field, .rect = r, .aux = aux };
    lay.slot_n += 1;
}

fn sliderPct(row: geom.Rect, x: i32) u8 {
    const inset = tokens.Space.sm;
    const tx = row.x + inset;
    const tw: i32 = @max(1, row.w - inset * 2);
    const t: i32 = std.math.clamp(x - tx, 0, tw);
    return @intCast(@min(100, @divTrunc(t * 100, tw)));
}

fn paintToggleRow(logical: *fb.LogicalFb, theme: tokens.Theme, r: geom.Rect, label: []const u8, on: bool) void {
    const lh = font.faceHeight(font.faceForRole(.label_m));
    font.drawTextRole(logical, r.x + tokens.Space.sm, r.y + @divTrunc(row_h - lh, 2), label, theme.on_surface_variant, .label_m);
    widgets.drawSwitchBool(logical, r.x + r.w - 52, r.y + @divTrunc(row_h - 28, 2), on, theme);
}

fn paintDropdownRow(logical: *fb.LogicalFb, theme: tokens.Theme, r: geom.Rect, label: []const u8, value: []const u8) void {
    const lh = font.faceHeight(font.faceForRole(.label_m));
    const label_y = r.y + @divTrunc(row_h - lh, 2);
    font.drawTextRole(logical, r.x + tokens.Space.sm, label_y, label, theme.on_surface_variant, .label_m);
    const val_x = r.x + @divTrunc(r.w, 3);
    const box_h = row_h - tokens.Space.sm;
    const box_y = r.y + @divTrunc(row_h - box_h, 2);
    widgets.fillRoundRect(logical, .{ .x = val_x, .y = box_y, .w = r.w - val_x + r.x - tokens.Space.sm, .h = box_h }, tokens.Shape.sm, theme.surface_container_high);
    widgets.strokeRoundRect(logical, .{ .x = val_x, .y = box_y, .w = r.w - val_x + r.x - tokens.Space.sm, .h = box_h }, tokens.Shape.sm, theme.outline_variant, 1);
    const vh = font.faceHeight(font.faceForRole(.body_m));
    font.drawTextRole(logical, val_x + tokens.Space.sm, box_y + @divTrunc(box_h - vh, 2), value, theme.on_surface, .body_m);
    widgets.drawChevronDown(logical, r.x + r.w - tokens.Space.lg, r.y + @divTrunc(row_h, 2), 5, theme.on_surface_variant);
}

fn paintReadonly(logical: *fb.LogicalFb, theme: tokens.Theme, r: geom.Rect, label: []const u8, value: []const u8, value_c: color.Rgb565) void {
    const lh = font.faceHeight(font.faceForRole(.label_m));
    const ty = r.y + @divTrunc(r.h - lh, 2);
    font.drawTextRole(logical, r.x, ty, label, theme.on_surface_variant, .label_m);
    const lw = font.textWidthStr(label, .label_m);
    font.drawTextRole(logical, r.x + lw + tokens.Space.sm, ty, value, value_c, .body_m);
}

fn paintDevCard(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    w: *const settings_prefs.WirelessPrefs,
    idx: u8,
    outer: geom.Rect,
    lay: *CardLayout,
) void {
    lay.* = .{ .outer = outer };
    const name = w.zbDevLabel(idx);
    const snap = w.zbSnap(idx);
    const ex = zb_exposes.active(snap);
    const purpose = zb_purpose.classifySnap(name, snap);
    const icon = zb_purpose.icon(purpose);
    const pad = tokens.Space.md;
    widgets.fillRoundRect(logical, outer, tokens.Shape.md, theme.surface_container);
    widgets.strokeRoundRect(logical, outer, tokens.Shape.md, theme.outline_variant, 1);

    icons_phosphor.draw(logical, outer.x + pad, outer.y + pad, icon, theme.primary);
    const th = font.faceHeight(font.faceForRole(.title_m));
    font.drawTextRole(logical, outer.x + pad + icons_phosphor.size + tokens.Space.sm, outer.y + pad + @divTrunc(th, 4), name, theme.on_surface, .title_m);

    var y = outer.y + pad + icons_phosphor.size + tokens.Space.sm;
    const inner_w = outer.w - pad * 2;
    const E = zb_exposes.E;

    if (zb_exposes.has(ex, E.state)) {
        const row: geom.Rect = .{ .x = outer.x + pad, .y = y, .w = inner_w, .h = row_h };
        const on = idx < w.zb_dev_on.len and w.zb_dev_on[idx];
        pushSlot(lay, .state, row, 0);
        paintToggleRow(logical, theme, row, "State", on);
        y += row_h;
    }

    if (zb_exposes.has(ex, E.brightness)) {
        const row: geom.Rect = .{ .x = outer.x + pad, .y = y, .w = inner_w, .h = row_h };
        const pct = zb_exposes.sliderPctFromLevel(snap.level);
        var vbuf: [8]u8 = undefined;
        const vt = std.fmt.bufPrint(&vbuf, "{d}", .{snap.level}) catch null;
        pushSlot(lay, .brightness, row, pct);
        zb_exposes.paintSliderRow(logical, theme, row, "Brightness", pct, vt);
        y += row_h + zb_exposes.slider_extra;
    }

    if (zb_exposes.has(ex, E.color_temp)) {
        const row: geom.Rect = .{ .x = outer.x + pad, .y = y, .w = inner_w, .h = row_h };
        const pct = zb_exposes.colorTempPct(snap.color_temp_mireds);
        var vbuf: [8]u8 = undefined;
        const vt = std.fmt.bufPrint(&vbuf, "{d}", .{snap.color_temp_mireds}) catch null;
        pushSlot(lay, .color_temp, row, pct);
        zb_exposes.paintSliderRow(logical, theme, row, "Color temp", pct, vt);
        y += row_h + zb_exposes.slider_extra;
    }

    if (zb_exposes.has(ex, E.color_xy)) {
        font.drawTextRole(logical, outer.x + pad, y, "Color XY", theme.on_surface_variant, .label_m);
        const color_row_y = y + zb_exposes.color_label_h + tokens.Space.xs;
        const color_row: geom.Rect = .{ .x = outer.x + pad, .y = color_row_y, .w = inner_w, .h = row_h };
        pushSlot(lay, .color_xy, color_row, 0);
        const bar_y = color_row_y + @divTrunc(row_h - zb_exposes.color_bar_visual_h, 2);
        zb_exposes.paintColorBar(logical, .{ .x = outer.x + pad, .y = bar_y, .w = inner_w, .h = zb_exposes.color_bar_visual_h }, snap, theme);
        y += zb_exposes.color_bar_h;
    }

    if (zb_exposes.has(ex, E.effect)) {
        const row: geom.Rect = .{ .x = outer.x + pad, .y = y, .w = inner_w, .h = row_h };
        pushSlot(lay, .effect, row, 0);
        paintDropdownRow(logical, theme, row, "Effect", zb_exposes.dropdownValue(snap, .effect));
        y += row_h;
    }

    if (zb_exposes.has(ex, E.min_brightness)) {
        const row: geom.Rect = .{ .x = outer.x + pad, .y = y, .w = inner_w, .h = row_h };
        const pct = zb_exposes.sliderPctFromLevel(snap.min_level);
        pushSlot(lay, .min_brightness, row, pct);
        zb_exposes.paintSliderRow(logical, theme, row, "Min brightness", pct, null);
        y += row_h + zb_exposes.slider_extra;
    }

    if (zb_exposes.has(ex, E.max_brightness)) {
        const row: geom.Rect = .{ .x = outer.x + pad, .y = y, .w = inner_w, .h = row_h };
        const pct = zb_exposes.sliderPctFromLevel(snap.max_level);
        pushSlot(lay, .max_brightness, row, pct);
        zb_exposes.paintSliderRow(logical, theme, row, "Max brightness", pct, null);
        y += row_h + zb_exposes.slider_extra;
    }

    if (zb_exposes.has(ex, E.light_type)) {
        const row: geom.Rect = .{ .x = outer.x + pad, .y = y, .w = inner_w, .h = row_h };
        pushSlot(lay, .light_type, row, 0);
        paintDropdownRow(logical, theme, row, "Light type", zb_exposes.dropdownValue(snap, .light_type));
        y += row_h;
    }

    if (zb_exposes.has(ex, E.countdown)) {
        const row: geom.Rect = .{ .x = outer.x + pad, .y = y, .w = inner_w, .h = row_h };
        const pct = zb_exposes.countdownPct(snap.countdown_s);
        var vbuf: [12]u8 = undefined;
        const vt = std.fmt.bufPrint(&vbuf, "{d}", .{snap.countdown_s}) catch null;
        pushSlot(lay, .countdown, row, pct);
        zb_exposes.paintSliderRow(logical, theme, row, "Countdown", pct, vt);
        y += row_h + zb_exposes.slider_extra;
    }

    if (zb_exposes.has(ex, E.power) or zb_exposes.has(ex, E.current) or zb_exposes.has(ex, E.voltage) or zb_exposes.has(ex, E.energy)) {
        var pbuf: [96]u8 = undefined;
        const line = zb_exposes.formatPowerBlock(snap, &pbuf);
        font.drawTextRole(logical, outer.x + pad, y, line, theme.on_surface_variant, .body_m);
        y += zb_exposes.power_block_h;
    }

    if (zb_exposes.has(ex, E.child_lock)) {
        const row: geom.Rect = .{ .x = outer.x + pad, .y = y, .w = inner_w, .h = row_h };
        pushSlot(lay, .child_lock, row, 0);
        paintToggleRow(logical, theme, row, "Child lock", snap.child_lock);
        y += row_h;
    }

    if (zb_exposes.has(ex, E.contact)) {
        const open = (snap.zone_status & 0x0001) != 0;
        const val: []const u8 = if (open) "Open" else "Closed";
        const rr: geom.Rect = .{ .x = outer.x + pad, .y = y, .w = inner_w, .h = row_h };
        paintReadonly(logical, theme, rr, "Contact", val, if (open) theme.err else theme.on_surface_variant);
        y += row_h;
    }

    if (zb_exposes.has(ex, E.device_temperature)) {
        var tbuf: [16]u8 = undefined;
        const val = std.fmt.bufPrint(&tbuf, "{d}.{d} C", .{
            @divTrunc(snap.device_temp_c_x10, 10),
            @mod(snap.device_temp_c_x10, 10),
        }) catch "?";
        const rr: geom.Rect = .{ .x = outer.x + pad, .y = y, .w = inner_w, .h = row_h };
        paintReadonly(logical, theme, rr, "Device temperature", val, theme.on_surface_variant);
        y += row_h;
    }

    if (zb_exposes.has(ex, E.power_outage_count)) {
        var cbuf: [12]u8 = undefined;
        const val = std.fmt.bufPrint(&cbuf, "{d}", .{snap.power_outage_count}) catch "?";
        const rr: geom.Rect = .{ .x = outer.x + pad, .y = y, .w = inner_w, .h = row_h };
        paintReadonly(logical, theme, rr, "Power outage count", val, theme.on_surface_variant);
        y += row_h;
    }

    if (zb_exposes.has(ex, E.trigger_count)) {
        var cbuf: [12]u8 = undefined;
        const val = std.fmt.bufPrint(&cbuf, "{d}", .{snap.trigger_count}) catch "?";
        const rr: geom.Rect = .{ .x = outer.x + pad, .y = y, .w = inner_w, .h = row_h };
        paintReadonly(logical, theme, rr, "Trigger count", val, theme.on_surface_variant);
        y += row_h;
    }

    if (zb_exposes.has(ex, E.cover)) {
        const labels = [_][]const u8{ "Open", "Close", "Stop" };
        var ci: u8 = 0;
        const chip_w = @divTrunc(inner_w - tokens.Space.sm * 2, 3);
        while (ci < 3) : (ci += 1) {
            const cr: geom.Rect = .{
                .x = outer.x + pad + @as(i32, @intCast(ci)) * (chip_w + tokens.Space.sm),
                .y = y,
                .w = chip_w,
                .h = row_h,
            };
            pushSlot(lay, .cover, cr, ci);
            widgets.drawTonalButton(logical, cr, labels[ci], theme);
        }
        y += row_h;
    }

    lay.exposes_link = .{ .x = outer.x + pad, .y = y, .w = inner_w, .h = row_h };
    const link_lh = font.faceHeight(font.faceForRole(.label_m));
    font.drawTextRole(logical, lay.exposes_link.x, y + @divTrunc(row_h - link_lh, 2), "Exposes >", theme.primary, .label_m);
    y += row_h;

    const foot_y = outer.y + outer.h - pad - row_h;
    var lqi_buf: [16]u8 = undefined;
    const lqi = std.fmt.bufPrint(&lqi_buf, "LQI {d}", .{snap.lqi}) catch "LQI";
    const foot_mid = foot_y + @divTrunc(row_h, 2);
    icons_phosphor.draw(logical, outer.x + pad, foot_y + @divTrunc(row_h - icons_phosphor.size, 2), .rss_simple, theme.on_surface_variant);
    const foot_lh = font.faceHeight(font.faceForRole(.label_m));
    font.drawTextRole(logical, outer.x + pad + icons_phosphor.size + tokens.Space.xs, foot_mid - @divTrunc(foot_lh, 2), lqi, theme.on_surface_variant, .label_m);

    if (zb_exposes.has(ex, E.battery) and snap.battery_pct != 255) {
        var bbuf: [12]u8 = undefined;
        const bat = std.fmt.bufPrint(&bbuf, "{d}%", .{snap.battery_pct}) catch "?";
        const bx = outer.x + @divTrunc(inner_w, 2);
        icons_phosphor.draw(logical, bx, foot_y + @divTrunc(row_h - icons_phosphor.size, 2), .battery_medium, theme.on_surface_variant);
        font.drawTextRole(logical, bx + icons_phosphor.size + tokens.Space.xs, foot_mid - @divTrunc(foot_lh, 2), bat, theme.on_surface_variant, .label_m);
    }

    const id_w = btnWidth("Identify");
    const del_w = btnWidth("Del");
    lay.remove = .{ .x = outer.x + outer.w - pad - del_w, .y = foot_y, .w = del_w, .h = row_h };
    lay.identify = .{ .x = lay.remove.x - tokens.Space.sm - id_w, .y = foot_y, .w = id_w, .h = row_h };
    widgets.drawTonalButton(logical, lay.identify, "Identify", theme);
    widgets.drawDangerTonalButton(logical, lay.remove, "Del", theme);
}

pub fn paint(logical: *fb.LogicalFb, theme: tokens.Theme, ctx: Ctx, enter_t: f32) Layout {
    widgets.fillScrim(logical, theme);
    const shell = cardGeom(enter_t);
    widgets.fillRoundRect(logical, shell, tokens.Shape.dialog, theme.elev(3));
    widgets.strokeRoundRect(logical, shell, tokens.Shape.dialog, theme.outline_variant, 1);

    var lay: Layout = .{};
    lay.header = tool_chrome.headerChrome(shell);
    tool_chrome.paintBackToPanel(logical, theme, lay.header.back);
    const title_x = lay.header.back.x + lay.header.back.w + tokens.Space.sm;
    tool_chrome.paintTitle(logical, theme, title_x, lay.header.back.y, "Zigbee");
    tool_chrome.paintExit(logical, theme, lay.header.exit);

    const pad = tokens.Space.lg;
    const w = ctx.wireless;
    const body_lh = font.faceHeight(font.faceForRole(.body_m));
    const status_y = lay.header.back.y + lay.header.back.h + tokens.Space.sm;
    font.drawTextRole(logical, shell.x + pad, status_y, w.zbStatusSlice(), theme.on_surface_variant, .body_m);
    const net = w.zbNetworkSlice();
    var bar_y = status_y + body_lh + tokens.Space.md;
    if (net.len > 0) {
        font.drawTextRole(logical, shell.x + pad, status_y + body_lh + tokens.Space.xs, net, theme.on_surface_variant, .body_m);
        bar_y = status_y + body_lh * 2 + tokens.Space.md;
    }

    const permit_w = btnWidth(if (w.zb_scan_phase == 1) "Joining..." else "Permit join");
    lay.permit = .{ .x = shell.x + pad, .y = bar_y, .w = permit_w, .h = btn_size.height() };
    const ref_w = btnWidth("Refresh");
    lay.refresh = .{ .x = lay.permit.x + permit_w + tokens.Space.sm, .y = bar_y, .w = ref_w, .h = btn_size.height() };
    if (!w.zb_joined) {
        const jw = btnWidth("Join hub");
        lay.join = .{ .x = lay.refresh.x + ref_w + tokens.Space.sm, .y = bar_y, .w = jw, .h = btn_size.height() };
    }

    const permit_on = w.zigbee and w.zb_joined and w.zb_scan_phase == 1;
    if (w.zigbee and w.zb_joined) {
        if (permit_on) {
            widgets.drawFilledButton(logical, lay.permit, "Joining...", theme);
        } else {
            widgets.drawFilledButton(logical, lay.permit, "Permit join", theme);
        }
    } else {
        widgets.drawButton(logical, lay.permit, "Permit join", .filled, .disabled, theme);
    }
    if (w.zigbee) {
        widgets.drawTonalButton(logical, lay.refresh, "Refresh", theme);
    } else {
        widgets.drawButton(logical, lay.refresh, "Refresh", .tonal, .disabled, theme);
    }
    if (!w.zb_joined) {
        widgets.drawTonalButton(logical, lay.join, "Join hub", theme);
    }

    if (permit_on) {
        const prog_w = lay.refresh.x + lay.refresh.w - lay.permit.x;
        const prog: geom.Rect = .{
            .x = lay.permit.x,
            .y = lay.permit.y + lay.permit.h + tokens.Space.xs,
            .w = prog_w,
            .h = tokens.Space.xs,
        };
        expr.drawLoadingIndicator(logical, prog, ctx.anim_t * 8.0, theme);
    }

    const footer_h = btn_size.height() + tokens.Space.md;
    const body_top = bar_y + btn_size.height() + tokens.Space.md + if (permit_on) tokens.Space.sm + tokens.Space.xs else 0;
    lay.view = .{
        .x = shell.x + pad,
        .y = body_top,
        .w = shell.w - pad * 2,
        .h = shell.y + shell.h - pad - footer_h - body_top,
    };
    lay.card_n = devCount(w);
    const cols = gridCols(lay.view.w);
    lay.grid_cols = @intCast(cols);
    lay.scroll_max = scrollMax(w, lay.view.w, lay.view.h);
    const scroll = std.math.clamp(ctx.scroll_px, 0, lay.scroll_max);

    logical.setClip(lay.view);
    // NOT defer — that releases at function exit, leaving the footer
    // controls below the list clipped away and invisible.

    if (!w.zigbee) {
        font.drawTextRole(logical, lay.view.x, lay.view.y, "Enable Zigbee radio in Settings > Wireless.", theme.on_surface_variant, .body_m);
        return lay;
    }
    if (!w.zb_joined) {
        font.drawTextRole(logical, lay.view.x, lay.view.y, "Join the Zigbee hub, then Permit join to pair devices.", theme.on_surface_variant, .body_m);
        return lay;
    }
    if (lay.card_n == 0) {
        font.drawTextRole(logical, lay.view.x, lay.view.y, "No devices - tap Permit join and pair a device.", theme.on_surface_variant, .body_m);
        return lay;
    }

    const tile_w = if (cols > 1)
        @divTrunc(lay.view.w - grid_gap * (cols - 1), cols)
    else
        lay.view.w;
    var row_heights: [4]i32 = .{0} ** 4;
    accumulateRowHeights(w, lay.card_n, cols, &row_heights);

    var y_off: i32 = lay.view.y - scroll;
    const rows = gridRows(lay.card_n, cols);
    var row: i32 = 0;
    while (row < rows and row < 4) : (row += 1) {
        const rh = row_heights[@intCast(row)];
        var col: i32 = 0;
        while (col < cols) : (col += 1) {
            const idx = @as(u8, @intCast(row * cols + col));
            if (idx >= lay.card_n) break;
            const x = lay.view.x + col * (tile_w + grid_gap);
            const outer: geom.Rect = .{ .x = x, .y = y_off, .w = tile_w, .h = rh };
            if (!geom.Rect.intersect(outer, lay.view).isEmpty()) {
                paintDevCard(logical, theme, w, idx, outer, &lay.cards[idx]);
            }
        }
        y_off += rh + grid_gap;
    }

    if (ctx.menu_dev != 0xff) {
        const snap = w.zbSnap(ctx.menu_dev);
        const labs = zb_exposes.dropdownLabels(ctx.menu_field);
        if (labs.len > 0) {
            for (lay.cards[ctx.menu_dev].slots) |slot| {
                if (slot.field == ctx.menu_field) {
                    lay.menu_anchor = slot.rect;
                    break;
                }
            }
        }
        _ = snap;
    }
    logical.setClip(null); // release before returning — clip is global state
    return lay;
}

pub fn scrollMax(w: *const settings_prefs.WirelessPrefs, view_w: i32, view_h: i32) i32 {
    const n = devCount(w);
    if (n == 0) return 0;
    const cols = gridCols(view_w);
    var row_heights: [4]i32 = .{0} ** 4;
    accumulateRowHeights(w, n, cols, &row_heights);
    const rows = gridRows(n, cols);
    var total: i32 = 0;
    var r: i32 = 0;
    while (r < rows) : (r += 1) {
        total += row_heights[@intCast(r)] + grid_gap;
    }
    return @max(0, total - grid_gap - view_h);
}

fn cardHitAt(c: CardLayout, dev: u8, x: i32, y: i32) Hit {
    if (c.outer.isEmpty() or !c.outer.contains(x, y)) return .{};
    if (c.exposes_link.contains(x, y)) return .{ .kind = .exposes, .dev = dev };
    if (c.identify.contains(x, y)) return .{ .kind = .identify, .dev = dev };
    if (c.remove.contains(x, y)) return .{ .kind = .remove, .dev = dev };
    var si: u8 = 0;
    while (si < c.slot_n) : (si += 1) {
        const slot = c.slots[si];
        if (!slot.rect.contains(x, y)) continue;
        return switch (slot.field) {
            .state => .{ .kind = .toggle, .dev = dev, .field = .state },
            .child_lock => .{ .kind = .child_lock, .dev = dev },
            .effect, .light_type => .{ .kind = .dropdown, .dev = dev, .field = slot.field },
            .brightness, .color_temp, .countdown, .min_brightness, .max_brightness => .{
                .kind = .slider,
                .dev = dev,
                .field = slot.field,
                .aux = sliderPct(slot.rect, x),
            },
            .color_xy => blk: {
                const rel_y = std.math.clamp(y - slot.rect.y, 0, slot.rect.h);
                const y_pct: u8 = @intCast(@min(100, @divTrunc(rel_y * 100, @max(1, slot.rect.h))));
                break :blk .{
                    .kind = .color_xy,
                    .dev = dev,
                    .aux = (@as(u16, sliderPct(slot.rect, x)) << 8) | y_pct,
                };
            },
            .cover => .{ .kind = .cover, .dev = dev, .aux = slot.aux },
            else => .{},
        };
    }
    return .{};
}

test "zigbee grid uses three columns on tab5 width" {
    try std.testing.expectEqual(@as(i32, 3), gridCols(1132));
    try std.testing.expectEqual(@as(i32, 2), gridCols(760));
}

pub fn layoutMenu(layout: Layout, dev: u8, field: zb_exposes.Field) geom.Rect {
    var anchor: geom.Rect = .{};
    if (dev < layout.card_n) {
        for (layout.cards[dev].slots) |slot| {
            if (slot.field == field) {
                anchor = slot.rect;
                break;
            }
        }
    }
    const labs = zb_exposes.dropdownLabels(field);
    const visible = @min(labs.len, expr.menu_max_visible);
    const mw = expr.menuPopupWidth(anchor.w, labs);
    const mh = @as(i32, @intCast(visible)) * expr.menu_item_h + expr.menu_pad * 2;
    var mx = anchor.x;
    var my = anchor.y + anchor.h + tokens.Space.xs;
    if (my + mh > tokens.Logical.height - tokens.Space.sm) my = anchor.y - mh - tokens.Space.xs;
    if (mx + mw > tokens.Logical.width - tokens.Space.sm) mx = tokens.Logical.width - mw - tokens.Space.sm;
    if (mx < tokens.Space.sm) mx = tokens.Space.sm;
    if (my < tokens.Space.sm) my = tokens.Space.sm;
    return .{ .x = mx, .y = my, .w = mw, .h = mh };
}

pub fn paintMenu(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    rect: geom.Rect,
    field: zb_exposes.Field,
    selected: usize,
    scroll: usize,
) void {
    const labs = zb_exposes.dropdownLabels(field);
    if (labs.len == 0) return;
    expr.drawMenuScrolled(logical, rect, labs, selected, scroll, theme);
}

pub fn hit(layout: Layout, x: i32, y: i32) Hit {
    if (tool_chrome.hitBack(layout.header, x, y)) return .{ .kind = .back };
    if (tool_chrome.hitExit(layout.header, x, y)) return .{ .kind = .exit };
    if (tool_chrome.hitScrim(layout.header, x, y)) return .{ .kind = .scrim };
    if (layout.permit.contains(x, y)) return .{ .kind = .permit_join };
    if (layout.refresh.contains(x, y)) return .{ .kind = .refresh };
    if (!layout.join.isEmpty() and layout.join.contains(x, y)) return .{ .kind = .join_hub };
    var i: u8 = 0;
    while (i < layout.card_n) : (i += 1) {
        const h = cardHitAt(layout.cards[i], i, x, y);
        if (h.kind != .none) return h;
    }
    return .{};
}

test "zigbee panel chrome meets touch_min" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    var wl: settings_prefs.WirelessPrefs = .{};
    wl.zigbee = true;
    wl.zb_joined = true;
    wl.joinZigbee();
    const lay = paint(&logical, tokens.Theme.industrialTealDark(), .{ .wireless = &wl }, 1);
    try std.testing.expect(lay.header.exit.w >= tokens.Logical.touch_min);
    try std.testing.expect(lay.permit.h >= tokens.Logical.touch_min);
    try std.testing.expect(lay.card_n >= 3);
    try std.testing.expectEqual(@as(u8, 3), lay.grid_cols);
    if (lay.card_n > 0) {
        try std.testing.expect(lay.cards[0].identify.h >= tokens.Logical.touch_min);
        try std.testing.expect(lay.cards[0].remove.h >= tokens.Logical.touch_min);
        try std.testing.expect(lay.cards[0].exposes_link.h >= tokens.Logical.touch_min);
    }
}
