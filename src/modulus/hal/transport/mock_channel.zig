//! Fixed-buffer mock byte channel — host UART/TCP stand-in, zero heap in poll.

const std = @import("std");
const driver = @import("../../cnc/driver.zig");

pub const cap = 512;

pub const Channel = struct {
    tx: [cap]u8 = undefined,
    tx_len: usize = 0,
    rx: [cap]u8 = undefined,
    rx_read: usize = 0,
    rx_write: usize = 0,
    rx_count: usize = 0,

    pub fn reset(self: *Channel) void {
        self.* = .{};
    }

    pub fn send(self: *Channel, data: []const u8) bool {
        if (self.tx_len + data.len > cap) return false;
        @memcpy(self.tx[self.tx_len..][0..data.len], data);
        self.tx_len += data.len;
        return true;
    }

    pub fn drainTx(self: *Channel) []const u8 {
        const slice = self.tx[0..self.tx_len];
        self.tx_len = 0;
        return slice;
    }

    pub fn injectRx(self: *Channel, data: []const u8) bool {
        if (data.len > cap) return false;
        if (self.rx_count + data.len > cap) return false;
        for (data) |b| {
            self.rx[self.rx_write] = b;
            self.rx_write = (self.rx_write + 1) % cap;
            self.rx_count += 1;
        }
        return true;
    }

    pub fn pollRx(self: *Channel, drv: *driver.Driver) void {
        var chunk: [64]u8 = undefined;
        while (self.rx_count > 0) {
            const n = @min(self.rx_count, chunk.len);
            for (0..n) |i| {
                chunk[i] = self.rx[self.rx_read];
                self.rx_read = (self.rx_read + 1) % cap;
            }
            self.rx_count -= n;
            drv.feed(chunk[0..n]);
        }
    }
};

/// Alias for comptime serial backend selection (`serial.zig`).
pub const Io = Channel;

test "hal: mock channel tx and rx" {
    var ch: Channel = .{};
    try std.testing.expect(ch.send("abc"));
    try std.testing.expectEqualStrings("abc", ch.drainTx());

    var drv = driver.Driver.init(.{});
    try std.testing.expect(ch.injectRx("ok\n"));
    ch.pollRx(&drv);
}
