//! Dashboard paint — Tab5 LVGL silhouette + Phosphor A8 icons (host).

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const font = @import("font.zig");
const widgets = @import("widgets.zig");
const icons_phosphor = @import("icons_phosphor.zig");
const battery_chrome = @import("battery_chrome.zig");
const dro_widget = @import("dro_widget.zig");
const jog_widget = @import("jog_widget.zig");
const override_widget = @import("override_widget.zig");
const actions_widget = @import("actions_widget.zig");
const job_progress_widget = @import("job_progress_widget.zig");

const expr = @import("widgets_expressive.zig");

pub const status_h: i32 = 80;
/// LVGL `ui_dashboard.c` DRO panel width.
pub const dro_w: i32 = 420;
/// LVGL `ui_dashboard.c` actions column width.
pub const actions_w: i32 = 280;
/// LVGL job strip height (see `job_progress_widget.strip_h`).
pub const job_strip_h: i32 = job_progress_widget.strip_h;
/// Idle body top (no job strip). Prefer `bodyTop(cnc)` for layout.
pub const body_top: i32 = status_h;
pub const pad: i32 = tokens.Space.lg; // WindowSizeClass.large.margin()

pub const CncView = struct {
    state: []const u8 = "Idle",
    wcs: []const u8 = "G54",
    tool: []const u8 = "T00",
    /// Device mirror writes `Tnn` here; `tool` points at the slice.
    tool_buf: [8]u8 = .{ 'T', '0', '0', 0, 0, 0, 0, 0 },
    mpg_active: bool = false,
    /// LVGL `modulus_zig_mpg_remote` — pill shows "MPG rem" when true.
    mpg_remote: bool = false,
    feed_pct: u8 = 100,
    spindle_pct: u8 = 100,
    rapid_pct: u8 = 100,
    feed_mm_min: u32 = 0,
    spindle_rpm: u32 = 0,
    battery_pct: u8 = 0,
    /// 0=discharging 1=charging 2=full 3=error/no pack (battery_shim).
    battery_charge_state: u8 = 0,
    /// Host stub / device — LVGL charge icon path.
    battery_charging: bool = false,
    /// Charge rate above `battery_chrome.fast_charge_ma` while charging.
    battery_fast_charge: bool = false,
    /// Device: System → FPS / paint HUD on status bar.
    perf_hud: bool = false,
    perf_fps_x10: u16 = 0,
    perf_paint_us: u32 = 0,
    /// Rotate/present share of `perf_paint_us` — PPA vs CPU transpose check.
    perf_rotate_us: u32 = 0,
    perf_dirty_kpx: u16 = 0,
    wifi_on: bool = false,
    bt_on: bool = false,
    espnow_on: bool = false,
    /// CNC transport index — fallback when no wireless radio is on.
    conn: u8 = 4,
    unit_mm: bool = true,
    lefty: bool = false,
    /// ABI: `modulus_cnc_status_t` fields used by LVGL update paths.
    connected: bool = false,
    session: u8 = 0,
    /// Active WCS index 0..5 (G54–G59).
    wcs_i: u8 = 0,
    /// Wall clock text for status bar (engine formats from SystemPrefs / RTC).
    clock_buf: [16]u8 = .{ '-', '-', ':', '-', '-', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    homing_block: bool = false,
    accessories: u8 = 0,
    sd_percent: f32 = 0,
    line_number: u32 = 0,
    sd_streaming: bool = false,
    alarm_code: u8 = 0,
    /// Raw `CncStatus.state` (1=Idle…); device mirror drives cycle/hold gates.
    mach_state: u8 = 1,
    fan_on: bool = false,
    dro: dro_widget.State = .{
        .axis_count = 3,
        .selected = 0,
        .work_um = .{ -910585, -12300, -9400, 0, 0, 0 },
        .mach_um = .{ -910585, -12300, -9400, 0, 0, 0 },
    },
    jog: jog_widget.State = .{},
    jog_mode: usize = 0,
    jog_incr: usize = 1,
    /// Device mirror of `sd_file`; `job_name` points here when set.
    job_name_buf: [32]u8 = .{0} ** 32,
    incr_storage: [4][8]u8 = .{
        .{ '0', '.', '0', '0', '1', 0, 0, 0 },
        .{ '0', '.', '0', '1', 0, 0, 0, 0 },
        .{ '0', '.', '1', '0', 0, 0, 0, 0 },
        .{ '1', '.', '0', 0, 0, 0, 0, 0 },
    },
    elapsed: []const u8 = "0:00",
    /// Backing store for `elapsed` (LVGL `s_time` — elapsed · ETA).
    elapsed_buf: [40]u8 = .{0} ** 40,
    /// Wall seconds since strip became active (engine advances).
    job_elapsed_f: f32 = 0,
    /// `sd_percent` when the strip last opened — ETA baseline (LVGL `s_pct_at_t0`).
    job_pct_at_t0: f32 = 0,
    job_strip_was_active: bool = false,
    actions: actions_widget.State = .{},
    /// Job progress 0..1 — mirrors `sd_percent/100` when streaming/run.
    job_progress: f32 = 0,
    /// Spring-smoothed progress for strip paint (engine syncs).
    job_progress_vis: f32 = 0,
    /// No usable % (LVGL sd_percent ≤ 0.05) → indeterminate bar.
    job_indet: bool = false,
    /// Wave / slide phase for job strip (engine advances while strip visible + indet).
    job_wave_phase: f32 = 0,
    /// Spring-smoothed override readouts (engine syncs).
    feed_vis: f32 = 100,
    spindle_vis: f32 = 100,
    rapid_vis: f32 = 100,
    /// Which two override cards to paint (engine syncs from dash prefs).
    ovr_slots: [2]override_widget.Which = .{ .feed, .spindle },
    /// SD / external job name shown on job strip (LVGL `sd_file` stand-in).
    job_name: []const u8 = "",
    /// LED morph 0=circle idle … 1=diamond run (spring-driven from engine).
    led_morph: f32 = 0,

    pub fn selected_axis(self: CncView) usize {
        return self.dro.selected;
    }

    pub fn accView(self: CncView) actions_widget.AccView {
        return .{
            .accessories = self.accessories,
            .connected = self.connected,
            .fan_on = self.fan_on,
        };
    }

    pub fn setPhase(self: *CncView, phase: actions_widget.MachinePhase) void {
        self.actions.phase = phase;
        if (self.alarm_code != 0) {
            self.state = "ALARM";
        } else {
            self.state = switch (phase) {
                .idle => "Idle",
                .run => "RUN",
                .hold => "HOLD",
            };
        }
        // LVGL job strip: streaming || Run|Hold
        self.sd_streaming = phase == .run or phase == .hold;
        if (phase == .idle and self.alarm_code == 0) {
            self.sd_streaming = false;
        }
        self.syncJobProgressFromSd();
    }

    pub fn syncJobProgressFromSd(self: *CncView) void {
        // LVGL: has_pct = sd_percent > 0.05
        self.job_indet = self.sd_percent <= 0.05;
        if (self.job_indet) {
            self.job_progress = 0;
        } else {
            self.job_progress = std.math.clamp(self.sd_percent / 100.0, 0, 1);
        }
    }

    /// LVGL `ui_job_progress_update` time line: `m:ss` + optional ETA from % gain.
    pub fn formatJobElapsed(self: *CncView) void {
        const elapsed_s: u32 = @intFromFloat(@max(self.job_elapsed_f, 0));
        var el_buf: [16]u8 = undefined;
        const el = fmtMmSs(&el_buf, elapsed_s) catch "0:00";

        if (!self.job_indet and self.sd_percent > 1 and self.sd_percent < 99.5) {
            const gained = self.sd_percent - self.job_pct_at_t0;
            if (gained > 0.5 and elapsed_s > 2) {
                const rem = 100.0 - self.sd_percent;
                const eta_s: u32 = @intFromFloat((rem / gained) * @as(f32, @floatFromInt(elapsed_s)));
                var eta_buf: [16]u8 = undefined;
                const eta = fmtMmSs(&eta_buf, eta_s) catch "0:00";
                if (std.fmt.bufPrint(&self.elapsed_buf, "{s} | ETA {s}", .{ el, eta })) |out| {
                    self.elapsed = out;
                    return;
                } else |_| {}
            }
        }
        const n = copyElapsed(self, el);
        self.elapsed = self.elapsed_buf[0..n];
    }

    fn copyElapsed(self: *CncView, el: []const u8) usize {
        const n = @min(el.len, self.elapsed_buf.len);
        @memcpy(self.elapsed_buf[0..n], el[0..n]);
        return n;
    }

    fn fmtMmSs(buf: []u8, sec: u32) ![]const u8 {
        const m = sec / 60;
        const s = sec % 60;
        return std.fmt.bufPrint(buf, "{d}:{d:0>2}", .{ m, s });
    }

    /// Job strip filename fallback (LVGL: SD job vs External job).
    pub fn jobDisplayName(self: *const CncView) []const u8 {
        if (self.job_name.len > 0) return self.job_name;
        if (self.sd_streaming or !self.job_indet) return "SD job";
        return "External job";
    }

    /// Toggle quick assign — accessories bits for CNC tools; latch for LED/macro/USER.
    pub fn toggleQuickAssign(self: *CncView, slot: usize) void {
        if (!self.connected) {
            self.fan_on = false;
            return;
        }
        if (slot >= actions_widget.State.clampQuickCount(self.actions.quick_count)) return;
        const id = self.actions.quick[slot];
        switch (id) {
            .spindle_cw => self.accessories ^= actions_widget.Acc.spindle_cw,
            .spindle_ccw => self.accessories ^= actions_widget.Acc.spindle_ccw,
            .mist => self.accessories ^= actions_widget.Acc.mist,
            .coolant => self.accessories ^= actions_widget.Acc.flood,
            .fan => self.fan_on = !self.fan_on,
            .zero_all, .off => {},
            .led, .macro, .single_step, .user0, .user1, .user2, .user3 => self.actions.toggleLatch(slot),
        }
    }

    pub fn isQuickActive(self: CncView, slot: usize) bool {
        return self.actions.isQuickOn(slot, self.accView());
    }

    pub fn syncJogFromFields(self: *CncView) void {
        self.jog.mode = self.jog_mode;
        self.jog.incr = self.jog_incr;
        var i: usize = 0;
        while (i < 4) : (i += 1) {
            var len: usize = 0;
            while (len < self.incr_storage[i].len and self.incr_storage[i][len] != 0) : (len += 1) {}
            self.jog.value_overrides[i] = self.incr_storage[i][0..len];
        }
    }

    /// Status-bar network glyph: enabled wireless radios first, else CNC transport.
    pub fn netIcon(self: CncView) icons_phosphor.Id {
        if (self.wifi_on) return .wifi;
        if (self.bt_on) return .bluetooth;
        if (self.espnow_on) return .broadcast;
        return switch (self.conn) {
            0 => .broadcast, // ESP-NOW transport
            1, 2 => .wifi, // WebSocket / Telnet
            3, 4, 6, 7 => .usb, // Serial / RS-485 / I2C / CAN
            5 => .bluetooth, // BLE HID
            else => .wifi,
        };
    }

    pub fn clockText(self: *const CncView) []const u8 {
        return std.mem.sliceTo(&self.clock_buf, 0);
    }

    /// Session LED color — LVGL `bar_conn_color` parity (success/warn/neutral → cycle/hold/muted).
    pub fn connLedColor(self: CncView, theme: tokens.Theme) @import("color.zig").Rgb565 {
        if (!self.connected) return theme.on_surface_variant;
        if (self.session >= 4 and self.session <= 6) return theme.cycle;
        if (self.session >= 1 and self.session <= 3) return theme.hold;
        return theme.on_surface_variant;
    }

    /// State pill fill/ink — LVGL `bar_state_pill_style` + CNC color lock.
    pub fn statePillColors(self: CncView, theme: tokens.Theme) struct { bg: @import("color.zig").Rgb565, fg: @import("color.zig").Rgb565 } {
        if (!self.connected) {
            return .{ .bg = theme.tertiary_container, .fg = theme.on_tertiary_container };
        }
        if (self.alarm_code != 0 or std.mem.eql(u8, self.state, "ALARM") or std.mem.eql(u8, self.state, "Alarm")) {
            return .{ .bg = theme.error_container, .fg = theme.on_error_container };
        }
        return switch (self.actions.phase) {
            .run => .{ .bg = theme.cycle, .fg = theme.on_cycle },
            .hold => .{ .bg = theme.hold, .fg = theme.on_hold },
            .idle => if (self.homing_block)
                .{ .bg = theme.home, .fg = theme.on_home }
            else
                .{ .bg = theme.secondary_container, .fg = theme.on_secondary_container },
        };
    }
};

pub fn jobStripVisible(cnc: CncView) bool {
    // LVGL: streaming || Run|Hold
    return cnc.sd_streaming or cnc.actions.phase == .run or cnc.actions.phase == .hold;
}

pub fn bodyTop(cnc: CncView) i32 {
    return if (jobStripVisible(cnc)) status_h + job_strip_h else status_h;
}

pub const Hit = enum {
    none,
    settings,
    power,
    mpg,
    wcs,
};

pub fn paint(logical: *fb.LogicalFb, theme: tokens.Theme, cnc: CncView) void {
    var local = cnc;
    local.syncJogFromFields();
    logical.clear(theme.surface);
    paintStatus(logical, theme, local);
    paintJob(logical, theme, local);
    paintDroRegion(logical, theme, local);
    paintCenter(logical, theme, local);
    actions_widget.paint(logical, actionsBounds(local), theme, local.actions, local.accView());
}

pub fn statusBounds() geom.Rect {
    return .{ .x = 0, .y = 0, .w = tokens.Logical.width, .h = status_h };
}

pub fn jobStripBounds() geom.Rect {
    return .{ .x = 0, .y = status_h, .w = tokens.Logical.width, .h = job_strip_h };
}

/// Status bar only (Phase B regional invalidation).
pub fn paintStatus(logical: *fb.LogicalFb, theme: tokens.Theme, cnc: CncView) void {
    paintStatusBar(logical, theme, cnc);
}

/// Job strip only when Run|Hold; clear stale strip when hidden (bodyTop shifts).
pub fn paintJob(logical: *fb.LogicalFb, theme: tokens.Theme, cnc: CncView) void {
    if (!jobStripVisible(cnc)) {
        logical.fillRect(jobStripBounds(), theme.surface);
        return;
    }
    paintJobStrip(logical, theme, cnc);
}

/// DRO column only — clears bounds then paints cards.
pub fn paintDroRegion(logical: *fb.LogicalFb, theme: tokens.Theme, cnc: CncView) void {
    const b = droBounds(cnc);
    logical.fillRect(b, theme.surface);
    dro_widget.paint(logical, b, theme, cnc.dro);
}

fn paintStatusBar(logical: *fb.LogicalFb, theme: tokens.Theme, cnc: CncView) void {
    logical.fillRect(.{ .x = 0, .y = 0, .w = tokens.Logical.width, .h = status_h }, theme.elev(1));
    // LVGL bottom hairline
    logical.fillRect(.{ .x = 0, .y = status_h - 1, .w = tokens.Logical.width, .h = 1 }, theme.outline_variant);

    const bar_pad: i32 = tokens.Space.lg; // LVGL pad_hor SPACE_LG
    const pill_h: i32 = tokens.Logical.touch_min;
    const pill_y: i32 = @divTrunc(status_h - pill_h, 2);
    const mid_y: i32 = @divTrunc(status_h, 2);
    // LVGL icon sizes on the bar.
    const ico_24: i32 = 24;
    const ico_32: i32 = 32;
    const ico_40: i32 = 40;
    const chrome = theme.on_surface_variant;

    var x: i32 = bar_pad;
    expr.drawShapeMorph(logical, x + 8, mid_y, 8, cnc.led_morph, cnc.connLedColor(theme));
    x += 24;

    const pill = cnc.statePillColors(theme);
    const idle_label = if (!cnc.connected) "Offline" else cnc.state;
    // LVGL state pill: BODY_L
    const idle_tw = font.textWidthStr(idle_label, .body_l);
    const idle_w = @max(72, idle_tw + tokens.Space.md * 2);
    const state_r: geom.Rect = .{ .x = x, .y = pill_y, .w = idle_w, .h = pill_h };
    widgets.fillRoundRect(logical, state_r, tokens.Shape.full, pill.bg);
    font.drawTextRole(
        logical,
        x + @divTrunc(idle_w - idle_tw, 2),
        pill_y + @divTrunc(pill_h - font.faceHeight(font.faceForRole(.body_l)), 2),
        idle_label,
        pill.fg,
        .body_l,
    );
    // Alarm badge (LVGL corner dot)
    if (cnc.connected and (cnc.alarm_code != 0 or std.mem.eql(u8, cnc.state, "ALARM"))) {
        widgets.fillRoundRect(logical, .{ .x = state_r.x + state_r.w - 12, .y = state_r.y + 4, .w = 8, .h = 8 }, 4, theme.err);
    }
    x += idle_w + tokens.Space.md; // LVGL left group pad_column MD

    // MPG pill — LVGL ui_status_bar_build / update: icon 24, BODY_L, primary when on.
    const mpg_txt: []const u8 = if (cnc.mpg_active)
        (if (cnc.mpg_remote) "MPG rem" else "MPG")
    else
        "MPG off";
    const mpg_pad_h: i32 = tokens.Space.sm + tokens.Space.xs; // 12
    const mpg_gap: i32 = tokens.Space.xs + @divTrunc(tokens.Space.xs, 2); // 6
    const mpg_tw = font.textWidthStr(mpg_txt, .body_l);
    const mpg_w = mpg_pad_h * 2 + ico_24 + mpg_gap + mpg_tw;
    const mpg_r: geom.Rect = .{ .x = x, .y = pill_y, .w = mpg_w, .h = pill_h };
    const mpg_bg = if (cnc.mpg_active) theme.primary else theme.elev(3);
    const mpg_fg = if (cnc.mpg_active) theme.on_primary else theme.on_surface_variant;
    const mpg_ico = if (cnc.mpg_active) theme.on_primary else chrome;
    widgets.fillRoundRect(logical, mpg_r, tokens.Shape.full, mpg_bg);
    icons_phosphor.drawCenteredScaled(logical, x + mpg_pad_h + @divTrunc(ico_24, 2), mid_y, .gamepad, mpg_ico, ico_24);
    font.drawTextRole(
        logical,
        x + mpg_pad_h + ico_24 + mpg_gap,
        pill_y + @divTrunc(pill_h - font.faceHeight(font.faceForRole(.body_l)), 2),
        mpg_txt,
        mpg_fg,
        .body_l,
    );
    hit_mpg = mpg_r;
    x += mpg_w + tokens.Space.md;

    const wcs_x0 = x;
    x = drawStackPair(logical, x, "WCS", cnc.wcs, theme, true);
    hit_wcs = .{ .x = wcs_x0, .y = 8, .w = x - wcs_x0, .h = status_h - 16 };
    x = drawVRule(logical, x + 14, theme) + 16;
    x = drawStackPair(logical, x, "Tool", cnc.tool, theme, false);

    var rx: i32 = tokens.Logical.width - bar_pad;

    // Power + settings — 48×48 hit; LVGL glyphs MOD_UI_ICON_SZ_40.
    // LVGL settings fill = bar bg (invisible); power = transparent. No tonal chrome.
    rx -= 48;
    const power_r: geom.Rect = .{ .x = rx, .y = mid_y - 24, .w = 48, .h = 48 };
    icons_phosphor.drawCenteredScaled(logical, power_r.x + 24, power_r.y + 24, .power, theme.stop, ico_40);
    hit_power = power_r;

    rx -= 8 + 48;
    const gear_r: geom.Rect = .{ .x = rx, .y = mid_y - 24, .w = 48, .h = 48 };
    icons_phosphor.drawCenteredScaled(logical, gear_r.x + 24, gear_r.y + 24, .gear, chrome, ico_40);
    hit_gear = gear_r;

    if (cnc.perf_hud) {
        var pbuf: [28]u8 = undefined;
        const fps_i = cnc.perf_fps_x10 / 10;
        const fps_f = cnc.perf_fps_x10 % 10;
        const pline = std.fmt.bufPrint(&pbuf, "{d}.{d}f {d}/{d}ms {d}k", .{
            fps_i,
            fps_f,
            cnc.perf_paint_us / 1000,
            cnc.perf_rotate_us / 1000,
            cnc.perf_dirty_kpx,
        }) catch "";
        const pw = font.textWidthStr(pline, .label_s);
        rx = drawVRule(logical, rx - 14, theme) - 12;
        rx -= pw;
        font.drawTextRole(
            logical,
            rx,
            mid_y - @divTrunc(font.faceHeight(font.faceForRole(.label_s)), 2),
            pline,
            theme.primary,
            .label_s,
        );
    }

    rx = drawVRule(logical, rx - 14, theme) - 12;

    // Battery — vertical Phosphor by SoC / charge / fault; tint matches state.
    var bbuf: [8]u8 = undefined;
    const batt = std.fmt.bufPrint(&bbuf, "{d}%", .{cnc.battery_pct}) catch "0%";
    const batt_tw = @max(@as(i32, 44), font.textWidthStr(batt, .title_m));
    const batt_gap: i32 = tokens.Space.xs + @divTrunc(tokens.Space.xs, 2);
    const batt_ch = battery_chrome.forState(
        theme,
        chrome,
        cnc.battery_charge_state,
        cnc.battery_pct,
        cnc.battery_fast_charge,
    );
    const batt_fg = batt_ch.fg;
    rx -= batt_tw;
    font.drawTextRole(
        logical,
        rx + batt_tw - font.textWidthStr(batt, .title_m),
        mid_y - @divTrunc(font.faceHeight(font.faceForRole(.title_m)), 2),
        batt,
        batt_fg,
        .title_m,
    );
    rx -= batt_gap + ico_32;
    icons_phosphor.drawCenteredScaled(logical, rx + @divTrunc(ico_32, 2), mid_y, batt_ch.icon, batt_fg, ico_32);

    rx = drawVRule(logical, rx - 14, theme) - 12;

    const clock = cnc.clockText();
    // LVGL clock: TITLE_L (24) → closest bake `.title_l` (ui22).
    const time_tw = font.textWidthStr(clock, .title_l);
    rx -= time_tw;
    font.drawTextRole(logical, rx, mid_y - @divTrunc(font.faceHeight(font.faceForRole(.title_l)), 2), clock, theme.on_surface, .title_l);

    rx = drawVRule(logical, rx - 14, theme) - 12;

    // Wireless row — Wi-Fi / BLE / ESP-NOW @ 24px (LVGL ICON_SZ_24).
    const any_radio = cnc.wifi_on or cnc.bt_on or cnc.espnow_on;
    if (any_radio) {
        if (cnc.espnow_on) {
            rx -= ico_24;
            icons_phosphor.drawCenteredScaled(logical, rx + @divTrunc(ico_24, 2), mid_y, .broadcast, theme.primary, ico_24);
            rx -= tokens.Space.xs;
        }
        if (cnc.bt_on) {
            rx -= ico_24;
            icons_phosphor.drawCenteredScaled(logical, rx + @divTrunc(ico_24, 2), mid_y, .bluetooth, chrome, ico_24);
            rx -= tokens.Space.xs;
        }
        if (cnc.wifi_on) {
            rx -= ico_24;
            icons_phosphor.drawCenteredScaled(logical, rx + @divTrunc(ico_24, 2), mid_y, .wifi, theme.cycle, ico_24);
            rx -= tokens.Space.xs;
        }
    } else {
        rx -= ico_24;
        icons_phosphor.drawCenteredScaled(logical, rx + @divTrunc(ico_24, 2), mid_y, cnc.netIcon(), chrome, ico_24);
    }

    rx = drawVRule(logical, rx - 14, theme) - 20;

    rx = drawMetric(logical, rx, cnc.spindle_rpm, "Spindle", "RPM", theme) - 32;
    _ = drawMetric(logical, rx, cnc.feed_mm_min, "Feed", "mm/min", theme);
}

var hit_gear: geom.Rect = .{};
var hit_power: geom.Rect = .{};
var hit_mpg: geom.Rect = .{};
var hit_wcs: geom.Rect = .{};

fn drawVRule(logical: *fb.LogicalFb, x: i32, theme: tokens.Theme) i32 {
    const top: i32 = 18;
    const bot: i32 = status_h - 18;
    var y: i32 = top;
    while (y < bot) : (y += 1) {
        if (x >= 0 and x < logical.w and y >= 0 and y < logical.h) {
            const i = @as(usize, @intCast(y)) * @as(usize, logical.w) + @as(usize, @intCast(x));
            logical.pixels[i] = theme.outline_variant;
        }
    }
    return x;
}

fn drawStackPair(
    logical: *fb.LogicalFb,
    x: i32,
    label: []const u8,
    value: []const u8,
    theme: tokens.Theme,
    accent_value: bool,
) i32 {
    // Match ref: small label over large value; value uses primary when accented (WCS).
    const label_role: tokens.TypeRole = .label_s;
    const value_role: tokens.TypeRole = .title_l;
    const label_h = font.faceHeight(font.faceForRole(label_role));
    const value_h = font.faceHeight(font.faceForRole(value_role));
    const gap: i32 = 2;
    const block_h = label_h + gap + value_h;
    const y0 = @divTrunc(status_h - block_h, 2);
    font.drawTextRole(logical, x, y0, label, theme.on_surface_variant, label_role);
    const vfg = if (accent_value) theme.primary else theme.on_surface;
    font.drawTextRole(logical, x, y0 + label_h + gap, value, vfg, value_role);
    const lw = font.textWidthStr(label, label_role);
    const vw = font.textWidthStr(value, value_role);
    return x + @max(lw, vw);
}

/// Label above; big number + unit on one line — right-aligned as a block (ref Feed/Spindle).
fn drawMetric(logical: *fb.LogicalFb, right: i32, value: u32, label: []const u8, unit: []const u8, theme: tokens.Theme) i32 {
    var nbuf: [12]u8 = undefined;
    const num = std.fmt.bufPrint(&nbuf, "{d}", .{value}) catch "0";
    const num_face: font.Face = .ui22;
    const num_w = font.textWidthFace(num, num_face);
    const num_h = font.faceHeight(num_face);
    const unit_role: tokens.TypeRole = .label_s;
    const label_role: tokens.TypeRole = .label_s;
    const unit_w = font.textWidthStr(unit, unit_role);
    const gap_nu: i32 = 6;
    const value_row_w = num_w + gap_nu + unit_w;
    const lab_w = font.textWidthStr(label, label_role);
    const block_w = @max(lab_w, value_row_w);
    const x0 = right - block_w;

    const lab_h = font.faceHeight(font.faceForRole(label_role));
    const gap: i32 = 2;
    const block_h = lab_h + gap + num_h;
    const y0 = @divTrunc(status_h - block_h, 2);

    // Label right-aligned to block
    font.drawTextRole(logical, x0 + block_w - lab_w, y0, label, theme.on_surface_variant, label_role);

    // Value row right-aligned: number + unit (LVGL on_surface for value)
    const row_x = x0 + block_w - value_row_w;
    const row_y = y0 + lab_h + gap;
    font.drawTextFace(logical, row_x, row_y, num, theme.on_surface, num_face);
    const unit_y = row_y + @divTrunc(num_h - font.faceHeight(font.faceForRole(unit_role)), 2);
    font.drawTextRole(logical, row_x + num_w + gap_nu, unit_y, unit, theme.on_surface_variant, unit_role);
    return x0;
}

pub fn hitStatus(x: i32, y: i32) Hit {
    return hitStatusDetail(x, y).hit;
}

pub fn hitStatusDetail(x: i32, y: i32) struct { hit: Hit, rect: geom.Rect } {
    if (y >= status_h) return .{ .hit = .none, .rect = .{} };
    if (hit_power.contains(x, y)) return .{ .hit = .power, .rect = hit_power };
    if (hit_gear.contains(x, y)) return .{ .hit = .settings, .rect = hit_gear };
    if (hit_mpg.contains(x, y)) return .{ .hit = .mpg, .rect = hit_mpg };
    if (hit_wcs.contains(x, y)) return .{ .hit = .wcs, .rect = hit_wcs };
    return .{ .hit = .none, .rect = .{} };
}

fn paintJobStrip(logical: *fb.LogicalFb, theme: tokens.Theme, cnc: CncView) void {
    if (!jobStripVisible(cnc)) return;
    job_progress_widget.paint(logical, theme, status_h, .{
        .progress = cnc.job_progress_vis,
        .indet = cnc.job_indet,
        .phase = cnc.job_wave_phase,
        .hold = cnc.actions.phase == .hold,
        .name = cnc.jobDisplayName(),
        .elapsed = cnc.elapsed,
        .line = cnc.line_number,
    });
}

/// LVGL `ui_dashboard.c` main row: pad_all + pad_column = SPACE_LG; dro=420; actions=280.
pub fn centerColumnBounds(cnc: CncView) geom.Rect {
    const top = bodyTop(cnc);
    const center_w = tokens.Logical.width - pad * 2 - dro_w - actions_w - pad * 2;
    const x: i32 = if (cnc.lefty) pad + actions_w + pad else pad + dro_w + pad;
    return .{
        .x = x,
        .y = top + pad,
        .w = center_w,
        .h = tokens.Logical.height - top - pad * 2,
    };
}

pub fn droBounds(cnc: CncView) geom.Rect {
    const top = bodyTop(cnc);
    // Full 420 panel — card pad (SPACE_MD) is inside dro_widget, not here.
    const x: i32 = if (cnc.lefty) tokens.Logical.width - pad - dro_w else pad;
    return .{
        .x = x,
        .y = top + pad,
        .w = dro_w,
        .h = tokens.Logical.height - top - pad * 2,
    };
}

/// Which dashboard column owns a point (strict bounds, no glove pad).
pub const Panel = enum { none, status, dro, jog, override, actions };

pub fn panelAt(x: i32, y: i32, cnc: CncView) Panel {
    if (y < status_h and x >= 0 and x < tokens.Logical.width) return .status;
    if (actionsBounds(cnc).containsStrict(x, y)) return .actions;
    if (jogBounds(cnc).containsStrict(x, y)) return .jog;
    if (overrideBounds(cnc).containsStrict(x, y)) return .override;
    if (droBounds(cnc).containsStrict(x, y)) return .dro;
    return .none;
}

pub fn hitDro(x: i32, y: i32, cnc: CncView) dro_widget.Hit {
    const b = droBounds(cnc);
    // Strict outer gate — padded `contains` was letting edge taps from the
    // jog column land on Home/Zero along the DRO's right edge.
    if (!b.containsStrict(x, y)) return .{};
    return dro_widget.hitTest(b, cnc.dro, x, y);
}

fn paintCenter(logical: *fb.LogicalFb, theme: tokens.Theme, cnc: CncView) void {
    var local = cnc;
    local.syncJogFromFields();
    local.jog.mode = local.jog_mode;
    local.jog.incr = local.jog_incr;
    jog_widget.paint(logical, jogBounds(local), theme, local.jog);

    override_widget.paintPair(logical, overrideBounds(local), theme, .{
        .feed_pct = local.feed_pct,
        .spindle_pct = local.spindle_pct,
        .rapid_pct = local.rapid_pct,
        .feed_vis = local.feed_vis,
        .spindle_vis = local.spindle_vis,
        .rapid_vis = local.rapid_vis,
    }, local.ovr_slots);
}

pub fn paintCenterRegion(logical: *fb.LogicalFb, theme: tokens.Theme, cnc: CncView) void {
    const b = overrideBounds(cnc);
    const jog = jogBounds(cnc);
    const area: geom.Rect = .{
        .x = jog.x,
        .y = jog.y,
        .w = jog.w,
        .h = (b.y + b.h) - jog.y,
    };
    logical.fillRect(area, theme.surface);
    paintCenter(logical, theme, cnc);
}

pub fn paintActionsRegion(logical: *fb.LogicalFb, theme: tokens.Theme, cnc: CncView) void {
    const b = actionsBounds(cnc);
    logical.fillRect(b, theme.surface);
    actions_widget.paint(logical, b, theme, cnc.actions, cnc.accView());
}

pub fn jogBounds(cnc: CncView) geom.Rect {
    const c = centerColumnBounds(cnc);
    return .{ .x = c.x, .y = c.y, .w = c.w, .h = jog_widget.card_h };
}

pub fn overrideBounds(cnc: CncView) geom.Rect {
    const c = centerColumnBounds(cnc);
    const jog = jogBounds(cnc);
    const gap: i32 = pad; // LVGL center pad_row = SPACE_LG
    return .{
        .x = c.x,
        .y = jog.y + jog.h + gap,
        .w = c.w,
        .h = @max(0, (c.y + c.h) - (jog.y + jog.h + gap)),
    };
}

pub fn actionsBounds(cnc: CncView) geom.Rect {
    const top = bodyTop(cnc);
    // Full 280 panel — matches LVGL `panel_w = 280`.
    const x: i32 = if (cnc.lefty) pad else tokens.Logical.width - pad - actions_w;
    return .{
        .x = x,
        .y = top + pad,
        .w = actions_w,
        .h = tokens.Logical.height - top - pad * 2,
    };
}

pub fn hitActions(x: i32, y: i32, cnc: CncView) actions_widget.Hit {
    return actions_widget.hitTest(actionsBounds(cnc), cnc.actions, x, y);
}

pub fn hitOverrides(x: i32, y: i32, cnc: CncView) override_widget.Hit {
    return override_widget.hitTest(overrideBounds(cnc), x, y, cnc.ovr_slots);
}

pub fn hitJog(x: i32, y: i32, cnc: CncView) jog_widget.Hit {
    return jog_widget.hitTest(jogBounds(cnc), x, y);
}

test "netIcon prefers wireless radios over CNC transport" {
    var cnc: CncView = .{ .conn = 4 }; // RS-485 → usb fallback
    try std.testing.expect(cnc.netIcon() == .usb);
    cnc.bt_on = true;
    try std.testing.expect(cnc.netIcon() == .bluetooth);
    cnc.wifi_on = true;
    try std.testing.expect(cnc.netIcon() == .wifi);
}

test "state pill uses CNC color lock" {
    const theme = tokens.Theme.industrialTealDark();
    var cnc: CncView = .{ .connected = true };
    cnc.setPhase(.run);
    const run = cnc.statePillColors(theme);
    try std.testing.expect(run.bg.toU16() == theme.cycle.toU16());
    cnc.setPhase(.hold);
    const hold = cnc.statePillColors(theme);
    try std.testing.expect(hold.bg.toU16() == theme.hold.toU16());
}

test "status hits include mpg after paint" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();
    paintStatus(&logical, theme, .{});
    try std.testing.expect(hit_mpg.w > 0);
    try std.testing.expect(hitStatus(hit_mpg.x + 4, hit_mpg.y + 4) == .mpg);
    try std.testing.expect(hitStatus(hit_wcs.x + 4, hit_wcs.y + 4) == .wcs);
    // Gear / power are 48×48 hits (LVGL).
    try std.testing.expectEqual(@as(i32, 48), hit_gear.w);
    try std.testing.expectEqual(@as(i32, 48), hit_power.w);
}

