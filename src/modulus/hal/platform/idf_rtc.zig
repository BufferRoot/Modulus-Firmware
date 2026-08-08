//! RX8130 RTC — `rtc_shim.c` via translate-C (`rtc_shim_translate.h`).

const c = @import("modulus_shims");

pub fn hwInit() void {
    c.modulus_rtc_init();
}

pub fn isReady() bool {
    return c.modulus_rtc_is_ready();
}

pub fn applyTimezone() void {
    c.modulus_rtc_apply_timezone();
}

pub fn tzChanged(tz_idx: u8) void {
    c.modulus_rtc_tz_changed(tz_idx);
}

pub fn formatTime(buf: [*]u8, len: usize) void {
    c.modulus_rtc_format_time(buf, len);
}

pub fn formatDate(buf: [*]u8, len: usize) void {
    c.modulus_rtc_format_date(buf, len);
}

pub fn getLocalTime(out: *anyopaque) void {
    c.modulus_rtc_get_local_time(out);
}

pub fn setLocalTime(year: c_int, month: c_int, day: c_int, hour: c_int, min: c_int, sec: c_int) bool {
    return c.modulus_rtc_set_local_time(year, month, day, hour, min, sec);
}

pub fn writeHwFromSystem() bool {
    return c.modulus_rtc_write_hw_from_system();
}

pub fn ntpStatusText() [*:0]const u8 {
    return c.modulus_rtc_ntp_status_text();
}

pub fn ntpSyncNow() bool {
    return c.modulus_rtc_ntp_sync_now();
}

pub fn ntpOnWifiConnected() void {
    c.modulus_rtc_ntp_on_wifi_connected();
}

pub fn ntpPoll() void {
    c.modulus_rtc_ntp_poll();
}

pub fn formatUptime(buf: [*]u8, len: usize) void {
    c.modulus_rtc_format_uptime(buf, len);
}
