//! NVS key literals — frozen to match C++ firmware (`namespace "modulus"`, max 15 chars).

const std = @import("std");

pub const max_key_len = 15;
pub const nvs_namespace = "modulus";

/// Default active transport: RS485 (`cnc_config::kDefaultCncConn`).
pub const k_default_cnc_conn: u8 = 4;

/// C++ `quick_grid_logic::kDefaultAssign` — SpindleCW, Coolant, Fan, ZeroAll.
pub const k_default_qbtn: [4]u8 = .{ 0, 2, 3, 4 };

pub const qbtn_slot_count = 4;

pub fn qbtnKey(slot: usize) []const u8 {
    const keys_tbl = [_][]const u8{ cnc_qbtn0, cnc_qbtn1, cnc_qbtn2, cnc_qbtn3 };
    if (slot >= keys_tbl.len) return cnc_qbtn0;
    return keys_tbl[slot];
}

/// Dynamic NVS keys — `bt_p%d` / `en_p%d` (C++ `hal_wireless.cpp`).
/// Build `"bt_pN"` NVS key for dynamic BT pair slot `idx` (0–9).
///
/// ```zig
/// const std = @import("std");
/// const settings_keys = @import("settings_keys.zig");
///
/// var buf: [settings_keys.max_key_len]u8 = undefined;
/// try std.testing.expectEqualStrings("bt_p3", settings_keys.btPairKey(3, &buf));
/// ```
pub fn btPairKey(idx: u8, buf: *[max_key_len]u8) []const u8 {
    const written = std.fmt.bufPrint(buf, "bt_p{d}", .{idx}) catch return bt_pcnt;
    return written;
}

pub fn espnowPeerKey(idx: u8, buf: *[max_key_len]u8) []const u8 {
    const written = std.fmt.bufPrint(buf, "en_p{d}", .{idx}) catch return en_pcnt;
    return written;
}

fn comptimeValidate(comptime key: []const u8) void {
    comptime {
        if (key.len == 0 or key.len > max_key_len) {
            @compileError("NVS key length invalid: " ++ key);
        }
    }
}

