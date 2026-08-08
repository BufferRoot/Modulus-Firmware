//! Tab5 device singleton — fixed arena + wired `Runtime` for C ABI entry.

const std = @import("std");
const build_options = @import("build_options");
const runtime_mod = @import("../runtime/root.zig");
const hooks = runtime_mod.hooks;

const device_stub = struct {
    pub fn configure(_: anytype) void {}
    pub fn spawn() void {}
    pub fn isSpawned() bool {
        return false;
    }
};

const event_dispatch_mod = if (build_options.device_nvs)
    @import("event_dispatch_task.zig")
else
    device_stub;

const system_events = @import("../core/system_events.zig");
const cnc_state = @import("../cnc/cnc_state.zig");
const rx_ring_mod = @import("../cnc/rx_ring.zig");
const dispatcher_mod = @import("../hal/transport/dispatcher.zig");
const device_ui_mod = @import("../ui/device_ui.zig");
const dro_batch = @import("../ui/dro_batch.zig");
const monotonic_ms = @import("../core/monotonic_ms.zig");

const timer_mod = if (build_options.device_nvs)
    struct {
        extern fn esp_timer_get_time() i64;
        pub fn nowUs() u64 {
            return @intCast(esp_timer_get_time());
        }
    }
else
    struct {
        pub fn nowUs() u64 {
            return 0;
        }
    };

const system_task_mod = if (build_options.device_nvs)
    @import("system_task.zig")
else
    struct {
        pub fn configure(_: *const fn (u32) void) void {}
        pub fn spawn() bool {
            return true;
        }
        pub fn isSpawned() bool {
            return true;
        }
    };

const transport_reinit_mod = if (build_options.device_nvs)
    @import("transport_reinit_task.zig")
else
    struct {
        pub fn spawn(_: anytype) void {}
        pub fn request() void {}
        pub const active = std.atomic.Value(bool).init(false);
    };

const probe_engine_mod = @import("../cnc/probe_engine.zig");

/// Boot-time arena only; hot path (`systemTick`) stays heap-free.
var arena_buf: [64 * 1024]u8 align(16) = undefined;
var arena: std.heap.FixedBufferAllocator = undefined;
var rt: runtime_mod.Runtime = undefined;
var boot_ok: bool = false;

/// Staging ring: `serial_rx` (pri 6) pushes, `systemTick` (pri 5) drains —
/// `Engine` stays single-owner (no feed/poll race on Core 1).
var rx_ring: rx_ring_mod.RxRing = .{};

pub fn boot() void {
    arena = std.heap.FixedBufferAllocator.init(&arena_buf);
    rt = runtime_mod.Runtime.init(arena.allocator(), null);
    event_dispatch_mod.configure(&rt.bus);
    event_dispatch_mod.spawn();
    system_task_mod.configure(systemTick);
    hooks.setSpawnHandler(system_task_mod.spawn);
    rt.boot() catch {
        boot_ok = false;
        return;
    };
    transport_reinit_mod.spawn(&rt.transport);
    boot_ok = true;
}

pub fn systemTick(tick_ms: u32) void {
    if (!boot_ok) return;
    rx_ring.drainInto(&rt.drv);
    rt.systemTick(tick_ms);
}

/// Called from `serial_rx` task only — stage bytes, never touch the engine here.
pub fn feedSerial(data: []const u8) void {
    if (!boot_ok) return;
    _ = rx_ring.push(data);
}

pub fn transportConnected() void {
    if (!boot_ok) return;
    rt.drv.onConnect(monotonic_ms.nowMs());
}

pub fn transportDisconnected() void {
    if (!boot_ok) return;
    rt.drv.onDisconnect();
}

export fn modulus_zig_enter_deep_sleep() void {
    if (!boot_ok) return;
    rt.bus.publish(system_events.EVT_SYSTEM_DEEP_SLEEP, &.{});
    rt.power.enterDeepSleep(timer_mod.nowUs());
}

export fn modulus_zig_wake_from_deep_sleep() void {
    if (!boot_ok) return;
    rt.power.wake(timer_mod.nowUs());
}

