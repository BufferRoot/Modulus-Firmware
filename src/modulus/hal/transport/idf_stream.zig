//! Device stream transport backends — bridge to `firmware/tab5` C shims.

const std = @import("std");
const c = @import("modulus_shims");
const cnc_config = @import("../../cnc/cnc_config.zig");
const settings_keys = @import("../../core/settings_keys.zig");
const settings_store = @import("../../core/settings_store.zig");
const espnow_config = @import("espnow_config.zig");

fn cstrFromStore(store: *const settings_store.Store, key: []const u8, def: []const u8, buf: []u8) [:0]u8 {
    if (store.getStr(key, buf)) {
        return buf[0 .. std.mem.indexOfScalar(u8, buf, 0) orelse buf.len :0];
    }
    @memcpy(buf[0..def.len], def);
    buf[def.len] = 0;
    return buf[0..def.len :0];
}

pub fn channelIo(comptime conn: cnc_config.Connection) type {
    return struct {
        open_ok: bool = false,

        pub fn reset(self: *@This()) void {
            switch (conn) {
                .websocket => c.modulus_ws_stop(),
                .telnet => c.modulus_telnet_stop(),
                .i2c => c.modulus_i2c_transport_stop(),
                .can_bus => c.modulus_canbus_stop(),
                .esp_now => c.modulus_espnow_transport_stop(),
                .ble_hid => c.modulus_ble_transport_stop(),
                else => {},
            }
            self.open_ok = false;
        }

        pub fn open(self: *@This(), store: *const settings_store.Store) bool {
            var host_buf: [64]u8 = undefined;
            var path_buf: [32]u8 = undefined;
            var mac_buf: [20]u8 = undefined;
            var name_buf: [32]u8 = undefined;

            const ok = switch (conn) {
                .websocket => blk: {
                    const host = cstrFromStore(store, settings_keys.ws_host, "192.168.1.100", &host_buf);
                    const path = cstrFromStore(store, settings_keys.ws_path, "/", &path_buf);
                    const port = store.getU16(settings_keys.ws_port, 81);
                    const tls = store.getU8(settings_keys.ws_tls, 0) != 0;
                    break :blk c.modulus_ws_start(host.ptr, port, path.ptr, tls);
                },
                .telnet => blk: {
                    const host = cstrFromStore(store, settings_keys.tn_host, "192.168.1.100", &host_buf);
                    // Proto-aware default: UI shows 5007/7878 but unset NVS used to open port 23.
                    const proto_idx = store.getU8(settings_keys.cnc_proto, cnc_config.k_default_cnc_proto);
                    const def_port: u16 = if (proto_idx < @intFromEnum(cnc_config.Protocol._count))
                        switch (@as(cnc_config.Protocol, @enumFromInt(proto_idx))) {
                            .linux_cnc => 5007,
                            .mach3_mach4 => 7878,
                            else => 23,
                        }
                    else
                        23;
                    const port = store.getU16(settings_keys.tn_port, def_port);
                    break :blk c.modulus_telnet_start(host.ptr, port);
                },
                .i2c => blk: {
                    const addr = store.getU8(settings_keys.i2c_addr, 0x50);
                    const spd = store.getU8(settings_keys.i2c_spd, 1);
                    break :blk c.modulus_i2c_transport_start(addr, spd);
                },
                .can_bus => blk: {
                    const brate = store.getU8(settings_keys.can_brate, 2);
                    const nid = store.getU8(settings_keys.can_nid, 1);
                    const mode = store.getU8(settings_keys.can_mode, 0);
                    break :blk c.modulus_canbus_start(brate, nid, mode);
                },
                .esp_now => blk: {
                    const mac = cstrFromStore(store, settings_keys.en_mac, "FF:FF:FF:FF:FF:FF", &mac_buf);
                    const ch = espnow_config.getChannel(store);
                    const enc = store.getU8(settings_keys.en_enc, 0) != 0;
                    break :blk c.modulus_espnow_transport_start(mac.ptr, ch, enc);
                },
                .ble_hid => blk: {
                    const name = cstrFromStore(store, settings_keys.ble_name, "grblHAL", &name_buf);
                    break :blk c.modulus_ble_transport_start(name.ptr);
                },
                else => false,
            };
            self.open_ok = ok;
            return ok;
        }

        pub fn send(self: *@This(), data: []const u8) bool {
            if (!self.open_ok) return false;
            return switch (conn) {
                .websocket => c.modulus_ws_send(data.ptr, data.len),
                .telnet => c.modulus_telnet_send(data.ptr, data.len),
                .i2c => c.modulus_i2c_transport_send(data.ptr, data.len),
                .can_bus => c.modulus_canbus_send(data.ptr, data.len),
                .esp_now => c.modulus_espnow_transport_send(data.ptr, data.len),
                .ble_hid => c.modulus_ble_transport_send(data.ptr, data.len),
                else => false,
            };
        }

        pub fn pollRx(_: *@This(), _: anytype) void {}

        pub fn injectRx(_: *@This(), _: []const u8) bool {
            return false;
        }

        pub fn drainTx(_: *@This()) []const u8 {
            return &[_]u8{};
        }
    };
}
