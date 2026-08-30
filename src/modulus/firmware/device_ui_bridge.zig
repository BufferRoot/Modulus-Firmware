//! Tab5 Zig UI ↔ C shims / device_runtime (battery, clock, bright/vol, power, PIN, wireless).
//! Prefs NVS load/save: `prefs_nvs.zig`. Freestanding only — from `device_ui_runtime.zig`.

const std = @import("std");
const builtin = @import("builtin");
const c = @import("modulus_shims");
const ui_engine = @import("../ui_engine/root.zig");
const Engine = ui_engine.engine.Engine;
const settings_prefs = ui_engine.settings_prefs;
const quick_settings = ui_engine.quick_settings;
const device_runtime = @import("device_runtime.zig");
const prefs_nvs = @import("prefs_nvs.zig");
const console_log = @import("../cnc/console_log.zig");

pub const loadPrefs = prefs_nvs.loadPrefs;
pub const savePrefs = prefs_nvs.savePrefs;
pub const loadMachineEnvelope = prefs_nvs.loadMachineEnvelope;

comptime {
    if (builtin.os.tag != .freestanding) {
        @compileError("device_ui_bridge is Tab5 freestanding only");
    }
}

extern "c" fn esp_timer_get_time() callconv(.c) i64;

fn nowMs() u64 {
    return @intCast(@max(@divTrunc(esp_timer_get_time(), 1000), 0));
}

var g_last_bright: u8 = 255;
var g_last_vol: u8 = 255;
var g_last_silent: bool = false;

/// Coalesce window for NVS writes after the last edit.
const prefs_flush_idle_ms: u64 = 400;
var g_prefs_dirty: bool = false;
var g_prefs_dirty_ms: u64 = 0;
var g_eng: ?*Engine = null;

pub fn applyBrightVol(p: *const settings_prefs.Prefs) void {
    if (p.display.bright != g_last_bright) {
        g_last_bright = p.display.bright;
        c.modulus_display_set_brightness(p.display.bright);
    }
    if (p.audio.vol != g_last_vol or p.audio.silent != g_last_silent) {
        g_last_vol = p.audio.vol;
        g_last_silent = p.audio.silent;
        const out: u8 = if (p.audio.silent) 0 else p.audio.vol;
        c.modulus_audio_set_volume(out);
    }
}

var g_last_tone: u8 = 255;
var g_last_wifi: u8 = 255;
var g_last_bt: u8 = 255;
var g_prev_bt_on: bool = false;
var g_last_espnow: u8 = 255;
var g_last_zb: u8 = 255;
var g_last_th: u8 = 255;

fn applyTone(p: *const settings_prefs.Prefs) void {
    if (p.audio.tone_prof == g_last_tone) return;
    g_last_tone = p.audio.tone_prof;
    c.modulus_audio_set_tone_profile(p.audio.tone_prof);
}

fn applyDisplayTimeouts(p: *const settings_prefs.Prefs) void {
    c.modulus_display_set_timeouts(p.power.dimSec(), p.power.scrSec());
}

fn tryEnableRadio(comptime name: []const u8, enable: *const fn () callconv(.c) c_int) bool {
    // Radio enable workers own C6 wake — never call wake_coprocessor here.
    // (BLE/Wi-Fi host init can block many seconds; UI thread must stay free.)
    _ = name;
    return enable() != 0;
}

fn applyWirelessRadios(p: *settings_prefs.Prefs) void {
    const wi: u8 = @intFromBool(p.wireless.wifi);
    const bt: u8 = @intFromBool(p.wireless.bt);
    const en: u8 = @intFromBool(p.wireless.espnow);
    const zb: u8 = @intFromBool(p.wireless.zigbee);
    const th: u8 = @intFromBool(p.wireless.thread);
    if (wi != g_last_wifi) {
        g_last_wifi = wi;
        if (p.wireless.wifi) {
            if (!tryEnableRadio("wifi", c.modulus_wireless_wifi_enable_zi)) {
                p.wireless.wifi = false;
                g_last_wifi = 0;
            }
        } else {
            c.modulus_wireless_wifi_disable();
        }
    }
    if (bt != g_last_bt) {
        g_last_bt = bt;
        if (p.wireless.bt) {
            if (!tryEnableRadio("ble", c.modulus_wireless_ble_enable_zi)) {
                p.wireless.bt = false;
                g_last_bt = 0;
            }
        } else {
            c.modulus_wireless_ble_disable();
        }
    }
    if (en != g_last_espnow) {
        g_last_espnow = en;
        if (p.wireless.espnow) {
            if (!tryEnableRadio("espnow", c.modulus_wireless_espnow_enable_zi)) {
                p.wireless.espnow = false;
                g_last_espnow = 0;
            }
        } else {
            c.modulus_wireless_espnow_disable();
        }
    }
    if (zb != g_last_zb) {
        g_last_zb = zb;
        if (p.wireless.zigbee) {
            if (!tryEnableRadio("zigbee", c.modulus_wireless_zigbee_enable_zi)) {
                p.wireless.zigbee = false;
                g_last_zb = 0;
            }
        } else {
            c.modulus_wireless_zigbee_disable();
        }
    }
    if (th != g_last_th) {
        g_last_th = th;
        if (p.wireless.thread) {
            if (!c.modulus_wireless_thread_supported()) {
                p.wireless.thread = false;
                g_last_th = 0;
            } else if (!tryEnableRadio("thread", c.modulus_wireless_thread_enable_zi)) {
                p.wireless.thread = false;
                g_last_th = 0;
            }
        } else {
            c.modulus_wireless_thread_disable();
        }
    }
}

fn copyCStr(dst: []u8, src: [*:0]const u8) void {
    @memset(dst, 0);
    const s = std.mem.span(src);
    if (dst.len == 0) return;
    const n = @min(s.len, dst.len -| 1);
    if (n > 0) @memcpy(dst[0..n], s[0..n]);
}

fn copySliceTo(dst: []u8, src: []const u8) void {
    @memset(dst, 0);
    if (dst.len == 0) return;
    const n = @min(src.len, dst.len -| 1);
    if (n > 0) @memcpy(dst[0..n], src[0..n]);
}

