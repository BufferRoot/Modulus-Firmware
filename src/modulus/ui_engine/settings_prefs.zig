//! Host settings prefs — mirrors Tab5 NVS keys for Dashboard & Display tabs.

const std = @import("std");
const color = @import("color.zig");
const tokens = @import("tokens.zig");
const dro_widget = @import("dro_widget.zig");
const actions_widget = @import("actions_widget.zig");
const override_widget = @import("override_widget.zig");
const dashboard = @import("dashboard.zig");
const battery_chrome = @import("battery_chrome.zig");

pub const confirm_never: u8 = 0;
pub const confirm_always: u8 = 1;
pub const confirm_when_running: u8 = 2;

pub const ConfirmPolicy = struct {
    cycle: u8 = confirm_never,
    spin: u8 = confirm_never,
    zero: u8 = confirm_when_running,
    home: u8 = confirm_never,
    mac: u8 = confirm_never,

    pub const labels = [_][]const u8{ "Never", "Always", "When running" };

    pub fn clamp(v: u8) u8 {
        return if (v > 2) 0 else v;
    }

    pub fn label(v: u8) []const u8 {
        return labels[clamp(v)];
    }
};

pub const MacroSlot = struct {
    name: [16]u8 = .{0} ** 16,
    on: [64]u8 = .{0} ** 64,
    off: [64]u8 = .{0} ** 64,

    pub fn occupied(self: *const MacroSlot) bool {
        return cstrSlice(&self.name).len > 0 and cstrSlice(&self.on).len > 0;
    }
    pub fn nameSlice(self: *const MacroSlot) []const u8 {
        return cstrSlice(&self.name);
    }
    pub fn onSlice(self: *const MacroSlot) []const u8 {
        return cstrSlice(&self.on);
    }
    pub fn offSlice(self: *const MacroSlot) []const u8 {
        return cstrSlice(&self.off);
    }
    pub fn setField(dst: []u8, src: []const u8) void {
        @memset(dst, 0);
        const n = @min(src.len, dst.len);
        var j: usize = 0;
        for (src[0..n]) |c| {
            if (c == '|') continue;
            dst[j] = c;
            j += 1;
            if (j >= dst.len) break;
        }
    }
    /// LVGL `cnc_macN` = `Label|on|off|icon`.
    pub fn packNvs(self: *const MacroSlot, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{s}|{s}|{s}|0", .{
            self.nameSlice(),
            self.onSlice(),
            self.offSlice(),
        }) catch "";
    }
    pub fn unpackNvs(self: *MacroSlot, raw: []const u8) bool {
        @memset(&self.name, 0);
        @memset(&self.on, 0);
        @memset(&self.off, 0);
        var parts: [3][]const u8 = .{ "", "", "" };
        var pi: usize = 0;
        var start: usize = 0;
        for (raw, 0..) |c, i| {
            // Stop after name|on|off — trailing `|icon` ignored.
            if (c == '|' and pi < 2) {
                parts[pi] = raw[start..i];
                pi += 1;
                start = i + 1;
            } else if (c == '|' and pi == 2) {
                parts[2] = raw[start..i];
                pi = 3;
                break;
            }
        }
        if (pi < 2) return false;
        if (pi == 2) parts[2] = raw[start..];
        if (parts[0].len == 0 or parts[1].len == 0) return false;
        setField(&self.name, parts[0]);
        setField(&self.on, parts[1]);
        setField(&self.off, parts[2]);
        return self.occupied();
    }
};

pub const DashboardPrefs = struct {
    /// Axes preset 0..4 → visible 2..6 (firmware `cnc_axes`).
    axes_preset: u8 = 1,
    jog_mode: u8 = 0,
    jog_incr_sel: u8 = 1,
    /// Four increment value strings (ASCII, null-padded).
    incr: [4][8]u8 = .{
        padIncr("0.001"),
        padIncr("0.01"),
        padIncr("0.1"),
        padIncr("1.0"),
    },
    wcs: u8 = 0,
    wcs_lock: u8 = 0,
    /// Custom labels for G54–G59 (`wcs_n0`–`n5`).
    wcs_names: [6][16]u8 = .{.{0} ** 16} ** 6,
    unit_mm: bool = true,
    confirm: ConfirmPolicy = .{},
    jog_coal_ms: u8 = 20,
    jog_pend_max: u8 = 32,
    encdiv: u8 = 2,
    jogspd_idx: u8 = 1,
    contpct: u8 = 100,
    stepacc: bool = false,
    mpgpol: u8 = 0,
    /// Override cards shown on dashboard (exactly 2). 0=Feed 1=Spindle 2=Rapid.
    ovr_left: u8 = 0,
    ovr_right: u8 = 1,
    probe_zoff_x10: u16 = 100,
    /// LVGL qs_probe NVS (×10).
    probe_max_x10: u16 = 250,
    probe_feed_x10: u16 = 750,
    probe_retr_x10: u16 = 20,
    probe_tip_x10: u16 = 20,
    quick_count: u8 = 4,
    /// LVGL qbtn_defaults {0,2,3,4} = CW, Coolant, Fan, Zero-all.
    quick: [4]actions_widget.QuickId = .{ .spindle_cw, .coolant, .fan, .zero_all },
    /// Custom G-code buttons (`cnc_mac0`–`3`); dashboard assign via QuickId.user0–3.
    macros: [4]MacroSlot = [_]MacroSlot{.{}} ** 4,
    hw_ref_exp: bool = false,

    pub const jogspd_labels = [_][]const u8{ "500", "1000", "2000", "3000", "5000", "8000", "10000" };
    pub const jogspd_mm = [_]u16{ 500, 1000, 2000, 3000, 5000, 8000, 10000 };

    pub fn jogspdMmAt(idx: u8) u16 {
        return jogspd_mm[@min(idx, jogspd_mm.len - 1)];
    }

    pub fn setJogspdIdxFromMm(self: *DashboardPrefs, mm: u16) void {
        var best: u8 = 0;
        for (jogspd_mm, 0..) |v, i| {
            if (v == mm) {
                self.jogspd_idx = @intCast(i);
                return;
            }
            if (v <= mm) best = @intCast(i);
        }
        self.jogspd_idx = best;
    }

    pub fn axesVisible(self: DashboardPrefs) u8 {
        const counts = [_]u8{ 2, 3, 4, 5, 6 };
        const p = if (self.axes_preset > 4) @as(u8, 1) else self.axes_preset;
        return counts[p];
    }

    pub fn setAxesVisible(self: *DashboardPrefs, n: u8) void {
        const v = @max(2, @min(6, n));
        self.axes_preset = v - 2;
    }

    pub fn incrSlice(self: *const DashboardPrefs, i: usize) []const u8 {
        if (i >= 4) return "0";
        const raw = &self.incr[i];
        var len: usize = 0;
        while (len < raw.len and raw[len] != 0) : (len += 1) {}
        return raw[0..len];
    }

    pub fn incrCsv(self: *const DashboardPrefs, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{s},{s},{s},{s}", .{
            self.incrSlice(0),
            self.incrSlice(1),
            self.incrSlice(2),
            self.incrSlice(3),
        }) catch "0.001,0.01,0.1,1.0";
    }

    pub fn setIncrFromCsv(self: *DashboardPrefs, csv: []const u8) void {
        var start: usize = 0;
        var slot: usize = 0;
        while (slot < 4) : (slot += 1) {
            const end = std.mem.indexOfScalarPos(u8, csv, start, ',') orelse csv.len;
            var piece = std.mem.trim(u8, csv[start..end], " \t");
            if (piece.len == 0) piece = "0";
            @memset(&self.incr[slot], 0);
            const n = @min(piece.len, self.incr[slot].len);
            @memcpy(self.incr[slot][0..n], piece[0..n]);
            if (end >= csv.len) {
                slot += 1;
                while (slot < 4) : (slot += 1) {
                    @memset(&self.incr[slot], 0);
                    self.incr[slot][0] = '0';
                }
                break;
            }
            start = end + 1;
        }
    }

    pub fn wcsNameSlice(self: *const DashboardPrefs, i: usize) []const u8 {
        if (i >= 6) return "";
        return cstrSlice(&self.wcs_names[i]);
    }

    pub fn setWcsName(self: *DashboardPrefs, i: usize, name: []const u8) void {
        if (i >= 6) return;
        MacroSlot.setField(&self.wcs_names[i], name);
    }

    pub fn wcsDisplayLabel(self: *const DashboardPrefs, i: usize) []const u8 {
        const custom = self.wcsNameSlice(i);
        if (custom.len > 0) return custom;
        return self.wcsLabelAt(i);
    }

    pub fn wcsLabelAt(_: DashboardPrefs, i: usize) []const u8 {
        const labs = [_][]const u8{ "G54", "G55", "G56", "G57", "G58", "G59" };
        return labs[@min(i, 5)];
    }

    pub fn macroOccupiedCount(self: *const DashboardPrefs) u8 {
        var n: u8 = 0;
        for (self.macros) |m| {
            if (m.occupied()) n += 1;
        }
        return n;
    }

    pub fn firstFreeMacro(self: *const DashboardPrefs) ?u8 {
        for (self.macros, 0..) |m, i| {
            if (!m.occupied()) return @intCast(i);
        }
        return null;
    }

    pub fn clearMacro(self: *DashboardPrefs, slot: u8) void {
        if (slot >= 4) return;
        self.macros[slot] = .{};
    }

    pub fn saveMacro(self: *DashboardPrefs, slot: u8, name: []const u8, on: []const u8, off: []const u8) bool {
        if (slot >= 4 or name.len == 0 or on.len == 0) return false;
        MacroSlot.setField(&self.macros[slot].name, name);
        MacroSlot.setField(&self.macros[slot].on, on);
        MacroSlot.setField(&self.macros[slot].off, off);
        return self.macros[slot].occupied();
    }

    pub fn quickAssignLabel(self: *const DashboardPrefs, id: actions_widget.QuickId) []const u8 {
        return switch (id) {
            .off => "Off - hide on dashboard",
            .user0 => if (self.macros[0].occupied()) self.macros[0].nameSlice() else "USER 0",
            .user1 => if (self.macros[1].occupied()) self.macros[1].nameSlice() else "USER 1",
            .user2 => if (self.macros[2].occupied()) self.macros[2].nameSlice() else "USER 2",
            .user3 => if (self.macros[3].occupied()) self.macros[3].nameSlice() else "USER 3",
            else => id.label(),
        };
    }

    pub fn wcsLabel(self: DashboardPrefs) []const u8 {
        return self.wcsDisplayLabel(self.wcs);
    }

    pub fn jogspdMmMin(self: DashboardPrefs) u16 {
        const opts = [_]u16{ 500, 1000, 2000, 3000, 5000, 8000, 10000 };
        return opts[@min(self.jogspd_idx, opts.len - 1)];
    }

    pub fn cycleIncrPreset(self: *DashboardPrefs) void {
        // Rotate through two common packs
        const packs = [_][4][]const u8{
            .{ "0.001", "0.01", "0.1", "1.0" },
            .{ "0.01", "0.1", "1.0", "5.0" },
        };
        const which: usize = if (std.mem.eql(u8, self.incrSlice(0), "0.001")) 1 else 0;
        for (packs[which], 0..) |s, i| {
            @memset(&self.incr[i], 0);
            @memcpy(self.incr[i][0..s.len], s);
        }
    }

    pub fn resetDefaults(self: *DashboardPrefs) void {
        self.* = .{};
    }

    pub fn ovrSlots(self: DashboardPrefs) [2]override_widget.Which {
        return override_widget.coercePair(
            override_widget.clampWhich(self.ovr_left),
            override_widget.clampWhich(self.ovr_right),
        );
    }

    pub fn setOvrLeft(self: *DashboardPrefs, v: u8) void {
        self.ovr_left = @intFromEnum(override_widget.clampWhich(v));
        const pair = self.ovrSlots();
        self.ovr_left = @intFromEnum(pair[0]);
        self.ovr_right = @intFromEnum(pair[1]);
    }

    pub fn setOvrRight(self: *DashboardPrefs, v: u8) void {
        self.ovr_right = @intFromEnum(override_widget.clampWhich(v));
        const pair = self.ovrSlots();
        self.ovr_left = @intFromEnum(pair[0]);
        self.ovr_right = @intFromEnum(pair[1]);
    }

    pub fn apply(self: DashboardPrefs, cnc: *dashboard.CncView) void {
        self.applyLayout(cnc);
        cnc.jog_mode = self.jog_mode;
        cnc.jog_incr = self.jog_incr_sel;
        cnc.wcs = self.wcsLabel();
        cnc.wcs_i = self.wcs;
        cnc.syncJogFromFields();
    }

    /// Axes / quick / units / incr labels — safe when device mirror owns jog + WCS.
    pub fn applyLayout(self: DashboardPrefs, cnc: *dashboard.CncView) void {
        cnc.dro.setAxisCount(self.axesVisible());
        cnc.actions.quick_count = actions_widget.State.clampQuickCount(self.quick_count);
        cnc.actions.quick = self.quick;
        cnc.dro.unit_mm = self.unit_mm;
        cnc.unit_mm = self.unit_mm;
        cnc.ovr_slots = self.ovrSlots();
        for (0..4) |i| {
            @memset(&cnc.incr_storage[i], 0);
            const s = self.incrSlice(i);
            const n = @min(s.len, cnc.incr_storage[i].len);
            @memcpy(cnc.incr_storage[i][0..n], s[0..n]);
        }
        cnc.syncJogFromFields();
    }
};

