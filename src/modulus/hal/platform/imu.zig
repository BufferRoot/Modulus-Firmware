//! BMI270 motion-wake HAL — `imu_shim.c` on device.

const build_options = @import("build_options");
const idf_imu_mod = if (build_options.device_nvs)
    @import("idf_imu.zig")
else
    struct {};

pub const Imu = struct {
    initialized: bool = false,

    pub fn init(self: *Imu) void {
        if (build_options.device_nvs) {
            idf_imu_mod.hwInit();
        }
        self.initialized = true;
    }
};