fn syncEspnowSaved(eng: *Engine) void {
    const w = &eng.prefs.wireless;
    const n = c.modulus_wireless_espnow_saved_count();
    w.live_en_saved_n = 0;
    w.en_saved_mask = 0;
    w.en_active = 255;
    var i: c_int = 0;
    while (i < n and w.live_en_saved_n < w.live_en_saved.len) : (i += 1) {
        var peer: c.modulus_espnow_peer_t = undefined;
        if (!c.modulus_wireless_espnow_saved_get(i, &peer)) continue;
        const mac = std.mem.sliceTo(&peer.mac, 0);
        copySliceTo(&w.live_en_saved[w.live_en_saved_n], mac);
        if (w.live_en_saved_n < 8) {
            w.en_saved_mask |= @as(u8, 1) << @intCast(w.live_en_saved_n);
        }
        if (c.modulus_wireless_espnow_saved_is_active(i)) {
            w.en_active = w.live_en_saved_n;
            copySliceTo(w.en_bridge[0..], mac);
        }
        w.live_en_saved_n += 1;
    }
    if (w.en_active == 255) {
        var macbuf: [18]u8 = undefined;
        c.modulus_wireless_espnow_peer_mac_str(@ptrCast(&macbuf), macbuf.len);
        const mac = std.mem.sliceTo(&macbuf, 0);
        const unset = mac.len == 0 or std.mem.eql(u8, mac, "None") or
            std.mem.eql(u8, mac, "FF:FF:FF:FF:FF:FF");
        if (unset) {
            @memset(&w.en_bridge, 0);
            const none = "None";
            @memcpy(w.en_bridge[0..none.len], none);
            @memset(&eng.prefs.cnc.espnow_mac, 0);
        } else {
            copySliceTo(w.en_bridge[0..], mac);
        }
    }
    // CNC field must match bridge before prefs flush writes `en_mac`.
    eng.prefs.syncEspnowMacFromBridge();
}

fn syncZbDevices(w: *settings_prefs.WirelessPrefs) void {
    const n = c.modulus_wireless_zigbee_device_count();
    w.live_zb_n = 0;
    w.zb_dev_n = 0;
    var i: c_int = 0;
    while (i < n and w.live_zb_n < w.live_zb.len) : (i += 1) {
        var d: c.modulus_zb_device_t = undefined;
        if (!c.modulus_wireless_zigbee_device_get(i, &d)) continue;
        const name = std.mem.sliceTo(&d.name, 0);
        copySliceTo(&w.live_zb[w.live_zb_n], if (name.len > 0) name else std.mem.sliceTo(&d.id, 0));
        if (w.live_zb_n < w.zb_dev_on.len) w.zb_dev_on[w.live_zb_n] = d.on;
        var snap: settings_prefs.ZbDevSnap = .{
            .caps = d.caps,
            .level = d.level,
            .rssi = d.rssi,
            .lqi = d.lqi,
            .short_addr = d.short_addr,
            .volt_raw = d.volt_raw,
            .curr_raw = d.curr_raw,
            .power_raw = d.power_raw,
            .energy_raw = d.energy_raw,
            .sensors_seen = d.sensors_seen,
            .zone_status = d.zone_status,
            .zone_seen = d.zone_seen,
        };
        copySliceTo(&snap.id, std.mem.sliceTo(&d.id, 0));
        copySliceTo(&snap.model, std.mem.sliceTo(&d.model, 0));
        const model = std.mem.sliceTo(&d.model, 0);
        if (model.len > 0) {
            if (c.zb_devdb_find(model.ptr)) |entry| {
                if (entry.*.description) |desc_c| {
                    copySliceTo(&snap.desc, std.mem.span(desc_c));
                }
            }
        }
        w.live_zb_snap[w.live_zb_n] = snap;
        w.live_zb_n += 1;
    }
    w.zb_dev_n = w.live_zb_n;
}

fn syncThDevices(w: *settings_prefs.WirelessPrefs) void {
    const n = c.modulus_wireless_thread_device_count();
    w.live_th_n = 0;
    w.th_dev_n = 0;
    var i: c_int = 0;
    while (i < n and w.live_th_n < w.live_th.len) : (i += 1) {
        var d: c.modulus_th_device_t = undefined;
        if (!c.modulus_wireless_thread_device_get(i, &d)) continue;
        const name = std.mem.sliceTo(&d.name, 0);
        copySliceTo(&w.live_th[w.live_th_n], if (name.len > 0) name else std.mem.sliceTo(&d.ext_addr, 0));
        if (w.live_th_n < w.th_dev_on.len) w.th_dev_on[w.live_th_n] = d.on;
        w.live_th_n += 1;
    }
    w.th_dev_n = @min(w.live_th_n, 2);
}

