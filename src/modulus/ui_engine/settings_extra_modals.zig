//! Gap-fill settings overlays — transport, Wi-Fi, BT, ZB/TH, probe, MPG, idle lock.
//! MD3: Space.* rhythm, outlined fields, tonal close, segments/menus for enums.

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const prefs_mod = @import("settings_prefs.zig");

pub const Kind = enum {
    none,
    transport,
    wifi_connect,
    bt_passkey,
    zb_add,
    th_add,
    probe,
    mpg,
    idle_lock,
};

pub const Hit = enum {
    none,
    close,
    primary,
    secondary,
    field0,
    field1,
    field2,
    field3,
    field4,
    toggle0,
    toggle1,
    /// Opens menu or advances small enum (legacy name; prefer menu from engine).
    cycle0,
    cycle1,
    seg0,
    seg1,
    inv0,
    inv1,
    inv2,
    inv3,
    inv4,
    inv5,
};

pub const Layout = struct {
    card: geom.Rect = .{},
    close: geom.Rect = .{},
    primary: geom.Rect = .{},
    secondary: geom.Rect = .{},
    field: [5]geom.Rect = [_]geom.Rect{.{}} ** 5,
    toggle: [2]geom.Rect = [_]geom.Rect{.{}} ** 2,
    cycle: [2]geom.Rect = [_]geom.Rect{.{}} ** 2,
    seg: [2]geom.Rect = [_]geom.Rect{.{}} ** 2,
    inv: [6]geom.Rect = [_]geom.Rect{.{}} ** 6,
    inv_n: u8 = 0,
};

const close_sz: i32 = tokens.Logical.touch_min;
const hit_h: i32 = tokens.Logical.touch_min;
const field_h: i32 = tokens.Logical.touch_min;

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

/// Title + optional support; returns y for first body row.
fn paintCard(logical: *fb.LogicalFb, theme: tokens.Theme, card: geom.Rect, title: []const u8, support: []const u8, lay: *Layout) i32 {
    widgets.fillScrim(logical, theme);
    widgets.fillRoundRect(logical, card, tokens.Shape.dialog, theme.elev(3));
    // No outline stroke — MD3 dialog elevation is tonal (matches PIN / machine-name).
    lay.card = card;
    const title_y = card.y + tokens.Space.md;
    font.drawTextRole(logical, card.x + tokens.Space.lg, title_y, title, theme.on_surface, .title_l);
    lay.close = .{
        .x = card.x + card.w - close_sz - tokens.Space.md,
        .y = card.y + tokens.Space.sm,
        .w = close_sz,
        .h = close_sz,
    };
    widgets.drawTonalCloseButton(logical, lay.close, theme);

    var y = title_y + font.faceHeight(font.faceForRole(.title_l)) + tokens.Space.sm;
    if (support.len > 0) {
        font.drawTextRole(logical, card.x + tokens.Space.lg, y, support, theme.on_surface_variant, .body_s);
        y += font.faceHeight(font.faceForRole(.body_s)) + tokens.Space.md;
    } else {
        y += tokens.Space.sm;
    }
    return y;
}

fn paintLabeledField(logical: *fb.LogicalFb, theme: tokens.Theme, x: i32, y: *i32, row_w: i32, label: []const u8, value: []const u8, placeholder: []const u8) geom.Rect {
    font.drawTextRole(logical, x, y.*, label, theme.on_surface_variant, .label_m);
    y.* += font.faceHeight(font.faceForRole(.label_m)) + tokens.Space.xs;
    const r: geom.Rect = .{ .x = x, .y = y.*, .w = row_w, .h = field_h };
    const shown = if (value.len > 0) value else "";
    const ph = if (value.len > 0) "" else placeholder;
    widgets.drawOutlinedTextField(logical, r, shown, ph, false, true, false, theme);
    y.* += field_h + tokens.Space.md;
    return r;
}

