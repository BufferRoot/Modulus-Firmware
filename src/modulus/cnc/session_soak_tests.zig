//! P3: host soak — connect → banner → ready → disconnect across protocols
//! and Zig settings transport preference (WS / Telnet / RS-485).

const std = @import("std");
const testing = std.testing;
const driver_mod = @import("driver.zig");
const test_util = @import("driver_test_util.zig");
const gh_session = @import("grblhal/session.zig");
const lc_engine = @import("linuxcnc/engine.zig");
const lc_session = @import("linuxcnc/session.zig");
const mach_engine = @import("mach3/engine.zig");
const mach_session = @import("mach3/session.zig");
const settings_prefs = @import("../ui_engine/settings_prefs.zig");

const Driver = driver_mod.Driver;
const soak_rounds: usize = 8;

fn grblhalRoundTrip(drv: *Driver, sent: *std.ArrayListUnmanaged(u8), tick: u32) !void {
    sent.clearRetainingCapacity();
    test_util.connectToReady(drv, tick);
    drv.feed("ok\n");
    drv.poll(tick);
    try test_util.expectReady(drv);
    drv.onDisconnect();
    try testing.expectEqual(gh_session.SessionState.disconnected, drv.engine.session());
}

test "soak: grblhal connect ready disconnect x8" {
    var drv = Driver.init(.{});
    var sent = std.ArrayListUnmanaged(u8).empty;
    defer sent.deinit(testing.allocator);
    drv.setSendFn(test_util.appendSend(&sent, testing.allocator));
    var i: usize = 0;
    while (i < soak_rounds) : (i += 1) {
        try grblhalRoundTrip(&drv, &sent, @intCast(i * 10));
    }
}

test "soak: linuxcnc connect ready disconnect x8" {
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

    var i: usize = 0;
    while (i < soak_rounds) : (i += 1) {
        sent.clearRetainingCapacity();
        var engine = lc_engine.Engine.init(Ctx.send);
        engine.onConnect(0);
        engine.feed("HELLO ACK EMCNETSVR 1.1\r\n", 0);
        engine.feed("ENABLE ON\r\n", 0);
        engine.feed("ESTOP OFF\r\n", 0);
        engine.feed("PROGRAM_STATUS IDLE\r\n", 0);
        engine.feed("ABS_ACT_POS 0 0 0\r\n", 0);
        engine.feed("FEED_OVERRIDE 100\r\n", 0);
        engine.feed("SPINDLE_OVERRIDE 100\r\n", 0);
        try testing.expectEqual(lc_session.SessionState.ready, engine.session());
        engine.onDisconnect();
        try testing.expectEqual(lc_session.SessionState.disconnected, engine.session());
    }
}

test "soak: mach3 connect ready disconnect x8" {
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

    var i: usize = 0;
    while (i < soak_rounds) : (i += 1) {
        sent.clearRetainingCapacity();
        var engine = mach_engine.Engine.init(Ctx.send);
        engine.onConnect(0);
        engine.feed("HELLO ACK Mach3\r\n", 0);
        engine.feed("STATUS IDLE ENABLED=1 ESTOP=0\r\n", 0);
        engine.feed("POS X=0 Y=0 Z=0\r\n", 0);
        engine.feed("OVR FEED=100 SPINDLE=100 RAPID=100\r\n", 0);
        try testing.expectEqual(mach_session.SessionState.ready, engine.session());
        engine.onDisconnect();
        try testing.expectEqual(mach_session.SessionState.disconnected, engine.session());
    }
}

test "soak: Zig settings preferred transport WS Telnet RS-485" {
    // Proto → preferred conn: FluidNC/Masso WS(1), LinuxCNC/Mach3 Telnet(2), else RS-485(4).
    try testing.expectEqual(@as(u8, 4), settings_prefs.CncPrefs.preferredTransport(0)); // grblhal
    try testing.expectEqual(@as(u8, 4), settings_prefs.CncPrefs.preferredTransport(1)); // classic
    try testing.expectEqual(@as(u8, 1), settings_prefs.CncPrefs.preferredTransport(2)); // fluidnc → WS
    try testing.expectEqual(@as(u8, 2), settings_prefs.CncPrefs.preferredTransport(3)); // linuxcnc → Telnet
    try testing.expectEqual(@as(u8, 2), settings_prefs.CncPrefs.preferredTransport(4)); // mach3 → Telnet
    try testing.expectEqual(@as(u8, 1), settings_prefs.CncPrefs.preferredTransport(5)); // masso → WS

    var prefs: settings_prefs.CncPrefs = .{};
    prefs.proto = 2;
    prefs.applyPreferredTransport();
    try testing.expectEqual(@as(u8, 1), prefs.conn);
    try testing.expect(!prefs.transport_off);
    prefs.startConnect();
    try testing.expectEqual(@as(u8, 2), prefs.session_phase);
    prefs.tickTelemetry();
    try testing.expectEqual(@as(u8, 3), prefs.session_phase);
    try testing.expect(prefs.session_up);
    prefs.disconnect();
    try testing.expectEqual(@as(u8, 0), prefs.session_phase);
    try testing.expect(!prefs.session_up);

    prefs.proto = 3;
    prefs.applyPreferredTransport();
    try testing.expectEqual(@as(u8, 2), prefs.conn);
    try testing.expectEqual(@as(u16, 5007), prefs.tn_port);

    prefs.proto = 0;
    prefs.applyPreferredTransport();
    try testing.expectEqual(@as(u8, 4), prefs.conn); // RS-485
}
