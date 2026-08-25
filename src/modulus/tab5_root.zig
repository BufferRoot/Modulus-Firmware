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

extern "c" fn esp_rom_printf(fmt: [*:0]const u8, ...) c_int;
extern "c" fn abort() callconv(.c) noreturn;

/// Without this, freestanding `defaultPanic` is a bare `@trap()` (riscv `unimp`),
/// which surfaces as "Illegal instruction" with the message discarded.
var panic_msg_buf: [192]u8 = undefined;

fn zigPanic(msg: []const u8, first_trace_addr: ?usize) noreturn {
    @branchHint(.cold);
    const n = @min(msg.len, panic_msg_buf.len - 1);
    var i: usize = 0;
    while (i < n) : (i += 1) panic_msg_buf[i] = msg[i];
    panic_msg_buf[n] = 0;
    const ra: u32 = @truncate(first_trace_addr orelse @returnAddress());
    _ = esp_rom_printf("\nZIG PANIC: %s (ra=0x%08x)\n", &panic_msg_buf, ra);
    abort();
}

pub const panic = std.debug.FullPanic(zigPanic);

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
        _ = @import("firmware/device_ui_runtime.zig");
    }
}
