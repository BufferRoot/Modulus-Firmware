//! Modulus Zig root module — host tests and future firmware layers.

const std = @import("std");
const build_options = @import("build_options");

pub const testing = @import("testing/leak_guard.zig");
pub const core = @import("core/root.zig");
pub const cnc = @import("cnc/root.zig");
pub const hal = @import("hal/root.zig");
pub const runtime = @import("runtime/root.zig");
pub const ui = @import("ui/root.zig");
pub const ui_engine = @import("ui_engine/root.zig");

comptime {
    if (build_options.device_nvs) {
        _ = @import("firmware/abi.zig");
    }
}

test {
    std.testing.refAllDecls(@This());
    _ = @import("testing/leak_guard.zig");
    _ = @import("core/root.zig");
    _ = @import("cnc/root.zig");
    _ = @import("hal/root.zig");
    _ = @import("hal/platform/root.zig");
    _ = @import("hal/wireless/root.zig");
    _ = @import("runtime/root.zig");
    _ = @import("ui/root.zig");
    _ = @import("ui_engine/root.zig");
    if (!build_options.device_nvs) {
        _ = @import("firmware/host_tests.zig");
        _ = @import("firmware/system_task.zig");
        _ = @import("firmware/event_dispatch_task.zig");
        _ = @import("core/nvs_manifest_test.zig");
    }
}
