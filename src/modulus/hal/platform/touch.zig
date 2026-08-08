//! Touch HAL — glove-friendly LVGL indev (`touch_shim.c` on device).

const build_options = @import("build_options");
const idf_touch_mod = if (build_options.device_nvs)
    @import("idf_touch.zig")
else
    struct {};

pub const Touch = struct {
    initialized: bool = false,

    pub fn init(self: *Touch) void {
        if (build_options.device_nvs) {
            idf_touch_mod.hwInit();
        }
        self.initialized = true;
    }
};
