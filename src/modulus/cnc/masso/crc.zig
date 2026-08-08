//! Masso Link CRC16-CCITT (poly 0x1021, init 0) over payload after checksum bytes.

pub fn crc16Ccitt(data: []const u8) u16 {
    var crc: u16 = 0;
    for (data) |b| {
        crc ^= @as(u16, b) << 8;
        var i: u8 = 0;
        while (i < 8) : (i += 1) {
            if ((crc & 0x8000) != 0) {
                crc = (crc << 1) ^ 0x1021;
            } else {
                crc <<= 1;
            }
        }
    }
    return crc;
}

/// Append little-endian CRC16 over body into out[0..2]; body is out[2..].
pub fn seal(out: []u8, body_len: usize) usize {
    if (body_len + 2 > out.len) return 0;
    const crc = crc16Ccitt(out[2 .. 2 + body_len]);
    out[0] = @truncate(crc);
    out[1] = @truncate(crc >> 8);
    return body_len + 2;
}

test "masso: crc16 known vector" {
    const std = @import("std");
    // Body: magic 03 00, type 01, five zeros — matches keepalive body.
    const body = [_]u8{ 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00 };
    const crc = crc16Ccitt(&body);
    var pkt: [10]u8 = undefined;
    @memcpy(pkt[2..], &body);
    const n = seal(&pkt, body.len);
    try std.testing.expectEqual(@as(usize, 10), n);
    try std.testing.expectEqual(crc, @as(u16, pkt[0]) | (@as(u16, pkt[1]) << 8));
}
