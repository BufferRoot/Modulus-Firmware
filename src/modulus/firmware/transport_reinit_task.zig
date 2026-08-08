//! Core 0 transport reinit worker — SDIO/UART setup must not run on Core 1
//! `sys_task` (IDLE1 WDT when ESP-NOW connect blocks ~5 s without yield).

const std = @import("std");
const build_options = @import("build_options");
const dispatcher_mod = @import("../hal/transport/dispatcher.zig");

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

extern fn vTaskDelay(ticks: u32) void;

/// Core 1 `sys_task` skips `transport.poll()` while the worker runs.
pub var active: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

var pending: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var spawned: bool = false;
var transport_ptr: ?*dispatcher_mod.Dispatcher = null;

pub fn spawn(disp: *dispatcher_mod.Dispatcher) void {
    if (!build_options.device_nvs or spawned) return;
    transport_ptr = disp;
    const ok = xTaskCreatePinnedToCore(
        workerEntry,
        "xport_reinit",
        8192,
        null,
        8,
        null,
        0,
    );
    if (ok != 1) return;
    spawned = true;
}

pub fn request() void {
    if (!build_options.device_nvs) return;
    pending.store(true, .release);
}

fn workerEntry(_: ?*anyopaque) callconv(.c) void {
    while (true) {
        if (!pending.load(.acquire)) {
            // 20 ms idle poll — vTaskDelay(1) at 1000 Hz tick woke this pri-8
            // task 1000x/s for a user-initiated, latency-insensitive request.
            vTaskDelay(20);
            continue;
        }
        while (pending.swap(false, .acq_rel)) {
            const disp = transport_ptr orelse continue;
            active.store(true, .release);
            disp.reinit();
            active.store(false, .release);
        }
    }
}

test "firmware: transport reinit worker starts idle" {
    try std.testing.expect(!active.load(.acquire));
}
