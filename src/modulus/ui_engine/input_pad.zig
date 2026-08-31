//! MD3-style input overlays: number pad, PIN keypad, date/time pickers, text keyboard.
//! Host demo — mirrors LVGL kb_full dock (48% / 560×240) + lv_keyboard row map.

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const color = @import("color.zig");

pub const Mode = enum { number, time, date, datetime, text };

/// Active date/time field (MD3 input-mode picker).
pub const Field = enum(u8) {
    year,
    month,
    day,
    hour,
    min,
    sec,

    pub fn maxDigits(self: Field) usize {
        return if (self == .year) 4 else 2;
    }

    pub fn index(self: Field) usize {
        return @intFromEnum(self);
    }
};

pub const Target = enum {
    none,
    disp_bright,
    dash_coal,
    dash_pend,
    dash_encdiv,
    dash_contpct,
    aud_vol,
    mach_mxfeed,
    mach_mxrpm,
    mach_jogspd,
    mach_feedovr,
    mach_spindovr,
    mach_trx,
    mach_try,
    mach_trz,
    mach_tra,
    mach_trb,
    mach_trc,
    sys_time,
    sys_date,
    sys_datetime,
    mach_name,
    mach_svc_dt,
    mach_svc_nt,
    sec_pin_new,
    sec_pin_confirm,
    sec_pin_clear,
    sec_pin_unlock,
    wl_ssid,
    wl_pass,
    wl_en_mac,
    wl_zb_code,
    wl_th_node,
    wl_bt_passkey,
    cnc_masso_ip,
    cnc_ws_host,
    cnc_ws_port,
    cnc_ws_path,
    cnc_tn_host,
    cnc_tn_port,
    cnc_ble_name,
    cnc_i2c_addr,
    cnc_can_nid,
    cnc_prof_rename,
    dash_incr,
    dash_wcs_name,
    dash_mac_name,
    dash_mac_on,
    dash_mac_off,
    dash_probe_zoff,
    qs_mdi,
    usb_rename,
    search,
};

