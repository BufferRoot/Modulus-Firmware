//! Host diagnostic text export — mirrors device `/sdcard/modulus_diag.txt` shape for tooling.

const std = @import("std");
const build_options = @import("build_options");
const host_io = @import("host_io.zig");
const modulus = @import("modulus.zig");
const ota_mod = @import("../firmware/ota.zig");
const cnc_config = @import("../cnc/cnc_config.zig");

pub const Snapshot = struct {
    transport_ready: bool = false,
    transport_conn: u8 = 0,
    wireless_ready: bool = false,
    system_task_armed: bool = false,
    sd_mounted: bool = false,
};

pub fn transportLabel(conn: u8) []const u8 {
    const e: cnc_config.Connection = @enumFromInt(conn);
    return @tagName(e);
}

pub fn format(snap: Snapshot, buf: []u8) ![]const u8 {
    return std.fmt.bufPrint(buf,
        \\Modulus host diagnostics
        \\target=host
        \\zig={s}
        \\modulus={s}
        \\transport_ready={any}
        \\transport_conn={s}({d})
        \\wireless_ready={any}
        \\system_task_armed={any}
        \\sd_mounted={any}
        \\ota_available={any}
        \\ota_status={s}
        \\error_trace_present={any}
        \\
    , .{
        @import("builtin").zig_version_string,
        modulus.version,
        snap.transport_ready,
        if (snap.transport_ready) transportLabel(snap.transport_conn) else "none",
        snap.transport_conn,
        snap.wireless_ready,
        snap.system_task_armed,
        snap.sd_mounted,
        ota_mod.available(),
        ota_mod.statusText(),
        @errorReturnTrace() != null,
    });
}

pub fn writeFile(io: std.Io, path: []const u8, snap: Snapshot) host_io.Error!void {
    if (comptime build_options.device_nvs) return error.IoUnavailable;
    return writeFileCold(io, path, snap);
}

fn writeFileCold(io: std.Io, path: []const u8, snap: Snapshot) host_io.Error!void {
    @branchHint(.cold);
    var buf: [2048]u8 = undefined;
    const base = try format(snap, &buf);
    var end = base.len;
    if (@errorReturnTrace() != null and end < buf.len) {
        const trace = host_io.formatErrorReturnTrace(buf[end..]) catch buf[end..0];
        end += trace.len;
    }
    try host_io.writeTextFile(io, path, buf[0..end]);
}

/// Cold-path export when diagnostics fail — captures `err` + optional trace.
pub fn writeFaultFile(
    io: std.Io,
    path: []const u8,
    snap: Snapshot,
    err: anyerror,
) host_io.Error!void {
    if (comptime build_options.device_nvs) return error.IoUnavailable;
    return writeFaultFileCold(io, path, snap, err);
}

fn writeFaultFileCold(
    io: std.Io,
    path: []const u8,
    snap: Snapshot,
    err: anyerror,
) host_io.Error!void {
    @branchHint(.cold);
    var buf: [2048]u8 = undefined;
    const base = try format(snap, &buf);
    var end = base.len;
    if (end < buf.len) {
        const line = std.fmt.bufPrint(buf[end..], "last_error={s}\n", .{@errorName(err)}) catch buf[end..0];
        end += line.len;
    }
    if (@errorReturnTrace() != null and end < buf.len) {
        const trace = host_io.formatErrorReturnTrace(buf[end..]) catch buf[end..0];
        end += trace.len;
    }
    try host_io.writeTextFile(io, path, buf[0..end]);
}

test "host_diagnostics: format includes transport" {
    var buf: [1024]u8 = undefined;
    const text = try format(.{
        .transport_ready = true,
        .transport_conn = @intFromEnum(cnc_config.Connection.rs485),
        .system_task_armed = true,
    }, &buf);
    try std.testing.expect(std.mem.indexOf(u8, text, "transport_conn=rs485") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "ota_status=Not implemented") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "error_trace_present=") != null);
}

test "host_diagnostics: write file via io" {
    if (comptime build_options.device_nvs) return error.SkipZigTest;
    const io = std.testing.io;
    const path = ".zig-cache/modulus_host_diag.txt";
    try writeFile(io, path, .{ .system_task_armed = true });
    defer std.Io.Dir.cwd().deleteFile(io, path) catch {};
    const data = try host_io.readTextFileLimited(io, std.testing.allocator, path, 4096);
    defer std.testing.allocator.free(data);
    try std.testing.expect(std.mem.indexOf(u8, data, "Modulus host diagnostics") != null);
}
