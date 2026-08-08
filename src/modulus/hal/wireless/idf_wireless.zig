//! ESP-Hosted wireless — bridge to `wireless_shim.c`.

const c = @import("modulus_shims");

pub const Io = struct {
    pub fn init() bool {
        return c.modulus_wireless_init();
    }

    pub fn isReady() bool {
        return c.modulus_wireless_ready();
    }

    pub fn restoreFromNvs() void {
        c.modulus_wireless_restore_settings();
    }

    pub fn postRestoreSettle() void {
        c.modulus_wireless_post_restore_settle();
    }

    pub fn prepareForSleep() void {
        c.modulus_wireless_prepare_for_sleep();
    }

    pub fn deinit() void {
        c.modulus_wireless_deinit();
    }

    pub fn wakeCoprocessor() bool {
        return c.modulus_wireless_wake_coprocessor();
    }

    pub fn wifiEnable() bool {
        return c.modulus_wireless_wifi_enable();
    }

    pub fn wifiDisable() void {
        c.modulus_wireless_wifi_disable();
    }

    pub fn wifiConnected() bool {
        return c.modulus_wireless_wifi_is_connected();
    }

    pub fn espnowEnable() bool {
        return c.modulus_wireless_espnow_enable();
    }

    pub fn espnowDisable() void {
        c.modulus_wireless_espnow_disable();
    }
};
