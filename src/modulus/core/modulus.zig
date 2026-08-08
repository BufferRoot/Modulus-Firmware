//! Modulus OS core — version constants and boot entry.

pub const version = "2.0";
pub const os_name = "MODULUS";
pub const creator = "POWERED BY M5STACK";

pub const boot = @import("boot.zig");
pub const SystemTaskPolicy = boot.SystemTaskPolicy;

/// Host/device boot entry — pass initialized `store`, `bus`, and optional HAL hooks.
pub fn start(ctx: *boot.BootContext) !void {
    try boot.run(ctx);
}