pub fn fillCncStatus(out: *device_ui_mod.CncStatus) void {
    if (!boot_ok) return;
    const st = rt.drv.status();
    out.state = @intFromEnum(st.state);
    out.connected = if (st.state != .disconnected) @as(u8, 1) else 0;
    out.session = @intFromEnum(rt.drv.engine.session());
    out.mpg_active = if (st.mpg_active) @as(u8, 1) else 0;
    out.jog_mode = @intFromEnum(st.jog_mode);
    out.step_size = @intFromEnum(st.step_size);
    dro_batch.storeWpos(out, dro_batch.packPosition(st.wpos));
    out.feed_rate = st.feed_rate;
    out.feed_ovr = st.overrides.feed;
    out.spindle_ovr = st.overrides.spindle;
    out.wcs = @intFromEnum(st.wcs);
    out.tool_number = st.tool_number;
    out.active_axis = @intFromEnum(st.active_axis);
    out.units_mm = if (st.units_mm) @as(u8, 1) else 0;
    out.spindle_rpm = st.spindle_speed;
    dro_batch.storeMpos(out, dro_batch.packPosition(st.mpos));
    out.homing_block = @intFromEnum(rt.drv.homingBlockReason());
    out.accessories = st.accessories;
    out.sd_percent = st.sd_percent;
    out.line_number = st.line_number;
    out.sd_streaming = if (st.sd_streaming) @as(u8, 1) else 0;
    out.alarm_code = st.alarm_code;
    @memset(&out.sd_file, 0);
    const file = std.mem.sliceTo(&st.sd_file, 0);
    const n = @min(file.len, out.sd_file.len - 1);
    @memcpy(out.sd_file[0..n], file[0..n]);
}

pub fn cmdCycleStart() void {
    if (!boot_ok) return;
    rt.drv.cmdCycleStart();
}

pub fn cmdFeedHold() void {
    if (!boot_ok) return;
    rt.drv.cmdFeedHold();
}

pub fn cmdHomeAll() void {
    if (!boot_ok) return;
    rt.drv.cmdHome(0);
}

pub fn cmdReset() void {
    if (!boot_ok) return;
    rt.drv.cmdReset();
}

pub fn cmdUnlock() void {
    if (!boot_ok) return;
    rt.drv.cmdUnlock();
}

pub fn cmdStop() void {
    if (!boot_ok) return;
    rt.drv.cmdStop();
}

pub fn cmdMpgToggle() void {
    if (!boot_ok) return;
    rt.drv.cmdMpgToggle();
}

pub fn mpgRemote() u8 {
    if (!boot_ok) return 0;
    return if (rt.drv.status().mpg_remote) @as(u8, 1) else 0;
}

pub fn probePin() u8 {
    if (!boot_ok) return 0;
    const PROBE_BIT: u32 = 1; // rt.pin.PROBE (grblHAL |Pn:P)
    return if ((rt.drv.status().pin_state & PROBE_BIT) != 0) @as(u8, 1) else 0;
}

pub fn setJogMode(mode: u8) void {
    if (!boot_ok) return;
    const m: cnc_state.JogMode = switch (mode) {
        1 => .cont,
        2 => .velo,
        else => .step,
    };
    rt.drv.setJogMode(m);
}

pub fn applyDumpEnvelope() u8 {
    if (!boot_ok) return 0;
    return rt.drv.applyDumpEnvelope();
}

pub fn sendGcode(line: []const u8) void {
    if (!boot_ok) return;
    rt.drv.cmdSendGcode(line);
}

pub fn probeStart(cycle: u8) bool {
    if (!boot_ok) return false;
    if (cycle > @intFromEnum(probe_engine_mod.Cycle.tool_setter)) return false;
    return rt.drv.cmdProbeStart(@enumFromInt(cycle));
}

pub fn probeCancel() void {
    if (!boot_ok) return;
    rt.drv.cmdProbeCancel();
}

pub fn probeBusy() bool {
    if (!boot_ok) return false;
    return rt.drv.probeBusy();
}

pub fn reloadMachineLimits() void {
    if (!boot_ok) return;
    rt.drv.limits_loaded = false; // bypass the 1 s reload throttle
    rt.drv.reloadLimits();
}

pub fn setWcs(idx: u8) void {
    if (!boot_ok) return;
    if (idx >= @intFromEnum(cnc_state.WCS._count)) return;
    rt.drv.setWcs(@enumFromInt(idx));
}

pub fn setUnitsMm(mm: bool) void {
    if (!boot_ok) return;
    rt.drv.setUnitsMm(mm);
}

pub fn setStepSize(idx: u8) void {
    if (!boot_ok) return;
    if (idx >= @intFromEnum(cnc_state.StepSize._count)) return;
    rt.drv.setStepSize(@enumFromInt(idx));
}

pub fn cmdFeedOverride(delta: i8) void {
    if (!boot_ok) return;
    rt.drv.cmdFeedOverride(delta);
}

pub fn cmdSpindleOverride(delta: i8) void {
    if (!boot_ok) return;
    rt.drv.cmdSpindleOverride(delta);
}

