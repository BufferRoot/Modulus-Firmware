//! Modulus runtime — wired boot + system task poll.

const std = @import("std");

pub const hooks = @import("hooks.zig");
pub const runtime = @import("runtime.zig");
pub const Runtime = runtime.Runtime;

test {
    std.testing.refAllDecls(@This());
}
