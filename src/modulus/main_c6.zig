//! C6 firmware entry — exported to C shim as `modulus_c6_main`.

const boot = @import("core/c6/boot.zig");
const bridge = @import("hal/bridge_c6.zig");

export fn modulus_c6_main() noreturn {
    boot.run() catch {
        bridge.logInfo("modulus_c6_main failed");
    };
    while (true) {
        boot.idle();
    }
}
