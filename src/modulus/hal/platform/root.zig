//! HAL platform — display, power, battery, I2C coex, ExtEncoder.

const std = @import("std");

pub const audio = @import("audio.zig");
pub const battery = @import("battery.zig");
pub const display = @import("display.zig");
pub const dsp = @import("dsp.zig");
pub const ext_encoder = @import("ext_encoder.zig");
pub const i18n = @import("i18n.zig");
pub const imu = @import("imu.zig");
pub const i2c_coex = @import("i2c_coex.zig");
pub const power = @import("power.zig");
pub const rtc = @import("rtc.zig");
pub const security = @import("security.zig");
pub const storage = @import("storage.zig");
pub const touch = @import("touch.zig");

test {
    std.testing.refAllDecls(@This());
}
