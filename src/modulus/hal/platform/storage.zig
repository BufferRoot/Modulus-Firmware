//! Storage HAL — SD + diagnostics; device I/O in `idf_storage.zig` / `storage_shim.c`.

const std = @import("std");
const build_options = @import("build_options");
const idf_storage_mod = if (build_options.device_nvs)
    @import("idf_storage.zig")
else
    struct {
        pub fn hwInit() void {}
        pub fn mount() bool {
            return false;
        }
        pub fn unmount() void {}
        pub fn isMounted() bool {
            return false;
        }
        pub fn syncSdInfo(_: *SdInfo) void {}
        pub fn syncMemInfo(_: *MemInfo) void {}
        pub fn exportDiagnostics(_: [*:0]const u8) bool {
            return false;
        }
        pub fn clearUiCache() void {}
        pub fn isUsbHostEnabled() bool {
            return false;
        }
    };

pub const Storage = struct {
    initialized: bool = false,
    sd: SdInfo = .{},
    mem: MemInfo = .{},

    pub fn init(self: *Storage) void {
        if (build_options.device_nvs) {
            idf_storage_mod.hwInit();
        }
        self.initialized = true;
    }

    pub fn mount(self: *Storage) bool {
        if (!self.initialized) return false;
        return idf_storage_mod.mount();
    }

    pub fn unmount(self: *Storage) void {
        if (!self.initialized) return;
        idf_storage_mod.unmount();
    }

    pub fn isMounted(self: *const Storage) bool {
        if (!self.initialized) return false;
        return idf_storage_mod.isMounted();
    }

    pub fn refreshSd(self: *Storage) void {
        if (!self.initialized) return;
        idf_storage_mod.syncSdInfo(&self.sd);
    }

    pub fn refreshMem(self: *Storage) void {
        if (!self.initialized) return;
        idf_storage_mod.syncMemInfo(&self.mem);
    }

    pub fn exportDiagnostics(self: *const Storage, path: [*:0]const u8) bool {
        if (!self.initialized) return false;
        return idf_storage_mod.exportDiagnostics(path);
    }

    pub fn clearUiCache(self: *Storage) void {
        if (!self.initialized) return;
        idf_storage_mod.clearUiCache();
    }

    pub fn usbHostEnabled(self: *const Storage) bool {
        if (!self.initialized) return false;
        return idf_storage_mod.isUsbHostEnabled();
    }
};

pub const SdState = enum(u8) {
    not_present = 0,
    mounted,
    sd_error,
};

pub const SdInfo = struct {
    state: SdState = .not_present,
    total_bytes: u64 = 0,
    free_bytes: u64 = 0,
    bus_width: u8 = 4,
};

pub const MemInfo = struct {
    internal_free: usize = 0,
    internal_total: usize = 0,
    internal_min_free: usize = 0,
    psram_free: usize = 0,
    psram_total: usize = 0,
    lvgl_free: usize = 0,
    lvgl_used_pct: u8 = 0,
};

pub fn formatCapacity(buf: []u8, free_bytes: u64, total_bytes: u64) ![]const u8 {
    if (free_bytes >= 1024 * 1024 * 1024 or total_bytes >= 1024 * 1024 * 1024) {
        return std.fmt.bufPrint(buf, "{d:.1} GB free of {d:.1} GB", .{
            @as(f64, @floatFromInt(free_bytes)) / (1024.0 * 1024.0 * 1024.0),
            @as(f64, @floatFromInt(total_bytes)) / (1024.0 * 1024.0 * 1024.0),
        });
    }
    return std.fmt.bufPrint(buf, "{d:.0} MB free of {d:.0} MB", .{
        @as(f64, @floatFromInt(free_bytes)) / (1024.0 * 1024.0),
        @as(f64, @floatFromInt(total_bytes)) / (1024.0 * 1024.0),
    });
}

test "storage: capacity format GB" {
    var buf: [64]u8 = undefined;
    const out = try formatCapacity(&buf, 2 * 1024 * 1024 * 1024, 4 * 1024 * 1024 * 1024);
    try std.testing.expect(std.mem.indexOf(u8, out, "GB") != null);
}
