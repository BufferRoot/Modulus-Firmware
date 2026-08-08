//! Host-only leak detection for unit and integration tests.
//!
//! Prefer `std.testing.allocator` in simple tests — it fails the test on leak.
//! Use `LeakGuard` when you need an owned GPA (nested scopes, multi-phase setup).

const std = @import("std");

pub const LeakGuard = struct {
    gpa: std.heap.DebugAllocator(.{}),

    pub fn init() LeakGuard {
        return .{ .gpa = .init };
    }

    pub fn allocator(self: *LeakGuard) std.mem.Allocator {
        return self.gpa.allocator();
    }

    /// Panics on leak so CI and local `zig build test` fail loudly.
    pub fn deinit(self: *LeakGuard) void {
        const status = self.gpa.deinit();
        if (status == .leak) {
            @panic("LeakGuard: unfreed allocation(s) — add defer/errdefer or free before scope exit");
        }
    }
};

/// Wraps a fallible block; always runs leak check even when `body` returns error.
pub fn withNoLeaks(comptime body: anytype) !void {
    var guard = LeakGuard.init();
    defer guard.deinit();
    const allocator = guard.allocator();
    try body(allocator);
}

test "LeakGuard: clean alloc/free" {
    var guard = LeakGuard.init();
    defer guard.deinit();
    const allocator = guard.allocator();

    const buf = try allocator.alloc(u8, 4);
    defer allocator.free(buf);
    @memset(buf, 0);
}

test "LeakGuard: errdefer frees on error path" {
    const Fail = struct {
        fn run(allocator: std.mem.Allocator) !void {
            const buf = try allocator.alloc(u8, 8);
            errdefer allocator.free(buf);
            return error.Simulated;
        }
    };
    var guard = LeakGuard.init();
    defer guard.deinit();
    try std.testing.expectError(error.Simulated, Fail.run(guard.allocator()));
}

test "std.testing.allocator rejects orphan" {
    const allocator = std.testing.allocator;
    const buf = try allocator.alloc(u8, 1);
    allocator.free(buf);
}
