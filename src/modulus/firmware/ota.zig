//! P4 OTA — not implemented. C6 ESP-Hosted slave has OTA RPC; host app has no
//! ota_0/ota_1 slots yet (factory-only `partitions.csv`). Matches C++ gap.

const std = @import("std");
const build_options = @import("build_options");
const host_io = @import("../core/host_io.zig");
const ota_manifest = @import("ota_manifest.zig");

pub const Status = enum(u8) {
    not_implemented = 0,
};

pub const StagingManifest = ota_manifest.StagingManifest;

pub fn available() bool {
    return false;
}

pub fn status() Status {
    return .not_implemented;
}

pub fn statusText() [:0]const u8 {
    return "Not implemented";
}

pub fn defaultManifest() StagingManifest {
    return .{};
}

/// Host OTA pipeline placeholder — writes JSON manifest until `ota_0`/`ota_1` exist.
pub fn writeStagingManifest(io: std.Io, allocator: std.mem.Allocator, path: []const u8) host_io.Error!void {
    if (comptime build_options.device_nvs) return error.IoUnavailable;
    return ota_manifest.writeJson(io, allocator, path, defaultManifest());
}

pub fn parseStagingManifest(allocator: std.mem.Allocator, text: []const u8) !StagingManifest {
    if (comptime build_options.device_nvs) return error.IoUnavailable;
    return ota_manifest.parseJson(allocator, text);
}

test "firmware: ota stub honest" {
    try std.testing.expect(!available());
    try std.testing.expectEqual(Status.not_implemented, status());
    try std.testing.expectEqualStrings("Not implemented", statusText());
}

test "firmware: ota host staging manifest json" {
    if (comptime build_options.device_nvs) return error.SkipZigTest;
    const io = std.testing.io;
    const a = std.testing.allocator;
    const path = ".zig-cache/modulus_ota_staging.json";
    try writeStagingManifest(io, a, path);
    defer std.Io.Dir.cwd().deleteFile(io, path) catch {};
    const data = try host_io.readTextFileAlloc(io, a, path);
    defer a.free(data);
    try std.testing.expect(std.mem.indexOf(u8, data, "\"status\":\"not_implemented\"") != null);
    const parsed = try parseStagingManifest(a, data);
    try std.testing.expectEqualStrings("not_implemented", parsed.status);
}