pub const DisplayPrefs = struct {
    bright: u8 = 80,
    darkmode: bool = true,
    accent: u8 = 0,
    ui_contrast: u8 = 0,
    /// MD3 system font size: 0=Small 1=Default 2=Large 3=Largest.
    font_scale: u8 = 1,
    touch_glove: bool = false,
    wake_motion: bool = false,
    sw_icons: bool = true,
    flip: bool = false,
    lefty: bool = false,
    /// Host/demo: force MD3 compact settings (hub → detail) even on Tab5 width.
    single_pane: bool = false,
    refr_hz: u8 = 0,
    smooth_anim: bool = true,
    /// 0=standard 1=expressive (LVGL NVS default Standard).
    motion_scheme: u8 = 0,
    theme_ref_exp: bool = false,
    /// Snackbar (toast) notifications master switch.
    notify_en: bool = false,
    /// Lowest importance that still shows: 0=all, 1=important, 2=errors only.
    notify_level: u8 = 0,

    pub fn fontScaleName(self: DisplayPrefs) []const u8 {
        return switch (@min(self.font_scale, 3)) {
            0 => "Small",
            2 => "Large",
            3 => "Largest",
            else => "Default",
        };
    }

    pub fn notifyLevelName(self: DisplayPrefs) []const u8 {
        return switch (self.notify_level) {
            1 => "Important and errors",
            2 => "Errors only",
            else => "Everything",
        };
    }

    pub fn resetDefaults(self: *DisplayPrefs) void {
        // Match LVGL display_reset_cb: bright → 100, motion_scheme → 0.
        self.* = .{};
        self.bright = 100;
    }

    pub const accent_names = [_][]const u8{
        "Industrial Teal",
        "Cyber-Industrial",
        "Nocturnal Safety",
        "Deep Sea",
        "Steel & Ruby",
        "Electric Orchid",
        "Tactical Sage",
        "Nordic White",
        "Monochrome Pro",
    };

    pub fn accentName(self: DisplayPrefs) []const u8 {
        return accent_names[@min(self.accent, accent_names.len - 1)];
    }

    pub fn refrLabel(self: DisplayPrefs) []const u8 {
        return switch (self.refr_hz) {
            1 => "Balanced",
            2 => "Power saver",
            else => "Fastest",
        };
    }

    pub fn refrHint(self: DisplayPrefs) []const u8 {
        return switch (self.refr_hz) {
            1 => "~25 Hz UI - balanced battery",
            2 => "~20 Hz UI - max battery",
            else => "~30 Hz UI - snappiest dashboard",
        };
    }

    /// LVGL `refresh_ms_from_hz` — dashboard timer period (never below 33 ms floor).
    pub fn refreshPeriodMs(self: DisplayPrefs) u32 {
        return switch (self.refr_hz) {
            1 => 40,
            2 => 50,
            else => 33,
        };
    }

    pub fn buildTheme(self: DisplayPrefs) tokens.Theme {
        var t = if (self.darkmode) tokens.Theme.industrialTealDark() else tokens.Theme.industrialTealLight();
        applyAccent(&t, self.accent, self.darkmode);
        t.applyContrastLevel(self.ui_contrast);
        return t;
    }
};

pub const proto_names = [_][]const u8{ "GrblHAL", "Grbl", "FluidNC", "LinuxCNC", "Mach3/Mach4", "Masso" };
pub const transport_names = [_][]const u8{ "ESP-NOW", "WebSocket", "Telnet", "Serial USB", "RS-485", "BLE HID", "I2C", "CAN Bus" };
pub const mach_type_names = [_][]const u8{ "Mill", "Router", "Lathe", "Plasma", "Laser", "EDM", "Drill/Tap", "Other" };
pub const baud_labels = [_][]const u8{ "9600", "19200", "38400", "57600", "115200", "230400", "460800" };
pub const profile_slots: usize = 4;
pub const profile_blob_max: usize = 220;
pub const profile_name_max: usize = 24;

pub const CncPrefs = struct {
    proto: u8 = 0,
    /// Selected transport 0..7 (kept while Off).
    conn: u8 = 4,
    /// LVGL `cnc_conn == 255` stand-in.
    transport_off: bool = false,
    session_up: bool = false,
    /// 0=disconnected 1=starting 2=connecting 3=connected (host stub).
    session_phase: u8 = 0,
    /// After `startConnect`, keep phase=2 until driver reports or this hits 0 (~frames).
    connect_hold_frames: u8 = 0,
    autocon: bool = true,
    prof: u8 = 0,
    masso_ip: [16]u8 = padStr("192.168.1.100", 16),
    masso_sn: [16]u8 = .{0} ** 16,
    masso_tx: u16 = 11000,
    masso_rx: u16 = 65535,
    ws_host: [16]u8 = padStr("192.168.1.100", 16),
    ws_port: u16 = 81,
    ws_path: [16]u8 = padStr("/", 16),
    ws_tls: bool = false,
    tn_host: [16]u8 = padStr("192.168.1.100", 16),
    tn_port: u16 = 23,
    ser_baud_idx: u8 = 4,
    r4_baud_idx: u8 = 4,
    ble_name: [16]u8 = padStr("(not set)", 16),
    i2c_addr: u8 = 0x50,
    i2c_spd: u8 = 1,
    can_brate: u8 = 2,
    can_nid: u8 = 1,
    /// Empty until peer select / NVS load — never stub MAC (savePrefs used to re-poison NVS).
    espnow_mac: [18]u8 = .{0} ** 18,
    espnow_enc: bool = false,
    proto_ref_exp: bool = false,
    /// LVGL `cnc_p0`–`cnc_p3` packed blobs (`name|proto|conn|…`).
    profiles: [profile_slots][profile_blob_max]u8 = .{.{0} ** profile_blob_max} ** profile_slots,

    pub fn protoLabel(self: CncPrefs) []const u8 {
        return proto_names[@min(self.proto, proto_names.len - 1)];
    }
    pub fn connLabel(self: CncPrefs) []const u8 {
        if (self.transport_off) return "Off";
        return transport_names[@min(self.conn, transport_names.len - 1)];
    }
    pub fn transportOn(self: CncPrefs) bool {
        return !self.transport_off and self.conn < transport_names.len;
    }
    pub fn supportsDump(self: CncPrefs) bool {
        // GrblHAL / Grbl / FluidNC — `$$` browser (LinuxCNC uses INI pull on Machine tab).
        return self.proto <= 2;
    }
    pub fn preferredTransport(proto: u8) u8 {
        return switch (proto) {
            3, 4 => 2, // Telnet
            2, 5 => 1, // WebSocket
            else => 4, // RS-485
        };
    }
    pub fn applyPreferredTransport(self: *CncPrefs) void {
        self.conn = preferredTransport(self.proto);
        self.transport_off = false;
        if (self.proto == 3) self.tn_port = 5007;
        if (self.proto == 4) self.tn_port = 7878;
    }
    pub fn sessionBusy(self: CncPrefs) bool {
        return self.session_up or self.session_phase == 1 or self.session_phase == 2;
    }
    pub fn sessionText(self: CncPrefs) []const u8 {
        if (!self.transportOn()) return "Transport off";
        return switch (self.session_phase) {
            1 => "Starting...",
            2 => "Connecting...",
            3 => "Connected",
            else => "Disconnected",
        };
    }
    pub fn sessionKind(self: CncPrefs) enum { ok, warn, err, dim } {
        if (!self.transportOn()) return .dim;
        return switch (self.session_phase) {
            1, 2 => .warn,
            3 => .ok,
            else => .err,
        };
    }
    pub fn massoIpSlice(self: *const CncPrefs) []const u8 {
        return cstrSlice(&self.masso_ip);
    }
    pub fn massoSnSlice(self: *const CncPrefs) []const u8 {
        const s = cstrSlice(&self.masso_sn);
        return if (s.len == 0) "(none)" else s;
    }
    pub fn wsHostSlice(self: *const CncPrefs) []const u8 {
        return cstrSlice(&self.ws_host);
    }
    pub fn wsPathSlice(self: *const CncPrefs) []const u8 {
        const s = cstrSlice(&self.ws_path);
        return if (s.len == 0) "/" else s;
    }
    pub fn tnHostSlice(self: *const CncPrefs) []const u8 {
        return cstrSlice(&self.tn_host);
    }
    pub fn bleNameSlice(self: *const CncPrefs) []const u8 {
        return cstrSlice(&self.ble_name);
    }
    pub fn setHostField(dst: *[16]u8, s: []const u8) void {
        @memset(dst, 0);
        const n = @min(s.len, dst.len);
        @memcpy(dst[0..n], s[0..n]);
    }
    pub fn espnowMacSlice(self: *const CncPrefs) []const u8 {
        return cstrSlice(&self.espnow_mac);
    }
    pub fn baudLabel(idx: u8) []const u8 {
        return baud_labels[@min(idx, baud_labels.len - 1)];
    }
    pub fn startConnect(self: *CncPrefs) void {
        if (self.transport_off) {
            self.transport_off = false;
            if (self.conn >= transport_names.len) self.conn = 4;
        }
        self.session_phase = 2;
        self.session_up = false;
        // ~1.5 s @ 60 Hz — covers transport reinit before mirror sees link-up.
        self.connect_hold_frames = 90;
    }
    pub fn disconnect(self: *CncPrefs) void {
        self.transport_off = true;
        self.session_phase = 0;
        self.session_up = false;
        self.connect_hold_frames = 0;
    }
    pub fn tickConnectHold(self: *CncPrefs) void {
        if (self.connect_hold_frames > 0) self.connect_hold_frames -= 1;
    }
    pub fn tickTelemetry(self: *CncPrefs) void {
        if (self.session_phase == 1) {
            self.session_phase = 2;
        } else if (self.session_phase == 2) {
            self.session_phase = 3;
            self.session_up = true;
        }
    }
    pub fn profileBlob(self: *const CncPrefs, slot: u8) []const u8 {
        if (slot >= profile_slots) return "";
        return cstrSlice(&self.profiles[slot]);
    }
    pub fn profileOccupied(self: *const CncPrefs, slot: u8) bool {
        return self.profileBlob(slot).len > 0;
    }
    /// First field of blob, or empty if unused.
    pub fn profileName(self: *const CncPrefs, slot: u8) []const u8 {
        const blob = self.profileBlob(slot);
        if (blob.len == 0) return "";
        if (std.mem.indexOfScalar(u8, blob, '|')) |bar| return blob[0..bar];
        return blob;
    }
    pub fn profileDetail(self: *const CncPrefs, buf: []u8) []const u8 {
        const slot = @min(self.prof, profile_slots - 1);
        const name = self.profileName(@intCast(slot));
        if (name.len > 0) {
            return std.fmt.bufPrint(buf, "Active: {s}", .{name}) catch "Active";
        }
        return std.fmt.bufPrint(buf, "Slot {d}", .{slot + 1}) catch "Slot";
    }
    pub fn saveProfileSlot(self: *CncPrefs, slot: u8, name: []const u8) void {
        if (slot >= profile_slots) return;
        var clean: [profile_name_max]u8 = undefined;
        const nm = sanitizeProfileName(&clean, name);
        var blob: [profile_blob_max]u8 = undefined;
        const packed_len = packProfileLive(&blob, nm, self) catch return;
        @memset(&self.profiles[slot], 0);
        @memcpy(self.profiles[slot][0..packed_len], blob[0..packed_len]);
        self.prof = slot;
    }
    pub fn activateProfile(self: *CncPrefs, slot: u8) bool {
        if (slot >= profile_slots) return false;
        const blob = self.profileBlob(slot);
        if (blob.len == 0) return false;
        applyProfileBlob(self, blob);
        self.prof = slot;
        self.startConnect();
        return true;
    }
    pub fn renameProfile(self: *CncPrefs, slot: u8, name: []const u8) void {
        if (slot >= profile_slots) return;
        const blob = self.profileBlob(slot);
        if (blob.len == 0) {
            self.saveProfileSlot(slot, name);
            return;
        }
        var clean: [profile_name_max]u8 = undefined;
        const nm = sanitizeProfileName(&clean, name);
        const rest = if (std.mem.indexOfScalar(u8, blob, '|')) |bar| blob[bar..] else "|0|4";
        var out: [profile_blob_max]u8 = undefined;
        const n = std.fmt.bufPrint(&out, "{s}{s}", .{ nm, rest }) catch return;
        @memset(&self.profiles[slot], 0);
        @memcpy(self.profiles[slot][0..n.len], n);
    }
    pub fn resetDefaults(self: *CncPrefs) void {
        // LVGL: conn → RS-485 (4), r4_baud → 4. Keep saved profiles (connection reset only).
        const keep = self.profiles;
        const keep_prof = self.prof;
        self.* = .{};
        self.r4_baud_idx = 4;
        self.conn = 4;
        self.transport_off = false;
        self.profiles = keep;
        self.prof = keep_prof;
    }
    pub fn clearProfiles(self: *CncPrefs) void {
        self.profiles = .{.{0} ** profile_blob_max} ** profile_slots;
        self.prof = 0;
    }
};

