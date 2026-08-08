//! HAL layer — transports (Phase 3), platform + wireless (Phase 4).

const std = @import("std");

pub const platform = @import("platform/root.zig");
pub const transport = @import("transport/root.zig");
pub const wireless = @import("wireless/root.zig");

test {
    std.testing.refAllDecls(@This());
}
