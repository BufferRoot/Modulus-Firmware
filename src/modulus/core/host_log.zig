//! Host-only scoped logging — never import from Core 1 / device hot paths.

const std = @import("std");
const build_options = @import("build_options");

pub const host = if (build_options.device_nvs)
    struct {
        pub fn info(comptime fmt: []const u8, args: anytype) void {
            _ = fmt;
            _ = args;
        }
        pub fn warn(comptime fmt: []const u8, args: anytype) void {
            _ = fmt;
            _ = args;
        }
        pub fn err(comptime fmt: []const u8, args: anytype) void {
            _ = fmt;
            _ = args;
        }
    }
else
    std.log.scoped(.modulus_host);

test "host_log: scoped tag on host" {
    if (comptime build_options.device_nvs) return error.SkipZigTest;
    host.info("probe {s}", .{@tagName(.modulus_host)});
}
