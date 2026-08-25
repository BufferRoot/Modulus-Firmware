//! Quick Settings sheet — single panel (no tabs). Painted by `Engine.openQuickSettings`.
//! ponytail: icon tiles + bright/vol sliders + Zigbee device chips; no CNC/macro chrome.

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const icons_phosphor = @import("icons_phosphor.zig");
const prefs_mod = @import("settings_prefs.zig");
const color = @import("color.zig");
const dashboard = @import("dashboard.zig");
const zb_purpose = @import("zb_purpose.zig");

pub const panel_h: i32 = tokens.Motion.qs_panel_h;
const touch: i32 = tokens.Logical.touch_min;
const tile_h: i32 = 72;
const icon_px: i32 = icons_phosphor.size; // 24 — same for radios + Zigbee devices
const cols: i32 = 5;

const radio_labels = [_][]const u8{ "Wi-Fi", "BLE", "ESP-NOW", "Zigbee", "Thread" };
const action_labels = [_][]const u8{ "Airplane", "Quiet mode", "Screen lock", "Performance", "Theme" };

pub const Hit = enum {
    none,
    scrim,
    handle,
    gear,
    radio,
    action,
    bright,
    volume,
    zb_dev,
    zb_detail_scrim,
    zb_detail_identify,
    zb_detail_remove,
    zb_detail_refresh,
    zb_detail_cover,
    zb_detail_level,
};

pub const HitInfo = struct {
    kind: Hit = .none,
    index: u8 = 0,
};

/// Radio row: Wi-Fi, BLE, ESP-NOW, Zigbee, Thread.
pub const RadioId = enum(u8) { wifi, ble, espnow, zigbee, thread };

/// Action row: Airplane, Silent, Screen Lock, Performance, Dark/Light.
pub const ActionId = enum(u8) { airplane, silent, lock, perf, theme };

pub const PaintCtx = struct {
    press_x: i32 = -1,
    press_y: i32 = -1,
    press_t: f32 = 0,
    hover_rect: geom.Rect = .{},
    focus_rect: geom.Rect = .{},
    body_scroll: i32 = 0,
    /// 0xff = no Exposes overlay.
    zb_detail_idx: u8 = 0xff,
    cnc: ?*const dashboard.CncView = null,
    term_log: []const u8 = "",
    mdi: []const u8 = "",
    probe_trig: bool = false,
    /// When false, skip upper-band scrim (stationary QS live updates — underlay already dimmed).
    paint_scrim: bool = true,
};

pub fn closedY() i32 {
    return tokens.Logical.height;
}

pub fn openY() i32 {
    return tokens.Logical.height - panel_h;
}

pub fn panelRect(sy: i32) geom.Rect {
    return .{ .x = 0, .y = sy, .w = tokens.Logical.width, .h = panel_h };
}

pub fn isOpen(sy: f32) bool {
    return sy < @as(f32, @floatFromInt(closedY())) - 1;
}

pub fn handleHitRect(panel: geom.Rect) geom.Rect {
    return .{ .x = panel.x, .y = panel.y, .w = panel.w, .h = touch };
}

fn gearRect(panel: geom.Rect) geom.Rect {
    return .{
        .x = panel.x + panel.w - tokens.Space.sm - touch,
        .y = panel.y + @divTrunc(touch - touch, 2) + 8,
        .w = touch,
        .h = touch,
    };
}

fn bodyTop(panel: geom.Rect) i32 {
    return panel.y + touch + tokens.Space.sm;
}

fn bodyViewH() i32 {
    return panel_h - touch - tokens.Space.sm;
}

pub fn contentH(prefs: *const prefs_mod.Prefs) i32 {
    const zb_n = zbDevCount(prefs);
    const zb_block: i32 = if (zb_n > 0) tile_h + tokens.Space.sm else 0;
    return tile_h + tokens.Space.sm + tile_h + tokens.Space.md + touch + tokens.Space.sm + touch + tokens.Space.md + zb_block;
}

pub fn bodyScrollMax(prefs: *const prefs_mod.Prefs) i32 {
    return @max(0, contentH(prefs) - bodyViewH());
}

fn zbDevCount(prefs: *const prefs_mod.Prefs) u8 {
    return @min(prefs.wireless.zb_dev_n, prefs.wireless.zb_dev_on.len);
}