pub const State = struct {
    open: bool = false,
    mode: Mode = .number,
    target: Target = .none,
    title: []const u8 = "",
    /// 64 covers G-code ON/OFF and incr CSV (LVGL textarea parity).
    buf: [64]u8 = .{0} ** 64,
    len: usize = 0,
    committed: bool = false,
    /// SystemPrefs.kb_full — full bottom dock vs compact card (text only).
    kb_full: bool = true,
    /// Password-style field (PIN).
    mask: bool = false,
    /// PIN 3×4 layout (ui_pin_lock style).
    pin_layout: bool = false,
    shift_on: bool = false,
    caps: bool = false,
    /// LVGL `1#` page — digits/symbols instead of QWERTY.
    digits_page: bool = false,

    /// MD3 date/time picker civil values (24h).
    year: u16 = 2026,
    month: u8 = 1,
    day: u8 = 1,
    hour: u8 = 0,
    min: u8 = 0,
    sec: u8 = 0,
    focus: Field = .hour,
    edit_buf: [4]u8 = .{0} ** 4,
    edit_len: usize = 0,
    /// First digit after focus replaces prior value (MD3 text-field feel).
    edit_fresh: bool = true,
    /// Hit targets filled during paint.
    f_rects: [6]geom.Rect = [_]geom.Rect{.{}} ** 6,
    cancel_r: geom.Rect = .{},
    apply_r: geom.Rect = .{},

    pub fn clear(self: *State) void {
        self.* = .{};
    }

    pub fn openPad(self: *State, mode: Mode, target: Target, title: []const u8, seed: []const u8) void {
        const pin = isPinTarget(target);
        self.open = true;
        self.mode = mode;
        self.target = target;
        self.title = title;
        self.committed = false;
        self.mask = pin;
        self.pin_layout = pin;
        self.shift_on = false;
        self.caps = false;
        self.digits_page = false;
        const n = @min(seed.len, self.buf.len);
        @memcpy(self.buf[0..n], seed[0..n]);
        self.len = n;
        if (n < self.buf.len) @memset(self.buf[n..], 0);
        if (isPicker(mode)) {
            self.seedPicker(mode, seed);
            self.syncEditFromFocus();
        }
    }

    /// Combined date+time modal (LVGL settings_time_modal parity).
    pub fn openDatetime(self: *State, target: Target, title: []const u8, y: u16, mo: u8, d: u8, h: u8, mi: u8, s: u8) void {
        self.open = true;
        self.mode = .datetime;
        self.target = target;
        self.title = title;
        self.committed = false;
        self.mask = false;
        self.pin_layout = false;
        self.shift_on = false;
        self.caps = false;
        self.digits_page = false;
        self.len = 0;
        self.year = y;
        self.month = @max(@min(mo, 12), 1);
        self.day = @max(@min(d, 31), 1);
        self.hour = @min(h, 23);
        self.min = @min(mi, 59);
        self.sec = @min(s, 59);
        self.focus = .year;
        self.syncEditFromFocus();
    }

    pub fn text(self: *const State) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn displayText(self: *const State, out: []u8) []const u8 {
        if (!self.mask or self.len == 0) return self.text();
        const n = @min(self.len, out.len);
        @memset(out[0..n], '*');
        return out[0..n];
    }

    pub fn pushChar(self: *State, ch: u8) void {
        if (self.len >= self.buf.len) return;
        self.buf[self.len] = ch;
        self.len += 1;
    }

    pub fn backspace(self: *State) void {
        if (self.len == 0) return;
        self.len -= 1;
        self.buf[self.len] = 0;
    }

    pub fn parseU32(self: *const State) ?u32 {
        if (self.len == 0) return null;
        return std.fmt.parseInt(u32, self.text(), 10) catch null;
    }

    pub fn clampAll(self: *State) void {
        self.year = @max(@min(self.year, 2099), 2020);
        self.month = @max(@min(self.month, 12), 1);
        self.day = @max(@min(self.day, 31), 1);
        self.hour = @min(self.hour, 23);
        self.min = @min(self.min, 59);
        self.sec = @min(self.sec, 59);
    }

    fn seedPicker(self: *State, mode: Mode, seed: []const u8) void {
        self.year = 2026;
        self.month = 1;
        self.day = 1;
        self.hour = 12;
        self.min = 0;
        self.sec = 0;
        if (mode == .time or mode == .datetime) {
            // HH:MM or HH:MM:SS
            if (seed.len >= 4) {
                self.hour = @intCast(std.fmt.parseInt(u32, seed[0..2], 10) catch 12);
                const colon = if (seed.len > 2 and seed[2] == ':') @as(usize, 3) else @as(usize, 2);
                if (seed.len > colon)
                    self.min = @intCast(std.fmt.parseInt(u32, seed[colon..@min(colon + 2, seed.len)], 10) catch 0);
                if (seed.len >= colon + 3 and seed[colon + 2] == ':')
                    self.sec = @intCast(std.fmt.parseInt(u32, seed[colon + 3 .. @min(colon + 5, seed.len)], 10) catch 0);
            }
            self.focus = .hour;
        }
        if (mode == .date or mode == .datetime) {
            if (seed.len >= 10 and seed[4] == '-' and seed[7] == '-') {
                self.year = @intCast(std.fmt.parseInt(u32, seed[0..4], 10) catch 2026);
                self.month = @intCast(std.fmt.parseInt(u32, seed[5..7], 10) catch 1);
                self.day = @intCast(std.fmt.parseInt(u32, seed[8..10], 10) catch 1);
            }
            if (mode == .date) self.focus = .year;
        }
        self.clampAll();
    }

    fn syncEditFromFocus(self: *State) void {
        var tmp: [8]u8 = undefined;
        const shown = switch (self.focus) {
            .year => std.fmt.bufPrint(&tmp, "{d:0>4}", .{self.year}) catch "2026",
            .month => std.fmt.bufPrint(&tmp, "{d:0>2}", .{self.month}) catch "01",
            .day => std.fmt.bufPrint(&tmp, "{d:0>2}", .{self.day}) catch "01",
            .hour => std.fmt.bufPrint(&tmp, "{d:0>2}", .{self.hour}) catch "00",
            .min => std.fmt.bufPrint(&tmp, "{d:0>2}", .{self.min}) catch "00",
            .sec => std.fmt.bufPrint(&tmp, "{d:0>2}", .{self.sec}) catch "00",
        };
        const n = @min(shown.len, self.edit_buf.len);
        @memcpy(self.edit_buf[0..n], shown[0..n]);
        self.edit_len = n;
        self.edit_fresh = true;
    }

    fn setFocus(self: *State, f: Field) void {
        self.commitEdit();
        self.focus = f;
        self.syncEditFromFocus();
    }

    fn commitEdit(self: *State) void {
        if (self.edit_len == 0) return;
        const v = std.fmt.parseInt(u32, self.edit_buf[0..self.edit_len], 10) catch return;
        switch (self.focus) {
            .year => self.year = @intCast(v),
            .month => self.month = @intCast(v),
            .day => self.day = @intCast(v),
            .hour => self.hour = @intCast(v),
            .min => self.min = @intCast(v),
            .sec => self.sec = @intCast(v),
        }
        self.clampAll();
    }

    fn pushPickerDigit(self: *State, d: u8) void {
        if (self.edit_fresh) {
            self.edit_len = 0;
            self.edit_fresh = false;
        }
        const max = self.focus.maxDigits();
        if (self.edit_len >= max) return;
        self.edit_buf[self.edit_len] = d;
        self.edit_len += 1;
        self.commitEdit();
        if (self.edit_len >= max) self.advanceFocus();
    }

    fn backspacePicker(self: *State) void {
        if (self.edit_fresh) {
            self.edit_len = 0;
            self.edit_fresh = false;
            return;
        }
        if (self.edit_len == 0) return;
        self.edit_len -= 1;
        self.edit_buf[self.edit_len] = 0;
        if (self.edit_len == 0) {
            switch (self.focus) {
                .year => self.year = 2020,
                .month => self.month = 1,
                .day => self.day = 1,
                .hour => self.hour = 0,
                .min => self.min = 0,
                .sec => self.sec = 0,
            }
        } else self.commitEdit();
    }

    fn advanceFocus(self: *State) void {
        const next: ?Field = switch (self.mode) {
            .date => switch (self.focus) {
                .year => .month,
                .month => .day,
                else => null,
            },
            .time => switch (self.focus) {
                .hour => .min,
                .min => .sec,
                else => null,
            },
            .datetime => switch (self.focus) {
                .year => .month,
                .month => .day,
                .day => .hour,
                .hour => .min,
                .min => .sec,
                .sec => null,
            },
            else => null,
        };
        if (next) |f| self.setFocus(f);
    }

    fn fieldVisible(self: *const State, f: Field) bool {
        return switch (self.mode) {
            .date => f == .year or f == .month or f == .day,
            .time => f == .hour or f == .min or f == .sec,
            .datetime => true,
            else => false,
        };
    }
};

