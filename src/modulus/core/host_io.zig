//! Host-only file and entropy helpers — require `std.Io` from Juicy Main or `std.testing.io`.
//!
//! Device freestanding code must not call these; pass `null` io on Tab5 `Runtime`.

const std = @import("std");
const Io = std.Io;

pub const Error = error{
    IoUnavailable,
    TraceWriteFailed,
} || Io.Cancelable || Io.Dir.WriteFileError || Io.Dir.ReadFileAllocError || std.process.ExecutablePathAllocError;

/// Returns `io` or `error.IoUnavailable` when running on device / without Juicy Main.
pub fn require(io: ?Io) Error!Io {
    return io orelse error.IoUnavailable;
}

/// Overwrite `path` (cwd-relative) with `data`.
pub fn writeTextFile(io: Io, path: []const u8, data: []const u8) Error!void {
    try Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = data,
    });
}

/// Read entire file into `gpa`-owned slice. Caller frees.
pub fn readTextFileAlloc(io: Io, gpa: std.mem.Allocator, path: []const u8) Error![]u8 {
    return Io.Dir.cwd().readFileAlloc(io, path, gpa, .unlimited);
}

/// Size-capped file read — returns `error.StreamTooLong` when `max_bytes` exceeded.
pub fn readTextFileLimited(io: Io, gpa: std.mem.Allocator, path: []const u8, max_bytes: usize) Error![]u8 {
    return Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(max_bytes));
}

/// Join `rel` to the host executable directory (not cwd). Caller frees.
pub fn resolveBesideExecutable(io: Io, gpa: std.mem.Allocator, rel: []const u8) Error![]u8 {
    const exe_dir = try std.process.executableDirPathAlloc(io, gpa);
    defer gpa.free(exe_dir);
    return std.fs.path.join(gpa, &.{ exe_dir, rel });
}

/// Fill `buf` with an error-return trace when present; returns written slice or empty.
pub fn formatErrorReturnTrace(buf: []u8) Error![]const u8 {
    const et = @errorReturnTrace() orelse return buf[0..0];
    var w = Io.Writer.fixed(buf);
    const term = Io.Terminal{ .writer = &w, .mode = .no_color };
    std.debug.writeErrorReturnTrace(et, term) catch return error.TraceWriteFailed;
    return Io.Writer.buffered(&w);
}

/// Fill `buf` with OS-backed entropy (`Io.random`).
pub fn randomBytes(io: Io, buf: []u8) void {
    io.random(buf);
}

test "host_io: write/read round-trip" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    const path = ".zig-cache/modulus_host_io_roundtrip.txt";

    try writeTextFile(io, path, "modulus-host-io");
    defer Io.Dir.cwd().deleteFile(io, path) catch {};

    const data = try readTextFileAlloc(io, gpa, path);
    defer gpa.free(data);
    try std.testing.expectEqualStrings("modulus-host-io", data);
}

test "host_io: limited read rejects oversize" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    const path = ".zig-cache/modulus_host_io_limited.txt";

    try writeTextFile(io, path, "1234567890");
    defer Io.Dir.cwd().deleteFile(io, path) catch {};

    const ok = try readTextFileLimited(io, gpa, path, 16);
    defer gpa.free(ok);
    try std.testing.expectEqualStrings("1234567890", ok);

    const err = readTextFileLimited(io, gpa, path, 4) catch |e| e;
    try std.testing.expect(err == error.StreamTooLong);
}

test "host_io: require rejects null io" {
    try std.testing.expectError(error.IoUnavailable, require(null));
}

test "host_io: resolve beside executable" {
    const io = std.testing.io;
    const gpa = std.testing.allocator;
    const joined = try resolveBesideExecutable(io, gpa, "data/manifest.txt");
    defer gpa.free(joined);
    try std.testing.expect(std.mem.endsWith(u8, joined, "data/manifest.txt") or
        std.mem.endsWith(u8, joined, "data\\manifest.txt"));
}
