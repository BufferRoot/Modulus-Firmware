//! Accumulates grbl `$$` setting lines for on-device browser.

const std = @import("std");
const build_options = @import("build_options");
const host_io = @import("../core/host_io.zig");
pub const dump_buf_max = 8192;

pub const SettingsDump = struct {
    active: bool = false,
    complete: bool = false,
    failed: bool = false,
    buf: [dump_buf_max]u8 = undefined,
    len: usize = 0,

    pub fn begin(self: *SettingsDump) void {
        self.* = .{};
        self.active = true;
    }

    pub fn cancel(self: *SettingsDump) void {
        self.* = .{};
    }

    pub fn appendLine(self: *SettingsDump, line: []const u8) bool {
        if (!self.active or self.complete or self.failed) return false;
        if (line.len == 0) return true;
        if (self.len + line.len + 1 > self.buf.len) {
            self.failed = true;
            self.active = false;
            return false;
        }
        @memcpy(self.buf[self.len..][0..line.len], line);
        self.len += line.len;
        self.buf[self.len] = '\n';
        self.len += 1;
        return true;
    }

    pub fn onOk(self: *SettingsDump) void {
        if (!self.active) return;
        self.active = false;
        self.complete = true;
    }

    pub fn onError(self: *SettingsDump) void {
        if (!self.active) return;
        self.active = false;
        self.failed = true;
    }

    pub fn text(self: *const SettingsDump) []const u8 {
        return self.buf[0..self.len];
    }

    /// Host export — requires Juicy Main / test `io` (see `Runtime.exportSettingsDump`).
    pub fn writeHostExport(self: *const SettingsDump, io: ?std.Io, path: []const u8) host_io.Error!void {
        if (comptime build_options.device_nvs) return error.IoUnavailable;
        return writeHostExportCold(self, io, path);
    }

    fn writeHostExportCold(self: *const SettingsDump, io: ?std.Io, path: []const u8) host_io.Error!void {
        @branchHint(.cold);
        const io_instance = try host_io.require(io);
        return host_io.writeTextFile(io_instance, path, self.text());
    }
};

test "cnc: settings dump accumulates lines" {
    var dump: SettingsDump = .{};
    dump.begin();
    try std.testing.expect(dump.appendLine("$110=5000"));
    try std.testing.expect(dump.appendLine("$111=5000"));
    dump.onOk();
    try std.testing.expect(dump.complete);
    try std.testing.expectEqualStrings("$110=5000\n$111=5000\n", dump.text());
}

test "cnc: settings dump host export via io" {
    if (comptime build_options.device_nvs) return error.SkipZigTest;
    var dump: SettingsDump = .{};
    dump.begin();
    try std.testing.expect(dump.appendLine("$110=5000"));
    dump.onOk();

    const io = std.testing.io;
    const path = ".zig-cache/modulus_settings_dump_export.txt";
    try dump.writeHostExport(io, path);
    defer std.Io.Dir.cwd().deleteFile(io, path) catch {};

    const data = try host_io.readTextFileLimited(io, std.testing.allocator, path, 4096);
    defer std.testing.allocator.free(data);
    try std.testing.expectEqualStrings("$110=5000\n", data);
}
