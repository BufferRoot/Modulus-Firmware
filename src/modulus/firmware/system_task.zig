//! Core 1 FreeRTOS `sys_task` — ~100 Hz CNC/transport/encoder poll (device only).

const std = @import("std");
const boot = @import("../core/boot.zig");
const freertos_ticks = @import("freertos_ticks.zig");
const policy = boot.SystemTaskPolicy;

const TaskFn = *const fn (?*anyopaque) callconv(.c) void;

extern fn xTaskCreatePinnedToCore(
    task: TaskFn,
    name: [*:0]const u8,
    stack_depth: u32,
    param: ?*anyopaque,
    priority: u32,
    handle: ?*anyopaque,
    core_id: i32,
) i32;

extern fn xTaskDelayUntil(prev_wake: *u32, increment: u32) i32;
extern fn xTaskGetTickCount() u32;
extern fn esp_timer_get_time() i64;

var tick_fn: ?*const fn (u32) void = null;
var spawned: bool = false;

pub fn configure(tick: *const fn (u32) void) void {
    tick_fn = tick;
}

pub fn isSpawned() bool {
    return spawned;
}

pub fn spawn() bool {
    if (spawned) return true;
    if (tick_fn == null) return false;

    const ok = xTaskCreatePinnedToCore(
        systemTaskEntry,
        policy.name,
        policy.stack_words,
        null,
        policy.priority,
        null,
        @intCast(policy.core_affinity),
    );
    if (ok != 1) {
        std.log.scoped(.firmware).err("sys_task spawn failed ({d})", .{ok});
        return false;
    }

    spawned = true;
    return true;
}

fn systemTaskEntry(_: ?*anyopaque) callconv(.c) void {
    const tick = tick_fn orelse return;
    const period_ticks = freertos_ticks.msToTicks(policy.period_ms);
    var last_wake: u32 = xTaskGetTickCount();

    while (true) {
        // @truncate, not @intCast: us/1000 > u32 max after ~49.7 days uptime
        // (@intCast panics in safe builds). Tick consumers use `-%` intervals.
        const ms: u64 = @intCast(@divTrunc(esp_timer_get_time(), 1000));
        tick(@truncate(ms));
        // Drift-free 100 Hz: vTaskDelay(period) made the period `10 ms + tick
        // work`, slowing CNC poll/jog cadence under load.
        _ = xTaskDelayUntil(&last_wake, period_ticks);
    }
}

test "firmware: msToTicks at 1000 Hz" {
    try std.testing.expectEqual(@as(u32, 10), freertos_ticks.msToTicks(10));
}

test "firmware: system task policy matches C++ modulus.cpp" {
    try std.testing.expectEqual(@as(u8, 1), policy.core_affinity);
    try std.testing.expectEqual(@as(u16, 8192), policy.stack_words);
    try std.testing.expectEqual(@as(u8, 5), policy.priority);
    try std.testing.expectEqual(@as(u16, 10), policy.period_ms);
    try std.testing.expectEqualStrings("sys_task", policy.name);
}
