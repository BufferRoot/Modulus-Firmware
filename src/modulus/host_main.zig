//! Host entry — full Modulus boot via wired `Runtime`.
//!
//! ```text
//! modulus-host                              # smoke boot + one tick
//! modulus-host --export-diagnostics PATH    # boot + write host diag report
//! modulus-host --export-ota-staging PATH    # write OTA staging manifest (no boot)
//! modulus-host --http-get URL [--out PATH]  # HTTP GET (body to stdout or file)
//! modulus-host --probe-ws HOST PORT PATH [--out PATH]
//! ```

const std = @import("std");
const host_http = @import("core/host_http.zig");
const host_io = @import("core/host_io.zig");
const host_log = @import("core/host_log.zig");
const runtime = @import("runtime/root.zig");

const log = host_log.host;

pub const std_options: std.Options = .{
    .log_level = .info,
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);

    if (args.len >= 2) {
        if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
            try std.Io.File.stdout().writeStreamingAll(io, help_text);
            return;
        }
        if (args.len >= 3 and std.mem.eql(u8, args[1], "--http-get")) {
            try runHttpGet(io, arena, args[2], outPath(args));
            return;
        }
        if (args.len >= 5 and std.mem.eql(u8, args[1], "--probe-ws")) {
            const port: u16 = try std.fmt.parseInt(u16, args[3], 10);
            try runWsProbe(io, arena, args[2], port, args[4], outPath(args));
            return;
        }
    }

    var rt = runtime.Runtime.init(gpa, io);
    defer rt.deinit();

    if (args.len >= 2) {
        if (args.len >= 3 and std.mem.eql(u8, args[1], "--export-diagnostics")) {
            try rt.boot();
            rt.exportHostDiagnostics(args[2]) catch |err| {
                log.err("export diagnostics failed: {s}", .{@errorName(err)});
                rt.exportHostDiagnosticsFault(args[2], err) catch |fault_err| {
                    log.err("fault export failed: {s}", .{@errorName(fault_err)});
                };
                return err;
            };
            log.info("wrote diagnostics to {s}", .{args[2]});
            return;
        }
        if (args.len >= 3 and std.mem.eql(u8, args[1], "--export-ota-staging")) {
            try rt.exportOtaStagingManifest(args[2]);
            log.info("wrote OTA staging manifest to {s}", .{args[2]});
            return;
        }
    }

    try rt.boot();
    rt.systemTick(10);
    log.info("smoke boot ok", .{});
}

fn outPath(args: []const []const u8) ?[]const u8 {
    var idx: usize = 2;
    while (idx + 1 < args.len) : (idx += 1) {
        if (std.mem.eql(u8, args[idx], "--out")) return args[idx + 1];
    }
    return null;
}

fn runHttpGet(io: std.Io, arena: std.mem.Allocator, url: []const u8, out: ?[]const u8) !void {
    const result = try host_http.httpGetAlloc(io, arena, url);
    defer arena.free(result.body);

    const payload = try std.fmt.allocPrint(arena, "HTTP {d}\n{s}", .{
        @intFromEnum(result.status),
        result.body,
    });

    if (out) |path| {
        try host_io.writeTextFile(io, path, payload);
        log.info("http-get wrote {d} bytes to {s}", .{ payload.len, path });
    } else {
        try std.Io.File.stdout().writeStreamingAll(io, payload);
    }
}

fn runWsProbe(
    io: std.Io,
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    path: []const u8,
    out: ?[]const u8,
) !void {
    const probe = try host_http.probeWebSocket(io, allocator, host, port, path, false);
    defer allocator.free(probe.response_snippet);

    const report = try host_http.formatWsProbeReport(allocator, probe);
    defer allocator.free(report);

    if (out) |file_path| {
        try host_io.writeTextFile(io, file_path, report);
        log.info("ws probe report -> {s} ok={any}", .{ file_path, probe.ok });
    } else {
        try std.Io.File.stdout().writeStreamingAll(io, report);
    }
}

const help_text =
    \\modulus-host — Modulus Zig host smoke / tooling
    \\
    \\  modulus-host
    \\  modulus-host --export-diagnostics <path>
    \\  modulus-host --export-ota-staging <path>
    \\  modulus-host --http-get <url> [--out <path>]
    \\  modulus-host --probe-ws <host> <port> <path> [--out <path>]
    \\
;