fn gridCell(panel: geom.Rect, scroll: i32, row: i32, col: i32) geom.Rect {
    const gap: i32 = tokens.Space.sm;
    const x0 = panel.x + tokens.Space.md;
    const avail = panel.w - tokens.Space.md * 2 - gap * (cols - 1);
    const tw = @divTrunc(avail, cols);
    return .{
        .x = x0 + col * (tw + gap),
        .y = bodyTop(panel) + scroll + row * (tile_h + tokens.Space.sm),
        .w = tw,
        .h = tile_h,
    };
}

fn radioRect(panel: geom.Rect, idx: u8, scroll: i32) geom.Rect {
    return gridCell(panel, scroll, 0, @intCast(idx));
}

fn actionRect(panel: geom.Rect, idx: u8, scroll: i32) geom.Rect {
    return gridCell(panel, scroll, 1, @intCast(idx));
}

fn brightRect(panel: geom.Rect, scroll: i32) geom.Rect {
    return .{
        .x = panel.x + tokens.Space.md,
        .y = bodyTop(panel) + scroll + 2 * (tile_h + tokens.Space.sm) + tokens.Space.sm,
        .w = panel.w - tokens.Space.md * 2,
        .h = touch,
    };
}

fn volumeRect(panel: geom.Rect, scroll: i32) geom.Rect {
    var r = brightRect(panel, scroll);
    r.y += touch + tokens.Space.sm;
    return r;
}

fn zbDevRect(panel: geom.Rect, idx: u8, scroll: i32) geom.Rect {
    // Same tile size as radio/action grid cells (icon 24 + label).
    const gap: i32 = tokens.Space.sm;
    const x0 = panel.x + tokens.Space.md;
    const avail = panel.w - tokens.Space.md * 2 - gap * 3;
    const tw = @divTrunc(avail, 4);
    const y = volumeRect(panel, scroll).y + touch + tokens.Space.md;
    return .{
        .x = x0 + @as(i32, idx) * (tw + gap),
        .y = y,
        .w = tw,
        .h = tile_h,
    };
}

fn sliderTrack(row: geom.Rect) geom.Rect {
    // "Brightness" label needs ~130px left; % label ~56px right.
    return .{
        .x = row.x + 130,
        .y = row.y + @divTrunc(row.h - 28, 2),
        .w = row.w - 130 - 56,
        .h = 28,
    };
}

fn fillSheetPanel(logical: *fb.LogicalFb, panel: geom.Rect, c: color.Rgb565) void {
    const rad = tokens.Shape.sheet;
    widgets.fillRoundRect(logical, panel, rad, c);
    if (panel.h > rad) {
        logical.fillRect(.{
            .x = panel.x,
            .y = panel.y + panel.h - rad,
            .w = panel.w,
            .h = rad,
        }, c);
    }
}

fn pressActive(ctx: PaintCtx) bool {
    return ctx.press_t > 0.08;
}

fn rippleT(ctx: PaintCtx, r: geom.Rect) f32 {
    if (pressActive(ctx) and r.contains(ctx.press_x, ctx.press_y)) return ctx.press_t;
    return 0;
}

fn paintIconTile(
    logical: *fb.LogicalFb,
    r: geom.Rect,
    icon: icons_phosphor.Id,
    label: []const u8,
    on: bool,
    theme: tokens.Theme,
    ctx: PaintCtx,
) void {
    const kind: widgets.ButtonKind = if (on) .primary_container else .outlined;
    const state = widgets.resolveButtonState(r, ctx.hover_rect, ctx.focus_rect, ctx.press_x, ctx.press_y, pressActive(ctx), false);
    const ink = widgets.drawButtonSurface(logical, r, kind, state, theme, rippleT(ctx, r), ctx.press_x, ctx.press_y);
    icons_phosphor.draw(logical, r.x + @divTrunc(r.w - icon_px, 2), r.y + 12, icon, ink);
    if (label.len != 0) {
        const tw = font.textWidthStr(label, .label_m);
        font.drawTextRole(logical, r.x + @divTrunc(r.w - tw, 2), r.y + 44, label, ink, .label_m);
    }
}

