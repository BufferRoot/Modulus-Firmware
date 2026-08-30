//! Host ports for CNC / Audio / Wireless / Power / Security / Machine / Storage / System.
//! ponytail: slot table hit-test; no live HAL — tap cycles / toggles prefs only.

const std = @import("std");
const geom = @import("geom.zig");
const tokens = @import("tokens.zig");
const fb = @import("fb.zig");
const form = @import("settings_form.zig");
const prefs_mod = @import("settings_prefs.zig");
const modulus = @import("../core/modulus.zig");

pub const max_slots = 72;

pub const SlotKind = enum { toggle, segment, slider, dropdown, action };

pub const Hit = enum(u16) {
    none,
    // CNC
    cnc_proto,
    cnc_conn,
    cnc_connect,
    cnc_disconnect,
    cnc_configure,
    cnc_profiles,
    cnc_dump,
    cnc_ref,
    cnc_reset,
    cnc_link_mach,
    cnc_link_dash,
    cnc_link_wl,
    cnc_open_enow,
    // Audio
    aud_vol,
    aud_tsound,
    aud_tone,
    aud_snd_up,
    aud_snd_dn,
    aud_mic,
    aud_ref,
    // Wireless
    wl_back,
    wl_wifi_page,
    wl_bt_page,
    wl_en_page,
    wl_zb_page,
    wl_th_page,
    wl_chips,
    wl_ant,
    wl_hub_ref,
    wl_reset,
    wl_wifi,
    wl_bt,
    wl_espnow,
    wl_zigbee,
    wl_thread,
    wl_wf_auto,
    wl_wf_arecon,
    wl_wf_dhcp,
    wl_scan,
    wl_adv,
    wl_ssid,
    wl_saved,
    wl_disconnect,
    wl_forget,
    wl_connect_saved,
    wl_ap0,
    wl_ap1,
    wl_ap2,
    wl_en_chan,
    wl_en_enc,
    wl_en_rate,
    wl_peer0,
    wl_peer1,
    wl_bt_disconnect,
    wl_bt_adv,
    wl_zb_join,
    wl_zb_leave,
    wl_th_attach,
    wl_th_detach,
    wl_zb_adv,
    wl_th_adv,
    wl_link_ntp,
    wl_link_cnc,
    wl_bt_dev0,
    wl_bt_dev1,
    wl_bt_clear,
    wl_en_add_mac,
    wl_en_saved0,
    wl_en_saved1,
    wl_en_rm0,
    wl_en_rm1,
    wl_en_adv,
    wl_en_clear_peers,
    wl_zb_dev0,
    wl_zb_dev1,
    wl_zb_dev,
    wl_zb_identify,
    wl_zb_remove,
    wl_zb_refresh,
    wl_zb_sensors,
    wl_th_dev0,
    wl_zb_energy,
    wl_zb_clear,
    wl_th_clear,
    wl_zb_add,
    wl_th_add,
    // Power
    pwr_ext5v,
    pwr_usb5v,
    pwr_dim,
    pwr_scr,
    pwr_sleep_now,
    pwr_mode,
    pwr_dsto,
    pwr_wake_touch,
    pwr_wake_usb,
    pwr_wake_timer,
    pwr_wtmin,
    pwr_gate_wifi,
    pwr_gate_ext,
    pwr_gate_usb,
    pwr_bat_type,
    pwr_warn,
    pwr_chg,
    pwr_adapt,
    pwr_qc,
    pwr_ref,
    pwr_reset,
    pwr_link_disp,
    // Security
    sec_set_pin,
    sec_clear_pin,
    sec_tmo,
    sec_boot,
    sec_slp,
    sec_idle,
    // Machine
    mach_mxfeed,
    mach_mxrpm,
    mach_jogspd,
    mach_feedovr,
    mach_spindovr,
    mach_slim,
    mach_trx,
    mach_try,
    mach_trz,
    mach_tra,
    mach_trb,
    mach_trc,
    mach_name,
    mach_type,
    mach_spcw,
    mach_pull,
    mach_push,
    mach_dump,
    mach_mnt,
    mach_mnt_odo,
    mach_mnt_sph,
    mach_mnt_run,
    mach_mnt_warn,
    mach_meters,
    mach_svc_dt,
    mach_svc_nt,
    mach_mnt_reset,
    mach_ref,
    mach_reset,
    mach_link_cnc,
    mach_link_dash,
    // Storage
    stor_sd,
    stor_loglvl,
    stor_export,
    stor_backup_exp,
    stor_backup_imp,
    stor_cache,
    stor_ref,
    stor_i2c_exp,
    stor_i2c_all,
    stor_i2c_mbus,
    stor_i2c_porta,
    stor_i2c_exp1,
    stor_i2c_exp2,
    stor_portmap,
    stor_i2c_ref,
    // System
    sys_h_c6,
    sys_h_wifi,
    sys_h_cnc,
    sys_h_sd,
    sys_h_batt,
    sys_perf_hud,
    sys_lang,
    sys_tz,
    sys_t24,
    sys_datefmt,
    sys_kb,
    sys_ntp,
    sys_sync,
    sys_manual,
    sys_restart,
    sys_shutdown,
    sys_factory,
    sys_ref,
    sys_link_stor,
};

pub const Slot = struct {
    hit: Hit = .none,
    rect: geom.Rect = .{},
    kind: SlotKind = .action,
    seg_n: u8 = 0,
    smin: u32 = 0,
    smax: u32 = 100,
    /// Device / peer index for list rows (Zigbee, etc.).
    aux: u8 = 0,
};

pub const Layout = struct {
    slots: [max_slots]Slot = [_]Slot{.{}} ** max_slots,
    n: u8 = 0,
    content_h: i32 = 0,

    fn push(self: *Layout, hit: Hit, rect: geom.Rect, kind: SlotKind) void {
        if (self.n >= max_slots) return;
        self.slots[self.n] = .{ .hit = hit, .rect = rect, .kind = kind };
        self.n += 1;
    }

    fn pushAux(self: *Layout, hit: Hit, rect: geom.Rect, kind: SlotKind, aux: u8) void {
        if (self.n >= max_slots) return;
        self.slots[self.n] = .{ .hit = hit, .rect = rect, .kind = kind, .aux = aux };
        self.n += 1;
    }

    fn pushSeg(self: *Layout, hit: Hit, rect: geom.Rect, seg_n: u8) void {
        if (self.n >= max_slots) return;
        self.slots[self.n] = .{ .hit = hit, .rect = rect, .kind = .segment, .seg_n = seg_n };
        self.n += 1;
    }

    fn pushSlider(self: *Layout, hit: Hit, rect: geom.Rect, smin: u32, smax: u32) void {
        if (self.n >= max_slots) return;
        self.slots[self.n] = .{ .hit = hit, .rect = rect, .kind = .slider, .smin = smin, .smax = smax };
        self.n += 1;
    }
};

pub const HitResult = struct {
    hit: Hit = .none,
    seg: ?usize = null,
    slot_i: u8 = 0,
    aux: u8 = 0,
};

pub fn paint(logical: *fb.LogicalFb, theme: tokens.Theme, prefs: *const prefs_mod.Prefs, tab: usize, scroll: i32, mach_pull_t: f32) Layout {
    return switch (tab) {
        0 => paintCnc(logical, theme, prefs.cnc, scroll),
        3 => paintAudio(logical, theme, prefs.audio, scroll),
        4 => paintWireless(logical, theme, prefs.wireless, scroll),
        5 => paintPower(logical, theme, prefs.power, prefs.power_tel, prefs.system, scroll),
        6 => paintSecurity(logical, theme, prefs.security, scroll),
        7 => paintMachine(logical, theme, prefs.machine, prefs.cnc, scroll, mach_pull_t),
        8 => paintStorage(logical, theme, prefs, scroll),
        9 => paintSystem(logical, theme, prefs, scroll),
        else => .{},
    };
}

pub fn hitTest(lay: Layout, x: i32, y: i32) HitResult {
    var i: u8 = lay.n;
    while (i > 0) {
        i -= 1;
        const s = lay.slots[i];
        if (!s.rect.contains(x, y)) continue;
        if (s.kind == .segment) {
            if (form.segmentIndexAt(s.rect, s.seg_n, x, y)) |si| {
                return .{ .hit = s.hit, .seg = si, .slot_i = i, .aux = s.aux };
            }
            return .{ .hit = .none, .seg = null, .slot_i = i, .aux = s.aux };
        }
        return .{ .hit = s.hit, .seg = null, .slot_i = i, .aux = s.aux };
    }
    return .{};
}

