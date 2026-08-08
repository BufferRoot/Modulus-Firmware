//! ESP-IDF event queue — bridge to `firmware/tab5/components/modulus_zig/event_shim.c`.

const std = @import("std");
const c = @import("modulus_shims");

pub const max_event_data = 64;
pub const ShimMessage = c.modulus_event_msg_t;

pub fn initQueue() void {
    c.modulus_event_init();
}

pub fn publish(id: u16, data: []const u8) void {
    const copy_len = @min(data.len, max_event_data);
    const ptr: ?[*]const u8 = if (copy_len > 0) data.ptr else null;
    if (!c.modulus_event_publish(id, ptr, @intCast(copy_len))) {
        @branchHint(.cold);
        std.log.scoped(.event).warn("queue full, dropped id={d}", .{id});
    }
}

pub fn receiveBlocking(out: *ShimMessage) bool {
    return c.modulus_event_receive(out);
}
