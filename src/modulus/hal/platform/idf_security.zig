//! PIN lock NVS — bridge to `security_shim.c`.

const c = @import("modulus_shims");

pub fn init() void {
    c.modulus_security_init();
}

pub fn hasPin() bool {
    return c.modulus_security_has_pin();
}

pub fn isLocked() bool {
    return c.modulus_security_is_locked();
}

pub fn lock() void {
    c.modulus_security_lock();
}

pub fn unlock() void {
    c.modulus_security_unlock();
}

pub fn verifyPin(pin: [*:0]const u8) bool {
    return c.modulus_security_verify_pin(pin);
}