/// Returns optional tab jump (rail index) for link rows.
pub fn applyHit(prefs: *prefs_mod.Prefs, hit: Hit, seg: ?usize, x: i32, y: i32, lay: Layout, slot_i: u8) ?usize {
    const slot: Slot = if (slot_i < lay.n) lay.slots[slot_i] else .{};
    switch (hit) {
        .none => {},
        // CNC
        .cnc_proto, .cnc_conn => {},
        .cnc_connect => prefs.cnc.startConnect(),
        .cnc_disconnect => if (prefs.cnc.sessionBusy()) prefs.cnc.disconnect(),
        .cnc_configure, .cnc_dump, .cnc_profiles, .cnc_reset => {},
        .cnc_ref => prefs.cnc.proto_ref_exp = !prefs.cnc.proto_ref_exp,
        .cnc_link_mach => return 7,
        .cnc_link_dash => return 1,
        .cnc_link_wl => return 4,
        .cnc_open_enow => {
            prefs.wireless.page = 3;
            return 4;
        },
        // Audio
        .aud_vol => if (prefs.audio.out_ready) {
            prefs.audio.vol = @intCast(form.sliderValueAt(slot.rect, 0, 100, x));
        },
        .aud_tsound => if (prefs.audio.out_ready) {
            prefs.audio.tsound = !prefs.audio.tsound;
        },
        .aud_tone => if (prefs.audio.out_ready) {
            if (seg) |i| prefs.audio.tone_prof = @intCast(i);
        },
        .aud_snd_up => prefs.audio.snd_up = !prefs.audio.snd_up,
        .aud_snd_dn => prefs.audio.snd_dn = !prefs.audio.snd_dn,
        .aud_mic => if (prefs.audio.in_ready) {
            if (seg) |i| prefs.audio.mic_gain = @intCast(i);
        },
        .aud_ref => prefs.audio.hw_ref_exp = !prefs.audio.hw_ref_exp,
        // Wireless
        .wl_back => prefs.wireless.page = if (prefs.wireless.page == 6 or prefs.wireless.page == 7) 1 else 0,
        .wl_wifi_page => prefs.wireless.page = 1,
        .wl_bt_page => prefs.wireless.page = 2,
        .wl_en_page => prefs.wireless.page = 3,
        .wl_zb_page => prefs.wireless.page = 4,
        .wl_th_page => prefs.wireless.page = 5,
        .wl_chips => {
            const chips = [_][]const u8{ "Wi-Fi", "BT", "ESP-NOW", "Zigbee", "Thread" };
            if (form.chipIndexAtXY(slot.rect, &chips, x, y)) |i| {
                prefs.wireless.page = @intCast(i + 1);
            }
        },
        .wl_ant => prefs.wireless.ant_ext = !prefs.wireless.ant_ext,
        .wl_hub_ref => prefs.wireless.hub_ref_exp = !prefs.wireless.hub_ref_exp,
        .wl_reset => {},
        .wl_wifi => {
            prefs.wireless.wifi = !prefs.wireless.wifi;
            if (!prefs.wireless.wifi) prefs.wireless.disconnectWifi();
        },
        .wl_bt => {
            prefs.wireless.bt = !prefs.wireless.bt;
            if (!prefs.wireless.bt) {
                prefs.wireless.clearBtPaired();
                prefs.wireless.bt_scan_phase = 0;
                prefs.wireless.bt_scan_n = 0;
            }
        },
        .wl_espnow => {
            prefs.wireless.espnow = !prefs.wireless.espnow;
            if (!prefs.wireless.espnow) {
                prefs.wireless.en_scan_phase = 0;
                prefs.wireless.en_peer_n = 0;
            }
        },
        .wl_zigbee => {
            prefs.wireless.zigbee = !prefs.wireless.zigbee;
            if (!prefs.wireless.zigbee) prefs.wireless.leaveZigbee();
        },
        .wl_thread => {
            prefs.wireless.thread = !prefs.wireless.thread;
            if (!prefs.wireless.thread) prefs.wireless.detachThread();
        },
        .wl_wf_auto => prefs.wireless.wf_auto = !prefs.wireless.wf_auto,
        .wl_wf_arecon => prefs.wireless.wf_arecon = !prefs.wireless.wf_arecon,
        .wl_wf_dhcp => prefs.wireless.wf_dhcp = !prefs.wireless.wf_dhcp,
        .wl_scan => {},
        .wl_adv => {
            if (prefs.wireless.page == 1) prefs.wireless.page = 7;
        },
        .wl_ssid => {},
        .wl_saved => prefs.wireless.page = 6,
        .wl_disconnect => prefs.wireless.disconnectWifi(),
        .wl_forget => prefs.wireless.forgetSaved(),
        .wl_connect_saved => prefs.wireless.connectSaved(),
        .wl_ap0 => prefs.wireless.connectAp(0),
        .wl_ap1 => prefs.wireless.connectAp(1),
        .wl_ap2 => prefs.wireless.connectAp(2),
        .wl_en_chan => {},
        .wl_en_enc => prefs.wireless.en_enc = !prefs.wireless.en_enc,
        .wl_en_rate => {},
        .wl_peer0 => prefs.wireless.setBridgePeer(0),
        .wl_peer1 => prefs.wireless.setBridgePeer(1),
        .wl_bt_disconnect => prefs.wireless.clearBtPaired(),
        .wl_bt_adv => prefs.wireless.bt_adv_exp = !prefs.wireless.bt_adv_exp,
        .wl_bt_dev0 => prefs.wireless.connectBt(0),
        .wl_bt_dev1 => prefs.wireless.connectBt(1),
        .wl_bt_clear => prefs.wireless.clearBtPaired(),
        .wl_zb_join => prefs.wireless.joinZigbee(),
        .wl_zb_leave => prefs.wireless.leaveZigbee(),
        .wl_th_attach => prefs.wireless.attachThread(),
        .wl_th_detach => prefs.wireless.detachThread(),
        .wl_zb_adv => prefs.wireless.zb_adv_exp = !prefs.wireless.zb_adv_exp,
        .wl_th_adv => prefs.wireless.th_adv_exp = !prefs.wireless.th_adv_exp,
        .wl_en_adv => prefs.wireless.en_adv_exp = !prefs.wireless.en_adv_exp,
        .wl_en_add_mac => {},
        .wl_en_saved0 => if (prefs.wireless.peerSaved(0)) prefs.wireless.setBridgePeer(0),
        .wl_en_saved1 => if (prefs.wireless.peerSaved(1)) prefs.wireless.setBridgePeer(1),
        .wl_en_rm0 => prefs.wireless.removeSavedPeer(0),
        .wl_en_rm1 => prefs.wireless.removeSavedPeer(1),
        .wl_en_clear_peers => prefs.wireless.clearSavedPeers(),
        .wl_zb_dev0 => if (prefs.wireless.zb_dev_n > 0) {
            prefs.wireless.zb_dev_on[0] = !prefs.wireless.zb_dev_on[0];
        },
        .wl_zb_dev1 => if (prefs.wireless.zb_dev_n > 1) {
            prefs.wireless.zb_dev_on[1] = !prefs.wireless.zb_dev_on[1];
        },
        .wl_zb_dev => {
            const idx = slot.aux;
            if (idx < prefs.wireless.zb_dev_on.len) {
                prefs.wireless.zb_dev_on[idx] = !prefs.wireless.zb_dev_on[idx];
            }
        },
        .wl_zb_identify, .wl_zb_remove, .wl_zb_refresh, .wl_zb_sensors => {},
        .wl_th_dev0 => if (prefs.wireless.th_dev_n > 0) {
            prefs.wireless.th_dev_on[0] = !prefs.wireless.th_dev_on[0];
        },
        .wl_zb_energy => prefs.wireless.startEnergyScan(),
        .wl_zb_clear => {
            prefs.wireless.zb_dev_n = 0;
        },
        .wl_th_clear => {
            prefs.wireless.th_dev_n = 0;
        },
        .wl_zb_add, .wl_th_add => {},
        .wl_link_ntp => return 9,
        .wl_link_cnc => return 0,
        // Power
        .pwr_ext5v => prefs.power.ext5v = !prefs.power.ext5v,
        .pwr_usb5v => prefs.power.usb5v = !prefs.power.usb5v,
        .pwr_dim => {},
        .pwr_scr => {},
        .pwr_sleep_now => {},
        .pwr_mode => if (seg) |i| {
            prefs.power.pwr_mode = @intCast(i);
        },
        .pwr_dsto => {},
        .pwr_wake_touch => prefs.power.wake_touch = !prefs.power.wake_touch,
        .pwr_wake_usb => prefs.power.wake_usb = !prefs.power.wake_usb,
        .pwr_wake_timer => prefs.power.wake_timer = !prefs.power.wake_timer,
        .pwr_wtmin => {},
        .pwr_gate_wifi => if (prefs.power.deepSleep()) {
            prefs.power.gate_wifi = !prefs.power.gate_wifi;
        },
        .pwr_gate_ext => if (prefs.power.deepSleep()) {
            prefs.power.gate_ext = !prefs.power.gate_ext;
        },
        .pwr_gate_usb => if (prefs.power.deepSleep()) {
            prefs.power.gate_usb = !prefs.power.gate_usb;
        },
        .pwr_bat_type => {},
        .pwr_warn => {},
        .pwr_chg => prefs.power.chg_en = !prefs.power.chg_en,
        .pwr_adapt => prefs.power.bat_adapt = !prefs.power.bat_adapt,
        .pwr_qc => prefs.power.qc = !prefs.power.qc,
        .pwr_ref => prefs.power.batt_ref_exp = !prefs.power.batt_ref_exp,
        .pwr_reset => {},
        .pwr_link_disp => return 2,
        // Security
        .sec_set_pin => {},
        .sec_clear_pin => {},
        .sec_tmo => {},
        .sec_boot => if (prefs.security.has_pin) {
            prefs.security.pin_boot = !prefs.security.pin_boot;
        },
        .sec_slp => if (prefs.security.has_pin) {
            prefs.security.setWake(!prefs.security.pin_slp);
        },
        .sec_idle => {},
        // Machine
        .mach_mxfeed => prefs.machine.mxfeed = @intCast(@max(100, form.sliderValueAt(slot.rect, 100, 20000, x))),
        .mach_mxrpm => prefs.machine.mxrpm = @intCast(@max(1000, form.sliderValueAt(slot.rect, 1000, 60000, x))),
        .mach_jogspd => prefs.machine.jogspd = @intCast(@max(100, form.sliderValueAt(slot.rect, 100, 10000, x))),
        .mach_feedovr => prefs.machine.feedovr = @intCast(@max(10, form.sliderValueAt(slot.rect, 10, 200, x))),
        .mach_spindovr => prefs.machine.spindovr = @intCast(@max(10, form.sliderValueAt(slot.rect, 10, 200, x))),
        .mach_slim => prefs.machine.slim = !prefs.machine.slim,
        .mach_trx => prefs.machine.tr_x = @intCast(@max(50, form.sliderValueAt(slot.rect, 50, 2000, x))),
        .mach_try => prefs.machine.tr_y = @intCast(@max(50, form.sliderValueAt(slot.rect, 50, 2000, x))),
        .mach_trz => prefs.machine.tr_z = @intCast(@max(10, form.sliderValueAt(slot.rect, 10, 1000, x))),
        .mach_tra => prefs.machine.tr_a = @intCast(@max(1, form.sliderValueAt(slot.rect, 1, 7200, x))),
        .mach_trb => prefs.machine.tr_b = @intCast(@max(1, form.sliderValueAt(slot.rect, 1, 7200, x))),
        .mach_trc => prefs.machine.tr_c = @intCast(@max(1, form.sliderValueAt(slot.rect, 1, 7200, x))),
        .mach_name => {},
        .mach_type => prefs.machine.mach_type = @intCast((prefs.machine.mach_type + 1) % @as(u8, prefs_mod.mach_type_names.len)),
        .mach_spcw => prefs.machine.spcw = !prefs.machine.spcw,
        .mach_pull, .mach_push, .mach_dump => {},
        .mach_mnt => {}, // legacy
        .mach_mnt_odo => {},
        .mach_mnt_sph => {},
        .mach_mnt_run => {},
        .mach_mnt_warn => {},
        .mach_meters => prefs.machine.meters_exp = !prefs.machine.meters_exp,
        .mach_svc_dt, .mach_svc_nt => {},
        .mach_mnt_reset => {},
        .mach_ref => prefs.machine.ref_exp = !prefs.machine.ref_exp,
        .mach_reset => {},
        .mach_link_cnc => return 0,
        .mach_link_dash => return 1,
        // Storage
        .stor_sd => {}, // engine: mount / confirm eject
        .stor_loglvl => if (seg) |i| {
            prefs.storage.loglvl = @intCast(i);
        },
        .stor_export, .stor_backup_exp, .stor_backup_imp, .stor_cache => {},
        .stor_ref => prefs.storage.ref_exp = !prefs.storage.ref_exp,
        .stor_i2c_exp => prefs.storage.i2c_exp = !prefs.storage.i2c_exp,
        .stor_i2c_all => prefs.storage.startI2cScan(0),
        .stor_i2c_mbus => prefs.storage.startI2cScan(2),
        .stor_i2c_porta => prefs.storage.startI2cScan(1),
        .stor_i2c_exp1 => prefs.storage.startI2cScan(3),
        .stor_i2c_exp2 => prefs.storage.startI2cScan(4),
        .stor_portmap => prefs.storage.portmap_exp = !prefs.storage.portmap_exp,
        .stor_i2c_ref => prefs.storage.i2c_ref_exp = !prefs.storage.i2c_ref_exp,
        // System
        .sys_h_c6, .sys_h_wifi => return 4,
        .sys_h_cnc => return 0,
        .sys_h_sd => return 8,
        .sys_h_batt => return 5,
        .sys_perf_hud => prefs.system.perf_hud = !prefs.system.perf_hud,
        .sys_lang => {},
        .sys_tz => {},
        .sys_t24 => if (seg) |i| {
            prefs.system.t_24h = i == 0;
        },
        .sys_datefmt => if (seg) |i| {
            prefs.system.datefmt = @intCast(i);
        },
        .sys_kb => prefs.system.kb_full = !prefs.system.kb_full,
        .sys_ntp => {
            prefs.system.setNtpEnabled(!prefs.system.ntp, prefs.wireless.wifi);
        },
        .sys_sync => {}, // engine: syncNow + snackbar
        .sys_manual, .sys_restart, .sys_shutdown => {},
        .sys_factory => factoryReset(prefs),
        .sys_ref => prefs.system.ref_exp = !prefs.system.ref_exp,
        .sys_link_stor => return 8,
    }
    return null;
}

pub fn factoryReset(prefs: *prefs_mod.Prefs) void {
    prefs.system.resetDefaults();
    prefs.cnc.resetDefaults();
    prefs.cnc.clearProfiles();
    prefs.audio.resetDefaults();
    prefs.wireless.resetDefaults();
    prefs.power.resetDefaults();
    prefs.security.resetDefaults();
    prefs.machine.resetDefaults();
    prefs.storage.resetDefaults();
    prefs.dash.resetDefaults();
    prefs.display.resetDefaults();
}

fn healthKinds(p: *const prefs_mod.Prefs) [5]form.StatusKind {
    const radio = p.wireless.wifi or p.wireless.bt or p.wireless.espnow or p.wireless.zigbee or p.wireless.thread;
    const c6: form.StatusKind = if (p.system.c6_ready) .ok else if (radio) .warn else .err;
    const wifi: form.StatusKind = if (p.wireless.wifi) .ok else if (radio) .warn else .err;
    const cnc: form.StatusKind = if (p.cnc.session_up) .ok else .warn;
    const sd: form.StatusKind = if (p.storage.sd_mounted) .ok else .warn;
    const batt: form.StatusKind = if (p.power_tel.bat_pct < 15) .err else if (p.power_tel.bat_pct < 30) .warn else .ok;
    return .{ c6, wifi, cnc, sd, batt };
}

fn healthLabels(kinds: *const [5]form.StatusKind) [5][]const u8 {
    const ok = [_][]const u8{ "C6", "Wi-Fi", "CNC", "SD", "Batt" };
    const bad = [_][]const u8{ "C6!", "Wi-Fi", "CNC", "SD", "Batt!" };
    var out: [5][]const u8 = undefined;
    for (0..5) |i| {
        out[i] = if (kinds[i] == .err) bad[i] else ok[i];
    }
    return out;
}

