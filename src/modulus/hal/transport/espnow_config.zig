//! ESP-NOW NVS helpers — MAC parse/format, channel + PHY rate (transport config).

const std = @import("std");
const settings_keys = @import("../../core/settings_keys.zig");
const settings_store = @import("../../core/settings_store.zig");

/// Matches C6/P4 ESPNOW_RATE_* (11b + OFDM + HT20 MCS).
pub const RateIdx = enum(u8) {
    rate_1m = 0,
    rate_2m = 1,
    rate_5m5 = 2,
    rate_11m = 3,
    rate_6m = 4,
    rate_12m = 5,
    rate_24m = 6,
    rate_mcs0 = 7,
    rate_mcs3 = 8,
};

pub fn parseMac(mac_str: []const u8, out: *[6]u8) bool {
    if (mac_str.len < 17) return false;
    var i: usize = 0;
    var byte_idx: usize = 0;
    while (byte_idx < 6) : (byte_idx += 1) {
        if (i + 1 >= mac_str.len) return false;
        const hi = std.fmt.parseInt(u8, mac_str[i .. i + 2], 16) catch return false;
        out[byte_idx] = hi;
        i += 2;
        if (byte_idx < 5) {
            if (i >= mac_str.len or mac_str[i] != ':') return false;
            i += 1;
        }
    }
    return i == mac_str.len;
}

pub fn formatMac(mac: *const [6]u8, buf: []u8) usize {
    const written = std.fmt.bufPrint(buf, "{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}:{X:0>2}", .{
        mac[0], mac[1], mac[2], mac[3], mac[4], mac[5],
    }) catch return 0;
    return written.len;
}

pub fn channelFromIdx(idx: u8) u8 {
    const clamped = @min(idx, 12);
    return clamped + 1;
}

pub fn getChannelIdx(store: *const settings_store.Store) u8 {
    return store.getU8(settings_keys.en_chan, 0);
}

pub fn getChannel(store: *const settings_store.Store) u8 {
    return channelFromIdx(getChannelIdx(store));
}

/// Default 24 Mbps OFDM (idx 6) — adaptive fallback on P4 drops tiers on fail.
pub fn getRateIdx(store: *const settings_store.Store) u8 {
    return @min(store.getU8(settings_keys.en_rate, @intFromEnum(RateIdx.rate_24m)), @intFromEnum(RateIdx.rate_mcs3));
}

test "hal: espnow parse and format mac" {
    var mac: [6]u8 = undefined;
    try std.testing.expect(parseMac("AA:BB:CC:DD:EE:FF", &mac));
    try std.testing.expectEqual(@as(u8, 0xAA), mac[0]);
    try std.testing.expectEqual(@as(u8, 0xFF), mac[5]);
    var buf: [18]u8 = undefined;
    const n = formatMac(&mac, &buf);
    try std.testing.expect(n > 0);
    try std.testing.expectEqualStrings("AA:BB:CC:DD:EE:FF", buf[0..n]);
}

test "hal: espnow channel index" {
    try std.testing.expectEqual(@as(u8, 1), channelFromIdx(0));
    try std.testing.expectEqual(@as(u8, 13), channelFromIdx(12));
}

test "hal: espnow rate idx default clamp" {
    try std.testing.expectEqual(@as(u8, 6), @intFromEnum(RateIdx.rate_24m));
}