pub const accent = key: {
    comptimeValidate("accent");
    break :key "accent";
};
pub const ant_ext = key: {
    comptimeValidate("ant_ext");
    break :key "ant_ext";
};
pub const bat_adapt = "bat_adapt";
pub const bat_type = "bat_type";
pub const bat_warn = "bat_warn";
pub const ble_mtu = "ble_mtu";
pub const ble_name = "ble_name";
pub const ble_phy = "ble_phy";
pub const bright = "bright";
pub const bt = "bt";
pub const bt_pcnt = "bt_pcnt";
pub const can_brate = "can_brate";
pub const can_filt = "can_filt";
pub const can_mode = "can_mode";
pub const can_nid = "can_nid";
pub const chg_en = "chg_en";
/// Auto-connect on boot. Was `cnc_auto_connect` (16 chars) which silently failed
/// every NVS op (IDF limit is 15) so the setting never persisted; shortened to a
/// valid key. No migration needed — nothing was ever stored under the old name.
pub const cnc_autocon = "cnc_autocon";
pub const cnc_axes = "cnc_axes";
pub const cnc_conn = "cnc_conn";
/// Last selected transport index while `cnc_conn` is Off (255). Survives disconnect.
pub const cnc_sel = "cnc_sel";
/// CONT jog feed scale, percent (10–200, default 100).
pub const cnc_contpct = "cnc_contpct";
pub const cnc_encdiv = "cnc_encdiv";
pub const cnc_feedovr = "cnc_feedovr";
pub const cnc_incr = "cnc_incr";
pub const cnc_jmode = "cnc_jmode";
pub const cnc_jogspd = "cnc_jogspd";
pub const cnc_mpgpol = "cnc_mpgpol";
pub const cnc_mxfeed = "cnc_mxfeed";
pub const cnc_mxrpm = "cnc_mxrpm";
pub const cnc_macro = "cnc_macro";
/// Single-line G-code for dashboard Quick button Macro slot (`ui_settings_modals.c`).
pub const cnc_macro_max_len = 127;
/// User quick-macro slots ("Label|on-gcode|off-gcode", off empty = momentary).
pub const cnc_mac0 = "cnc_mac0";
pub const cnc_mac1 = "cnc_mac1";
pub const cnc_mac2 = "cnc_mac2";
pub const cnc_mac3 = "cnc_mac3";
pub const cnc_odo_h = "cnc_odo_h";
pub const cnc_odo_l = "cnc_odo_l";
/// Per-axis travel mm (hi/lo u16 pairs).
pub const cnc_odx_h = "cnc_odx_h";
pub const cnc_odx_l = "cnc_odx_l";
pub const cnc_ody_h = "cnc_ody_h";
pub const cnc_ody_l = "cnc_ody_l";
pub const cnc_odz_h = "cnc_odz_h";
pub const cnc_odz_l = "cnc_odz_l";
/// Per-axis rotary travel degrees (hi/lo u16 pairs).
pub const cnc_oda_h = "cnc_oda_h";
pub const cnc_oda_l = "cnc_oda_l";
pub const cnc_odb_h = "cnc_odb_h";
pub const cnc_odb_l = "cnc_odb_l";
pub const cnc_odc_h = "cnc_odc_h";
pub const cnc_odc_l = "cnc_odc_l";
/// Last service date `YYYY-MM-DD` (or empty).
pub const cnc_svc_dt = "cnc_svc_dt";
/// Free-text service notes (≤63 chars).
pub const cnc_svc_nt = "cnc_svc_nt";
/// Axis travel service interval in meters (`0` = off). Default 500 m.
pub const cnc_mnt_odo = "cnc_mnt_odo";
/// Spindle-on service interval in hours (`0` = off). Default 100.
pub const cnc_mnt_sph = "cnc_mnt_sph";
/// Job RUN-state service interval in hours (`0` = off). Default 200.
pub const cnc_mnt_run = "cnc_mnt_run";
/// Warn when meter reaches this % of its interval (10–100). Default 90.
pub const cnc_mnt_warn = "cnc_mnt_warn";
pub const cnc_poll = "cnc_poll";
pub const cnc_proto = "cnc_proto";
pub const cnc_qbtn0 = "cnc_qbtn0";
pub const cnc_qbtn1 = "cnc_qbtn1";
pub const cnc_qbtn2 = "cnc_qbtn2";
pub const cnc_qbtn3 = "cnc_qbtn3";
/// Job / program RUN time seconds (hi/lo u16 pair).
pub const cnc_run_h = "cnc_run_h";
pub const cnc_run_l = "cnc_run_l";
pub const cnc_spcw = "cnc_spcw";
pub const cnc_slim = "cnc_slim";
/// STEP accuracy mode — never clamp the detent queue (exact 1:1 wheel distance).
pub const cnc_stepacc = "cnc_stepacc";
pub const cnc_tr_x = "cnc_tr_x";
pub const cnc_tr_y = "cnc_tr_y";
pub const cnc_tr_z = "cnc_tr_z";
/// Rotary envelope max (degrees). GrblHAL $133/$134/$135.
pub const cnc_tr_a = "cnc_tr_a";
pub const cnc_tr_b = "cnc_tr_b";
pub const cnc_tr_c = "cnc_tr_c";
pub const cnc_spindovr = "cnc_spindovr";
pub const cnc_sph_h = "cnc_sph_h";
pub const cnc_sph_l = "cnc_sph_l";
pub const cnc_unit = "cnc_unit";
pub const cnc_wcs = "cnc_wcs";
/// Active connection profile slot (0–3).
pub const cnc_prof = "cnc_prof";
/// Packed profile blobs (proto|conn|hosts…); empty = unused.
pub const cnc_p0 = "cnc_p0";
pub const cnc_p1 = "cnc_p1";
pub const cnc_p2 = "cnc_p2";
pub const cnc_p3 = "cnc_p3";
/// Confirm policy: 0=never, 1=always, 2=when_run.
pub const cnf_cycle = "cnf_cycle";
pub const cnf_spin = "cnf_spin";
pub const cnf_zero = "cnf_zero";
pub const cnf_home = "cnf_home";
pub const cnf_mac = "cnf_mac";
/// Jog coalesce window (ms) and max pending STEP detents.
pub const jog_coal_ms = "jog_coal_ms";
pub const jog_pend_max = "jog_pend_max";
pub const ovr_l = "ovr_l";
pub const ovr_r = "ovr_r";
/// WCS custom names (short) + lock bitmask (bit0=G54 … bit5=G59).
pub const wcs_n0 = "wcs_n0";
pub const wcs_n1 = "wcs_n1";
pub const wcs_n2 = "wcs_n2";
pub const wcs_n3 = "wcs_n3";
pub const wcs_n4 = "wcs_n4";
pub const wcs_n5 = "wcs_n5";
pub const wcs_lock = "wcs_lock";
/// Masso Link scaffolding (UDP client pending).
pub const masso_ip = "masso_ip";
pub const masso_rx = "masso_rx";
pub const masso_sn = "masso_sn";
pub const masso_tx = "masso_tx";
pub const darkmode = "darkmode";
pub const datefmt = "datefmt";
pub const dim_to = "dim_to";
pub const en_chan = "en_chan";
pub const en_enc = "en_enc";
pub const en_mac = "en_mac";
pub const en_pcnt = "en_pcnt";
/// ESP-NOW PHY rate idx: 0=1M 1=2M 2=5.5M 3=11M (default 3).
pub const en_rate = "en_rate";
pub const espnow = "espnow";
pub const ext5v = "ext5v";
pub const flip = "flip";
pub const i2c_addr = "i2c_addr";
pub const i2c_pull = "i2c_pull";
pub const i2c_spd = "i2c_spd";
pub const kb_full = "kb_full";
pub const lefty = "lefty";
pub const lcnc_cpw = "lcnc_cpw";
pub const lcnc_epw = "lcnc_epw";
pub const loglvl = "loglvl";
pub const mach_name = "mach_name";
/// C++ `mach_name_buf[32]` / textarea `max_length` 31.
pub const mach_name_max_len = 31;
pub const mach_type = "mach_type";
pub const mat_rec = "mat_rec";
pub const shop_wifioff = "shop_wifioff";
pub const mic_gain = "mic_gain";
pub const ntp = "ntp";
pub const pin_hash = "pin_hash";
pub const pin_boot = "pin_boot";
pub const pin_slp = "pin_slp";
pub const pin_tmo = "pin_tmo";
pub const pin_idle = "pin_idle";
pub const pin_idle_tmo = "pin_idle_tmo";
/// QS Probe tab (x10 fixed-point mm / mm/min).
pub const pb_zoff = "pb_zoff";
pub const pb_max = "pb_max";
pub const pb_feed = "pb_feed";
pub const pb_retr = "pb_retr";
pub const pb_tip = "pb_tip";
pub const pwr_dsto = "pwr_dsto";
pub const pwr_gext = "pwr_gext";
pub const pwr_gusb = "pwr_gusb";
pub const pwr_gwifi = "pwr_gwifi";
pub const pwr_mode = "pwr_mode";
pub const pwr_wake = "pwr_wake";
pub const pwr_wtmin = "pwr_wtmin";
pub const qc = "qc";
pub const r4_baud = "r4_baud";
pub const r4_dbit = "r4_dbit";
pub const r4_dir = "r4_dir";
pub const r4_par = "r4_par";
pub const r4_sbit = "r4_sbit";
pub const refr_hz = "refr_hz";
pub const scr_to = "scr_to";
pub const ser_baud = "ser_baud";
pub const ser_dbit = "ser_dbit";
pub const ser_flow = "ser_flow";
pub const ser_par = "ser_par";
pub const ser_sbit = "ser_sbit";
pub const smooth_anim = "smooth_anim";
pub const sw_icons = "sw_icons";
pub const snd_dn = "snd_dn";
pub const snd_up = "snd_up";
pub const t_24h = "t_24h";
pub const thread = "thread";
pub const tn_host = "tn_host";
pub const tn_port = "tn_port";
pub const tone_prof = "tone_prof";
pub const touch_glove = "touch_glove";
pub const tsound = "tsound";
pub const tz_idx = "tz_idx";
pub const uhid_pid = "uhid_pid";
pub const uhid_poll = "uhid_poll";
pub const uhid_vid = "uhid_vid";
pub const ugp_dead = "ugp_dead";
pub const ugp_map = "ugp_map";
pub const ugp_poll = "ugp_poll";
pub const ui_adv = "ui_adv";
pub const ui_lang = "ui_lang";
/// MD3 system font size: 0=Small 1=Default 2=Large 3=Largest.
pub const font_scale = "font_scale";
pub const usb5v = "usb5v";
pub const vol = "vol";
pub const wake_motion = "wake_motion";
pub const wf_arecon = "wf_arecon";
pub const wf_auto = "wf_auto";
pub const wf_bsave = "wf_bsave";
pub const wf_dhcp = "wf_dhcp";
pub const wf_direct = "wf_direct";
pub const wf_lowdata = "wf_lowdata";
pub const wf_pass = "wf_pass";
pub const wf_proxy = "wf_proxy";
pub const wf_rmac = "wf_rmac";
pub const wf_roam = "wf_roam";
pub const wf_scanon = "wf_scanon";
pub const wf_sleep = "wf_sleep";
pub const wf_ssid = "wf_ssid";
pub const wifi = "wifi";
pub const ws_host = "ws_host";
pub const ws_path = "ws_path";
pub const ws_port = "ws_port";
pub const ws_tls = "ws_tls";
pub const zigbee = "zigbee";