/// Mirror radio status + finish async scans (call each UI frame).
pub fn wirelessPoll(eng: *Engine) void {
    c.modulus_wireless_poll();
    c.modulus_wireless_802154_poll();
    c.modulus_wireless_espnow_poll_scan();
    c.modulus_wireless_zigbee_join_poll();

    const w = &eng.prefs.wireless;
    const was_bt_on = g_prev_bt_on;
    // While prefs flush is pending, do not stomp enable bits with HW (toggle race).
    // Connection / counters still refresh.
    if (!g_prefs_dirty) {
        w.wifi = c.modulus_wireless_wifi_is_enabled();
        w.bt = c.modulus_wireless_ble_is_enabled();
        w.espnow = c.modulus_wireless_espnow_is_enabled();
        // Keep edge detectors aligned after async enable fail (toggle would stick).
        g_last_wifi = @intFromBool(w.wifi);
        g_last_bt = @intFromBool(w.bt);
        g_last_espnow = @intFromBool(w.espnow);
    }
    const was_wifi_conn = w.wifi_conn;
    const was_wifi_connecting = w.wifi_connecting;
    const was_bt_conn = w.bt_conn;
    const was_bt_connecting = w.bt_connecting;
    w.wifi_connecting = c.modulus_wireless_wifi_is_connecting();
    w.wifi_conn = c.modulus_wireless_wifi_is_connected();
    if (w.wifi_conn) {
        copyCStr(w.ssid[0..], c.modulus_wireless_wifi_ssid_text());
        copyCStr(w.ip[0..], c.modulus_wireless_wifi_ip_text());
    } else if (w.wifi_connecting and w.ssidSlice().len == 0) {
        copyCStr(w.ssid[0..], c.modulus_wireless_wifi_ssid_text());
    }
    copyCStr(w.wifi_status[0..], c.modulus_wireless_wifi_radio_text());

    if (w.bt) {
        w.bt_connecting = c.modulus_wireless_ble_is_connecting();
        w.bt_conn = c.modulus_wireless_ble_is_connected();
        if (w.bt_conn) {
            copyCStr(w.bt_name[0..], c.modulus_wireless_ble_paired_text());
        }
    } else {
        w.bt_connecting = false;
        w.bt_conn = false;
    }
    copyCStr(w.bt_status[0..], c.modulus_wireless_ble_status_text());

    if (was_bt_on and !w.bt and c.modulus_wireless_ble_enable_failed()) {
        if (!(c.modulus_c6_sdio_ready() and c.modulus_wireless_transport_up())) {
            eng.showSnackbarError("Bluetooth failed — C6 offline (dual-flash C6 UART COM18)");
        } else {
            eng.showSnackbarError("Bluetooth failed — retry or reboot Tab5");
        }
        eng.requestFull();
    }
    g_prev_bt_on = w.bt;

    if (was_wifi_connecting and !w.wifi_connecting) {
        if (!w.wifi_conn) {
            const err = std.mem.span(c.modulus_wireless_wifi_error_text());
            if (err.len > 0) {
                eng.showSnackbarError(err);
            } else {
                eng.showSnackbarError("Wi-Fi connection failed");
            }
            eng.requestFull();
        }
    }
    if (!was_wifi_conn and w.wifi_conn) {
        eng.showSnackbar("Wi-Fi connected");
        eng.requestFull();
        const cnc = eng.prefs.cnc;
        if (!cnc.transport_off and (cnc.conn == 1 or cnc.conn == 2) and !cnc.session_up) {
            if (eng.transport_reinit_sink) |s| s();
        }
    }
    if (was_bt_connecting and !w.bt_connecting and !w.bt_conn) {
        const st = std.mem.span(c.modulus_wireless_ble_status_text());
        if (std.mem.indexOf(u8, st, "failed") != null or std.mem.indexOf(u8, st, "Failed") != null) {
            eng.showSnackbarError("Bluetooth pairing failed");
            eng.requestFull();
        }
    } else if (!was_bt_conn and w.bt_conn) {
        eng.showSnackbar("Bluetooth connected");
        eng.requestFull();
    }

    w.en_tx = c.modulus_wireless_espnow_tx_count();
    w.en_rx = c.modulus_wireless_espnow_rx_count();
    syncEspnowSaved(eng);

    const was_zb_pending = w.zb_join_pending;
    w.zb_join_pending = c.modulus_wireless_zigbee_join_pending();
    w.zb_joined = c.modulus_wireless_zigbee_can_control();
    w.thread_supported = c.modulus_wireless_thread_supported();
    if (!w.thread_supported) {
        w.thread = false;
    }
    w.th_attached = c.modulus_wireless_thread_can_control();
    if (was_zb_pending and !w.zb_join_pending) {
        if (w.zb_joined) {
            eng.showSnackbar("Zigbee hub joined");
            eng.requestFull();
        } else {
            eng.showSnackbarError("Zigbee join failed — check NanoH2 / Grove / EXT 5V");
            eng.requestFull();
        }
    }
    if (w.zb_join_pending and !w.zb_joined) {
        copySliceTo(w.zb_status[0..], "Joining hub...");
    } else {
        copyCStr(w.zb_status[0..], c.modulus_wireless_zigbee_status_text());
    }
    copyCStr(w.zb_network[0..], c.modulus_wireless_zigbee_network_text());
    syncZbDevices(w);
    syncThDevices(w);

    if (w.scan_phase == 1 and c.modulus_wireless_wifi_scan_done()) {
        const count = c.modulus_wireless_wifi_scan_count();
        w.live_ap_n = 0;
        var i: c_int = 0;
        while (i < count and w.live_ap_n < w.live_ap.len) : (i += 1) {
            var ap: c.modulus_wifi_ap_t = undefined;
            if (!c.modulus_wireless_wifi_scan_get(i, &ap)) continue;
            const ssid = std.mem.sliceTo(&ap.ssid, 0);
            if (ssid.len == 0) continue; // skip hidden / empty
            copySliceTo(&w.live_ap[w.live_ap_n], ssid);
            w.live_ap_n += 1;
        }
        w.scan_n = w.live_ap_n;
        w.scan_phase = 2;
        w.wifi_scan_hw = false;
        w.scan_c6_down = w.scan_n == 0 and !(c.modulus_c6_sdio_ready() and c.modulus_wireless_transport_up());
        if (w.scan_c6_down) {
            eng.showSnackbarError("C6 offline — dual-flash C6 UART (COM18)");
        }
        eng.requestSettingsRepaint();
    }

    if (w.bt_scan_phase == 1 and c.modulus_wireless_ble_scan_done()) {
        const count = c.modulus_wireless_ble_scan_count();
        w.live_bt_n = 0;
        var i: c_int = 0;
        while (i < count and w.live_bt_n < w.live_bt.len) : (i += 1) {
            var name: [24]u8 = undefined;
            var addr: [24]u8 = undefined;
            var rssi: i8 = 0;
            if (!c.modulus_wireless_ble_scan_get(i, &name, name.len, &rssi, &addr, addr.len)) continue;
            const nm = std.mem.sliceTo(&name, 0);
            if (nm.len > 0) {
                copySliceTo(&w.live_bt[w.live_bt_n], nm);
            } else {
                copySliceTo(&w.live_bt[w.live_bt_n], std.mem.sliceTo(&addr, 0));
            }
            w.live_bt_rssi[w.live_bt_n] = rssi;
            w.live_bt_n += 1;
        }
        w.bt_scan_n = w.live_bt_n;
        w.bt_scan_phase = 2;
        w.bt_scan_hw = false;
        if (w.bt_scan_n == 0) {
            if (!(c.modulus_c6_sdio_ready() and c.modulus_wireless_transport_up())) {
                eng.showSnackbarError("No BLE devices — C6 offline (dual-flash COM18)");
            } else if (!c.modulus_wireless_ble_is_enabled()) {
                eng.showSnackbarError("No BLE devices — radio off");
            }
        }
        eng.requestSettingsRepaint();
    }

    if (w.en_scan_phase == 1) {
        if (c.modulus_wireless_espnow_scan_failed()) {
            w.en_scan_phase = 2;
            w.en_peer_n = 0;
            w.en_scan_hw = false;
            eng.showSnackbar("ESP-NOW scan failed");
            eng.requestSettingsRepaint();
        } else if (c.modulus_wireless_espnow_scan_done()) {
            const count = c.modulus_wireless_espnow_scan_count();
            w.live_en_n = 0;
            var i: c_int = 0;
            while (i < count and w.live_en_n < w.live_en.len) : (i += 1) {
                var peer: c.modulus_espnow_peer_t = undefined;
                if (!c.modulus_wireless_espnow_scan_get(i, &peer)) continue;
                copySliceTo(&w.live_en[w.live_en_n], std.mem.sliceTo(&peer.mac, 0));
                w.live_en_n += 1;
            }
            w.en_peer_n = w.live_en_n;
            w.en_scan_phase = 2;
            w.en_scan_hw = false;
            eng.requestSettingsRepaint();
        }
    }

    if (w.zb_scan_phase == 1 and c.modulus_wireless_zigbee_scan_done()) {
        const count = c.modulus_wireless_zigbee_scan_count();
        w.zb_scan_n = if (count > 0) @intCast(@min(count, 255)) else 0;
        w.zb_scan_phase = 2;
        w.zb_scan_hw = false;
        if (!w.zb_joined) {
            var i: c_int = 0;
            while (i < count and i < 2) : (i += 1) {
                _ = c.modulus_wireless_zigbee_scan_select(i);
            }
        }
        syncZbDevices(w);
        eng.requestFull();
    }

    if (w.th_scan_phase == 1 and c.modulus_wireless_thread_scan_done()) {
        const count = c.modulus_wireless_thread_scan_count();
        w.th_scan_n = if (count > 0) @intCast(@min(count, 255)) else 0;
        w.th_scan_phase = 2;
        w.th_scan_hw = false;
        {
            var i: c_int = 0;
            while (i < count and i < 2) : (i += 1) {
                _ = c.modulus_wireless_thread_scan_select(i);
            }
        }
        syncThDevices(w);
        eng.requestFull();
    }

    if (w.zb_energy_phase == 1 and w.zb_energy_hw) {
        const txt = c.modulus_wireless_zigbee_energy_text();
        const s = std.mem.span(txt);
        if (s.len > 0 and !std.mem.eql(u8, s, "Scanning...")) {
            copySliceTo(w.zb_energy_detail[0..], s);
            w.zb_energy_phase = 2;
            w.zb_energy_hw = false;
            eng.requestFull();
        }
    }

    // Status bar paints cnc.*_on — keep in sync with prefs after HW mirror.
    eng.cnc.wifi_on = w.wifi;
    eng.cnc.bt_on = w.bt;
    eng.cnc.espnow_on = w.espnow;
}

