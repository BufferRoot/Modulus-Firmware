//! Deferred CNC connect — 11 s delay on device (matches C++ `hal_serial.cpp` RS485 boot probe).

const std = @import("std");
const build_options = @import("build_options");
const freertos_ticks = @import("../firmware/freertos_ticks.zig");

pub const defer_ms: u32 = 11_000;

const TaskFn = *const fn (?*anyopaque) callconv(.c) void;

extern fn xTaskCreatePinnedToCore(
    task: TaskFn,
    name: [*:0]const u8,
    stack_depth: u32,
    param: ?*anyopaque,
    priority: u32,
    handle: *?*anyopaque,
    core_id: i32,
) i32;

extern fn vTaskDelay(ticks: u32) void;
extern fn vTaskDelete(task: ?*anyopaque) void;

var handler: ?*const fn () void = null;
var defer_epoch: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
var epoch_at_spawn: u32 = 0;
var task_handle: ?*anyopaque = null;

/// Drop a pending deferred connect (transport deinit / reinit). No-op on host.
pub fn cancel() void {
    if (!build_options.device_nvs) return;
    _ = defer_epoch.fetchAdd(1, .acq_rel);
    handler = null;
    if (task_handle) |h| {
        vTaskDelete(h);
        task_handle = null;
    }
}

pub fn schedule(connect: *const fn () void) void {
    if (!build_options.device_nvs) {
        connect();
        return;
    }

    cancel();
    handler = connect;
    epoch_at_spawn = defer_epoch.load(.monotonic);

    var created_handle: ?*anyopaque = null;
    const ok = xTaskCreatePinnedToCore(
        taskEntry,
        "cnc_defer",
        3072,
        null,
        3,
        &created_handle,
        1,
    );
    if (ok != 1) {
        handler = null;
        std.log.scoped(.cnc).warn("cnc_defer spawn failed ({d})", .{ok});
        return;
    }
    task_handle = created_handle;
}

fn taskEntry(_: ?*anyopaque) callconv(.c) void {
    vTaskDelay(freertos_ticks.msToTicks(defer_ms));
    task_handle = null;
    if (defer_epoch.load(.acquire) != epoch_at_spawn) {
        vTaskDelete(null);
        return;
    }
    if (handler) |h| {
        handler = null;
        h();
    }
    vTaskDelete(null);
}

test "cnc: deferred connect delay matches C++" {
    try std.testing.expectEqual(@as(u32, 11_000), defer_ms);
}

test "cnc: deferred connect runs immediately on host" {
    var called = false;
    const Ctx = struct {
        var hit: *bool = undefined;
        fn go() void {
            hit.* = true;
        }
    };
    Ctx.hit = &called;
    schedule(Ctx.go);
    try std.testing.expect(called);
    cancel();
}