fn paintCnc(logical: *fb.LogicalFb, theme: tokens.Theme, c: prefs_mod.CncPrefs, scroll: i32) Layout {
    var cur: form.Cursor = .{};
    var lay: Layout = .{};
    const adv = form.isAdvanced();
    _ = form.paintModeToggle(logical, theme, &cur, scroll, adv);

    form.paintSection(logical, theme, &cur, scroll, "CNC & connection");

    form.paintSection(logical, theme, &cur, scroll, "Connection status");
    const sk: form.StatusKind = switch (c.sessionKind()) {
        .ok => .ok,
        .warn => .warn,
        .err => .err,
        .dim => .dim,
    };
    form.paintDetailStatus(logical, theme, &cur, scroll, "Session", c.sessionText(), sk);
    form.paintDetail(logical, theme, &cur, scroll, "Transport", c.connLabel());
    form.paintDetail(logical, theme, &cur, scroll, "Motion control", c.protoLabel());

    form.paintSection(logical, theme, &cur, scroll, "Motion control systems");
    lay.push(.cnc_proto, form.paintDropdown(logical, theme, &cur, scroll, "System", c.protoLabel()), .dropdown);
    switch (c.proto) {
        1 => form.paintNote(logical, theme, &cur, scroll, "Grbl 1.1: status ? handshake only. No $I+ or MPG/FAN RT."),
        2 => form.paintNote(logical, theme, &cur, scroll, "FluidNC: classic Grbl dialect. Prefer WebSocket to FluidNC IP."),
        3 => {
            form.paintNote(logical, theme, &cur, scroll, "linuxcncrsh over Telnet. Default port 5007.");
            form.paintNote(logical, theme, &cur, scroll, "Use Transport Telnet to LinuxCNC PC IP. Enable linuxcncrsh in INI.");
            form.paintDetail(logical, theme, &cur, scroll, "Connect password", "EMC");
            form.paintDetail(logical, theme, &cur, scroll, "Enable password", "EMCTOO");
        },
        4 => {
            form.paintNote(logical, theme, &cur, scroll, "MMBP text bridge: tools/mmbp_bridge on PC. Default Telnet port 7878.");
            form.paintNote(logical, theme, &cur, scroll, "Mach3/Mach4 have no native network API - run Modulus bridge on PC.");
        },
        5 => {
            form.paintNote(logical, theme, &cur, scroll, "Masso Link UDP - status/keepalive only. No jog/gcode in RE'd Link protocol.");
            form.paintNote(logical, theme, &cur, scroll, "DRO XYZ not in Link packets (shows --). Handwheel MPG disabled for Masso.");
            form.paintNote(logical, theme, &cur, scroll, "Do not run official Masso Link PC app at the same time (shared UDP 65535).");
            form.paintSection(logical, theme, &cur, scroll, "Masso Link");
            form.paintNote(logical, theme, &cur, scroll, "Wi-Fi via C6. UDP opens automatically for this MCS.");
            form.paintDetail(logical, theme, &cur, scroll, "Controller IP", c.massoIpSlice());
            form.paintDetail(logical, theme, &cur, scroll, "Serial (optional)", c.massoSnSlice());
            var txb: [8]u8 = undefined;
            var rxb: [8]u8 = undefined;
            form.paintDetail(logical, theme, &cur, scroll, "UDP send port", std.fmt.bufPrint(&txb, "{d}", .{c.masso_tx}) catch "?");
            form.paintDetail(logical, theme, &cur, scroll, "UDP recv port", std.fmt.bufPrint(&rxb, "{d}", .{c.masso_rx}) catch "?");
            form.paintNote(logical, theme, &cur, scroll, "Docs: send 11000-11050, recv 65535.");
        },
        else => {},
    }

    form.paintSection(logical, theme, &cur, scroll, "Active transport");
    lay.push(.cnc_conn, form.paintDropdown(logical, theme, &cur, scroll, "Transport", c.connLabel()), .dropdown);

    form.paintSection(logical, theme, &cur, scroll, "Actions");
    if (c.conn == 0 and !c.transport_off) {
        lay.push(.cnc_connect, form.paintAction(logical, theme, &cur, scroll, "Connect", if (c.session_up) "Connected" else "Apply & connect"), .action);
    } else {
        lay.push(.cnc_connect, form.paintAction(logical, theme, &cur, scroll, "Reconnect / test", "Apply & connect"), .action);
        var cfgbuf: [40]u8 = undefined;
        const cfg = std.fmt.bufPrint(&cfgbuf, "Configure {s}", .{c.connLabel()}) catch "Configure";
        lay.push(.cnc_configure, form.paintAction(logical, theme, &cur, scroll, cfg, ""), .action);
    }
    lay.push(.cnc_disconnect, form.paintActionState(logical, theme, &cur, scroll, "Disconnect", if (c.sessionBusy()) "Stop session" else "Already off", c.sessionBusy(), true), .action);

    if (adv) {
    if (c.conn == 0 and !c.transport_off) {
        form.paintSection(logical, theme, &cur, scroll, "ESP-NOW peer");
        form.paintNote(logical, theme, &cur, scroll, "Read-only bridge peer summary.");
        form.paintDetail(logical, theme, &cur, scroll, "MAC", c.espnowMacSlice());
        form.paintDetail(logical, theme, &cur, scroll, "Encryption", if (c.espnow_enc) "On" else "Off");
        form.paintDetail(logical, theme, &cur, scroll, "Radio", "Needs C6");
        form.paintDetail(logical, theme, &cur, scroll, "CNC transport", if (c.session_up) "Live" else "Idle (bridge only)");
        lay.push(.cnc_open_enow, form.paintAction(logical, theme, &cur, scroll, "Open wireless ESP-NOW", ""), .action);
    } else if (c.transportOn()) {
        form.paintSection(logical, theme, &cur, scroll, "Transport parameters");
        paintCncTransportParams(logical, theme, &cur, scroll, c);
    }

    form.paintSection(logical, theme, &cur, scroll, "Related settings");
    lay.push(.cnc_link_mach, form.paintAction(logical, theme, &cur, scroll, "Machine", "Open tab"), .action);
    lay.push(.cnc_link_dash, form.paintAction(logical, theme, &cur, scroll, "Dashboard & handwheel", "Open tab"), .action);
    lay.push(.cnc_link_wl, form.paintAction(logical, theme, &cur, scroll, "Wireless", "Open tab"), .action);

    if (c.proto_ref_exp) {
        form.paintDetail(logical, theme, &cur, scroll, "GrblHAL", "$I+ info, ENUMS, MPG/FAN RT, bracket reports");
        form.paintDetail(logical, theme, &cur, scroll, "Grbl", "Grbl 1.1f banner, ? status poll, $J= jog");
        form.paintDetail(logical, theme, &cur, scroll, "FluidNC", "Classic Grbl dialect; WebSocket preferred");
        form.paintDetail(logical, theme, &cur, scroll, "LinuxCNC", "linuxcncrsh: hello/enable, get poll, set jog/mdi");
        form.paintDetail(logical, theme, &cur, scroll, "LinuxCNC port", "Telnet default 5007 (linuxcncrsh)");
        form.paintDetail(logical, theme, &cur, scroll, "Masso", "Link UDP status (XYZ DRO not in Link packets)");
        form.paintDetail(logical, theme, &cur, scroll, "Mach3/Mach4", "MMBP: tools/mmbp_bridge Telnet 7878");
        form.paintDetail(logical, theme, &cur, scroll, "Grbl transport", "RS-485, Serial USB, Telnet, WebSocket");
        lay.push(.cnc_ref, form.paintAction(logical, theme, &cur, scroll, "Hide motion control reference", ""), .action);
    } else {
        lay.push(.cnc_ref, form.paintAction(logical, theme, &cur, scroll, "Show motion control reference", ""), .action);
    }

    form.paintSection(logical, theme, &cur, scroll, "Advanced");
    if (c.supportsDump()) {
        lay.push(.cnc_dump, form.paintAction(logical, theme, &cur, scroll, "Settings browser ($$)", "Read controller"), .action);
    } else {
        form.paintNote(logical, theme, &cur, scroll, "Settings browser ($$) is Grbl-family only (GrblHAL / Grbl / FluidNC).");
    }
    form.paintSection(logical, theme, &cur, scroll, "Connection profiles");
    form.paintNote(logical, theme, &cur, scroll, "Save/activate up to 4 machine setups.");
    var pbuf: [48]u8 = undefined;
    const pd = c.profileDetail(&pbuf);
    lay.push(.cnc_profiles, form.paintAction(logical, theme, &cur, scroll, "Manage profiles", pd), .action);
    form.paintSection(logical, theme, &cur, scroll, "Planned features");
    form.paintNote(logical, theme, &cur, scroll, "USB HID / Gamepad transport - coming soon");
    lay.push(.cnc_reset, form.paintDestructiveAction(logical, theme, &cur, scroll, "Reset CNC connection", "RS-485 defaults"), .action);
    }

    lay.content_h = cur.y + 40;
    return lay;
}

fn paintCncTransportParams(logical: *fb.LogicalFb, theme: tokens.Theme, cur: *form.Cursor, scroll: i32, c: prefs_mod.CncPrefs) void {
    var buf: [64]u8 = undefined;
    switch (c.conn) {
        1 => {
            const ep = std.fmt.bufPrint(&buf, "{s}:{d}{s}", .{ c.wsHostSlice(), c.ws_port, if (c.ws_tls) " (TLS)" else "" }) catch "?";
            form.paintDetail(logical, theme, cur, scroll, "Endpoint", ep);
        },
        2 => {
            const ep = std.fmt.bufPrint(&buf, "{s}:{d}", .{ c.tnHostSlice(), c.tn_port }) catch "?";
            form.paintDetail(logical, theme, cur, scroll, "Endpoint", ep);
        },
        3 => {
            const baud = std.fmt.bufPrint(&buf, "{s} baud", .{prefs_mod.CncPrefs.baudLabel(c.ser_baud_idx)}) catch "?";
            form.paintDetail(logical, theme, cur, scroll, "Serial", baud);
            form.paintDetail(logical, theme, cur, scroll, "Interface", "USB CDC");
        },
        4 => {
            const baud = std.fmt.bufPrint(&buf, "{s} baud", .{prefs_mod.CncPrefs.baudLabel(c.r4_baud_idx)}) catch "?";
            form.paintDetail(logical, theme, cur, scroll, "Serial", baud);
            form.paintDetail(logical, theme, cur, scroll, "Interface", "UART1 RS-485 (DE pin)");
        },
        5 => form.paintDetail(logical, theme, cur, scroll, "Device name", c.bleNameSlice()),
        6 => {
            const addr = std.fmt.bufPrint(&buf, "0x{X:0>2}", .{c.i2c_addr}) catch "?";
            form.paintDetail(logical, theme, cur, scroll, "Slave address", addr);
            form.paintDetail(logical, theme, cur, scroll, "Speed", if (c.i2c_spd == 0) "100 kHz" else "400 kHz");
        },
        7 => {
            const rates = [_][]const u8{ "125 Kbps", "250 Kbps", "500 Kbps", "1 Mbps" };
            form.paintDetail(logical, theme, cur, scroll, "Bitrate", rates[@min(c.can_brate, rates.len - 1)]);
            const nid = std.fmt.bufPrint(&buf, "{d}", .{c.can_nid}) catch "?";
            form.paintDetail(logical, theme, cur, scroll, "Node ID", nid);
        },
        else => form.paintDetail(logical, theme, cur, scroll, "Parameters", "Open configure"),
    }
}

fn paintAudio(logical: *fb.LogicalFb, theme: tokens.Theme, a: prefs_mod.AudioPrefs, scroll: i32) Layout {
    var cur: form.Cursor = .{};
    var lay: Layout = .{};
    const adv = form.isAdvanced();
    _ = form.paintModeToggle(logical, theme, &cur, scroll, adv);

    form.paintSection(logical, theme, &cur, scroll, "Audio & haptics");
    if (!a.out_ready) {
        form.paintDetailStatus(logical, theme, &cur, scroll, "Output", "Codec unavailable", .err);
    }
    form.paintSection(logical, theme, &cur, scroll, "Volume");
    if (a.out_ready) {
        lay.pushSlider(.aud_vol, form.paintSliderUnit(logical, theme, &cur, scroll, "Master volume", a.vol, 0, 100, "%"), 0, 100);
    } else {
        form.paintDetail(logical, theme, &cur, scroll, "Master volume", "--");
    }

    form.paintSection(logical, theme, &cur, scroll, "Touch feedback");
    lay.push(.aud_tsound, form.paintToggleState(logical, theme, &cur, scroll, "Touch sounds", a.tsound, a.out_ready), .toggle);
    if (a.out_ready) {
        lay.pushSeg(.aud_tone, form.paintSegment(logical, theme, &cur, scroll, "Tone profile", &prefs_mod.AudioPrefs.tone_labels, a.tone_prof), 4);
    } else {
        form.paintDetail(logical, theme, &cur, scroll, "Tone profile", a.toneLabel());
    }

    if (adv) {
        form.paintSection(logical, theme, &cur, scroll, "System sounds");
        lay.push(.aud_snd_up, form.paintToggle(logical, theme, &cur, scroll, "Startup sound", a.snd_up), .toggle);
        lay.push(.aud_snd_dn, form.paintToggle(logical, theme, &cur, scroll, "Shutdown sound", a.snd_dn), .toggle);

        form.paintSection(logical, theme, &cur, scroll, "Microphone");
        form.paintDetail(logical, theme, &cur, scroll, "System", "Dual Mic + AEC (ES7210)");
        if (!a.in_ready) {
            form.paintDetailStatus(logical, theme, &cur, scroll, "Input", "Codec unavailable", .err);
            form.paintDetail(logical, theme, &cur, scroll, "Microphone gain", a.gainLabel());
        } else {
            lay.pushSeg(.aud_mic, form.paintSegment(logical, theme, &cur, scroll, "Microphone gain", &prefs_mod.AudioPrefs.gain_labels, a.mic_gain), 5);
        }

        if (a.hw_ref_exp) {
            form.paintDetail(logical, theme, &cur, scroll, "Codec", "ES8388 DAC/ADC");
            form.paintDetail(logical, theme, &cur, scroll, "AEC front-end", "ES7210 (4-ch ADC)");
            form.paintDetail(logical, theme, &cur, scroll, "Speaker", "1W @ 8 ohm (NS4150B)");
            form.paintDetail(logical, theme, &cur, scroll, "Headphone", "3.5mm Jack");
            form.paintDetailStatus(logical, theme, &cur, scroll, "Headphone jack", if (a.hp_inserted) "Inserted" else "Not connected", if (a.hp_inserted) form.StatusKind.ok else .dim);
            lay.push(.aud_ref, form.paintAction(logical, theme, &cur, scroll, "Hide hardware reference", ""), .action);
        } else {
            lay.push(.aud_ref, form.paintAction(logical, theme, &cur, scroll, "Show hardware reference", ""), .action);
        }
    }
    lay.content_h = cur.y + 40;
    return lay;
}

