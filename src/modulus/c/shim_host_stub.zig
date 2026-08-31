//! Host-test extern stubs — mirror `modulus_shims_bundle.h` symbols (never called on host).
//! Tab5 device builds use translate-C `@import("modulus_shims")` from `build.zig`.

pub const modulus_event_msg_t = extern struct {
    id: u16,
    data: [64]u8,
    data_len: u32,
};

pub const modulus_battery_status_t = extern struct {
    voltage: f32,
    current: f32,
    power: f32,
    percent: u8,
    charge_state: u8,
    cpu_temp: f32,
    rate_mA: f32,
    time_to_empty: i32,
    time_to_full: i32,
};

pub const modulus_cnc_status_t = extern struct {
    state: u8 = 0,
    connected: u8 = 0,
    session: u8 = 0,
    mpg_active: u8 = 0,
    jog_mode: u8 = 0,
    step_size: u8 = 0,
    wpos_x: f32 = 0,
    wpos_y: f32 = 0,
    wpos_z: f32 = 0,
    wpos_a: f32 = 0,
    wpos_b: f32 = 0,
    wpos_c: f32 = 0,
    feed_rate: f32 = 0,
    feed_ovr: u8 = 0,
    spindle_ovr: u8 = 0,
    rapid_ovr: u8 = 0,
    wcs: u8 = 0,
    tool_number: u8 = 0,
    active_axis: u8 = 0,
    units_mm: u8 = 0,
    spindle_rpm: u32 = 0,
    mpos_x: f32 = 0,
    mpos_y: f32 = 0,
    mpos_z: f32 = 0,
    mpos_a: f32 = 0,
    mpos_b: f32 = 0,
    mpos_c: f32 = 0,
    homing_block: u8 = 0,
    accessories: u8 = 0,
    sd_percent: f32 = 0,
    line_number: u32 = 0,
    sd_streaming: u8 = 0,
    alarm_code: u8 = 0,
    sd_file: [32]u8 = .{0} ** 32,
};

pub const modulus_sd_state_t = enum(c_int) {
    MODULUS_SD_NOT_PRESENT = 0,
    MODULUS_SD_MOUNTED,
    MODULUS_SD_ERROR,
};

pub const modulus_sd_info_t = extern struct {
    state: modulus_sd_state_t,
    total_bytes: u64,
    free_bytes: u64,
    bus_width: u8,
};

pub const modulus_mem_info_t = extern struct {
    internal_free: usize,
    internal_total: usize,
    internal_min_free: usize,
    psram_free: usize,
    psram_total: usize,
    lvgl_free: usize,
    lvgl_used_pct: u8,
};

pub const modulus_serial_rx_fn = ?*const fn ([*c]const u8, usize) callconv(.c) void;

extern fn modulus_event_init() void;
extern fn modulus_event_publish(id: u16, data: ?[*]const u8, len: u32) bool;
extern fn modulus_event_receive(out: *modulus_event_msg_t) bool;

extern fn modulus_nvs_init() c_int;
extern fn modulus_nvs_has_u8(key: [*:0]const u8) bool;
extern fn modulus_nvs_get_u8(key: [*:0]const u8, def: u8) u8;
extern fn modulus_nvs_set_u8(key: [*:0]const u8, val: u8) c_int;
extern fn modulus_nvs_get_u16(key: [*:0]const u8, def: u16) u16;
extern fn modulus_nvs_set_u16(key: [*:0]const u8, val: u16) c_int;
extern fn modulus_nvs_get_str(key: [*:0]const u8, buf: [*]u8, buf_len: usize) bool;
extern fn modulus_nvs_set_str(key: [*:0]const u8, val: [*:0]const u8) c_int;
extern fn modulus_nvs_begin_batch() void;
extern fn modulus_nvs_end_batch() void;
extern fn modulus_nvs_erase_all() c_int;