test "MPG pill label matches LVGL active/off/rem" {
    const gpa = std.testing.allocator;
    var logical = try fb.LogicalFb.alloc(gpa);
    defer logical.deinit(gpa);
    const theme = tokens.Theme.industrialTealDark();

    paintStatus(&logical, theme, .{ .mpg_active = false });
    const off_w = hit_mpg.w;
    paintStatus(&logical, theme, .{ .mpg_active = true, .mpg_remote = false });
    try std.testing.expect(hit_mpg.w < off_w); // "MPG" shorter than "MPG off"
    paintStatus(&logical, theme, .{ .mpg_active = true, .mpg_remote = true });
    try std.testing.expect(hit_mpg.w > 0);
    try std.testing.expect(hit_mpg.h >= tokens.Logical.touch_min);
}

test "layout rails match LVGL dashboard" {
    try std.testing.expectEqual(@as(i32, 420), dro_w);
    try std.testing.expectEqual(@as(i32, 280), actions_w);
    try std.testing.expectEqual(@as(i32, 60), job_strip_h);
    try std.testing.expectEqual(@as(i32, 80), status_h);
}

test "bodyTop grows for Run and Hold job strip" {
    var cnc: CncView = .{};
    try std.testing.expectEqual(status_h, bodyTop(cnc));
    cnc.setPhase(.run);
    try std.testing.expectEqual(status_h + job_strip_h, bodyTop(cnc));
    try std.testing.expect(jobStripVisible(cnc));
    cnc.setPhase(.hold);
    try std.testing.expectEqual(status_h + job_strip_h, bodyTop(cnc));
    cnc.setPhase(.idle);
    try std.testing.expect(!jobStripVisible(cnc));
}

