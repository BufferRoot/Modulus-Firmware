//! Device ExtEncoder I2C — `ext_encoder_shim.c` on Port A @ 0x59.

const c = @import("modulus_shims");

pub fn traceWheel(
    count: i32,
    delta: i32,
    mpg_active: bool,
    axis: u8,
    machine_state: u8,
    jog_steps: i32,
    jog_mm: f32,
    block_code: u8,
) void {
    c.modulus_ext_encoder_trace_wheel(count, delta, mpg_active, @intCast(axis), machine_state, jog_steps, jog_mm, block_code);
}

pub fn traceStatus(connected: bool, fw_version: u8) void {
    c.modulus_ext_encoder_trace_status(connected, fw_version);
}

pub fn hwInit() void {
    c.modulus_ext_encoder_hw_init();
}

pub fn hwDeinit() void {
    c.modulus_ext_encoder_hw_deinit();
}

pub fn maintain(connected: *bool, count: *i32, fw_version: *u8) bool {
    return c.modulus_ext_encoder_hw_maintain(connected, count, fw_version);
}

pub fn notifyExt5v(enabled: bool) void {
    c.modulus_ext_encoder_notify_ext5v(enabled);
}
