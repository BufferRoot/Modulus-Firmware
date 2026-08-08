//! Defensive checks for C→Zig ABI exports (null pointers, oversize slices).

/// Max bytes per `modulus_zig_serial_rx` call — sanity bound against corrupt
/// `len` from C callers, NOT flow control. Must cover the largest legitimate
/// delivery (WS accumulator = 2048 B); the old 512 cap silently dropped the
/// tail of larger frames, corrupting the CNC stream. Real backpressure is the
/// RX ring, which drops with a counter (`droppedBytes`) when overrun.
pub const max_serial_rx_chunk: usize = 2048;

pub fn isNonNull(ptr: anytype) bool {
    return @intFromPtr(ptr) != 0;
}

pub fn clampSerialLen(len: usize) usize {
    return @min(len, max_serial_rx_chunk);
}

test "firmware: abi_guard clamps serial rx len" {
    try @import("std").testing.expectEqual(@as(usize, 2048), clampSerialLen(9000));
    try @import("std").testing.expectEqual(@as(usize, 64), clampSerialLen(64));
}
