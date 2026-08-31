//! SD card folder catalog — `/sdcard/modulus/{logs,backups,...}`.

const std = @import("std");
const build_options = @import("build_options");

pub const max_entries: usize = 32;
pub const name_len: usize = 36;
pub const path_len: usize = 96;

pub const Folder = enum(u8) {
    logs = 0,
    backups = 1,
    macros = 2,
    scripts = 3,
    reports = 4,
    cache = 5,
};

pub const folders = [_]struct { id: Folder, label: []const u8 }{
    .{ .id = .logs, .label = "Logs" },
    .{ .id = .backups, .label = "Backups" },
    .{ .id = .macros, .label = "Macros" },
    .{ .id = .scripts, .label = "Scripts" },
    .{ .id = .reports, .label = "Reports" },
    .{ .id = .cache, .label = "Cache" },
};

pub const Catalog = struct {
    folder: Folder = .backups,
    count: u8 = 0,
    names: [max_entries][name_len]u8 = [_][name_len]u8{.{0} ** name_len} ** max_entries,
    selected: u8 = 0xff,

    pub fn clear(self: *Catalog) void {
        self.count = 0;
        self.selected = 0xff;
    }

    pub fn nameSlice(self: *const Catalog, i: u8) []const u8 {
        if (i >= self.count) return "";
        return std.mem.sliceTo(&self.names[i], 0);
    }

    pub fn setSelected(self: *Catalog, i: u8) void {
        if (i < self.count) self.selected = i;
    }

    pub fn volumeReady(self: *const Catalog, sd_mounted: bool) bool {
        _ = self;
        return sd_mounted;
    }

    pub fn ensureLayout(self: *Catalog, sd_mounted: bool) bool {
        if (!sd_mounted) return false;
        if (build_options.device_nvs) {
            return device.modulus_sd_volume_ensure_layout();
        }
        _ = self;
        return true;
    }

    pub fn refresh(self: *Catalog, sd_mounted: bool) void {
        self.clear();
        if (!sd_mounted) return;
        if (build_options.device_nvs) {
            refreshDevice(self);
        } else {
            refreshHostStub(self);
        }
    }

    pub fn deleteSelected(self: *Catalog, sd_mounted: bool) bool {
        if (self.selected >= self.count) return false;
        if (build_options.device_nvs) {
            if (!device.modulus_sd_volume_delete(@intFromEnum(self.folder), self.selected)) return false;
            self.refresh(sd_mounted);
            return true;
        }
        const sel = self.selected;
        var i = sel;
        while (i + 1 < self.count) : (i += 1) {
            @memcpy(self.names[i][0..], self.names[i + 1][0..]);
            self.names[i][name_len - 1] = 0;
        }
        if (self.count > 0) self.count -= 1;
        if (self.count == 0) {
            self.selected = 0xff;
        } else if (sel >= self.count) {
            self.selected = self.count - 1;
        }
        return true;
    }

    pub fn selectedPath(self: *const Catalog, buf: []u8) ?[]const u8 {
        if (self.selected >= self.count) return null;
        if (build_options.device_nvs) {
            var z: [path_len:0]u8 = .{0} ** path_len;
            if (!device.modulus_sd_volume_entry_path(@intFromEnum(self.folder), self.selected, &z, z.len)) return null;
            const n = std.mem.sliceTo(&z, 0).len;
            if (n >= buf.len) return null;
            @memcpy(buf[0..n], z[0..n]);
            buf[n] = 0;
            return buf[0..n];
        }
        const rel = folderRel(self.folder);
        return std.fmt.bufPrint(buf, "/sdcard/modulus/{s}/{s}", .{ rel, self.nameSlice(self.selected) }) catch null;
    }

    pub fn makeBackupPath(buf: []u8) ?[]const u8 {
        if (build_options.device_nvs) {
            var z: [path_len:0]u8 = .{0} ** path_len;
            if (!device.modulus_sd_volume_backup_path(&z, z.len)) return null;
            const n = std.mem.sliceTo(&z, 0).len;
            if (n >= buf.len) return null;
            @memcpy(buf[0..n], z[0..n]);
            buf[n] = 0;
            return buf[0..n];
        }
        return std.fmt.bufPrint(buf, "/sdcard/modulus/backups/settings_demo.json", .{}) catch null;
    }

    pub fn makeLogPath(buf: []u8) ?[]const u8 {
        if (build_options.device_nvs) {
            var z: [path_len:0]u8 = .{0} ** path_len;
            if (!device.modulus_sd_volume_log_path(&z, z.len)) return null;
            const n = std.mem.sliceTo(&z, 0).len;
            if (n >= buf.len) return null;
            @memcpy(buf[0..n], z[0..n]);
            buf[n] = 0;
            return buf[0..n];
        }
        return std.fmt.bufPrint(buf, "/sdcard/modulus/logs/diag_demo.txt", .{}) catch null;
    }
};

fn folderRel(f: Folder) []const u8 {
    return switch (f) {
        .logs => "logs",
        .backups => "backups",
        .macros => "macros",
        .scripts => "scripts",
        .reports => "reports",
        .cache => "cache",
    };
}

const device = struct {
    extern fn modulus_sd_volume_ensure_layout() bool;
    extern fn modulus_sd_volume_refresh(folder: u8) usize;
    extern fn modulus_sd_volume_name(index: usize, buf: [*]u8, cap: usize) bool;
    extern fn modulus_sd_volume_delete(folder: u8, index: usize) bool;
    extern fn modulus_sd_volume_backup_path(out: [*]u8, cap: usize) bool;
    extern fn modulus_sd_volume_log_path(out: [*]u8, cap: usize) bool;
    extern fn modulus_sd_volume_entry_path(folder: u8, index: usize, out: [*]u8, cap: usize) bool;
};

fn refreshDevice(cat: *Catalog) void {
    const n = @min(device.modulus_sd_volume_refresh(@intFromEnum(cat.folder)), max_entries);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!device.modulus_sd_volume_name(i, &cat.names[i], name_len)) continue;
        cat.names[i][name_len - 1] = 0;
        cat.count += 1;
    }
    if (cat.count > 0) cat.selected = 0;
}

fn refreshHostStub(cat: *Catalog) void {
    const demo = switch (cat.folder) {
        .logs => [_][]const u8{ "diag_20260830.txt", "runtime.log" },
        .backups => [_][]const u8{ "settings_20260830.json", "profile_shop.json" },
        .macros => [_][]const u8{ "warmup.macro", "toolchange.macro" },
        .scripts => [_][]const u8{ "homing.gcode", "probe_ngc.gcode" },
        .reports => [_][]const u8{ "job_summary.csv", "maint_report.txt" },
        .cache => [_][]const u8{ "ui_tiles.bin", "zb_index.cache" },
    };
    for (demo, 0..) |name, i| {
        if (i >= max_entries) break;
        const n = @min(name.len, name_len - 1);
        @memcpy(cat.names[i][0..n], name[0..n]);
        cat.names[i][n] = 0;
        cat.count += 1;
    }
    if (cat.count > 0) cat.selected = 0;
}

test "sd folders cover volume layout" {
    try std.testing.expect(folders.len == 6);
    try std.testing.expect(@intFromEnum(Folder.cache) + 1 == folders.len);
}

test "host stub lists per folder" {
    var cat: Catalog = .{ .folder = .reports };
    cat.refresh(true);
    try std.testing.expect(cat.count > 0);
    try std.testing.expect(std.mem.eql(u8, cat.nameSlice(0), "maint_report.txt") or
        std.mem.eql(u8, cat.nameSlice(0), "job_summary.csv"));
}