fn paintSliderRow(logical: *fb.LogicalFb, theme: tokens.Theme, r: geom.Rect, name: []const u8, pct: u8, ctx: PaintCtx) void {
    const state = widgets.resolveButtonState(r, ctx.hover_rect, ctx.focus_rect, ctx.press_x, ctx.press_y, pressActive(ctx), false);
    widgets.fillRoundRect(logical, r, tokens.Shape.md, theme.surface_container);
    const a = widgets.buttonStateAlpha(state);
    if (a != 0) widgets.drawStateLayerInk(logical, r, tokens.Shape.md, theme.on_surface, a);
    font.drawTextRole(logical, r.x + 8, r.y + @divTrunc(r.h - font.faceHeight(font.faceForRole(.body_m)), 2), name, theme.on_surface, .body_m);
    const track = sliderTrack(r);
    widgets.drawSlider(logical, track, @as(f32, @floatFromInt(pct)) / 100.0, theme);
    var buf: [8]u8 = undefined;
    const lab = std.fmt.bufPrint(&buf, "{d}%", .{pct}) catch "%";
    font.drawTextRole(logical, r.x + r.w - 52, r.y + @divTrunc(r.h - font.faceHeight(font.faceForRole(.label_l)), 2), lab, theme.on_surface_variant, .label_l);
}

fn zbDevShortLabel(prefs: *const prefs_mod.Prefs, idx: u8, buf: *[12]u8) []const u8 {
    const name = prefs.wireless.zbDevLabel(idx);
    if (name.len == 0) return "ZB";
    const n = @min(name.len, buf.len);
    @memcpy(buf[0..n], name[0..n]);
    return buf[0..n];
}

pub fn paint(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    prefs: *const prefs_mod.Prefs,
    sy: i32,
    ctx: PaintCtx,
) void {
    const panel = panelRect(sy);
    if (panel.y >= tokens.Logical.height) return;

    if (ctx.paint_scrim and sy < tokens.Logical.height) {
        const band_h = @max(0, sy);
        if (band_h > 0) {
            // Blend over painted underlay (engine paints dashboard/settings first).
            widgets.paintScrimOver(logical, .{
                .x = 0,
                .y = 0,
                .w = tokens.Logical.width,
                .h = band_h,
            }, theme);
        }
    }

    fillSheetPanel(logical, panel, theme.surface_container);

    widgets.fillRoundRect(logical, .{
        .x = panel.x + @divTrunc(panel.w - 32, 2),
        .y = panel.y + 10,
        .w = 32,
        .h = 4,
    }, 2, theme.outline_variant);

    const gear = gearRect(panel);
    {
        const state = widgets.resolveButtonState(gear, ctx.hover_rect, ctx.focus_rect, ctx.press_x, ctx.press_y, pressActive(ctx), false);
        const ink = widgets.drawIconButtonChrome(logical, gear, .tonal, state, false, theme);
        icons_phosphor.draw(logical, gear.x + 12, gear.y + 12, .gear, ink);
        if (state == .pressed and rippleT(ctx, gear) > 0.02) {
            widgets.drawButtonRipple(logical, gear, ctx.press_x, ctx.press_y, rippleT(ctx, gear), ink);
        }
    }

    const scroll = -ctx.body_scroll;
    const w = prefs.wireless;
    const radio_on = [_]bool{
        w.wifi and !w.airplane,
        w.bt and !w.airplane,
        w.espnow and !w.airplane,
        w.zigbee and !w.airplane,
        w.thread and !w.airplane,
    };
    const radio_icons = [_]icons_phosphor.Id{ .wifi, .bluetooth, .broadcast, .lightning, .rss_simple };
    var ri: u8 = 0;
    while (ri < 5) : (ri += 1) {
        paintIconTile(logical, radioRect(panel, ri, scroll), radio_icons[ri], radio_labels[ri], radio_on[ri], theme, ctx);
    }

    const action_on = [_]bool{
        w.airplane,
        prefs.audio.silent,
        false, // lock is momentary
        prefs.system.perf_hud,
        prefs.display.darkmode,
    };
    const action_icons = [_]icons_phosphor.Id{ .airplane, .speaker_slash, .lock_key, .speedometer, .paint_roller };
    var ai: u8 = 0;
    while (ai < 5) : (ai += 1) {
        const lab: []const u8 = if (ai == 4)
            (if (prefs.display.darkmode) "Light theme" else "Dark theme")
        else
            action_labels[ai];
        paintIconTile(logical, actionRect(panel, ai, scroll), action_icons[ai], lab, action_on[ai], theme, ctx);
    }

    paintSliderRow(logical, theme, brightRect(panel, scroll), "Brightness", prefs.display.bright, ctx);
    const vol_show: u8 = if (prefs.audio.silent) 0 else prefs.audio.vol;
    paintSliderRow(logical, theme, volumeRect(panel, scroll), "Volume", vol_show, ctx);

    const n = zbDevCount(prefs);
    var zi: u8 = 0;
    while (zi < n) : (zi += 1) {
        var name_buf: [12]u8 = undefined;
        const name = zbDevShortLabel(prefs, zi, &name_buf);
        const snap = prefs.wireless.zbSnap(zi);
        const full_name = prefs.wireless.zbDevLabel(zi);
        const purpose = zb_purpose.classifySnap(full_name, snap);
        paintIconTile(
            logical,
            zbDevRect(panel, zi, scroll),
            zb_purpose.icon(purpose),
            name,
            prefs.wireless.zb_dev_on[zi],
            theme,
            ctx,
        );
    }

    if (ctx.zb_detail_idx != 0xff and ctx.zb_detail_idx < zbDevCount(prefs)) {
        paintZbDetail(logical, theme, prefs, panel, ctx.zb_detail_idx, ctx);
    }
}

