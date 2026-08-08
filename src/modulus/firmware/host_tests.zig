//! Host-only test aggregator — keeps firmware tests out of device `tab5-lib` graph.

test {
    _ = @import("abi.zig");
    _ = @import("abi_layout.zig");
    _ = @import("device_runtime.zig");
    _ = @import("system_task.zig");
    _ = @import("ota.zig");
}
