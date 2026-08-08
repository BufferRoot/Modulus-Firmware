//! Persistent settings — host mock NVS; device uses ESP-IDF shim (`idf_nvs.zig`).

const std = @import("std");
const keys = @import("settings_keys.zig");
const device_log = @import("device_log.zig");
const build_options = @import("build_options");
const nvs_mod = if (build_options.device_nvs)
    @import("idf_nvs.zig")
else
    @import("mock_nvs.zig");

pub const Keys = keys;
pub const max_key_len = keys.max_key_len;
pub const nvs_namespace = keys.nvs_namespace;

pub const InitHooks = struct {
    /// Mirrors C++ `init()` brightness apply — no-op on host when null.
    apply_brightness: ?*const fn (u8) void = null,
    apply_flip: ?*const fn (bool) void = null,
    apply_timeouts: ?*const fn (u16, u16) void = null,
    apply_theme: ?*const fn () void = null,
};

pub const Store = struct {
    nvs: nvs_mod.NvsBackend,

    const log = device_log.settings;

    pub fn init(allocator: std.mem.Allocator) Store {
        return .{ .nvs = nvs_mod.NvsBackend.init(allocator) };
    }

    pub fn deinit(self: *Store) void {
        self.nvs.deinit();
    }

    /// Open NVS namespace (device flash init) and apply saved display/theme hooks.
    pub fn open(self: *Store, hooks: InitHooks) void {
        self.nvs.open();
        const bright = self.getU8(keys.bright, 100);
        if (hooks.apply_brightness) |apply| apply(bright);
        const flip = self.getBool(keys.flip, false);
        if (hooks.apply_flip) |apply| apply(flip);
        const dim_to = self.getU16(keys.dim_to, 0);
        const scr_to = self.getU16(keys.scr_to, 0);
        if (hooks.apply_timeouts) |apply| apply(dim_to, scr_to);
        if (hooks.apply_theme) |apply| apply();
    }

    pub fn getBool(self: *const Store, key: []const u8, def: bool) bool {
        return self.nvs.getBool(key, def);
    }

    pub fn setBool(self: *Store, key: []const u8, val: bool) !void {
        try self.nvs.setBool(key, val);
    }

    pub fn hasU8(self: *const Store, key: []const u8) bool {
        return self.nvs.hasU8(key);
    }

    pub fn getU8(self: *const Store, key: []const u8, def: u8) u8 {
        return self.nvs.getU8(key, def);
    }

    pub fn setU8(self: *Store, key: []const u8, val: u8) !void {
        try self.nvs.setU8(key, val);
    }

    pub fn setU8Clamped(self: *Store, key: []const u8, val: u8, min_v: u8, max_v: u8) !void {
        const clamped = std.math.clamp(val, min_v, max_v);
        try self.setU8(key, clamped);
    }

    pub fn getU16(self: *const Store, key: []const u8, def: u16) u16 {
        return self.nvs.getU16(key, def);
    }

    pub fn setU16(self: *Store, key: []const u8, val: u16) !void {
        try self.nvs.setU16(key, val);
    }

    pub fn setU16Clamped(self: *Store, key: []const u8, val: u16, min_v: u16, max_v: u16) !void {
        const clamped = std.math.clamp(val, min_v, max_v);
        try self.setU16(key, clamped);
    }

    pub fn getStr(self: *const Store, key: []const u8, buf: []u8) bool {
        return self.nvs.getStr(key, buf);
    }

    pub fn setStr(self: *Store, key: []const u8, val: []const u8) !void {
        try self.nvs.setStr(key, val);
    }

    pub fn setStrValidated(self: *Store, key: []const u8, val: []const u8, max_len: usize) !void {
        if (val.len > max_len) {
            try self.setStr(key, val[0..max_len]);
        } else {
            try self.setStr(key, val);
        }
    }

    pub fn factoryReset(self: *Store) !void {
        try self.nvs.eraseAll();
    }

    /// Fire-and-forget NVS write — C++ parity; UI/CNC paths must not abort on flash errors.
    pub fn persistU8(self: *Store, key: []const u8, val: u8) void {
        self.setU8(key, val) catch |err| log.warn("persistU8 {s}: {}", .{ key, err });
    }

    pub fn persistBool(self: *Store, key: []const u8, val: bool) void {
        self.setBool(key, val) catch |err| log.warn("persistBool {s}: {}", .{ key, err });
    }

    pub fn persistU16(self: *Store, key: []const u8, val: u16) void {
        self.setU16(key, val) catch |err| log.warn("persistU16 {s}: {}", .{ key, err });
    }

    /// Defer flash commits across many writes (maintenance flush on Core 1).
    pub fn beginBatch(self: *Store) void {
        self.nvs.beginBatch();
    }

    pub fn endBatch(self: *Store) void {
        self.nvs.endBatch();
    }
};