fn paintDropdownRow(logical: *fb.LogicalFb, theme: tokens.Theme, x: i32, y: *i32, row_w: i32, label: []const u8, value: []const u8) geom.Rect {
    font.drawTextRole(logical, x, y.*, label, theme.on_surface_variant, .label_m);
    y.* += font.faceHeight(font.faceForRole(.label_m)) + tokens.Space.xs;
    const r: geom.Rect = .{ .x = x, .y = y.*, .w = row_w, .h = field_h };
    widgets.fillRoundRect(logical, r, tokens.Shape.sm, theme.surface_container_highest);
    widgets.strokeRoundRect(logical, r, tokens.Shape.sm, theme.outline, 1);
    const lh = font.faceHeight(font.faceForRole(.body_m));
    font.drawTextRole(logical, r.x + tokens.Space.md, r.y + @divTrunc(r.h - lh, 2), value, theme.on_surface, .body_m);
    widgets.drawChevronDown(logical, r.x + r.w - tokens.Space.lg, r.y + @divTrunc(r.h, 2), 5, theme.on_surface_variant);
    y.* += field_h + tokens.Space.md;
    return r;
}

fn paintSegBlock(logical: *fb.LogicalFb, theme: tokens.Theme, x: i32, y: *i32, row_w: i32, label: []const u8, labs: []const []const u8, selected: usize) geom.Rect {
    font.drawTextRole(logical, x, y.*, label, theme.on_surface_variant, .label_m);
    y.* += font.faceHeight(font.faceForRole(.label_m)) + tokens.Space.xs;
    const r: geom.Rect = .{ .x = x, .y = y.*, .w = row_w, .h = field_h };
    widgets.drawSegmented(logical, r, labs, selected, theme);
    y.* += field_h + tokens.Space.md;
    return r;
}

fn paintToggleRow(logical: *fb.LogicalFb, theme: tokens.Theme, x: i32, y: *i32, row_w: i32, label: []const u8, on: bool) geom.Rect {
    const r: geom.Rect = .{ .x = x, .y = y.*, .w = row_w, .h = hit_h };
    widgets.fillRoundRect(logical, r, tokens.Shape.sm, theme.surface_container_high);
    const lh = font.faceHeight(font.faceForRole(.body_m));
    font.drawTextRole(logical, r.x + tokens.Space.md, r.y + @divTrunc(r.h - lh, 2), label, theme.on_surface, .body_m);
    const sx = widgets.switchTrailingX(r.x, r.w);
    const sy = r.y + @divTrunc(r.h - widgets.switch_h, 2);
    widgets.drawSwitch(logical, sx, sy, if (on) 1 else 0, theme, true, true);
    y.* += hit_h + tokens.Space.sm;
    return r;
}

fn paintFilledBtn(logical: *fb.LogicalFb, theme: tokens.Theme, r: geom.Rect, label: []const u8) void {
    widgets.drawFilledButton(logical, r, label, theme);
}

fn paintTonalBtn(logical: *fb.LogicalFb, theme: tokens.Theme, r: geom.Rect, label: []const u8) void {
    widgets.drawTonalButton(logical, r, label, theme);
}

fn footerBtns(card: geom.Rect, lay: *Layout, dual: bool) void {
    const btn_h = @max(tokens.ButtonSize.m.height(), hit_h);
    const y = card.y + card.h - btn_h - tokens.Space.lg;
    if (dual) {
        const gap: i32 = tokens.Space.sm;
        const bw = @divTrunc(card.w - tokens.Space.lg * 2 - gap, 2);
        lay.secondary = .{ .x = card.x + tokens.Space.lg, .y = y, .w = bw, .h = btn_h };
        lay.primary = .{ .x = lay.secondary.x + bw + gap, .y = y, .w = bw, .h = btn_h };
    } else {
        lay.primary = .{ .x = card.x + tokens.Space.lg, .y = y, .w = card.w - tokens.Space.lg * 2, .h = btn_h };
        lay.secondary = .{};
    }
}

