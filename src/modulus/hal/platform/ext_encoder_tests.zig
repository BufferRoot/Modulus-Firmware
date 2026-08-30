//! ExtEncoder integration tests.

const std = @import("std");
const driver = @import("../../cnc/driver.zig");
const settings_store = @import("../../core/settings_store.zig");
const settings_keys = @import("../../core/settings_keys.zig");
const i2c_coex = @import("i2c_coex.zig");
const ext_encoder = @import("ext_encoder.zig");
const poll_ops = @import("ext_encoder_poll_ops.zig");

test "hal: ext encoder step mode jogs and queues" {
    var store = settings_store.Store.init(std.testing.allocator);
    defer store.deinit();
    try store.setU8(settings_keys.cnc_encdiv, 2);
    try store.setU8(settings_keys.jog_coal_ms, 0);
    var coex: i2c_coex.I2cCoex = .{};
    coex.init();
    var drv = driver.Driver.init(.{ .store = &store });
    drv.setSendFn(struct {
        fn send(_: []const u8) bool {
            return true;
        }
    }.send);
    var enc: ext_encoder.ExtEncoder = .{ .coex = &coex };
    enc.init(&coex, &drv, &store);
    enc.reloadJogSettings();
    enc.connectMock();

    drv.onConnect(0);
    drv.feed("GrblHAL 1.1f\nok\n");
    var snap = drv.statusLocal();
    snap.mpg_active = true;
    snap.active_axis = .x;
    snap.step_size = .step_0_01;
    snap.state = .idle;
    snap.jog_mode = .step;

    enc.setCount(4);
    enc.poll(20);
    try std.testing.expect(enc.jog_active);
    try std.testing.expectEqual(@as(i32, 0), enc.pending_steps);
}

test "hal: ext encoder cancel on stop" {
    var store = settings_store.Store.init(std.testing.allocator);
    defer store.deinit();
    var coex: i2c_coex.I2cCoex = .{};
    var drv = driver.Driver.init(.{ .store = &store });
    var enc: ext_encoder.ExtEncoder = .{ .coex = &coex, .jog_active = true };
    enc.init(&coex, &drv, &store);
    enc.connectMock();
    enc.jog_active = true;
    enc.last_wheel_move_ms = 20;
    const snap = drv.statusLocal();

    poll_ops.releaseOnWheelStop(&enc, &drv, false, snap.*, 'X', @intFromEnum(snap.state), 40);
    try std.testing.expect(enc.jog_active);
    poll_ops.releaseOnWheelStop(&enc, &drv, false, snap.*, 'X', @intFromEnum(snap.state), 120);
    try std.testing.expect(!enc.jog_active);
}

test "hal: ext encoder stop discards stale negative step backlog" {
    var store = settings_store.Store.init(std.testing.allocator);
    defer store.deinit();
    var coex: i2c_coex.I2cCoex = .{};
    var drv = driver.Driver.init(.{ .store = &store });
    var enc: ext_encoder.ExtEncoder = .{ .coex = &coex };
    enc.init(&coex, &drv, &store);
    enc.connectMock();
    enc.jog_active = true;
    enc.pending_steps = -12;
    enc.pulse_remainder = -1;
    enc.coal_start_ms = 20;
    enc.last_wheel_move_ms = 20;
    const snap = drv.statusLocal();

    poll_ops.releaseOnWheelStop(&enc, &drv, false, snap.*, 'X', @intFromEnum(snap.state), 120);
    try std.testing.expect(!enc.jog_active);
    try std.testing.expectEqual(@as(i32, 0), enc.pending_steps);
    try std.testing.expectEqual(@as(i32, 0), enc.pulse_remainder);
    try std.testing.expectEqual(@as(u32, 0), enc.coal_start_ms);
}