// ── tests ──

test "core: settings u8 default and round-trip" {
    const a = std.testing.allocator;
    var store = Store.init(a);
    defer store.deinit();

    try std.testing.expectEqual(@as(u8, 4), store.getU8(keys.cnc_conn, keys.k_default_cnc_conn));
    try store.setU8(keys.cnc_conn, 2);
    try std.testing.expect(store.hasU8(keys.cnc_conn));
    try std.testing.expectEqual(@as(u8, 2), store.getU8(keys.cnc_conn, keys.k_default_cnc_conn));
}

test "core: settings bool stored as u8" {
    const a = std.testing.allocator;
    var store = Store.init(a);
    defer store.deinit();

    try std.testing.expect(!store.getBool(keys.wifi, false));
    try store.setBool(keys.wifi, true);
    try std.testing.expect(store.getBool(keys.wifi, false));
}

test "core: settings str copy out" {
    const a = std.testing.allocator;
    var store = Store.init(a);
    defer store.deinit();

    try store.setStr(keys.wf_ssid, "Modulus-AP");
    var buf: [32]u8 = undefined;
    try std.testing.expect(store.getStr(keys.wf_ssid, &buf));
    try std.testing.expectEqualStrings("Modulus-AP", std.mem.sliceTo(&buf, 0));
}

test "core: settings str validated truncates" {
    const a = std.testing.allocator;
    var store = Store.init(a);
    defer store.deinit();

    try store.setStrValidated(keys.mach_name, "VeryLongMachineName", 8);
    var buf: [32]u8 = undefined;
    try std.testing.expect(store.getStr(keys.mach_name, &buf));
    try std.testing.expectEqualStrings("VeryLong", std.mem.sliceTo(&buf, 0));
}

test "core: mach_name round-trip at C++ max length" {
    const a = std.testing.allocator;
    var store = Store.init(a);
    defer store.deinit();

    const long_name = "0123456789012345678901234567890XY";
    try store.setStrValidated(keys.mach_name, long_name, keys.mach_name_max_len);
    var buf: [32]u8 = undefined;
    try std.testing.expect(store.getStr(keys.mach_name, &buf));
    try std.testing.expectEqualStrings(long_name[0..keys.mach_name_max_len], std.mem.sliceTo(&buf, 0));
}

test "core: settings clamped u8" {
    const a = std.testing.allocator;
    var store = Store.init(a);
    defer store.deinit();

    try store.setU8Clamped(keys.bright, 200, 0, 100);
    try std.testing.expectEqual(@as(u8, 100), store.getU8(keys.bright, 0));
}

test "core: settings factory reset clears" {
    const a = std.testing.allocator;
    var store = Store.init(a);
    defer store.deinit();

    store.open(.{});
    try store.setU8(keys.loglvl, 3);
    try store.factoryReset();
    try std.testing.expect(!store.hasU8(keys.loglvl));
}

test "core: settings factory reset fails before open" {
    const a = std.testing.allocator;
    var store = Store.init(a);
    defer store.deinit();

    try store.setU8(keys.loglvl, 3);
    try std.testing.expectError(error.NvsNotReady, store.factoryReset());
    try std.testing.expect(store.hasU8(keys.loglvl));
}

test "core: settings qbtn keys round-trip" {
    const a = std.testing.allocator;
    var store = Store.init(a);
    defer store.deinit();

    inline for (0..keys.qbtn_slot_count) |slot| {
        const key = keys.qbtnKey(slot);
        const def = keys.k_default_qbtn[slot];
        try std.testing.expectEqual(def, store.getU8(key, def));
        try store.setU8(key, @intCast(slot + 1));
        try std.testing.expectEqual(@as(u8, @intCast(slot + 1)), store.getU8(key, def));
    }
}

test "core: settings open applies brightness hook" {
    const a = std.testing.allocator;
    var store = Store.init(a);
    defer store.deinit();

    const Ctx = struct {
        var applied: u8 = 0;
        fn hook(v: u8) void {
            applied = v;
        }
    };

    try store.setU8(keys.bright, 42);
    store.open(.{ .apply_brightness = Ctx.hook });
    try std.testing.expectEqual(@as(u8, 42), Ctx.applied);
}

test "core: settings persist helpers round-trip" {
    const a = std.testing.allocator;
    var store = Store.init(a);
    defer store.deinit();

    store.persistU8(keys.cnc_feedovr, 150);
    try std.testing.expectEqual(@as(u8, 150), store.getU8(keys.cnc_feedovr, 100));
    store.persistBool(keys.wifi, true);
    try std.testing.expect(store.getBool(keys.wifi, false));
    store.persistU16(keys.cnc_poll, 500);
    try std.testing.expectEqual(@as(u16, 500), store.getU16(keys.cnc_poll, 250));
}
