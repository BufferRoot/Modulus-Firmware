//! USB volume G-code catalog — device C shim + host demo stub.

const std = @import("std");
const build_options = @import("build_options");

pub const max_files: usize = 32;
pub const name_len: usize = 28;

pub const Catalog = struct {
    count: u8 = 0,
    names: [max_files][name_len]u8 = [_][name_len]u8{.{0} ** name_len} ** max_files,
    selected: u8 = 0xff,
    /// Index handed to the controller as the pending job (0xff = none).
    /// Distinct from `selected`: the operator can browse other files after
    /// loading without changing what Cycle Start will run.
    loaded: u8 = 0xff,
    /// Set after safe eject; clears when USB host reports disconnect.
    ejected: bool = false,

    pub fn clear(self: *Catalog) void {
        self.count = 0;
        self.selected = 0xff;
        self.loaded = 0xff;
    }

    pub fn volumeReady(self: *const Catalog, usb_ready: bool) bool {
        return usb_ready and !self.ejected;
    }

    pub fn nameSlice(self: *const Catalog, i: u8) []const u8 {
        if (i >= self.count) return "";
        return std.mem.sliceTo(&self.names[i], 0);
    }

    pub fn setSelected(self: *Catalog, i: u8) void {
        if (i < self.count) self.selected = i;
    }

    pub fn refresh(self: *Catalog, usb_ready: bool) void {
        if (!usb_ready) self.ejected = false;
        self.clear();
        if (!usb_ready or self.ejected) return;
        if (build_options.device_nvs) {
            refreshDevice(self);
        } else {
            refreshHostStub(self);
        }
    }

    pub fn safeEject(self: *Catalog) bool {
        if (build_options.device_nvs) {
            if (!deviceEject()) return false;
        }
        self.clear();
        self.ejected = true;
        return true;
    }

    pub fn deleteSelected(self: *Catalog, usb_ready: bool) bool {
        if (self.selected >= self.count) return false;
        if (build_options.device_nvs) {
            if (!deviceDelete(self.selected)) return false;
            self.refresh(usb_ready);
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

    pub fn renameSelected(self: *Catalog, usb_ready: bool, new_name: []const u8) bool {
        if (self.selected >= self.count or new_name.len == 0) return false;
        if (build_options.device_nvs) {
            if (!deviceRename(self.selected, new_name)) return false;
            self.refresh(usb_ready);
            return true;
        }
        const n = @min(new_name.len, name_len - 1);
        @memset(&self.names[self.selected], 0);
        @memcpy(self.names[self.selected][0..n], new_name[0..n]);
        return true;
    }

    /// Select the file as the controller's pending job. Deliberately does NOT
    /// start motion — grblHAL `$SD/Run=` on some builds runs immediately, so we
    /// use the two-step select form and let Cycle Start do the running.
    pub fn loadCommand(self: *const Catalog, buf: []u8) ?[]const u8 {
        if (self.selected >= self.count) return null;
        const name = self.nameSlice(self.selected);
        return std.fmt.bufPrint(buf, "$SD/Select=/usb/{s}", .{name}) catch null;
    }

    /// Legacy immediate-run form, kept for the SD tool / older senders.
    pub fn startCommand(self: *const Catalog, buf: []u8) ?[]const u8 {
        if (self.selected >= self.count) return null;
        const name = self.nameSlice(self.selected);
        return std.fmt.bufPrint(buf, "$SD/Run={s}", .{name}) catch null;
    }
};

fn refreshHostStub(cat: *Catalog) void {
    const demo = [_][]const u8{ "bracket.nc", "pocket.gcode", "probe.ngc" };
    for (demo, 0..) |name, i| {
        if (i >= max_files) break;
        const n = @min(name.len, name_len - 1);
        @memcpy(cat.names[i][0..n], name[0..n]);
        cat.names[i][n] = 0;
        cat.count += 1;
    }
    if (cat.count > 0) cat.selected = 0;
}

const device = struct {
    extern fn modulus_usb_volume_refresh() usize;
    extern fn modulus_usb_volume_name(index: usize, buf: [*]u8, cap: usize) bool;
    extern fn modulus_usb_volume_delete(index: usize) bool;
    extern fn modulus_usb_volume_rename(index: usize, new_name: [*:0]const u8) bool;
    extern fn modulus_usb_volume_eject() bool;
};

fn refreshDevice(cat: *Catalog) void {
    const n = @min(device.modulus_usb_volume_refresh(), max_files);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (!device.modulus_usb_volume_name(i, &cat.names[i], name_len)) continue;
        cat.names[i][name_len - 1] = 0;
        cat.count += 1;
    }
    if (cat.count > 0) cat.selected = 0;
}

fn deviceDelete(index: u8) bool {
    return device.modulus_usb_volume_delete(index);
}

fn deviceRename(index: u8, new_name: []const u8) bool {
    var z: [name_len:0]u8 = .{0} ** name_len;
    const n = @min(new_name.len, name_len - 1);
    @memcpy(z[0..n], new_name[0..n]);
    return device.modulus_usb_volume_rename(index, &z);
}

fn deviceEject() bool {
    return device.modulus_usb_volume_eject();
}

pub fn isGcodeName(name: []const u8) bool {
    if (name.len < 4) return false;
    const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return false;
    const ext = name[dot + 1 ..];
    return extEq(ext, "nc") or extEq(ext, "gcode") or extEq(ext, "ngc") or extEq(ext, "tap");
}

fn extEq(ext: []const u8, lit: []const u8) bool {
    if (ext.len != lit.len) return false;
    for (ext, lit) |a, b| {
        if (std.ascii.toLower(a) != b) return false;
    }
    return true;
}

test "gcode extension filter" {
    try std.testing.expect(isGcodeName("part.NC"));
    try std.testing.expect(!isGcodeName("readme.txt"));
}

test "host stub fills catalog" {
    var cat: Catalog = .{};
    cat.refresh(true);
    try std.testing.expect(cat.count >= 3);
}

test "safe eject blocks refresh until disconnect" {
    var cat: Catalog = .{};
    cat.refresh(true);
    try std.testing.expect(cat.safeEject());
    try std.testing.expect(cat.ejected);
    cat.refresh(true);
    try std.testing.expectEqual(@as(u8, 0), cat.count);
    cat.refresh(false);
    try std.testing.expect(!cat.ejected);
    cat.refresh(true);
    try std.testing.expect(cat.count >= 3);
}
