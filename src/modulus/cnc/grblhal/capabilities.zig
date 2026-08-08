//! grblHAL controller capabilities and $I+ info parsing.

const std = @import("std");
const str_util = @import("../../core/str_util.zig");
const parse_util = @import("parse_util.zig");

pub const Capabilities = struct {
    atc: bool = false,
    block_delete: bool = false,
    bluetooth: bool = false,
    enums: bool = false,
    estop: bool = false,
    ethernet: bool = false,
    homing: bool = false,
    lathe: bool = false,
    mpg: bool = false,
    no_probe: bool = false,
    odometer: bool = false,
    opt_stop: bool = false,
    probe_connect: bool = false,
    pid: bool = false,
    rt_commands: bool = false,
    sd_card: bool = false,
    ymodem: bool = false,
    spindle_sync: bool = false,
    tool_change: bool = false,
    wifi: bool = false,
    ftp: bool = false,
    webdav: bool = false,
    settings_desc: bool = false,
    probe_count: u8 = 1,
};

pub const ControllerInfo = struct {
    firmware: [16]u8 = [_]u8{0} ** 16,
    version: [16]u8 = [_]u8{0} ** 16,
    options: [32]u8 = [_]u8{0} ** 32,
    block_buffer: u16 = 0,
    rx_buffer: u16 = 0,
    n_axes: u8 = 3,
    n_tools: u8 = 0,
    axis_letters: [10]u8 = blk: {
        var a: [10]u8 = [_]u8{0} ** 10;
        @memcpy(a[0..3], "XYZ");
        break :blk a;
    },
    driver: [32]u8 = [_]u8{0} ** 32,
    driver_ver: [16]u8 = [_]u8{0} ** 16,
    board: [32]u8 = [_]u8{0} ** 32,
    aux_din: u8 = 0,
    aux_dout: u8 = 0,
    aux_ain: u8 = 0,
    aux_aout: u8 = 0,
    caps: Capabilities = .{},
};

pub fn parseOptLine(data: []const u8, info: *ControllerInfo) void {
    var parts = std.mem.splitScalar(u8, data, ',');
    var idx: usize = 0;
    while (parts.next()) |tok| : (idx += 1) {
        switch (idx) {
            0 => str_util.copy(&info.options, tok),
            1 => info.block_buffer = parse_util.parseU16(tok) orelse 0,
            2 => info.rx_buffer = parse_util.parseU16(tok) orelse 0,
            3 => info.n_axes = parse_util.parseU8(tok) orelse info.n_axes,
            4 => info.n_tools = parse_util.parseU8(tok) orelse 0,
            else => {},
        }
    }
}

pub fn parseNewopt(data: []const u8, caps: *Capabilities) void {
    var parts = std.mem.splitScalar(u8, data, ',');
    while (parts.next()) |raw| {
        if (std.mem.indexOfScalar(u8, raw, '=')) |eq| {
            const key = raw[0..eq];
            const val = raw[eq + 1 ..];
            if (std.mem.eql(u8, key, "ATC")) caps.atc = (parse_util.parseU8(val) orelse 0) != 0;
            if (std.mem.eql(u8, key, "PROBES")) caps.probe_count = parse_util.parseU8(val) orelse caps.probe_count;
            continue;
        }
        if (std.mem.eql(u8, raw, "ATC")) caps.atc = true else if (std.mem.eql(u8, raw, "BD")) caps.block_delete = true else if (std.mem.eql(u8, raw, "BT")) caps.bluetooth = true else if (std.mem.eql(u8, raw, "ENUMS")) caps.enums = true else if (std.mem.eql(u8, raw, "ES")) caps.estop = true else if (std.mem.eql(u8, raw, "ETH")) caps.ethernet = true else if (std.mem.eql(u8, raw, "HOME")) caps.homing = true else if (std.mem.eql(u8, raw, "LATHE")) caps.lathe = true else if (std.mem.eql(u8, raw, "MPG")) caps.mpg = true else if (std.mem.eql(u8, raw, "NOPROBE")) caps.no_probe = true else if (std.mem.eql(u8, raw, "ODO")) caps.odometer = true else if (std.mem.eql(u8, raw, "OS")) caps.opt_stop = true else if (std.mem.eql(u8, raw, "PC")) caps.probe_connect = true else if (std.mem.eql(u8, raw, "PID")) caps.pid = true else if (std.mem.eql(u8, raw, "RT+") or std.mem.eql(u8, raw, "RT-")) caps.rt_commands = true else if (std.mem.eql(u8, raw, "SD")) caps.sd_card = true else if (std.mem.eql(u8, raw, "SED")) caps.settings_desc = true else if (std.mem.eql(u8, raw, "YM")) caps.ymodem = true else if (std.mem.eql(u8, raw, "SS")) caps.spindle_sync = true else if (std.mem.eql(u8, raw, "TC")) caps.tool_change = true else if (std.mem.eql(u8, raw, "WIFI")) caps.wifi = true else if (std.mem.eql(u8, raw, "FTP")) caps.ftp = true else if (std.mem.eql(u8, raw, "WebDAV")) caps.webdav = true;
    }
}

pub fn parseAxesInfo(data: []const u8, info: *ControllerInfo) void {
    if (std.mem.indexOfScalar(u8, data, ':')) |colon| {
        info.n_axes = parse_util.parseU8(data[0..colon]) orelse info.n_axes;
        str_util.copy(&info.axis_letters, data[colon + 1 ..]);
    }
}

test "cnc: parseNewopt enums and sd" {
    var caps: Capabilities = .{};
    parseNewopt("ENUMS,SD,MPG,PROBES=2", &caps);
    try std.testing.expect(caps.enums);
    try std.testing.expect(caps.sd_card);
    try std.testing.expect(caps.mpg);
    try std.testing.expectEqual(@as(u8, 2), caps.probe_count);
}

test "cnc: parseOptLine" {
    var info: ControllerInfo = .{};
    parseOptLine("VFD,15,127,6,8", &info);
    try std.testing.expectEqualStrings("VFD", std.mem.sliceTo(&info.options, 0));
    try std.testing.expectEqual(@as(u16, 15), info.block_buffer);
    try std.testing.expectEqual(@as(u16, 127), info.rx_buffer);
    try std.testing.expectEqual(@as(u8, 6), info.n_axes);
    try std.testing.expectEqual(@as(u8, 8), info.n_tools);
}
