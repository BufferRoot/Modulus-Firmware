//! C6 coprocessor boot — no P4 display/sensor/dashboard imports.

const bridge = @import("../../hal/bridge_c6.zig");
const wireless = @import("../../hal/c6/wireless.zig");

pub const BootError = error{
    HalUnavailable,
};

var idle_tick: u32 = 0;

pub fn run() BootError!void {
    bridge.logInfo("modulus_c6: Zig runtime online");
    if (!bridge.halReady()) return error.HalUnavailable;
    wireless.initAll();
    wireless.logSummary();
}

pub fn idle() void {
    wireless.pollBle();
    wireless.pollEspNow();
    wireless.pollThread();
    wireless.pollZigbee();
    if (idle_tick % 1 == 0) {
        bridge.logHeartbeat(idle_tick);
    }
    idle_tick +%= 1;
    bridge.delayMs(5000);
}

test "c6 boot smoke" {
    wireless.resetForTest();
    defer wireless.resetForTest();
    try run();
}