pub fn isPinTarget(t: Target) bool {
    return switch (t) {
        .sec_pin_new, .sec_pin_confirm, .sec_pin_clear, .sec_pin_unlock => true,
        else => false,
    };
}

/// What a `.number` buffer must parse as before commit.
pub const NumberKind = enum {
    /// `parseInt(u32)` — every settings value except the two below.
    integer,
    /// `parseFloat` — probe plate thickness.
    decimal,
    /// Dotted quad kept as text (Masso IP).
    dotted,
};

pub fn numberKind(t: Target) NumberKind {
    return switch (t) {
        .dash_probe_zoff => .decimal,
        .cnc_masso_ip => .dotted,
        else => .integer,
    };
}

/// Only paint/hit the '.' key where the target can actually use it — an
/// integer target that accepts "1.5" just drops the value on commit.
pub fn allowsDot(t: Target) bool {
    return numberKind(t) != .integer;
}

/// True when the number buffer will commit. PIN buffers are raw digits and
/// carry their own length rules.
pub fn numberValid(t: Target, txt: []const u8) bool {
    if (isPinTarget(t)) return true;
    if (txt.len == 0) return false;
    switch (numberKind(t)) {
        .integer => _ = std.fmt.parseInt(u32, txt, 10) catch return false,
        .decimal => _ = std.fmt.parseFloat(f32, txt) catch return false,
        .dotted => {},
    }
    return true;
}

fn isPicker(mode: Mode) bool {
    return mode == .time or mode == .date or mode == .datetime;
}

/// Title (~34) + field (48) + gap above the first key row.
const grid_head: i32 = 34 + tokens.Logical.touch_min + tokens.Space.sm;
/// `gridFor` never shrinks a key below this, so panels must budget for it.
const key_min_h: i32 = 40;

fn compactCardHeight() i32 {
    const rows: i32 = 4;
    return grid_head + rows * key_min_h + (rows - 1) * tokens.Space.xs + tokens.Space.sm;
}

fn fullDock() geom.Rect {
    // LVGL settings_modal_kb_configure_text: lv_pct(48).
    const h: i32 = @divTrunc(@as(i32, tokens.Logical.height) * 48, 100);
    return .{
        .x = 0,
        .y = tokens.Logical.height - h,
        .w = tokens.Logical.width,
        .h = h,
    };
}

fn compactCard() geom.Rect {
    // LVGL compact: 560 wide, align bottom -20. Height must clear the header
    // plus 4 rows of min-height keys or the OK/space row lands on the scrim,
    // where `hitTest` reads it as an outside tap and cancels the edit.
    const w: i32 = 560;
    const h: i32 = compactCardHeight();
    return .{
        .x = @divTrunc(tokens.Logical.width - w, 2),
        .y = tokens.Logical.height - h - 20,
        .w = w,
        .h = h,
    };
}

/// MD3 date/time picker dialog (elev 3, Shape.dialog) — LVGL card size.
fn pickerDialog() geom.Rect {
    const w: i32 = 500;
    const h: i32 = 260;
    return .{
        .x = @divTrunc(tokens.Logical.width - w, 2),
        .y = 30,
        .w = w,
        .h = h,
    };
}

/// Number/PIN always dock full. Text uses kb_full. Pickers: dialog + dock.
pub fn panelRect(st: *const State) geom.Rect {
    if (isPicker(st.mode)) return pickerDialog();
    if (st.mode != .text or st.pin_layout) return fullDock();
    return if (st.kb_full) fullDock() else compactCard();
}

const Grid = struct {
    ox: i32,
    oy: i32,
    kw: i32,
    kh: i32,
    gap: i32,
};

fn gridFor(panel: geom.Rect, cols: i32, rows: i32) Grid {
    const pad: i32 = tokens.Space.sm;
    const ox = panel.x + pad;
    const oy = panel.y + grid_head;
    const avail_w = panel.w - pad * 2;
    const avail_h = panel.h - grid_head - pad;
    const gap: i32 = tokens.Space.xs;
    const kw = @max(key_min_h, @divTrunc(avail_w - (cols - 1) * gap, cols));
    const kh = @max(key_min_h, @divTrunc(avail_h - (rows - 1) * gap, rows));
    return .{ .ox = ox, .oy = oy, .kw = kw, .kh = kh, .gap = gap };
}

fn gridForDock(panel: geom.Rect, cols: i32, rows: i32) Grid {
    const pad: i32 = tokens.Space.sm;
    const head: i32 = tokens.Space.sm;
    const ox = panel.x + pad;
    const oy = panel.y + head;
    const avail_w = panel.w - pad * 2;
    const avail_h = panel.h - head - pad;
    const gap: i32 = tokens.Space.xs;
    const kw = @max(key_min_h, @divTrunc(avail_w - (cols - 1) * gap, cols));
    const kh = @max(key_min_h, @divTrunc(avail_h - (rows - 1) * gap, rows));
    return .{ .ox = ox, .oy = oy, .kw = kw, .kh = kh, .gap = gap };
}

