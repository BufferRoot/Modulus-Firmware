//! Masso Link outbound packet builders (reverse-engineered; see PROTOCOL_SPEC community docs).

const crc = @import("crc.zig");

pub const PacketType = enum(u8) {
    status = 0x01,
    version = 0x02,
    config = 0x03,
    tool = 0x08,
};

/// Keepalive / status request → sealed into `out`. Returns length or 0.
pub fn buildStatusReq(out: []u8) usize {
    if (out.len < 10) return 0;
    out[2] = 0x03;
    out[3] = 0x00;
    out[4] = @intFromEnum(PacketType.status);
    @memset(out[5..10], 0);
    return crc.seal(out, 8);
}

pub fn buildVersionReq(out: []u8) usize {
    if (out.len < 10) return 0;
    out[2] = 0x03;
    out[3] = 0x00;
    out[4] = @intFromEnum(PacketType.version);
    out[5] = 0xf8;
    out[6] = 0x2a;
    out[7] = 0x00;
    out[8] = 0x00;
    out[9] = 0x0b;
    return crc.seal(out, 8);
}

pub fn buildConfigReq(out: []u8) usize {
    if (out.len < 14) return 0;
    out[2] = 0x03;
    out[3] = 0x00;
    out[4] = @intFromEnum(PacketType.config);
    @memset(out[5..14], 0);
    return crc.seal(out, 12);
}

test {
    const std = @import("std");
    var buf: [16]u8 = undefined;
    try std.testing.expectEqual(@as(usize, 10), buildStatusReq(&buf));
    try std.testing.expectEqual(@as(u8, 0x01), buf[4]);
}
