//! PMS150G / deep sleep — bridge to `power_shim.c`.

const c = @import("modulus_shims");

pub fn hwInit() void {
    c.modulus_power_init();
}
