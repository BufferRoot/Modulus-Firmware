//! RX8130 BCD helpers and RTC types — host-testable; device I/O in `idf_rtc.zig`.

const std = @import("std");
const build_options = @import("build_options");
const idf_rtc_mod = if (build_options.device_nvs)
    @import("idf_rtc.zig")
else
    struct {
        pub fn hwInit() void {}
        pub fn isReady() bool {
            return false;
        }
    };

pub const Rtc = struct {
    initialized: bool = false,

    pub fn init(self: *Rtc) void {
        if (build_options.device_nvs) {
            idf_rtc_mod.hwInit();
        }
        self.initialized = true;
    }

    pub fn isReady(self: *const Rtc) bool {
        if (!self.initialized) return false;
        return idf_rtc_mod.isReady();
    }
};

pub fn bcdToDec(val: u8) u8 {
    return @truncate((val >> 4) * 10 + (val & 0x0f));
}

pub fn decToBcd(val: u8) u8 {
    return @truncate(((val / 10) << 4) + (val % 10));
}

pub fn isPlausible(year: i32, month: i32, day: i32, hour: i32, min: i32, sec: i32) bool {
    return year >= 2020 and year <= 2099 and month >= 1 and month <= 12 and day >= 1 and day <= 31 and
        hour >= 0 and hour <= 23 and min >= 0 and min <= 59 and sec >= 0 and sec <= 59;
}

test "rtc: bcd round trip" {
    try std.testing.expectEqual(@as(u8, 59), bcdToDec(decToBcd(59)));
    try std.testing.expectEqual(@as(u8, 23), bcdToDec(0x23));
    try std.testing.expectEqual(@as(u8, 0x45), decToBcd(45));
}

test "rtc: plausible range" {
    try std.testing.expect(isPlausible(2026, 6, 6, 12, 0, 0));
    try std.testing.expect(!isPlausible(2019, 1, 1, 0, 0, 0));
}
