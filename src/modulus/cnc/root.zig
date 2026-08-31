//! CNC layer — config, machine state, grblHAL engine, driver.

const std = @import("std");

pub const cnc_config = @import("cnc_config.zig");
pub const cnc_state = @import("cnc_state.zig");
pub const driver = @import("driver.zig");
pub const grblhal = @import("grblhal/root.zig");
pub const linuxcnc = @import("linuxcnc/root.zig");
pub const protocol_engine = @import("protocol_engine.zig");
pub const rx_ring = @import("rx_ring.zig");
pub const maintenance = @import("maintenance.zig");
pub const envelope = @import("envelope.zig");
pub const settings_dump = @import("settings_dump.zig");
pub const mach3 = @import("mach3/root.zig");
pub const masso = @import("masso/root.zig");
pub const probe_engine = @import("probe_engine.zig");
/// Pendant-as-sender G-code streamer over the grblHAL MPG port.
pub const job_stream = @import("job_stream.zig");

test {
    std.testing.refAllDecls(@This());
}