fn paintWireless(logical: *fb.LogicalFb, theme: tokens.Theme, w: prefs_mod.WirelessPrefs, scroll: i32) Layout {
    var cur: form.Cursor = .{};
    var lay: Layout = .{};
    const wl_chips = [_][]const u8{ "Wi-Fi", "BT", "ESP-NOW", "Zigbee", "Thread" };
    switch (w.page) {
        1 => { // Wi-Fi hub
            lay.push(.wl_back, form.paintBackRow(logical, theme, &cur, scroll, "Wireless"), .action);
            lay.push(.wl_chips, form.paintChipRow(logical, theme, &cur, scroll, &wl_chips, 0), .action);
            form.paintSection(logical, theme, &cur, scroll, "Status");
            form.paintDetailStatus(logical, theme, &cur, scroll, "Radio", w.wifiStatusSlice(), if (w.wifi_conn) form.StatusKind.ok else if (w.wifi_connecting) .warn else if (w.wifi) .warn else .dim);
            form.paintDetail(logical, theme, &cur, scroll, "SSID", if (w.wifi_conn or w.wifi_connecting) w.ssidSlice() else "--");
            form.paintDetail(logical, theme, &cur, scroll, "IP address", if (w.wifi_conn) w.ipSlice() else "--");
            lay.push(.wl_wifi, form.paintToggle(logical, theme, &cur, scroll, "Wi-Fi radio", w.wifi), .toggle);
            lay.push(.wl_ssid, form.paintAction(logical, theme, &cur, scroll, "Enter SSID", if (w.ssidSlice().len > 0) w.ssidSlice() else "Manual"), .action);
            form.paintSection(logical, theme, &cur, scroll, "Networks");
            form.paintDetail(logical, theme, &cur, scroll, "Scan", w.scanText());
            lay.push(.wl_scan, form.paintActionState(logical, theme, &cur, scroll, "Scan for networks", if (w.scan_phase == 1) "Scanning..." else if (w.wifi) "" else "Enable radio", w.wifi or w.scan_phase == 1, false), .action);
            // Show APs even while connected (LVGL parity) so Scan is not a no-op after auto-connect.
            if (w.scan_phase == 2 and w.scan_n > 0) {
                form.paintSection(logical, theme, &cur, scroll, "Results");
                form.paintNote(logical, theme, &cur, scroll, if (w.wifi_conn) "Tap to switch network" else "Tap to connect");
                var i: u8 = 0;
                const max_show: u8 = @min(w.scan_n, 3); // Hit slots wl_ap0..2
                while (i < max_show) : (i += 1) {
                    const name = w.apLabel(i);
                    var sup: [40]u8 = undefined;
                    const support = if (w.live_ap_n > 0)
                        (std.fmt.bufPrint(&sup, "AP {d}", .{i + 1}) catch "AP")
                    else
                        "Tap to connect";
                    const hit: Hit = switch (i) {
                        0 => .wl_ap0,
                        1 => .wl_ap1,
                        else => .wl_ap2,
                    };
                    const label = if (name.len > 0) name else "(hidden)";
                    lay.push(hit, form.paintTwoLineAction(logical, theme, &cur, scroll, label, support), .action);
                }
            } else if (w.scan_phase == 2 and w.scan_n == 0) {
                form.paintSection(logical, theme, &cur, scroll, "Results");
                const empty: []const u8 = if (w.scan_c6_down)
                    "C6 offline - dual-flash C6"
                else
                    "No networks found";
                form.paintDetailStatus(logical, theme, &cur, scroll, "Status", empty, if (w.scan_c6_down) .warn else .dim);
            }
            if (w.wifi_conn) {
                lay.push(.wl_disconnect, form.paintDestructiveAction(logical, theme, &cur, scroll, "Disconnect", ""), .action);
            }
            lay.push(.wl_saved, form.paintAction(logical, theme, &cur, scroll, "Saved networks", ""), .action);
            lay.push(.wl_link_ntp, form.paintAction(logical, theme, &cur, scroll, "Time sync (NTP)", "System tab"), .action);
            lay.push(.wl_adv, form.paintAction(logical, theme, &cur, scroll, "Advanced", "IP / reconnect"), .action);
        },
        6 => { // Saved
            lay.push(.wl_back, form.paintBackRow(logical, theme, &cur, scroll, "Wi-Fi"), .action);
            form.paintSection(logical, theme, &cur, scroll, "Saved");
            if (w.has_saved) {
                form.paintDetail(logical, theme, &cur, scroll, "SSID", w.savedSsidSlice());
                form.paintDetail(logical, theme, &cur, scroll, "Auto-connect", if (w.wf_auto) "On" else "Off");
                lay.push(.wl_connect_saved, form.paintAction(logical, theme, &cur, scroll, "Connect now", ""), .action);
                lay.push(.wl_forget, form.paintDestructiveAction(logical, theme, &cur, scroll, "Forget network", ""), .action);
            } else {
                form.paintDetailStatus(logical, theme, &cur, scroll, "Status", "No saved network", .dim);
            }
            if (w.wifi_conn) {
                lay.push(.wl_disconnect, form.paintDestructiveAction(logical, theme, &cur, scroll, "Disconnect", ""), .action);
            }
        },
        7 => { // Wi-Fi advanced
            lay.push(.wl_back, form.paintBackRow(logical, theme, &cur, scroll, "Wi-Fi"), .action);
            form.paintSection(logical, theme, &cur, scroll, "Advanced");
            lay.push(.wl_wf_arecon, form.paintToggle(logical, theme, &cur, scroll, "Auto-reconnect", w.wf_arecon), .toggle);
            lay.push(.wl_wf_auto, form.paintToggle(logical, theme, &cur, scroll, "Auto-connect saved", w.wf_auto), .toggle);
            form.paintSection(logical, theme, &cur, scroll, "IP config");
            form.paintDetail(logical, theme, &cur, scroll, "Mode", if (w.wf_dhcp) "DHCP" else "Static");
            lay.push(.wl_wf_dhcp, form.paintToggle(logical, theme, &cur, scroll, "Use DHCP", w.wf_dhcp), .toggle);
            form.paintNote(logical, theme, &cur, scroll, "Static IP / DNS - coming soon on device.");
        },
        2 => { // BT
            lay.push(.wl_back, form.paintBackRow(logical, theme, &cur, scroll, "Wireless"), .action);
            lay.push(.wl_chips, form.paintChipRow(logical, theme, &cur, scroll, &wl_chips, 1), .action);
            form.paintSection(logical, theme, &cur, scroll, "Status");
            form.paintDetailStatus(logical, theme, &cur, scroll, "Radio", w.btStatusSlice(), if (w.bt_conn) form.StatusKind.ok else if (w.bt_connecting) .warn else if (w.bt) form.StatusKind.ok else .dim);
            form.paintDetail(logical, theme, &cur, scroll, "Paired", w.pairedText());
            lay.push(.wl_bt, form.paintToggle(logical, theme, &cur, scroll, "Bluetooth radio", w.bt), .toggle);
            if (!w.bt) {
                form.paintNote(logical, theme, &cur, scroll, "Enable radio for BLE discovery and pairing.");
            } else {
                form.paintSection(logical, theme, &cur, scroll, "Paired devices");
                form.paintDetail(logical, theme, &cur, scroll, "Saved", w.pairedText());
                if (w.bt_conn) {
                    lay.push(.wl_bt_disconnect, form.paintDestructiveAction(logical, theme, &cur, scroll, "Disconnect", ""), .action);
                }
                form.paintSection(logical, theme, &cur, scroll, "Discovery");
                form.paintNote(logical, theme, &cur, scroll, "Tap device to connect");
                const scan_lbl: []const u8 = switch (w.bt_scan_phase) {
                    1 => "Scanning...",
                    2 => if (w.bt_scan_n == 0) "No devices found" else "Done",
                    else => "Idle",
                };
                form.paintDetail(logical, theme, &cur, scroll, "Scan", scan_lbl);
                if (w.bt_scan_phase == 2) {
                    if (w.bt_scan_n > 0) {
                        var rssi0: [16]u8 = undefined;
                        const s0 = std.fmt.bufPrint(&rssi0, "{d} dBm", .{w.btRssi(0)}) catch "? dBm";
                        lay.push(.wl_bt_dev0, form.paintTwoLineAction(logical, theme, &cur, scroll, w.btLabel(0), s0), .action);
                    }
                    if (w.bt_scan_n > 1) {
                        var rssi1: [16]u8 = undefined;
                        const s1 = std.fmt.bufPrint(&rssi1, "{d} dBm", .{w.btRssi(1)}) catch "? dBm";
                        lay.push(.wl_bt_dev1, form.paintTwoLineAction(logical, theme, &cur, scroll, w.btLabel(1), s1), .action);
                    }
                }
                lay.push(.wl_scan, form.paintActionState(logical, theme, &cur, scroll, "Scan for devices", if (w.bt_scan_phase == 1) "Scanning..." else if (w.bt) "" else "Enable radio", w.bt or w.bt_scan_phase == 1, false), .action);
                if (w.bt_adv_exp) {
                    form.paintSection(logical, theme, &cur, scroll, "Power");
                    _ = form.paintActionState(logical, theme, &cur, scroll, "Turn off when idle", "Coming soon", false, false);
                    _ = form.paintActionState(logical, theme, &cur, scroll, "Background scanning", "Coming soon", false, false);
                    form.paintSection(logical, theme, &cur, scroll, "Security");
                    _ = form.paintActionState(logical, theme, &cur, scroll, "Require pairing confirmation", "Coming soon", false, false);
                    _ = form.paintActionState(logical, theme, &cur, scroll, "Block unknown devices", "Coming soon", false, false);
                    form.paintSection(logical, theme, &cur, scroll, "Troubleshooting");
                    lay.push(.wl_bt_clear, form.paintAction(logical, theme, &cur, scroll, "Clear paired devices", ""), .action);
                    lay.push(.wl_bt_adv, form.paintAction(logical, theme, &cur, scroll, "Hide advanced", ""), .action);
                } else {
                    lay.push(.wl_bt_adv, form.paintAction(logical, theme, &cur, scroll, "Advanced", ""), .action);
                }
            }
        },
        3 => { // ESP-NOW
            lay.push(.wl_back, form.paintBackRow(logical, theme, &cur, scroll, "Wireless"), .action);
            lay.push(.wl_chips, form.paintChipRow(logical, theme, &cur, scroll, &wl_chips, 2), .action);
            form.paintSection(logical, theme, &cur, scroll, "Status");
            form.paintDetailStatus(logical, theme, &cur, scroll, "Radio", prefs_mod.WirelessPrefs.radioLabel(w.espnow), if (w.espnow) form.StatusKind.ok else .dim);
            form.paintDetail(logical, theme, &cur, scroll, "Bridge peer", w.bridgeSlice());
            var chbuf: [24]u8 = undefined;
            form.paintDetail(logical, theme, &cur, scroll, "Channel", std.fmt.bufPrint(&chbuf, "{s} (match bridge)", .{w.chanLabel()}) catch w.chanLabel());
            lay.push(.wl_espnow, form.paintToggle(logical, theme, &cur, scroll, "ESP-NOW radio", w.espnow), .toggle);
            if (!w.espnow) {
                form.paintNote(logical, theme, &cur, scroll, "Enable radio for peer discovery and bridge.");
            } else {
                const en_scan: []const u8 = switch (w.en_scan_phase) {
                    1 => "Scanning...",
                    2 => if (w.en_peer_n > 0) "Done" else "Done (none)",
                    else => "Idle",
                };
                form.paintDetail(logical, theme, &cur, scroll, "Scan", en_scan);
                lay.push(.wl_scan, form.paintAction(logical, theme, &cur, scroll, "Scan for peers", if (w.en_scan_phase == 1) "..." else ""), .action);
                if (w.en_scan_phase == 2 and w.en_peer_n > 0) {
                    form.paintSection(logical, theme, &cur, scroll, "Discovered");
                    form.paintNote(logical, theme, &cur, scroll, "Tap to save + use");
                    lay.push(.wl_peer0, form.paintTwoLineAction(logical, theme, &cur, scroll, w.enPeerLabel(0), "Save + use as bridge"), .action);
                    if (w.en_peer_n > 1) {
                        lay.push(.wl_peer1, form.paintTwoLineAction(logical, theme, &cur, scroll, w.enPeerLabel(1), "Save + use as bridge"), .action);
                    }
                }
                form.paintSection(logical, theme, &cur, scroll, "Saved peers");
                form.paintNote(logical, theme, &cur, scroll, "Tap MAC to use; Remove deletes from list");
                var any_saved = false;
                if (w.peerSaved(0)) {
                    any_saved = true;
                    if (w.en_active == 0) {
                        lay.push(.wl_en_saved0, form.paintActionAccent(logical, theme, &cur, scroll, w.enSavedLabel(0), "Active"), .action);
                    } else {
                        lay.push(.wl_en_saved0, form.paintTwoLineAction(logical, theme, &cur, scroll, w.enSavedLabel(0), "Tap to use"), .action);
                    }
                    lay.push(.wl_en_rm0, form.paintDestructiveAction(logical, theme, &cur, scroll, "Remove", w.enSavedLabel(0)), .action);
                }
                if (w.peerSaved(1)) {
                    any_saved = true;
                    if (w.en_active == 1) {
                        lay.push(.wl_en_saved1, form.paintActionAccent(logical, theme, &cur, scroll, w.enSavedLabel(1), "Active"), .action);
                    } else {
                        lay.push(.wl_en_saved1, form.paintTwoLineAction(logical, theme, &cur, scroll, w.enSavedLabel(1), "Tap to use"), .action);
                    }
                    lay.push(.wl_en_rm1, form.paintDestructiveAction(logical, theme, &cur, scroll, "Remove", w.enSavedLabel(1)), .action);
                }
                if (!any_saved) {
                    form.paintDetailStatus(logical, theme, &cur, scroll, "Status", "None saved", .dim);
                } else {
                    lay.push(.wl_en_clear_peers, form.paintDestructiveAction(logical, theme, &cur, scroll, "Clear all saved peers", ""), .action);
                }
                lay.push(.wl_en_add_mac, form.paintAction(logical, theme, &cur, scroll, "Add MAC manually", ""), .action);
                form.paintSection(logical, theme, &cur, scroll, "Traffic");
                var traf: [32]u8 = undefined;
                form.paintDetail(logical, theme, &cur, scroll, "CNC TX / RX", std.fmt.bufPrint(&traf, "{d} / {d}", .{ w.en_tx, w.en_rx }) catch "0 / 0");
                form.paintNote(logical, theme, &cur, scroll, "Counters track CNC traffic when transport is ESP-NOW.");
                lay.push(.wl_link_cnc, form.paintAction(logical, theme, &cur, scroll, "CNC Connection tab", "Configure"), .action);
                if (w.en_adv_exp) {
                    form.paintSection(logical, theme, &cur, scroll, "Advanced");
                    lay.push(.wl_en_chan, form.paintDropdown(logical, theme, &cur, scroll, "Channel", w.chanLabel()), .dropdown);
                    lay.push(.wl_en_rate, form.paintDropdown(logical, theme, &cur, scroll, "PHY rate", w.rateLabel()), .dropdown);
                    lay.push(.wl_en_enc, form.paintToggle(logical, theme, &cur, scroll, "PMK encryption", w.en_enc), .toggle);
                    form.paintDetail(logical, theme, &cur, scroll, "PMK", "MODULUS_ENOW_PMK (fixed)");
                    lay.push(.wl_en_adv, form.paintAction(logical, theme, &cur, scroll, "Hide advanced", ""), .action);
                } else {
                    lay.push(.wl_en_adv, form.paintAction(logical, theme, &cur, scroll, "Advanced", ""), .action);
                }
            }
        },
        4, 5 => {
            lay.push(.wl_back, form.paintBackRow(logical, theme, &cur, scroll, "Wireless"), .action);
            lay.push(.wl_chips, form.paintChipRow(logical, theme, &cur, scroll, &wl_chips, if (w.page == 4) @as(usize, 3) else 4), .action);
            const zb = w.page == 4;
            const on = if (zb) w.zigbee else w.thread;
            form.paintSection(logical, theme, &cur, scroll, "Status");
            if (zb) {
                const zb_st = w.zbStatusSlice();
                const zb_ok = w.zb_joined or std.mem.indexOf(u8, zb_st, "Joined") != null;
                form.paintDetailStatus(logical, theme, &cur, scroll, "Radio", zb_st, if (zb_ok) form.StatusKind.ok else if (w.zb_join_pending) .warn else if (w.zigbee) .warn else .dim);
                form.paintDetail(logical, theme, &cur, scroll, "Network", w.zbNetworkSlice());
                form.paintDetail(logical, theme, &cur, scroll, "Pairing", if (w.zb_scan_phase == 1) "Open" else "Closed");
                lay.push(.wl_zigbee, form.paintToggle(logical, theme, &cur, scroll, "Radio enable", w.zigbee), .toggle);
            } else {
                form.paintDetailStatus(logical, theme, &cur, scroll, "Radio", prefs_mod.WirelessPrefs.radioLabel(on), if (on) form.StatusKind.ok else .dim);
            }
            if (zb) {
                if (w.zigbee) {
                    form.paintSection(logical, theme, &cur, scroll, "Network control");
                    lay.push(.wl_zb_join, if (w.zb_joined) form.paintActionAccent(logical, theme, &cur, scroll, "Join network", "Joined") else if (w.zb_join_pending) form.paintAction(logical, theme, &cur, scroll, "Join network", "Joining...") else form.paintAction(logical, theme, &cur, scroll, "Join network", ""), .action);
                    lay.push(.wl_zb_leave, form.paintAction(logical, theme, &cur, scroll, "Leave network", ""), .action);
                    if (!w.zb_joined) {
                        form.paintNote(logical, theme, &cur, scroll, "Join the network first, then pair devices.");
                    }
                    form.paintSection(logical, theme, &cur, scroll, "Discovery");
                    form.paintNote(logical, theme, &cur, scroll, if (w.zb_joined) "Opens the network - put device in pairing mode" else "Tap to save device");
                    const zs: []const u8 = switch (w.zb_scan_phase) {
                        1 => "Scanning...",
                        2 => if (w.zb_scan_n == 0) "No devices" else "Done",
                        else => "Idle",
                    };
                    form.paintDetail(logical, theme, &cur, scroll, "Scan", zs);
                    if (w.zb_scan_phase == 2 and w.zb_scan_n > 0) {
                        var cnt: [24]u8 = undefined;
                        form.paintDetail(logical, theme, &cur, scroll, "Found", std.fmt.bufPrint(&cnt, "{d} device(s)", .{w.zb_scan_n}) catch "?");
                    }
                    lay.push(.wl_scan, form.paintAction(logical, theme, &cur, scroll, if (w.zb_joined) "Pair devices (permit join)" else "Scan for devices", if (w.zb_scan_phase == 1) "..." else ""), .action);
                    lay.push(.wl_zb_add, form.paintAction(logical, theme, &cur, scroll, "Add with install code", ""), .action);
                    form.paintSection(logical, theme, &cur, scroll, "Saved devices");
                    form.paintNote(logical, theme, &cur, scroll, "On/Off, Identify, Remove - NanoH2 hub");
                    if (w.zb_dev_n == 0 and w.live_zb_n == 0) {
                        form.paintDetailStatus(logical, theme, &cur, scroll, "Status", "None saved", .dim);
                    } else {
                        const show_n = @min(@as(usize, if (w.live_zb_n > 0) w.live_zb_n else w.zb_dev_n), w.live_zb.len);
                        var di: usize = 0;
                        while (di < show_n) : (di += 1) {
                            const dev_on = if (di < w.zb_dev_on.len) w.zb_dev_on[di] else false;
                            lay.pushAux(.wl_zb_dev, form.paintToggle(logical, theme, &cur, scroll, w.zbDevLabel(di), dev_on), .toggle, @intCast(di));
                            lay.pushAux(.wl_zb_identify, form.paintAction(logical, theme, &cur, scroll, "Identify", "blink 5s"), .action, @intCast(di));
                            lay.pushAux(.wl_zb_remove, form.paintDestructiveAction(logical, theme, &cur, scroll, "Remove device", ""), .action, @intCast(di));
                            if (form.isAdvanced()) {
                                lay.pushAux(.wl_zb_sensors, form.paintAction(logical, theme, &cur, scroll, "Read sensors / LQI", ""), .action, @intCast(di));
                            }
                        }
                    }
                    lay.push(.wl_zb_refresh, form.paintAction(logical, theme, &cur, scroll, "Refresh device list", "Ask hub"), .action);
                    if (w.zb_adv_exp) {
                        form.paintSection(logical, theme, &cur, scroll, "Radio");
                        form.paintDetail(logical, theme, &cur, scroll, "Control path", "NanoH2 UART (ESP32-H2)");
                        form.paintDetail(logical, theme, &cur, scroll, "Link", if (w.zb_joined) "Up + joined" else w.zbStatusSlice());
                        form.paintDetail(logical, theme, &cur, scroll, "Energy scan", w.energyText());
                        lay.push(.wl_zb_energy, form.paintAction(logical, theme, &cur, scroll, "Scan channel energy", ""), .action);
                        form.paintNote(logical, theme, &cur, scroll, "Pick quietest 802.15.4 channel before (re)forming hub.");
                        form.paintSection(logical, theme, &cur, scroll, "Troubleshooting");
                        lay.push(.wl_zb_clear, form.paintDestructiveAction(logical, theme, &cur, scroll, "Clear saved devices", ""), .action);
                        lay.push(.wl_zb_adv, form.paintAction(logical, theme, &cur, scroll, "Hide advanced", ""), .action);
                    } else {
                        lay.push(.wl_zb_adv, form.paintAction(logical, theme, &cur, scroll, "Advanced", ""), .action);
                    }
                } else {
                    form.paintNote(logical, theme, &cur, scroll, "Enable radio for network and device control.");
                }
            } else if (!w.thread_supported) {
                form.paintNote(logical, theme, &cur, scroll, "Thread not supported on this C6 image.");
            } else {
                form.paintDetail(logical, theme, &cur, scroll, "Network", if (w.th_attached) "Attached" else "None");
                lay.push(.wl_thread, form.paintToggle(logical, theme, &cur, scroll, "Radio enable", w.thread), .toggle);
                if (w.thread) {
                    form.paintSection(logical, theme, &cur, scroll, "Network control");
                    lay.push(.wl_th_attach, if (w.th_attached) form.paintActionAccent(logical, theme, &cur, scroll, "Attach network", "Attached") else form.paintAction(logical, theme, &cur, scroll, "Attach network", ""), .action);
                    lay.push(.wl_th_detach, form.paintAction(logical, theme, &cur, scroll, "Detach network", ""), .action);
                    if (!w.th_attached) {
                        form.paintNote(logical, theme, &cur, scroll, "Attach Thread network for device refresh.");
                    }
                    form.paintSection(logical, theme, &cur, scroll, "Discovery");
                    form.paintNote(logical, theme, &cur, scroll, "Tap to save node");
                    lay.push(.wl_scan, form.paintAction(logical, theme, &cur, scroll, "Refresh nodes", if (w.th_scan_phase == 1) "..." else ""), .action);
                    lay.push(.wl_th_add, form.paintAction(logical, theme, &cur, scroll, "Add node manually", ""), .action);
                    form.paintSection(logical, theme, &cur, scroll, "Saved devices");
                    form.paintNote(logical, theme, &cur, scroll, "Toggle on/off");
                    if (w.th_dev_n == 0 and w.live_th_n == 0) {
                        form.paintDetailStatus(logical, theme, &cur, scroll, "Status", "None saved", .dim);
                    } else {
                        lay.push(.wl_th_dev0, form.paintToggle(logical, theme, &cur, scroll, w.thDevLabel(0), w.th_dev_on[0]), .toggle);
                        form.paintNote(logical, theme, &cur, scroll, "Clear devices in Advanced.");
                    }
                    if (w.th_adv_exp) {
                        form.paintSection(logical, theme, &cur, scroll, "Radio");
                        form.paintDetail(logical, theme, &cur, scroll, "Control path", if (w.th_attached) "Attached" else "Cache only");
                        form.paintNote(logical, theme, &cur, scroll, "Matter/CoAP ON/OFF needs C6 border router RPC.");
                        form.paintSection(logical, theme, &cur, scroll, "Troubleshooting");
                        lay.push(.wl_th_clear, form.paintDestructiveAction(logical, theme, &cur, scroll, "Clear saved devices", ""), .action);
                        lay.push(.wl_th_adv, form.paintAction(logical, theme, &cur, scroll, "Hide advanced", ""), .action);
                    } else {
                        lay.push(.wl_th_adv, form.paintAction(logical, theme, &cur, scroll, "Advanced", ""), .action);
                    }
                } else {
                    form.paintNote(logical, theme, &cur, scroll, "Enable radio for network and device control.");
                }
            }
        },
        else => { // Hub — LVGL action-row layout
            const adv = form.isAdvanced();
            _ = form.paintModeToggle(logical, theme, &cur, scroll, adv);
            form.paintSection(logical, theme, &cur, scroll, "Wireless protocols");
            form.paintNote(logical, theme, &cur, scroll, "ESP32-C6 co-processor via SDIO2.");
            lay.push(.wl_wifi_page, if (w.wifi) form.paintActionAccent(logical, theme, &cur, scroll, "Wi-Fi", "On") else form.paintAction(logical, theme, &cur, scroll, "Wi-Fi", ""), .action);
            lay.push(.wl_bt_page, if (w.bt) form.paintActionAccent(logical, theme, &cur, scroll, "Bluetooth", "On") else form.paintAction(logical, theme, &cur, scroll, "Bluetooth", ""), .action);
            if (adv) {
                lay.push(.wl_en_page, if (w.espnow) form.paintActionAccent(logical, theme, &cur, scroll, "ESP-NOW", "On") else form.paintAction(logical, theme, &cur, scroll, "ESP-NOW", ""), .action);
                form.paintSection(logical, theme, &cur, scroll, "802.15.4 radios");
                lay.push(.wl_zb_page, if (w.zigbee) form.paintActionAccent(logical, theme, &cur, scroll, "Zigbee", "On") else form.paintAction(logical, theme, &cur, scroll, "Zigbee", ""), .action);
                if (w.thread_supported) {
                    lay.push(.wl_th_page, if (w.thread) form.paintActionAccent(logical, theme, &cur, scroll, "Thread", "On") else form.paintAction(logical, theme, &cur, scroll, "Thread", ""), .action);
                }
                form.paintSection(logical, theme, &cur, scroll, "Antenna");
                form.paintDetail(logical, theme, &cur, scroll, "Active", if (w.ant_ext) "External MMCX" else "Internal PCB");
                lay.push(.wl_ant, form.paintToggle(logical, theme, &cur, scroll, "External MMCX", w.ant_ext), .toggle);
                if (w.hub_ref_exp) {
                    form.paintDetail(logical, theme, &cur, scroll, "Module", "ESP32-C6-MINI-1U");
                    form.paintDetail(logical, theme, &cur, scroll, "Transport", "ESP-Hosted SDIO2");
                    const ch_note = if (w.thread_supported) "ESP-NOW=8 Zigbee=9 Thread=10" else "ESP-NOW=8 Zigbee=9";
                    form.paintDetail(logical, theme, &cur, scroll, "Channels", ch_note);
                    lay.push(.wl_hub_ref, form.paintAction(logical, theme, &cur, scroll, "Hide radio reference", ""), .action);
                } else {
                    lay.push(.wl_hub_ref, form.paintAction(logical, theme, &cur, scroll, "Show radio reference", ""), .action);
                }
                lay.push(.wl_reset, form.paintDestructiveAction(logical, theme, &cur, scroll, "Reset network defaults", ""), .action);
            }
        },
    }
    lay.content_h = cur.y + 40;
    return lay;
}

