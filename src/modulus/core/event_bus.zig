//! Async event bus — queue depth 16, payload max 64 bytes.
//! **Host-only** ring buffer + `dispatchOne` / `dispatchAll`. Device publishes via
//! `idf_event.zig` FreeRTOS queue + Core 0 `evt_dispatch` task.

const std = @import("std");
const build_options = @import("build_options");
const fixed_ring = @import("fixed_ring.zig");
const system_events = @import("system_events.zig");
const idf_event_mod = if (build_options.device_nvs)
    @import("idf_event.zig")
else
    struct {};

pub const EventId = system_events.EventId;
pub const max_event_data = 64;
pub const queue_len = 16;

pub const Callback = *const fn (event_id: EventId, data: []const u8) void;

/// Fixed subscriber capacity — C++ reference registers <10; no heap, no realloc,
/// so `evt_dispatch` (spawned before boot subscriptions) can never iterate a
/// reallocated/freed array.
pub const max_subscriptions = 16;

pub const Message = struct {
    id: EventId,
    data: [max_event_data]u8 = undefined,
    data_len: usize = 0,
};

const Subscription = struct {
    event_id: EventId,
    callback: Callback,
};

pub const EventBus = struct {
    subs_buf: [max_subscriptions]Subscription = undefined,
    /// Published with `.release` on subscribe, read with `.acquire` in dispatch —
    /// readers always see fully written entries `[0..len)`.
    subs_len: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    host_queue: fixed_ring.FixedSlotQueue(Message, queue_len) = .{},

    pub fn init() EventBus {
        return .{};
    }

    pub fn deinit(self: *EventBus) void {
        self.subs_len.store(0, .release);
    }

    /// INVARIANT — single writer. All `subscribe` calls must come from one
    /// thread (boot, Core 0). The release/acquire pairing only guarantees the
    /// dispatch reader sees a *completed* entry before the bumped length; it
    /// does NOT serialize two concurrent writers. A `subscribe` from another
    /// core (e.g. Core 1 `sys_task`) would race the `subs_buf[len]` write and
    /// silently lose a subscription. Keep all subscriptions on the boot path.
    pub fn subscribe(self: *EventBus, event_id: EventId, callback: Callback) !void {
        const len = self.subs_len.load(.monotonic);
        if (len >= max_subscriptions) return error.TooManySubscribers;
        self.subs_buf[len] = .{ .event_id = event_id, .callback = callback };
        self.subs_len.store(len + 1, .release);
    }

    /// Enqueues; drops when full (matches C++ publish on timeout). Logs on host drop.
    pub fn publish(self: *EventBus, event_id: EventId, data: []const u8) void {
        if (build_options.device_nvs) {
            idf_event_mod.publish(event_id, data);
            return;
        }
        var msg: Message = .{ .id = event_id };
        const copy_len = @min(data.len, max_event_data);
        if (copy_len > 0) {
            @memcpy(msg.data[0..copy_len], data[0..copy_len]);
            msg.data_len = copy_len;
        }

        if (!self.host_queue.push(msg)) {
            @branchHint(.cold);
            std.log.scoped(.event).warn("host queue full, dropped id={d}", .{event_id});
        }
    }

    /// Dispatches one message to matching subscribers (host ring buffer only).
    pub fn dispatchOne(self: *EventBus) bool {
        if (build_options.device_nvs) return false;
        const msg = self.host_queue.pop() orelse {
            @branchHint(.unlikely);
            return false;
        };

        self.dispatchMessage(msg);
        return true;
    }

    /// Shared subscriber dispatch — host tests and Core 0 `evt_dispatch` task.
    pub fn dispatchMessage(self: *EventBus, msg: Message) void {
        const data_len = @min(msg.data_len, max_event_data);
        const subs_len = self.subs_len.load(.acquire);
        for (self.subs_buf[0..subs_len]) |sub| {
            if (sub.event_id != msg.id) continue;
            sub.callback(msg.id, msg.data[0..data_len]);
        }
    }

    pub fn dispatchAll(self: *EventBus) void {
        while (self.dispatchOne()) {}
    }

    pub fn pendingCount(self: *const EventBus) usize {
        return self.host_queue.len();
    }
};