pub fn paint(logical: *fb.LogicalFb, theme: tokens.Theme, st: *State) void {
    if (!st.open) return;
    if (isPicker(st.mode)) {
        paintPicker(logical, theme, st);
        return;
    }

    const panel = panelRect(st);
    widgets.fillScrim(logical, theme);
    // LVGL tray: surface_container, top border only on full dock.
    widgets.fillRoundRect(logical, panel, if (panel.x == 0) 0 else tokens.Shape.xl, theme.surface_container);
    if (panel.x == 0) {
        logical.fillRect(.{ .x = panel.x, .y = panel.y, .w = panel.w, .h = 1 }, theme.outline_variant);
    }
    font.drawTextRole(logical, panel.x + 16, panel.y + 10, st.title, theme.on_surface, .title_s);

    const field: geom.Rect = .{
        .x = panel.x + 16,
        .y = panel.y + 34,
        .w = panel.w - 32,
        .h = tokens.Logical.touch_min,
    };
    var mask_buf: [64]u8 = undefined;
    const empty = st.len == 0;
    const value = if (!empty) st.displayText(&mask_buf) else "";
    const placeholder: []const u8 = switch (st.target) {
        .dash_incr => "0.001,0.01,0.1,1.0",
        .dash_wcs_name => "Custom name",
        .dash_mac_name => "Button name",
        .dash_mac_on => "M64 P0",
        .dash_mac_off => "M65 P0",
        .dash_probe_zoff => "1.0",
        else => switch (st.mode) {
            .number => "0",
            // ASCII only — the Noto bake stops at 0x7E, so an ellipsis paints
            // three blank cells.
            .text => "Type here",
            else => "0",
        },
    };
    // Modal pad field is the active input → focused.
    widgets.drawOutlinedTextField(logical, field, value, placeholder, true, true, false, theme);

    if (st.pin_layout) {
        paintPinGrid(logical, theme, gridFor(panel, 3, 4));
    } else switch (st.mode) {
        .number => paintNumGrid(logical, theme, gridFor(panel, 4, 4), allowsDot(st.target)),
        .text => paintTextGrid(logical, theme, panel, st),
        else => {},
    }
}

fn paintPicker(logical: *fb.LogicalFb, theme: tokens.Theme, st: *State) void {
    widgets.fillScrim(logical, theme);

    const card = pickerDialog();
    // MD3: date/time pickers at elevation 3; dialog corners.
    widgets.fillRoundRect(logical, card, tokens.Shape.dialog, theme.elev(3));
    widgets.strokeRoundRect(logical, card, tokens.Shape.dialog, theme.outline_variant, 1);
    font.drawTextRole(logical, card.x + 20, card.y + 18, st.title, theme.on_surface, .title_m);

    var y: i32 = card.y + 56;
    if (st.mode == .date or st.mode == .datetime) {
        font.drawTextRole(logical, card.x + 20, y + 12, "Date", theme.on_surface_variant, .label_l);
        paintFieldRow(logical, theme, st, y, &.{ .year, .month, .day }, &.{ "-", "-" }, 72);
        y += 56;
    }
    if (st.mode == .time or st.mode == .datetime) {
        font.drawTextRole(logical, card.x + 20, y + 12, "Time", theme.on_surface_variant, .label_l);
        paintFieldRow(logical, theme, st, y, &.{ .hour, .min, .sec }, &.{ ":", ":" }, 168);
        y += 56;
    }

    const btn_h: i32 = tokens.Logical.touch_min;
    const btn_y = card.y + card.h - btn_h - 16;
    st.cancel_r = .{ .x = card.x + card.w - 232, .y = btn_y, .w = 100, .h = btn_h };
    st.apply_r = .{ .x = card.x + card.w - 120, .y = btn_y, .w = 100, .h = btn_h };
    widgets.drawTonalButton(logical, st.cancel_r, "Cancel", theme);
    widgets.drawFilledButton(logical, st.apply_r, "Apply", theme);

    const dock = fullDock();
    widgets.fillRoundRect(logical, dock, tokens.Shape.lg, theme.surface_container_high);
    // Pickers consume digits only — a separator key here would be inert.
    paintNumGrid(logical, theme, gridForDock(dock, 4, 4), false);
}

fn paintFieldRow(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    st: *State,
    row_y: i32,
    fields: []const Field,
    seps: []const []const u8,
    label_w: i32,
) void {
    const card = pickerDialog();
    var x = card.x + 20 + label_w;
    const fh: i32 = 44;
    for (fields, 0..) |f, i| {
        const fw: i32 = if (f == .year) 88 else 64;
        const r: geom.Rect = .{ .x = x, .y = row_y, .w = fw, .h = fh };
        st.f_rects[@intFromEnum(f)] = r;
        const focused = st.focus == f;
        var lab: [8]u8 = undefined;
        const shown = fieldLabel(st, f, &lab);
        widgets.drawOutlinedTextFieldCentered(logical, r, shown, focused, theme, .title_m);
        x += fw + 8;
        if (i < seps.len) {
            font.drawTextRole(logical, x, row_y + 12, seps[i], theme.on_surface_variant, .title_m);
            x += 12;
        }
    }
}

