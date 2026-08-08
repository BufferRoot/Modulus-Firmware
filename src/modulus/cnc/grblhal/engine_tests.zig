//! grblHAL engine integration tests.

const std = @import("std");
const testing = std.testing;
const parser = @import("parser.zig");
const gh_session = @import("session.zig");
const engine_mod = @import("engine.zig");

const Engine = engine_mod.Engine;
const test_util = @import("../driver_test_util.zig");

test "cnc: engine connect to ready via banner" {
    var sent = std.ArrayListUnmanaged(u8).empty;
    defer sent.deinit(testing.allocator);

    var engine = Engine.init(test_util.appendSend(&sent, testing.allocator));
    engine.onConnect(0);
    engine.feed("GrblHAL 1.1f ['$' for help]\n", 0);
    engine.poll(0);
    engine.feed("ok\n", 0);
    try testing.expectEqual(gh_session.SessionState.ready, engine.session());
}

test "cnc: engine classic grbl banner skips $I+ and goes ready on status" {
    var sent = std.ArrayListUnmanaged(u8).empty;
    defer sent.deinit(testing.allocator);

    var engine = Engine.init(test_util.appendSend(&sent, testing.allocator));
    engine.setProtocol(@import("../cnc_config.zig").Protocol.classic_grbl);
    engine.onConnect(0);
    engine.feed("Grbl 1.1f ['$' for help]\n", 0);
    try testing.expectEqual(@as(usize, 1), sent.items.len);
    try testing.expectEqual(@as(u8, '?'), sent.items[0]);
    engine.feed("<Idle|MPos:0.000,0.000,0.000|FS:0,0>\n", 0);
    try testing.expectEqual(gh_session.SessionState.ready, engine.session());
}

test "cnc: engine feed hold sends 0x82" {
    var last: [4]u8 = undefined;
    var last_len: usize = 0;
    const Ctx = struct {
        var buf: []u8 = undefined;
        var len: *usize = undefined;
        fn send(data: []const u8) bool {
            @memcpy(buf[0..data.len], data);
            len.* = data.len;
            return true;
        }
    };
    Ctx.buf = &last;
    Ctx.len = &last_len;

    var engine = Engine.init(Ctx.send);
    engine.sendFeedHold();
    try testing.expectEqual(@as(usize, 1), last_len);
    try testing.expectEqual(@as(u8, 0x82), last[0]);
}

test "cnc: engine response timeout disconnects" {
    var engine = Engine.init(null);
    engine.onConnect(0);
    engine.feed("GrblHAL 1.1f\n", 0);
    engine.tick_ms = 100;
    engine.feed("ok\n", 100);
    try testing.expectEqual(gh_session.SessionState.ready, engine.session());
    engine.last_response_ms = 1000;
    engine.poll(1000 + gh_session.response_timeout_ms);
    try testing.expectEqual(gh_session.SessionState.disconnected, engine.session());
}

test "cnc: engine enumeration gate without ENUMS goes ready" {
    var sent = std.ArrayListUnmanaged(u8).empty;
    defer sent.deinit(testing.allocator);
    var engine = Engine.init(test_util.appendSend(&sent, testing.allocator));
    engine.onConnect(0);
    engine.feed("GrblHAL 1.1f\n", 0);
    engine.poll(0);
    engine.feed("[NEWOPT:SD,MPG]\n", 0);
    engine.feed("ok\n", 0);
    try testing.expectEqual(gh_session.SessionState.ready, engine.session());
    try testing.expect(!std.mem.endsWith(u8, sent.items, "$EA\n"));
}

test "cnc: engine enumeration gate with ENUMS sends $EA $EE $ES $EG" {
    var sent = std.ArrayListUnmanaged(u8).empty;
    defer sent.deinit(testing.allocator);
    var engine = Engine.init(test_util.appendSend(&sent, testing.allocator));
    engine.onConnect(0);
    engine.feed("GrblHAL 1.1f\n", 0);
    engine.poll(0);
    sent.clearRetainingCapacity();
    engine.feed("[NEWOPT:ENUMS,SD]\n", 0);
    engine.feed("ok\n", 0);
    try testing.expectEqual(gh_session.SessionState.configuring, engine.session());
    try testing.expect(std.mem.indexOf(u8, sent.items, "$EA\n") != null);
    try testing.expect(std.mem.indexOf(u8, sent.items, "$EE\n") != null);
    try testing.expect(std.mem.indexOf(u8, sent.items, "$ES\n") != null);
    try testing.expect(std.mem.indexOf(u8, sent.items, "$EG\n") != null);
    engine.feed("ok\n", 0);
    try testing.expectEqual(gh_session.SessionState.ready, engine.session());
}

test "cnc: engine $I+ multi-line info reaches ready" {
    var sent = std.ArrayListUnmanaged(u8).empty;
    defer sent.deinit(testing.allocator);
    var engine = Engine.init(test_util.appendSend(&sent, testing.allocator));
    engine.onConnect(0);
    engine.feed("GrblHAL 1.1f\n", 0);
    try testing.expect(std.mem.endsWith(u8, sent.items, "$I+\n"));
    engine.feed("[VER:1.1f]\n", 0);
    engine.feed("[OPT:SD,MPG,14,256,3,0]\n", 0);
    engine.feed("[NEWOPT:SD]\n", 0);
    engine.feed("ok\n", 0);
    try testing.expectEqual(gh_session.SessionState.ready, engine.session());
    try testing.expect(engine.parser.ctrl_info.caps.sd_card);
}

test "cnc: engine setSendFn preserves session state" {
    var count_a: u32 = 0;
    var count_b: u32 = 0;
    const SendA = struct {
        var n: *u32 = undefined;
        fn send(_: []const u8) bool {
            n.* += 1;
            return true;
        }
    };
    const SendB = struct {
        var n: *u32 = undefined;
        fn send(_: []const u8) bool {
            n.* += 1;
            return true;
        }
    };
    SendA.n = &count_a;
    SendB.n = &count_b;

    var engine = Engine.init(SendA.send);
    engine.onConnect(100);
    engine.feed("GrblHAL 1.1f\n", 100);
    engine.poll(100);
    engine.feed("ok\n", 100);
    try testing.expectEqual(gh_session.SessionState.ready, engine.session());

    count_a = 0;
    count_b = 0;
    engine.setSendFn(SendB.send);
    try testing.expectEqual(gh_session.SessionState.ready, engine.session());
    engine.sendFeedHold();
    try testing.expectEqual(@as(u32, 0), count_a);
    try testing.expectEqual(@as(u32, 1), count_b);
}

test "cnc: engine drops oversize line and resets assembly" {
    var engine = Engine.init(null);
    engine.onConnect(0);
    const fill_len = parser.line_buf_max - 1;
    const long = "X" ** fill_len;
    engine.feed(long, 0);
    try testing.expectEqual(fill_len, engine.line_pos);
    engine.feed("Y", 0);
    try testing.expectEqual(@as(u32, 1), engine.lines_dropped);
    try testing.expectEqual(@as(usize, 0), engine.line_pos);
}