extern fn modulus_ws_start(host: [*:0]const u8, port: u16, path: [*:0]const u8, tls: bool) bool;
extern fn modulus_ws_stop() void;
extern fn modulus_ws_send(data: [*]const u8, len: usize) bool;
extern fn modulus_ws_is_connected() bool;
extern fn modulus_telnet_start(host: [*:0]const u8, port: u16) bool;
extern fn modulus_telnet_stop() void;
extern fn modulus_telnet_send(data: [*]const u8, len: usize) bool;
extern fn modulus_telnet_is_connected() bool;
extern fn modulus_masso_udp_start(host: [*:0]const u8, tx_port: u16, rx_port: u16) bool;
extern fn modulus_masso_udp_stop() void;
extern fn modulus_masso_udp_send(data: [*]const u8, len: usize) bool;
extern fn modulus_masso_udp_is_connected() bool;
extern fn modulus_i2c_transport_start(addr: u8, spd_idx: u8) bool;
extern fn modulus_i2c_transport_stop() void;
extern fn modulus_i2c_transport_send(data: [*]const u8, len: usize) bool;
extern fn modulus_canbus_start(brate_idx: u8, nid: u8, mode_idx: u8) bool;
extern fn modulus_canbus_stop() void;
extern fn modulus_canbus_send(data: [*]const u8, len: usize) bool;
extern fn modulus_espnow_transport_start(mac: [*:0]const u8, channel: u8, encrypt: bool) bool;
extern fn modulus_espnow_transport_stop() void;
extern fn modulus_espnow_transport_send(data: [*]const u8, len: usize) bool;
extern fn modulus_ble_transport_start(name: [*:0]const u8) bool;
extern fn modulus_ble_transport_stop() void;
extern fn modulus_ble_transport_send(data: [*]const u8, len: usize) bool;

extern fn modulus_zig_serial_rx(data: [*]const u8, len: usize) void;
extern fn modulus_serial_open(port: u8, baud: u32, data_bits: u8, parity: u8, stop_bits: u8) bool;
extern fn modulus_serial_close() void;
extern fn modulus_serial_is_open() bool;
extern fn modulus_serial_write(data: [*]const u8, len: usize) c_int;
extern fn modulus_serial_read(buf: [*]u8, max_len: usize) c_int;
extern fn modulus_serial_set_rx_handler(handler: modulus_serial_rx_fn) void;

extern fn modulus_display_init(stripe_lines: u32, flipped: bool, brightness_pct: u8) bool;
extern fn modulus_display_set_brightness(percent: u8) void;
extern fn modulus_display_backlight_off() void;
extern fn modulus_display_backlight_on() void;
extern fn modulus_display_lock() void;
extern fn modulus_display_unlock() void;
extern fn modulus_display_set_flip(flipped: bool) void;
extern fn modulus_display_set_timeouts(dim_sec: u16, sleep_sec: u16) void;
extern fn modulus_display_start_activity_monitor() void;

extern fn modulus_battery_init() void;
extern fn modulus_battery_get_status(out: *modulus_battery_status_t) bool;

extern fn modulus_wireless_init() bool;
extern fn modulus_wireless_ready() bool;
extern fn modulus_wireless_restore_settings() void;
extern fn modulus_wireless_post_restore_settle() void;
extern fn modulus_wireless_prepare_for_sleep() void;
extern fn modulus_wireless_deinit() void;
extern fn modulus_wireless_wake_coprocessor() bool;
extern fn modulus_wireless_wifi_enable() bool;
extern fn modulus_wireless_wifi_disable() void;
extern fn modulus_wireless_wifi_is_connected() bool;
extern fn modulus_wireless_espnow_enable() bool;
extern fn modulus_wireless_espnow_disable() void;

extern fn modulus_touch_init() void;
extern fn modulus_cnc_trace_tx(data: [*]const u8, len: usize) void;
extern fn modulus_dsp_init() void;
extern fn modulus_dsp_process() void;
extern fn modulus_dsp_is_ready() bool;

