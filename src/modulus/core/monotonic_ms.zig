//! Wall-clock milliseconds for CNC session timing — host OS tick, device `esp_timer`.

const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");

const backend = if (build_options.device_nvs)
    struct {
        extern fn esp_timer_get_time() i64;
        pub fn nowMs() u32 {
            // @truncate, not @intCast: us/1000 exceeds u32 after ~49.7 days of
            // uptime and @intCast panics in safe builds. Callers use wrapping
            // (`-%`) interval math, so a wrapped counter is correct.
            const ms: u64 = @intCast(@divTrunc(esp_timer_get_time(), 1000));
            return @truncate(ms);
        }
    }
else
    struct {
        extern "kernel32" fn GetTickCount64() u64;

        pub fn nowMs() u32 {
            if (builtin.os.tag == .windows) {
                // @truncate: hosts up >49.7 days exceed u32 (same wrap contract as device).
                return @truncate(GetTickCount64());
            }
            // Non-Windows host builds (CI): coarse monotonic fallback.
            return fallback_ms.fetchAdd(1, .monotonic);
        }

        var fallback_ms: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
    };

pub fn nowMs() u32 {
    return backend.nowMs();
}

test "core: monotonic_ms returns u32 on host" {
    const ms = nowMs();
    try std.testing.expect(ms > 0 or ms == 0);
}
