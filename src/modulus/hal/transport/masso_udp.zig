//! Masso Link UDP stream — device C shim; host uses mock_channel.

const std = @import("std");
const build_options = @import("build_options");
const driver = @import("../../cnc/driver.zig");
const settings_keys = @import("../../core/settings_keys.zig");
const settings_store = @import("../../core/settings_store.zig");
const link = @import("link.zig");
const mock_channel = @import("mock_channel.zig");
const monotonic_ms = @import("../../core/monotonic_ms.zig");

const Io = if (build_options.device_nvs) struct {
    open_ok: bool = false,

    pub fn reset(self: *@This()) void {
        const c = @import("modulus_shims");
        c.modulus_masso_udp_stop();
        self.open_ok = false;
    }

    pub fn open(self: *@This(), store: *const settings_store.Store) bool {
        const c = @import("modulus_shims");
        var host_buf: [64]u8 = undefined;
        const def = "192.168.1.100";
        const host: [:0]u8 = blk: {
            if (store.getStr(settings_keys.masso_ip, &host_buf)) {
                const z = std.mem.indexOfScalar(u8, &host_buf, 0) orelse host_buf.len;
                break :blk host_buf[0..z :0];
            }
            @memcpy(host_buf[0..def.len], def);
            host_buf[def.len] = 0;
            break :blk host_buf[0..def.len :0];
        };
        const tx = store.getU16(settings_keys.masso_tx, 11000);
        const rx = store.getU16(settings_keys.masso_rx, 65535);
        const ok = c.modulus_masso_udp_start(host.ptr, tx, rx);
        self.open_ok = ok;
        return ok;
    }

    pub fn send(self: *@This(), data: []const u8) bool {
        const c = @import("modulus_shims");
        if (!self.open_ok) return false;
        return c.modulus_masso_udp_send(data.ptr, data.len);
    }

    pub fn pollRx(_: *@This(), _: anytype) void {}
} else struct {
    open_ok: bool = false,

    pub fn reset(_: *@This()) void {}
    pub fn open(_: *@This(), _: *const settings_store.Store) bool {
        return true;
    }
    pub fn send(_: *@This(), _: []const u8) bool {
        return false;
    }
    pub fn pollRx(_: *@This(), _: anytype) void {}
};

pub const MassoUdp = struct {
    channel: mock_channel.Channel = .{},
    io: Io = .{},
    initialized: bool = false,

    pub fn init(self: *@This(), drv: *driver.Driver, store: *settings_store.Store) void {
        if (self.initialized) return;
        drv.setSendFn(link.sendFn);
        link.setActive(self, sendImpl);
        if (build_options.device_nvs) {
            if (!self.io.open(store)) {
                drv.setSendFn(null);
                link.clearActive(self);
                return;
            }
        } else if (store.getBool(settings_keys.cnc_autocon, false)) {
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
