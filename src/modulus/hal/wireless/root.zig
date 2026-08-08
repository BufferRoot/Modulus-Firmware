//! HAL wireless — SDIO pins, mock ESP-Hosted, radio API.

const std = @import("std");

pub const mock_hosted = @import("mock_hosted.zig");
pub const sdio_pins = @import("sdio_pins.zig");
pub const wireless = @import("wireless.zig");

test {
    std.testing.refAllDecls(@This());
}
