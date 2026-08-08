//! Display HAL — 1280×720 MIPI-DSI; host stub; device uses Tab5 BSP (`display_shim.c`).

const std = @import("std");
const build_options = @import("build_options");
const settings_keys = @import("../../core/settings_keys.zig");
const settings_store = @import("../../core/settings_store.zig");
const idf_display_mod = if (build_options.device_nvs)
    @import("idf_display.zig")
else
    struct {};

pub const screen_width: u16 = 1280;
pub const screen_height: u16 = 720;
/// 120-line stripe (more flushes, ~337 KiB double buf) — internal DMA failed at boot; PSRAM + DMA.
pub const draw_stripe_lines: u32 = 120;

pub const Display = struct {
    store: ?*settings_store.Store = null,
    brightness: u8 = 100,
    saved_brightness: u8 = 100,
    flipped: bool = false,
    dim_timeout_sec: u16 = 0,
    sleep_timeout_sec: u16 = 0,
    sleeping: bool = false,
    dimmed: bool = false,
    hw_ready: bool = false,
    activity_monitor_started: bool = false,
    wake_hold_ms: u32 = 0,
    last_activity_ms: u32 = 0,
    lock_state: std.atomic.Mutex = .unlocked,

    pub fn init(self: *Display, store: *settings_store.Store) void {
        self.store = store;
        self.brightness = store.getU8(settings_keys.bright, 100);
        self.saved_brightness = self.brightness;
        self.dim_timeout_sec = store.getU16(settings_keys.dim_to, 0);
        self.sleep_timeout_sec = store.getU16(settings_keys.scr_to, 0);
        self.flipped = store.getBool(settings_keys.flip, false);
        if (build_options.device_nvs) {
            self.hw_ready = idf_display_mod.hwInit(draw_stripe_lines, self.flipped, self.brightness);
            if (self.hw_ready) {
                idf_display_mod.setTimeouts(self.dim_timeout_sec, self.sleep_timeout_sec);
            }
        }
    }

    pub fn setBrightness(self: *Display, pct: u8) void {
        if (pct > 0) self.saved_brightness = pct;
        self.brightness = pct;
        self.sleeping = pct == 0;
        if (build_options.device_nvs and self.hw_ready) {
            if (pct == 0) {
                idf_display_mod.backlightOff();
            } else {
                idf_display_mod.setBrightness(pct);
            }
        }
        if (self.store) |s| s.persistU8(settings_keys.bright, pct);
    }

    pub fn getBrightness(self: *const Display) u8 {
        return self.brightness;
    }

    pub fn lock(self: *Display) void {
        if (build_options.device_nvs and self.hw_ready) {
            idf_display_mod.lock();
            return;
        }
        while (!self.lock_state.tryLock()) std.atomic.spinLoopHint();
    }

    pub fn unlock(self: *Display) void {
        if (build_options.device_nvs and self.hw_ready) {
            idf_display_mod.unlock();
            if (!self.activity_monitor_started) {
                idf_display_mod.startActivityMonitor();
                self.activity_monitor_started = true;
            }
            return;
        }
        self.lock_state.unlock();
    }

    pub fn setRotationFlip(self: *Display, flipped: bool) void {
        self.flipped = flipped;
        if (build_options.device_nvs and self.hw_ready) {
            idf_display_mod.setFlip(flipped);
        }
        if (self.store) |s| s.persistBool(settings_keys.flip, flipped);
    }

    pub fn getRotationFlip(self: *const Display) bool {
        return self.flipped;
    }

    pub fn setDimTimeout(self: *Display, sec: u16) void {
        self.dim_timeout_sec = sec;
        if (build_options.device_nvs and self.hw_ready) {
            idf_display_mod.setTimeouts(self.dim_timeout_sec, self.sleep_timeout_sec);
        }
        if (self.store) |s| s.persistU16(settings_keys.dim_to, sec);
    }

    pub fn setSleepTimeout(self: *Display, sec: u16) void {
        self.sleep_timeout_sec = sec;
        if (build_options.device_nvs and self.hw_ready) {
            idf_display_mod.setTimeouts(self.dim_timeout_sec, self.sleep_timeout_sec);
        }
        if (self.store) |s| s.persistU16(settings_keys.scr_to, sec);
    }

    pub fn isSleeping(self: *const Display) bool {
        return self.sleeping;
    }

    pub fn isDimmed(self: *const Display) bool {
        return self.dimmed;
    }

    pub fn isWakeHoldActive(self: *const Display, now_ms: u32) bool {
        return now_ms -% self.last_activity_ms < self.wake_hold_ms;
    }

    pub fn wakeFromIdle(self: *Display, now_ms: u32) void {
        self.last_activity_ms = now_ms;
        self.wake_hold_ms = 3000;
        const was_dimmed = self.dimmed;
        self.dimmed = false;
        if (self.sleeping) {
            if (build_options.device_nvs and self.hw_ready) {
                idf_display_mod.backlightOn();
            }
            self.setBrightness(self.saved_brightness);
        } else if (was_dimmed and build_options.device_nvs and self.hw_ready) {
            idf_display_mod.setBrightness(self.saved_brightness);
        }
    }

    pub fn tickPolicy(self: *Display, now_ms: u32) void {
        if (self.isWakeHoldActive(now_ms)) return;
        const idle_sec = (now_ms -% self.last_activity_ms) / 1000;
        if (self.sleep_timeout_sec > 0 and idle_sec >= self.sleep_timeout_sec) {
            self.setBrightness(0);
            return;
        }
        if (self.dim_timeout_sec > 0 and idle_sec >= self.dim_timeout_sec and !self.dimmed) {
            self.dimmed = true;
            if (build_options.device_nvs and self.hw_ready) {
                idf_display_mod.setBrightness(5);
            }
        }
    }
};

/// Module-level BSP lock for UI paths without a `Display` instance (LVGL overlays).
pub fn lockHw() void {
    if (build_options.device_nvs) idf_display_mod.lock();
}

pub fn unlockHw() void {
    if (build_options.device_nvs) idf_display_mod.unlock();
}

pub fn applyTimeouts(dim_sec: u16, sleep_sec: u16) void {
    if (build_options.device_nvs) idf_display_mod.setTimeouts(dim_sec, sleep_sec);
}

test "hal: display brightness from nvs" {
    var store = settings_store.Store.init(std.testing.allocator);
    defer store.deinit();
    try store.setU8(settings_keys.bright, 80);
    var disp: Display = .{};
    disp.init(&store);
    try std.testing.expectEqual(@as(u8, 80), disp.getBrightness());
}
