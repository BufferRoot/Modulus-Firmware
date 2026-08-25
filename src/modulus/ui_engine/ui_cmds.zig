//! Device/host UI command unions — pure types (no Engine / paint / alloc).

/// Device wireless side-effects (C6). Host leaves `wireless_cmd_sink` null.
pub const WirelessUiCmd = union(enum) {
    scan,
    wifi_connect: struct { ssid: []const u8, pass: []const u8 },
    wifi_disconnect,
    ble_pair: struct { idx: u8, passkey: []const u8 },
    ble_disconnect,
    ble_clear,
    en_select_scan: u8,
    en_activate_saved: u8,
    en_delete_saved: u8,
    en_clear,
    en_commit_mac: []const u8,
    zb_join,
    zb_leave,
    zb_toggle: u8,
    zb_identify: u8,
    zb_remove: u8,
    zb_sensors: u8,
    zb_cover: struct { idx: u8, op: u8 },
    zb_level: struct { idx: u8, level: u8 },
    zb_refresh,
    zb_clear,
    zb_energy,
    zb_add_code: []const u8,
    th_attach,
    th_detach,
    th_toggle: u8,
    th_clear,
    th_add_node: []const u8,
};

/// Storage / I2C / RTC — device sinks; host keeps prefs stubs.
pub const StorSysUiCmd = union(enum) {
    mount,
    unmount,
    export_diag,
    export_settings,
    import_settings,
    clear_cache,
    poll,
    i2c_scan: u8, // Zig target: 0=all 1=PortA 2=M-Bus 3=EXP1 4=EXP2
    ntp_sync,
    rtc_set: struct { year: u16, month: u8, day: u8, hour: u8, min: u8, sec: u8 },
};

pub const CncUiCmd = union(enum) {
    cycle_start,
    stop,
    unlock,
    reset,
    feed_hold,
    home_all,
    home_axis: u8,
    zero_axis: u8,
    zero_all,
    set_jog_mode: u8,
    set_step_size: u8,
    set_active_axis: u8,
    spindle_cw,
    spindle_ccw,
    coolant_toggle,
    mist_toggle,
    fan_toggle,
    single_step,
    run_macro,
};