test "hal: ext encoder cont mode ramp-down on stop" {
    var store = settings_store.Store.init(std.testing.allocator);
    defer store.deinit();
    try store.setU8(settings_keys.cnc_encdiv, 1);
    var coex: i2c_coex.I2cCoex = .{};
    coex.init();
    var drv = driver.Driver.init(.{ .store = &store });
    const Cap = struct {
        var last: u8 = 0;
        fn send(data: []const u8) bool {
            if (data.len > 0) last = data[data.len - 1];
            return true;
        }
    };
    drv.setSendFn(Cap.send);
    drv.onConnect(0);
    drv.feed("GrblHAL 1.1f\nok\n");
    var enc: ext_encoder.ExtEncoder = .{ .coex = &coex };
    enc.init(&coex, &drv, &store);
    enc.connectMock();
    var snap = drv.statusLocal();
    snap.mpg_active = true;
    snap.active_axis = .x;
    snap.step_size = .step_0_1;
    snap.state = .idle;
    snap.jog_mode = .cont;

    enc.setCount(3);
    enc.poll(20);
    try std.testing.expect(enc.jog_active);

    Cap.last = 0;
    poll_ops.releaseOnWheelStop(&enc, &drv, true, snap.*, 'X', @intFromEnum(snap.state), 40);
    try std.testing.expect(enc.jog_active);
    try std.testing.expectEqual(@as(u8, 0), Cap.last);

    poll_ops.releaseOnWheelStop(&enc, &drv, true, snap.*, 'X', @intFromEnum(snap.state), 120);
    try std.testing.expect(!enc.jog_active);
    try std.testing.expectEqual(@as(u8, 0x85), Cap.last);
}

test "hal: ext encoder uses custom cnc_incr distance" {
    var store = settings_store.Store.init(std.testing.allocator);
    defer store.deinit();
    try store.setU8(settings_keys.cnc_encdiv, 1);
    try store.setU8(settings_keys.jog_coal_ms, 0);
    try store.setStr(settings_keys.cnc_incr, "0.25,0.5,1.0,2.0");
    var coex: i2c_coex.I2cCoex = .{};
    coex.init();
    var drv = driver.Driver.init(.{ .store = &store });
    var last_line: []const u8 = "";
    const Cap = struct {
        var line: *[]const u8 = undefined;
        fn send(data: []const u8) bool {
            line.* = data;
            return true;
        }
    };
    Cap.line = &last_line;
    drv.setSendFn(Cap.send);
    drv.onConnect(0);
    drv.feed("GrblHAL 1.1f\nok\n");
    var enc: ext_encoder.ExtEncoder = .{ .coex = &coex };
    enc.init(&coex, &drv, &store);
    enc.connectMock();
    try std.testing.expectEqual(@as(f32, 0.25), enc.increments[0]);
    var snap = drv.statusLocal();
    snap.mpg_active = true;
    snap.active_axis = .x;
    snap.step_size = .step_0_001; // chip 0 → 0.25 mm from cnc_incr
    snap.state = .idle;
    snap.jog_mode = .step;
    enc.setCount(1);
    enc.poll(20);
    try std.testing.expect(std.mem.indexOf(u8, last_line, "X0.2500") != null or
        std.mem.indexOf(u8, last_line, "X0.25") != null);
}

test "hal: ext encoder velo ignores contpct base scale" {
    var store = settings_store.Store.init(std.testing.allocator);
    defer store.deinit();
    try store.setU8(settings_keys.cnc_encdiv, 1);
    try store.setU16(settings_keys.cnc_jogspd, 1000);
    try store.setU8(settings_keys.cnc_contpct, 200);
    var coex: i2c_coex.I2cCoex = .{};
    coex.init();
    var drv = driver.Driver.init(.{ .store = &store });
    drv.setSendFn(struct {
        fn send(_: []const u8) bool {
            return true;
        }
    }.send);
    drv.onConnect(0);
    drv.feed("GrblHAL 1.1f\nok\n");
    var enc: ext_encoder.ExtEncoder = .{ .coex = &coex };
    enc.init(&coex, &drv, &store);
    enc.connectMock();
    var snap = drv.statusLocal();
    snap.mpg_active = true;
    snap.active_axis = .y;
    snap.step_size = .step_1_0;
    snap.state = .idle;
    snap.jog_mode = .velo;
    enc.setCount(10);
    enc.poll(20);
    try std.testing.expect(enc.jog_active);
    // VELO base is jogspd (1000), not jogspd×30×2.0 — feed stays well below CONT would.
    try std.testing.expect(enc.cont_feed <= 10000.0);
    try std.testing.expect(enc.cont_feed >= 100.0);
}
