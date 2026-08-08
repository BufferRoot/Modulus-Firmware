//! Shared grblHAL text parsing — ints from ASCII tokens.

const std = @import("std");

pub fn parseU8(s: []const u8) ?u8 {
    return std.fmt.parseInt(u8, s, 10) catch null;
}

pub fn parseI16(s: []const u8) ?i16 {
    return std.fmt.parseInt(i16, s, 10) catch null;
}

pub fn parseU16(s: []const u8) ?u16 {
    return std.fmt.parseInt(u16, s, 10) catch null;
}

pub fn parseU32(s: []const u8) ?u32 {
    return std.fmt.parseInt(u32, s, 10) catch null;
}