pub const AudioPrefs = struct {
    vol: u8 = 70,
    /// Quiet Mode — UI/codec treat volume as 0 while latch is on.
    silent: bool = false,
    tsound: bool = true,
    tone_prof: u8 = 0,
    snd_up: bool = true,
    snd_dn: bool = true,
    mic_gain: u8 = 2,
    hw_ref_exp: bool = false,
    /// Host stubs — LVGL codec ready gates.
    out_ready: bool = true,
    in_ready: bool = true,
    hp_inserted: bool = false,

    pub const tone_labels = [_][]const u8{ "Standard", "Soft", "Crisp", "Industrial" };
    pub const gain_labels = [_][]const u8{ "Off", "Low", "Med", "High", "Max" };

    pub fn toneLabel(self: AudioPrefs) []const u8 {
        return tone_labels[@min(self.tone_prof, tone_labels.len - 1)];
    }
    pub fn gainLabel(self: AudioPrefs) []const u8 {
        return gain_labels[@min(self.mic_gain, gain_labels.len - 1)];
    }
    pub fn resetDefaults(self: *AudioPrefs) void {
        self.* = .{};
    }
};

/// ZIGBEE_CAP_* bits (zb_link_proto.h) — QS Exposes detail.
pub const ZbCap = struct {
    pub const onoff: u8 = 0x01;
    pub const level: u8 = 0x02;
    pub const cover: u8 = 0x04;
    pub const thermostat: u8 = 0x08;
    pub const sensor: u8 = 0x10;
    pub const power: u8 = 0x20;
    pub const meter: u8 = 0x40;
    pub const color: u8 = 0x80;
};

pub const ZbDevSnap = struct {
    id: [17]u8 = .{0} ** 17,
    model: [17]u8 = .{0} ** 17,
    /// Devdb description snippet (purpose keywords); empty when unknown.
    desc: [40]u8 = .{0} ** 40,
    caps: u8 = 0,
    level: u8 = 0,
    rssi: i8 = 0,
    lqi: u8 = 0,
    short_addr: u16 = 0,
    volt_raw: u16 = 0,
    curr_raw: u16 = 0,
    power_raw: i16 = 0,
    energy_raw: u32 = 0,
    sensors_seen: u8 = 0,
    zone_status: u16 = 0,
    zone_seen: bool = false,

    pub fn idSlice(self: *const ZbDevSnap) []const u8 {
        return cstrSlice(&self.id);
    }
    pub fn modelSlice(self: *const ZbDevSnap) []const u8 {
        return cstrSlice(&self.model);
    }
    pub fn descSlice(self: *const ZbDevSnap) []const u8 {
        return cstrSlice(&self.desc);
    }
};

pub const WirelessPrefs = struct {
    /// 0=hub 1=wifi 2=bt 3=espnow 4=zigbee 5=thread 6=wifi_saved 7=wifi_adv
    page: u8 = 0,
    wifi: bool = false,
    bt: bool = false,
    espnow: bool = false,
    zigbee: bool = false,
    thread: bool = false,
    /// Airplane — all radios off while latched.
    airplane: bool = false,
    ant_ext: bool = false,
    wf_auto: bool = true,
    wf_arecon: bool = true,
    wf_dhcp: bool = true,
    en_chan: u8 = 1, // 1..13
    en_enc: bool = false,
    en_rate: u8 = 3,
    hub_ref_exp: bool = false,
    bt_adv_exp: bool = false,
    zb_adv_exp: bool = false,
    th_adv_exp: bool = false,
    en_adv_exp: bool = false,
    /// Live stubs (host).
    wifi_conn: bool = false,
    ssid: [24]u8 = .{0} ** 24,
    /// Draft password for Wi-Fi connect modal (host stub; not persisted).
    draft_pass: [32]u8 = .{0} ** 32,
    zb_install: [32]u8 = .{0} ** 32,
    th_node: [32]u8 = .{0} ** 32,
    bt_passkey: [8]u8 = .{0} ** 8,
    /// Pending BT discovery index while passkey modal open (0xff = none).
    bt_pair_idx: u8 = 0xff,
    ip: [16]u8 = padStr("--", 16),
    scan_phase: u8 = 0, // 0 idle 1 scanning 2 done
    scan_n: u8 = 0,
    /// Device: Wi-Fi scan owned by C6 poll — skip host 1 Hz stub completion.
    wifi_scan_hw: bool = false,
    has_saved: bool = false,
    saved_ssid: [24]u8 = .{0} ** 24,
    bt_conn: bool = false,
    bt_name: [24]u8 = .{0} ** 24,
    bt_scan_phase: u8 = 0,
    bt_scan_n: u8 = 0,
    en_scan_phase: u8 = 0,
    en_peer_n: u8 = 0,
    en_bridge: [24]u8 = padStr("None", 24),
    /// Bit i = stub_peers[i] saved; en_active 255 = none.
    en_saved_mask: u8 = 0,
    en_active: u8 = 255,
    en_rx: u32 = 0,
    en_tx: u32 = 0,
    zb_joined: bool = false,
    th_attached: bool = false,
    zb_scan_phase: u8 = 0,
    zb_scan_n: u8 = 0,
    th_scan_phase: u8 = 0,
    th_scan_n: u8 = 0,
    zb_dev_n: u8 = 0,
    zb_dev_on: [8]bool = .{true} ** 8,
    th_dev_n: u8 = 0,
    th_dev_on: [2]bool = .{ true, false },
    zb_energy_phase: u8 = 0, // 0 idle 1 scanning 2 done
    /// Device scan results (Wi-Fi); when live_ap_n>0 paint uses these over stubs.
    live_ap: [12][33]u8 = .{.{0} ** 33} ** 12,
    live_ap_n: u8 = 0,
    /// BLE discovery (name + rssi).
    live_bt: [12][24]u8 = .{.{0} ** 24} ** 12,
    live_bt_rssi: [12]i8 = .{0} ** 12,
    live_bt_n: u8 = 0,
    bt_scan_hw: bool = false,
    /// ESP-NOW scan + saved peer MACs.
    live_en: [8][18]u8 = .{.{0} ** 18} ** 8,
    live_en_n: u8 = 0,
    en_scan_hw: bool = false,
    live_en_saved: [8][18]u8 = .{.{0} ** 18} ** 8,
    live_en_saved_n: u8 = 0,
    /// Zigbee / Thread saved device names (on-state mirrored from C).
    live_zb: [8][24]u8 = .{.{0} ** 24} ** 8,
    live_zb_n: u8 = 0,
    /// Live Zigbee exposes (caps / link / sensors) — QS long-press detail.
    live_zb_snap: [8]ZbDevSnap = [_]ZbDevSnap{.{}} ** 8,
    zb_scan_hw: bool = false,
    live_th: [8][24]u8 = .{.{0} ** 24} ** 8,
    live_th_n: u8 = 0,
    th_scan_hw: bool = false,
    zb_energy_hw: bool = false,
    zb_energy_detail: [40]u8 = .{0} ** 40,
    /// Device: live NanoH2 status / network lines from wireless shim.
    zb_status: [48]u8 = .{0} ** 48,
    zb_network: [40]u8 = .{0} ** 40,

    pub const rate_labels = [_][]const u8{ "1M", "2M", "5.5M", "11M" };
    pub const chan_labels = [_][]const u8{ "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13" };
    pub const stub_aps = [_][]const u8{ "DemoNet", "ShopFloor", "GuestCNC" };
    pub const stub_rssi = [_]i8{ -42, -61, -78 };
    pub const stub_auth = [_][]const u8{ "WPA2", "WPA2", "Open" };
    pub const stub_bt = [_][]const u8{ "Pendant-BLE", "M5-Keyboard" };
    pub const stub_peers = [_][]const u8{ "AA:BB:CC:DD:EE:01", "AA:BB:CC:DD:EE:02" };
    pub const stub_zb = [_][]const u8{ "Shop switch", "Door contact" };
    pub const stub_th = [_][]const u8{ "Matter plug" };

    pub fn apLabel(self: *const WirelessPrefs, i: usize) []const u8 {
        if (i < self.live_ap_n) return cstrSlice(&self.live_ap[i]);
        return "--";
    }
    pub fn btLabel(self: *const WirelessPrefs, i: usize) []const u8 {
        if (i < self.live_bt_n) return cstrSlice(&self.live_bt[i]);
        return "--";
    }
    pub fn btRssi(self: *const WirelessPrefs, i: usize) i8 {
        if (i < self.live_bt_n) return self.live_bt_rssi[i];
        return 0;
    }
    pub fn enPeerLabel(self: *const WirelessPrefs, i: usize) []const u8 {
        if (i < self.live_en_n) return cstrSlice(&self.live_en[i]);
        return "--";
    }
    pub fn enSavedLabel(self: *const WirelessPrefs, i: usize) []const u8 {
        if (i < self.live_en_saved_n) return cstrSlice(&self.live_en_saved[i]);
        return "--";
    }
    pub fn zbDevLabel(self: *const WirelessPrefs, i: usize) []const u8 {
        if (i < self.live_zb_n) return cstrSlice(&self.live_zb[i]);
        return "--";
    }
    pub fn zbSnap(self: *const WirelessPrefs, i: usize) ZbDevSnap {
        if (i < self.live_zb_n) return self.live_zb_snap[i];
        return .{};
    }
    pub fn softFillZbSnaps(self: *WirelessPrefs) void {
        var i: usize = 0;
        while (i < self.live_zb_n) : (i += 1) {
            var s: ZbDevSnap = .{ .caps = ZbCap.onoff, .short_addr = @intCast(0x1000 + i), .lqi = 180, .rssi = -55 };
            if (i == 0) {
                setDraftField(&s.desc, "smart switch wall module");
            } else if (i == 1) {
                s.caps = ZbCap.sensor;
                s.zone_seen = true;
                s.zone_status = 0;
                setDraftField(&s.desc, "door window contact sensor");
            }
            self.live_zb_snap[i] = s;
        }
    }
    pub fn thDevLabel(self: *const WirelessPrefs, i: usize) []const u8 {
        if (i < self.live_th_n) return cstrSlice(&self.live_th[i]);
        return "--";
    }
    pub fn zbStatusSlice(self: *const WirelessPrefs) []const u8 {
        const s = cstrSlice(&self.zb_status);
        if (s.len > 0) return s;
        if (!self.zigbee) return "Off";
        if (self.zb_joined) return "Joined (hub)";
        return "On (not joined)";
    }
    pub fn zbNetworkSlice(self: *const WirelessPrefs) []const u8 {
        const s = cstrSlice(&self.zb_network);
        if (s.len > 0) return s;
        return if (self.zb_joined) "Joined (hub)" else "None";
    }
    pub fn ssidSlice(self: *const WirelessPrefs) []const u8 {
        return cstrSlice(&self.ssid);
    }
    pub fn draftPassSlice(self: *const WirelessPrefs) []const u8 {
        return cstrSlice(&self.draft_pass);
    }
    pub fn zbInstallSlice(self: *const WirelessPrefs) []const u8 {
        return cstrSlice(&self.zb_install);
    }
    pub fn thNodeSlice(self: *const WirelessPrefs) []const u8 {
        return cstrSlice(&self.th_node);
    }
    pub fn btPasskeySlice(self: *const WirelessPrefs) []const u8 {
        return cstrSlice(&self.bt_passkey);
    }
    pub fn setDraftField(dst: anytype, s: []const u8) void {
        @memset(dst, 0);
        const n = @min(s.len, dst.len);
        @memcpy(dst[0..n], s[0..n]);
    }
    pub fn beginWifiConnect(self: *WirelessPrefs, idx: u8) void {
        const lab = self.apLabel(idx);
        @memset(&self.ssid, 0);
        const n = @min(lab.len, self.ssid.len);
        @memcpy(self.ssid[0..n], lab[0..n]);
        @memset(&self.draft_pass, 0);
    }
    pub fn finishWifiConnect(self: *WirelessPrefs) void {
        _ = self.draft_pass; // host stub ignores password
        const s = self.ssidSlice();
        if (s.len == 0) return;
        @memset(&self.ip, 0);
        const ip = "192.168.1.50";
        @memcpy(self.ip[0..ip.len], ip);
        self.wifi_conn = true;
        self.wifi = true;
        self.has_saved = true;
        @memset(&self.saved_ssid, 0);
        @memcpy(self.saved_ssid[0..s.len], s);
    }
    pub fn addZbFromInstall(self: *WirelessPrefs) void {
        if (self.zbInstallSlice().len == 0) return;
        if (self.zb_dev_n < self.zb_dev_on.len) {
            self.zb_dev_on[self.zb_dev_n] = true;
            self.zb_dev_n += 1;
        }
        @memset(&self.zb_install, 0);
    }
    pub fn addThFromNode(self: *WirelessPrefs) void {
        if (self.thNodeSlice().len == 0) return;
        if (self.th_dev_n < 1) {
            self.th_dev_on[0] = true;
            self.th_dev_n = 1;
        }
        @memset(&self.th_node, 0);
    }
    pub fn ipSlice(self: *const WirelessPrefs) []const u8 {
        return cstrSlice(&self.ip);
    }
    pub fn savedSsidSlice(self: *const WirelessPrefs) []const u8 {
        return cstrSlice(&self.saved_ssid);
    }
    pub fn bridgeSlice(self: *const WirelessPrefs) []const u8 {
        return cstrSlice(&self.en_bridge);
    }
    pub fn btNameSlice(self: *const WirelessPrefs) []const u8 {
        const s = cstrSlice(&self.bt_name);
        return if (s.len > 0) s else "None";
    }
    pub fn pairedText(self: *const WirelessPrefs) []const u8 {
        return if (self.bt_conn) self.btNameSlice() else "None";
    }
    pub fn radioLabel(on: bool) []const u8 {
        return if (on) "On" else "Off";
    }
    pub fn hubOn(on: bool) []const u8 {
        return if (on) "On" else "";
    }
    pub fn wifiRadioText(self: WirelessPrefs) []const u8 {
        if (!self.wifi) return "Off";
        if (self.wifi_conn) return "Connected";
        return "On (idle)";
    }
    pub fn scanText(self: WirelessPrefs) []const u8 {
        return switch (self.scan_phase) {
            1 => "Scanning...",
            2 => if (self.scan_n == 0) "No networks" else "Done",
            else => "Idle",
        };
    }
    pub fn energyText(self: *const WirelessPrefs) []const u8 {
        if (self.zb_energy_hw and self.zb_energy_phase == 1) return "Scanning...";
        if (self.zb_energy_detail[0] != 0) return cstrSlice(&self.zb_energy_detail);
        return switch (self.zb_energy_phase) {
            1 => "Scanning...",
            2 => "Ch15 quietest (stub)",
            else => "Idle",
        };
    }
    pub fn chanLabel(self: WirelessPrefs) []const u8 {
        const i = if (self.en_chan == 0) 0 else self.en_chan - 1;
        return chan_labels[@min(i, chan_labels.len - 1)];
    }
    pub fn rateLabel(self: WirelessPrefs) []const u8 {
        return rate_labels[@min(self.en_rate, rate_labels.len - 1)];
    }
    pub fn peerSaved(self: WirelessPrefs, idx: u8) bool {
        if (self.live_en_saved_n > 0) return idx < self.live_en_saved_n;
        return (self.en_saved_mask & (@as(u8, 1) << @intCast(idx))) != 0;
    }
    pub fn startWifiScan(self: *WirelessPrefs) void {
        if (!self.wifi) return;
        self.scan_phase = 1;
        self.scan_n = 0;
        self.wifi_scan_hw = false;
        self.live_ap_n = 0;
    }
    pub fn startBtScan(self: *WirelessPrefs) void {
        if (!self.bt) return;
        self.bt_scan_phase = 1;
        self.bt_scan_n = 0;
        self.bt_scan_hw = false;
        self.live_bt_n = 0;
    }
    pub fn startEnScan(self: *WirelessPrefs) void {
        if (!self.espnow) return;
        self.en_scan_phase = 1;
        self.en_peer_n = 0;
        self.en_scan_hw = false;
        self.live_en_n = 0;
    }
    pub fn startZbScan(self: *WirelessPrefs) void {
        if (!self.zigbee) return;
        self.zb_scan_phase = 1;
        self.zb_scan_n = 0;
        self.zb_scan_hw = false;
    }
    pub fn startThScan(self: *WirelessPrefs) void {
        if (!self.thread) return;
        self.th_scan_phase = 1;
        self.th_scan_n = 0;
        self.th_scan_hw = false;
    }
    pub fn startEnergyScan(self: *WirelessPrefs) void {
        if (!self.zigbee) return;
        self.zb_energy_phase = 1;
        self.zb_energy_hw = false;
        @memset(&self.zb_energy_detail, 0);
    }
    pub fn connectAp(self: *WirelessPrefs, idx: u8) void {
        const lab = self.apLabel(idx);
        if (lab.len == 0 or std.mem.eql(u8, lab, "--")) return;
        @memset(&self.ssid, 0);
        const n = @min(lab.len, self.ssid.len);
        @memcpy(self.ssid[0..n], lab[0..n]);
        @memset(&self.ip, 0);
        const ip = "192.168.1.50";
        @memcpy(self.ip[0..ip.len], ip);
        self.wifi_conn = true;
        self.wifi = true;
        self.has_saved = true;
        @memset(&self.saved_ssid, 0);
        @memcpy(self.saved_ssid[0..n], lab[0..n]);
    }
    pub fn disconnectWifi(self: *WirelessPrefs) void {
        self.wifi_conn = false;
        @memset(&self.ssid, 0);
        @memset(&self.ip, 0);
        const dash = "--";
        @memcpy(self.ip[0..dash.len], dash);
    }
    pub fn forgetSaved(self: *WirelessPrefs) void {
        self.disconnectWifi();
        self.has_saved = false;
        @memset(&self.saved_ssid, 0);
    }
    pub fn connectSaved(self: *WirelessPrefs) void {
        if (!self.has_saved) return;
        self.wifi = true;
        @memset(&self.ssid, 0);
        const s = self.savedSsidSlice();
        @memcpy(self.ssid[0..s.len], s);
        @memset(&self.ip, 0);
        const ip = "192.168.1.50";
        @memcpy(self.ip[0..ip.len], ip);
        self.wifi_conn = true;
    }
    pub fn beginBtPair(self: *WirelessPrefs, idx: u8) void {
        const lab = self.btLabel(idx);
        self.bt_pair_idx = idx;
        @memset(&self.bt_passkey, 0);
        @memset(&self.bt_name, 0);
        const n = @min(lab.len, self.bt_name.len);
        @memcpy(self.bt_name[0..n], lab[0..n]);
    }
    pub fn connectBt(self: *WirelessPrefs, idx: u8) void {
        const lab = self.btLabel(idx);
        @memset(&self.bt_name, 0);
        const n = @min(lab.len, self.bt_name.len);
        @memcpy(self.bt_name[0..n], lab[0..n]);
        self.bt_conn = true;
        self.bt = true;
    }
    pub fn clearBtPaired(self: *WirelessPrefs) void {
        self.bt_conn = false;
        @memset(&self.bt_name, 0);
    }
    pub fn setBridgePeer(self: *WirelessPrefs, idx: u8) void {
        const lab = self.enPeerLabel(idx);
        if (lab.len == 0 or std.mem.eql(u8, lab, "--")) return;
        @memset(&self.en_bridge, 0);
        const n = @min(lab.len, self.en_bridge.len);
        @memcpy(self.en_bridge[0..n], lab[0..n]);
        const i: u8 = @intCast(@min(idx, 7));
        self.en_saved_mask |= @as(u8, 1) << @intCast(i);
        self.en_active = i;
        // Mirror into saved list for paint.
        if (self.live_en_saved_n < self.live_en_saved.len) {
            const si = self.live_en_saved_n;
            @memset(&self.live_en_saved[si], 0);
            @memcpy(self.live_en_saved[si][0..n], lab[0..n]);
            self.live_en_saved_n += 1;
        }
    }
    pub fn removeSavedPeer(self: *WirelessPrefs, idx: u8) void {
        const i = @min(idx, stub_peers.len - 1);
        self.en_saved_mask &= ~(@as(u8, 1) << @intCast(i));
        if (self.en_active == i) {
            self.en_active = 255;
            @memset(&self.en_bridge, 0);
            const none = "None";
            @memcpy(self.en_bridge[0..none.len], none);
        }
    }
    pub fn clearSavedPeers(self: *WirelessPrefs) void {
        self.en_saved_mask = 0;
        self.en_active = 255;
        self.en_peer_n = 0;
        self.en_scan_phase = 0;
        @memset(&self.en_bridge, 0);
        const none = "None";
        @memcpy(self.en_bridge[0..none.len], none);
    }
    pub fn commitMac(self: *WirelessPrefs, mac: []const u8) void {
        var clean: [24]u8 = .{0} ** 24;
        var j: usize = 0;
        for (mac) |c| {
            if (j >= clean.len) break;
            const up = if (c >= 'a' and c <= 'f') c - 32 else c;
            if ((up >= '0' and up <= '9') or (up >= 'A' and up <= 'F') or up == ':') {
                clean[j] = up;
                j += 1;
            }
        }
        if (j < 11) return; // need something MAC-like
        @memset(&self.en_bridge, 0);
        @memcpy(self.en_bridge[0..j], clean[0..j]);
        self.en_saved_mask |= 1;
        self.en_active = 0;
        self.espnow = true;
    }
    pub fn joinZigbee(self: *WirelessPrefs) void {
        self.zigbee = true;
        self.zb_joined = true;
        if (self.live_zb_n == 0) softFillNames(&self.live_zb, &self.live_zb_n, &stub_zb);
        self.zb_dev_n = self.live_zb_n;
        self.zb_dev_on = .{true} ** 8;
        self.softFillZbSnaps();
    }
    pub fn leaveZigbee(self: *WirelessPrefs) void {
        self.zb_joined = false;
        self.zb_dev_n = 0;
        self.live_zb_n = 0;
        self.zb_scan_phase = 0;
    }
    pub fn attachThread(self: *WirelessPrefs) void {
        self.thread = true;
        self.th_attached = true;
        if (self.live_th_n == 0) softFillNames(&self.live_th, &self.live_th_n, &stub_th);
        self.th_dev_n = self.live_th_n;
        self.th_dev_on[0] = true;
    }
    pub fn detachThread(self: *WirelessPrefs) void {
        self.th_attached = false;
        self.th_dev_n = 0;
        self.th_scan_phase = 0;
    }
    /// 1 Hz host soft telemetry — never called on device (`now_us_sink` path).
    pub fn tickTelemetry(self: *WirelessPrefs) void {
        if (self.scan_phase == 1 and !self.wifi_scan_hw) {
            self.scan_phase = 2;
            softFillNames(&self.live_ap, &self.live_ap_n, &stub_aps);
            self.scan_n = self.live_ap_n;
        }
        if (self.bt_scan_phase == 1 and !self.bt_scan_hw) {
            self.bt_scan_phase = 2;
            softFillNames(&self.live_bt, &self.live_bt_n, &stub_bt);
            self.bt_scan_n = self.live_bt_n;
            if (self.live_bt_n > 0) self.live_bt_rssi[0] = -55;
            if (self.live_bt_n > 1) self.live_bt_rssi[1] = -62;
        }
        if (self.en_scan_phase == 1 and !self.en_scan_hw) {
            self.en_scan_phase = 2;
            softFillNames(&self.live_en, &self.live_en_n, &stub_peers);
            self.en_peer_n = self.live_en_n;
        }
        if (self.zb_scan_phase == 1 and !self.zb_scan_hw) {
            self.zb_scan_phase = 2;
            softFillNames(&self.live_zb, &self.live_zb_n, &stub_zb);
            self.zb_scan_n = self.live_zb_n;
            self.softFillZbSnaps();
        }
        if (self.th_scan_phase == 1 and !self.th_scan_hw) {
            self.th_scan_phase = 2;
            softFillNames(&self.live_th, &self.live_th_n, &stub_th);
            self.th_scan_n = self.live_th_n;
        }
        if (self.zb_energy_phase == 1 and !self.zb_energy_hw) {
            self.zb_energy_phase = 2;
        }
        if (self.espnow and self.live_en_saved_n == 0) {
            self.en_rx +%= 3;
            self.en_tx +%= 1;
        }
    }
    pub fn resetDefaults(self: *WirelessPrefs) void {
        self.* = .{};
    }
};

