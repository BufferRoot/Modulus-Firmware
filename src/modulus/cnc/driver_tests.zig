//! CNC driver integration tests (split from `driver.zig` for file-size budget).

const std = @import("std");
const testing = std.testing;
const cnc_state = @import("cnc_state.zig");
const settings_keys = @import("../core/settings_keys.zig");
const settings_store = @import("../core/settings_store.zig");
const driver_mod = @import("driver.zig");
const test_util = @import("driver_test_util.zig");

const Driver = driver_mod.Driver;
const HomingBlockReason = driver_mod.HomingBlockReason;

test "cnc: driver session connect to ready" {
    var drv = Driver.init(.{});
    var sent = std.ArrayListUnmanaged(u8).empty;
    defer sent.deinit(testing.allocator);
    drv.setSendFn(test_util.appendSend(&sent, testing.allocator));
    test_util.connectToReady(&drv, 0);
    drv.feed("ok\n");
    drv.poll(0);
    try test_util.expectReady(&drv);
}

test "cnc: driver feed hold when ready sends 0x82" {
    var drv = Driver.init(.{});
    var last: u8 = 0;
    drv.setSendFn(test_util.firstByteSend(&last));
    test_util.connectToReady(&drv, 0);
    drv.feed("ok\n");
    drv.poll(0);
    drv.cmdFeedHold();
    try testing.expectEqual(@as(u8, 0x82), last);
}

test "cnc: driver fan toggle when ready sends 0x8A" {
    var drv = Driver.init(.{});
    var last: u8 = 0;
    drv.setSendFn(test_util.firstByteSend(&last));
    test_util.connectToReady(&drv, 0);
    drv.feed("ok\n");
    drv.poll(0);
    drv.cmdFanToggle();
    try testing.expectEqual(@as(u8, 0x8A), last);
}

test "cnc: driver mist toggle when ready sends 0xA1" {
    var drv = Driver.init(.{});
    var last: u8 = 0;
    drv.setSendFn(test_util.firstByteSend(&last));
    test_util.connectToReady(&drv, 0);
    drv.feed("ok\n");
    drv.poll(0);
    drv.cmdMistToggle();
    try testing.expectEqual(@as(u8, 0xA1), last);
}

test "cnc: driver single step when ready sends 0x89" {
    var drv = Driver.init(.{});
    var last: u8 = 0;
    drv.setSendFn(test_util.firstByteSend(&last));
    test_util.connectToReady(&drv, 0);
    drv.feed("ok\n");
    drv.poll(0);
    drv.cmdSingleStep();
    try testing.expectEqual(@as(u8, 0x89), last);
}

test "cnc: driver fan toggle gated when disconnected" {
    var drv = Driver.init(.{});
    var tx_len: usize = 0;
    drv.setSendFn(test_util.countSend(&tx_len));
    drv.cmdFanToggle();
    try testing.expectEqual(@as(usize, 0), tx_len);
}

test "cnc: driver disconnected feed hold mutates snapshot" {
    var drv = Driver.init(.{});
    drv.cmdFeedHold();
    try testing.expectEqual(cnc_state.MachineState.hold, drv.status().state);
}

test "cnc: driver cmd gating blocks cycle when not ready" {
    var drv = Driver.init(.{});
    var tx_len: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn send(_: []const u8) bool {
            count.* += 1;
            return true;
        }
    };
    Ctx.count = &tx_len;
    drv.setSendFn(Ctx.send);
    drv.cmdCycleStart();
    try testing.expectEqual(@as(usize, 0), tx_len);
    try testing.expectEqual(cnc_state.MachineState.run, drv.status().state);
}

test "cnc: driver homing blocked on alarm" {
    var drv = Driver.init(.{});
    drv.setSendFn(struct {
        fn send(_: []const u8) bool {
            return true;
        }
    }.send);
    drv.onConnect(0);
    drv.feed("GrblHAL 1.1f\nok\n");
    drv.poll(0);
    drv.feed("<Alarm:1|>\n");
    drv.poll(0);
    try testing.expectEqual(cnc_state.MachineState.alarm, drv.status().state);
    try testing.expectEqual(HomingBlockReason.alarm, drv.homingBlockReason());
}

