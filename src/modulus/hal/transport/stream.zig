//! Stream transports — WebSocket, Telnet, BLE, I2C, CAN, ESP-NOW.

const build_options = @import("build_options");
const cnc_config = @import("../../cnc/cnc_config.zig");
const driver = @import("../../cnc/driver.zig");
const settings_keys = @import("../../core/settings_keys.zig");
const settings_store = @import("../../core/settings_store.zig");
const link = @import("link.zig");
const mock_channel = @import("mock_channel.zig");
const idf_stream = @import("idf_stream.zig");
const monotonic_ms = @import("../../core/monotonic_ms.zig");

pub fn StreamTransport(comptime conn: cnc_config.Connection, comptime label: []const u8) type {
    _ = label;
    const Io = if (build_options.device_nvs)
        idf_stream.channelIo(conn)
    else
        mock_channel.Channel;

    return struct {
        channel: mock_channel.Channel = .{},
        io: Io = .{},
        initialized: bool = false,
        connection: cnc_config.Connection = conn,

        pub fn init(self: *@This(), drv: *driver.Driver, store: *settings_store.Store) void {
            if (self.initialized) return;
            // Wire the engine BEFORE opening: synchronous shims (ESP-NOW, I2C,
            // CAN) fire modulus_zig_transport_on_connect() inside open(); with
            // the old order setSendFn() then replaced the Engine and erased the
            // connected session — transport up, session stuck .disconnected.
            drv.setSendFn(link.sendFn);
            link.setActive(self, sendImpl);
            if (build_options.device_nvs) {
                if (!self.io.open(store)) {
                    drv.setSendFn(null);
                    link.clearActive(self);
                    return;
                }
            }
            if (store.getBool(settings_keys.cnc_autocon, false) and !build_options.device_nvs) {
                drv.onConnect(monotonic_ms.nowMs());
            }
            self.initialized = true;
        }

        pub fn deinit(self: *@This(), drv: *driver.Driver) void {
            if (!self.initialized) return;
            drv.onDisconnect();
            drv.setSendFn(null);
            link.clearActive(self);
            if (build_options.device_nvs) {
                self.io.reset();
            } else {
                self.channel.reset();
            }
            self.initialized = false;
        }

        /// C shim already opened ESP-NOW (`modulus_espnow_transport_start`); wire
        /// Zig send path without a second C open (avoids IDLE1 WDT on full reinit).
        pub fn attachCOpen(self: *@This(), drv: *driver.Driver) void {
            drv.setSendFn(link.sendFn);
            link.setActive(self, sendImpl);
            if (build_options.device_nvs) {
                self.io.open_ok = true;
            }
            self.initialized = true;
        }

        pub fn poll(self: *@This(), drv: *driver.Driver) void {
            if (build_options.device_nvs) {
                self.io.pollRx(drv);
            } else {
                self.channel.pollRx(drv);
            }
        }

        fn sendImpl(ctx: *anyopaque, data: []const u8) bool {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            if (build_options.device_nvs) {
                return self.io.send(data);
            }
            return self.channel.send(data);
        }
    };
}

pub const WebSocket = StreamTransport(.websocket, "WebSocket");
pub const Telnet = StreamTransport(.telnet, "Telnet");
pub const Ble = StreamTransport(.ble_hid, "BLE HID");
pub const I2c = StreamTransport(.i2c, "I2C");
pub const CanBus = StreamTransport(.can_bus, "CAN Bus");
pub const EspNow = StreamTransport(.esp_now, "ESP-NOW");

test "hal: stream autoconnect keeps session after setSendFn" {
    const std = @import("std");
    if (build_options.device_nvs) return;

    var store = settings_store.Store.init(std.testing.allocator);
    defer store.deinit();
    try store.setBool(settings_keys.cnc_autocon, true);

    var drv = driver.Driver.init(.{ .store = &store });
    var ws = WebSocket{};
    ws.init(&drv, &store);
    defer ws.deinit(&drv);
    try std.testing.expect(drv.engine.session() != .disconnected);
}