pub const PowerPrefs = struct {
    bat_pct: u8 = 0,
    /// 0=Discharging 1=Charging 2=Full 3=No battery
    charge_state: u8 = 0,
    bat_v: f32 = 0,
    bat_ma: f32 = 0,
    bat_w: f32 = 0,
    bat_rate_ma: f32 = 0,
    /// Minutes; <0 → "--"
    bat_eta_min: i32 = -1,
    cpu_temp_c: f32 = 0,
    ina_ok: bool = false,
    ext5v: bool = true,
    usb5v: bool = true,
    dim_idx: u8 = 0,
    scr_idx: u8 = 0,
    pwr_mode: u8 = 0,
    dsto_idx: u8 = 2,
    wake_touch: bool = true,
    wake_usb: bool = false,
    wake_timer: bool = false,
    wtmin_idx: u8 = 0,
    gate_wifi: bool = true,
    gate_ext: bool = true,
    gate_usb: bool = false,
    bat_type: u8 = 0,
    bat_warn_idx: u8 = 3,
    chg_en: bool = true,
    bat_adapt: bool = false,
    qc: bool = true,
    batt_ref_exp: bool = false,

    pub const dim_labels = [_][]const u8{ "Never", "10 sec", "30 sec", "1 min", "2 min", "5 min" };
    pub const scr_labels = [_][]const u8{ "Never", "15 sec", "30 sec", "1 min", "2 min", "5 min", "10 min" };
    pub const dsto_labels = [_][]const u8{ "30 sec", "1 min", "2 min", "5 min", "10 min" };
    pub const wtmin_labels = [_][]const u8{ "Disabled", "5 min", "10 min", "15 min", "30 min", "1 hr", "2 hr", "4 hr", "8 hr" };
    pub const bat_type_labels = [_][]const u8{ "F550 (2200 mAh)", "F550 3500 mAh", "F750", "F950", "F970" };
    pub const warn_labels = [_][]const u8{ "Off", "5%", "10%", "15%", "20%", "25%", "30%" };

    pub fn deepSleep(self: PowerPrefs) bool {
        return self.pwr_mode == 1;
    }
    pub fn dimLabel(self: PowerPrefs) []const u8 {
        return dim_labels[@min(self.dim_idx, dim_labels.len - 1)];
    }
    pub fn scrLabel(self: PowerPrefs) []const u8 {
        return scr_labels[@min(self.scr_idx, scr_labels.len - 1)];
    }
    /// LVGL `k_dim_vals` seconds.
    pub fn dimSec(self: PowerPrefs) u16 {
        const vals = [_]u16{ 0, 10, 30, 60, 120, 300 };
        return vals[@min(self.dim_idx, vals.len - 1)];
    }
    /// LVGL `k_scr_vals` seconds.
    pub fn scrSec(self: PowerPrefs) u16 {
        const vals = [_]u16{ 0, 15, 30, 60, 120, 300, 600 };
        return vals[@min(self.scr_idx, vals.len - 1)];
    }
    /// LVGL `k_ds_vals` deep-sleep timeout seconds.
    pub fn dstoSec(self: PowerPrefs) u16 {
        const vals = [_]u16{ 30, 60, 120, 300, 600 };
        return vals[@min(self.dsto_idx, vals.len - 1)];
    }
    /// LVGL `k_wtm_vals` wake-timer minutes.
    pub fn wtminMin(self: PowerPrefs) u16 {
        const vals = [_]u16{ 0, 5, 10, 15, 30, 60, 120, 240, 480 };
        return vals[@min(self.wtmin_idx, vals.len - 1)];
    }
    /// LVGL `k_warn_vals` battery warn %.
    pub fn batWarnPct(self: PowerPrefs) u8 {
        const vals = [_]u8{ 0, 5, 10, 15, 20, 25, 30 };
        return vals[@min(self.bat_warn_idx, vals.len - 1)];
    }
    /// `pwr_wake` bitfield: touch=0x01 timer=0x02 usb=0x04.
    pub fn wakeBits(self: PowerPrefs) u8 {
        var w: u8 = 0;
        if (self.wake_touch) w |= 0x01;
        if (self.wake_timer) w |= 0x02;
        if (self.wake_usb) w |= 0x04;
        return w;
    }
    pub fn setDimFromSec(self: *PowerPrefs, sec: u16) void {
        const vals = [_]u16{ 0, 10, 30, 60, 120, 300 };
        self.dim_idx = 0;
        for (vals, 0..) |v, i| {
            if (v == sec) self.dim_idx = @intCast(i);
        }
    }
    pub fn setScrFromSec(self: *PowerPrefs, sec: u16) void {
        const vals = [_]u16{ 0, 15, 30, 60, 120, 300, 600 };
        self.scr_idx = 0;
        for (vals, 0..) |v, i| {
            if (v == sec) self.scr_idx = @intCast(i);
        }
    }
    pub fn setDstoFromSec(self: *PowerPrefs, sec: u16) void {
        const vals = [_]u16{ 30, 60, 120, 300, 600 };
        self.dsto_idx = 2;
        for (vals, 0..) |v, i| {
            if (v == sec) self.dsto_idx = @intCast(i);
        }
    }
    pub fn setWtminFromMin(self: *PowerPrefs, min: u16) void {
        const vals = [_]u16{ 0, 5, 10, 15, 30, 60, 120, 240, 480 };
        self.wtmin_idx = 0;
        for (vals, 0..) |v, i| {
            if (v == min) self.wtmin_idx = @intCast(i);
        }
    }
    pub fn setWarnFromPct(self: *PowerPrefs, pct: u8) void {
        const vals = [_]u8{ 0, 5, 10, 15, 20, 25, 30 };
        self.bat_warn_idx = 3;
        for (vals, 0..) |v, i| {
            if (v == pct) self.bat_warn_idx = @intCast(i);
        }
    }
    pub fn setWakeFromBits(self: *PowerPrefs, bits: u8) void {
        self.wake_touch = (bits & 0x01) != 0;
        self.wake_timer = (bits & 0x02) != 0;
        self.wake_usb = (bits & 0x04) != 0;
    }
    pub fn dstoLabel(self: PowerPrefs) []const u8 {
        return dsto_labels[@min(self.dsto_idx, dsto_labels.len - 1)];
    }
    pub fn wtminLabel(self: PowerPrefs) []const u8 {
        return wtmin_labels[@min(self.wtmin_idx, wtmin_labels.len - 1)];
    }
    pub fn batTypeLabel(self: PowerPrefs) []const u8 {
        return bat_type_labels[@min(self.bat_type, bat_type_labels.len - 1)];
    }
    pub fn warnLabel(self: PowerPrefs) []const u8 {
        return warn_labels[@min(self.bat_warn_idx, warn_labels.len - 1)];
    }
    pub fn chargeStateLabel(self: PowerPrefs) []const u8 {
        return switch (self.charge_state) {
            1 => "Charging",
            2 => "Full",
            3 => "No battery",
            else => "Discharging",
        };
    }
    pub fn formatPct(self: PowerPrefs, buf: []u8) []const u8 {
        if (self.charge_state == 3) return "N/A";
        return std.fmt.bufPrint(buf, "{d}%", .{self.bat_pct}) catch "?%";
    }
    pub fn formatVolt(self: PowerPrefs, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{d:.2} V", .{self.bat_v}) catch "? V";
    }
    pub fn formatCurr(self: PowerPrefs, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{d:.0} mA", .{self.bat_ma}) catch "? mA";
    }
    pub fn formatPower(self: PowerPrefs, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{d:.2} W", .{self.bat_w}) catch "? W";
    }
    pub fn formatRate(self: PowerPrefs, buf: []u8) []const u8 {
        return switch (self.charge_state) {
            1 => std.fmt.bufPrint(buf, "{d:.0} mA (charging)", .{self.bat_rate_ma}) catch "--",
            0 => std.fmt.bufPrint(buf, "{d:.0} mA (discharging)", .{self.bat_rate_ma}) catch "--",
            else => "--",
        };
    }
    pub fn formatEta(self: PowerPrefs, buf: []u8) []const u8 {
        if (self.charge_state == 3 or self.bat_eta_min < 0) return "--";
        const mins: u32 = @intCast(self.bat_eta_min);
        const h = mins / 60;
        const m = mins % 60;
        const suffix: []const u8 = if (self.charge_state == 1) " to full" else " left";
        if (h > 0) return std.fmt.bufPrint(buf, "~{d}h {d}m{s}", .{ h, m, suffix }) catch "--";
        return std.fmt.bufPrint(buf, "~{d}m{s}", .{ m, suffix }) catch "--";
    }
    pub fn formatTemp(self: PowerPrefs, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{d:.1} C", .{self.cpu_temp_c}) catch "? C";
    }
    /// Soft INA226 stub — host only (device never calls; `now_us_sink` path).
    pub fn tickTelemetry(self: *PowerPrefs) void {
        if (!self.ina_ok) {
            self.ina_ok = true;
            self.bat_pct = 78;
            self.bat_v = 7.82;
            self.bat_ma = -320;
            self.bat_w = 2.50;
            self.bat_rate_ma = 320;
            self.bat_eta_min = 95;
            self.cpu_temp_c = 42.0;
            self.charge_state = 0;
        }
        self.cpu_temp_c += if (@mod(self.bat_pct, 2) == 0) @as(f32, 0.05) else -0.05;
        if (self.charge_state == 1) {
            self.bat_ma = 480;
            self.bat_rate_ma = 480;
            self.bat_w = self.bat_v * self.bat_ma / 1000.0;
            if (self.bat_pct < 100) self.bat_pct += 1;
            if (self.bat_pct >= 100) {
                self.bat_pct = 100;
                self.charge_state = 2;
            }
            self.bat_eta_min = @max(0, @as(i32, @as(i32, self.bat_pct) * -3 + 300));
            self.bat_v = @min(8.40, self.bat_v + 0.01);
        } else if (self.charge_state == 0) {
            self.bat_ma = -280 - @as(f32, @floatFromInt(self.bat_pct % 40));
            self.bat_rate_ma = -self.bat_ma;
            self.bat_w = self.bat_v * (-self.bat_ma) / 1000.0;
            if (self.bat_pct > 5) self.bat_pct -= 1;
            self.bat_eta_min = @max(0, @as(i32, self.bat_pct) * 4);
            self.bat_v = @max(6.10, self.bat_v - 0.005);
        } else if (self.charge_state == 2) {
            self.bat_ma = 0;
            self.bat_rate_ma = 0;
            self.bat_w = 0;
            self.bat_eta_min = -1;
        }
    }
    pub fn resetDefaults(self: *PowerPrefs) void {
        self.* = .{};
    }
};

