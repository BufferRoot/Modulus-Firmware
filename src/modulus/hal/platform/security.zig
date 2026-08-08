//! PIN lock HAL — `security_shim.c` on device.

const build_options = @import("build_options");
const idf_security_mod = if (build_options.device_nvs)
    @import("idf_security.zig")
else
    struct {
        pub fn init() void {}
        pub fn hasPin() bool {
            return false;
        }
        pub fn isLocked() bool {
            return false;
        }
        pub fn lock() void {}
        pub fn unlock() void {}
        pub fn verifyPin(_: []const u8) bool {
            return false;
        }
    };

var active: ?*Security = null;

pub const Security = struct {
    initialized: bool = false,

    pub fn init(self: *Security) void {
        idf_security_mod.init();
        self.initialized = true;
        active = self;
    }

    pub fn hasPin(self: *const Security) bool {
        _ = self;
        return idf_security_mod.hasPin();
    }

    pub fn isLocked(self: *const Security) bool {
        _ = self;
        return idf_security_mod.isLocked();
    }

    pub fn lock(self: *Security) void {
        _ = self;
        idf_security_mod.lock();
    }

    pub fn unlock(self: *Security) void {
        _ = self;
        idf_security_mod.unlock();
    }

    pub fn verifyPin(self: *const Security, pin: []const u8) bool {
        _ = self;
        return idf_security_mod.verifyPin(pin);
    }
};

/// PIN lock state for UI event handlers without a `Runtime` pointer.
pub fn isLockedActive() bool {
    if (active) |s| return s.isLocked();
    return false;
}
