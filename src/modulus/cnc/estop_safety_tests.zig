//! P3+/perf: E-stop path must never wait on UI frame or PSRAM alloc.
//! Host mirrors of `estop_gpio_shim.c` + `driver_commands.cmdReset` contracts.

const std = @import("std");
const testing = std.testing;
const boot = @import("../core/boot.zig");
const driver_mod = @import("driver.zig");
const test_util = @import("driver_test_util.zig");
const gh_session = @import("grblhal/session.zig");

const Driver = driver_mod.Driver;

test "safety: estop priority above zig_ui and sys_task" {
    try testing.expect(boot.EstopGpioPolicy.priority > boot.ZigUiTaskPolicy.priority);
    try testing.expect(boot.EstopGpioPolicy.priority > boot.SystemTaskPolicy.priority);
    try testing.expectEqual(@as(u8, 1), boot.EstopGpioPolicy.core_affinity);
    try testing.expectEqual(@as(u8, 0), boot.ZigUiTaskPolicy.core_affinity);
}

test "safety: soft reset while ready sends 0x18 without UI" {
    var drv = Driver.init(.{});
    var last: u8 = 0;
    drv.setSendFn(test_util.firstByteSend(&last));
    test_util.connectToReady(&drv, 0);
    drv.feed("ok\n");
    drv.poll(0);
    try test_util.expectReady(&drv);
    drv.cmdReset();
    try testing.expectEqual(@as(u8, 0x18), last);
}

test "safety: soft reset while disconnected is local snapshot only" {
    var drv = Driver.init(.{});
    var sends: usize = 0;
    drv.setSendFn(test_util.countSend(&sends));
    drv.cmdReset();
    try testing.expectEqual(@as(usize, 0), sends);
    try testing.expectEqual(gh_session.SessionState.disconnected, drv.engine.session());
}

test "safety: soak reset unlock cycle x16" {
    var drv = Driver.init(.{});
    var sent = std.ArrayListUnmanaged(u8).empty;
    defer sent.deinit(testing.allocator);
    drv.setSendFn(test_util.appendSend(&sent, testing.allocator));
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        sent.clearRetainingCapacity();
        test_util.connectToReady(&drv, @intCast(i));
        drv.feed("ok\n");
        drv.poll(@intCast(i));
        try test_util.expectReady(&drv);
        drv.cmdReset();
        drv.onDisconnect();
        try testing.expectEqual(gh_session.SessionState.disconnected, drv.engine.session());
    }
}
