//! Serial HAL — RS-485 / USB UART. Host: mock channel; device: UART1 TX20/RX21/DE34.

const std = @import("std");
const build_options = @import("build_options");
const cnc_config = @import("../../cnc/cnc_config.zig");
const driver = @import("../../cnc/driver.zig");
const settings_keys = @import("../../core/settings_keys.zig");
const settings_store = @import("../../core/settings_store.zig");
const link = @import("link.zig");
const deferred_connect = @import("../../cnc/deferred_connect.zig");
const monotonic_ms = @import("../../core/monotonic_ms.zig");
const io_mod = if (build_options.device_nvs)
    @import("idf_serial.zig")
else
    @import("mock_channel.zig");

pub const rs485_tx_pin: u8 = 20;
pub const rs485_rx_pin: u8 = 21;
pub const rs485_de_pin: u8 = 34;

pub const baud_table = [_]u32{ 9600, 19200, 38400, 57600, 115200, 250000, 1000000 };

pub const Port = enum(u8) {
    rs485 = 0,
    serial_usb,
};

pub const Config = struct {
    baud_rate: u32 = 115200,
    data_bits: u8 = 8,
    parity: u8 = 0,
    stop_bits: u8 = 1,
    flow_ctrl: u8 = 0,
    dir_ctrl: u8 = 0,
};

pub const Stats = struct {
    tx_bytes: u32 = 0,
    rx_bytes: u32 = 0,
    rx_errors: u32 = 0,
    overflows: u32 = 0,
};

const ConnectCtx = struct {
    var drv: ?*driver.Driver = null;

    fn onConnect() void {
        if (drv) |d| d.onConnect(monotonic_ms.nowMs());
    }
};

pub const Serial = struct {
    io: io_mod.Io = .{},
    initialized: bool = false,
    port_open: bool = false,
    active_port: Port = .rs485,
    stats: Stats = .{},

    pub fn loadConfig(store: *const settings_store.Store, port: Port) Config {
        var cfg: Config = .{};
        if (port == .rs485) {
            const baud_idx = store.getU8(settings_keys.r4_baud, 4);
            cfg.baud_rate = if (baud_idx < baud_table.len) baud_table[baud_idx] else 115200;
            cfg.data_bits = if (store.getU8(settings_keys.r4_dbit, 1) == 0) 7 else 8;
            cfg.parity = store.getU8(settings_keys.r4_par, 0);
            cfg.stop_bits = if (store.getU8(settings_keys.r4_sbit, 0) == 0) 1 else 2;
            cfg.dir_ctrl = store.getU8(settings_keys.r4_dir, 0);
        } else {
            const baud_idx = store.getU8(settings_keys.ser_baud, 4);
            cfg.baud_rate = if (baud_idx < baud_table.len) baud_table[baud_idx] else 115200;
            cfg.data_bits = if (store.getU8(settings_keys.ser_dbit, 1) == 0) 7 else 8;
            cfg.parity = store.getU8(settings_keys.ser_par, 0);
            cfg.stop_bits = if (store.getU8(settings_keys.ser_sbit, 0) == 0) 1 else 2;
            cfg.flow_ctrl = store.getU8(settings_keys.ser_flow, 0);
        }
        return cfg;
    }

    pub fn init(self: *Serial, drv: *driver.Driver, store: *settings_store.Store, conn: cnc_config.Connection) void {
        if (self.initialized) return;
        const port: Port = if (conn == .rs485) .rs485 else .serial_usb;
        const cfg = loadConfig(store, port);
        if (!self.open(port, cfg)) return;
        drv.setSendFn(link.sendFn);
        link.setActive(self, sendImpl);
        if (store.getBool(settings_keys.cnc_autocon, false)) {
            ConnectCtx.drv = drv;
            deferred_connect.schedule(ConnectCtx.onConnect);
        }
        self.initialized = true;
    }

    pub fn deinit(self: *Serial, drv: *driver.Driver) void {
        if (!self.initialized) return;
        deferred_connect.cancel();
        drv.onDisconnect();
        drv.setSendFn(null);
        link.clearActive(self);
        self.close();
        self.initialized = false;
    }

    pub fn poll(self: *Serial, drv: *driver.Driver) void {
        self.io.pollRx(drv);
    }

    pub fn open(self: *Serial, port: Port, cfg: Config) bool {
        if (self.port_open) self.close();
        if (build_options.device_nvs) {
            if (!self.io.open(@intFromEnum(port), cfg.baud_rate, cfg.data_bits, cfg.parity, cfg.stop_bits)) {
                return false;
            }
        }
        self.active_port = port;
        self.stats = .{};
        self.port_open = true;
        return true;
    }

    pub fn close(self: *Serial) void {
        self.port_open = false;
        self.io.reset();
    }

    /// Host integration tests only.
    pub fn testInjectRx(self: *Serial, data: []const u8) bool {
        return self.io.injectRx(data);
    }

    pub fn testDrainTx(self: *Serial) []const u8 {
        return self.io.drainTx();
    }

    fn sendImpl(ctx: *anyopaque, data: []const u8) bool {
        const self: *Serial = @ptrCast(@alignCast(ctx));
        if (!self.port_open) return false;
        const ok = self.io.send(data);
        if (ok) self.stats.tx_bytes += @intCast(data.len);
        return ok;
    }
};

test "hal: serial loadConfig rs485 default baud" {
    var store = settings_store.Store.init(std.testing.allocator);
    defer store.deinit();
    const cfg = Serial.loadConfig(&store, .rs485);
    try std.testing.expectEqual(@as(u32, 115200), cfg.baud_rate);
}

test "hal: serial auto connect defers on device only" {
    var store = settings_store.Store.init(std.testing.allocator);
    defer store.deinit();
    try store.setBool(settings_keys.cnc_autocon, true);
    var drv = driver.Driver.init(.{ .store = &store });
    var serial: Serial = .{};
    serial.init(&drv, &store, .rs485);
    defer serial.deinit(&drv);
    if (build_options.device_nvs) {
        try std.testing.expectEqual(@import("../../cnc/grblhal/session.zig").SessionState.disconnected, drv.engine.session());
    } else {
        try std.testing.expect(drv.engine.session() != .disconnected);
    }
}
