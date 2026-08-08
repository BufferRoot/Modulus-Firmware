//! Core 0 FreeRTOS `evt_dispatch` — drains cross-core event queue to subscribers (device only).

const std = @import("std");
const boot = @import("../core/boot.zig");
const event_bus = @import("../core/event_bus.zig");
const idf_event = @import("../core/idf_event.zig");

const policy = boot.EventDispatchPolicy;
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

var bus_ptr: ?*event_bus.EventBus = null;
var spawned: bool = false;

pub fn configure(bus: *event_bus.EventBus) void {
    bus_ptr = bus;
}

pub fn isSpawned() bool {
    return spawned;
}

pub fn spawn() void {
    if (spawned or bus_ptr == null) return;

    idf_event.initQueue();

    const ok = xTaskCreatePinnedToCore(
        dispatchTaskEntry,
        policy.name,
        policy.stack_words,
        null,
        policy.priority,
        null,
        @intCast(policy.core_affinity),
    );
    if (ok != 1) {
        std.log.scoped(.firmware).err("evt_dispatch spawn failed ({d})", .{ok});
        return;
    }

    spawned = true;
}

fn dispatchTaskEntry(_: ?*anyopaque) callconv(.c) void {
    const bus = bus_ptr orelse return;
    var shim: idf_event.ShimMessage = undefined;

    while (true) {
        if (!idf_event.receiveBlocking(&shim)) continue;
        const data_len = @min(shim.data_len, idf_event.max_event_data);
        bus.dispatchMessage(.{
            .id = shim.id,
            .data = shim.data,
            .data_len = data_len,
        });
    }
}

test "firmware: event dispatch policy matches C++ event_bus.cpp" {
    try std.testing.expectEqual(@as(u8, 0), policy.core_affinity);
    try std.testing.expectEqual(@as(u16, 12288), policy.stack_words);
    try std.testing.expectEqual(@as(u8, 10), policy.priority);
    try std.testing.expectEqualStrings("evt_dispatch", policy.name);
}
