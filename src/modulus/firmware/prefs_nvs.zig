//! Tab5 Prefs ↔ NVS (load/save). Freestanding only — used by `device_ui_bridge`.

const std = @import("std");
const builtin = @import("builtin");
const c = @import("modulus_shims");
const keys = @import("../core/settings_keys.zig");
const ui_engine = @import("../ui_engine/root.zig");
const settings_prefs = ui_engine.settings_prefs;
const actions_widget = ui_engine.actions_widget;
const device_runtime = @import("device_runtime.zig");

comptime {
    if (builtin.os.tag != .freestanding) {
        @compileError("prefs_nvs is Tab5 freestanding only");
    }
}

var g_nvs_ok: bool = false;

fn nvsInit() void {
    if (g_nvs_ok) return;
    _ = c.modulus_nvs_init();
    g_nvs_ok = true;
}

fn getU8(key: []const u8, def: u8) u8 {
    nvsInit();
    var kbuf: [16]u8 = undefined;
    if (key.len >= kbuf.len) return def;
    @memcpy(kbuf[0..key.len], key);
    kbuf[key.len] = 0;
    return c.modulus_nvs_get_u8(kbuf[0..key.len :0].ptr, def);
}

fn setU8(key: []const u8, val: u8) void {
    nvsInit();
    var kbuf: [16]u8 = undefined;
    if (key.len >= kbuf.len) return;
    @memcpy(kbuf[0..key.len], key);
    kbuf[key.len] = 0;
    _ = c.modulus_nvs_set_u8(kbuf[0..key.len :0].ptr, val);
}

fn getU16(key: []const u8, def: u16) u16 {
    nvsInit();
    var kbuf: [16]u8 = undefined;
    if (key.len >= kbuf.len) return def;
    @memcpy(kbuf[0..key.len], key);
    kbuf[key.len] = 0;
    return c.modulus_nvs_get_u16(kbuf[0..key.len :0].ptr, def);
}

fn setU16(key: []const u8, val: u16) void {
    nvsInit();
    var kbuf: [16]u8 = undefined;
    if (key.len >= kbuf.len) return;
    @memcpy(kbuf[0..key.len], key);
    kbuf[key.len] = 0;
    _ = c.modulus_nvs_set_u16(kbuf[0..key.len :0].ptr, val);
}

fn getU32Pair(key_hi: []const u8, key_lo: []const u8) u32 {
    const hi = getU16(key_hi, 0);
    const lo = getU16(key_lo, 0);
    return (@as(u32, hi) << 16) | lo;
}

fn getStr(key: []const u8, buf: []u8) bool {
    nvsInit();
    var kbuf: [16]u8 = undefined;
    if (key.len >= kbuf.len or buf.len == 0) return false;
    @memcpy(kbuf[0..key.len], key);
    kbuf[key.len] = 0;
    return c.modulus_nvs_get_str(kbuf[0..key.len :0].ptr, buf.ptr, buf.len);
}

fn setStr(key: []const u8, val: []const u8) void {
    nvsInit();
    var kbuf: [16]u8 = undefined;
    var vbuf: [256]u8 = undefined;
    if (key.len >= kbuf.len) return;
    @memcpy(kbuf[0..key.len], key);
    kbuf[key.len] = 0;
    const n = @min(val.len, vbuf.len - 1);
    @memcpy(vbuf[0..n], val[0..n]);
    vbuf[n] = 0;
    _ = c.modulus_nvs_set_str(kbuf[0..key.len :0].ptr, vbuf[0..n :0].ptr);
}

fn loadStrField(dst: []u8, key: []const u8) void {
    var buf: [256]u8 = undefined;
    if (!getStr(key, buf[0..])) return;
    const s = std.mem.sliceTo(&buf, 0);
    @memset(dst, 0);
    const n = @min(s.len, dst.len);
    @memcpy(dst[0..n], s[0..n]);
}

fn quickFromNvs(v: u8) actions_widget.QuickId {
    const n = @typeInfo(actions_widget.QuickId).@"enum".fields.len;
    if (v >= n) return .spindle_cw;
    return @enumFromInt(v);
}

