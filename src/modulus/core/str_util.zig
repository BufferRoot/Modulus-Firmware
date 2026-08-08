//! Bounded C-string copy — mirrors `str_util.h` (avoids truncation warnings in C++).

const std = @import("std");

pub inline fn copy(dst: []u8, src: []const u8) void {
    if (dst.len == 0) return;
    const n = @min(src.len, dst.len - 1);
    @memcpy(dst[0..n], src[0..n]);
    dst[n] = 0;
}

test "core: str_util bounded copy" {
    var buf: [5]u8 = undefined;
    copy(&buf, "abcdef");
    try std.testing.expectEqualStrings("abcd", std.mem.sliceTo(&buf, 0));
}

test "core: str_util null-safe empty dst" {
    copy(&.{}, "x");
}