fn paintPower(logical: *fb.LogicalFb, theme: tokens.Theme, p: prefs_mod.PowerPrefs, tel: prefs_mod.PowerTelemetry, sys: prefs_mod.SystemPrefs, scroll: i32) Layout {
    var cur: form.Cursor = .{};
    var lay: Layout = .{};
    const adv = form.isAdvanced();
    const deep = p.deepSleep();
    const wake_tm = p.wake_timer;
    _ = form.paintModeToggle(logical, theme, &cur, scroll, adv);

    form.paintSection(logical, theme, &cur, scroll, "Power");
    form.paintSection(logical, theme, &cur, scroll, "Battery status");
    if (tel.ina_ok) {
        var pctbuf: [12]u8 = undefined;
        var vbuf: [16]u8 = undefined;
        var ibuf: [16]u8 = undefined;
        var wbuf: [16]u8 = undefined;
        var rbuf: [32]u8 = undefined;
        var ebuf: [32]u8 = undefined;
        var tbuf: [16]u8 = undefined;
        const pct_kind: form.StatusKind = if (tel.charge_state == 1)
            .ok
        else if (tel.charge_state == 2)
            .ok
        else if (tel.bat_pct <= 20)
            .err
        else if (tel.bat_pct <= 50)
            .warn
        else
            .ok;
        const st_kind: form.StatusKind = if (tel.charge_state == 1)
            .ok
        else if (tel.charge_state == 2)
            .ok
        else if (tel.charge_state == 3)
            .warn
        else if (tel.bat_pct <= 20)
            .err
        else if (tel.bat_pct <= 50)
            .warn
        else
            .dim;
        form.paintDetailStatus(logical, theme, &cur, scroll, "Charge", tel.formatPct(&pctbuf), pct_kind);
        form.paintDetailStatus(logical, theme, &cur, scroll, "State", tel.chargeStateLabel(), st_kind);
        form.paintDetail(logical, theme, &cur, scroll, "Voltage", tel.formatVolt(&vbuf));
        form.paintDetail(logical, theme, &cur, scroll, "Current", tel.formatCurr(&ibuf));
        form.paintDetail(logical, theme, &cur, scroll, "Power", tel.formatPower(&wbuf));
        form.paintDetail(logical, theme, &cur, scroll, "Charge rate", tel.formatRate(&rbuf));
        form.paintDetail(logical, theme, &cur, scroll, "Time remaining", tel.formatEta(&ebuf));
        form.paintDetail(logical, theme, &cur, scroll, "SoC temperature", tel.formatTemp(&tbuf));
    } else {
        form.paintDetailStatus(logical, theme, &cur, scroll, "Battery", "Monitor unavailable", .err);
    }
    var upbuf: [24]u8 = undefined;
    form.paintDetail(logical, theme, &cur, scroll, "Since boot", sys.formatUptime(&upbuf));

    form.paintSection(logical, theme, &cur, scroll, "Power rails");
    lay.push(.pwr_ext5v, form.paintToggle(logical, theme, &cur, scroll, "EXT 5V output", p.ext5v), .toggle);
    lay.push(.pwr_usb5v, form.paintToggle(logical, theme, &cur, scroll, "USB 5V output", p.usb5v), .toggle);

    form.paintSection(logical, theme, &cur, scroll, "Display sleep");
    lay.push(.pwr_dim, form.paintDropdown(logical, theme, &cur, scroll, "Dim display after", p.dimLabel()), .dropdown);
    lay.push(.pwr_scr, form.paintDropdown(logical, theme, &cur, scroll, "Screen timeout", p.scrLabel()), .dropdown);
    lay.push(.pwr_link_disp, form.paintAction(logical, theme, &cur, scroll, "Display & theme", "Open tab"), .action);

    form.paintSection(logical, theme, &cur, scroll, "Actions");
    lay.push(.pwr_sleep_now, form.paintAction(logical, theme, &cur, scroll, "Sleep now", "Enter deep sleep"), .action);

    if (adv) {
    form.paintSection(logical, theme, &cur, scroll, "System sleep");
    const modes = [_][]const u8{ "Display only", "Deep sleep" };
    lay.pushSeg(.pwr_mode, form.paintSegment(logical, theme, &cur, scroll, "Sleep mode", &modes, p.pwr_mode), 2);
    lay.push(.pwr_dsto, form.paintDropdownState(logical, theme, &cur, scroll, "Deep sleep after", p.dstoLabel(), deep), .dropdown);
    lay.push(.pwr_wake_touch, form.paintToggle(logical, theme, &cur, scroll, "Wake on touch", p.wake_touch), .toggle);
    lay.push(.pwr_wake_usb, form.paintToggle(logical, theme, &cur, scroll, "Wake on USB-C", p.wake_usb), .toggle);
    lay.push(.pwr_wake_timer, form.paintToggle(logical, theme, &cur, scroll, "Wake on timer", p.wake_timer), .toggle);
    lay.push(.pwr_wtmin, form.paintDropdownState(logical, theme, &cur, scroll, "Auto-wake timer", p.wtminLabel(), wake_tm), .dropdown);
    lay.push(.pwr_gate_wifi, form.paintToggleState(logical, theme, &cur, scroll, "Gate Wi-Fi in sleep", p.gate_wifi, deep), .toggle);
    lay.push(.pwr_gate_ext, form.paintToggleState(logical, theme, &cur, scroll, "Gate EXT 5V in sleep", p.gate_ext, deep), .toggle);
    lay.push(.pwr_gate_usb, form.paintToggleState(logical, theme, &cur, scroll, "Gate USB 5V in sleep", p.gate_usb, deep), .toggle);

    form.paintSection(logical, theme, &cur, scroll, "Battery behavior");
    lay.push(.pwr_bat_type, form.paintDropdown(logical, theme, &cur, scroll, "Battery pack", p.batTypeLabel()), .dropdown);
    lay.push(.pwr_warn, form.paintDropdown(logical, theme, &cur, scroll, "Warn at", p.warnLabel()), .dropdown);
    lay.push(.pwr_chg, form.paintToggle(logical, theme, &cur, scroll, "Enable charging", p.chg_en), .toggle);
    lay.push(.pwr_adapt, form.paintToggle(logical, theme, &cur, scroll, "Adaptive battery", p.bat_adapt), .toggle);
    lay.push(.pwr_qc, form.paintToggle(logical, theme, &cur, scroll, "Quick charge (QC 2.0/3)", p.qc), .toggle);

    if (p.batt_ref_exp) {
        form.paintDetail(logical, theme, &cur, scroll, "Compatible packs", "NP-F330 / F530 / F550 / F750 / F770 / F960 / F970");
        form.paintDetail(logical, theme, &cur, scroll, "Percent source", "Charge current + voltage curve");
        form.paintDetail(logical, theme, &cur, scroll, "Chemistry", "Li-ion 2S (7.2V nominal)");
        form.paintDetail(logical, theme, &cur, scroll, "Voltage range", "6.0V empty - 8.4V full");
        form.paintDetail(logical, theme, &cur, scroll, "Charge IC", "IP2326");
        form.paintDetail(logical, theme, &cur, scroll, "Monitor", "INA226 (0x41)");
        form.paintDetail(logical, theme, &cur, scroll, "Adaptive battery", "Tightens dim/timeout on battery");
        form.paintDetail(logical, theme, &cur, scroll, "SoC temperature", "ESP32-P4 die (not pack thermistor)");
        lay.push(.pwr_ref, form.paintAction(logical, theme, &cur, scroll, "Hide battery reference", ""), .action);
    } else {
        lay.push(.pwr_ref, form.paintAction(logical, theme, &cur, scroll, "Show battery reference", ""), .action);
    }
    lay.push(.pwr_reset, form.paintDestructiveAction(logical, theme, &cur, scroll, "Reset power settings", ""), .action);
    }
    lay.content_h = cur.y + 40;
    return lay;
}

