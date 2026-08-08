//! UI string catalog — bridge to `i18n_shim.c`.

const c = @import("modulus_shims");

pub fn hwInit() void {
    c.modulus_i18n_init();
}
