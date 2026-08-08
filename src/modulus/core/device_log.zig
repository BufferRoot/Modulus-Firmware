//! Logging scopes — import here, not `std.log.scoped` directly. Never log in Core 1 hot loops.

const std = @import("std");

/// Cold-path NVS persist failures (`settings_store.zig`).
pub const settings = std.log.scoped(.settings);

/// UI manager boot/cold paths (`ui/manager.zig`).
pub const ui = std.log.scoped(.ui);
