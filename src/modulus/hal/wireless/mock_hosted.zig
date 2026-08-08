//! Mock ESP-Hosted / C6 coprocessor state — host tests without SDIO.

const std = @import("std");

pub const MockHosted = struct {
    initialized: bool = false,
    prepared_for_sleep: bool = false,
    c6_power_on: bool = false,
    reset_pulses: u32 = 0,
    tx_frames: u32 = 0,

    pub fn init(self: *MockHosted) bool {
        self.initialized = true;
        self.c6_power_on = true;
        self.prepared_for_sleep = false;
        return true;
    }

    pub fn prepareForSleep(self: *MockHosted) void {
        self.prepared_for_sleep = true;
    }

    pub fn deinit(self: *MockHosted) void {
        self.initialized = false;
        self.prepared_for_sleep = false;
    }

    pub fn wakeCoprocessor(self: *MockHosted) bool {
        self.reset_pulses += 1;
        self.c6_power_on = true;
        return self.init();
    }

    pub fn setC6Power(self: *MockHosted, on: bool) void {
        self.c6_power_on = on;
        if (!on) self.initialized = false;
    }
};

test "hal: mock hosted sleep cycle" {
    var m: MockHosted = .{};
    try std.testing.expect(m.init());
    m.prepareForSleep();
    try std.testing.expect(m.prepared_for_sleep);
    m.deinit();
    try std.testing.expect(!m.initialized);
    try std.testing.expect(m.wakeCoprocessor());
    try std.testing.expectEqual(@as(u32, 1), m.reset_pulses);
}
