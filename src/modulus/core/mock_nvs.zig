//! In-memory NVS backend for host unit tests.

const std = @import("std");

const Value = union(enum) {
    u8: u8,
    u16: u16,
    string: []u8,
};

pub const NvsBackend = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMapUnmanaged(Value) = .empty,
    opened: bool = false,

    pub fn open(self: *NvsBackend) void {
        self.opened = true;
    }

    pub fn init(allocator: std.mem.Allocator) NvsBackend {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *NvsBackend) void {
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.freeValue(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.entries.deinit(self.allocator);
    }

    pub fn eraseAll(self: *NvsBackend) !void {
        if (!self.opened) return error.NvsNotReady;
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            self.freeValue(entry.value_ptr.*);
            self.allocator.free(entry.key_ptr.*);
        }
        self.entries.clearRetainingCapacity();
    }

    fn freeValue(self: *NvsBackend, value: Value) void {
        if (value == .string) self.allocator.free(value.string);
    }

    fn putKey(self: *NvsBackend, key: []const u8) !*Value {
        const owned_key = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned_key);
        const gop = try self.entries.getOrPut(self.allocator, owned_key);
        if (!gop.found_existing) {
            gop.key_ptr.* = owned_key;
        } else {
            self.allocator.free(owned_key);
            self.freeValue(gop.value_ptr.*);
        }
        return gop.value_ptr;
    }

    pub fn beginBatch(_: *NvsBackend) void {}
    pub fn endBatch(_: *NvsBackend) void {}

    pub fn hasU8(self: *const NvsBackend, key: []const u8) bool {
        const entry = self.entries.get(key) orelse return false;
        return entry == .u8;
    }

    pub fn getU8(self: *const NvsBackend, key: []const u8, def: u8) u8 {
        const entry = self.entries.get(key) orelse return def;
        return switch (entry) {
            .u8 => |v| v,
            else => def,
        };
    }

    pub fn setU8(self: *NvsBackend, key: []const u8, val: u8) !void {
        const slot = try self.putKey(key);
        slot.* = .{ .u8 = val };
    }

    pub fn getU16(self: *const NvsBackend, key: []const u8, def: u16) u16 {
        const entry = self.entries.get(key) orelse return def;
        return switch (entry) {
            .u16 => |v| v,
            .u8 => |v| v,
            else => def,
        };
    }

    pub fn setU16(self: *NvsBackend, key: []const u8, val: u16) !void {
        const slot = try self.putKey(key);
        slot.* = .{ .u16 = val };
    }

    pub fn getBool(self: *const NvsBackend, key: []const u8, def: bool) bool {
        return self.getU8(key, if (def) 1 else 0) != 0;
    }

    pub fn setBool(self: *NvsBackend, key: []const u8, val: bool) !void {
        try self.setU8(key, if (val) 1 else 0);
    }

    pub fn getStr(self: *const NvsBackend, key: []const u8, buf: []u8) bool {
        if (buf.len == 0) return false;
        const entry = self.entries.get(key) orelse {
            buf[0] = 0;
            return false;
        };
        const src = switch (entry) {
            .string => |s| s,
            else => {
                buf[0] = 0;
                return false;
            },
        };
        const copy_len = @min(src.len, buf.len - 1);
        @memcpy(buf[0..copy_len], src[0..copy_len]);
        buf[copy_len] = 0;
        return true;
    }

    pub fn setStr(self: *NvsBackend, key: []const u8, val: []const u8) !void {
        const owned_val = try self.allocator.dupe(u8, val);
        errdefer self.allocator.free(owned_val);
        const slot = try self.putKey(key);
        slot.* = .{ .string = owned_val };
    }
};

test "mock_nvs: StringHashMapUnmanaged round-trip" {
    const a = std.testing.allocator;
    var backend = NvsBackend.init(a);
    defer backend.deinit();
    backend.open();
    try backend.setU8("step", 3);
    try std.testing.expect(backend.hasU8("step"));
    try std.testing.expectEqual(@as(u8, 3), backend.getU8("step", 0));
    try backend.setU16("feed", 1200);
    try std.testing.expectEqual(@as(u16, 1200), backend.getU16("feed", 0));
    try backend.setStr("name", "modulus");
    var buf: [32]u8 = undefined;
    try std.testing.expect(backend.getStr("name", &buf));
    try std.testing.expectEqualStrings("modulus", std.mem.sliceTo(&buf, 0));
}
