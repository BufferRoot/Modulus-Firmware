//! Host OTA staging manifest — JSON parse/emit (device stays text-only stub).

const std = @import("std");
const build_options = @import("build_options");
const modulus = @import("../core/modulus.zig");

pub const StagingManifest = struct {
    status: []const u8 = "not_implemented",
    version: []const u8 = modulus.version,
    available: bool = false,
    note: []const u8 = "factory-only partition table on Tab5 P4 today",
};

pub fn writeJson(io: std.Io, allocator: std.mem.Allocator, path: []const u8, manifest: StagingManifest) !void {
    if (comptime build_options.device_nvs) return error.HostOnly;
    const json = try std.json.Stringify.valueAlloc(allocator, manifest, .{});
    defer allocator.free(json);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = json });
}

pub fn parseJson(allocator: std.mem.Allocator, text: []const u8) !StagingManifest {
    if (comptime build_options.device_nvs) return error.HostOnly;
    const parsed = try std.json.parseFromSlice(StagingManifest, allocator, text, .{});
    defer parsed.deinit();
    return parsed.value;
}

test "firmware: ota manifest json round-trip" {
    if (comptime build_options.device_nvs) return error.SkipZigTest;
    const a = std.testing.allocator;
    const io = std.testing.io;
    const path = ".zig-cache/modulus_ota_staging.json";
    const sample: StagingManifest = .{};
    try writeJson(io, a, path, sample);
    defer std.Io.Dir.cwd().deleteFile(io, path) catch {};
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, a, .unlimited);
    defer a.free(raw);
    const decoded = try parseJson(a, raw);
    try std.testing.expectEqualStrings("not_implemented", decoded.status);
    try std.testing.expectEqualStrings(modulus.version, decoded.version);
    try std.testing.expect(!decoded.available);
}
