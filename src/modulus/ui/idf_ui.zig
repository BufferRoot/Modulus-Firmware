//! LVGL UI bridge — `firmware/tab5/components/modulus_zig/ui_*.c`.

const c = @import("modulus_shims");

pub const CncStatus = c.modulus_cnc_status_t;

pub fn hwInit() void {
    c.modulus_ui_init();
}

pub fn showBootScreen() void {
    c.modulus_ui_show_boot_screen();
}

pub fn armBootTransition() void {
    c.modulus_ui_arm_boot_transition();
}

pub fn showDashboard() void {
    c.modulus_ui_show_dashboard();
}

pub fn showPinLock() void {
    c.modulus_ui_show_pin_lock();
}

pub fn hidePinLock() void {
    c.modulus_ui_hide_pin_lock();
}

pub fn onDeepSleep() void {
    c.modulus_ui_on_deep_sleep();
}

pub fn onWake() void {
    c.modulus_ui_on_wake();
}

pub fn onCncStatusEvent() void {
    c.modulus_ui_on_cnc_status_event();
}

pub fn showSettings() void {
    c.modulus_ui_show_settings();
}

pub fn hideSettings() void {
    c.modulus_ui_hide_settings();
}

pub fn settingsOpen() bool {
    return c.modulus_ui_settings_open();
}

pub fn showQuickSettings() void {
    c.modulus_ui_show_quick_settings();
}

pub fn showPowerMenu() void {
    c.modulus_ui_show_power_menu();
}
