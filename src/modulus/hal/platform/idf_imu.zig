//! BMI270 IMU — bridge to `imu_shim.c`.

const c = @import("modulus_shims");

pub fn hwInit() void {
    c.modulus_imu_init();
}