pub const SecurityPrefs = struct {
    has_pin: bool = false,
    locked: bool = false,
    /// SHA-256 hex of PIN digits (device NVS `pin_hash` parity).
    pin_hash: [64]u8 = .{0} ** 64,
    pin_tmo_idx: u8 = 0,
    pin_boot: bool = false,
    pin_slp: bool = false,
    pin_idle: bool = false,
    /// 0=Never … 5=1 hour (LVGL idle modal; no 30 s).
    pin_idle_tmo_idx: u8 = 0,
    idle_exp: bool = false,

    pub const tmo_labels = [_][]const u8{ "Never", "1 min", "5 min", "15 min", "30 min", "1 hour", "On sleep" };
    pub const idle_tmo_labels = [_][]const u8{ "Never", "1 min", "5 min", "15 min", "30 min", "1 hour" };

    pub fn tmoLabel(self: SecurityPrefs) []const u8 {
        return tmo_labels[@min(self.pin_tmo_idx, tmo_labels.len - 1)];
    }
    pub fn idleTmoLabel(self: SecurityPrefs) []const u8 {
        return idle_tmo_labels[@min(self.pin_idle_tmo_idx, idle_tmo_labels.len - 1)];
    }
    /// LVGL idle modal seconds (Never / 1 / 5 / 15 / 30 / 60 min).
    pub fn idleTmoSec(self: SecurityPrefs) u16 {
        const vals = [_]u16{ 0, 60, 300, 900, 1800, 3600 };
        return vals[@min(self.pin_idle_tmo_idx, vals.len - 1)];
    }
    /// LVGL `k_pin_tmo_secs` (65535 = On sleep).
    pub fn tmoSec(self: SecurityPrefs) u16 {
        const vals = [_]u16{ 0, 60, 300, 900, 1800, 3600, 65535 };
        return vals[@min(self.pin_tmo_idx, vals.len - 1)];
    }
    pub fn setIdleTmoFromSec(self: *SecurityPrefs, sec: u16) void {
        const vals = [_]u16{ 0, 60, 300, 900, 1800, 3600 };
        self.pin_idle_tmo_idx = 0;
        for (vals, 0..) |v, i| {
            if (v == sec) self.pin_idle_tmo_idx = @intCast(i);
        }
        if (self.pin_idle_tmo_idx == 0) self.pin_idle = false;
    }
    pub fn setTmoFromSec(self: *SecurityPrefs, sec: u16) void {
        const vals = [_]u16{ 0, 60, 300, 900, 1800, 3600, 65535 };
        self.pin_tmo_idx = 0;
        for (vals, 0..) |v, i| {
            if (v == sec) self.pin_tmo_idx = @intCast(i);
        }
        if (self.pin_tmo_idx == 0) self.pin_slp = false;
        if (self.pin_tmo_idx == 6) self.pin_slp = true;
    }
    /// LVGL detail: "Off" or "On / N min".
    pub fn formatIdleDetail(self: SecurityPrefs, buf: []u8) []const u8 {
        if (!self.pin_idle or self.pin_idle_tmo_idx == 0) return "Off";
        return std.fmt.bufPrint(buf, "On / {s}", .{self.idleTmoLabel()}) catch "On";
    }
    pub fn pinDigitsValid(digits: []const u8) bool {
        if (digits.len < 4 or digits.len > 8) return false;
        for (digits) |c| {
            if (c < '0' or c > '9') return false;
        }
        return true;
    }
    fn hashPinHex(digits: []const u8, out: *[64]u8) void {
        var dig: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(digits, &dig, .{});
        const hex = "0123456789abcdef";
        for (dig, 0..) |b, i| {
            out[i * 2] = hex[b >> 4];
            out[i * 2 + 1] = hex[b & 0xf];
        }
    }
    pub fn setPin(self: *SecurityPrefs, digits: []const u8) bool {
        if (!pinDigitsValid(digits)) return false;
        hashPinHex(digits, &self.pin_hash);
        self.has_pin = true;
        return true;
    }
    pub fn verifyPin(self: *const SecurityPrefs, digits: []const u8) bool {
        if (!self.has_pin or !pinDigitsValid(digits)) return false;
        var hex: [64]u8 = undefined;
        hashPinHex(digits, &hex);
        return std.mem.eql(u8, &self.pin_hash, &hex);
    }
    pub fn clearPin(self: *SecurityPrefs) void {
        @memset(&self.pin_hash, 0);
        self.has_pin = false;
        self.locked = false;
        self.pin_boot = false;
        self.pin_slp = false;
        self.pin_idle = false;
        self.pin_idle_tmo_idx = 0;
        self.pin_tmo_idx = 0;
        self.idle_exp = false;
    }
    /// Wake on + Never tmo → On sleep; Never tmo → clear wake.
    pub fn applyTmoIdx(self: *SecurityPrefs, idx: u8) void {
        self.pin_tmo_idx = @min(idx, tmo_labels.len - 1);
        if (self.pin_tmo_idx == 0) self.pin_slp = false;
    }
    pub fn setWake(self: *SecurityPrefs, on: bool) void {
        self.pin_slp = on;
        if (on and self.pin_tmo_idx == 0) self.pin_tmo_idx = 6; // On sleep
    }
    pub fn applyIdleTmoIdx(self: *SecurityPrefs, idx: u8) void {
        self.pin_idle_tmo_idx = @min(idx, idle_tmo_labels.len - 1);
        if (self.pin_idle_tmo_idx == 0) self.pin_idle = false;
    }
    pub fn setIdle(self: *SecurityPrefs, on: bool) void {
        self.pin_idle = on;
        if (on and self.pin_idle_tmo_idx == 0) self.pin_idle_tmo_idx = 2; // 5 min default
    }
    pub fn resetDefaults(self: *SecurityPrefs) void {
        self.* = .{};
    }
};