/// Load hot prefs from NVS (LVGL key parity). Call once at Zig UI boot.
pub fn loadPrefs(p: *settings_prefs.Prefs) void {
    nvsInit();
    p.display.bright = getU8(keys.bright, p.display.bright);
    p.audio.vol = getU8(keys.vol, p.audio.vol);
    p.display.darkmode = getU8(keys.darkmode, @intFromBool(p.display.darkmode)) != 0;
    p.display.accent = getU8(keys.accent, p.display.accent);
    p.display.ui_contrast = getU8("ui_contrast", p.display.ui_contrast);
    p.display.font_scale = @min(getU8(keys.font_scale, p.display.font_scale), 3);
    p.display.flip = getU8(keys.flip, @intFromBool(p.display.flip)) != 0;
    p.display.lefty = getU8(keys.lefty, @intFromBool(p.display.lefty)) != 0;
    p.display.touch_glove = getU8(keys.touch_glove, @intFromBool(p.display.touch_glove)) != 0;
    p.display.wake_motion = getU8(keys.wake_motion, @intFromBool(p.display.wake_motion)) != 0;
    p.display.sw_icons = getU8(keys.sw_icons, @intFromBool(p.display.sw_icons)) != 0;
    p.display.smooth_anim = getU8(keys.smooth_anim, @intFromBool(p.display.smooth_anim)) != 0;
    p.display.refr_hz = getU8(keys.refr_hz, p.display.refr_hz);
    p.display.motion_scheme = getU8("motion_scheme", p.display.motion_scheme);
    p.display.notify_en = getU8("notify_en", @intFromBool(p.display.notify_en)) != 0;
    p.display.notify_level = @min(getU8("notify_lvl", p.display.notify_level), 2);
    p.qs_tab = getU8("qs_tab", p.qs_tab);

    p.dash.confirm.cycle = settings_prefs.ConfirmPolicy.clamp(getU8(keys.cnf_cycle, p.dash.confirm.cycle));
    p.dash.confirm.spin = settings_prefs.ConfirmPolicy.clamp(getU8(keys.cnf_spin, p.dash.confirm.spin));
    p.dash.confirm.zero = settings_prefs.ConfirmPolicy.clamp(getU8(keys.cnf_zero, p.dash.confirm.zero));
    p.dash.confirm.home = settings_prefs.ConfirmPolicy.clamp(getU8(keys.cnf_home, p.dash.confirm.home));
    p.dash.confirm.mac = settings_prefs.ConfirmPolicy.clamp(getU8(keys.cnf_mac, p.dash.confirm.mac));

    p.dash.jog_mode = getU8(keys.cnc_jmode, p.dash.jog_mode);
    p.dash.encdiv = getU8(keys.cnc_encdiv, p.dash.encdiv);
    p.dash.contpct = getU8(keys.cnc_contpct, p.dash.contpct);
    p.dash.mpgpol = getU8(keys.cnc_mpgpol, p.dash.mpgpol);
    p.dash.axes_preset = getU8(keys.cnc_axes, p.dash.axes_preset);
    p.dash.wcs = getU8(keys.cnc_wcs, p.dash.wcs);
    p.dash.wcs_lock = getU8(keys.wcs_lock, p.dash.wcs_lock);
    p.dash.unit_mm = getU8(keys.cnc_unit, @intFromBool(p.dash.unit_mm)) != 0;
    p.dash.jog_coal_ms = getU8(keys.jog_coal_ms, p.dash.jog_coal_ms);
    p.dash.jog_pend_max = getU8(keys.jog_pend_max, p.dash.jog_pend_max);
    p.dash.ovr_left = getU8(keys.ovr_l, p.dash.ovr_left);
    p.dash.ovr_right = getU8(keys.ovr_r, p.dash.ovr_right);
    // Coerce so stored pair stays distinct after load.
    const ovr_pair = p.dash.ovrSlots();
    p.dash.ovr_left = @intFromEnum(ovr_pair[0]);
    p.dash.ovr_right = @intFromEnum(ovr_pair[1]);
    p.dash.stepacc = getU8(keys.cnc_stepacc, @intFromBool(p.dash.stepacc)) != 0;
    p.dash.quick[0] = quickFromNvs(getU8(keys.cnc_qbtn0, @intFromEnum(p.dash.quick[0])));
    p.dash.quick[1] = quickFromNvs(getU8(keys.cnc_qbtn1, @intFromEnum(p.dash.quick[1])));
    p.dash.quick[2] = quickFromNvs(getU8(keys.cnc_qbtn2, @intFromEnum(p.dash.quick[2])));
    p.dash.quick[3] = quickFromNvs(getU8(keys.cnc_qbtn3, @intFromEnum(p.dash.quick[3])));

    var incr_buf: [48]u8 = undefined;
    if (getStr(keys.cnc_incr, &incr_buf)) {
        const s = std.mem.sliceTo(&incr_buf, 0);
        if (s.len > 0) p.dash.setIncrFromCsv(s);
    }

    p.dash.probe_zoff_x10 = getU16(keys.pb_zoff, p.dash.probe_zoff_x10);
    p.dash.probe_max_x10 = getU16(keys.pb_max, p.dash.probe_max_x10);
    p.dash.probe_feed_x10 = getU16(keys.pb_feed, p.dash.probe_feed_x10);
    p.dash.probe_retr_x10 = getU16(keys.pb_retr, p.dash.probe_retr_x10);
    p.dash.probe_tip_x10 = getU16(keys.pb_tip, p.dash.probe_tip_x10);

    p.cnc.conn = getU8(keys.cnc_conn, p.cnc.conn);
    p.cnc.proto = getU8(keys.cnc_proto, p.cnc.proto);
    p.cnc.prof = getU8(keys.cnc_prof, p.cnc.prof);
    p.cnc.autocon = getU8(keys.cnc_autocon, @intFromBool(p.cnc.autocon)) != 0;
    p.cnc.ws_port = getU16(keys.ws_port, p.cnc.ws_port);
    p.cnc.tn_port = getU16(keys.tn_port, p.cnc.tn_port);
    p.cnc.ws_tls = getU8(keys.ws_tls, @intFromBool(p.cnc.ws_tls)) != 0;
    p.cnc.ser_baud_idx = getU8(keys.ser_baud, p.cnc.ser_baud_idx);
    p.cnc.r4_baud_idx = getU8(keys.r4_baud, p.cnc.r4_baud_idx);
    p.cnc.i2c_addr = getU8(keys.i2c_addr, p.cnc.i2c_addr);
    p.cnc.i2c_spd = getU8(keys.i2c_spd, p.cnc.i2c_spd);
    p.cnc.can_brate = getU8(keys.can_brate, p.cnc.can_brate);
    p.cnc.can_nid = getU8(keys.can_nid, p.cnc.can_nid);
    p.cnc.masso_tx = getU16(keys.masso_tx, p.cnc.masso_tx);
    p.cnc.masso_rx = getU16(keys.masso_rx, p.cnc.masso_rx);
    p.cnc.espnow_enc = getU8(keys.en_enc, @intFromBool(p.cnc.espnow_enc)) != 0;
    loadStrField(p.cnc.ws_host[0..], keys.ws_host);
    loadStrField(p.cnc.ws_path[0..], keys.ws_path);
    loadStrField(p.cnc.tn_host[0..], keys.tn_host);
    loadStrField(p.cnc.ble_name[0..], keys.ble_name);
    loadStrField(p.cnc.masso_ip[0..], keys.masso_ip);
    loadStrField(p.cnc.masso_sn[0..], keys.masso_sn);
    loadStrField(p.cnc.espnow_mac[0..], keys.en_mac);
    if (p.cnc.conn == 255) {
        p.cnc.transport_off = true;
        // Restore last selection (do not force RS-485 — kills ESP-NOW after Disconnect).
        const sel = getU8(keys.cnc_sel, 4);
        p.cnc.conn = if (sel < settings_prefs.transport_names.len) sel else 4;
    }

    const mac_keys = [_][]const u8{ keys.cnc_mac0, keys.cnc_mac1, keys.cnc_mac2, keys.cnc_mac3 };
    for (&p.dash.macros, mac_keys) |*slot, mk| {
        var mbuf: [192]u8 = undefined;
        if (getStr(mk, mbuf[0..])) {
            const raw = std.mem.sliceTo(&mbuf, 0);
            if (raw.len > 0) _ = slot.unpackNvs(raw);
        }
    }
    const prof_keys = [_][]const u8{ keys.cnc_p0, keys.cnc_p1, keys.cnc_p2, keys.cnc_p3 };
    for (&p.cnc.profiles, prof_keys) |*blob, pk| {
        loadStrField(blob[0..], pk);
    }
    const wcs_keys = [_][]const u8{ keys.wcs_n0, keys.wcs_n1, keys.wcs_n2, keys.wcs_n3, keys.wcs_n4, keys.wcs_n5 };
    for (&p.dash.wcs_names, wcs_keys) |*name, wk| {
        loadStrField(name[0..], wk);
    }

    p.storage.loglvl = getU8(keys.loglvl, p.storage.loglvl);

    p.system.t_24h = getU8(keys.t_24h, @intFromBool(p.system.t_24h)) != 0;
    p.system.ntp = getU8(keys.ntp, @intFromBool(p.system.ntp)) != 0;
    p.system.tz_idx = getU8(keys.tz_idx, p.system.tz_idx);
    p.system.lang = getU8(keys.ui_lang, p.system.lang);
    p.system.datefmt = getU8(keys.datefmt, p.system.datefmt);
    p.system.kb_full = getU8(keys.kb_full, @intFromBool(p.system.kb_full)) != 0;
    p.settings_advanced = getU8(keys.ui_adv, @intFromBool(p.settings_advanced)) != 0;

    p.wireless.wifi = getU8(keys.wifi, @intFromBool(p.wireless.wifi)) != 0;
    p.wireless.bt = getU8(keys.bt, @intFromBool(p.wireless.bt)) != 0;
    p.wireless.espnow = getU8(keys.espnow, @intFromBool(p.wireless.espnow)) != 0;
    p.wireless.zigbee = getU8(keys.zigbee, @intFromBool(p.wireless.zigbee)) != 0;
    p.wireless.thread = getU8(keys.thread, @intFromBool(p.wireless.thread)) != 0;
    p.wireless.ant_ext = getU8(keys.ant_ext, @intFromBool(p.wireless.ant_ext)) != 0;
    p.wireless.wf_auto = getU8(keys.wf_auto, @intFromBool(p.wireless.wf_auto)) != 0;
    p.wireless.wf_arecon = getU8(keys.wf_arecon, @intFromBool(p.wireless.wf_arecon)) != 0;
    p.wireless.wf_dhcp = getU8(keys.wf_dhcp, @intFromBool(p.wireless.wf_dhcp)) != 0;
    // NVS en_chan is 0-based; prefs use 1..13.
    p.wireless.en_chan = getU8(keys.en_chan, p.wireless.en_chan -| 1) + 1;
    p.wireless.en_rate = getU8(keys.en_rate, p.wireless.en_rate);

    p.audio.tone_prof = getU8(keys.tone_prof, p.audio.tone_prof);
    p.audio.tsound = getU8(keys.tsound, @intFromBool(p.audio.tsound)) != 0;
    p.audio.snd_up = getU8(keys.snd_up, @intFromBool(p.audio.snd_up)) != 0;
    p.audio.snd_dn = getU8(keys.snd_dn, @intFromBool(p.audio.snd_dn)) != 0;
    p.audio.mic_gain = getU8(keys.mic_gain, p.audio.mic_gain);

    p.power.setDimFromSec(getU16(keys.dim_to, p.power.dimSec()));
    p.power.setScrFromSec(getU16(keys.scr_to, p.power.scrSec()));
    p.power.ext5v = getU8(keys.ext5v, @intFromBool(p.power.ext5v)) != 0;
    p.power.usb5v = getU8(keys.usb5v, @intFromBool(p.power.usb5v)) != 0;
    p.power.pwr_mode = getU8(keys.pwr_mode, p.power.pwr_mode);
    p.power.setDstoFromSec(getU16(keys.pwr_dsto, p.power.dstoSec()));
    p.power.setWtminFromMin(getU16(keys.pwr_wtmin, p.power.wtminMin()));
    p.power.setWakeFromBits(getU8(keys.pwr_wake, p.power.wakeBits()));
    p.power.gate_wifi = getU8(keys.pwr_gwifi, @intFromBool(p.power.gate_wifi)) != 0;
    p.power.gate_ext = getU8(keys.pwr_gext, @intFromBool(p.power.gate_ext)) != 0;
    p.power.gate_usb = getU8(keys.pwr_gusb, @intFromBool(p.power.gate_usb)) != 0;
    p.power.bat_type = getU8(keys.bat_type, p.power.bat_type);
    p.power.setWarnFromPct(getU8(keys.bat_warn, p.power.batWarnPct()));
    p.power.chg_en = getU8(keys.chg_en, @intFromBool(p.power.chg_en)) != 0;
    p.power.bat_adapt = getU8(keys.bat_adapt, @intFromBool(p.power.bat_adapt)) != 0;
    p.power.qc = getU8(keys.qc, @intFromBool(p.power.qc)) != 0;

    p.security.has_pin = c.modulus_security_has_pin();
    p.security.pin_boot = c.modulus_security_lock_on_boot();
    p.security.pin_slp = c.modulus_security_lock_on_sleep();
    p.security.setTmoFromSec(getU16(keys.pin_tmo, p.security.tmoSec()));
    p.security.pin_idle = getU8(keys.pin_idle, @intFromBool(p.security.pin_idle)) != 0;
    p.security.setIdleTmoFromSec(getU16(keys.pin_idle_tmo, p.security.idleTmoSec()));

    p.machine.mxfeed = getU16(keys.cnc_mxfeed, p.machine.mxfeed);
    p.machine.mxrpm = getU16(keys.cnc_mxrpm, p.machine.mxrpm);
    p.machine.jogspd = getU16(keys.cnc_jogspd, p.machine.jogspd);
    p.dash.setJogspdIdxFromMm(p.machine.jogspd);
    p.machine.tr_x = getU16(keys.cnc_tr_x, p.machine.tr_x);
    p.machine.tr_y = getU16(keys.cnc_tr_y, p.machine.tr_y);
    p.machine.tr_z = getU16(keys.cnc_tr_z, p.machine.tr_z);
    p.machine.tr_a = getU16(keys.cnc_tr_a, p.machine.tr_a);
    p.machine.tr_b = getU16(keys.cnc_tr_b, p.machine.tr_b);
    p.machine.tr_c = getU16(keys.cnc_tr_c, p.machine.tr_c);
    p.machine.slim = getU8(keys.cnc_slim, @intFromBool(p.machine.slim)) != 0;
    p.machine.spcw = getU8(keys.cnc_spcw, @intFromBool(p.machine.spcw)) != 0;
    p.machine.feedovr = getU8(keys.cnc_feedovr, p.machine.feedovr);
    p.machine.spindovr = getU8(keys.cnc_spindovr, p.machine.spindovr);
    p.machine.mnt_odo_idx = idxFromVal(settings_prefs.MachinePrefs.mnt_odo_m[0..], getU16(keys.cnc_mnt_odo, 500));
    p.machine.mnt_sph_idx = idxFromVal(settings_prefs.MachinePrefs.mnt_hours[0..], getU16(keys.cnc_mnt_sph, 100));
    p.machine.mnt_run_idx = idxFromVal(settings_prefs.MachinePrefs.mnt_hours[0..], getU16(keys.cnc_mnt_run, 200));
    p.machine.mnt_warn_idx = idxFromValU8(settings_prefs.MachinePrefs.mnt_warn_pct[0..], getU8(keys.cnc_mnt_warn, 90));
    p.machine.odo_mm = getU32Pair(keys.cnc_odo_h, keys.cnc_odo_l);
    p.machine.sph_sec = getU32Pair(keys.cnc_sph_h, keys.cnc_sph_l);
    p.machine.run_sec = getU32Pair(keys.cnc_run_h, keys.cnc_run_l);
    var name_buf: [32]u8 = undefined;
    if (getStr(keys.mach_name, &name_buf)) {
        const s = std.mem.sliceTo(&name_buf, 0);
        if (s.len > 0) p.machine.setName(s);
    }
    var svc_buf: [64]u8 = undefined;
    if (getStr(keys.cnc_svc_nt, &svc_buf)) {
        const s = std.mem.sliceTo(&svc_buf, 0);
        p.machine.setSvcNotes(s);
    }
    var svc_dt_buf: [16]u8 = undefined;
    if (getStr(keys.cnc_svc_dt, &svc_dt_buf)) {
        const s = std.mem.sliceTo(&svc_dt_buf, 0);
        if (s.len > 0) {
            @memset(&p.machine.svc_dt, 0);
            const n = @min(s.len, p.machine.svc_dt.len);
            @memcpy(p.machine.svc_dt[0..n], s[0..n]);
        }
    }
    var type_buf: [16]u8 = undefined;
    if (getStr(keys.mach_type, &type_buf)) {
        const s = std.mem.sliceTo(&type_buf, 0);
        for (settings_prefs.mach_type_names, 0..) |name, i| {
            if (std.mem.eql(u8, s, name)) {
                p.machine.mach_type = @intCast(i);
                break;
            }
        }
    }
}

