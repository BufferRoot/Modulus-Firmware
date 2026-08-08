//! Tab5 freestanding root — std_options for riscv32-freestanding, re-exports `root.zig`.

const std = @import("std");
const build_options = @import("build_options");

pub const std_options: std.Options = .{
    .page_size_min = 4096,
    .page_size_max = 65536,
    .queryPageSize = struct {
        fn pageSize() usize {
            return 4096;
        }
    }.pageSize,
    .networking = false,
    .allow_stack_tracing = false,
    .unexpected_error_tracing = false,
};

/// Freestanding debug_io must not open host paths (Zig 0.16 std).
pub const std_options_debug_io: std.Io = std.Io.failing;

pub const testing = @import("root.zig").testing;
pub const core = @import("root.zig").core;
pub const cnc = @import("root.zig").cnc;
pub const hal = @import("root.zig").hal;
pub const runtime = @import("root.zig").runtime;
pub const ui = @import("root.zig").ui;

comptime {
    if (build_options.device_nvs) {
        _ = @import("firmware/abi.zig");
        _ = @import("firmware/abi_bool.zig");
    }
}
