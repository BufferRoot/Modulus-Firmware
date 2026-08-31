//! Device/host UI command unions — pure types (no Engine / paint / alloc).

/// Device wireless side-effects (C6). Host leaves `wireless_cmd_sink` null.
pub const WirelessUiCmd = union(enum) {
    scan,
    wifi_connect: struct { ssid: []const u8, pass: []const u8 },
    wifi_connect_saved,
    wifi_forget,
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
    zb_color_temp: struct { idx: u8, mireds: u16 },
    zb_color_xy: struct { idx: u8, x: u16, y: u16 },
    zb_effect: struct { idx: u8, effect: u8 },
    zb_light_type: struct { idx: u8, typ: u8 },
    zb_min_level: struct { idx: u8, level: u8 },
    zb_max_level: struct { idx: u8, level: u8 },
    zb_countdown: struct { idx: u8, seconds: u32 },
    zb_child_lock: struct { idx: u8, on: bool },
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
    format_sd,
    export_diag,
    export_settings,
    import_settings,
    /// Path is null-terminated in a stack buffer at the sink.
    export_settings_to: []const u8,
    import_settings_from: []const u8,
    export_diag_to: []const u8,
    clear_cache,
    poll,
    /// Arm the USB file at this catalog index as the pending job. Does NOT
    /// move the machine — Cycle Start claims MPG and starts streaming.
    job_load_usb: u8,
    /// Operator pressed Cycle Start with a job armed.
    job_start,
    /// Feed hold while streaming.
    job_hold,
    /// Resume after a hold.
    job_resume,
    /// Abort: soft reset + release MPG.
    job_abort,
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
