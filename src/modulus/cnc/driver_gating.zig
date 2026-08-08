//! CNC driver session gating + snapshot mutex.

const std = @import("std");
const build_options = @import("build_options");
const types = @import("driver_types.zig");

const yield_impl = if (build_options.device_nvs)
    struct {
        extern fn vTaskDelay(ticks: u32) void;
        fn yield() void {
            vTaskDelay(1);
        }
    }
else
    struct {
        fn yield() void {}
    };

pub fn lockSnapshot(drv: anytype) void {
    // Bounded spin, then block one tick. A pure spin deadlocks on same-core
    // priority inversion: a higher-priority task (evt_dispatch pri 10, estop
    // poll) spinning here starves a preempted lower-priority holder (taskLVGL
    // pri 5) on the same core forever -> task WDT. Cross-core contention
    // resolves within the spin budget; the yield path is the cold escape.
    var spins: u32 = 0;
    while (!drv.mutex.tryLock()) {
        std.atomic.spinLoopHint();
        spins += 1;
        if (spins >= 512) {
            @branchHint(.cold);
            spins = 0;
            yield_impl.yield();
        }
    }
}

pub fn unlockSnapshot(drv: anytype) void {
    drv.mutex.unlock();
}

pub const lockEngine = lockSnapshot;
pub const unlockEngine = unlockSnapshot;

pub fn isConnected(drv: anytype) bool {
    return drv.engine.session() != .disconnected;
}

pub fn isReady(drv: anytype) bool {
    const st = drv.engine.session();
    return st == .ready or st == .locked;
}

pub fn canJog(drv: anytype) bool {
    // Masso Link has no jog in RE'd protocol — never arm handwheel.
    if (drv.engine.active == .masso) return false;
    if (!isConnected(drv)) return false;
    const st = drv.engine.session();
    if (st == .ready or st == .locked) return true;
    if (st == .mpg_blocked) {
        lockSnapshot(drv);
        defer unlockSnapshot(drv);
        return drv.snapshot.mpg_active;
    }
    return false;
}

pub fn canJogInternal(drv: anytype) bool {
    return canJog(drv);
}

pub fn homingBlockReason(drv: anytype) types.HomingBlockReason {
    lockSnapshot(drv);
    const state = drv.snapshot.state;
    unlockSnapshot(drv);
    if (state == .disconnected or !isConnected(drv)) return .disconnected;
    if (state == .alarm) return .alarm;
    if (state == .run or state == .jog or state == .hold) return .busy;
    if (!canSendCommands(drv)) return .disconnected;
    return .none;
}

pub fn canSendCommands(drv: anytype) bool {
    if (!drv.protocol_supported) return false;
    if (!isConnected(drv)) return false;
    const st = drv.engine.session();
    return st == .ready or st == .locked or st == .mpg_blocked;
}

pub fn isMachineBusy(drv: anytype) bool {
    lockSnapshot(drv);
    defer unlockSnapshot(drv);
    const st = drv.snapshot.state;
    return st == .run or st == .jog or st == .hold;
}
