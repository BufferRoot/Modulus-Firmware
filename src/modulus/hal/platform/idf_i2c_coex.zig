//! I2C bus mutex — bridge to `i2c_coex_shim.c`.

const c = @import("modulus_shims");

pub fn init() void {
    c.modulus_i2c_coex_init();
}

pub fn lock(timeout_ms: u32) bool {
    return c.modulus_i2c_coex_lock(timeout_ms);
}

pub fn unlock() void {
    c.modulus_i2c_coex_unlock();
}