test "cnc: driver local MPG armed survives update without |MPG| tag" {
    var drv = Driver.init(.{});
    drv.setSendFn(struct {
        fn send(_: []const u8) bool {
            return true;
        }
    }.send);
    drv.onConnect(0);
    drv.feed("GrblHAL 1.1f\nok\n");
    drv.poll(0);
    drv.cmdMpgToggle();
    try testing.expect(drv.status().mpg_active);
    drv.feed("<Idle|MPos:0,0,0|>\n");
    drv.poll(100);
    try testing.expect(drv.status().mpg_active);
    drv.cmdMpgToggle();
    try testing.expect(!drv.status().mpg_active);
}

test "cnc: driver mpg toggle skips 0x8B when local matches remote" {
    var drv = Driver.init(.{});
    var tx_len: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn send(_: []const u8) bool {
            count.* += 1;
            return true;
        }
    };
    Ctx.count = &tx_len;
    drv.setSendFn(Ctx.send);
    drv.onConnect(0);
    drv.feed("GrblHAL 1.1f\nok\n");
    drv.poll(0);
    drv.cmdMpgToggle();
    try testing.expect(drv.status().mpg_active);
    try testing.expect(!drv.status().mpg_remote);
    tx_len = 0;
    drv.cmdMpgToggle();
    try testing.expectEqual(@as(usize, 0), tx_len);
}

test "cnc: driver stop when ready sends soft reset 0x18" {
    var drv = Driver.init(.{});
    var last: u8 = 0;
    const Ctx = struct {
        var byte: *u8 = undefined;
        fn send(data: []const u8) bool {
            byte.* = data[0];
            return true;
        }
    };
    Ctx.byte = &last;
    drv.setSendFn(Ctx.send);
    drv.onConnect(0);
    drv.feed("GrblHAL 1.1f\nok\n");
    drv.poll(0);
    drv.cmdStop();
    try testing.expectEqual(@as(u8, 0x18), last);
}

test "cnc: driver cmdSendGcode clamps S word to cnc_mxrpm" {
    var store = settings_store.Store.init(testing.allocator);
    defer store.deinit();
    try store.setU16(settings_keys.cnc_mxrpm, 12000);

    var drv = Driver.init(.{ .store = &store });
    const Ctx = struct {
        var line: []const u8 = "";
        fn send(data: []const u8) bool {
            line = data;
            return true;
        }
    };
    drv.setSendFn(Ctx.send);
    drv.onConnect(0);
    drv.feed("GrblHAL 1.1f\nok\n");
    drv.poll(0);
    drv.cmdSendGcode("M3 S24000");
    try testing.expectEqualStrings("M3 S12000\n", Ctx.line);
}

test "cnc: driver cmdSpindleCw sends clamped M3" {
    var store = settings_store.Store.init(testing.allocator);
    defer store.deinit();
    try store.setU16(settings_keys.cnc_mxrpm, 8000);

    var drv = Driver.init(.{ .store = &store });
    const Ctx = struct {
        var line: []const u8 = "";
        fn send(data: []const u8) bool {
            line = data;
            return true;
        }
    };
    drv.setSendFn(Ctx.send);
    drv.onConnect(0);
    drv.feed("GrblHAL 1.1f\nok\n");
    drv.poll(0);
    drv.lockSnapshot();
    drv.snapshot.spindle_speed = 10000;
    drv.snapshot.overrides.spindle = 100;
    drv.unlockSnapshot();
    drv.cmdSpindleCw();
    try testing.expectEqualStrings("M3 S8000\n", Ctx.line);
}

test "cnc: driver cmdSpindleCcw blocked when cnc_spcw off" {
    var store = settings_store.Store.init(testing.allocator);
    defer store.deinit();
    try store.setBool(settings_keys.cnc_spcw, false);

    var drv = Driver.init(.{ .store = &store });
    var tx: usize = 0;
    const Ctx = struct {
        var count: *usize = undefined;
        fn send(_: []const u8) bool {
            count.* += 1;
            return true;
        }
    };
    Ctx.count = &tx;
    drv.setSendFn(Ctx.send);
    drv.onConnect(0);
    drv.feed("GrblHAL 1.1f\nok\n");
    drv.poll(0);
    tx = 0;
    drv.cmdSpindleCcw();
    try testing.expectEqual(@as(usize, 0), tx);
}

test "cnc: driver cmdRunMacro defaults to M5 when unset" {
    var drv = Driver.init(.{});
    const Ctx = struct {
        var line: []const u8 = "";
        fn send(data: []const u8) bool {
            line = data;
            return true;
        }
    };
    drv.setSendFn(Ctx.send);
    drv.onConnect(0);
    drv.feed("GrblHAL 1.1f\nok\n");
    drv.poll(0);
    drv.cmdRunMacro();
    try testing.expectEqualStrings("M5\n", Ctx.line);
}