test "center column width from LVGL rails" {
    const cnc: CncView = .{};
    // 1280 − 2×24 margin − 420 − 280 − 2×24 column gaps = 484
    const center = centerColumnBounds(cnc);
    try std.testing.expectEqual(@as(i32, 484), center.w);
    try std.testing.expectEqual(@as(i32, pad + dro_w + pad), center.x);
    const jog = jogBounds(cnc);
    try std.testing.expectEqual(center.w, jog.w);
    try std.testing.expectEqual(status_h + pad, jog.y);
    const dro = droBounds(cnc);
    try std.testing.expectEqual(@as(i32, dro_w), dro.w);
    try std.testing.expectEqual(pad, dro.x);
    const act = actionsBounds(cnc);
    try std.testing.expectEqual(@as(i32, actions_w), act.w);
    try std.testing.expectEqual(tokens.Logical.width - pad - actions_w, act.x);
    // Columns do not overlap.
    try std.testing.expect(geom.Rect.intersect(dro, jog).isEmpty());
    try std.testing.expect(geom.Rect.intersect(jog, act).isEmpty());
}

test "lefty center sits between actions and DRO" {
    const cnc: CncView = .{ .lefty = true };
    const jog = jogBounds(cnc);
    const dro = droBounds(cnc);
    const act = actionsBounds(cnc);
    try std.testing.expect(jog.x >= act.x + act.w);
    try std.testing.expect(jog.x + jog.w <= dro.x);
    try std.testing.expect(geom.Rect.intersect(jog, dro).isEmpty());
    try std.testing.expectEqual(pad, act.x);
    try std.testing.expectEqual(tokens.Logical.width - pad - dro_w, dro.x);
}

