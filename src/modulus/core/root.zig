//! Core layer — events, event bus, settings store, boot orchestration.

const std = @import("std");

pub const system_events = @import("system_events.zig");
pub const event_bus = @import("event_bus.zig");
pub const settings_keys = @import("settings_keys.zig");
pub const settings_store = @import("settings_store.zig");
pub const str_util = @import("str_util.zig");
pub const boot = @import("boot.zig");
pub const modulus = @import("modulus.zig");
pub const host_io = @import("host_io.zig");
pub const host_diagnostics = @import("host_diagnostics.zig");
pub const host_http = @import("host_http.zig");
pub const host_log = @import("host_log.zig");
pub const device_log = @import("device_log.zig");

test {
    std.testing.refAllDecls(@This());
}