pub fn detailCardRect(panel: geom.Rect) geom.Rect {
    const w: i32 = @min(460, panel.w - 32);
    const h: i32 = @min(panel.h - 24, 360);
    return .{
        .x = panel.x + @divTrunc(panel.w - w, 2),
        .y = panel.y + @divTrunc(panel.h - h, 2),
        .w = w,
        .h = h,
    };
}

fn detailBtnRect(card: geom.Rect, col: u8, row: u8) geom.Rect {
    const gap: i32 = 8;
    const bw: i32 = @divTrunc(card.w - 24 - gap * 2, 3);
    return .{
        .x = card.x + 12 + @as(i32, col) * (bw + gap),
        .y = card.y + card.h - touch - 12 - @as(i32, row) * (touch + gap),
        .w = bw,
        .h = touch,
    };
}

pub fn detailLevelRow(card: geom.Rect) geom.Rect {
    return .{
        .x = card.x + 12,
        .y = card.y + 120,
        .w = card.w - 24,
        .h = touch,
    };
}

fn paintDetailChip(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, theme: tokens.Theme, ctx: PaintCtx) void {
    const state = widgets.resolveButtonState(r, ctx.hover_rect, ctx.focus_rect, ctx.press_x, ctx.press_y, pressActive(ctx), false);
    const ink = widgets.drawButtonSurface(logical, r, .tonal, state, theme, rippleT(ctx, r), ctx.press_x, ctx.press_y);
    const tw = font.textWidthStr(label, .label_m);
    font.drawTextRole(logical, r.x + @divTrunc(r.w - tw, 2), r.y + @divTrunc(r.h - font.faceHeight(font.faceForRole(.label_m)), 2), label, ink, .label_m);
}

