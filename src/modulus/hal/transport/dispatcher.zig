//! Transport dispatcher — single active `cnc_conn` transport, wired to CNC driver.

const std = @import("std");
const testing = std.testing;
const cnc_config = @import("../../cnc/cnc_config.zig");
const driver = @import("../../cnc/driver.zig");
const settings_keys = @import("../../core/settings_keys.zig");
const settings_store = @import("../../core/settings_store.zig");
const serial = @import("serial.zig");
const stream = @import("stream.zig");
const masso_udp = @import("masso_udp.zig");
const build_options = @import("build_options");
const idf_serial_mod = if (build_options.device_nvs)
    @import("idf_serial.zig")
else
    struct {};

/// Register UART RX callback before transport open (device only).
pub fn registerDeviceRxHandler() void {
    if (build_options.device_nvs) idf_serial_mod.registerRxHandler();
}

pub const none_active: u8 = 0xFF;
/// Sentinel: Masso Link UDP is active (not a Connection enum value).
pub const masso_active: u8 = 0xFE;

pub const Dispatcher = struct {
    store: *settings_store.Store,
    drv: *driver.Driver,
    active_conn: u8 = none_active,
    serial_hal: serial.Serial = .{},
    websocket: stream.WebSocket = .{},
    telnet: stream.Telnet = .{},
    ble: stream.Ble = .{},
    i2c: stream.I2c = .{},
    canbus: stream.CanBus = .{},
    espnow: stream.EspNow = .{},
    masso: masso_udp.MassoUdp = .{},

    pub fn init(self: *Dispatcher) void {
        const conn = self.store.getU8(settings_keys.cnc_conn, cnc_config.k_default_cnc_conn);
        self.start(conn);
    }

    pub fn reinit(self: *Dispatcher) void {
        self.stop();
        const conn = self.store.getU8(settings_keys.cnc_conn, cnc_config.k_default_cnc_conn);
        self.start(conn);
    }

    /// After UI light-start opens the C ESP-NOW transport, attach Zig `sendFn`
    /// without `transport_start` / full SDIO reinit.
    pub fn attachEspNowCOpen(self: *Dispatcher) void {
        if (self.active_conn != @intFromEnum(cnc_config.Connection.esp_now)) {
            if (self.active_conn != none_active) {
                const prev: cnc_config.Connection = @enumFromInt(self.active_conn);
                switch (prev) {
                    inline else => |conn| stopConn(self, conn),
                }
            }
            self.active_conn = none_active;
        }
        self.espnow.attachCOpen(self.drv);
        self.active_conn = @intFromEnum(cnc_config.Connection.esp_now);
    }

    pub fn deinit(self: *Dispatcher) void {
        self.stop();
    }

    pub fn activeConnection(self: *const Dispatcher) u8 {
        return self.active_conn;
    }

    pub fn poll(self: *Dispatcher) void {
        if (self.active_conn == none_active) return;
        if (self.active_conn == masso_active) {
            self.masso.poll(self.drv);
            return;
        }
        const c: cnc_config.Connection = @enumFromInt(self.active_conn);
        switch (c) {
            inline else => |conn| pollConn(self, conn),
        }
    }

    fn pollConn(self: *Dispatcher, comptime conn: cnc_config.Connection) void {
        switch (conn) {
            .serial_usb, .rs485 => self.serial_hal.poll(self.drv),
            .websocket => self.websocket.poll(self.drv),
            .telnet => self.telnet.poll(self.drv),
            .ble_hid => self.ble.poll(self.drv),
            .i2c => self.i2c.poll(self.drv),
            .can_bus => self.canbus.poll(self.drv),
            .esp_now => self.espnow.poll(self.drv),
            else => {},
        }
    }

    fn stop(self: *Dispatcher) void {
        if (self.active_conn == none_active) return;
        if (self.active_conn == masso_active) {
            self.masso.deinit(self.drv);
            self.active_conn = none_active;
            return;
        }
        const c: cnc_config.Connection = @enumFromInt(self.active_conn);
        switch (c) {
            inline else => |conn| stopConn(self, conn),
        }
        self.active_conn = none_active;
    }

    fn stopConn(self: *Dispatcher, comptime conn: cnc_config.Connection) void {
        switch (conn) {
            .serial_usb, .rs485 => self.serial_hal.deinit(self.drv),
            .websocket => self.websocket.deinit(self.drv),
            .telnet => self.telnet.deinit(self.drv),
            .ble_hid => self.ble.deinit(self.drv),
            .i2c => self.i2c.deinit(self.drv),
            .can_bus => self.canbus.deinit(self.drv),
            .esp_now => self.espnow.deinit(self.drv),
            else => {},
        }
    }

    fn start(self: *Dispatcher, conn: u8) void {
        const proto_idx = self.store.getU8(settings_keys.cnc_proto, cnc_config.k_default_cnc_proto);
        if (proto_idx == @intFromEnum(cnc_config.Protocol.masso)) {
            self.masso.init(self.drv, self.store);
            if (!self.masso.initialized) return;
            self.active_conn = masso_active;
            return;
        }
        if (conn >= @intFromEnum(cnc_config.Connection._count)) return;
        const c: cnc_config.Connection = @enumFromInt(conn);
        switch (c) {
            .esp_now => {
                self.espnow.init(self.drv, self.store);
                if (!self.espnow.initialized) return;
            },
            .websocket => {
                self.websocket.init(self.drv, self.store);
                if (!self.websocket.initialized) return;
            },
            .telnet => {
                self.telnet.init(self.drv, self.store);
                if (!self.telnet.initialized) return;
            },
            .serial_usb, .rs485 => {
                self.serial_hal.init(self.drv, self.store, c);
                if (!self.serial_hal.initialized) return;
            },
            .ble_hid => {
                self.ble.init(self.drv, self.store);
                if (!self.ble.initialized) return;
            },
            .i2c => {
                self.i2c.init(self.drv, self.store);
                if (!self.i2c.initialized) return;
            },
            .can_bus => {
                self.canbus.init(self.drv, self.store);
                if (!self.canbus.initialized) return;
            },
            .usb_hid, .usb_gamepad => return,
            else => return,
        }
        self.active_conn = conn;
    }
};