fn wirelessScanStart(eng: *Engine) void {
    const w = &eng.prefs.wireless;
    switch (w.page) {
        1 => {
            // Radio must be up before C6 scan (toggle can race enable worker).
            if (!w.wifi) {
                w.wifi = true;
                applyWirelessRadios(&eng.prefs);
            }
            w.live_ap_n = 0;
            w.startWifiScan();
            w.wifi_scan_hw = true;
            // Worker may wake C6 (seconds); stay on Scanning until scan_done.
            if (!c.modulus_wireless_wifi_scan_start()) {
                w.wifi_scan_hw = false;
                w.scan_phase = 2;
                w.scan_n = 0;
                w.scan_c6_down = !(c.modulus_c6_sdio_ready() and c.modulus_wireless_transport_up());
                eng.showSnackbarError(if (w.scan_c6_down)
                    "C6 offline — dual-flash C6 UART (COM18)"
                else
                    "Wi-Fi scan failed");
            }
        },
        2 => {
            if (!w.bt) {
                w.bt = true;
                applyWirelessRadios(&eng.prefs);
            }
            w.live_bt_n = 0;
            w.startBtScan();
            w.bt_scan_hw = true;
            if (!c.modulus_wireless_ble_scan_start()) {
                w.bt_scan_hw = false;
                w.bt_scan_phase = 2;
                w.bt_scan_n = 0;
                const c6_down = !(c.modulus_c6_sdio_ready() and c.modulus_wireless_transport_up());
                eng.showSnackbarError(if (c6_down)
                    "BLE scan failed — C6 offline (dual-flash COM18)"
                else
                    "BLE scan failed — enable radio / wait for Ready");
            }
        },
        3 => {
            w.live_en_n = 0;
            w.startEnScan();
            w.en_scan_hw = true;
            eng.requestSettingsRepaint(); // show Scanning... before worker finishes
            if (!c.modulus_wireless_espnow_scan_start()) {
                w.en_scan_hw = false;
                w.en_scan_phase = 2;
                w.en_peer_n = 0;
                eng.showSnackbar("ESP-NOW scan failed");
            }
        },
        4 => {
            w.startZbScan();
            w.zb_scan_hw = true;
            if (!c.modulus_wireless_zigbee_scan_start()) {
                w.zb_scan_hw = false;
                w.zb_scan_phase = 2;
                w.zb_scan_n = 0;
                eng.showSnackbar("Zigbee scan failed");
            }
        },
        5 => {
            w.startThScan();
            w.th_scan_hw = true;
            if (!c.modulus_wireless_thread_scan_start()) {
                w.th_scan_hw = false;
                w.th_scan_phase = 2;
                w.th_scan_n = 0;
                eng.showSnackbar("Thread scan failed");
            }
        },
        else => {},
    }
}

fn zTerm(buf: []u8, src: []const u8) [:0]const u8 {
    const n = @min(src.len, buf.len - 1);
    @memcpy(buf[0..n], src[0..n]);
    buf[n] = 0;
    return buf[0..n :0];
}