fn fieldLabel(st: *const State, f: Field, lab: *[8]u8) []const u8 {
    if (st.focus == f and st.edit_len > 0 and !st.edit_fresh) {
        return st.edit_buf[0..st.edit_len];
    }
    if (st.focus == f and st.edit_len > 0) {
        return st.edit_buf[0..st.edit_len];
    }
    return switch (f) {
        .year => std.fmt.bufPrint(lab, "{d:0>4}", .{st.year}) catch "----",
        .month => std.fmt.bufPrint(lab, "{d:0>2}", .{st.month}) catch "--",
        .day => std.fmt.bufPrint(lab, "{d:0>2}", .{st.day}) catch "--",
        .hour => std.fmt.bufPrint(lab, "{d:0>2}", .{st.hour}) catch "--",
        .min => std.fmt.bufPrint(lab, "{d:0>2}", .{st.min}) catch "--",
        .sec => std.fmt.bufPrint(lab, "{d:0>2}", .{st.sec}) catch "--",
    };
}

fn paintKey(logical: *fb.LogicalFb, r: geom.Rect, label: []const u8, fill: color.Rgb565, on: color.Rgb565) void {
    // LVGL keyboard items: Shape.sm + tonal fill.
    widgets.fillRoundRect(logical, r, tokens.Shape.sm, fill);
    const tw = font.textWidthStr(label, .label_l);
    const th = font.faceHeight(font.faceForRole(.label_l));
    font.drawTextRole(logical, r.x + @divTrunc(r.w - tw, 2), r.y + @divTrunc(r.h - th, 2), label, on, .label_l);
}

fn cell(g: Grid, col: i32, row: i32) geom.Rect {
    return .{
        .x = g.ox + col * (g.kw + g.gap),
        .y = g.oy + row * (g.kh + g.gap),
        .w = g.kw,
        .h = g.kh,
    };
}

fn paintPinGrid(logical: *fb.LogicalFb, theme: tokens.Theme, g: Grid) void {
    const digits = "123456789";
    var i: usize = 0;
    while (i < 9) : (i += 1) {
        var lab: [1]u8 = .{digits[i]};
        paintKey(logical, cell(g, @intCast(i % 3), @intCast(i / 3)), lab[0..], theme.surface_container, theme.on_surface);
    }
    paintKey(logical, cell(g, 0, 3), "Bk", theme.secondary_container, theme.on_secondary_container);
    paintKey(logical, cell(g, 1, 3), "0", theme.surface_container, theme.on_surface);
    paintKey(logical, cell(g, 2, 3), "OK", theme.primary, theme.on_primary);
}

fn paintNumGrid(logical: *fb.LogicalFb, theme: tokens.Theme, g: Grid, dot: bool) void {
    const digits = "123456789";
    var i: usize = 0;
    while (i < 9) : (i += 1) {
        var lab: [1]u8 = .{digits[i]};
        paintKey(logical, cell(g, @intCast(i % 3), @intCast(i / 3)), lab[0..], theme.surface_container, theme.on_surface);
    }
    paintKey(logical, cell(g, 3, 0), "Bk", theme.secondary_container, theme.on_secondary_container);
    if (dot) paintKey(logical, cell(g, 3, 2), ".", theme.surface_container, theme.on_surface);
    paintKey(logical, cell(g, 3, 3), "X", theme.error_container, theme.on_error_container);
    const ok: geom.Rect = .{
        .x = g.ox,
        .y = g.oy + 3 * (g.kh + g.gap),
        .w = g.kw * 2 + g.gap,
        .h = g.kh,
    };
    paintKey(logical, ok, "OK", theme.primary, theme.on_primary);
    paintKey(logical, cell(g, 2, 3), "0", theme.surface_container, theme.on_surface);
}

fn paintTextGrid(logical: *fb.LogicalFb, theme: tokens.Theme, panel: geom.Rect, st: *const State) void {
    // LVGL lv_keyboard TEXT: 4 rows. Keys = secondary_container (ui_theme).
    const g = gridFor(panel, 10, 4);
    const fill = theme.secondary_container;
    const on = theme.on_secondary_container;
    const upper = st.shift_on or st.caps;

    if (st.digits_page) {
        paintCharRow(logical, theme, g, 0, "1234567890", 0, fill, on);
        paintCharRow(logical, theme, g, 1, "-/:;()$&@\"", 0, fill, on);
        // Row 2: punctuation (7) + Bk (1.5) with left pad matching letter row.
        const punct = ".,?!'" ++ "\"";
        var i: usize = 0;
        while (i < punct.len) : (i += 1) {
            const unit0 = 0.5 + @as(f32, @floatFromInt(i));
            var lab: [1]u8 = .{punct[i]};
            paintKey(logical, textKeySpan(g, 2, unit0, 1), lab[0..], fill, on);
        }
        paintKey(logical, textKeySpan(g, 2, 8.5, 1.5), "Bk", fill, on);
        paintTextBottom(logical, theme, g, true);
        return;
    }

    const row0 = if (upper) "QWERTYUIOP" else "qwertyuiop";
    const row1 = if (upper) "ASDFGHJKL" else "asdfghjkl";
    const row2 = if (upper) "ZXCVBNM" else "zxcvbnm";
    paintCharRow(logical, theme, g, 0, row0, 0, fill, on);
    paintCharRow(logical, theme, g, 1, row1, @divTrunc(g.kw + g.gap, 2), fill, on);
    // Row 2: ABC (1.5) + 7 letters + Bk (1.5) = 10 units.
    {
        const shift_fill = if (st.shift_on or st.caps) theme.primary else fill;
        const shift_on = if (st.shift_on or st.caps) theme.on_primary else on;
        const shift_lab: []const u8 = if (st.caps) "CAPS" else "ABC";
        paintKey(logical, textKeySpan(g, 2, 0, 1.5), shift_lab, shift_fill, shift_on);
        var i: usize = 0;
        while (i < row2.len) : (i += 1) {
            const unit0 = 1.5 + @as(f32, @floatFromInt(i));
            var lab: [1]u8 = .{row2[i]};
            paintKey(logical, textKeySpan(g, 2, unit0, 1), lab[0..], fill, on);
        }
        paintKey(logical, textKeySpan(g, 2, 8.5, 1.5), "Bk", fill, on);
    }
    paintTextBottom(logical, theme, g, false);
}

