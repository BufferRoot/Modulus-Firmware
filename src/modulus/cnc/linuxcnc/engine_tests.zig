//! LinuxCNC engine integration tests.

const std = @import("std");
const testing = std.testing;
const lc_session = @import("session.zig");
const engine_mod = @import("engine.zig");
const cnc_state = @import("../cnc_state.zig");

const Engine = engine_mod.Engine;

test "linuxcnc: hello enable poll reaches ready" {
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
    try testing.expect(std.mem.startsWith(u8, sent.items, "hello EMC "));
    engine.feed("HELLO ACK EMCNETSVR 1.1\r\n", 0);
    engine.feed("ENABLE ON\r\n", 0);
    engine.feed("ESTOP OFF\r\n", 0);
    engine.feed("PROGRAM_STATUS IDLE\r\n", 0);
    engine.feed("ABS_ACT_POS 0 0 0\r\n", 0);
    engine.feed("FEED_OVERRIDE 100\r\n", 0);
    engine.feed("SPINDLE_OVERRIDE 100\r\n", 0);
    try testing.expectEqual(lc_session.SessionState.ready, engine.session());
}

test "linuxcnc: estop locks but poll keeps link; spindle updates" {
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
    engine.feed("HELLO ACK EMCNETSVR 1.1\r\n", 0);
    engine.feed("ENABLE ON\r\n", 100);
    engine.feed("PROGRAM_STATUS IDLE\r\n", 100);
    try testing.expectEqual(lc_session.SessionState.ready, engine.session());

    engine.feed("ESTOP ON\r\n", 200);
    try testing.expectEqual(lc_session.SessionState.locked, engine.session());

    sent.clearRetainingCapacity();
    engine.poll(500);
    try testing.expect(std.mem.indexOf(u8, sent.items, "get spindle") != null);

    engine.feed("SPINDLE FORWARD\r\n", 500);
    try testing.expectEqual(cnc_state.SpindleState.cw, engine.status().spindle_dir);

    engine.feed("ESTOP OFF\r\n", 600);
    try testing.expectEqual(lc_session.SessionState.ready, engine.session());
}