test "cnc: session defaults after ready clears pending without deadlock" {
    var store = settings_store.Store.init(testing.allocator);
    defer store.deinit();
    var drv = Driver.init(.{ .store = &store });
    drv.setSendFn(test_util.noopSend());
    test_util.connectToReady(&drv, 0);
    try testing.expect(drv.apply_defaults_pending);
    drv.feed("ok\n");
    drv.poll(0);
    try test_util.expectReady(&drv);
    try testing.expect(!drv.apply_defaults_pending);
}

test "cnc: cmdZeroAxis sends G10 L20 when ready" {
    var drv = Driver.init(.{});
    var sent = std.ArrayListUnmanaged(u8).empty;
    defer sent.deinit(testing.allocator);
    drv.setSendFn(test_util.appendSend(&sent, testing.allocator));
    test_util.connectToReady(&drv, 0);
    drv.feed("ok\n");
    drv.poll(0);
    try test_util.expectReady(&drv);
    drv.feed("<Idle|MPos:1.0,2.0,3.0|WPos:1.0,2.0,3.0>\n");
    drv.poll(0);
    try testing.expectEqual(cnc_state.MachineState.idle, drv.status().state);
    sent.clearRetainingCapacity();
    drv.cmdZeroAxis(0);
    try testing.expectEqualStrings("G10 L20 P0 X0\n", sent.items);
    sent.clearRetainingCapacity();
    drv.cmdZeroAxis(1);
    try testing.expectEqualStrings("G10 L20 P0 Y0\n", sent.items);
    sent.clearRetainingCapacity();
    drv.cmdZeroAxis(2);
    try testing.expectEqualStrings("G10 L20 P0 Z0\n", sent.items);
}

test "cnc: cmdZeroAxis still sends under mpg_blocked" {
    var drv = Driver.init(.{});
    var sent = std.ArrayListUnmanaged(u8).empty;
    defer sent.deinit(testing.allocator);
    drv.setSendFn(test_util.appendSend(&sent, testing.allocator));
    test_util.connectToReady(&drv, 0);
    drv.feed("ok\n");
    drv.poll(0);
    try test_util.expectReady(&drv);
    drv.feed("<Idle|MPos:1.0,2.0,3.0|MPG:1>\n");
    drv.poll(0);
    try testing.expectEqual(
        @import("grblhal/session.zig").SessionState.mpg_blocked,
        drv.engine.session(),
    );
    try testing.expectEqual(cnc_state.MachineState.idle, drv.status().state);
    sent.clearRetainingCapacity();
    drv.cmdZeroAxis(0);
    try testing.expectEqualStrings("G10 L20 P0 X0\n", sent.items);
}

test "cnc: cmdZeroAxis gated when disconnected" {
    var drv = Driver.init(.{});
    var tx_len: usize = 0;
    drv.setSendFn(test_util.countSend(&tx_len));
    drv.cmdZeroAxis(0);
    try testing.expectEqual(@as(usize, 0), tx_len);
}

test "cnc: cmdHomeAxis sends per-axis $HX/$HY/$HZ" {
    var drv = Driver.init(.{});
    var sent = std.ArrayListUnmanaged(u8).empty;
    defer sent.deinit(testing.allocator);
    drv.setSendFn(test_util.appendSend(&sent, testing.allocator));
    test_util.connectToReady(&drv, 0);
    drv.feed("ok\n");
    drv.poll(0);
    try test_util.expectReady(&drv);
    drv.feed("<Idle|MPos:0,0,0>\n");
    drv.poll(0);
    sent.clearRetainingCapacity();
    drv.cmdHomeAxis(0);
    try testing.expectEqualStrings("$HX\n", sent.items);
    sent.clearRetainingCapacity();
    drv.cmdHomeAxis(1);
    try testing.expectEqualStrings("$HY\n", sent.items);
    sent.clearRetainingCapacity();
    drv.cmdHomeAxis(2);
    try testing.expectEqualStrings("$HZ\n", sent.items);
    sent.clearRetainingCapacity();
    drv.cmdHomeAxis(3);
    try testing.expectEqualStrings("$HA\n", sent.items);
    sent.clearRetainingCapacity();
    drv.cmdHomeAxis(4);
    try testing.expectEqualStrings("$HB\n", sent.items);
    sent.clearRetainingCapacity();
    drv.cmdHomeAxis(5);
    try testing.expectEqualStrings("$HC\n", sent.items);
    sent.clearRetainingCapacity();
    drv.cmdHome(0);
    try testing.expectEqualStrings("$H\n", sent.items);
}

