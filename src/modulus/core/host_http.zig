//! Host HTTP / WebSocket probe tooling — uses `std.Io` + `std.http.Client`.
//!
//! Mirrors Tab5 `tcp_transport_shim.c` handshake for field diagnostics from a PC.
//! Device code must not import this module.

const std = @import("std");
const build_options = @import("build_options");
const host_io = @import("host_io.zig");

pub const Error = error{
    IoUnavailable,
    HostOnly,
    TlsProbeUnsupported,
    InvalidHost,
    ConnectFailed,
    HandshakeFailed,
    ResponseTooLarge,
    ParseFailed,
    UnresolvedScope,
} || host_io.Error || std.http.Client.FetchError || std.Io.net.IpAddress.ConnectError || std.Io.Reader.ShortError;

pub const HttpGetResult = struct {
    status: std.http.Status,
    body: []u8,
};

pub const WsProbeResult = struct {
    ok: bool,
    host: []const u8,
    port: u16,
    path: []const u8,
    tls: bool,
    response_snippet: []const u8,
};

/// GET `url` — body owned by `allocator`. Caller frees.
pub fn httpGetAlloc(io: std.Io, allocator: std.mem.Allocator, url: []const u8) Error!HttpGetResult {
    if (comptime build_options.device_nvs) return error.HostOnly;
    _ = try host_io.require(io);

    var list = std.ArrayList(u8).empty;
    errdefer list.deinit(allocator);
    try list.ensureTotalCapacity(allocator, max_body_bytes);

    var body_writer = std.Io.Writer.Allocating.fromArrayList(allocator, &list);
    defer list = body_writer.toArrayList();

    var client = std.http.Client{ .allocator = allocator, .io = io };
    defer client.deinit();

    const result = client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &body_writer.writer,
    }) catch |err| {
        if (list.items.len > max_body_bytes) return error.ResponseTooLarge;
        return err;
    };

    if (list.items.len > max_body_bytes) {
        return error.ResponseTooLarge;
    }

    const body = try list.toOwnedSlice(allocator);

    return .{
        .status = result.status,
        .body = body,
    };
}

/// Max HTTP GET body for host tooling (field diagnostic fetch).
pub const max_body_bytes: usize = 1 * 1024 * 1024;

/// Build RFC6455 upgrade request (same key as Tab5 `tcp_transport_shim.c`).
pub fn formatWsUpgradeRequest(path: []const u8, host: []const u8, port: u16, buf: []u8) ![]const u8 {
    return std.fmt.bufPrint(buf,
        \\GET {s} HTTP/1.1
        \\Host: {s}:{d}
        \\Upgrade: websocket
        \\Connection: Upgrade
        \\Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
        \\Sec-WebSocket-Version: 13
        \\
        \\
    , .{ path, host, port });
}

/// TCP WebSocket handshake probe (plain TCP — matches device `ws_tls=0`).
pub fn probeWebSocket(
    io: std.Io,
    allocator: std.mem.Allocator,
    host: []const u8,
    port: u16,
    path: []const u8,
    tls: bool,
) Error!WsProbeResult {
    if (comptime build_options.device_nvs) return error.HostOnly;
    _ = try host_io.require(io);
    if (tls) return error.TlsProbeUnsupported;
    if (host.len == 0) return error.InvalidHost;

    var req_buf: [384]u8 = undefined;
    const req = try formatWsUpgradeRequest(path, host, port, &req_buf);

    const addr = try std.Io.net.IpAddress.parse(host, port);
    var stream = try std.Io.net.IpAddress.connect(&addr, io, .{ .mode = .stream });
    defer stream.close(io);

    var w_buf: [512]u8 = undefined;
    var writer = stream.writer(io, &w_buf);
    try std.Io.Writer.writeAll(&writer.interface, req);

    var r_buf: [512]u8 = undefined;
    var reader = stream.reader(io, &r_buf);
    var resp_list = std.ArrayList(u8).empty;
    defer resp_list.deinit(allocator);
    var resp_writer = std.Io.Writer.Allocating.fromArrayList(allocator, &resp_list);
    defer resp_list = resp_writer.toArrayList();

    const max: usize = 511;
    while (resp_list.items.len < max) {
        const read_result = std.Io.Reader.readSliceShort(&reader.interface, &r_buf);
        if (read_result) |n| {
            if (n == 0) break;
            try std.Io.Writer.writeAll(&resp_writer.writer, r_buf[0..n]);
            if (std.mem.indexOf(u8, resp_list.items, "\r\n\r\n") != null) break;
        } else |err| {
            if (err != error.EndOfStream) return err;
            break;
        }
    }

    const snippet = try allocator.dupe(u8, resp_list.items);
    errdefer allocator.free(snippet);

    const ok = std.mem.indexOf(u8, snippet, "101") != null;
    return .{
        .ok = ok,
        .host = host,
        .port = port,
        .path = path,
        .tls = tls,
        .response_snippet = snippet,
    };
}

pub fn formatWsProbeReport(allocator: std.mem.Allocator, probe: WsProbeResult) Error![]u8 {
    return std.fmt.allocPrint(allocator,
        \\Modulus WebSocket probe (host)
        \\host={s}
        \\port={d}
        \\path={s}
        \\tls={any}
        \\handshake_ok={any}
        \\response:
        \\{s}
        \\
    , .{
        probe.host,
        probe.port,
        probe.path,
        probe.tls,
        probe.ok,
        probe.response_snippet,
    });
}

test "host_http: ws upgrade request matches device shim" {
    if (comptime build_options.device_nvs) return error.SkipZigTest;
    var buf: [384]u8 = undefined;
    const req = try formatWsUpgradeRequest("/", "192.168.1.100", 81, &buf);
    try std.testing.expect(std.mem.indexOf(u8, req, "GET / HTTP/1.1") != null);
    try std.testing.expect(std.mem.indexOf(u8, req, "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==") != null);
}

test "host_http: http get invalid url" {
    if (comptime build_options.device_nvs) return error.SkipZigTest;
    const io = std.testing.io;
    const err = httpGetAlloc(io, std.testing.allocator, "://bad") catch |e| e;
    try std.testing.expect(err == error.UnexpectedCharacter or err == error.UriInvalidFormat);
}
