//! SD card + diagnostics shim — `storage_shim.c`.

const c = @import("modulus_shims");
const storage_mod = @import("storage.zig");

pub const CSdInfo = c.modulus_sd_info_t;
pub const CMemInfo = c.modulus_mem_info_t;

pub fn hwInit() void {
    c.modulus_storage_init();
}

pub fn mount() bool {
    return c.modulus_storage_mount();
}

pub fn unmount() void {
    c.modulus_storage_unmount();
}

pub fn isMounted() bool {
    return c.modulus_storage_is_mounted();
}

pub fn syncSdInfo(dst: *storage_mod.SdInfo) void {
    var raw: CSdInfo = undefined;
    c.modulus_storage_get_sd_info(&raw);
    dst.state = @enumFromInt(@intFromEnum(raw.state));
    dst.total_bytes = raw.total_bytes;
    dst.free_bytes = raw.free_bytes;
    dst.bus_width = raw.bus_width;
}

pub fn syncMemInfo(dst: *storage_mod.MemInfo) void {
    var raw: CMemInfo = undefined;
    c.modulus_storage_get_mem_info(&raw);
    dst.internal_free = raw.internal_free;
    dst.internal_total = raw.internal_total;
    dst.internal_min_free = raw.internal_min_free;
    dst.psram_free = raw.psram_free;
    dst.psram_total = raw.psram_total;
    dst.lvgl_free = raw.lvgl_free;
    dst.lvgl_used_pct = raw.lvgl_used_pct;
}

pub fn exportDiagnostics(path: [*:0]const u8) bool {
    return c.modulus_storage_export_diagnostics(path);
}

pub fn clearUiCache() void {
    c.modulus_storage_clear_ui_cache();
}

pub fn isUsbHostEnabled() bool {
    return c.modulus_storage_is_usb_host_enabled();
}