pub const MachinePrefs = struct {
    mxfeed: u16 = 5000,
    mxrpm: u16 = 24000,
    jogspd: u16 = 2000,
    feedovr: u8 = 100,
    spindovr: u8 = 100,
    slim: bool = false,
    tr_x: u16 = 300,
    tr_y: u16 = 300,
    tr_z: u16 = 100,
    tr_a: u16 = 360,
    tr_b: u16 = 360,
    tr_c: u16 = 360,
    mach_name: [32]u8 = padStr("My CNC", 32),
    mach_type: u8 = 0,
    spcw: bool = true,
    /// Accrued path travel (mm), spindle-on (sec), program run (sec).
    odo_mm: u32 = 0,
    sph_sec: u32 = 0,
    run_sec: u32 = 0,
    /// Interval dropdown indices (0 = Off).
    mnt_odo_idx: u8 = 3, // 500 m
    mnt_sph_idx: u8 = 3, // 100 h
    mnt_run_idx: u8 = 4, // 200 h
    mnt_warn_idx: u8 = 2, // 90%
    svc_dt: [16]u8 = padStr("Not set", 16),
    /// LVGL `cnc_svc_nt` max 63 + NUL.
    svc_nt: [64]u8 = .{0} ** 64,
    meters_exp: bool = false,
    ref_exp: bool = false,

    pub const mnt_odo_m = [_]u16{ 0, 100, 250, 500, 1000, 2000, 5000 };
    pub const mnt_hours = [_]u16{ 0, 25, 50, 100, 200, 500, 1000 };
    pub const mnt_warn_pct = [_]u8{ 80, 85, 90, 95, 100 };
    pub const mnt_odo_labels = [_][]const u8{ "Off", "100 m", "250 m", "500 m", "1 km", "2 km", "5 km" };
    pub const mnt_hours_labels = [_][]const u8{ "Off", "25 h", "50 h", "100 h", "200 h", "500 h", "1000 h" };
    pub const mnt_warn_labels = [_][]const u8{ "80%", "85%", "90%", "95%", "100%" };

    pub fn nameSlice(self: *const MachinePrefs) []const u8 {
        return cstrSlice(&self.mach_name);
    }
    pub fn typeLabel(self: MachinePrefs) []const u8 {
        return mach_type_names[@min(self.mach_type, mach_type_names.len - 1)];
    }
    pub fn svcDtSlice(self: *const MachinePrefs) []const u8 {
        return cstrSlice(&self.svc_dt);
    }
    pub fn svcNtSlice(self: *const MachinePrefs) []const u8 {
        return cstrSlice(&self.svc_nt);
    }
    /// LVGL MACH_NAME_MAX_LEN 31 — printable ASCII only.
    pub const name_max: usize = 31;
    pub const svc_nt_max: usize = 63;

    pub fn sanitizeName(src: []const u8, out: *[32]u8) []const u8 {
        @memset(out, 0);
        var j: usize = 0;
        for (src) |c| {
            if (j >= name_max) break;
            if (c >= 0x20 and c <= 0x7E) {
                out[j] = c;
                j += 1;
            }
        }
        return out[0..j];
    }
    pub fn setName(self: *MachinePrefs, src: []const u8) void {
        _ = sanitizeName(src, &self.mach_name);
    }
    pub fn setSvcNotes(self: *MachinePrefs, src: []const u8) void {
        @memset(&self.svc_nt, 0);
        const n = @min(src.len, svc_nt_max);
        @memcpy(self.svc_nt[0..n], src[0..n]);
    }
    /// Host stub — apply sample Grbl envelope ($110/$30/$130-132) like dump sample.
    pub fn applyPullStub(self: *MachinePrefs) u8 {
        self.mxfeed = 5000;
        self.mxrpm = 1000;
        self.tr_x = 200;
        self.tr_y = 200;
        self.tr_z = 100;
        return 5;
    }
    pub fn odoLimitMm(self: MachinePrefs) u64 {
        const m = mnt_odo_m[@min(self.mnt_odo_idx, mnt_odo_m.len - 1)];
        return @as(u64, m) * 1000;
    }
    pub fn sphLimitSec(self: MachinePrefs) u64 {
        const h = mnt_hours[@min(self.mnt_sph_idx, mnt_hours.len - 1)];
        return @as(u64, h) * 3600;
    }
    pub fn runLimitSec(self: MachinePrefs) u64 {
        const h = mnt_hours[@min(self.mnt_run_idx, mnt_hours.len - 1)];
        return @as(u64, h) * 3600;
    }
    pub fn warnPct(self: MachinePrefs) u8 {
        return mnt_warn_pct[@min(self.mnt_warn_idx, mnt_warn_pct.len - 1)];
    }
    pub fn mntOdoM(self: MachinePrefs) u16 {
        return mnt_odo_m[@min(self.mnt_odo_idx, mnt_odo_m.len - 1)];
    }
    pub fn mntSphH(self: MachinePrefs) u16 {
        return mnt_hours[@min(self.mnt_sph_idx, mnt_hours.len - 1)];
    }
    pub fn mntRunH(self: MachinePrefs) u16 {
        return mnt_hours[@min(self.mnt_run_idx, mnt_hours.len - 1)];
    }
    pub fn mntWarnPct(self: MachinePrefs) u8 {
        return self.warnPct();
    }
    pub fn formatTravel(self: MachinePrefs, buf: []u8) []const u8 {
        if (self.odo_mm >= 1000) {
            const m = @as(f32, @floatFromInt(self.odo_mm)) / 1000.0;
            return std.fmt.bufPrint(buf, "{d:.1} m", .{m}) catch "0 m";
        }
        return std.fmt.bufPrint(buf, "{d} mm", .{self.odo_mm}) catch "0 mm";
    }
    pub fn formatServicePct(value: u32, limit: u64, buf: []u8) []const u8 {
        if (limit == 0) return "interval off";
        const pct: u32 = @intCast(@min(100, (value * 100) / limit));
        return std.fmt.bufPrint(buf, "{d}% of interval", .{pct}) catch "?%";
    }
    pub fn formatDuration(sec: u32, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{d} h {d} min", .{ sec / 3600, (sec % 3600) / 60 }) catch "?";
    }
    /// Soft accrual so Maintenance reads live on host (LVGL 2 s timer parity).
    pub fn tickMaint(self: *MachinePrefs) void {
        self.odo_mm +%= 12;
        self.sph_sec +%= 1;
        self.run_sec +%= 1;
    }
    pub fn resetMaintCounters(self: *MachinePrefs) void {
        self.odo_mm = 0;
        self.sph_sec = 0;
        self.run_sec = 0;
    }
    pub fn resetDefaults(self: *MachinePrefs) void {
        self.* = .{};
    }
};

pub const SdState = enum { unmounted, mounted, failed };

pub const StorExportResult = enum { ok, need_sd, failed };

pub const StoragePrefs = struct {
    sd: SdState = .unmounted,
    /// Kept in sync with `sd` for System health chips.
    sd_mounted: bool = false,
    loglvl: u8 = 2,
    usb_host: bool = false,
    ref_exp: bool = false,
    i2c_exp: bool = false,
    portmap_exp: bool = false,
    i2c_ref_exp: bool = false,
    /// Host stub heap telemetry (refreshed every ~2 s).
    int_free_kb: u32 = 180,
    int_total_kb: u32 = 512,
    ps_free_mb: u32 = 28,
    ps_total_mb: u32 = 32,
    lvgl_free_kb: u32 = 4200,
    lvgl_used_pct: u8 = 12,
    min_free_kb: u32 = 120,
    sd_free_gb_x10: u16 = 142,
    sd_total_gb_x10: u16 = 298,
    i2c_scan_phase: u8 = 0, // 0=idle 1=scanning 2=done
    i2c_last_target: u8 = 0,
    /// Device: I2C scan owned by shim worker.
    i2c_scan_hw: bool = false,
    /// Live scan result lines (1=PortA 2=M-Bus 3=EXP1 4=EXP2); 0 unused.
    i2c_live: [5][96]u8 = .{.{0} ** 96} ** 5,
    /// ~4 s row flash after diagnostics export (LVGL `s_stor_export_flash_start`).
    diag_flash_frames: u16 = 0,
    diag_flash: [32]u8 = undefined,
    diag_flash_len: u8 = 0,
    /// Brief detail flash after settings export.
    backup_flash_frames: u16 = 0,
    backup_flash: [40]u8 = undefined,
    backup_flash_len: u8 = 0,

    pub fn syncMounted(self: *StoragePrefs) void {
        self.sd_mounted = self.sd == .mounted;
    }
    pub fn sdStatus(self: StoragePrefs) []const u8 {
        return switch (self.sd) {
            .mounted => "Mounted",
            .failed => "Error",
            .unmounted => "Not mounted",
        };
    }
    pub fn sdCapacity(self: StoragePrefs, buf: []u8) []const u8 {
        if (self.sd != .mounted) return "--";
        const free_g = @as(f32, @floatFromInt(self.sd_free_gb_x10)) / 10.0;
        const tot_g = @as(f32, @floatFromInt(self.sd_total_gb_x10)) / 10.0;
        return std.fmt.bufPrint(buf, "{d:.1} GB free of {d:.1} GB", .{ free_g, tot_g }) catch "--";
    }
    pub fn formatMemPair(buf: []u8, free_n: u32, total_n: u32, unit: []const u8) []const u8 {
        return std.fmt.bufPrint(buf, "{d} {s} / {d} {s}", .{ free_n, unit, total_n, unit }) catch "?";
    }
    pub fn formatLvgl(self: StoragePrefs, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{d} KB max blk ({d}% used)", .{ self.lvgl_free_kb, self.lvgl_used_pct }) catch "?";
    }
    pub fn formatMinFree(self: StoragePrefs, buf: []u8) []const u8 {
        return std.fmt.bufPrint(buf, "{d} KB", .{self.min_free_kb}) catch "?";
    }
    /// Soft jitter so Memory section reads “live” on host (skipped when `i2c_scan_hw`).
    pub fn tickTelemetry(self: *StoragePrefs) void {
        self.int_free_kb = 160 + (self.int_free_kb + 3) % 40;
        self.ps_free_mb = 26 + (self.ps_free_mb + 1) % 4;
        self.lvgl_used_pct = 8 + (self.lvgl_used_pct + 1) % 20;
        if (self.min_free_kb > self.int_free_kb) self.min_free_kb = self.int_free_kb;
        if (self.sd == .mounted) {
            self.sd_free_gb_x10 = 140 + (self.sd_free_gb_x10 + 1) % 5;
        }
        if (self.i2c_scan_phase == 1 and !self.i2c_scan_hw) {
            self.i2c_scan_phase = 2;
        }
        if (self.diag_flash_frames > 0) self.diag_flash_frames -= 1;
        if (self.backup_flash_frames > 0) self.backup_flash_frames -= 1;
    }
    pub fn setLiveLine(self: *StoragePrefs, which: u8, text: []const u8) void {
        if (which == 0 or which > 4) return;
        @memset(&self.i2c_live[which], 0);
        const n = @min(text.len, self.i2c_live[which].len - 1);
        @memcpy(self.i2c_live[which][0..n], text[0..n]);
    }
    pub fn markExportOk(self: *StoragePrefs, diag: bool, msg: []const u8) void {
        if (diag) {
            setFlash(&self.diag_flash, &self.diag_flash_len, &self.diag_flash_frames, msg);
        } else {
            setFlash(&self.backup_flash, &self.backup_flash_len, &self.backup_flash_frames, msg);
        }
    }
    fn setFlash(buf: []u8, len: *u8, frames: *u16, msg: []const u8) void {
        const n = @min(msg.len, buf.len);
        @memcpy(buf[0..n], msg[0..n]);
        len.* = @intCast(n);
        frames.* = 240; // ~4 s @ 60 Hz
    }
    pub fn diagDetail(self: *const StoragePrefs) []const u8 {
        if (self.diag_flash_frames > 0 and self.diag_flash_len > 0)
            return self.diag_flash[0..self.diag_flash_len];
        return if (self.sd == .mounted) "Save to SD" else "Insert SD card";
    }
    pub fn backupExportDetail(self: *const StoragePrefs) []const u8 {
        if (self.backup_flash_frames > 0 and self.backup_flash_len > 0)
            return self.backup_flash[0..self.backup_flash_len];
        return if (self.sd == .mounted) "modulus_settings.json" else "Insert SD card";
    }
    /// Host stub: success when mounted; fail when `.failed`; need_sd otherwise.
    pub fn exportDiagnosticsStub(self: *StoragePrefs) StorExportResult {
        return switch (self.sd) {
            .mounted => {
                setFlash(&self.diag_flash, &self.diag_flash_len, &self.diag_flash_frames, "Saved modulus_diag.txt");
                return .ok;
            },
            .failed => {
                setFlash(&self.diag_flash, &self.diag_flash_len, &self.diag_flash_frames, "Export failed");
                return .failed;
            },
            .unmounted => {
                setFlash(&self.diag_flash, &self.diag_flash_len, &self.diag_flash_frames, "Insert SD card");
                return .need_sd;
            },
        };
    }
    pub fn exportSettingsStub(self: *StoragePrefs) StorExportResult {
        return switch (self.sd) {
            .mounted => {
                setFlash(&self.backup_flash, &self.backup_flash_len, &self.backup_flash_frames, "Exported");
                return .ok;
            },
            .failed => {
                setFlash(&self.backup_flash, &self.backup_flash_len, &self.backup_flash_frames, "Export failed");
                return .failed;
            },
            .unmounted => {
                setFlash(&self.backup_flash, &self.backup_flash_len, &self.backup_flash_frames, "Insert SD card");
                return .need_sd;
            },
        };
    }
    pub fn mount(self: *StoragePrefs) void {
        self.sd = .mounted;
        self.syncMounted();
    }
    pub fn eject(self: *StoragePrefs) void {
        self.sd = .unmounted;
        self.syncMounted();
    }
    pub fn startI2cScan(self: *StoragePrefs, target: u8) void {
        self.i2c_last_target = target;
        self.i2c_scan_phase = 1;
        self.i2c_scan_hw = false;
    }
    pub fn i2cStatusText(self: StoragePrefs) []const u8 {
        return switch (self.i2c_scan_phase) {
            1 => "Scanning...",
            2 => "Done",
            else => "Idle",
        };
    }
    pub fn i2cResult(self: *const StoragePrefs, which: u8) []const u8 {
        if (self.i2c_scan_phase == 0) return "Not scanned";
        if (self.i2c_scan_phase == 1) return "Scanning...";
        if (which >= 1 and which <= 4 and self.i2c_live[which][0] != 0) {
            return cstrSlice(&self.i2c_live[which]);
        }
        return "No ACKs";
    }
    pub fn resetDefaults(self: *StoragePrefs) void {
        self.* = .{};
    }
};

