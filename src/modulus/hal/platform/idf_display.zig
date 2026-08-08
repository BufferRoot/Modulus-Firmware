//! Tab5 display BSP — bridge to `firmware/tab5/components/modulus_zig/display_shim.c`.

const c = @import("modulus_shims");

pub fn hwInit(stripe_lines: u32, flipped: bool, brightness_pct: u8) bool {
    return c.modulus_display_init(stripe_lines, flipped, brightness_pct);
}

pub fn setBrightness(percent: u8) void {
    c.modulus_display_set_brightness(percent);
}

pub fn backlightOff() void {
    c.modulus_display_backlight_off();
}

pub fn backlightOn() void {
    c.modulus_display_backlight_on();
}

pub fn lock() void {
    c.modulus_display_lock();
}

pub fn unlock() void {
    c.modulus_display_unlock();
}

pub fn setFlip(flipped: bool) void {
    c.modulus_display_set_flip(flipped);
}

pub fn setTimeouts(dim_sec: u16, sleep_sec: u16) void {
    c.modulus_display_set_timeouts(dim_sec, sleep_sec);
}

pub fn startActivityMonitor() void {
    c.modulus_display_start_activity_monitor();
}
