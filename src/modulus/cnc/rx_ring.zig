//! Lock-free SPSC byte ring — producer: `serial_rx` task (Core 1, pri 6);
//! consumer: `sys_task` tick (Core 1, pri 5). Makes the grblHAL `Engine`
//! single-owner: RX bytes are staged here and drained at the top of
//! `Runtime.systemTick`, so `engine.feed`/`engine.poll` never race.

const std = @import("std");
const fixed_ring = @import("../core/fixed_ring.zig");

/// Power of two; must absorb the largest single delivery between two 10 ms
/// ticks: 512 B UART driver flushes, and up to 2048 B from the WS accumulator
/// (`abi_guard.max_serial_rx_chunk`) — 4096 leaves headroom for a flush plus
/// a max WS frame in the same window.
pub const RxRing = fixed_ring.SpscByteRing(4096);

// ── tests ──

const TestSink = struct {
    out: std.ArrayListUnmanaged(u8) = .empty,
    a: std.mem.Allocator,

    pub fn feed(self: *TestSink, data: []const u8) void {
        self.out.appendSlice(self.a, data) catch unreachable;
    }
};

test "cnc: rx ring push/drain round-trip" {
    var ring = RxRing{};
    var sink = TestSink{ .a = std.testing.allocator };
    defer sink.out.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), ring.push("<Idle"));
    try std.testing.expectEqual(@as(usize, 2), ring.push(">\n"));
    ring.drainInto(&sink);
    try std.testing.expectEqualStrings("<Idle>\n", sink.out.items);
    try std.testing.expectEqual(@as(?[]const u8, null), ring.readableSlice());
}

test "cnc: rx ring wraps across boundary" {
    var ring = RxRing{};
    var sink = TestSink{ .a = std.testing.allocator };
    defer sink.out.deinit(std.testing.allocator);

    // Advance indices near the wrap point, then push across it.
    const pad = RxRing.size - 3;
    var i: u32 = 0;
    while (i < pad) : (i += 1) {
        _ = ring.push("x");
    }
    ring.drainInto(&sink);
    sink.out.clearRetainingCapacity();

    try std.testing.expectEqual(@as(usize, 6), ring.push("ABCDEF"));
    ring.drainInto(&sink);
    try std.testing.expectEqualStrings("ABCDEF", sink.out.items);
}

test "cnc: rx ring drops on overflow and counts" {
    var ring = RxRing{};
    const big = "y" ** (RxRing.size + 10);
    const accepted = ring.push(big);
    try std.testing.expectEqual(@as(usize, RxRing.size), accepted);
    try std.testing.expectEqual(@as(u32, 10), ring.droppedBytes());
}
