//! ExtEncoder HAL — M5 Port A I2C 0x59; host mock drives CNC jog.
//! STEP/CONT handwheel jogging ported from hal_ext_encoder.cpp.

pub const i2c_addr = @import("ext_encoder_const.zig").i2c_addr;
pub const reg_encoder_count = @import("ext_encoder_const.zig").reg_encoder_count;
pub const reg_reset = @import("ext_encoder_const.zig").reg_reset;
pub const reg_fw_version = @import("ext_encoder_const.zig").reg_fw_version;
pub const WheelBlock = @import("ext_encoder_const.zig").WheelBlock;

pub const ExtEncoder = @import("ext_encoder_state.zig").ExtEncoder;

test {
    _ = @import("ext_encoder_util.zig");
    _ = @import("ext_encoder_tests.zig");
}