pub const SystemPrefs = struct {
    lang: u8 = 0,
    tz_idx: u8 = 0,
    t_24h: bool = true,
    datefmt: u8 = 0,
    kb_full: bool = true,
    ntp: bool = true,
    ntp_synced: bool = false,
    /// Host stub: frames left in "Syncing..." (1 Hz tick). 0 = idle.
    ntp_syncing_frames: u8 = 0,
    ref_exp: bool = false,
    /// Device: overlay FPS / paint-µs / dirty-px on status bar (Zig path).
    perf_hud: bool = false,
    /// Device mirror: C6 SDIO link up (esp_hosted).
    c6_ready: bool = false,
    sdio_stream_drop: u32 = 0,
    sdio_queue_stall: u32 = 0,
    sdio_pad_skip: u32 = 0,
    /// Device: RTC shim owns time/date/NTP status (see `mirrorBatteryClock`).
    rtc_live: bool = false,
    time_live: [24]u8 = .{0} ** 24,
    date_live: [24]u8 = .{0} ** 24,
    ntp_live: [40]u8 = .{0} ** 40,
    /// Demo wall clock (unix seconds). Host only — engine advances 1/s.
    wall_sec: i64 = 1_787_341_080, // ~2026-08-21 20:58 UTC
    uptime_sec: u64 = 0,

    pub fn langLabel(self: SystemPrefs) []const u8 {
        const labs = [_][]const u8{ "English", "Spanish", "German", "French", "Chinese" };
        return labs[@min(self.lang, labs.len - 1)];
    }
    pub const tz_labels = [_][]const u8{ "UTC", "UTC-8 Pacific", "UTC-5 Eastern", "UTC+0 London", "UTC+1 Berlin", "UTC+8 China" };

    pub fn tzLabel(self: SystemPrefs) []const u8 {
        return tz_labels[@min(self.tz_idx, tz_labels.len - 1)];
    }
    pub fn tzOffsetSec(self: SystemPrefs) i32 {
        const off = [_]i32{ 0, -8 * 3600, -5 * 3600, 0, 3600, 8 * 3600 };
        return off[@min(self.tz_idx, off.len - 1)];
    }
    pub fn tickOneSec(self: *SystemPrefs) void {
        self.wall_sec += 1;
        self.uptime_sec += 1;
        if (self.ntp_syncing_frames > 0) {
            self.ntp_syncing_frames -= 1;
            if (self.ntp_syncing_frames == 0 and self.ntp) self.ntp_synced = true;
        }
    }
    pub fn nowEpoch(self: SystemPrefs) i64 {
        return self.wall_sec + self.tzOffsetSec();
    }
    /// LVGL `modulus_rtc_ntp_status_text` vocabulary.
    pub fn ntpStatus(self: SystemPrefs, wifi_on: bool) []const u8 {
        if (self.rtc_live) {
            const live = cstrSlice(&self.ntp_live);
            if (live.len > 0) return live;
        }
        if (!self.ntp) return "Disabled";
        if (!wifi_on) return "No network";
        if (self.ntp_syncing_frames > 0) return "Syncing...";
        if (self.ntp_synced) return "Synced";
        return "Not synced";
    }
    pub const SyncNowResult = enum { disabled, no_net, started };

    /// Host stub for Sync now — does not force-enable NTP (LVGL parity).
    pub fn syncNow(self: *SystemPrefs, wifi_on: bool) SyncNowResult {
        if (!self.ntp) return .disabled;
        if (!wifi_on) return .no_net;
        self.ntp_synced = false;
        self.ntp_syncing_frames = 2;
        return .started;
    }
    pub fn setNtpEnabled(self: *SystemPrefs, on: bool, wifi_on: bool) void {
        self.ntp = on;
        self.ntp_syncing_frames = 0;
        self.ntp_synced = false;
        if (on and wifi_on) self.ntp_syncing_frames = 2;
    }
    pub fn formatTime(self: SystemPrefs, buf: []u8) []const u8 {
        if (self.rtc_live) {
            const live = cstrSlice(&self.time_live);
            if (live.len > 0) {
                const n = @min(live.len, buf.len);
                @memcpy(buf[0..n], live[0..n]);
                return buf[0..n];
            }
        }
        const e = self.nowEpoch();
        const tod = @mod(e, 86400);
        var h: u32 = @intCast(@divTrunc(tod, 3600));
        const m: u32 = @intCast(@divTrunc(@mod(tod, 3600), 60));
        const s: u32 = @intCast(@mod(tod, 60));
        if (self.t_24h) {
            return std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}:{d:0>2}", .{ h, m, s }) catch "00:00:00";
        }
        const am = h < 12;
        h = h % 12;
        if (h == 0) h = 12;
        return std.fmt.bufPrint(buf, "{d}:{d:0>2}:{d:0>2} {s}", .{ h, m, s, if (am) "AM" else "PM" }) catch "12:00:00 AM";
    }
    pub fn formatDate(self: SystemPrefs, buf: []u8) []const u8 {
        if (self.rtc_live) {
            const live = cstrSlice(&self.date_live);
            if (live.len > 0) {
                const n = @min(live.len, buf.len);
                @memcpy(buf[0..n], live[0..n]);
                return buf[0..n];
            }
        }
        // ponytail: civil date from unix day — good enough for host demo; ceiling: full calendar lib.
        const days = @divTrunc(self.nowEpoch(), 86400);
        var z = days + 719468;
        if (z < 0) z = 0;
        const era: i64 = @divTrunc(if (z >= 0) z else z - 146096, 146097);
        const doe: u64 = @intCast(z - era * 146097);
        const yoe: u64 = @divTrunc(doe - @divTrunc(doe, 1460) + @divTrunc(doe, 36524) - @divTrunc(doe, 146096), 365);
        var y: i64 = @as(i64, @intCast(yoe)) + era * 400;
        const doy: u64 = doe - (365 * yoe + @divTrunc(yoe, 4) - @divTrunc(yoe, 100));
        const mp: u64 = @divTrunc(5 * doy + 2, 153);
        const d: u32 = @intCast(doy - @divTrunc(153 * mp + 2, 5) + 1);
        var m: u32 = @intCast(mp +% 3);
        if (m > 12) {
            m -= 12;
            y += 1;
        }
        const yi: u32 = @intCast(@max(y, 1970));
        return switch (self.datefmt) {
            1 => std.fmt.bufPrint(buf, "{d:0>2}/{d:0>2}/{d}", .{ m, d, yi }) catch "01/01/1970",
            2 => std.fmt.bufPrint(buf, "{d:0>2}/{d:0>2}/{d}", .{ d, m, yi }) catch "01/01/1970",
            else => std.fmt.bufPrint(buf, "{d}-{d:0>2}-{d:0>2}", .{ yi, m, d }) catch "1970-01-01",
        };
    }
    pub fn formatUptime(self: SystemPrefs, buf: []u8) []const u8 {
        const u = self.uptime_sec;
        const h = u / 3600;
        const m = (u % 3600) / 60;
        const s = u % 60;
        return std.fmt.bufPrint(buf, "{d}:{d:0>2}:{d:0>2}", .{ h, m, s }) catch "0:00:00";
    }
    pub fn hmsParts(self: SystemPrefs) struct { h: u32, m: u32, s: u32 } {
        const tod = @mod(self.nowEpoch(), 86400);
        return .{
            .h = @intCast(@divTrunc(tod, 3600)),
            .m = @intCast(@divTrunc(@mod(tod, 3600), 60)),
            .s = @intCast(@mod(tod, 60)),
        };
    }
    pub fn ymdParts(self: SystemPrefs) struct { y: u32, m: u32, d: u32 } {
        // Same civil math as formatDate — keep in sync.
        const days = @divTrunc(self.nowEpoch(), 86400);
        var z = days + 719468;
        if (z < 0) z = 0;
        const era: i64 = @divTrunc(if (z >= 0) z else z - 146096, 146097);
        const doe: u64 = @intCast(z - era * 146097);
        const yoe: u64 = @divTrunc(doe - @divTrunc(doe, 1460) + @divTrunc(doe, 36524) - @divTrunc(doe, 146096), 365);
        var y: i64 = @as(i64, @intCast(yoe)) + era * 400;
        const doy: u64 = doe - (365 * yoe + @divTrunc(yoe, 4) - @divTrunc(yoe, 100));
        const mp: u64 = @divTrunc(5 * doy + 2, 153);
        const d: u32 = @intCast(doy - @divTrunc(153 * mp + 2, 5) + 1);
        var m: u32 = @intCast(mp +% 3);
        if (m > 12) {
            m -= 12;
            y += 1;
        }
        return .{ .y = @intCast(@max(y, 1970)), .m = m, .d = d };
    }
    pub fn applyManualTime(self: *SystemPrefs, hh: u32, mm: u32, ss: u32) void {
        const e = self.nowEpoch();
        const day = @divTrunc(e, 86400) * 86400;
        const local = day + @as(i64, @intCast(hh * 3600 + mm * 60 + @min(ss, 59)));
        self.wall_sec = local - self.tzOffsetSec();
        self.ntp_synced = false;
    }
    pub fn applyManualDate(self: *SystemPrefs, year: u32, month: u32, day: u32) void {
        // ponytail: approximate epoch from Y-M-D; ceiling: civil_from_days inverse.
        const y: i64 = @intCast(@max(year, 1970));
        const m: i64 = @intCast(@max(@min(month, 12), 1));
        const d: i64 = @intCast(@max(@min(day, 31), 1));
        const days = y * 365 + @divTrunc(y, 4) - @divTrunc(y, 100) + @divTrunc(y, 400) + (m - 1) * 30 + d - 719468;
        const tod = @mod(self.nowEpoch(), 86400);
        self.wall_sec = days * 86400 + tod - self.tzOffsetSec();
        self.ntp_synced = false;
    }
    pub fn resetDefaults(self: *SystemPrefs) void {
        const up = self.uptime_sec;
        const wall = self.wall_sec;
        self.* = .{ .uptime_sec = up, .wall_sec = wall };
    }
};