pub fn paintTransport(logical: *fb.LogicalFb, theme: tokens.Theme, c: *const prefs_mod.CncPrefs, enter_t: f32) Layout {
    var lay: Layout = .{};
    const name = prefs_mod.transport_names[@min(c.conn, prefs_mod.transport_names.len - 1)];
    var title_buf: [40]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buf, "{s} Configuration", .{name}) catch "Transport";
    const card = cardGeom(520, 520, enter_t);
    var y = paintCard(logical, theme, card, title, "Edit params then set active & connect.", &lay);
    const x = card.x + tokens.Space.lg;
    const row_w = card.w - tokens.Space.lg * 2;

    const active = !c.transport_off and c.conn < prefs_mod.transport_names.len;
    font.drawTextRole(logical, x, y, "Active transport", theme.on_surface_variant, .label_m);
    y += font.faceHeight(font.faceForRole(.label_m)) + tokens.Space.xs;
    {
        const r: geom.Rect = .{ .x = x, .y = y, .w = row_w, .h = field_h };
        widgets.drawOutlinedTextField(logical, r, if (active) "Currently active" else "Inactive", "", false, false, false, theme);
        y += field_h + tokens.Space.md;
    }

    var fbuf: [48]u8 = undefined;
    switch (c.conn) {
        1 => {
            lay.field[0] = paintLabeledField(logical, theme, x, &y, row_w, "Host", c.wsHostSlice(), "hostname");
            const port = std.fmt.bufPrint(&fbuf, "{d}", .{c.ws_port}) catch "?";
            lay.field[1] = paintLabeledField(logical, theme, x, &y, row_w, "Port", port, "81");
            lay.field[2] = paintLabeledField(logical, theme, x, &y, row_w, "Path", c.wsPathSlice(), "/");
            lay.toggle[0] = paintToggleRow(logical, theme, x, &y, row_w, "TLS (wss://)", c.ws_tls);
        },
        2 => {
            lay.field[0] = paintLabeledField(logical, theme, x, &y, row_w, "Host", c.tnHostSlice(), "hostname");
            const port = std.fmt.bufPrint(&fbuf, "{d}", .{c.tn_port}) catch "?";
            lay.field[1] = paintLabeledField(logical, theme, x, &y, row_w, "Port", port, "23");
        },
        3 => {
            lay.cycle[0] = paintDropdownRow(logical, theme, x, &y, row_w, "Baud rate", prefs_mod.CncPrefs.baudLabel(c.ser_baud_idx));
        },
        4 => {
            lay.cycle[0] = paintDropdownRow(logical, theme, x, &y, row_w, "Baud rate", prefs_mod.CncPrefs.baudLabel(c.r4_baud_idx));
        },
        5 => {
            lay.field[0] = paintLabeledField(logical, theme, x, &y, row_w, "Device name", c.bleNameSlice(), "Scan to find");
        },
        6 => {
            const addr = std.fmt.bufPrint(&fbuf, "0x{X:0>2}", .{c.i2c_addr}) catch "?";
            lay.field[0] = paintLabeledField(logical, theme, x, &y, row_w, "Slave address", addr, "0x50");
            const spd = [_][]const u8{ "100 kHz", "400 kHz" };
            lay.seg[0] = paintSegBlock(logical, theme, x, &y, row_w, "Speed", &spd, @min(c.i2c_spd, 1));
        },
        7 => {
            const rates = [_][]const u8{ "125K", "250K", "500K", "1M" };
            lay.seg[0] = paintSegBlock(logical, theme, x, &y, row_w, "Bitrate", &rates, @min(c.can_brate, 3));
            const nid = std.fmt.bufPrint(&fbuf, "{d}", .{c.can_nid}) catch "?";
            lay.field[0] = paintLabeledField(logical, theme, x, &y, row_w, "Node ID", nid, "1");
        },
        else => {},
    }

    footerBtns(card, &lay, false);
    paintFilledBtn(logical, theme, lay.primary, "Set as active & connect");
    return lay;
}

pub fn paintWifiConnect(logical: *fb.LogicalFb, theme: tokens.Theme, ssid: []const u8, pass: []const u8, enter_t: f32) Layout {
    var lay: Layout = .{};
    var title_buf: [48]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buf, "Connect to {s}", .{ssid}) catch "Connect";
    const card = cardGeom(480, 340, enter_t);
    var y = paintCard(logical, theme, card, title, "Enter password then connect.", &lay);
    const x = card.x + tokens.Space.lg;
    const row_w = card.w - tokens.Space.lg * 2;
    const masked: []const u8 = if (pass.len == 0) "" else "********";
    lay.field[0] = paintLabeledField(logical, theme, x, &y, row_w, "Password", masked, "Tap to enter");
    footerBtns(card, &lay, true);
    paintTonalBtn(logical, theme, lay.secondary, "Cancel");
    paintFilledBtn(logical, theme, lay.primary, "Connect");
    return lay;
}