test "cnc: cmdHomeAxis still sends under mpg_blocked" {
    var drv = Driver.init(.{});
    var sent = std.ArrayListUnmanaged(u8).empty;
    defer sent.deinit(testing.allocator);
    drv.setSendFn(test_util.appendSend(&sent, testing.allocator));
    test_util.connectToReady(&drv, 0);
    drv.feed("ok\n");
    drv.poll(0);
    drv.feed("<Idle|MPos:0,0,0|MPG:1>\n");
    drv.poll(0);
    try testing.expectEqual(
        @import("grblhal/session.zig").SessionState.mpg_blocked,
        drv.engine.session(),
    );
    sent.clearRetainingCapacity();
    drv.cmdHomeAxis(1);
    try testing.expectEqualStrings("$HY\n", sent.items);
}

test "cnc: classic_grbl per-axis home falls back to $H" {
    const cnc_config = @import("cnc_config.zig");
    var drv = Driver.init(.{});
    var sent = std.ArrayListUnmanaged(u8).empty;
    defer sent.deinit(testing.allocator);
    drv.setSendFn(test_util.appendSend(&sent, testing.allocator));
    // onConnect reloads protocol from NVS — set classic AFTER connect.
    test_util.connectToReady(&drv, 0);
    drv.feed("ok\n");
    drv.poll(0);
    drv.engine.setProtocol(cnc_config.Protocol.classic_grbl);
    drv.feed("<Idle|MPos:0,0,0>\n");
    drv.poll(0);
    sent.clearRetainingCapacity();
    drv.cmdHomeAxis(0);
    try testing.expectEqualStrings("$H\n", sent.items);
}

test "cnc: cmdHomeAxis gated when disconnected" {
    var drv = Driver.init(.{});
    var tx_len: usize = 0;
    drv.setSendFn(test_util.countSend(&tx_len));
    drv.cmdHomeAxis(0);
    try testing.expectEqual(@as(usize, 0), tx_len);
}

test "cnc: settings dump sends $$ when ready" {
    var drv = Driver.init(.{});
    var sent = std.ArrayListUnmanaged(u8).empty;
    defer sent.deinit(testing.allocator);
    drv.setSendFn(test_util.appendSend(&sent, testing.allocator));
    test_util.connectToReady(&drv, 0);
    drv.feed("ok\n");
    drv.poll(0);
    sent.clearRetainingCapacity();
    drv.cmdRequestSettingsDump();
    try testing.expectEqualStrings("$$\n", sent.items);
    try testing.expect(drv.settings_dump.active);
}

test "cnc: settings dump still sends under mpg_blocked" {
    var drv = Driver.init(.{});
    var sent = std.ArrayListUnmanaged(u8).empty;
    defer sent.deinit(testing.allocator);
    drv.setSendFn(test_util.appendSend(&sent, testing.allocator));
    test_util.connectToReady(&drv, 0);
    drv.feed("ok\n");
    drv.poll(0);
    drv.feed("<Idle|MPos:0,0,0|MPG:1>\n");
    drv.poll(0);
    sent.clearRetainingCapacity();
    drv.cmdRequestSettingsDump();
    try testing.expectEqualStrings("$$\n", sent.items);
}

test "cnc: settings dump fails closed when disconnected" {
    var drv = Driver.init(.{});
    var tx_len: usize = 0;
    drv.setSendFn(test_util.countSend(&tx_len));
    drv.cmdRequestSettingsDump();
    try testing.expectEqual(@as(usize, 0), tx_len);
    try testing.expect(drv.settingsDumpFailed());
}

test "cnc: masso implemented; dump via INI for linuxcnc; paste for masso/mach3" {
    const cnc_config = @import("cnc_config.zig");
    try testing.expect(cnc_config.protocolImplemented(.masso));
    try testing.expect(!cnc_config.supportsSettingsDump(.masso));
    try testing.expect(cnc_config.supportsEnvelopePaste(.masso));
    try testing.expect(cnc_config.supportsEnvelopePaste(.mach3_mach4));
    try testing.expectEqualStrings("Masso", cnc_config.protocolStr(.masso));
    try testing.expect(cnc_config.supportsSettingsDump(.grblhal));
    try testing.expect(cnc_config.supportsSettingsDump(.fluid_nc));
    try testing.expect(cnc_config.supportsSettingsDump(.linux_cnc));
}
