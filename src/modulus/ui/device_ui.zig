//! Device LVGL UI facade — manager uses this instead of `idf_ui.zig` directly.

const build_options = @import("build_options");

const backend = if (build_options.device_nvs)
    @import("idf_ui.zig")
else
    struct {
        pub const CncStatus = extern struct {
            state: u8 = 0,
            connected: u8 = 0,
            session: u8 = 0,
            mpg_active: u8 = 0,
            jog_mode: u8 = 0,
            step_size: u8 = 0,
            wpos_x: f32 = 0,
            wpos_y: f32 = 0,
            wpos_z: f32 = 0,
            wpos_a: f32 = 0,
            wpos_b: f32 = 0,
            wpos_c: f32 = 0,
            feed_rate: f32 = 0,
            feed_ovr: u8 = 0,
            spindle_ovr: u8 = 0,
            wcs: u8 = 0,
            tool_number: u8 = 0,
            active_axis: u8 = 0,
            units_mm: u8 = 0,
            spindle_rpm: u32 = 0,
            mpos_x: f32 = 0,
            mpos_y: f32 = 0,
            mpos_z: f32 = 0,
            mpos_a: f32 = 0,
            mpos_b: f32 = 0,
            mpos_c: f32 = 0,
            homing_block: u8 = 0,
            accessories: u8 = 0,
            sd_percent: f32 = 0,
            line_number: u32 = 0,
            sd_streaming: u8 = 0,
            alarm_code: u8 = 0,
            sd_file: [32]u8 = .{0} ** 32,
        };

        pub fn hwInit() void {}
        pub fn showBootScreen() void {}
        pub fn armBootTransition() void {}
        pub fn showDashboard() void {}
        pub fn showPinLock() void {}
        pub fn hidePinLock() void {}
        pub fn onDeepSleep() void {}
        pub fn onWake() void {}
        pub fn onCncStatusEvent() void {}
        pub fn showSettings() void {}
        pub fn hideSettings() void {}
        pub fn settingsOpen() bool {
            return false;
        }
        pub fn showQuickSettings() void {}
        pub fn showPowerMenu() void {}
    };

pub const CncStatus = backend.CncStatus;

pub fn hwInit() void {
    backend.hwInit();
}

pub fn showBootScreen() void {
    backend.showBootScreen();
}

pub fn armBootTransition() void {
    backend.armBootTransition();
}

pub fn showDashboard() void {
    backend.showDashboard();
}

pub fn showPinLock() void {
    backend.showPinLock();
}

pub fn hidePinLock() void {
    backend.hidePinLock();
}

pub fn onDeepSleep() void {
    backend.onDeepSleep();
}

pub fn onWake() void {
    backend.onWake();
}

pub fn onCncStatusEvent() void {
    backend.onCncStatusEvent();
}

pub fn showSettings() void {
    backend.showSettings();
}

pub fn hideSettings() void {
    backend.hideSettings();
}

pub fn settingsOpen() bool {
    return backend.settingsOpen();
}

pub fn showQuickSettings() void {
    backend.showQuickSettings();
}

pub fn showPowerMenu() void {
    backend.showPowerMenu();
}

test "abi: CncStatus size matches shim stub (ui_shim.h layout)" {
    const c = @import("modulus_shims");
    try @import("std").testing.expectEqual(@sizeOf(c.modulus_cnc_status_t), @sizeOf(CncStatus));
}
