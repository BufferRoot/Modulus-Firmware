//! GT911 touch — bridge to `touch_shim.c`.

const c = @import("modulus_shims");

pub fn hwInit() void {
    c.modulus_touch_init();
}