/// Comptime guard — every exported key must respect NVS length limit.
pub const all_keys = .{
    accent,      ant_ext,     bat_adapt, bat_type,    bat_warn,     ble_mtu,      ble_name,  ble_phy,    bright,     bt,          bt_pcnt,
    can_brate,   can_filt,    can_mode,  can_nid,     chg_en,       cnc_autocon,  cnc_axes,  cnc_conn,   cnc_sel,    cnc_contpct, cnc_encdiv, cnc_feedovr, cnc_incr,
    cnc_jmode,   cnc_jogspd,  cnc_mac0,  cnc_mac1,    cnc_mac2,     cnc_mac3,     cnc_macro, cnc_mpgpol, cnc_mxfeed,  cnc_mxrpm,  cnc_odo_h,   cnc_odo_l,
    cnc_odx_h,   cnc_odx_l,   cnc_ody_h, cnc_ody_l,   cnc_odz_h,    cnc_odz_l,    cnc_oda_h,  cnc_oda_l,  cnc_odb_h,   cnc_odb_l,  cnc_odc_h,   cnc_odc_l,
    cnc_svc_dt,  cnc_svc_nt,
    cnc_mnt_odo, cnc_mnt_sph, cnc_mnt_run, cnc_mnt_warn, cnc_poll,    cnc_proto,   cnc_qbtn0,
    cnc_qbtn1,   cnc_qbtn2,   cnc_qbtn3, cnc_run_h,   cnc_run_l,    cnc_slim,    cnc_spcw,     cnc_spindovr, cnc_sph_h, cnc_sph_l,  cnc_stepacc,
    cnc_tr_x,    cnc_tr_y,    cnc_tr_z,  cnc_tr_a,    cnc_tr_b,     cnc_tr_c,
    cnc_unit,    cnc_wcs,     cnc_prof,  cnc_p0,      cnc_p1,       cnc_p2,       cnc_p3,
    cnf_cycle,   cnf_spin,    cnf_zero,  cnf_home,    cnf_mac,      jog_coal_ms,  jog_pend_max, ovr_l, ovr_r,
    wcs_n0,      wcs_n1,      wcs_n2,    wcs_n3,      wcs_n4,       wcs_n5,       wcs_lock,
    darkmode,  datefmt,     dim_to,       en_chan,      en_enc,    en_mac,     en_rate,    espnow,     ext5v,       flip,
    i2c_addr,    i2c_pull,    i2c_spd,   kb_full,     lefty,        lcnc_cpw,     lcnc_epw,  loglvl,       mach_name, mach_type,  masso_ip,   masso_rx,    masso_sn,   masso_tx,    mat_rec,    mic_gain,   ntp,         pin_hash,
    pin_boot,    pin_slp,     pin_tmo,   pin_idle,    pin_idle_tmo, pb_zoff,      pb_max,    pb_feed,    pb_retr,    pb_tip,
    pwr_dsto,     pwr_gext,  pwr_gusb,   pwr_gwifi,  pwr_mode,    pwr_wake,
    pwr_wtmin,   qc,          r4_baud,   r4_dbit,     r4_dir,       r4_par,       r4_sbit,   refr_hz,    scr_to,     ser_baud,    ser_dbit,
    ser_flow,    ser_par,     ser_sbit,  smooth_anim, snd_dn,       snd_up,       shop_wifioff, sw_icons, t_24h,     thread,     tn_host,    tn_port,     tone_prof,
    touch_glove, tsound,      tz_idx,    uhid_pid,    uhid_poll,    uhid_vid,     ugp_dead,  ugp_map,    ugp_poll,   ui_adv,     ui_lang,     font_scale, usb5v,
    vol,         wake_motion, wf_arecon, wf_auto,     wf_bsave,     wf_dhcp,      wf_direct, wf_lowdata, wf_pass,    wf_proxy,    wf_rmac,
    wf_roam,     wf_scanon,   wf_sleep,  wf_ssid,     wifi,         ws_host,      ws_path,   ws_port,    ws_tls,     zigbee,
};

test "core: settings keys within NVS limit" {
    inline for (all_keys) |key| {
        try std.testing.expect(key.len > 0 and key.len <= max_key_len);
    }
    var buf: [max_key_len]u8 = undefined;
    try std.testing.expect(btPairKey(3, &buf).len <= max_key_len);
    try std.testing.expectEqualStrings("bt_p3", btPairKey(3, &buf));
    try std.testing.expectEqualStrings("en_p7", espnowPeerKey(7, &buf));
}
