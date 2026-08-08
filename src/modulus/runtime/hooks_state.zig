//! Active `Runtime` pointer for boot/power/settings hook thunks.

const Runtime = @import("runtime.zig").Runtime;

var active: ?*Runtime = null;
var spawn_handler: ?*const fn () bool = null;

pub fn bind(rt: *Runtime) void {
    active = rt;
}

pub fn setSpawnHandler(handler: *const fn () bool) void {
    spawn_handler = handler;
}

/// Returns true if Core 1 `sys_task` is running. No handler → host path (true).
pub fn invokeSpawnHandler() bool {
    if (spawn_handler) |spawn| return spawn();
    return true;
}

pub fn rtPtr() ?*Runtime {
    return active;
}
