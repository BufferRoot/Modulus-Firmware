//! ES7210 mic path — bridge to `dsp_shim.c`.

const c = @import("modulus_shims");

pub fn hwInit() void {
    c.modulus_dsp_init();
}

pub fn hwProcess() void {
    c.modulus_dsp_process();
}

pub fn isReady() bool {
    return c.modulus_dsp_is_ready();
}