pub fn paintBtPasskey(logical: *fb.LogicalFb, theme: tokens.Theme, name: []const u8, digits: []const u8, enter_t: f32) Layout {
    var lay: Layout = .{};
    const card = cardGeom(440, 320, enter_t);
    var y = paintCard(logical, theme, card, "Bluetooth pairing", name, &lay);
    const x = card.x + tokens.Space.lg;
    const row_w = card.w - tokens.Space.lg * 2;
    lay.field[0] = paintLabeledField(logical, theme, x, &y, row_w, "Passkey", digits, "Tap to enter");
    footerBtns(card, &lay, true);
    paintTonalBtn(logical, theme, lay.secondary, "Cancel");
    paintFilledBtn(logical, theme, lay.primary, "Confirm");
    return lay;
}

pub fn paintZbAdd(logical: *fb.LogicalFb, theme: tokens.Theme, code: []const u8, enter_t: f32) Layout {
    var lay: Layout = .{};
    const card = cardGeom(480, 320, enter_t);
    var y = paintCard(logical, theme, card, "Add Zigbee device", "Install code.", &lay);
    const x = card.x + tokens.Space.lg;
    const row_w = card.w - tokens.Space.lg * 2;
    lay.field[0] = paintLabeledField(logical, theme, x, &y, row_w, "Install code", code, "Tap to enter");
    footerBtns(card, &lay, true);
    paintTonalBtn(logical, theme, lay.secondary, "Cancel");
    paintFilledBtn(logical, theme, lay.primary, "Add");
    return lay;
}

pub fn paintThAdd(logical: *fb.LogicalFb, theme: tokens.Theme, node: []const u8, enter_t: f32) Layout {
    var lay: Layout = .{};
    const card = cardGeom(480, 320, enter_t);
    var y = paintCard(logical, theme, card, "Add Thread node", "Manual join.", &lay);
    const x = card.x + tokens.Space.lg;
    const row_w = card.w - tokens.Space.lg * 2;
    lay.field[0] = paintLabeledField(logical, theme, x, &y, row_w, "Node ID / EUI", node, "Tap to enter");
    footerBtns(card, &lay, true);
    paintTonalBtn(logical, theme, lay.secondary, "Cancel");
    paintFilledBtn(logical, theme, lay.primary, "Add");
    return lay;
}

pub fn paintProbe(logical: *fb.LogicalFb, theme: tokens.Theme, dash: *const prefs_mod.DashboardPrefs, busy: bool, enter_t: f32) Layout {
    var lay: Layout = .{};
    const card = cardGeom(480, 340, enter_t);
    var y = paintCard(logical, theme, card, "Probe Z-plate", "Tap thickness to edit. Edge/center: Quick Settings -> Probe.", &lay);
    const x = card.x + tokens.Space.lg;
    const row_w = card.w - tokens.Space.lg * 2;

    var pbuf: [24]u8 = undefined;
    const plate = std.fmt.bufPrint(&pbuf, "{d}.{d} mm", .{ dash.probe_zoff_x10 / 10, dash.probe_zoff_x10 % 10 }) catch "?";
    lay.field[0] = paintLabeledField(logical, theme, x, &y, row_w, "Plate thickness", plate, "e.g. 1.0");

    font.drawTextRole(logical, x, y, "Status", theme.on_surface_variant, .label_m);
    y += font.faceHeight(font.faceForRole(.label_m)) + tokens.Space.xs;
    const status: []const u8 = if (busy) "Probing plate..." else "Ready";
    const status_c = if (busy) theme.primary else theme.on_surface;
    font.drawTextRole(logical, x, y, status, status_c, .body_m);

    footerBtns(card, &lay, true);
    paintTonalBtn(logical, theme, lay.secondary, "Cancel");
    paintFilledBtn(logical, theme, lay.primary, if (busy) "Busy" else "Start");
    return lay;
}