extern fn modulus_ext_encoder_hw_init() void;
extern fn modulus_ext_encoder_hw_deinit() void;
extern fn modulus_ext_encoder_hw_maintain(connected: *bool, count: *i32, fw_version: *u8) bool;
extern fn modulus_ext_encoder_trace_wheel(count: i32, delta: i32, mpg_active: bool, axis: i8, machine_state: u8, jog_steps: i32, jog_mm: f32, block_code: u8) void;
extern fn modulus_ext_encoder_trace_status(connected: bool, fw_version: u8) void;
extern fn modulus_ext_encoder_notify_ext5v(enabled: bool) void;

extern fn modulus_ui_init() void;
extern fn modulus_ui_show_boot_screen() void;
extern fn modulus_ui_arm_boot_transition() void;
extern fn modulus_ui_show_dashboard() void;
extern fn modulus_ui_show_pin_lock() void;
extern fn modulus_ui_hide_pin_lock() void;
extern fn modulus_ui_pin_lock_visible() bool;
extern fn modulus_ui_on_deep_sleep() void;
extern fn modulus_ui_on_wake() void;
extern fn modulus_ui_on_cnc_status_event() void;
extern fn modulus_ui_show_settings() void;
extern fn modulus_ui_hide_settings() void;
extern fn modulus_ui_settings_open() bool;
extern fn modulus_ui_show_quick_settings() void;
extern fn modulus_ui_show_power_menu() void;

extern fn modulus_storage_init() void;
extern fn modulus_storage_mount() bool;
extern fn modulus_storage_unmount() void;
extern fn modulus_storage_is_mounted() bool;
extern fn modulus_storage_get_sd_info(out: *modulus_sd_info_t) void;
extern fn modulus_storage_get_mem_info(out: *modulus_mem_info_t) void;
extern fn modulus_storage_export_diagnostics(path: [*:0]const u8) bool;
extern fn modulus_storage_clear_ui_cache() void;
extern fn modulus_storage_is_usb_host_enabled() bool;
extern fn modulus_storage_usb_volume_mounted() bool;

extern fn modulus_security_init() void;
extern fn modulus_security_has_pin() bool;
extern fn modulus_security_is_locked() bool;
extern fn modulus_security_lock() void;
extern fn modulus_security_unlock() void;
extern fn modulus_security_verify_pin(pin: [*:0]const u8) bool;

extern fn modulus_audio_init() void;
extern fn modulus_audio_set_volume(percent: u8) void;
extern fn modulus_audio_get_volume() u8;
extern fn modulus_audio_set_mic_gain_idx(idx: u8) void;
extern fn modulus_audio_get_mic_gain() f32;
extern fn modulus_audio_set_tone_profile(profile: u8) void;
extern fn modulus_audio_play_boot() void;

extern fn modulus_rtc_init() void;
extern fn modulus_rtc_is_ready() bool;
extern fn modulus_rtc_apply_timezone() void;
extern fn modulus_rtc_tz_changed(tz_idx: u8) void;
extern fn modulus_rtc_format_time(buf: [*]u8, len: usize) void;
extern fn modulus_rtc_format_date(buf: [*]u8, len: usize) void;
extern fn modulus_rtc_get_local_time(out: *anyopaque) void;
extern fn modulus_rtc_set_local_time(year: c_int, month: c_int, day: c_int, hour: c_int, min: c_int, sec: c_int) bool;
extern fn modulus_rtc_write_hw_from_system() bool;
extern fn modulus_rtc_ntp_status_text() [*:0]const u8;
extern fn modulus_rtc_ntp_sync_now() bool;
extern fn modulus_rtc_ntp_on_wifi_connected() void;
extern fn modulus_rtc_ntp_poll() void;
extern fn modulus_rtc_format_uptime(buf: [*]u8, len: usize) void;

extern fn modulus_imu_init() void;
extern fn modulus_power_init() void;
extern fn modulus_i2c_coex_init() void;
extern fn modulus_i2c_coex_lock(timeout_ms: u32) bool;
extern fn modulus_i2c_coex_unlock() void;
extern fn modulus_i18n_init() void;

test "shim: bundle header manifest matches translate umbrella" {
    const manifest = @import("shim_bundle_manifest.zig");
    try @import("std").testing.expectEqual(@as(usize, 20), manifest.headers.len);
}