pub fn wirelessCmd(eng: *Engine, cmd: ui_engine.engine.WirelessUiCmd) void {
    switch (cmd) {
        .scan => wirelessScanStart(eng),
        .wifi_connect => |p| {
            if (!eng.prefs.wireless.wifi) {
                eng.prefs.wireless.wifi = true;
                applyWirelessRadios(&eng.prefs);
            }
            var sbuf: [33]u8 = undefined;
            var pbuf: [64]u8 = undefined;
            const ssid = zTerm(&sbuf, p.ssid);
            const pass = zTerm(&pbuf, p.pass);
            copySliceTo(eng.prefs.wireless.ssid[0..], p.ssid);
            if (!c.modulus_wireless_wifi_connect(ssid.ptr, pass.ptr)) {
                eng.prefs.wireless.wifi_connecting = false;
                eng.showSnackbarError("Wi-Fi connect failed — C6 / SDIO");
            } else {
                eng.prefs.wireless.wifi_connecting = true;
            }
        },
        .wifi_connect_saved => {
            if (!eng.prefs.wireless.wifi) {
                eng.prefs.wireless.wifi = true;
                applyWirelessRadios(&eng.prefs);
            }
            if (!c.modulus_wireless_wifi_connect_saved()) {
                eng.prefs.wireless.wifi_connecting = false;
                eng.showSnackbarError("No saved network");
            } else {
                eng.prefs.wireless.wifi_connecting = true;
            }
        },
        .wifi_forget => {
            c.modulus_wireless_wifi_forget_saved();
            eng.prefs.wireless.forgetSaved();
        },
        .wifi_disconnect => {
            _ = c.modulus_wireless_wifi_disconnect();
            eng.prefs.wireless.disconnectWifi();
            eng.prefs.wireless.wifi_connecting = false;
        },
        .ble_pair => |p| {
            if (!eng.prefs.wireless.bt) {
                eng.prefs.wireless.bt = true;
                applyWirelessRadios(&eng.prefs);
            }
            if (p.passkey.len > 0) {
                var pk: u32 = 0;
                for (p.passkey) |ch| {
                    if (ch < '0' or ch > '9') break;
                    pk = pk *% 10 + (ch - '0');
                }
                _ = c.modulus_wireless_ble_passkey_submit(pk);
            } else {
                _ = c.modulus_wireless_ble_passkey_confirm();
            }
            if (!c.modulus_wireless_ble_connect(@intCast(p.idx))) {
                eng.prefs.wireless.bt_connecting = false;
                eng.showSnackbarError("Bluetooth connect failed — enable radio");
            } else {
                eng.prefs.wireless.bt_connecting = true;
            }
        },
        .ble_disconnect => {
            c.modulus_wireless_ble_disconnect();
            eng.prefs.wireless.clearBtPaired();
            eng.prefs.wireless.bt_connecting = false;
        },
        .ble_clear => c.modulus_wireless_ble_clear_paired(),
        .en_select_scan => |idx| {
            _ = c.modulus_wireless_espnow_select_scan_peer(@intCast(idx));
            syncEspnowSaved(eng);
        },
        .en_activate_saved => |idx| {
            _ = c.modulus_wireless_espnow_activate_saved(@intCast(idx));
            syncEspnowSaved(eng);
        },
        .en_delete_saved => |idx| {
            _ = c.modulus_wireless_espnow_delete_saved(@intCast(idx));
            syncEspnowSaved(eng);
        },
        .en_clear => {
            c.modulus_wireless_espnow_clear_peers();
            syncEspnowSaved(eng);
        },
        .en_commit_mac => |mac| {
            var mbuf: [24]u8 = undefined;
            _ = c.modulus_wireless_espnow_set_peer_mac(zTerm(&mbuf, mac).ptr);
            syncEspnowSaved(eng);
        },
        .zb_join => {
            // Radio must be on before HUB_START; Zig UI used to join with radio off.
            if (!eng.prefs.wireless.zigbee) {
                eng.prefs.wireless.zigbee = true;
                applyWirelessRadios(&eng.prefs);
            }
            if (!c.modulus_wireless_zigbee_join()) {
                eng.prefs.wireless.zb_join_pending = false;
                eng.showSnackbarError("Zigbee join failed — radio / UART");
            } else {
                eng.prefs.wireless.zb_join_pending = true;
            }
        },
        .zb_leave => {
            _ = c.modulus_wireless_zigbee_leave();
            eng.prefs.wireless.zb_join_pending = false;
            eng.prefs.wireless.zb_joined = false;
        },
        .zb_toggle => |idx| _ = c.modulus_wireless_zigbee_device_toggle(@intCast(idx)),
        .zb_identify => |idx| _ = c.modulus_wireless_zigbee_device_identify(@intCast(idx)),
        .zb_remove => |idx| {
            _ = c.modulus_wireless_zigbee_device_leave(@intCast(idx));
            syncZbDevices(&eng.prefs.wireless);
        },
        .zb_sensors => |idx| _ = c.modulus_wireless_zigbee_device_read_sensors(@intCast(idx)),
        .zb_cover => |p| _ = c.modulus_wireless_zigbee_device_cover(@intCast(p.idx), p.op),
        .zb_level => |p| _ = c.modulus_wireless_zigbee_device_set_level(@intCast(p.idx), p.level),
        .zb_refresh => {
            syncZbDevices(&eng.prefs.wireless);
        },
        .zb_clear => {
            c.modulus_wireless_zigbee_devices_clear();
            eng.prefs.wireless.live_zb_n = 0;
            eng.prefs.wireless.zb_dev_n = 0;
        },
        .zb_energy => {
            eng.prefs.wireless.startEnergyScan();
            eng.prefs.wireless.zb_energy_hw = true;
            if (!c.modulus_wireless_zigbee_energy_scan()) {
                eng.prefs.wireless.zb_energy_hw = false;
                eng.prefs.wireless.zb_energy_phase = 0;
                eng.showSnackbar("Energy scan failed");
            }
        },
        .zb_add_code => |code| {
            var cbuf: [40]u8 = undefined;
            _ = c.modulus_wireless_zigbee_device_add("Device", "", 1, zTerm(&cbuf, code).ptr);
            syncZbDevices(&eng.prefs.wireless);
        },
        .th_attach => _ = c.modulus_wireless_thread_attach(),
        .th_detach => _ = c.modulus_wireless_thread_detach(),
        .th_toggle => |idx| _ = c.modulus_wireless_thread_device_toggle(@intCast(idx)),
        .th_clear => {
            c.modulus_wireless_thread_devices_clear();
            eng.prefs.wireless.live_th_n = 0;
            eng.prefs.wireless.th_dev_n = 0;
        },
        .th_add_node => |node| {
            var nbuf: [40]u8 = undefined;
            _ = c.modulus_wireless_thread_device_add("Node", zTerm(&nbuf, node).ptr);
            syncThDevices(&eng.prefs.wireless);
        },
    }
}

pub fn wifiScanStart(eng: *Engine) void {
    eng.prefs.wireless.page = 1;
    wirelessScanStart(eng);
}

pub fn wifiConnect(ssid: []const u8, pass: []const u8) void {
    var sbuf: [33]u8 = undefined;
    var pbuf: [64]u8 = undefined;
    _ = c.modulus_wireless_wifi_connect(zTerm(&sbuf, ssid).ptr, zTerm(&pbuf, pass).ptr);
}

pub fn wifiDisconnect() void {
    _ = c.modulus_wireless_wifi_disconnect();
}

pub fn noteUserActivity() void {
    c.modulus_display_note_user_activity();
}

pub fn pollPinLock(eng: *Engine) void {
    if (isPinLocked() and eng.screen != .pin and eng.screen != .boot) {
        eng.screen = .pin;
        eng.requestFull();
    }
}

pub fn machPullBegin() void {
    device_runtime.settingsDumpBegin();
}

pub fn machPullTick(eng: *Engine) ui_engine.engine.MachPullTick {
    if (device_runtime.settingsDumpFailed()) {
        device_runtime.settingsDumpCancel();
        return .failed;
    }
    if (device_runtime.settingsDumpReady()) {
        const n = device_runtime.applyDumpEnvelope();
        prefs_nvs.loadMachineEnvelope(&eng.prefs);
        eng.applyPrefsPublic();
        return if (n > 0) .applied else .empty;
    }
    if (eng.mach_pull_polls > 40) {
        device_runtime.settingsDumpCancel();
        return .timeout;
    }
    return .pending;
}

pub fn machPush() void {
    device_runtime.syncEnvelopeToController();
}

pub fn maintReset() void {
    device_runtime.maintResetCounters();
    device_runtime.reloadMachineLimits();
}

fn bytesToGbX10(bytes: u64) u16 {
    // GB * 10 = bytes * 10 / 1e9
    const x10 = bytes / 100_000_000;
    return @intCast(@min(x10, 65535));
}

fn i2cTargetToC(zig_target: u8) c.modulus_i2c_scan_target_t {
    return switch (zig_target) {
        1 => c.MODULUS_I2C_SCAN_PORT_A,
        2 => c.MODULUS_I2C_SCAN_MBUS,
        3 => c.MODULUS_I2C_SCAN_EXP1,
        4 => c.MODULUS_I2C_SCAN_EXP2,
        else => c.MODULUS_I2C_SCAN_ALL,
    };
}

fn copyI2cLine(dst: *settings_prefs.StoragePrefs, which: u8, src: [*:0]const u8) void {
    var tmp: [96]u8 = undefined;
    copyCStr(tmp[0..], src);
    dst.setLiveLine(which, std.mem.sliceTo(&tmp, 0));
}