fn paintZbDetail(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    prefs: *const prefs_mod.Prefs,
    panel: geom.Rect,
    idx: u8,
    ctx: PaintCtx,
) void {
    widgets.fillScrimRect(logical, panel, theme);
    const card = detailCardRect(panel);
    widgets.fillRoundRect(logical, card, tokens.Shape.dialog, theme.elev(3));
    widgets.strokeRoundRect(logical, card, tokens.Shape.dialog, theme.outline_variant, 1);

    const name = prefs.wireless.zbDevLabel(idx);
    font.drawTextRole(logical, card.x + 16, card.y + 16, name, theme.on_surface, .title_m);
    font.drawTextRole(logical, card.x + 16, card.y + 44, "Endpoints", theme.on_surface_variant, .label_l);

    const snap = prefs.wireless.zbSnap(idx);
    var y: i32 = card.y + 68;
    var line_buf: [64]u8 = undefined;

    if (snap.modelSlice().len > 0) {
        const m = std.fmt.bufPrint(&line_buf, "Model {s}", .{snap.modelSlice()}) catch "Model";
        font.drawTextRole(logical, card.x + 16, y, m, theme.on_surface_variant, .body_m);
        y += 22;
    }
    if (snap.short_addr != 0 and (snap.lqi != 0 or snap.rssi != 0)) {
        const lk = if (snap.rssi != 0)
            (std.fmt.bufPrint(&line_buf, "LQI {d} | {d} dBm", .{ snap.lqi, snap.rssi }) catch "LQI")
        else
            (std.fmt.bufPrint(&line_buf, "LQI {d}", .{snap.lqi}) catch "LQI");
        font.drawTextRole(logical, card.x + 16, y, lk, theme.on_surface_variant, .body_m);
        y += 22;
    }

    // Cap chips
    var caps_lab: [48]u8 = undefined;
    var clen: usize = 0;
    const add = struct {
        fn push(dst: []u8, len: *usize, s: []const u8) void {
            if (len.* > 0 and len.* + 2 < dst.len) {
                dst[len.*] = ',';
                dst[len.* + 1] = ' ';
                len.* += 2;
            }
            const n = @min(s.len, dst.len -| len.*);
            @memcpy(dst[len.*..][0..n], s[0..n]);
            len.* += n;
        }
    }.push;
    if (snap.caps == 0 or (snap.caps & prefs_mod.ZbCap.onoff) != 0) add(&caps_lab, &clen, "On/Off");
    if ((snap.caps & prefs_mod.ZbCap.level) != 0) add(&caps_lab, &clen, "Level");
    if ((snap.caps & prefs_mod.ZbCap.cover) != 0) add(&caps_lab, &clen, "Cover");
    if ((snap.caps & prefs_mod.ZbCap.sensor) != 0) add(&caps_lab, &clen, "Sensor");
    if ((snap.caps & (prefs_mod.ZbCap.power | prefs_mod.ZbCap.meter)) != 0) add(&caps_lab, &clen, "Power");
    if ((snap.caps & prefs_mod.ZbCap.color) != 0) add(&caps_lab, &clen, "Color");
    if (clen > 0) {
        font.drawTextRole(logical, card.x + 16, y, caps_lab[0..clen], theme.primary, .body_m);
        y += 22;
    }

    if ((snap.caps & prefs_mod.ZbCap.sensor) != 0 and snap.zone_seen) {
        const zn: []const u8 = if ((snap.zone_status & 0x0001) != 0) "Zone: alarm (open)" else "Zone: clear";
        const c = if ((snap.zone_status & 0x0001) != 0) theme.err else theme.on_surface_variant;
        font.drawTextRole(logical, card.x + 16, y, zn, c, .body_m);
        y += 22;
    }

    if ((snap.caps & prefs_mod.ZbCap.level) != 0) {
        const row = detailLevelRow(card);
        const pct: u8 = @intCast(@min(100, (@as(u16, snap.level) * 100) / 254));
        paintSliderRow(logical, theme, row, "Level", pct, ctx);
    }

    if ((snap.caps & (prefs_mod.ZbCap.power | prefs_mod.ZbCap.meter)) != 0) {
        const py = if ((snap.caps & prefs_mod.ZbCap.level) != 0) detailLevelRow(card).y + touch + 8 else y;
        const ptxt = if (snap.sensors_seen != 0)
            (std.fmt.bufPrint(&line_buf, "{d}.{d}V  {d}mA  {d}.{d}W", .{
                snap.volt_raw / 10,
                snap.volt_raw % 10,
                snap.curr_raw,
                @divTrunc(@as(i32, @intCast(@abs(snap.power_raw))), 10),
                @mod(@as(i32, @intCast(@abs(snap.power_raw))), 10),
            }) catch "Power")
        else
            "Tap refresh for readings.";
        font.drawTextRole(logical, card.x + 16, py, ptxt, theme.on_surface_variant, .body_m);
    }

    var btn_col: u8 = 0;
    var btn_row: u8 = 0;
    const place = struct {
        fn next(col: *u8, row: *u8) void {
            col.* += 1;
            if (col.* >= 3) {
                col.* = 0;
                row.* += 1;
            }
        }
    }.next;

    if ((snap.caps & prefs_mod.ZbCap.cover) != 0) {
        paintDetailChip(logical, detailBtnRect(card, btn_col, btn_row), "Open", theme, ctx);
        place(&btn_col, &btn_row);
        paintDetailChip(logical, detailBtnRect(card, btn_col, btn_row), "Close", theme, ctx);
        place(&btn_col, &btn_row);
        paintDetailChip(logical, detailBtnRect(card, btn_col, btn_row), "Stop", theme, ctx);
        place(&btn_col, &btn_row);
    }
    if ((snap.caps & (prefs_mod.ZbCap.power | prefs_mod.ZbCap.meter)) != 0) {
        paintDetailChip(logical, detailBtnRect(card, btn_col, btn_row), "Refresh", theme, ctx);
        place(&btn_col, &btn_row);
    }
    if (snap.short_addr != 0) {
        paintDetailChip(logical, detailBtnRect(card, btn_col, btn_row), "Identify", theme, ctx);
        place(&btn_col, &btn_row);
    }
    paintDetailChip(logical, detailBtnRect(card, btn_col, btn_row), "Remove", theme, ctx);
}

