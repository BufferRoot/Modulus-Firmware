//! Headers included in `modulus_shims_bundle.h` — drift guard for translate-C.

pub const headers = [_][]const u8{
    "audio_shim.h",
    "battery_shim.h",
    "cnc_trace_shim.h",
    "display_shim.h",
    "dsp_shim.h",
    "event_shim.h",
    "ext_encoder_shim.h",
    "i18n_shim.h",
    "i2c_coex_shim.h",
    "i2c_scan_shim.h",
    "imu_shim.h",
    "nvs_shim.h",
    "power_shim.h",
    "rtc_shim_translate.h",
    "security_shim.h",
    "serial_shim.h",
    "storage_shim.h",
    "touch_shim.h",
    "transport_shim.h",
    "ui_shim.h",
    "wireless_shim.h",
};

test "shim: bundle header count" {
    try @import("std").testing.expectEqual(@as(usize, 21), headers.len);
}