pub fn paintMpg(logical: *fb.LogicalFb, theme: tokens.Theme, dash: *const prefs_mod.DashboardPrefs, enter_t: f32) Layout {
    var lay: Layout = .{};
    const n = dash.axesVisible();
    const card_h: i32 = tokens.Space.lg * 2 + 80 + @as(i32, @intCast(n)) * (hit_h + tokens.Space.sm) + tokens.ButtonSize.m.height() + tokens.Space.lg;
    const card = cardGeom(480, @max(360, card_h), enter_t);
    var y = paintCard(logical, theme, card, "MPG direction", "Invert handwheel direction per axis.", &lay);
    const labs = [_][]const u8{ "X Inverted", "Y Inverted", "Z Inverted", "A Inverted", "B Inverted", "C Inverted" };
    lay.inv_n = n;
    const x = card.x + tokens.Space.lg;
    const row_w = card.w - tokens.Space.lg * 2;
    var i: u8 = 0;
    while (i < n and i < 6) : (i += 1) {
        const on = (dash.mpgpol & (@as(u8, 1) << @intCast(i))) != 0;
        lay.inv[i] = paintToggleRow(logical, theme, x, &y, row_w, labs[i], on);
    }
    footerBtns(card, &lay, false);
    paintFilledBtn(logical, theme, lay.primary, "Done");
    return lay;
}

pub fn paintIdleLock(logical: *fb.LogicalFb, theme: tokens.Theme, s: *const prefs_mod.SecurityPrefs, enter_t: f32) Layout {
    var lay: Layout = .{};
    const card = cardGeom(480, 360, enter_t);
    var y = paintCard(logical, theme, card, "Idle lock", "Lock when display stays on and idle.", &lay);
    const x = card.x + tokens.Space.lg;
    const row_w = card.w - tokens.Space.lg * 2;
    const enabled = s.has_pin;
    lay.toggle[0] = paintToggleRow(logical, theme, x, &y, row_w, "Lock when idle", s.pin_idle and enabled);
    lay.cycle[0] = paintDropdownRow(logical, theme, x, &y, row_w, "Idle timeout", s.idleTmoLabel());
    if (!enabled) {
        font.drawTextRole(logical, x, y, "Set a PIN first to enable idle lock.", theme.on_surface_variant, .body_s);
    }
    footerBtns(card, &lay, false);
    paintFilledBtn(logical, theme, lay.primary, "Done");
    return lay;
}

pub fn hit(lay: Layout, x: i32, y: i32) Hit {
    if (lay.close.contains(x, y)) return .close;
    if (lay.primary.w > 0 and lay.primary.contains(x, y)) return .primary;
    if (lay.secondary.w > 0 and lay.secondary.contains(x, y)) return .secondary;
    inline for (0..5) |i| {
        if (lay.field[i].w > 0 and lay.field[i].contains(x, y)) {
            return switch (i) {
                0 => .field0,
                1 => .field1,
                2 => .field2,
                3 => .field3,
                else => .field4,
            };
        }
    }
    if (lay.toggle[0].w > 0 and lay.toggle[0].contains(x, y)) return .toggle0;
    if (lay.toggle[1].w > 0 and lay.toggle[1].contains(x, y)) return .toggle1;
    if (lay.cycle[0].w > 0 and lay.cycle[0].contains(x, y)) return .cycle0;
    if (lay.cycle[1].w > 0 and lay.cycle[1].contains(x, y)) return .cycle1;
    if (lay.seg[0].w > 0 and lay.seg[0].contains(x, y)) return .seg0;
    if (lay.seg[1].w > 0 and lay.seg[1].contains(x, y)) return .seg1;
    inline for (0..6) |i| {
        if (i < lay.inv_n and lay.inv[i].w > 0 and lay.inv[i].contains(x, y)) {
            return switch (i) {
                0 => .inv0,
                1 => .inv1,
                2 => .inv2,
                3 => .inv3,
                4 => .inv4,
                else => .inv5,
            };
        }
    }
    if (!lay.card.contains(x, y)) return .close;
    return .none;
}

/// Segment index from hit X within seg rect (equal columns).
pub fn segmentIndexAt(r: geom.Rect, x: i32, n: usize) ?usize {
    if (n == 0 or !r.contains(x, r.y + 1)) return null;
    const col_w = @divTrunc(r.w, @as(i32, @intCast(n)));
    if (col_w <= 0) return 0;
    const i: usize = @intCast(@divTrunc(x - r.x, col_w));
    return @min(i, n - 1);
}

test "transport hit close" {
    var lay: Layout = .{};
    lay.close = .{ .x = 10, .y = 10, .w = 48, .h = 48 };
    lay.card = .{ .x = 0, .y = 0, .w = 200, .h = 200 };
    try std.testing.expect(hit(lay, 20, 20) == .close);
}
