//! Shared driver test send hooks — avoids duplicating Ctx structs in every test.

const std = @import("std");
const engine_mod = @import("grblhal/engine.zig");
const gh_session = @import("grblhal/session.zig");

pub const SendFn = engine_mod.SendFn;

pub fn appendSend(list: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator) SendFn {
    const Ctx = struct {
        var target: *std.ArrayListUnmanaged(u8) = undefined;
        var alloc: std.mem.Allocator = undefined;
        fn send(data: []const u8) bool {
            target.appendSlice(alloc, data) catch return false;
            return true;
        }
    };
    Ctx.target = list;
    Ctx.alloc = allocator;
    return Ctx.send;
}

pub fn firstByteSend(byte: *u8) SendFn {
    const Ctx = struct {
        var out: *u8 = undefined;
        fn send(data: []const u8) bool {
            out.* = data[0];
            return true;
        }
    };
    Ctx.out = byte;
    return Ctx.send;
}

pub fn lineSend(line: *[]const u8) SendFn {
    const Ctx = struct {
        var out: *[]const u8 = undefined;
        fn send(data: []const u8) bool {
            out.* = data;
            return true;
        }
    };
    Ctx.out = line;
    return Ctx.send;
}

pub fn countSend(count: *usize) SendFn {
    const Ctx = struct {
        var n: *usize = undefined;
        fn send(_: []const u8) bool {
            n.* += 1;
            return true;
        }
    };
    Ctx.n = count;
    return Ctx.send;
}

pub fn noopSend() SendFn {
    return struct {
        fn send(_: []const u8) bool {
            return true;
        }
    }.send;
}

/// Minimal banner handshake — session `.ready` on host mock path.
pub fn connectToReady(drv: anytype, tick_ms: u32) void {
    drv.onConnect(tick_ms);
    drv.feed("GrblHAL 1.1f\n");
    drv.poll(tick_ms);
}

pub fn expectReady(drv: anytype) !void {
    try std.testing.expectEqual(gh_session.SessionState.ready, drv.engine.session());
}