pub fn interactiveRect(info: HitInfo, sy: i32, prefs: *const prefs_mod.Prefs, body_scroll: i32) geom.Rect {
    _ = prefs;
    if (info.kind == .none or info.kind == .scrim or info.kind == .handle or info.kind == .zb_detail_scrim) return .{};
    const panel = panelRect(sy);
    const scroll = -body_scroll;
    const card = detailCardRect(panel);
    return switch (info.kind) {
        .none, .scrim, .handle, .zb_detail_scrim => .{},
        .gear => gearRect(panel),
        .radio => radioRect(panel, info.index, scroll),
        .action => actionRect(panel, info.index, scroll),
        .bright => brightRect(panel, scroll),
        .volume => volumeRect(panel, scroll),
        .zb_dev => zbDevRect(panel, info.index, scroll),
        .zb_detail_identify, .zb_detail_remove, .zb_detail_refresh, .zb_detail_cover => detailBtnRect(card, info.index % 3, info.index / 3),
        .zb_detail_level => detailLevelRow(card),
    };
}

fn hitDetail(x: i32, y: i32, panel: geom.Rect, prefs: *const prefs_mod.Prefs, idx: u8) HitInfo {
    const card = detailCardRect(panel);
    if (!card.contains(x, y)) return .{ .kind = .zb_detail_scrim };
    const snap = prefs.wireless.zbSnap(idx);
    if ((snap.caps & prefs_mod.ZbCap.level) != 0 and detailLevelRow(card).contains(x, y)) {
        return .{ .kind = .zb_detail_level, .index = idx };
    }
    var btn_col: u8 = 0;
    var btn_row: u8 = 0;
    if ((snap.caps & prefs_mod.ZbCap.cover) != 0) {
        var op: u8 = 0;
        while (op < 3) : (op += 1) {
            if (detailBtnRect(card, btn_col, btn_row).contains(x, y)) {
                return .{ .kind = .zb_detail_cover, .index = op };
            }
            btn_col += 1;
            if (btn_col >= 3) {
                btn_col = 0;
                btn_row += 1;
            }
        }
    }
    if ((snap.caps & (prefs_mod.ZbCap.power | prefs_mod.ZbCap.meter)) != 0) {
        if (detailBtnRect(card, btn_col, btn_row).contains(x, y)) return .{ .kind = .zb_detail_refresh };
        btn_col += 1;
        if (btn_col >= 3) {
            btn_col = 0;
            btn_row += 1;
        }
    }
    if (snap.short_addr != 0) {
        if (detailBtnRect(card, btn_col, btn_row).contains(x, y)) return .{ .kind = .zb_detail_identify };
        btn_col += 1;
        if (btn_col >= 3) {
            btn_col = 0;
            btn_row += 1;
        }
    }
    if (detailBtnRect(card, btn_col, btn_row).contains(x, y)) return .{ .kind = .zb_detail_remove };
    // Card body: absorb, do not close (only dimmed area outside card closes).
    return .{};
}

pub fn hit(x: i32, y: i32, sy: i32, prefs: *const prefs_mod.Prefs, body_scroll: i32, zb_detail_idx: u8) HitInfo {
    if (!isOpen(@floatFromInt(sy))) return .{};
    const panel = panelRect(sy);
    if (zb_detail_idx != 0xff and zb_detail_idx < zbDevCount(prefs)) {
        if (y < panel.y) return .{ .kind = .zb_detail_scrim };
        return hitDetail(x, y, panel, prefs, zb_detail_idx);
    }
    if (y < panel.y) return .{ .kind = .scrim };
    if (!panel.contains(x, y)) return .{};

    if (handleHitRect(panel).contains(x, y) and y < bodyTop(panel)) return .{ .kind = .handle };
    if (gearRect(panel).contains(x, y)) return .{ .kind = .gear };

    const scroll = -body_scroll;
    var i: u8 = 0;
    while (i < 5) : (i += 1) {
        if (radioRect(panel, i, scroll).contains(x, y)) return .{ .kind = .radio, .index = i };
    }
    i = 0;
    while (i < 5) : (i += 1) {
        if (actionRect(panel, i, scroll).contains(x, y)) return .{ .kind = .action, .index = i };
    }
    if (brightRect(panel, scroll).contains(x, y)) return .{ .kind = .bright };
    if (volumeRect(panel, scroll).contains(x, y)) return .{ .kind = .volume };
    const n = zbDevCount(prefs);
    i = 0;
    while (i < n) : (i += 1) {
        if (zbDevRect(panel, i, scroll).contains(x, y)) return .{ .kind = .zb_dev, .index = i };
    }
    return .{};
}