fn paintSecurity(logical: *fb.LogicalFb, theme: tokens.Theme, s: prefs_mod.SecurityPrefs, scroll: i32) Layout {
    var cur: form.Cursor = .{};
    var lay: Layout = .{};
    const has = s.has_pin;
    const adv = form.isAdvanced();
    _ = form.paintModeToggle(logical, theme, &cur, scroll, adv);

    form.paintSection(logical, theme, &cur, scroll, "Security");
    form.paintSection(logical, theme, &cur, scroll, "Device lock");
    form.paintDetailStatus(logical, theme, &cur, scroll, "Lock status", if (s.locked) "Locked" else "Unlocked", if (s.locked) form.StatusKind.warn else .ok);
    form.paintDetailStatus(logical, theme, &cur, scroll, "PIN", if (has) "Configured" else "Not set", if (has) form.StatusKind.dim else .err);
    lay.push(.sec_set_pin, form.paintAction(logical, theme, &cur, scroll, if (has) "Change PIN" else "Set PIN", if (has) "Update" else "Create"), .action);
    lay.push(.sec_clear_pin, form.paintActionState(logical, theme, &cur, scroll, "Clear PIN", if (has) "Remove" else "Not set", has, true), .action);

    form.paintSection(logical, theme, &cur, scroll, "Auto lock");
    form.paintNote(logical, theme, &cur, scroll, "After display sleep. Never disables wake lock.");
    lay.push(.sec_tmo, form.paintDropdownState(logical, theme, &cur, scroll, "Lock after sleep", s.tmoLabel(), has), .dropdown);

    form.paintSection(logical, theme, &cur, scroll, "Session policy");
    form.paintNote(logical, theme, &cur, scroll, "Enabling requires confirm - remember your PIN.");
    lay.push(.sec_boot, form.paintToggleState(logical, theme, &cur, scroll, "Require PIN after boot", s.pin_boot, has), .toggle);
    lay.push(.sec_slp, form.paintToggleState(logical, theme, &cur, scroll, "Require PIN after sleep", s.pin_slp, has), .toggle);

    if (adv) {
        form.paintSection(logical, theme, &cur, scroll, "Idle lock");
        form.paintNote(logical, theme, &cur, scroll, "While display stays on.");
        var idbuf: [24]u8 = undefined;
        lay.push(.sec_idle, form.paintActionState(logical, theme, &cur, scroll, "Configure idle lock", s.formatIdleDetail(&idbuf), has, false), .action);
    }
    lay.content_h = cur.y + 40;
    return lay;
}

