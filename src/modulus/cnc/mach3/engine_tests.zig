//! MMBP engine integration tests.

const std = @import("std");
const testing = std.testing;
const mach_session = @import("session.zig");
const engine_mod = @import("engine.zig");

const Engine = engine_mod.Engine;

test "mach3: hello poll reaches ready" {
    var sent = std.ArrayListUnmanaged(u8).empty;
    defer sent.deinit(testing.allocator);

    const Ctx = struct {
        var list: *std.ArrayListUnmanaged(u8) = undefined;
        fn send(data: []const u8) bool {
            list.appendSlice(testing.allocator, data) catch return false;
            return true;
        }
    };
    Ctx.list = &sent;

    var engine = Engine.init(Ctx.send);
    engine.onConnect(0);
    try testing.expect(std.mem.startsWith(u8, sent.items, "HELLO modulus-tab5 "));
    engine.feed("HELLO ACK Mach3\r\n", 0);
    try testing.expect(std.mem.indexOf(u8, sent.items, "GET STATUS") != null);
    engine.feed("STATUS IDLE ENABLED=1 ESTOP=0\r\n", 0);
    engine.feed("POS X=0 Y=0 Z=0\r\n", 0);
    engine.feed("OVR FEED=100 SPINDLE=100 RAPID=100\r\n", 0);
    try testing.expectEqual(mach_session.SessionState.ready, engine.session());
}

test "mach3: unlock leaves configuring then OK reaches ready; estop locks" {
    var sent = std.ArrayListUnmanaged(u8).empty;
    defer sent.deinit(testing.allocator);

    const Ctx = struct {
        var list: *std.ArrayListUnmanaged(u8) = undefined;
        fn send(data: []const u8) bool {
            list.appendSlice(testing.allocator, data) catch return false;
            return true;
        }
    };
    Ctx.list = &sent;

    var engine = Engine.init(Ctx.send);
    engine.onConnect(0);
    engine.feed("HELLO ACK Mach3\r\n", 0);
    engine.feed("STATUS IDLE ENABLED=1 ESTOP=0\r\n", 0);
    try testing.expectEqual(mach_session.SessionState.ready, engine.session());

    engine.sendReset();
    try testing.expectEqual(mach_session.SessionState.locked, engine.session());
    engine.sendUnlock();
    try testing.expectEqual(mach_session.SessionState.configuring, engine.session());
    engine.feed("OK\r\n", 100);
    try testing.expectEqual(mach_session.SessionState.ready, engine.session());

    engine.feed("STATUS IDLE ENABLED=0 ESTOP=1\r\n", 200);
    try testing.expectEqual(mach_session.SessionState.locked, engine.session());
}
