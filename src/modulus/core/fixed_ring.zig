//! Fixed-size ring primitives — heap-free; shared by host event queue and Core 1 RX.

const std = @import("std");

/// Single-producer single-consumer byte ring (power-of-two size, monotonic indices).
pub fn SpscByteRing(comptime ring_size: comptime_int) type {
    comptime {
        if (!std.math.isPowerOfTwo(ring_size)) @compileError("SpscByteRing size must be power of two");
    }
    return struct {
        pub const size: u32 = ring_size;
        const mask: u32 = size - 1;

        buf: [size]u8 = undefined,
        head: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        tail: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        dropped: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

        pub fn push(self: *@This(), data: []const u8) usize {
            const head = self.head.load(.monotonic);
            const tail = self.tail.load(.acquire);
            const free: u32 = size - (head -% tail);
            const n: u32 = @intCast(@min(data.len, free));
            // ponytail: two-split @memcpy avoids per-byte masking; lets compiler vectorize
            const start: u32 = head & mask;
            const until_wrap: u32 = size - start;
            const first: u32 = @min(n, until_wrap);
            @memcpy(self.buf[start..][0..first], data[0..first]);
            if (first < n) @memcpy(self.buf[0..][0..n - first], data[first..n]);
            self.head.store(head +% n, .release);
            if (n < data.len) {
                _ = self.dropped.fetchAdd(@intCast(data.len - n), .monotonic);
            }
            return n;
        }

        pub fn readableSlice(self: *@This()) ?[]const u8 {
            const tail = self.tail.load(.monotonic);
            const head = self.head.load(.acquire);
            const avail = head -% tail;
            if (avail == 0) return null;
            const start = tail & mask;
            const until_wrap = size - start;
            const n = @min(avail, until_wrap);
            return self.buf[start .. start + n];
        }

        pub fn consume(self: *@This(), n: usize) void {
            const tail = self.tail.load(.monotonic);
            self.tail.store(tail +% @as(u32, @intCast(n)), .release);
        }

        pub fn drainInto(self: *@This(), sink: anytype) void {
            while (self.readableSlice()) |span| {
                sink.feed(span);
                self.consume(span.len);
            }
        }

        pub fn droppedBytes(self: *const @This()) u32 {
            return self.dropped.load(.monotonic);
        }
    };
}

/// Host-only fixed slot queue (single-threaded writer/reader).
pub fn FixedSlotQueue(comptime T: type, comptime capacity: comptime_int) type {
    return struct {
        storage: [capacity]T = undefined,
        read: usize = 0,
        write: usize = 0,
        count: usize = 0,

        pub fn push(self: *@This(), item: T) bool {
            if (self.count >= capacity) return false;
            self.storage[self.write] = item;
            self.write = (self.write + 1) % capacity;
            self.count += 1;
            return true;
        }

        pub fn pop(self: *@This()) ?T {
            if (self.count == 0) return null;
            const item = self.storage[self.read];
            self.read = (self.read + 1) % capacity;
            self.count -= 1;
            return item;
        }

        pub fn len(self: *const @This()) usize {
            return self.count;
        }
    };
}

test "core: fixed slot queue round-trip" {
    var q: FixedSlotQueue(u8, 4) = .{};
    try std.testing.expect(q.push('a'));
    try std.testing.expect(q.push('b'));
    try std.testing.expectEqual(@as(?u8, 'a'), q.pop());
    try std.testing.expectEqual(@as(?u8, 'b'), q.pop());
    try std.testing.expectEqual(@as(?u8, null), q.pop());
}

test "core: spsc byte ring push/drain" {
    var ring: SpscByteRing(256) = .{};
    const TestSink = struct {
        out: std.ArrayListUnmanaged(u8) = .empty,
        a: std.mem.Allocator,
        pub fn feed(self: *@This(), data: []const u8) void {
            self.out.appendSlice(self.a, data) catch unreachable;
        }
    };
    var sink: TestSink = .{ .a = std.testing.allocator };
    defer sink.out.deinit(std.testing.allocator);
    _ = ring.push("abc");
    ring.drainInto(&sink);
    try std.testing.expectEqualStrings("abc", sink.out.items);
}