// ── tests ──

test "core: pub/sub delivers payload" {
    var bus = EventBus.init();
    defer bus.deinit();

    const Ctx = struct {
        var last_id: EventId = 0;
        var last_payload: [max_event_data]u8 = undefined;
        var last_len: usize = 0;

        fn onStatus(id: EventId, data: []const u8) void {
            last_id = id;
            last_len = data.len;
            @memcpy(last_payload[0..data.len], data);
        }
    };

    try bus.subscribe(system_events.EVT_CNC_STATUS_UPDATE, Ctx.onStatus);
    bus.publish(system_events.EVT_CNC_STATUS_UPDATE, "Run");
    try std.testing.expectEqual(@as(usize, 1), bus.pendingCount());
    try std.testing.expect(bus.dispatchOne());
    try std.testing.expectEqual(system_events.EVT_CNC_STATUS_UPDATE, Ctx.last_id);
    try std.testing.expectEqualStrings("Run", Ctx.last_payload[0..Ctx.last_len]);
}

test "core: ignores unsubscribed events" {
    var bus = EventBus.init();
    defer bus.deinit();

    const Ctx = struct {
        var hits: usize = 0;
        fn onAlarm(id: EventId, data: []const u8) void {
            _ = id;
            _ = data;
            hits += 1;
        }
    };

    try bus.subscribe(system_events.EVT_CNC_ALARM, Ctx.onAlarm);
    bus.publish(system_events.EVT_CNC_STATUS_UPDATE, "");
    try std.testing.expect(bus.dispatchOne());
    try std.testing.expectEqual(@as(usize, 0), Ctx.hits);
}

test "core: truncates payload to 64 bytes" {
    var bus = EventBus.init();
    defer bus.deinit();

    const Ctx = struct {
        var len: usize = 0;
        fn onMsg(id: EventId, data: []const u8) void {
            _ = id;
            len = data.len;
        }
    };

    const big = "x" ** 80;
    try bus.subscribe(system_events.EVT_CNC_MESSAGE, Ctx.onMsg);
    bus.publish(system_events.EVT_CNC_MESSAGE, big);
    _ = bus.dispatchOne();
    try std.testing.expectEqual(max_event_data, Ctx.len);
}

test "core: drops when queue full" {
    var bus = EventBus.init();
    defer bus.deinit();

    var i: usize = 0;
    while (i < queue_len) : (i += 1) {
        bus.publish(system_events.EVT_CNC_STATUS_UPDATE, &.{});
    }
    bus.publish(system_events.EVT_CNC_STATUS_UPDATE, &.{});
    try std.testing.expectEqual(queue_len, bus.pendingCount());
}

test "core: multiple subscribers same event" {
    var bus = EventBus.init();
    defer bus.deinit();

    const Ctx = struct {
        var a_hits: usize = 0;
        var b_hits: usize = 0;
        fn onA(id: EventId, data: []const u8) void {
            _ = id;
            _ = data;
            a_hits += 1;
        }
        fn onB(id: EventId, data: []const u8) void {
            _ = id;
            _ = data;
            b_hits += 1;
        }
    };

    try bus.subscribe(system_events.EVT_CNC_CONNECTED, Ctx.onA);
    try bus.subscribe(system_events.EVT_CNC_CONNECTED, Ctx.onB);
    bus.publish(system_events.EVT_CNC_CONNECTED, "");
    bus.dispatchAll();
    try std.testing.expectEqual(@as(usize, 1), Ctx.a_hits);
    try std.testing.expectEqual(@as(usize, 1), Ctx.b_hits);
}
