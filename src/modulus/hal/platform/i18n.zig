//! i18n HAL — locale tables via `i18n_shim.c` on device.

const build_options = @import("build_options");
const idf_i18n_mod = if (build_options.device_nvs)
    @import("idf_i18n.zig")
else
    struct {};

pub const I18n = struct {
    initialized: bool = false,

    pub fn init(self: *I18n) void {
        if (build_options.device_nvs) {
            idf_i18n_mod.hwInit();
        }
        self.initialized = true;
    }
};