fn paintTextBottom(logical: *fb.LogicalFb, theme: tokens.Theme, g: Grid, digits: bool) void {
    const fill = theme.secondary_container;
    const on = theme.on_secondary_container;
    // LVGL bottom: 1# | space | . | OK — host keeps Cancel (X).
    const mode_lab: []const u8 = if (digits) "ABC" else "123";
    paintKey(logical, textKeySpan(g, 3, 0, 1.5), mode_lab, fill, on);
    paintKey(logical, textKeySpan(g, 3, 1.5, 4.5), "space", fill, on);
    paintKey(logical, textKeySpan(g, 3, 6, 1), ".", fill, on);
    paintKey(logical, textKeySpan(g, 3, 7, 1.5), "OK", theme.primary, theme.on_primary);
    paintKey(logical, textKeySpan(g, 3, 8.5, 1.5), "X", theme.error_container, theme.on_error_container);
}

/// Key rect in a 10-unit row (LVGL btnmatrix column spans).
fn textKeySpan(g: Grid, row: i32, unit0: f32, units: f32) geom.Rect {
    const total: f32 = @floatFromInt(10 * g.kw + 9 * g.gap);
    const u = total / 10.0;
    const x0: i32 = @intFromFloat(@round(unit0 * u));
    const x1: i32 = @intFromFloat(@round((unit0 + units) * u));
    const gap_trim: i32 = if (unit0 + units < 9.99) g.gap else 0;
    return .{
        .x = g.ox + x0,
        .y = g.oy + row * (g.kh + g.gap),
        .w = @max(1, x1 - x0 - gap_trim),
        .h = g.kh,
    };
}

fn paintCharRow(
    logical: *fb.LogicalFb,
    theme: tokens.Theme,
    g: Grid,
    row: i32,
    chars: []const u8,
    x0: i32,
    fill: color.Rgb565,
    on: color.Rgb565,
) void {
    _ = theme;
    var i: usize = 0;
    while (i < chars.len) : (i += 1) {
        const r: geom.Rect = .{
            .x = g.ox + x0 + @as(i32, @intCast(i)) * (g.kw + g.gap),
            .y = g.oy + row * (g.kh + g.gap),
            .w = g.kw,
            .h = g.kh,
        };
        var lab: [1]u8 = .{chars[i]};
        paintKey(logical, r, lab[0..], fill, on);
    }
}

pub const Hit = enum { none, outside, ok, cancel, backspace, space, dot, digit, letter, shift, mode_toggle, field };

pub const HitInfo = struct {
    kind: Hit = .none,
    ch: u8 = 0,
};

pub fn hitTest(st: *const State, x: i32, y: i32) HitInfo {
    if (!st.open) return .{};
    if (isPicker(st.mode)) return hitPicker(st, x, y);

    const panel = panelRect(st);
    if (!panel.contains(x, y)) return .{ .kind = .outside };
    if (st.pin_layout) return hitPin(gridFor(panel, 3, 4), x, y);
    return switch (st.mode) {
        .text => hitText(st, panel, x, y),
        .number => hitNum(gridFor(panel, 4, 4), x, y, allowsDot(st.target)),
        else => .{},
    };
}

fn hitPicker(st: *const State, x: i32, y: i32) HitInfo {
    if (st.cancel_r.contains(x, y)) return .{ .kind = .cancel };
    if (st.apply_r.contains(x, y)) return .{ .kind = .ok };
    const fields = [_]Field{ .year, .month, .day, .hour, .min, .sec };
    for (fields) |f| {
        if (st.fieldVisible(f) and st.f_rects[@intFromEnum(f)].contains(x, y))
            return .{ .kind = .field, .ch = @intFromEnum(f) };
    }
    const dock = fullDock();
    if (dock.contains(x, y)) return hitNum(gridForDock(dock, 4, 4), x, y, false);
    const card = pickerDialog();
    if (card.contains(x, y)) return .{};
    return .{ .kind = .outside };
}

fn hitPin(g: Grid, x: i32, y: i32) HitInfo {
    if (cell(g, 0, 3).contains(x, y)) return .{ .kind = .backspace };
    if (cell(g, 1, 3).contains(x, y)) return .{ .kind = .digit, .ch = '0' };
    if (cell(g, 2, 3).contains(x, y)) return .{ .kind = .ok };
    const digits = "123456789";
    var i: usize = 0;
    while (i < 9) : (i += 1) {
        if (cell(g, @intCast(i % 3), @intCast(i / 3)).contains(x, y))
            return .{ .kind = .digit, .ch = digits[i] };
    }
    return .{};
}

