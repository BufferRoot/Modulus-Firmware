//! HAL transport layer — dispatcher, serial, stream mocks, ESP-NOW config.

const std = @import("std");

pub const dispatcher = @import("dispatcher.zig");
pub const espnow_config = @import("espnow_config.zig");
pub const link = @import("link.zig");
pub const mock_channel = @import("mock_channel.zig");
pub const serial = @import("serial.zig");
pub const stream = @import("stream.zig");

test {
    std.testing.refAllDecls(@This());
}