pub fn cmdHomeAxis(axis_idx: u8) void {
    if (!boot_ok) return;
    rt.drv.cmdHomeAxis(axis_idx);
}

pub fn cmdZeroAxis(axis_idx: u8) void {
    if (!boot_ok) return;
    rt.drv.cmdZeroAxis(axis_idx);
}

pub fn cmdZeroAll() void {
    if (!boot_ok) return;
    rt.drv.cmdZeroAll();
}

pub fn cycleWcs() void {
    if (!boot_ok) return;
    rt.drv.cycleWcs();
}

pub fn setActiveAxis(axis_idx: u8) void {
    if (!boot_ok) return;
    rt.drv.setActiveAxis(axis_idx);
}

pub fn cmdSpindleToggle() void {
    if (!boot_ok) return;
    rt.drv.cmdSpindleToggle();
}

pub fn cmdSpindleCw() void {
    if (!boot_ok) return;
    rt.drv.cmdSpindleCw();
}

pub fn cmdSpindleCcw() void {
    if (!boot_ok) return;
    rt.drv.cmdSpindleCcw();
}

pub fn cmdRunMacro() void {
    if (!boot_ok) return;
    rt.drv.cmdRunMacro();
}

pub fn limitsReload() void {
    if (!boot_ok) return;
    rt.drv.reloadLimits();
}

pub fn settingsDumpBegin() void {
    if (!boot_ok) return;
    rt.drv.cmdRequestSettingsDump();
}

pub fn settingsDumpCancel() void {
    if (!boot_ok) return;
    rt.drv.settingsDumpCancel();
}

pub fn settingsDumpReady() bool {
    if (!boot_ok) return false;
    return rt.drv.settingsDumpReady();
}

pub fn settingsDumpFailed() bool {
    if (!boot_ok) return false;
    return rt.drv.settingsDumpFailed();
}

pub fn settingsDumpCopy(dst: []u8) usize {
    if (!boot_ok) return 0;
    return rt.drv.settingsDumpCopy(dst);
}

pub fn syncEnvelopeToController() void {
    if (!boot_ok) return;
    rt.drv.cmdSyncEnvelopeToController();
}

pub fn maintResetCounters() void {
    if (!boot_ok) return;
    rt.drv.maintResetCounters();
}

pub fn maintFlush() void {
    if (!boot_ok) return;
    rt.drv.maintFlush();
}

pub fn cmdCoolantToggle() void {
    if (!boot_ok) return;
    rt.drv.cmdCoolantToggle();
}

pub fn cmdMistToggle() void {
    if (!boot_ok) return;
    rt.drv.cmdMistToggle();
}

pub fn cmdFanToggle() void {
    if (!boot_ok) return;
    rt.drv.cmdFanToggle();
}

pub fn cmdSingleStep() void {
    if (!boot_ok) return;
    rt.drv.cmdSingleStep();
}

pub fn transportReinit() void {
    if (!boot_ok) return;
    transport_reinit_mod.request();
}

pub fn transportAttachEspNow() void {
    if (!boot_ok) return;
    rt.transport.attachEspNowCOpen();
}

pub fn encoderReloadSettings() void {
    if (!boot_ok) return;
    rt.encoder.reloadJogSettings();
}

pub fn activeTransport() u8 {
    if (!boot_ok) return dispatcher_mod.none_active;
    return rt.transport.activeConnection();
}

pub fn factoryReset() c_int {
    if (!boot_ok) return -1;
    rt.store.factoryReset() catch return -1;
    return 0;
}

pub fn isBootOk() bool {
    return boot_ok;
}

pub fn isSystemTaskSpawned() bool {
    return system_task_mod.isSpawned();
}

pub fn isEventDispatchSpawned() bool {
    return event_dispatch_mod.isSpawned();
}

test "firmware: device runtime boots on host mock nvs" {
    boot();
    try std.testing.expect(isBootOk());
    systemTick(10);
}

test "firmware: rx ring drains on systemTick" {
    boot();
    try std.testing.expectEqual(@as(usize, 5), rx_ring.push("hello"));
    systemTick(1);
    try std.testing.expect(rx_ring.readableSlice() == null);
}

test "firmware: serial feed via ring reaches connected session" {
    boot();
    transportConnected();
    feedSerial("GrblHAL 1.1f\n");
    systemTick(0);
    feedSerial("ok\n");
    systemTick(10);
    var out: device_ui_mod.CncStatus = std.mem.zeroes(device_ui_mod.CncStatus);
    fillCncStatus(&out);
    try std.testing.expect(out.session != 0);
}