fn paintMachine(logical: *fb.LogicalFb, theme: tokens.Theme, m: prefs_mod.MachinePrefs, c: prefs_mod.CncPrefs, scroll: i32, mach_pull_t: f32) Layout {
    var cur: form.Cursor = .{};
    var lay: Layout = .{};
    const adv = form.isAdvanced();
    _ = form.paintModeToggle(logical, theme, &cur, scroll, adv);

    form.paintSection(logical, theme, &cur, scroll, "Machine");
    form.paintSection(logical, theme, &cur, scroll, "Work envelope");
    form.paintNote(logical, theme, &cur, scroll, "Limits enforced on jog and overrides.");
    lay.pushSlider(.mach_mxfeed, form.paintSliderUnit(logical, theme, &cur, scroll, "Max feed rate", m.mxfeed, 100, 20000, "mm/min"), 100, 20000);
    lay.pushSlider(.mach_mxrpm, form.paintSliderUnit(logical, theme, &cur, scroll, "Max spindle RPM", m.mxrpm, 1000, 60000, "RPM"), 1000, 60000);
    lay.pushSlider(.mach_jogspd, form.paintSliderUnit(logical, theme, &cur, scroll, "Default jog speed", m.jogspd, 100, 10000, "mm/min"), 100, 10000);
    if (adv) {
        lay.pushSlider(.mach_feedovr, form.paintSliderUnit(logical, theme, &cur, scroll, "Default feed override", m.feedovr, 10, 200, "%"), 10, 200);
        lay.pushSlider(.mach_spindovr, form.paintSliderUnit(logical, theme, &cur, scroll, "Default spindle override", m.spindovr, 10, 200, "%"), 10, 200);

        form.paintSection(logical, theme, &cur, scroll, "Pendant soft limits");
        form.paintNote(logical, theme, &cur, scroll, "Confirm before enabling or changing travel.");
        lay.push(.mach_slim, form.paintToggle(logical, theme, &cur, scroll, "Soft limit enforcement", m.slim), .toggle);
        lay.pushSlider(.mach_trx, form.paintSliderUnit(logical, theme, &cur, scroll, "Max travel X", m.tr_x, 50, 2000, "mm"), 50, 2000);
        lay.pushSlider(.mach_try, form.paintSliderUnit(logical, theme, &cur, scroll, "Max travel Y", m.tr_y, 50, 2000, "mm"), 50, 2000);
        lay.pushSlider(.mach_trz, form.paintSliderUnit(logical, theme, &cur, scroll, "Max travel Z", m.tr_z, 10, 1000, "mm"), 10, 1000);
        lay.pushSlider(.mach_tra, form.paintSliderUnit(logical, theme, &cur, scroll, "Max travel A", m.tr_a, 1, 7200, "deg"), 1, 7200);
        lay.pushSlider(.mach_trb, form.paintSliderUnit(logical, theme, &cur, scroll, "Max travel B", m.tr_b, 1, 7200, "deg"), 1, 7200);
        lay.pushSlider(.mach_trc, form.paintSliderUnit(logical, theme, &cur, scroll, "Max travel C", m.tr_c, 1, 7200, "deg"), 1, 7200);
        form.paintNote(logical, theme, &cur, scroll, "A/B/C soft limits in degrees. Unused axes: leave default 360.");
    }

    form.paintSection(logical, theme, &cur, scroll, "Controller sync");
    var mcsbuf: [48]u8 = undefined;
    const mcs = std.fmt.bufPrint(&mcsbuf, "Active MCS: {s}", .{c.protoLabel()}) catch "MCS";
    form.paintNote(logical, theme, &cur, scroll, mcs);
    const proto = c.proto;
    if (proto <= 2) {
        // GrblHAL / Grbl / FluidNC
        const pulling = mach_pull_t > 0;
        const pull_detail: []const u8 = if (pulling) "Pulling..." else "$110/$30/$130-135";
        lay.push(.mach_pull, form.paintActionState(logical, theme, &cur, scroll, "Pull from controller", pull_detail, !pulling, false), .action);
        if (pulling) form.paintProgressTrack(logical, theme, &cur, scroll, mach_pull_t);
        lay.push(.mach_push, form.paintAction(logical, theme, &cur, scroll, "Push to controller", "$110-$112, $30"), .action);
        lay.push(.mach_dump, form.paintAction(logical, theme, &cur, scroll, "Settings browser ($$)", "Read all $nn"), .action);
    } else if (proto == 3) {
        const pulling = mach_pull_t > 0;
        const pull_detail: []const u8 = if (pulling) "Pulling..." else "INI TRAJ/AXIS -> pendant";
        lay.push(.mach_pull, form.paintActionState(logical, theme, &cur, scroll, "Pull from controller", pull_detail, !pulling, false), .action);
        if (pulling) form.paintProgressTrack(logical, theme, &cur, scroll, mach_pull_t);
        form.paintNote(logical, theme, &cur, scroll, "linuxcncrsh INI pull (no $$). Sliders remain source of truth if keys missing.");
    } else if (proto == 4) {
        form.paintNote(logical, theme, &cur, scroll, "No remote INI on Mach3. Paste $110/$30/$130 lines or set sliders.");
        form.paintNote(logical, theme, &cur, scroll, "Paste format: $110=4000  $30=18000  $130=610 (one per line).");
    } else if (proto == 5) {
        var masso: [64]u8 = undefined;
        const ms = std.fmt.bufPrint(&masso, "{s} UDP {d}/{d}", .{ cstrSlice(&c.masso_ip), c.masso_tx, c.masso_rx }) catch "Masso";
        form.paintDetail(logical, theme, &cur, scroll, "Masso Link", ms);
        form.paintNote(logical, theme, &cur, scroll, "UDP status live. Envelope is pendant-local.");
        lay.push(.mach_link_cnc, form.paintAction(logical, theme, &cur, scroll, "CNC connection", "Edit Masso fields"), .action);
    } else {
        form.paintNote(logical, theme, &cur, scroll, "Controller sync not available for this MCS yet.");
    }

    form.paintSection(logical, theme, &cur, scroll, "Machine identity");
    lay.push(.mach_name, form.paintAction(logical, theme, &cur, scroll, "Machine name", m.nameSlice()), .action);
    lay.push(.mach_type, form.paintDropdown(logical, theme, &cur, scroll, "Machine type", m.typeLabel()), .dropdown);
    var linkbuf: [48]u8 = undefined;
    const link = std.fmt.bufPrint(&linkbuf, "{s} / {s}", .{ c.protoLabel(), c.connLabel() }) catch "link";
    form.paintDetail(logical, theme, &cur, scroll, "Controller link", link);
    if (proto != 5) {
        lay.push(.mach_link_cnc, form.paintAction(logical, theme, &cur, scroll, "CNC connection", "Edit transport"), .action);
    }

    form.paintSection(logical, theme, &cur, scroll, "Spindle");
    lay.push(.mach_spcw, form.paintToggle(logical, theme, &cur, scroll, "Allow CCW (M4)", m.spcw), .toggle);

    form.paintSection(logical, theme, &cur, scroll, "Maintenance");
    form.paintNote(logical, theme, &cur, scroll, "Accrues from jog/run motion, spindle-on time, and program RUN.");
    var tbuf: [24]u8 = undefined;
    var tpbuf: [32]u8 = undefined;
    var spbuf: [32]u8 = undefined;
    var rpbuf: [32]u8 = undefined;
    form.paintDetail(logical, theme, &cur, scroll, "Path travel", m.formatTravel(&tbuf));
    form.paintDetail(logical, theme, &cur, scroll, "Travel service", prefs_mod.MachinePrefs.formatServicePct(m.odo_mm, m.odoLimitMm(), &tpbuf));
    form.paintDetail(logical, theme, &cur, scroll, "Spindle service", prefs_mod.MachinePrefs.formatServicePct(m.sph_sec, m.sphLimitSec(), &spbuf));
    form.paintDetail(logical, theme, &cur, scroll, "Run service", prefs_mod.MachinePrefs.formatServicePct(m.run_sec, m.runLimitSec(), &rpbuf));
    if (m.meters_exp) {
        var xb: [24]u8 = undefined;
        var yb: [24]u8 = undefined;
        var zb: [24]u8 = undefined;
        const third = m.odo_mm / 3;
        form.paintDetail(logical, theme, &cur, scroll, "Travel X (stub)", std.fmt.bufPrint(&xb, "{d} mm", .{third}) catch "?");
        form.paintDetail(logical, theme, &cur, scroll, "Travel Y (stub)", std.fmt.bufPrint(&yb, "{d} mm", .{third}) catch "?");
        form.paintDetail(logical, theme, &cur, scroll, "Travel Z (stub)", std.fmt.bufPrint(&zb, "{d} mm", .{third}) catch "?");
        var sb: [24]u8 = undefined;
        var rb: [24]u8 = undefined;
        form.paintDetail(logical, theme, &cur, scroll, "Spindle on", prefs_mod.MachinePrefs.formatDuration(m.sph_sec, &sb));
        form.paintDetail(logical, theme, &cur, scroll, "Program run", prefs_mod.MachinePrefs.formatDuration(m.run_sec, &rb));
        lay.push(.mach_meters, form.paintAction(logical, theme, &cur, scroll, "Hide maintenance meters", ""), .action);
    } else {
        lay.push(.mach_meters, form.paintAction(logical, theme, &cur, scroll, "Maintenance meters", "Axes + times"), .action);
    }
    lay.push(.mach_svc_dt, form.paintAction(logical, theme, &cur, scroll, "Last service", blk: {
        const s = m.svcDtSlice();
        if (s.len == 0 or std.mem.eql(u8, s, "Not set")) break :blk "YYYY-MM-DD";
        break :blk s;
    }), .action);
    lay.push(.mach_svc_nt, form.paintAction(logical, theme, &cur, scroll, "Service notes", blk: {
        const s = m.svcNtSlice();
        if (s.len == 0) break :blk "Add note";
        break :blk s;
    }), .action);
    lay.push(.mach_mnt_odo, form.paintDropdown(logical, theme, &cur, scroll, "Travel interval", prefs_mod.MachinePrefs.mnt_odo_labels[@min(m.mnt_odo_idx, prefs_mod.MachinePrefs.mnt_odo_labels.len - 1)]), .dropdown);
    lay.push(.mach_mnt_sph, form.paintDropdown(logical, theme, &cur, scroll, "Spindle interval", prefs_mod.MachinePrefs.mnt_hours_labels[@min(m.mnt_sph_idx, prefs_mod.MachinePrefs.mnt_hours_labels.len - 1)]), .dropdown);
    lay.push(.mach_mnt_run, form.paintDropdown(logical, theme, &cur, scroll, "Run-time interval", prefs_mod.MachinePrefs.mnt_hours_labels[@min(m.mnt_run_idx, prefs_mod.MachinePrefs.mnt_hours_labels.len - 1)]), .dropdown);
    lay.push(.mach_mnt_warn, form.paintDropdown(logical, theme, &cur, scroll, "Warn at", prefs_mod.MachinePrefs.mnt_warn_labels[@min(m.mnt_warn_idx, prefs_mod.MachinePrefs.mnt_warn_labels.len - 1)]), .dropdown);
    form.paintNote(logical, theme, &cur, scroll, "Warn fires once per threshold. Off = no service interval.");
    lay.push(.mach_mnt_reset, form.paintDestructiveAction(logical, theme, &cur, scroll, "Reset counters", ""), .action);

    form.paintSection(logical, theme, &cur, scroll, "Related settings");
    lay.push(.mach_link_dash, form.paintAction(logical, theme, &cur, scroll, "Dashboard & handwheel", "Open tab"), .action);

    form.paintSection(logical, theme, &cur, scroll, "Grbl / GrblHAL reference");
    if (m.ref_exp) {
        form.paintDetail(logical, theme, &cur, scroll, "$130 / $131 / $132", "Max travel: X / Y / Z (mm)");
        form.paintDetail(logical, theme, &cur, scroll, "$133 / $134 / $135", "Max travel: A / B / C (deg)");
        form.paintDetail(logical, theme, &cur, scroll, "$110 / $111 / $112", "Max rate: X / Y / Z (mm/min)");
        form.paintDetail(logical, theme, &cur, scroll, "$120 / $121 / $122", "Acceleration: X / Y / Z (mm/s2)");
        form.paintDetail(logical, theme, &cur, scroll, "$22", "Homing cycle enable");
        form.paintDetail(logical, theme, &cur, scroll, "$23", "Homing direction invert mask");
        form.paintDetail(logical, theme, &cur, scroll, "$20", "Soft limits enable (controller)");
        form.paintNote(logical, theme, &cur, scroll, "Pendant soft limits clamp jog before $J= is sent.");
        form.paintNote(logical, theme, &cur, scroll, "Feed, spindle, and jog limits above apply on the pendant side.");
        lay.push(.mach_ref, form.paintAction(logical, theme, &cur, scroll, "Hide reference", ""), .action);
    } else {
        lay.push(.mach_ref, form.paintAction(logical, theme, &cur, scroll, "Show reference", ""), .action);
    }
    lay.push(.mach_reset, form.paintDestructiveAction(logical, theme, &cur, scroll, "Reset machine settings", ""), .action);
    lay.content_h = cur.y + 40;
    return lay;
}

fn cstrSlice(raw: []const u8) []const u8 {
    var len: usize = 0;
    while (len < raw.len and raw[len] != 0) : (len += 1) {}
    return raw[0..len];
}

fn storMemKind(free_n: u32, total_n: u32) form.StatusKind {
    if (total_n == 0) return .dim;
    const pct = (free_n * 100) / total_n;
    if (pct < 10) return .err;
    if (pct < 25) return .warn;
    return .ok;
}

fn storSdKind(s: prefs_mod.SdState) form.StatusKind {
    return switch (s) {
        .mounted => .ok,
        .failed => .err,
        .unmounted => .dim,
    };
}

const k_port_map = [_]struct { title: []const u8, detail: []const u8 }{
    .{ .title = "Port A Grove (4p)", .detail = "GND | EXT5V | G53 SDA | G54 SCL" },
    .{ .title = "Port A power", .detail = "EXT5V from PI4IOE1 P2 - Power tab" },
    .{ .title = "Port A CAN mode", .detail = "TWAI TX G54 RX G53 - conflicts I2C1" },
    .{ .title = "ExtPort2 (6p)", .detail = "GND | HVIN | 485A/B | G31/G32" },
    .{ .title = "Int I2C0 (M-Bus)", .detail = "G31 SDA G32 SCL onboard + ExtPort2" },
    .{ .title = "ExtPort1 (10p)", .detail = "HVIN GND 3V3 G1 G50 / EXT5V G0 G49" },
    .{ .title = "RS-485 SIT3088", .detail = "UART1 TX G20 RX G21 DE G34" },
    .{ .title = "M5-Bus rear (30p)", .detail = "E-stop G16; I2C 17-18; SPI/UART" },
    .{ .title = "USB Type-A host", .detail = "GND D+ D- USB5V out" },
    .{ .title = "USB Type-C OTG", .detail = "USB1 D+ D- GND 5VIN" },
    .{ .title = "COM.X STAMP", .detail = "G46 G6 G31 G32 G33 G19 G18 G5" },
};

