//! Device LVGL UI facade — manager uses this instead of `idf_ui.zig` directly.

const build_options = @import("build_options");

const backend = if (build_options.device_nvs)
    @import("idf_ui.zig")
else
    struct {
        pub const CncStatus = @import("modulus_shims").modulus_cnc_status_t;

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

test "abi: CncStatus size matches shim / ui_shim.h" {
    const c = @import("modulus_shims");
    try @import("std").testing.expectEqual(@sizeOf(c.modulus_cnc_status_t), @sizeOf(CncStatus));
}