fn hitNum(g: Grid, x: i32, y: i32, dot: bool) HitInfo {
    const ok: geom.Rect = .{
        .x = g.ox,
        .y = g.oy + 3 * (g.kh + g.gap),
        .w = g.kw * 2 + g.gap,
        .h = g.kh,
    };
    if (ok.contains(x, y)) return .{ .kind = .ok };
    if (cell(g, 2, 3).contains(x, y)) return .{ .kind = .digit, .ch = '0' };
    if (cell(g, 3, 3).contains(x, y)) return .{ .kind = .cancel };
    if (cell(g, 3, 0).contains(x, y)) return .{ .kind = .backspace };
    if (dot and cell(g, 3, 2).contains(x, y)) return .{ .kind = .dot, .ch = '.' };
    const digits = "123456789";
    var i: usize = 0;
    while (i < 9) : (i += 1) {
        if (cell(g, @intCast(i % 3), @intCast(i / 3)).contains(x, y))
            return .{ .kind = .digit, .ch = digits[i] };
    }
    return .{};
}

fn hitText(st: *const State, panel: geom.Rect, x: i32, y: i32) HitInfo {
    const g = gridFor(panel, 10, 4);
    const upper = st.shift_on or st.caps;

    if (st.digits_page) {
        if (hitCharRow(g, 0, "1234567890", 0, x, y)) |ch| return .{ .kind = .letter, .ch = ch };
        if (hitCharRow(g, 1, "-/:;()$&@\"", 0, x, y)) |ch| return .{ .kind = .letter, .ch = ch };
        const punct = ".,?!'" ++ "\"";
        var i: usize = 0;
        while (i < punct.len) : (i += 1) {
            const unit0 = 0.5 + @as(f32, @floatFromInt(i));
            if (textKeySpan(g, 2, unit0, 1).contains(x, y)) return .{ .kind = .letter, .ch = punct[i] };
        }
        if (textKeySpan(g, 2, 8.5, 1.5).contains(x, y)) return .{ .kind = .backspace };
    } else {
        const row0 = if (upper) "QWERTYUIOP" else "qwertyuiop";
        const row1 = if (upper) "ASDFGHJKL" else "asdfghjkl";
        const row2 = if (upper) "ZXCVBNM" else "zxcvbnm";
        if (hitCharRow(g, 0, row0, 0, x, y)) |ch| return .{ .kind = .letter, .ch = ch };
        if (hitCharRow(g, 1, row1, @divTrunc(g.kw + g.gap, 2), x, y)) |ch| return .{ .kind = .letter, .ch = ch };
        if (textKeySpan(g, 2, 0, 1.5).contains(x, y)) return .{ .kind = .shift };
        var i: usize = 0;
        while (i < row2.len) : (i += 1) {
            const unit0 = 1.5 + @as(f32, @floatFromInt(i));
            if (textKeySpan(g, 2, unit0, 1).contains(x, y)) return .{ .kind = .letter, .ch = row2[i] };
        }
        if (textKeySpan(g, 2, 8.5, 1.5).contains(x, y)) return .{ .kind = .backspace };
    }

    if (textKeySpan(g, 3, 0, 1.5).contains(x, y)) return .{ .kind = .mode_toggle };
    if (textKeySpan(g, 3, 1.5, 4.5).contains(x, y)) return .{ .kind = .space, .ch = ' ' };
    if (textKeySpan(g, 3, 6, 1).contains(x, y)) return .{ .kind = .dot, .ch = '.' };
    if (textKeySpan(g, 3, 7, 1.5).contains(x, y)) return .{ .kind = .ok };
    if (textKeySpan(g, 3, 8.5, 1.5).contains(x, y)) return .{ .kind = .cancel };
    return .{};
}

fn hitCharRow(g: Grid, row: i32, chars: []const u8, x0: i32, x: i32, y: i32) ?u8 {
    var i: usize = 0;
    while (i < chars.len) : (i += 1) {
        const r: geom.Rect = .{
            .x = g.ox + x0 + @as(i32, @intCast(i)) * (g.kw + g.gap),
            .y = g.oy + row * (g.kh + g.gap),
            .w = g.kw,
            .h = g.kh,
        };
        if (r.contains(x, y)) return chars[i];
    }
    return null;
}

pub const Close = enum { none, close_cancel, close_ok };

pub fn applyHit(st: *State, info: HitInfo) Close {
    if (isPicker(st.mode)) return applyPickerHit(st, info);
    switch (info.kind) {
        .none, .field => return .none,
        .outside, .cancel => {
            st.clear();
            return .close_cancel;
        },
        .ok => {
            st.committed = true;
            return .close_ok;
        },
        .backspace => st.backspace(),
        .mode_toggle => st.digits_page = !st.digits_page,
        .shift => {
            if (st.shift_on and !st.caps) {
                st.caps = true;
                st.shift_on = true;
            } else if (st.caps) {
                st.caps = false;
                st.shift_on = false;
            } else {
                st.shift_on = true;
            }
        },
        .space, .dot, .digit, .letter => {
            if (info.ch != 0) {
                st.pushChar(info.ch);
                if (info.kind == .letter and st.shift_on and !st.caps) st.shift_on = false;
            }
        },
    }
    return .none;
}