fn storagePoll(eng: *Engine) void {
    // No storage_init here — installLate() owns it. Calling an init from a 2 s
    // poll re-read NVS and retried the SD mount on every tick.
    var sd: c.modulus_sd_info_t = undefined;
    c.modulus_storage_get_sd_info(&sd);
    eng.prefs.storage.sd = switch (sd.state) {
        c.MODULUS_SD_MOUNTED => .mounted,
        c.MODULUS_SD_ERROR => .failed,
        else => .unmounted,
    };
    eng.prefs.storage.syncMounted();
    if (sd.state == c.MODULUS_SD_MOUNTED) {
        eng.prefs.storage.sd_free_gb_x10 = bytesToGbX10(sd.free_bytes);
        eng.prefs.storage.sd_total_gb_x10 = bytesToGbX10(sd.total_bytes);
    }

    var mem: c.modulus_mem_info_t = undefined;
    c.modulus_storage_get_mem_info(&mem);
    eng.prefs.storage.int_free_kb = @intCast(mem.internal_free / 1024);
    eng.prefs.storage.int_total_kb = @intCast(mem.internal_total / 1024);
    eng.prefs.storage.min_free_kb = @intCast(mem.internal_min_free / 1024);
    eng.prefs.storage.ps_free_mb = @intCast(mem.psram_free / (1024 * 1024));
    eng.prefs.storage.ps_total_mb = @intCast(mem.psram_total / (1024 * 1024));
    eng.prefs.storage.lvgl_free_kb = @intCast(mem.lvgl_free / 1024);
    eng.prefs.storage.lvgl_used_pct = mem.lvgl_used_pct;
    eng.prefs.storage.usb_host = c.modulus_storage_is_usb_host_enabled();

    const m = device_runtime.maintMeters();
    eng.prefs.machine.odo_mm = m.travel_mm;
    eng.prefs.machine.sph_sec = m.spindle_sec;
    eng.prefs.machine.run_sec = m.run_sec;

    if (eng.prefs.storage.i2c_scan_hw) {
        if (c.modulus_i2c_scan_busy()) {
            eng.prefs.storage.i2c_scan_phase = 1;
        } else if (c.modulus_i2c_scan_done()) {
            copyI2cLine(&eng.prefs.storage, 1, c.modulus_i2c_scan_port_a_text());
            copyI2cLine(&eng.prefs.storage, 2, c.modulus_i2c_scan_mbus_text());
            copyI2cLine(&eng.prefs.storage, 3, c.modulus_i2c_scan_exp1_text());
            copyI2cLine(&eng.prefs.storage, 4, c.modulus_i2c_scan_exp2_text());
            eng.prefs.storage.i2c_scan_phase = 2;
            eng.prefs.storage.i2c_scan_hw = false;
        }
    }

    if (eng.prefs.storage.diag_flash_frames > 0) eng.prefs.storage.diag_flash_frames -= 1;
    if (eng.prefs.storage.backup_flash_frames > 0) eng.prefs.storage.backup_flash_frames -= 1;

    c.modulus_rtc_ntp_poll();
}

pub fn storSysCmd(eng: *Engine, cmd: ui_engine.engine.StorSysUiCmd) void {
    switch (cmd) {
        .mount => {
            c.modulus_storage_init();
            if (c.modulus_storage_mount()) {
                eng.prefs.storage.mount();
            } else {
                eng.prefs.storage.sd = .failed;
                eng.prefs.storage.syncMounted();
            }
            storagePoll(eng);
        },
        .unmount => {
            c.modulus_storage_unmount();
            eng.prefs.storage.eject();
            storagePoll(eng);
        },
        .export_diag => {
            storagePoll(eng);
            if (eng.prefs.storage.sd != .mounted) {
                eng.prefs.storage.markExportOk(true, "Need SD card");
                return;
            }
            if (c.modulus_storage_export_diagnostics("/sdcard/modulus_diag.txt")) {
                eng.prefs.storage.markExportOk(true, "Saved modulus_diag.txt");
            } else {
                eng.prefs.storage.markExportOk(true, "Export failed");
            }
        },
        .export_settings => {
            storagePoll(eng);
            if (eng.prefs.storage.sd != .mounted) {
                eng.prefs.storage.markExportOk(false, "Need SD");
                return;
            }
            if (c.modulus_storage_export_settings("/sdcard/modulus_settings.json", false)) {
                eng.prefs.storage.markExportOk(false, "Exported");
            } else {
                eng.prefs.storage.markExportOk(false, "Export failed");
            }
        },
        .import_settings => {
            if (c.modulus_storage_import_settings("/sdcard/modulus_settings.json", false)) {
                loadPrefs(&eng.prefs);
                eng.applyPrefsPublic();
            }
        },
        .clear_cache => c.modulus_storage_clear_ui_cache(),
        .poll => storagePoll(eng),
        .i2c_scan => |target| {
            c.modulus_i2c_scan_init();
            eng.prefs.storage.i2c_scan_hw = true;
            eng.prefs.storage.i2c_scan_phase = 1;
            if (!c.modulus_i2c_scan_start(i2cTargetToC(target))) {
                eng.prefs.storage.i2c_scan_hw = false;
                eng.prefs.storage.i2c_scan_phase = 0;
            }
        },
        .ntp_sync => {
            if (!eng.prefs.system.ntp) return;
            c.modulus_rtc_ntp_set_enabled(true);
            _ = c.modulus_rtc_ntp_sync_now();
        },
        .rtc_set => |t| {
            _ = c.modulus_rtc_set_local_time(
                @intCast(t.year),
                @intCast(t.month),
                @intCast(t.day),
                @intCast(t.hour),
                @intCast(t.min),
                @intCast(t.sec),
            );
            _ = c.modulus_rtc_write_hw_from_system();
        },
    }
}

/// Map driver session enum → CNC tab session_phase (0/2/3).
pub fn mirrorCncSession(eng: *Engine, connected: u8, session: u8) void {
    eng.prefs.cnc.tickConnectHold();
    if (eng.prefs.cnc.transport_off) {
        eng.prefs.cnc.session_up = false;
        eng.prefs.cnc.session_phase = 0;
        eng.prefs.cnc.connect_hold_frames = 0;
        return;
    }
    // SessionState: disconnected=0, wait_banner..configuring=1..3, ready+=4
    if (connected != 0 and session >= 4) {
        eng.prefs.cnc.session_up = true;
        eng.prefs.cnc.session_phase = 3;
        eng.prefs.cnc.connect_hold_frames = 0;
    } else if (connected != 0 or session >= 1) {
        eng.prefs.cnc.session_up = false;
        eng.prefs.cnc.session_phase = 2;
    } else if (eng.prefs.cnc.connect_hold_frames > 0) {
        // Optimistic Connecting from Connect/peer select — keep until hold expires.
        eng.prefs.cnc.session_up = false;
        eng.prefs.cnc.session_phase = 2;
    } else {
        // Driver fully idle — clear sticky Connecting so Disconnect/retry work.
        eng.prefs.cnc.session_up = false;
        eng.prefs.cnc.session_phase = 0;
    }
}