fn paintStorage(logical: *fb.LogicalFb, theme: tokens.Theme, prefs: *const prefs_mod.Prefs, scroll: i32) Layout {
    const s = prefs.storage;
    const usb5v = prefs.power.usb5v;
    const ext5v = prefs.power.ext5v;
    var cur: form.Cursor = .{};
    var lay: Layout = .{};
    const adv = form.isAdvanced();
    _ = form.paintModeToggle(logical, theme, &cur, scroll, adv);

    form.paintSection(logical, theme, &cur, scroll, "Storage & diagnostics");
    form.paintSection(logical, theme, &cur, scroll, "microSD card");
    form.paintDetailStatus(logical, theme, &cur, scroll, "Status", s.sdStatus(), storSdKind(s.sd));
    var cap_buf: [48]u8 = undefined;
    form.paintDetail(logical, theme, &cur, scroll, "Capacity", s.sdCapacity(&cap_buf));
    const sd_act: []const u8 = switch (s.sd) {
        .mounted => "Eject",
        .failed => "Retry",
        .unmounted => "Mount",
    };
    lay.push(.stor_sd, form.paintAction(logical, theme, &cur, scroll, "SD card", sd_act), .action);

    if (adv) {
    form.paintSection(logical, theme, &cur, scroll, "Memory");
    form.paintNote(logical, theme, &cur, scroll, "Live heap telemetry.");
    var ibuf: [40]u8 = undefined;
    var pbuf: [40]u8 = undefined;
    var lbuf: [48]u8 = undefined;
    var mbuf: [24]u8 = undefined;
    form.paintDetailStatus(logical, theme, &cur, scroll, "Internal SRAM", prefs_mod.StoragePrefs.formatMemPair(&ibuf, s.int_free_kb, s.int_total_kb, "KB"), storMemKind(s.int_free_kb, s.int_total_kb));
    form.paintDetailStatus(logical, theme, &cur, scroll, "PSRAM", prefs_mod.StoragePrefs.formatMemPair(&pbuf, s.ps_free_mb, s.ps_total_mb, "MB"), storMemKind(s.ps_free_mb, s.ps_total_mb));
    form.paintDetail(logical, theme, &cur, scroll, "CLIB + PSRAM", s.formatLvgl(&lbuf));
    form.paintDetail(logical, theme, &cur, scroll, "Min free ever", s.formatMinFree(&mbuf));

    form.paintSection(logical, theme, &cur, scroll, "Logging & diagnostics");
    const lvls = [_][]const u8{ "Off", "Err", "Warn", "Info", "Dbg", "Verb" };
    lay.pushSeg(.stor_loglvl, form.paintSegment(logical, theme, &cur, scroll, "Log level", &lvls, s.loglvl), 6);
    const exp_en = s.sd == .mounted;
    lay.push(.stor_export, form.paintActionState(logical, theme, &cur, scroll, "Export diagnostics", s.diagDetail(), exp_en, false), .action);

    form.paintSection(logical, theme, &cur, scroll, "Settings backup");
    form.paintNote(logical, theme, &cur, scroll, "JSON on SD (passwords excluded by default).");
    lay.push(.stor_backup_exp, form.paintActionState(logical, theme, &cur, scroll, "Export settings", s.backupExportDetail(), exp_en, false), .action);
    lay.push(.stor_backup_imp, form.paintActionState(logical, theme, &cur, scroll, "Import settings", if (exp_en) "Tap to confirm" else "Insert SD card", exp_en, false), .action);
    form.paintNote(logical, theme, &cur, scroll, "Does not include PIN hash or WiFi password.");
    lay.push(.stor_cache, form.paintAction(logical, theme, &cur, scroll, "Clear UI cache", "Refresh draw buffers"), .action);

    form.paintSection(logical, theme, &cur, scroll, "USB host");
    form.paintNote(logical, theme, &cur, scroll, "VBUS is Power tab; host stack enumerates when rail is on.");
    const usb_host_txt: []const u8 = if (s.usb_host)
        "Device linked"
    else if (!usb5v)
        "VBUS off"
    else
        "No device";
    const usb_host_kind: form.StatusKind = if (s.usb_host) .ok else .dim;
    form.paintDetailStatus(logical, theme, &cur, scroll, "Host data", usb_host_txt, usb_host_kind);
    form.paintDetailStatus(logical, theme, &cur, scroll, "Type-A VBUS", if (usb5v) "On (Power tab)" else "Off", if (usb5v) form.StatusKind.ok else .dim);

    form.paintSection(logical, theme, &cur, scroll, "Storage reference");
    if (s.ref_exp) {
        form.paintDetail(logical, theme, &cur, scroll, "Flash chip", "16 MB");
        form.paintDetail(logical, theme, &cur, scroll, "SD interface", "SDMMC 4-bit @ /sdcard");
        form.paintDetail(logical, theme, &cur, scroll, "USB host", "Type-A USB 2.0");
        lay.push(.stor_ref, form.paintAction(logical, theme, &cur, scroll, "Hide reference details", ""), .action);
    } else {
        lay.push(.stor_ref, form.paintAction(logical, theme, &cur, scroll, "Show reference details", ""), .action);
    }

    if (s.i2c_exp) {
        lay.push(.stor_i2c_exp, form.paintAction(logical, theme, &cur, scroll, "Hide I2C bus diagnostics", ""), .action);
        lay.push(.stor_i2c_all, form.paintAction(logical, theme, &cur, scroll, "Scan all buses", "Tap to scan"), .action);
        lay.push(.stor_i2c_mbus, form.paintAction(logical, theme, &cur, scroll, "Scan M-Bus", "Tap to scan"), .action);
        lay.push(.stor_i2c_porta, form.paintAction(logical, theme, &cur, scroll, "Scan Port A", "Tap to scan"), .action);
        lay.push(.stor_i2c_exp1, form.paintAction(logical, theme, &cur, scroll, "Scan EXP1 PI4IOE", "Tap to scan"), .action);
        lay.push(.stor_i2c_exp2, form.paintAction(logical, theme, &cur, scroll, "Scan EXP2 PI4IOE", "Tap to scan"), .action);
        form.paintDetailStatus(logical, theme, &cur, scroll, "Scanner", s.i2cStatusText(), if (s.i2c_scan_phase == 1) form.StatusKind.warn else .dim);
        form.paintDetail(logical, theme, &cur, scroll, "Port A Grove I2C1", s.i2cResult(1));
        form.paintDetail(logical, theme, &cur, scroll, "Int I2C0 M-Bus", s.i2cResult(2));
        form.paintDetail(logical, theme, &cur, scroll, "EXP1 PI4IOE1", s.i2cResult(3));
        form.paintDetail(logical, theme, &cur, scroll, "EXP2 PI4IOE2", s.i2cResult(4));
        form.paintDetailStatus(logical, theme, &cur, scroll, "Port A EXT5V rail", if (ext5v) "On (Grove pin 2 powered)" else "Enable in Power settings", if (ext5v) form.StatusKind.ok else .warn);

        if (s.portmap_exp) {
            for (k_port_map) |row| {
                form.paintDetail(logical, theme, &cur, scroll, row.title, row.detail);
            }
            lay.push(.stor_portmap, form.paintAction(logical, theme, &cur, scroll, "Hide expansion port map", ""), .action);
        } else {
            lay.push(.stor_portmap, form.paintAction(logical, theme, &cur, scroll, "Show expansion port map", ""), .action);
        }

        if (s.i2c_ref_exp) {
            form.paintDetail(logical, theme, &cur, scroll, "RS-485 UART1", "TX G20 RX G21 DE G34");
            form.paintDetail(logical, theme, &cur, scroll, "Int I2C0 pins", "SDA G31 SCL G32");
            form.paintDetail(logical, theme, &cur, scroll, "Port A I2C1 pins", "SDA G53 SCL G54 (STD_GPIO mux)");
            form.paintDetail(logical, theme, &cur, scroll, "Port A note", "Schematic STD_GPIO = matrix pin; fw uses I2C1");
            form.paintDetail(logical, theme, &cur, scroll, "ExtPort2 I2C tap", "Same Int I2C0 (G31/G32)");
            form.paintDetail(logical, theme, &cur, scroll, "M5-Bus Int I2C", "Pins 17-18 = G31/G32");
            form.paintDetail(logical, theme, &cur, scroll, "Known addrs", "ES8388 0x10 ES7210 0x40 GT911 0x14 ST7123 0x55");
            form.paintDetail(logical, theme, &cur, scroll, "Known addrs 2", "BMI270 0x68 RX8130 0x32 INA226 0x41 PI4IOE 0x43/0x44");
            form.paintDetail(logical, theme, &cur, scroll, "Port A module", "ExtEncoder 0x59 (handwheel MPG)");
            lay.push(.stor_i2c_ref, form.paintAction(logical, theme, &cur, scroll, "Hide bus details", ""), .action);
        } else {
            lay.push(.stor_i2c_ref, form.paintAction(logical, theme, &cur, scroll, "Show bus details", ""), .action);
        }
    } else {
        lay.push(.stor_i2c_exp, form.paintAction(logical, theme, &cur, scroll, "Show I2C bus diagnostics", ""), .action);
    }
    }

    lay.content_h = cur.y + 40;
    return lay;
}

fn paintSystem(logical: *fb.LogicalFb, theme: tokens.Theme, prefs: *const prefs_mod.Prefs, scroll: i32) Layout {
    const s = prefs.system;
    var cur: form.Cursor = .{};
    var lay: Layout = .{};
    const adv = form.isAdvanced();
    _ = form.paintModeToggle(logical, theme, &cur, scroll, adv);

    form.paintSection(logical, theme, &cur, scroll, "System & about");
    form.paintSection(logical, theme, &cur, scroll, "Health");
    form.paintNote(logical, theme, &cur, scroll, "Tap a chip to open related settings.");
    const kinds = healthKinds(prefs);
    const labs = healthLabels(&kinds);
    const chips = form.paintHealthStrip(logical, theme, &cur, scroll, &labs, &kinds);
    const health_hits = [_]Hit{ .sys_h_c6, .sys_h_wifi, .sys_h_cnc, .sys_h_sd, .sys_h_batt };
    for (health_hits, 0..) |h, i| lay.push(h, chips[i], .action);
    var sdio_buf: [48]u8 = undefined;
    const sdio_line = std.fmt.bufPrint(&sdio_buf, "SDIO drop={d} stall={d} pad={d}", .{
        s.sdio_stream_drop,
        s.sdio_queue_stall,
        s.sdio_pad_skip,
    }) catch "SDIO n/a";
    form.paintDetail(logical, theme, &cur, scroll, "C6 SDIO", if (s.c6_ready) sdio_line else "down");
    if (adv) {
        lay.push(.sys_perf_hud, form.paintToggle(logical, theme, &cur, scroll, "FPS / paint HUD", s.perf_hud), .toggle);
    }

    form.paintSection(logical, theme, &cur, scroll, "Device");
    var ver_card_buf: [12]u8 = undefined;
    var fw_buf: [24]u8 = undefined;
    const card_ver = std.fmt.bufPrint(&ver_card_buf, "v{s}", .{modulus.version}) catch "v3.1.0";
    const fw_line = std.fmt.bufPrint(&fw_buf, "Modulus v{s}", .{modulus.version}) catch "Modulus v3.1.0";
    form.paintDeviceCard(logical, theme, &cur, scroll, card_ver);
    form.paintDetail(logical, theme, &cur, scroll, "Firmware", fw_line);
    form.paintDetail(logical, theme, &cur, scroll, "ESP-IDF", if (comptime @import("builtin").os.tag == .freestanding) "ESP-IDF 6.0" else "n/a (host)");
    form.paintDetail(logical, theme, &cur, scroll, "Zig", @import("builtin").zig_version_string);
    form.paintDetail(logical, theme, &cur, scroll, "ZIG UI Engine", "V1.0");
    form.paintDetail(logical, theme, &cur, scroll, "Platform", "ESP32-P4 + C6 | M5Stack Tab5");
    form.paintDetail(logical, theme, &cur, scroll, "Theme contrast", if (theme.contrastOk()) "AA pass (WCAG 4.5:1)" else "FAIL - check theme");

    form.paintSection(logical, theme, &cur, scroll, "Language & region");
    form.paintDetail(logical, theme, &cur, scroll, "Language", "English");
    lay.push(.sys_tz, form.paintDropdown(logical, theme, &cur, scroll, "Time zone", s.tzLabel()), .dropdown);
    const clk = [_][]const u8{ "24-hour", "12-hour" };
    lay.pushSeg(.sys_t24, form.paintSegment(logical, theme, &cur, scroll, "Time format", &clk, if (s.t_24h) @as(usize, 0) else 1), 2);
    const df = [_][]const u8{ "YYYY-MM-DD", "MM/DD/YYYY", "DD/MM/YYYY" };
    lay.pushSeg(.sys_datefmt, form.paintSegment(logical, theme, &cur, scroll, "Date format", &df, s.datefmt), 3);
    lay.push(.sys_kb, form.paintToggle(logical, theme, &cur, scroll, "Full-screen keyboard", s.kb_full), .toggle);

    form.paintSection(logical, theme, &cur, scroll, "Date & time");
    var tbuf: [24]u8 = undefined;
    var dbuf: [24]u8 = undefined;
    form.paintDetail(logical, theme, &cur, scroll, "Current time", s.formatTime(&tbuf));
    form.paintDetail(logical, theme, &cur, scroll, "Current date", s.formatDate(&dbuf));
    lay.push(.sys_ntp, form.paintToggle(logical, theme, &cur, scroll, "NTP sync", s.ntp), .toggle);
    form.paintDetail(logical, theme, &cur, scroll, "NTP status", s.ntpStatus(prefs.wireless.wifi));
    lay.push(.sys_sync, form.paintAction(logical, theme, &cur, scroll, "Sync now", "NTP"), .action);
    lay.push(.sys_manual, form.paintActionState(logical, theme, &cur, scroll, "Set date/time manually", "Manual", !s.ntp, false), .action);

    form.paintSection(logical, theme, &cur, scroll, "System actions");
    var ubuf: [24]u8 = undefined;
    form.paintDetail(logical, theme, &cur, scroll, "Since boot", s.formatUptime(&ubuf));
    lay.push(.sys_restart, form.paintAction(logical, theme, &cur, scroll, "Restart device", "Reboot now"), .action);
    lay.push(.sys_shutdown, form.paintDestructiveAction(logical, theme, &cur, scroll, "Shutdown device", ""), .action);
    lay.push(.sys_factory, form.paintDestructiveAction(logical, theme, &cur, scroll, "Factory reset", ""), .action);
    if (adv) {
        lay.push(.sys_link_stor, form.paintAction(logical, theme, &cur, scroll, "Storage & Diagnostics", "Open tab"), .action);

        form.paintSection(logical, theme, &cur, scroll, "Firmware update");
        form.paintNote(logical, theme, &cur, scroll, "OTA coming soon on device.");
        form.paintDetail(logical, theme, &cur, scroll, "Check for updates", "Coming soon");
        form.paintDetail(logical, theme, &cur, scroll, "Auto-update", "Coming soon");

        if (s.ref_exp) {
            form.paintDetail(logical, theme, &cur, scroll, "Host", "ESP32-P4 RISC-V 360 MHz");
            form.paintDetail(logical, theme, &cur, scroll, "Display", "ST7123 1280x720 DSI");
            form.paintDetail(logical, theme, &cur, scroll, "RTC", "RX8130CE @ 0x32");
            form.paintDetail(logical, theme, &cur, scroll, "ABI", "ABI epoch 22");
            lay.push(.sys_ref, form.paintAction(logical, theme, &cur, scroll, "Hide device reference", ""), .action);
        } else {
            lay.push(.sys_ref, form.paintAction(logical, theme, &cur, scroll, "Show device reference", ""), .action);
        }
        form.paintSection(logical, theme, &cur, scroll, "Runtime");
        if (comptime @import("builtin").os.tag == .freestanding) {
            var mbuf: [40]u8 = undefined;
            form.paintDetail(logical, theme, &cur, scroll, "Memory", prefs_mod.StoragePrefs.formatMemPair(&mbuf, prefs.storage.int_free_kb, prefs.storage.int_total_kb, "KB"));
        } else {
            form.paintDetail(logical, theme, &cur, scroll, "Memory", "host process");
        }
    }
    lay.content_h = cur.y + 40;
    return lay;
}

test "other tabs paint non-empty" {
    var logical = try fb.LogicalFb.alloc(std.testing.allocator);
    defer logical.deinit(std.testing.allocator);
    const theme = tokens.Theme.industrialTealDark();
    const prefs: prefs_mod.Prefs = .{};
    const tabs = [_]usize{ 0, 3, 4, 5, 6, 7, 8, 9 };
    for (tabs) |t| {
        const lay = paint(&logical, theme, &prefs, t, 0, 0);
        try std.testing.expect(lay.content_h > 100);
        try std.testing.expect(lay.n > 0);
    }
}