fn applyPickerHit(st: *State, info: HitInfo) Close {
    switch (info.kind) {
        .none => return .none,
        .outside, .cancel => {
            st.clear();
            return .close_cancel;
        },
        .ok => {
            st.commitEdit();
            st.clampAll();
            st.committed = true;
            return .close_ok;
        },
        .field => {
            st.setFocus(@enumFromInt(info.ch));
            return .none;
        },
        .backspace => {
            st.backspacePicker();
            return .none;
        },
        .digit => {
            if (info.ch >= '0' and info.ch <= '9') st.pushPickerDigit(info.ch);
            return .none;
        },
        else => return .none,
    }
}

test "number pad parses" {
    var st: State = .{};
    st.openPad(.number, .disp_bright, "Brightness", "42");
    try std.testing.expectEqual(@as(u32, 42), st.parseU32().?);
    st.pushChar('0');
    try std.testing.expectEqual(@as(u32, 420), st.parseU32().?);
}

test "pin mask and dock" {
    var st: State = .{};
    st.openPad(.number, .sec_pin_unlock, "Enter PIN", "12");
    try std.testing.expect(st.mask and st.pin_layout);
    var m: [8]u8 = undefined;
    try std.testing.expectEqualStrings("**", st.displayText(&m));
    st.kb_full = false;
    const pin_panel = panelRect(&st);
    try std.testing.expectEqual(@as(i32, 0), pin_panel.x);

    st.openPad(.text, .mach_name, "Name", "ab");
    st.kb_full = false;
    const compact = panelRect(&st);
    try std.testing.expect(compact.w == 560);
    try std.testing.expect(compact.h == compactCardHeight());
    st.kb_full = true;
    try std.testing.expectEqual(@as(i32, 0), panelRect(&st).x);
    try std.testing.expectEqual(@as(i32, @divTrunc(@as(i32, tokens.Logical.height) * 48, 100)), panelRect(&st).h);
}

test "text keyboard keys fit inside dock" {
    var st: State = .{};
    st.openPad(.text, .mach_name, "Name", "");
    st.kb_full = true;
    const panel = panelRect(&st);
    const g = gridFor(panel, 10, 4);
    const last = textKeySpan(g, 3, 8.5, 1.5);
    try std.testing.expect(last.y + last.h <= panel.y + panel.h);
    try std.testing.expect(last.x + last.w <= panel.x + panel.w);
}

test "compact keyboard bottom row stays hittable inside the card" {
    var st: State = .{};
    st.openPad(.text, .mach_name, "Name", "");
    st.kb_full = false;
    const panel = panelRect(&st);
    try std.testing.expect(panel.y + panel.h <= tokens.Logical.height);
    const g = gridFor(panel, 10, 4);
    const ok = textKeySpan(g, 3, 7, 1.5);
    try std.testing.expect(ok.y + ok.h <= panel.y + panel.h);
    // Outside the card `hitTest` reports `.outside`, which cancels the edit.
    try std.testing.expect(hitTest(&st, ok.x + 4, ok.y + 4).kind == .ok);
}

test "decimal key only where the target parses it" {
    var st: State = .{};
    st.openPad(.number, .disp_bright, "Brightness", "50");
    const dot = cell(gridFor(panelRect(&st), 4, 4), 3, 2);
    try std.testing.expect(hitTest(&st, dot.x + 4, dot.y + 4).kind == .none);
    try std.testing.expect(!numberValid(.disp_bright, "50.5"));

    st.openPad(.number, .dash_probe_zoff, "Plate thickness (mm)", "1.0");
    try std.testing.expect(hitTest(&st, dot.x + 4, dot.y + 4).kind == .dot);
    try std.testing.expect(numberValid(.dash_probe_zoff, "1.5"));
    try std.testing.expect(numberValid(.cnc_masso_ip, "192.168.1.5"));
    try std.testing.expect(!numberValid(.disp_bright, ""));
}

test "picker dock has no inert separator key" {
    var st: State = .{};
    st.openDatetime(.sys_datetime, "Set date and time", 2026, 8, 21, 14, 30, 5);
    const sep = cell(gridForDock(fullDock(), 4, 4), 3, 2);
    try std.testing.expect(hitTest(&st, sep.x + 4, sep.y + 4).kind == .none);
}

test "datetime picker fields clamp and advance" {
    var st: State = .{};
    st.openDatetime(.sys_datetime, "Set date and time", 2026, 8, 21, 14, 30, 5);
    try std.testing.expect(st.mode == .datetime);
    try std.testing.expectEqual(@as(u8, 14), st.hour);
    st.setFocus(.hour);
    _ = applyPickerHit(&st, .{ .kind = .digit, .ch = '2' });
    _ = applyPickerHit(&st, .{ .kind = .digit, .ch = '5' });
    try std.testing.expectEqual(@as(u8, 23), st.hour); // clamped
    try std.testing.expect(st.focus == .min); // auto-advance
    st.setFocus(.month);
    _ = applyPickerHit(&st, .{ .kind = .digit, .ch = '0' });
    _ = applyPickerHit(&st, .{ .kind = .digit, .ch = '0' });
    try std.testing.expectEqual(@as(u8, 1), st.month);
}

test "date mode seeds YYYY-MM-DD" {
    var st: State = .{};
    st.openPad(.date, .mach_svc_dt, "Service", "2024-12-05");
    try std.testing.expectEqual(@as(u16, 2024), st.year);
    try std.testing.expectEqual(@as(u8, 12), st.month);
    try std.testing.expectEqual(@as(u8, 5), st.day);
    try std.testing.expect(panelRect(&st).w == 500);
}