pub fn mirrorBatteryClock(eng: *Engine) void {
    var st: c.modulus_battery_status_t = undefined;
    if (c.modulus_battery_get_status(&st)) {
        eng.cnc.battery_pct = @min(st.percent, 100);
        eng.cnc.battery_charge_state = st.charge_state;
        eng.cnc.battery_charging = st.charge_state == 1 or st.charge_state == 2;
        eng.cnc.battery_fast_charge = ui_engine.battery_chrome.isFastCharge(st.charge_state, st.rate_mA);
        eng.prefs.power_tel.bat_pct = eng.cnc.battery_pct;
        eng.prefs.power_tel.charge_state = st.charge_state;
        eng.prefs.power_tel.bat_v = st.voltage;
        eng.prefs.power_tel.bat_ma = st.current * 1000.0;
        eng.prefs.power_tel.bat_rate_ma = st.rate_mA;
        eng.prefs.power_tel.bat_w = st.power;
        eng.prefs.power_tel.bat_eta_min = if (st.charge_state == 1) st.time_to_full else st.time_to_empty;
        eng.prefs.power_tel.cpu_temp_c = st.cpu_temp;
        eng.prefs.power_tel.ina_ok = true;
    } else {
        eng.prefs.power_tel.ina_ok = false;
    }

    var tbuf: [16]u8 = undefined;
    c.modulus_rtc_format_time(@ptrCast(&tbuf), tbuf.len);
    const clock = std.mem.sliceTo(&tbuf, 0);
    const n = @min(clock.len, eng.cnc.clock_buf.len - 1);
    @memcpy(eng.cnc.clock_buf[0..n], clock[0..n]);
    eng.cnc.clock_buf[n] = 0;

    eng.prefs.system.rtc_live = true;
    @memset(&eng.prefs.system.time_live, 0);
    @memcpy(eng.prefs.system.time_live[0..@min(clock.len, eng.prefs.system.time_live.len - 1)], clock[0..@min(clock.len, eng.prefs.system.time_live.len - 1)]);

    var dbuf: [24]u8 = undefined;
    c.modulus_rtc_format_date(@ptrCast(&dbuf), dbuf.len);
    const date = std.mem.sliceTo(&dbuf, 0);
    @memset(&eng.prefs.system.date_live, 0);
    @memcpy(eng.prefs.system.date_live[0..@min(date.len, eng.prefs.system.date_live.len - 1)], date[0..@min(date.len, eng.prefs.system.date_live.len - 1)]);

    const ntp = std.mem.span(c.modulus_rtc_ntp_status_text());
    @memset(&eng.prefs.system.ntp_live, 0);
    @memcpy(eng.prefs.system.ntp_live[0..@min(ntp.len, eng.prefs.system.ntp_live.len - 1)], ntp[0..@min(ntp.len, eng.prefs.system.ntp_live.len - 1)]);
    eng.prefs.system.ntp_synced = std.mem.eql(u8, ntp, "Synced");
}

/// C6 SDIO link + health counters for System health strip / detail.
pub fn mirrorC6Sdio(eng: *Engine) void {
    eng.prefs.system.c6_ready = c.modulus_c6_sdio_ready() and c.modulus_wireless_ready();
    var h: c.modulus_c6_sdio_health_t = .{ .stream_drop = 0, .queue_stall = 0, .pad_skip = 0 };
    c.modulus_c6_sdio_health_get(&h);
    eng.prefs.system.sdio_stream_drop = h.stream_drop;
    eng.prefs.system.sdio_queue_stall = h.queue_stall;
    eng.prefs.system.sdio_pad_skip = h.pad_skip;
}

pub fn drainConsole(eng: *Engine) void {
    var dir: u8 = 0;
    var line: [96]u8 = undefined;
    var safety: u8 = 0;
    while (safety < 8) : (safety += 1) {
        const n = console_log.pop(&dir, &line);
        if (n < 0) break;
        const slice = line[0..@intCast(n)];
        quick_settings.termAppend(&eng.qs_term, &eng.qs_term_len, slice, dir != 0);
    }
}

/// Edits fire per touch sample (slider drag), so only live feedback runs inline.
/// Flash is coalesced by `pollPrefsFlush`. Radios apply immediately — otherwise
/// `wirelessPoll` mirrors HW off and clears the toggle before the 400 ms flush.
pub fn prefsDirty(eng: *Engine) void {
    applyBrightVol(&eng.prefs);
    applyTone(&eng.prefs);
    applyDisplayTimeouts(&eng.prefs);
    applyWirelessRadios(&eng.prefs);
    g_prefs_dirty = true;
    g_prefs_dirty_ms = nowMs();
}

/// Persist + apply policy once edits go quiet. Call every UI frame.
pub fn pollPrefsFlush(eng: *Engine) void {
    if (!g_prefs_dirty) return;
    if (nowMs() -| g_prefs_dirty_ms < prefs_flush_idle_ms) return;
    flushPrefs(eng);
}

pub fn flushPrefs(eng: *Engine) void {
    if (!g_prefs_dirty) return;
    g_prefs_dirty = false;
    savePrefs(&eng.prefs);
    applyWirelessRadios(&eng.prefs);
    applyPowerPolicy(&eng.prefs);
    // Same reasoning as applyPowerPolicy: these log and touch hardware, so
    // only push on a real change.
    if (g_applied_mic == null or g_applied_mic.? != eng.prefs.audio.mic_gain) {
        g_applied_mic = eng.prefs.audio.mic_gain;
        c.modulus_audio_set_mic_gain_idx(eng.prefs.audio.mic_gain);
    }
    if (g_applied_ntp == null or g_applied_ntp.? != eng.prefs.system.ntp) {
        g_applied_ntp = eng.prefs.system.ntp;
        c.modulus_rtc_ntp_set_enabled(eng.prefs.system.ntp);
    }
    if (g_applied_tz == null or g_applied_tz.? != eng.prefs.system.tz_idx) {
        g_applied_tz = eng.prefs.system.tz_idx;
        c.modulus_rtc_tz_changed(eng.prefs.system.tz_idx);
    }
}

/// Never lose an edit to a power transition.
fn flushPendingPrefs() void {
    if (g_eng) |eng| flushPrefs(eng);
}

/// Last power settings pushed to the HAL.
///
/// `PowerPrefs` is now settings-only (live readings live in `PowerTelemetry`),
/// so comparing the struct directly is sound — it was not while telemetry
/// shared the struct, because every INA226 sample made it unequal and the gate
/// silently never held. Keeping the gate matters: `flushPrefs` runs after every
/// settings edit, and `modulus_power_set_ext5v` kicks an ExtEncoder re-probe
/// that holds the I2C coex lock for ~815 ms, which the touch read also needs.
/// Ungated, that dragged the UI from 99 polls/s to 11-40/s.
var g_applied_power: ?settings_prefs.PowerPrefs = null;
var g_applied_tz: ?u8 = null;
var g_applied_mic: ?u8 = null;
var g_applied_ntp: ?bool = null;