pub const Prefs = struct {
    dash: DashboardPrefs = .{},
    display: DisplayPrefs = .{},
    cnc: CncPrefs = .{},
    audio: AudioPrefs = .{},
    wireless: WirelessPrefs = .{},
    power: PowerPrefs = .{},
    security: SecurityPrefs = .{},
    machine: MachinePrefs = .{},
    storage: StoragePrefs = .{},
    system: SystemPrefs = .{},
    /// LVGL `qs_tab` NVS — System/Devices/Terminal/Probe/Material.
    qs_tab: u8 = 0,
    /// LVGL `modulus_recipe_get` — Aluminum/Wood/Acrylic.
    qs_recipe: u8 = 0,
    /// Checkable macro latch bits (slots 0..3) when off-cmd present.
    qs_macro_on: u8 = 0,
    /// Settings UI: false = Essentials (fewer rows), true = Advanced.
    settings_advanced: bool = false,

    pub fn applyAll(self: Prefs, cnc: *dashboard.CncView, theme: *tokens.Theme) void {
        self.applyAllOpts(cnc, theme, .{});
    }

    pub const ApplyOpts = struct {
        /// Device: mirror owns overrides / WCS / jog — do not stomp from NVS.
        preserve_machine_live: bool = false,
    };

    pub fn applyAllOpts(self: Prefs, cnc: *dashboard.CncView, theme: *tokens.Theme, opts: ApplyOpts) void {
        if (opts.preserve_machine_live) {
            self.dash.applyLayout(cnc);
            // Keep WCS label in sync with mirrored index (not prefs.dash.wcs).
            const wi = @min(cnc.wcs_i, 5);
            cnc.wcs = self.dash.wcsDisplayLabel(wi);
        } else {
            self.dash.apply(cnc);
            cnc.feed_pct = self.machine.feedovr;
            cnc.spindle_pct = self.machine.spindovr;
        }
        cnc.lefty = self.display.lefty;
        cnc.conn = self.cnc.conn;
        cnc.battery_pct = self.power.bat_pct;
        cnc.battery_charge_state = self.power.charge_state;
        cnc.battery_charging = self.power.charge_state == 1 or self.power.charge_state == 2;
        cnc.battery_fast_charge = battery_chrome.isFastCharge(self.power.charge_state, @abs(self.power.bat_ma));
        cnc.wifi_on = self.wireless.wifi;
        cnc.bt_on = self.wireless.bt;
        cnc.espnow_on = self.wireless.espnow;
        theme.* = self.display.buildTheme();
    }

    /// Host stub for SD JSON import — mutates a canned snapshot (PIN/Wi-Fi stay local).
    pub fn applyImportStub(self: *Prefs) void {
        self.machine.setName("Imported CNC");
        self.display.bright = 72;
        self.audio.vol = 50;
        self.storage.loglvl = 3;
        self.machine.feedovr = 100;
        self.machine.spindovr = 100;
    }

    /// Keep CNC `espnow_mac` locked to wireless bridge — `savePrefs` persists `en_mac` from CNC.
    pub fn syncEspnowMacFromBridge(self: *Prefs) void {
        const mac = self.wireless.bridgeSlice();
        @memset(&self.cnc.espnow_mac, 0);
        if (mac.len == 0 or std.mem.eql(u8, mac, "None")) return;
        const n = @min(mac.len, self.cnc.espnow_mac.len -| 1);
        if (n > 0) @memcpy(self.cnc.espnow_mac[0..n], mac[0..n]);
    }

    /// NVS write source: live bridge first, else CNC field (skip "None").
    pub fn espnowMacForNvs(self: *const Prefs) []const u8 {
        const b = self.wireless.bridgeSlice();
        if (b.len > 0 and !std.mem.eql(u8, b, "None")) return b;
        const m = self.cnc.espnowMacSlice();
        if (m.len > 0 and !std.mem.eql(u8, m, "None")) return m;
        return "";
    }
};

fn colorHex(h: u24) color.Rgb565 {
    return color.Rgb565.fromHex(h);
}

fn padIncr(comptime s: []const u8) [8]u8 {
    return padStr(s, 8);
}

fn padStr(comptime s: []const u8, comptime N: usize) [N]u8 {
    var out: [N]u8 = .{0} ** N;
    const n = @min(s.len, N);
    @memcpy(out[0..n], s[0..n]);
    return out;
}

/// Host soft-fill: copy stub labels into live_* so paint never reads stub_* directly.
fn softFillNames(live: anytype, n_out: *u8, stubs: []const []const u8) void {
    const count = @min(stubs.len, live.len);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        @memset(&live[i], 0);
        const s = stubs[i];
        const n = @min(s.len, live[i].len - 1);
        @memcpy(live[i][0..n], s[0..n]);
    }
    n_out.* = @intCast(count);
}

fn cstrSlice(raw: []const u8) []const u8 {
    var len: usize = 0;
    while (len < raw.len and raw[len] != 0) : (len += 1) {}
    return raw[0..len];
}

fn sanitizeProfileName(out: *[profile_name_max]u8, src: []const u8) []const u8 {
    var j: usize = 0;
    for (src) |c| {
        if (j + 1 >= profile_name_max) break;
        if (c >= 0x20 and c <= 0x7E and c != '|') {
            out[j] = c;
            j += 1;
        }
    }
    if (j == 0) {
        const d = "Profile";
        @memcpy(out[0..d.len], d);
        j = d.len;
    }
    return out[0..j];
}

fn packProfileLive(out: *[profile_blob_max]u8, name: []const u8, c: *const CncPrefs) error{NoSpace}!usize {
    const n = std.fmt.bufPrint(out, "{s}|{d}|{d}|{s}|{d}|{s}|{d}|{s}|{s}|{s}|1", .{
        name,
        c.proto,
        c.conn,
        c.wsHostSlice(),
        c.ws_port,
        c.tnHostSlice(),
        c.tn_port,
        c.massoIpSlice(),
        blk: {
            const s = cstrSlice(&c.masso_sn);
            break :blk if (s.len == 0) "" else s;
        },
        c.espnowMacSlice(),
    }) catch return error.NoSpace;
    return n.len;
}

fn profileField(blob: []const u8, idx: usize) ?[]const u8 {
    var start: usize = 0;
    var i: usize = 0;
    while (start <= blob.len) {
        const end = std.mem.indexOfScalarPos(u8, blob, start, '|') orelse blob.len;
        if (i == idx) return blob[start..end];
        if (end >= blob.len) break;
        start = end + 1;
        i += 1;
    }
    return null;
}

fn applyProfileBlob(c: *CncPrefs, blob: []const u8) void {
    if (profileField(blob, 1)) |s| c.proto = std.fmt.parseInt(u8, s, 10) catch c.proto;
    if (profileField(blob, 2)) |s| {
        c.conn = std.fmt.parseInt(u8, s, 10) catch c.conn;
        c.transport_off = false;
    }
    if (profileField(blob, 3)) |s| {
        @memset(&c.ws_host, 0);
        const n = @min(s.len, c.ws_host.len);
        @memcpy(c.ws_host[0..n], s[0..n]);
    }
    if (profileField(blob, 4)) |s| c.ws_port = std.fmt.parseInt(u16, s, 10) catch c.ws_port;
    if (profileField(blob, 5)) |s| {
        @memset(&c.tn_host, 0);
        const n = @min(s.len, c.tn_host.len);
        @memcpy(c.tn_host[0..n], s[0..n]);
    }
    if (profileField(blob, 6)) |s| c.tn_port = std.fmt.parseInt(u16, s, 10) catch c.tn_port;
    if (profileField(blob, 7)) |s| {
        @memset(&c.masso_ip, 0);
        const n = @min(s.len, c.masso_ip.len);
        @memcpy(c.masso_ip[0..n], s[0..n]);
    }
    if (profileField(blob, 8)) |s| {
        @memset(&c.masso_sn, 0);
        const n = @min(s.len, c.masso_sn.len);
        @memcpy(c.masso_sn[0..n], s[0..n]);
    }
    if (profileField(blob, 9)) |s| {
        @memset(&c.espnow_mac, 0);
        const n = @min(s.len, c.espnow_mac.len);
        @memcpy(c.espnow_mac[0..n], s[0..n]);
    }
}

fn applyAccent(t: *tokens.Theme, accent: u8, dark: bool) void {
    const primaries_dark = [_]u24{ 0x4FD6E0, 0x00E5FF, 0xFFB020, 0x4FC3F7, 0xFF6B6B, 0xCE93D8, 0xA5D6A7, 0xECEFF1, 0xB0BEC5 };
    const primaries_light = [_]u24{ 0x006974, 0x00838F, 0xE65100, 0x0277BD, 0xC62828, 0x7B1FA2, 0x2E7D32, 0x455A64, 0x37474F };
    const idx = @min(accent, primaries_dark.len - 1);
    const seed = if (dark) primaries_dark[idx] else primaries_light[idx];
    t.applySeed(seed, dark);
    if (idx == 7 and !dark) {
        t.surface = colorHex(0xFAFBFC);
    }
}

test "axes preset maps 2..6" {
    var d: DashboardPrefs = .{};
    d.setAxesVisible(6);
    try std.testing.expectEqual(@as(u8, 6), d.axesVisible());
    d.setAxesVisible(2);
    try std.testing.expectEqual(@as(u8, 2), d.axesVisible());
}

test "theme accent builds" {
    var d: DisplayPrefs = .{ .accent = 3, .darkmode = true };
    const t = d.buildTheme();
    try std.testing.expect(t.dark);
    _ = t.primary;
}

test "ui contrast levels change outline ink" {
    var d: DisplayPrefs = .{ .darkmode = true, .ui_contrast = 0 };
    const std_t = d.buildTheme();
    d.ui_contrast = 1;
    const med = d.buildTheme();
    d.ui_contrast = 2;
    const hi = d.buildTheme();
    try std.testing.expect(med.outline.toU16() != std_t.outline.toU16());
    try std.testing.expect(hi.on_surface.toU16() == color.Rgb565.fromHex(0xFFFFFF).toU16());
    try std.testing.expect(hi.outline.toU16() == color.Rgb565.fromHex(0xFFFFFF).toU16());
}

test "font scale labels" {
    var d: DisplayPrefs = .{ .font_scale = 0 };
    try std.testing.expectEqualStrings("Small", d.fontScaleName());
    d.font_scale = 1;
    try std.testing.expectEqualStrings("Default", d.fontScaleName());
    d.font_scale = 3;
    try std.testing.expectEqualStrings("Largest", d.fontScaleName());
}

test "cnc profiles save activate rename" {
    var c: CncPrefs = .{};
    c.proto = 2;
    c.conn = 1;
    c.ws_port = 81;
    c.saveProfileSlot(0, "Shop A");
    try std.testing.expectEqualStrings("Shop A", c.profileName(0));
    try std.testing.expectEqual(@as(u8, 0), c.prof);

    c.proto = 0;
    c.conn = 4;
    try std.testing.expect(c.activateProfile(0));
    try std.testing.expectEqual(@as(u8, 2), c.proto);
    try std.testing.expectEqual(@as(u8, 1), c.conn);
    try std.testing.expectEqual(@as(u8, 2), c.session_phase);

    c.renameProfile(0, "Lathe|bad");
    try std.testing.expectEqualStrings("Lathebad", c.profileName(0));

    var dbuf: [48]u8 = undefined;
    const detail = c.profileDetail(&dbuf);
    try std.testing.expect(std.mem.startsWith(u8, detail, "Active:"));
}

test "cnc supportsDump grbl-family only" {
    var c: CncPrefs = .{ .proto = 2 };
    try std.testing.expect(c.supportsDump());
    c.proto = 3;
    try std.testing.expect(!c.supportsDump());
}

test "cnc disconnect aborts connecting without session_up" {
    var c: CncPrefs = .{};
    c.conn = 0;
    c.startConnect();
    try std.testing.expect(c.sessionBusy());
    try std.testing.expect(!c.session_up);
    try std.testing.expectEqualStrings("Connecting...", c.sessionText());
    c.disconnect();
    try std.testing.expect(!c.sessionBusy());
    try std.testing.expect(c.transport_off);
    try std.testing.expectEqual(@as(u8, 0), c.conn); // selection preserved
    try std.testing.expectEqualStrings("Transport off", c.sessionText());
}

test "cnc connect hold expires" {
    var c: CncPrefs = .{};
    c.startConnect();
    try std.testing.expectEqual(@as(u8, 90), c.connect_hold_frames);
    var i: u8 = 0;
    while (i < 90) : (i += 1) c.tickConnectHold();
    try std.testing.expectEqual(@as(u8, 0), c.connect_hold_frames);
}

test "dashboard incr csv and macros" {
    var d: DashboardPrefs = .{};
    d.setIncrFromCsv("0.02,0.2,2,10");
    try std.testing.expectEqualStrings("0.02", d.incrSlice(0));
    try std.testing.expectEqualStrings("10", d.incrSlice(3));
    try std.testing.expect(d.saveMacro(0, "Clamp", "M64 P0", "M65 P0"));
    try std.testing.expect(d.macros[0].occupied());
    var packed_buf: [192]u8 = undefined;
    const packed_s = d.macros[0].packNvs(&packed_buf);
    try std.testing.expect(std.mem.indexOf(u8, packed_s, "Clamp") != null);
    var round: MacroSlot = .{};
    try std.testing.expect(round.unpackNvs(packed_s));
    try std.testing.expectEqualStrings("Clamp", round.nameSlice());
    try std.testing.expectEqualStrings("M64 P0", round.onSlice());
    try std.testing.expectEqualStrings("M65 P0", round.offSlice());
    try std.testing.expectEqual(@as(?u8, 1), d.firstFreeMacro());
    d.setWcsName(0, "Fixture A");
    try std.testing.expectEqualStrings("Fixture A", d.wcsDisplayLabel(0));
    try std.testing.expectEqualStrings("G55", d.wcsDisplayLabel(1));
}

test "applyAllOpts preserve_machine_live keeps overrides and wcs" {
    var prefs: Prefs = .{};
    prefs.machine.feedovr = 100;
    prefs.machine.spindovr = 100;
    prefs.dash.wcs = 0;
    var cnc: dashboard.CncView = .{};
    cnc.feed_pct = 130;
    cnc.spindle_pct = 90;
    cnc.wcs_i = 2;
    var theme = tokens.Theme.industrialTealDark();
    prefs.applyAllOpts(&cnc, &theme, .{ .preserve_machine_live = true });
    try std.testing.expectEqual(@as(u8, 130), cnc.feed_pct);
    try std.testing.expectEqual(@as(u8, 90), cnc.spindle_pct);
    try std.testing.expectEqual(@as(u8, 2), cnc.wcs_i);
    prefs.applyAllOpts(&cnc, &theme, .{});
    try std.testing.expectEqual(@as(u8, 100), cnc.feed_pct);
    try std.testing.expectEqual(@as(u8, 0), cnc.wcs_i);
}