fn idxFromVal(vals: []const u16, want: u16) u8 {
    for (vals, 0..) |v, i| {
        if (v == want) return @intCast(i);
    }
    return 0;
}

fn idxFromValU8(vals: []const u8, want: u8) u8 {
    for (vals, 0..) |v, i| {
        if (v == want) return @intCast(i);
    }
    return 0;
}

/// Persist hot prefs (call after settings/QS edits).
/// Batched: `modulus_nvs_set_*` commits per key otherwise, and this writes ~150.
pub fn savePrefs(p: *const settings_prefs.Prefs) void {
    nvsInit();
    c.modulus_nvs_begin_batch();
    defer c.modulus_nvs_end_batch();
    setU8(keys.bright, p.display.bright);
    setU8(keys.vol, p.audio.vol);
    setU8(keys.darkmode, @intFromBool(p.display.darkmode));
    setU8(keys.accent, p.display.accent);
    setU8("ui_contrast", p.display.ui_contrast);
    setU8(keys.font_scale, @min(p.display.font_scale, 3));
    setU8(keys.flip, @intFromBool(p.display.flip));
    setU8(keys.lefty, @intFromBool(p.display.lefty));
    setU8(keys.touch_glove, @intFromBool(p.display.touch_glove));
    setU8(keys.wake_motion, @intFromBool(p.display.wake_motion));
    setU8(keys.sw_icons, @intFromBool(p.display.sw_icons));
    setU8(keys.smooth_anim, @intFromBool(p.display.smooth_anim));
    setU8(keys.refr_hz, p.display.refr_hz);
    setU8("motion_scheme", p.display.motion_scheme);
    setU8("notify_en", @intFromBool(p.display.notify_en));
    setU8("notify_lvl", p.display.notify_level);
    setU8("qs_tab", p.qs_tab);

    setU8(keys.cnf_cycle, p.dash.confirm.cycle);
    setU8(keys.cnf_spin, p.dash.confirm.spin);
    setU8(keys.cnf_zero, p.dash.confirm.zero);
    setU8(keys.cnf_home, p.dash.confirm.home);
    setU8(keys.cnf_mac, p.dash.confirm.mac);

    setU8(keys.cnc_jmode, p.dash.jog_mode);
    setU8(keys.cnc_encdiv, p.dash.encdiv);
    setU16(keys.cnc_jogspd, p.machine.jogspd);
    setU8(keys.cnc_contpct, p.dash.contpct);
    setU8(keys.cnc_mpgpol, p.dash.mpgpol);
    setU8(keys.cnc_axes, p.dash.axes_preset);
    setU8(keys.cnc_wcs, p.dash.wcs);
    setU8(keys.wcs_lock, p.dash.wcs_lock);
    setU8(keys.cnc_unit, @intFromBool(p.dash.unit_mm));
    setU8(keys.jog_coal_ms, p.dash.jog_coal_ms);
    setU8(keys.jog_pend_max, p.dash.jog_pend_max);
    setU8(keys.ovr_l, p.dash.ovr_left);
    setU8(keys.ovr_r, p.dash.ovr_right);
    setU8(keys.cnc_stepacc, @intFromBool(p.dash.stepacc));
    setU8(keys.cnc_qbtn0, @intFromEnum(p.dash.quick[0]));
    setU8(keys.cnc_qbtn1, @intFromEnum(p.dash.quick[1]));
    setU8(keys.cnc_qbtn2, @intFromEnum(p.dash.quick[2]));
    setU8(keys.cnc_qbtn3, @intFromEnum(p.dash.quick[3]));

    var csv: [48]u8 = undefined;
    const incr = p.dash.incrCsv(&csv);
    setStr(keys.cnc_incr, incr);

    setU16(keys.pb_zoff, p.dash.probe_zoff_x10);
    setU16(keys.pb_max, p.dash.probe_max_x10);
    setU16(keys.pb_feed, p.dash.probe_feed_x10);
    setU16(keys.pb_retr, p.dash.probe_retr_x10);
    setU16(keys.pb_tip, p.dash.probe_tip_x10);

    setU8(keys.cnc_conn, if (p.cnc.transport_off) 255 else p.cnc.conn);
    setU8(keys.cnc_sel, p.cnc.conn);
    setU8(keys.cnc_proto, p.cnc.proto);
    setU8(keys.cnc_prof, p.cnc.prof);
    setU8(keys.cnc_autocon, @intFromBool(p.cnc.autocon));
    setU16(keys.ws_port, p.cnc.ws_port);
    setU16(keys.tn_port, p.cnc.tn_port);
    setU8(keys.ws_tls, @intFromBool(p.cnc.ws_tls));
    setU8(keys.ser_baud, p.cnc.ser_baud_idx);
    setU8(keys.r4_baud, p.cnc.r4_baud_idx);
    setU8(keys.i2c_addr, p.cnc.i2c_addr);
    setU8(keys.i2c_spd, p.cnc.i2c_spd);
    setU8(keys.can_brate, p.cnc.can_brate);
    setU8(keys.can_nid, p.cnc.can_nid);
    setU16(keys.masso_tx, p.cnc.masso_tx);
    setU16(keys.masso_rx, p.cnc.masso_rx);
    setU8(keys.en_enc, @intFromBool(p.cnc.espnow_enc));
    setStr(keys.ws_host, p.cnc.wsHostSlice());
    setStr(keys.ws_path, p.cnc.wsPathSlice());
    setStr(keys.tn_host, p.cnc.tnHostSlice());
    setStr(keys.ble_name, p.cnc.bleNameSlice());
    setStr(keys.masso_ip, p.cnc.massoIpSlice());
    setStr(keys.masso_sn, std.mem.sliceTo(&p.cnc.masso_sn, 0));
    setStr(keys.en_mac, p.espnowMacForNvs());

    const mac_keys = [_][]const u8{ keys.cnc_mac0, keys.cnc_mac1, keys.cnc_mac2, keys.cnc_mac3 };
    for (p.dash.macros, mac_keys) |slot, mk| {
        if (slot.occupied()) {
            var mbuf: [192]u8 = undefined;
            setStr(mk, slot.packNvs(&mbuf));
        } else {
            setStr(mk, "");
        }
    }
    const prof_keys = [_][]const u8{ keys.cnc_p0, keys.cnc_p1, keys.cnc_p2, keys.cnc_p3 };
    for (p.cnc.profiles, prof_keys) |blob, pk| {
        setStr(pk, std.mem.sliceTo(&blob, 0));
    }
    const wcs_keys = [_][]const u8{ keys.wcs_n0, keys.wcs_n1, keys.wcs_n2, keys.wcs_n3, keys.wcs_n4, keys.wcs_n5 };
    for (p.dash.wcs_names, wcs_keys) |name, wk| {
        setStr(wk, std.mem.sliceTo(&name, 0));
    }
    setU8(keys.loglvl, p.storage.loglvl);

    setU8(keys.t_24h, @intFromBool(p.system.t_24h));
    setU8(keys.ntp, @intFromBool(p.system.ntp));
    setU8(keys.tz_idx, p.system.tz_idx);
    setU8(keys.ui_lang, p.system.lang);
    setU8(keys.datefmt, p.system.datefmt);
    setU8(keys.kb_full, @intFromBool(p.system.kb_full));
    setU8(keys.ui_adv, @intFromBool(p.settings_advanced));

    setU8(keys.wifi, @intFromBool(p.wireless.wifi));
    setU8(keys.bt, @intFromBool(p.wireless.bt));
    setU8(keys.espnow, @intFromBool(p.wireless.espnow));
    setU8(keys.zigbee, @intFromBool(p.wireless.zigbee));
    setU8(keys.thread, @intFromBool(p.wireless.thread));
    setU8(keys.ant_ext, @intFromBool(p.wireless.ant_ext));
    setU8(keys.wf_auto, @intFromBool(p.wireless.wf_auto));
    setU8(keys.wf_arecon, @intFromBool(p.wireless.wf_arecon));
    setU8(keys.wf_dhcp, @intFromBool(p.wireless.wf_dhcp));
    setU8(keys.en_chan, p.wireless.en_chan -| 1);
    setU8(keys.en_rate, p.wireless.en_rate);

    setU8(keys.tone_prof, p.audio.tone_prof);
    setU8(keys.tsound, @intFromBool(p.audio.tsound));
    setU8(keys.snd_up, @intFromBool(p.audio.snd_up));
    setU8(keys.snd_dn, @intFromBool(p.audio.snd_dn));
    setU8(keys.mic_gain, p.audio.mic_gain);

    setU16(keys.dim_to, p.power.dimSec());
    setU16(keys.scr_to, p.power.scrSec());
    setU8(keys.ext5v, @intFromBool(p.power.ext5v));
    setU8(keys.usb5v, @intFromBool(p.power.usb5v));
    setU8(keys.pwr_mode, p.power.pwr_mode);
    setU16(keys.pwr_dsto, p.power.dstoSec());
    setU16(keys.pwr_wtmin, p.power.wtminMin());
    setU8(keys.pwr_wake, p.power.wakeBits());
    setU8(keys.pwr_gwifi, @intFromBool(p.power.gate_wifi));
    setU8(keys.pwr_gext, @intFromBool(p.power.gate_ext));
    setU8(keys.pwr_gusb, @intFromBool(p.power.gate_usb));
    setU8(keys.bat_type, p.power.bat_type);
    setU8(keys.bat_warn, p.power.batWarnPct());
    setU8(keys.chg_en, @intFromBool(p.power.chg_en));
    setU8(keys.bat_adapt, @intFromBool(p.power.bat_adapt));
    setU8(keys.qc, @intFromBool(p.power.qc));

    setU8(keys.pin_boot, @intFromBool(p.security.pin_boot));
    setU8(keys.pin_slp, @intFromBool(p.security.pin_slp));
    setU16(keys.pin_tmo, p.security.tmoSec());
    setU8(keys.pin_idle, @intFromBool(p.security.pin_idle));
    setU16(keys.pin_idle_tmo, if (p.security.pin_idle) p.security.idleTmoSec() else 0);

    setU16(keys.cnc_mxfeed, p.machine.mxfeed);
    setU16(keys.cnc_mxrpm, p.machine.mxrpm);
    setU16(keys.cnc_tr_x, p.machine.tr_x);
    setU16(keys.cnc_tr_y, p.machine.tr_y);
    setU16(keys.cnc_tr_z, p.machine.tr_z);
    setU16(keys.cnc_tr_a, p.machine.tr_a);
    setU16(keys.cnc_tr_b, p.machine.tr_b);
    setU16(keys.cnc_tr_c, p.machine.tr_c);
    setU8(keys.cnc_slim, @intFromBool(p.machine.slim));
    setU8(keys.cnc_spcw, @intFromBool(p.machine.spcw));
    setU8(keys.cnc_feedovr, p.machine.feedovr);
    setU8(keys.cnc_spindovr, p.machine.spindovr);
    setU16(keys.cnc_mnt_odo, p.machine.mntOdoM());
    setU16(keys.cnc_mnt_sph, p.machine.mntSphH());
    setU16(keys.cnc_mnt_run, p.machine.mntRunH());
    setU8(keys.cnc_mnt_warn, p.machine.mntWarnPct());
    setStr(keys.mach_name, p.machine.nameSlice());
    setStr(keys.cnc_svc_nt, p.machine.svcNtSlice());
    setStr(keys.cnc_svc_dt, p.machine.svcDtSlice());
    setStr(keys.mach_type, p.machine.typeLabel());

    device_runtime.encoderReloadSettings();
    device_runtime.reloadMachineLimits();
}

/// Reload travel/feed envelope fields after a settings dump lands in NVS.
pub fn loadMachineEnvelope(p: *settings_prefs.Prefs) void {
    p.machine.mxfeed = getU16(keys.cnc_mxfeed, p.machine.mxfeed);
    p.machine.mxrpm = getU16(keys.cnc_mxrpm, p.machine.mxrpm);
    p.machine.tr_x = getU16(keys.cnc_tr_x, p.machine.tr_x);
    p.machine.tr_y = getU16(keys.cnc_tr_y, p.machine.tr_y);
    p.machine.tr_z = getU16(keys.cnc_tr_z, p.machine.tr_z);
    p.machine.tr_a = getU16(keys.cnc_tr_a, p.machine.tr_a);
    p.machine.tr_b = getU16(keys.cnc_tr_b, p.machine.tr_b);
    p.machine.tr_c = getU16(keys.cnc_tr_c, p.machine.tr_c);
}
