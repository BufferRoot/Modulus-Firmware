//! I2C bus co-existence mutex — Port A ExtEncoder vs internal BSP bus.

const std = @import("std");
const build_options = @import("build_options");
const idf_coex = if (build_options.device_nvs)
    @import("idf_i2c_coex.zig")
else
    struct {};

pub const I2cCoex = struct {
    mutex: std.atomic.Mutex = .unlocked,
    initialized: bool = false,

    pub fn init(self: *I2cCoex) void {
        if (build_options.device_nvs) {
            idf_coex.init();
        }
        self.initialized = true;
    }

    pub fn lock(self: *I2cCoex) void {
        if (build_options.device_nvs) {
            while (!idf_coex.lock(5000)) std.atomic.spinLoopHint();
            return;
        }
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
    }

    pub fn tryLock(self: *I2cCoex) bool {
        if (build_options.device_nvs) return idf_coex.lock(0);
        return self.mutex.tryLock();
    }

    pub fn tryLockMs(self: *I2cCoex, timeout_ms: u32) bool {
        if (build_options.device_nvs) return idf_coex.lock(timeout_ms);
        return self.mutex.tryLock();
    }

    pub fn unlock(self: *I2cCoex) void {
        if (build_options.device_nvs) {
            idf_coex.unlock();
            return;
        }
        self.mutex.unlock();
    }
};

test "hal: i2c coex lock roundtrip" {
    var coex: I2cCoex = .{};
    coex.init();
    try std.testing.expect(coex.tryLock());
    coex.unlock();
    coex.lock();
    coex.unlock();
}