/// Call when something outside prefs may have moved the rails (deep-sleep
/// wake, power-save gating) so the next flush re-drives them.
pub fn invalidatePowerCache() void {
    g_applied_power = null;
}

fn applyPowerPolicy(p: *const settings_prefs.Prefs) void {
    if (g_applied_power) |prev| {
        if (std.meta.eql(prev, p.power)) return;
    }
    g_applied_power = p.power;
    c.modulus_power_set_ext5v(p.power.ext5v);
    c.modulus_power_set_usb5v(p.power.usb5v);
    c.modulus_power_set_charge_en(p.power.chg_en);
    c.modulus_power_set_quick_charge(p.power.qc);
    c.modulus_power_set_wake_sources(p.power.wakeBits());
    c.modulus_power_set_wake_timer_min(p.power.wtminMin());
    c.modulus_power_set_gate_wifi(p.power.gate_wifi);
    c.modulus_power_set_gate_ext5v(p.power.gate_ext);
    c.modulus_power_set_gate_usb5v(p.power.gate_usb);
    c.modulus_power_set_sleep_policy(p.power.pwr_mode, p.power.dstoSec());
    c.modulus_battery_set_pack_type(p.power.bat_type);
    c.modulus_battery_set_low_warn_pct(p.power.batWarnPct());
    c.modulus_battery_set_adaptive(p.power.bat_adapt);
    c.modulus_power_apply_rails();
}

pub fn sendMdi(line: []const u8) void {
    device_runtime.sendGcode(line);
}

pub fn powerRestart() void {
    flushPendingPrefs();
    c.modulus_power_request(true);
}

pub fn powerShutdown() void {
    flushPendingPrefs();
    c.modulus_power_request(false);
}

pub fn powerDeepSleep() void {
    flushPendingPrefs();
    c.modulus_power_enter_deep_sleep();
}

pub fn pinVerify(digits: []const u8) bool {
    var buf: [16]u8 = undefined;
    const n = @min(digits.len, buf.len - 1);
    @memcpy(buf[0..n], digits[0..n]);
    buf[n] = 0;
    return c.modulus_security_verify_pin(buf[0..n :0].ptr);
}

pub fn pinUnlock() void {
    c.modulus_security_unlock();
}

pub fn pinSet(digits: []const u8) bool {
    var buf: [16]u8 = undefined;
    const n = @min(digits.len, buf.len - 1);
    @memcpy(buf[0..n], digits[0..n]);
    buf[n] = 0;
    return c.modulus_security_set_pin(buf[0..n :0].ptr);
}

pub fn pinClear(current: []const u8) bool {
    var buf: [16]u8 = undefined;
    const n = @min(current.len, buf.len - 1);
    @memcpy(buf[0..n], current[0..n]);
    buf[n] = 0;
    return c.modulus_security_clear_pin(buf[0..n :0].ptr);
}

pub fn isPinLocked() bool {
    return c.modulus_security_is_locked();
}

pub fn factoryReset() void {
    _ = c.modulus_factory_reset();
    c.modulus_power_request(true);
}

pub fn transportReinit() void {
    // Connect/Disconnect/profile must hit NVS before the Core-0 worker reads
    // `cnc_conn` / `en_mac`. Deferred 400 ms flush left Disconnect's 255 in NVS
    // so ESP-NOW Connect reinit started nothing → Connecting then Disconnected.
    flushPendingPrefs();
    device_runtime.transportReinit();
}

pub fn dumpBegin() void {
    device_runtime.settingsDumpBegin();
}

pub fn dumpCancel() void {
    device_runtime.settingsDumpCancel();
}

pub fn dumpTick(dump: *ui_engine.settings_cnc_modals.DumpState) bool {
    if (!dump.open or dump.ready or dump.failed) return false;
    if (device_runtime.settingsDumpFailed()) {
        dump.failed = true;
        return true;
    }
    if (!device_runtime.settingsDumpReady()) {
        if (dump.ticks < 90) dump.ticks +|= 3;
        return true;
    }
    dump.len = device_runtime.settingsDumpCopy(dump.buf[0..]);
    dump.ready = true;
    dump.ticks = 100;
    return true;
}

pub fn probeStart(cycle: u8) bool {
    return device_runtime.probeStart(cycle);
}

pub fn probeBusy() bool {
    return device_runtime.probeBusy();
}

pub fn probePin() bool {
    return device_runtime.probePin() != 0;
}

pub fn install(eng: *Engine) void {
    g_eng = eng;
    loadPrefs(&eng.prefs);
    eng.applyPrefsPublic();
    applyBrightVol(&eng.prefs);
    applyTone(&eng.prefs);
    applyDisplayTimeouts(&eng.prefs);
    // Wireless radios deferred to installLate (needs hosted/C6 bring-up).
    g_last_bright = eng.prefs.display.bright;
    g_last_vol = eng.prefs.audio.vol;
    g_last_silent = eng.prefs.audio.silent;
    g_last_tone = eng.prefs.audio.tone_prof;

    eng.prefs_dirty_sink = prefsDirty;
    eng.gcode_sink = sendMdi;
    eng.power_restart_sink = powerRestart;
    eng.power_shutdown_sink = powerShutdown;
    eng.power_sleep_sink = powerDeepSleep;
    eng.pin_verify_sink = pinVerify;
    eng.pin_unlock_sink = pinUnlock;
    eng.pin_set_sink = pinSet;
    eng.pin_clear_sink = pinClear;
    eng.factory_reset_sink = factoryReset;
    eng.transport_reinit_sink = transportReinit;
    eng.dump_begin_sink = dumpBegin;
    eng.dump_cancel_sink = dumpCancel;
    eng.dump_tick_sink = dumpTick;
    eng.probe_start_sink = probeStart;
    eng.probe_busy_sink = probeBusy;
    eng.probe_pin_sink = probePin;
    eng.mach_pull_begin_sink = machPullBegin;
    eng.mach_pull_tick_sink = machPullTick;
    eng.mach_push_sink = machPush;
    eng.maint_reset_sink = maintReset;
    eng.wireless_cmd_sink = wirelessCmd;
    eng.wifi_scan_sink = wifiScanStart;
    eng.wifi_connect_sink = wifiConnect;
    eng.wifi_disconnect_sink = wifiDisconnect;
    eng.stor_sys_sink = storSysCmd;

    // storage / i2c / wireless deferred to installLate — after boot i2c_coex.
    c.modulus_display_resume_activity_monitor();

    // Do not steal .boot for pin here — finishBoot / pollPinLock own that after
    // the splash hold. Jumping to .pin mid-install blanked the panel for seconds.
}

/// Call after boot HAL `i2c_coex_init` + `storage_init` (ui_boot_arm phase).
pub fn installLate(eng: *Engine) void {
    applyWirelessRadios(&eng.prefs);
    c.modulus_storage_init();
    c.modulus_i2c_scan_init();
    storagePoll(eng);
    mirrorBatteryClock(eng);
}