test "panelAt: jog tap is not dro" {
    const cnc: CncView = .{};
    const jog = jogBounds(cnc);
    const dro = droBounds(cnc);
    try std.testing.expect(panelAt(jog.x + 8, jog.y + 8, cnc) == .jog);
    try std.testing.expect(panelAt(dro.x + dro.w - 4, dro.y + 40, cnc) == .dro);
    // Just right of DRO must not route as DRO (Home/Zero live on that edge).
    try std.testing.expect(panelAt(dro.x + dro.w + 4, dro.y + 40, cnc) != .dro);
    try std.testing.expect(hitDro(jog.x + 8, jog.y + 8, cnc).kind == .none);
}

test "CncView ABI fields drive accessories and job strip" {
    var cnc: CncView = .{};
    try std.testing.expect(!cnc.connected);
    cnc.connected = true;
    try std.testing.expectEqual(@as(u8, 0), cnc.accessories);
    cnc.actions.quick[0] = .spindle_cw;
    cnc.toggleQuickAssign(0);
    try std.testing.expectEqual(actions_widget.Acc.spindle_cw, cnc.accessories);
    try std.testing.expect(cnc.isQuickActive(0));
    cnc.connected = false;
    try std.testing.expect(!cnc.isQuickActive(0));

    cnc.connected = true;
    cnc.sd_streaming = true;
    try std.testing.expect(jobStripVisible(cnc));
    cnc.sd_streaming = false;
    cnc.setPhase(.idle);
    try std.testing.expect(!jobStripVisible(cnc));
    cnc.setPhase(.run);
    try std.testing.expect(cnc.sd_streaming);
    try std.testing.expect(jobStripVisible(cnc));
}