pub fn sliderPctFromX(row: geom.Rect, x: i32) u8 {
    const track = sliderTrack(row);
    if (track.w <= 0) return 0;
    const t = @as(f32, @floatFromInt(x - track.x)) / @as(f32, @floatFromInt(track.w));
    return @intFromFloat(@round(std.math.clamp(t, 0, 1) * 100.0));
}

pub fn brightHitRect(sy: i32, body_scroll: i32) geom.Rect {
    return brightRect(panelRect(sy), -body_scroll);
}

pub fn volumeHitRect(sy: i32, body_scroll: i32) geom.Rect {
    return volumeRect(panelRect(sy), -body_scroll);
}

/// Append TX/RX line into fixed host scrollback (console bridge).
pub fn termAppend(buf: []u8, len: *usize, line: []const u8, tx: bool) void {
    const prefix: []const u8 = if (tx) "> " else "";
    const need = prefix.len + line.len + 1;
    if (need >= buf.len) return;
    if (len.* + need >= buf.len) {
        const cut = len.* / 2;
        const keep = len.* - cut;
        @memmove(buf[0..keep], buf[cut..][0..keep]);
        len.* = keep;
    }
    @memcpy(buf[len.*..][0..prefix.len], prefix);
    len.* += prefix.len;
    @memcpy(buf[len.*..][0..line.len], line);
    len.* += line.len;
    buf[len.*] = '\n';
    len.* += 1;
}

test "qs panel openY clears height" {
    try std.testing.expectEqual(@as(i32, tokens.Logical.height - panel_h), openY());
    try std.testing.expect(isOpen(@floatFromInt(openY())));
    try std.testing.expect(!isOpen(@floatFromInt(closedY())));
}

test "qs touch targets meet 48" {
    const p = panelRect(openY());
    try std.testing.expect(gearRect(p).h >= touch);
    try std.testing.expect(brightRect(p, 0).h >= touch);
    try std.testing.expect(volumeRect(p, 0).h >= touch);
    try std.testing.expect(handleHitRect(p).h >= touch);
    try std.testing.expect(radioRect(p, 0, 0).h >= touch);
    try std.testing.expect(actionRect(p, 0, 0).h >= touch);
    try std.testing.expect(zbDevRect(p, 0, 0).h == tile_h);
    try std.testing.expect(zbDevRect(p, 0, 0).h == radioRect(p, 0, 0).h);
}

test "qs slider track follows finger x" {
    const row = brightRect(panelRect(openY()), 0);
    const track = sliderTrack(row);
    try std.testing.expectEqual(@as(u8, 0), sliderPctFromX(row, track.x));
    try std.testing.expectEqual(@as(u8, 100), sliderPctFromX(row, track.x + track.w));
    const mid = sliderPctFromX(row, track.x + @divTrunc(track.w, 2));
    try std.testing.expect(mid >= 45 and mid <= 55);
}

test "qs zb detail: outside card closes, body absorbs" {
    var prefs: prefs_mod.Prefs = .{};
    prefs.wireless.live_zb_n = 1;
    prefs.wireless.zb_dev_n = 1;
    prefs.wireless.live_zb_snap[0] = .{ .caps = prefs_mod.ZbCap.onoff, .short_addr = 0x1234 };
    const sy = openY();
    const panel = panelRect(sy);
    const card = detailCardRect(panel);
    // Dimmed margin left of card
    const outside = hit(card.x - 8, card.y + @divTrunc(card.h, 2), sy, &prefs, 0, 0);
    try std.testing.expect(outside.kind == .zb_detail_scrim);
    // Empty card body (not a button)
    const body = hit(card.x + 20, card.y + 80, sy, &prefs, 0, 0);
    try std.testing.expect(body.kind == .none);
    // Above sheet
    const above = hit(100, panel.y - 20, sy, &prefs, 0, 0);
    try std.testing.expect(above.kind == .zb_detail_scrim);
}