test "hal: dispatcher default rs485" {
    var store = settings_store.Store.init(testing.allocator);
    defer store.deinit();
    var drv = driver.Driver.init(.{ .store = &store });
    var disp: Dispatcher = .{ .store = &store, .drv = &drv };
    disp.init();
    try testing.expectEqual(@as(u8, @intFromEnum(cnc_config.Connection.rs485)), disp.activeConnection());
}

test "hal: dispatcher reinit switches transport" {
    var store = settings_store.Store.init(testing.allocator);
    defer store.deinit();
    try store.setU8(settings_keys.cnc_conn, @intFromEnum(cnc_config.Connection.websocket));
    var drv = driver.Driver.init(.{ .store = &store });
    var disp: Dispatcher = .{ .store = &store, .drv = &drv };
    disp.init();
    try testing.expectEqual(@as(u8, @intFromEnum(cnc_config.Connection.websocket)), disp.activeConnection());
    try store.setU8(settings_keys.cnc_conn, @intFromEnum(cnc_config.Connection.telnet));
    disp.reinit();
    try testing.expectEqual(@as(u8, @intFromEnum(cnc_config.Connection.telnet)), disp.activeConnection());
}

test "hal: usb_hid not dispatched" {
    var store = settings_store.Store.init(testing.allocator);
    defer store.deinit();
    try store.setU8(settings_keys.cnc_conn, @intFromEnum(cnc_config.Connection.usb_hid));
    var drv = driver.Driver.init(.{ .store = &store });
    var disp: Dispatcher = .{ .store = &store, .drv = &drv };
    disp.init();
    try testing.expectEqual(none_active, disp.activeConnection());
}

test "hal: dispatcher attach espnow after rs485" {
    var store = settings_store.Store.init(testing.allocator);
    defer store.deinit();
    var drv = driver.Driver.init(.{ .store = &store });
    var disp: Dispatcher = .{ .store = &store, .drv = &drv };
    disp.init();
    try testing.expectEqual(@as(u8, @intFromEnum(cnc_config.Connection.rs485)), disp.activeConnection());

    try store.setU8(settings_keys.cnc_conn, @intFromEnum(cnc_config.Connection.esp_now));
    disp.attachEspNowCOpen();
    try testing.expectEqual(@as(u8, @intFromEnum(cnc_config.Connection.esp_now)), disp.activeConnection());
    try testing.expect(disp.espnow.initialized);
    _ = drv.engine.send("?");
}

test "hal: integration serial tx and rx" {
    var store = settings_store.Store.init(testing.allocator);
    defer store.deinit();
    try store.setU8(settings_keys.cnc_conn, @intFromEnum(cnc_config.Connection.rs485));
    try store.setBool(settings_keys.cnc_autocon, true);
    var drv = driver.Driver.init(.{ .store = &store });
    var disp: Dispatcher = .{ .store = &store, .drv = &drv };
    disp.init();

    try testing.expect(disp.serial_hal.testInjectRx("GrblHAL 1.1f\n"));
    disp.poll();
    try testing.expect(disp.serial_hal.testInjectRx("ok\n"));
    disp.poll();
    try testing.expectEqual(@import("../../cnc/grblhal/session.zig").SessionState.ready, drv.engine.session());
    _ = disp.serial_hal.testDrainTx(); // handshake $I+

    drv.cmdFeedHold();
    const tx = disp.serial_hal.testDrainTx();
    try testing.expectEqual(@as(usize, 1), tx.len);
    try testing.expectEqual(@as(u8, 0x82), tx[0]);
}
