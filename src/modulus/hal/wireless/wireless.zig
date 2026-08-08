//! Wireless HAL — ESP-Hosted SDIO to C6; host mock backend.

const std = @import("std");
const build_options = @import("build_options");
const settings_keys = @import("../../core/settings_keys.zig");
const settings_store = @import("../../core/settings_store.zig");
const mock_hosted = @import("mock_hosted.zig");
const sdio_pins = @import("sdio_pins.zig");

const io_mod = if (build_options.device_nvs)
    @import("idf_wireless.zig")
else
    struct {
        pub const Io = struct {
            pub fn init() bool {
                return true;
            }
            pub fn isReady() bool {
                return true;
            }
            pub fn restoreFromNvs() void {}
            pub fn postRestoreSettle() void {}
            pub fn wifiEnable() bool {
                return true;
            }
            pub fn wifiDisable() void {}
            pub fn wifiConnected() bool {
                return false;
            }
            pub fn espnowEnable() bool {
                return true;
            }
            pub fn espnowDisable() void {}
        };
    };

pub const RadioState = enum(u8) {
    off = 0,
    init,
    ready,
    fault,
};

pub const RecvCb = *const fn (src_mac: *const [6]u8, data: []const u8) void;

pub const Wireless = struct {
    store: ?*settings_store.Store = null,
    hosted: mock_hosted.MockHosted = .{},
    external_antenna: bool = false,
    wifi_state: RadioState = .off,
    espnow_state: RadioState = .off,
    recv_cb: ?RecvCb = null,

    pub fn init(self: *Wireless) bool {
        if (build_options.device_nvs) {
            const ok = io_mod.Io.init();
            if (ok) self.wifi_state = .ready;
            self.hosted.initialized = ok;
            return ok;
        }
        const ok = self.hosted.init();
        if (ok) self.wifi_state = .ready;
        return ok;
    }

    pub fn isInitialized(self: *const Wireless) bool {
        return self.hosted.initialized;
    }

    pub fn prepareForSleep(self: *Wireless) void {
        if (build_options.device_nvs) {
            io_mod.Io.prepareForSleep();
            return;
        }
        self.hosted.prepareForSleep();
    }

    pub fn deinit(self: *Wireless) void {
        if (build_options.device_nvs) {
            io_mod.Io.deinit();
            self.wifi_state = .off;
            self.espnow_state = .off;
            self.hosted.initialized = false;
            return;
        }
        self.hosted.deinit();
        self.wifi_state = .off;
        self.espnow_state = .off;
    }

    pub fn wakeCoprocessor(self: *Wireless) bool {
        if (build_options.device_nvs) {
            const ok = io_mod.Io.wakeCoprocessor();
            if (ok) {
                self.hosted.initialized = true;
                self.wifi_state = .ready;
            }
            return ok;
        }
        return self.hosted.wakeCoprocessor();
    }

    pub fn restoreSettings(self: *Wireless, store: *settings_store.Store) void {
        self.store = store;
        self.external_antenna = store.getBool(settings_keys.ant_ext, false);
        if (build_options.device_nvs) {
            io_mod.Io.restoreFromNvs();
            return;
        }
        if (store.getBool(settings_keys.wifi, false)) {
            if (!self.wifiEnable()) std.log.warn("wifi restore failed", .{});
        }
        if (store.getBool(settings_keys.espnow, false)) {
            if (!self.espnowEnable()) std.log.warn("espnow restore failed", .{});
        }
    }

    pub fn postRestoreSettle(self: *Wireless) void {
        if (build_options.device_nvs) io_mod.Io.postRestoreSettle();
        _ = self;
    }

    pub fn setAntenna(self: *Wireless, external: bool) void {
        self.external_antenna = external;
        if (self.store) |s| s.persistBool(settings_keys.ant_ext, external);
    }

    pub fn isExternalAntenna(self: *const Wireless) bool {
        return self.external_antenna;
    }

    pub fn wifiEnable(self: *Wireless) bool {
        if (!self.hosted.initialized) return false;
        if (build_options.device_nvs and !io_mod.Io.wifiEnable()) return false;
        self.wifi_state = .ready;
        return true;
    }

    pub fn wifiDisable(self: *Wireless) void {
        if (build_options.device_nvs) io_mod.Io.wifiDisable();
        self.wifi_state = .off;
    }

    pub fn wifiIsConnected(self: *const Wireless) bool {
        if (build_options.device_nvs) return io_mod.Io.wifiConnected();
        return self.wifi_state == .ready;
    }

    pub fn espnowEnable(self: *Wireless) bool {
        if (!self.hosted.initialized) return false;
        if (build_options.device_nvs and !io_mod.Io.espnowEnable()) return false;
        self.espnow_state = .ready;
        return true;
    }

    pub fn espnowDisable(self: *Wireless) void {
        if (build_options.device_nvs) io_mod.Io.espnowDisable();
        self.espnow_state = .off;
    }

    pub fn espnowSetRecvCb(self: *Wireless, cb: ?RecvCb) void {
        self.recv_cb = cb;
    }

    pub fn espnowDeliver(self: *Wireless, src: *const [6]u8, data: []const u8) void {
        if (self.recv_cb) |cb| cb(src, data);
        self.hosted.tx_frames += 1;
    }

    pub const pins = sdio_pins;
};

test "hal: wireless restore nvs flags" {
    var store = settings_store.Store.init(std.testing.allocator);
    defer store.deinit();
    try store.setBool(settings_keys.wifi, true);
    try store.setBool(settings_keys.espnow, true);
    var wl: Wireless = .{};
    try std.testing.expect(wl.init());
    wl.restoreSettings(&store);
    try std.testing.expect(wl.wifiIsConnected());
    try std.testing.expectEqual(RadioState.ready, wl.espnow_state);
}

test "hal: wireless sleep before c6 power off" {
    var wl: Wireless = .{};
    try std.testing.expect(wl.init());
    wl.prepareForSleep();
    try std.testing.expect(wl.hosted.prepared_for_sleep);
    wl.deinit();
    wl.hosted.setC6Power(false);
    try std.testing.expect(!wl.hosted.c6_power_on);
}
