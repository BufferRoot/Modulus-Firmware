//! ESP-IDF NVS backend — bridge to `firmware/tab5/components/modulus_zig/nvs_shim.c`.

const std = @import("std");
const c = @import("modulus_shims");

/// ESP-IDF NVS key length limit (namespace keys).
const max_key_len = 15;

pub const NvsBackend = struct {
    ready: bool = false,

    pub fn init(_: std.mem.Allocator) NvsBackend {
        return .{};
    }

    pub fn deinit(_: *NvsBackend) void {}

    pub fn open(self: *NvsBackend) void {
        const err = c.modulus_nvs_init();
        if (err != 0) @panic("modulus_nvs_init failed");
        self.ready = true;
    }

    fn keyCstr(key: []const u8, buf: *[max_key_len + 1]u8) ![*:0]const u8 {
        if (key.len > max_key_len) return error.KeyTooLong;
        @memcpy(buf[0..key.len], key);
        buf[key.len] = 0;
        return buf[0..key.len :0].ptr;
    }

    pub fn hasU8(self: *const NvsBackend, key: []const u8) bool {
        if (!self.ready) return false;
        var kbuf: [max_key_len + 1]u8 = undefined;
        const k = keyCstr(key, &kbuf) catch return false;
        return c.modulus_nvs_has_u8(k);
    }

    pub fn getU8(self: *const NvsBackend, key: []const u8, def: u8) u8 {
        if (!self.ready) return def;
        var kbuf: [max_key_len + 1]u8 = undefined;
        const k = keyCstr(key, &kbuf) catch return def;
        return c.modulus_nvs_get_u8(k, def);
    }

    pub fn setU8(self: *NvsBackend, key: []const u8, val: u8) !void {
        if (!self.ready) return error.NvsNotReady;
        var kbuf: [max_key_len + 1]u8 = undefined;
        const k = try keyCstr(key, &kbuf);
        if (c.modulus_nvs_set_u8(k, val) != 0) return error.NvsWriteFailed;
    }

    pub fn getU16(self: *const NvsBackend, key: []const u8, def: u16) u16 {
        if (!self.ready) return def;
        var kbuf: [max_key_len + 1]u8 = undefined;
        const k = keyCstr(key, &kbuf) catch return def;
        return c.modulus_nvs_get_u16(k, def);
    }

    pub fn setU16(self: *NvsBackend, key: []const u8, val: u16) !void {
        if (!self.ready) return error.NvsNotReady;
        var kbuf: [max_key_len + 1]u8 = undefined;
        const k = try keyCstr(key, &kbuf);
        if (c.modulus_nvs_set_u16(k, val) != 0) return error.NvsWriteFailed;
    }

    pub fn getBool(self: *const NvsBackend, key: []const u8, def: bool) bool {
        return self.getU8(key, if (def) 1 else 0) != 0;
    }

    pub fn setBool(self: *NvsBackend, key: []const u8, val: bool) !void {
        try self.setU8(key, if (val) 1 else 0);
    }

    pub fn getStr(self: *const NvsBackend, key: []const u8, buf: []u8) bool {
        if (!self.ready or buf.len == 0) {
            if (buf.len > 0) buf[0] = 0;
            return false;
        }
        var kbuf: [max_key_len + 1]u8 = undefined;
        const k = keyCstr(key, &kbuf) catch {
            buf[0] = 0;
            return false;
        };
        return c.modulus_nvs_get_str(k, buf.ptr, buf.len);
    }

    pub fn setStr(self: *NvsBackend, key: []const u8, val: []const u8) !void {
        if (!self.ready) return error.NvsNotReady;
        var tmp: [128]u8 = undefined;
        if (val.len >= tmp.len) return error.ValueTooLong;
        @memcpy(tmp[0..val.len], val);
        tmp[val.len] = 0;
        var kbuf: [max_key_len + 1]u8 = undefined;
        const k = try keyCstr(key, &kbuf);
        if (c.modulus_nvs_set_str(k, @ptrCast(&tmp)) != 0) return error.NvsWriteFailed;
    }

    pub fn eraseAll(self: *NvsBackend) !void {
        if (!self.ready) return error.NvsNotReady;
        const err = c.modulus_nvs_erase_all();
        if (err != 0) return error.NvsEraseFailed;
    }

    pub fn beginBatch(_: *NvsBackend) void {
        c.modulus_nvs_begin_batch();
    }

    pub fn endBatch(_: *NvsBackend) void {
        c.modulus_nvs_end_batch();
    }
};