test "job elapsed formats ETA like LVGL" {
    var cnc: CncView = .{};
    cnc.job_indet = false;
    cnc.sd_percent = 50;
    cnc.job_pct_at_t0 = 10;
    cnc.job_elapsed_f = 40;
    cnc.formatJobElapsed();
    try std.testing.expect(std.mem.indexOf(u8, cnc.elapsed, "ETA") != null);
    try std.testing.expect(std.mem.startsWith(u8, cnc.elapsed, "0:40"));
}

test "job display name falls back External vs SD" {
    var cnc: CncView = .{};
    cnc.job_name = "";
    cnc.job_indet = true;
    cnc.sd_streaming = false;
    try std.testing.expectEqualStrings("External job", cnc.jobDisplayName());
    cnc.sd_streaming = true;
    try std.testing.expectEqualStrings("SD job", cnc.jobDisplayName());
}

test "syncJobProgressFromSd indet threshold" {
    var cnc: CncView = .{};
    cnc.sd_percent = 0.04;
    cnc.syncJobProgressFromSd();
    try std.testing.expect(cnc.job_indet);
    try std.testing.expectEqual(@as(f32, 0), cnc.job_progress);
    cnc.sd_percent = 42;
    cnc.syncJobProgressFromSd();
    try std.testing.expect(!cnc.job_indet);
    try std.testing.expectApproxEqAbs(@as(f32, 0.42), cnc.job_progress, 0.001);
}
