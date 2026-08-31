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
const job_runner = @import("job_runner.zig");

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
        rt.deinit();
        return;
    };
    transport_reinit_mod.spawn(&rt.transport);
    boot_ok = true;
}

pub fn systemTick(tick_ms: u32) void {
    if (!boot_ok) return;
    rx_ring.drainInto(&rt.drv);
    rt.systemTick(tick_ms);
    // After the parse drain so this tick's acks are already counted.
    g_job.pump(&rt.drv, tick_ms);
}

// --- G-code job streaming (pendant acts as sender over the MPG port) -------
//
// State lives here, not in the UI: the pump runs on Core 1 at ~100 Hz and must
// keep running while the operator is on any screen.

var g_job: job_runner.JobRunner = .{};

/// Diagnostics go through esp_rom_printf, NOT std.log.
///
/// This target has no `logFn` in std_options and sets
/// `std_options_debug_io = std.Io.failing`, so any `std.log.*` call panics with
/// "reached unreachable code". A std.log.warn added here for job diagnostics
/// crashed the pendant the instant Load was pressed.
extern "c" fn esp_rom_printf(fmt: [*:0]const u8, ...) c_int;

/// Arm a USB catalog entry. Does not move the machine.
pub fn jobLoadUsb(index: u8) bool {
    const ok = g_job.load(index);
    _ = esp_rom_printf(
        "[job] loadUsb idx=%d lines=%d ok=%d\n",
        @as(c_int, index),
        @as(c_int, @intCast(g_job.stream.total_lines)),
        @as(c_int, if (ok) 1 else 0),
    );
    return ok;
}

/// Cycle Start with a job armed: claim MPG, then stream once `|MPG:1` lands.
pub fn jobStart() bool {
    if (!boot_ok) return false;
    const st = blk: {
        rt.drv.lockSnapshot();
        defer rt.drv.unlockSnapshot();
        break :blk rt.drv.snapshot.state;
    };
    const idle = st == .idle;
    const ok = g_job.requestStart(&rt.drv, monotonic_ms.nowMs(), idle);
    _ = esp_rom_printf(
        "[job] start state=%d idle=%d stream=%d supported=%d ok=%d\n",
        @as(c_int, @intFromEnum(st)),
        @as(c_int, if (idle) 1 else 0),
        @as(c_int, @intFromEnum(g_job.stream.state)),
        @as(c_int, if (rt.drv.engine.supportsJobStream()) 1 else 0),
        @as(c_int, if (ok) 1 else 0),
    );
    return ok;
}

pub fn jobLogArmed(armed: bool) void {
    _ = esp_rom_printf("[job] cycleStart armed=%d\n", @as(c_int, if (armed) 1 else 0));
}

pub fn jobHold() void {
    g_job.stream.hold();
    rt.drv.engine.sendFeedHold();
}

pub fn jobResume() void {
    g_job.stream.unhold(monotonic_ms.nowMs());
    rt.drv.engine.sendCycleStart();
}

/// Abort: soft reset stops motion, then the pump releases MPG.
pub fn jobAbort() void {
    g_job.stream.abort();
    rt.drv.engine.sendReset();
}

pub const JobStatus = struct {
    active: bool,
    per_mille: u16,
    state: job_runner.State,
    fault: job_runner.Fault,
    /// `.complete` or `.aborted` from the job that just finished.
    terminal: job_runner.State,
};

pub fn jobStatus() JobStatus {
    return .{
        .active = g_job.isActive(),
        .per_mille = g_job.progressPerMille(),
        .state = g_job.state(),
        .fault = g_job.fault(),
        .terminal = g_job.lastTerminal(),
    };
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
    // Rails may have been dropped/restored around sleep — force the next
    // prefs flush to re-drive them instead of trusting the change cache.
    // device_ui_bridge is freestanding-only; this file also builds for host.
    if (comptime @import("builtin").os.tag == .freestanding) {
        @import("device_ui_bridge.zig").invalidatePowerCache();
    }
}

pub fn fillCncStatus(out: *device_ui_mod.CncStatus) void {
    if (!boot_ok) return;
    const st = rt.drv.status();
    out.state = @intFromEnum(st.state);
    out.connected = if (rt.drv.engine.session() != .disconnected) @as(u8, 1) else 0;
    out.session = @intFromEnum(rt.drv.engine.session());
    out.mpg_active = if (st.mpg_active) @as(u8, 1) else 0;
    out.jog_mode = @intFromEnum(st.jog_mode);
    out.step_size = @intFromEnum(st.step_size);
    dro_batch.storeWpos(out, dro_batch.packPosition(st.wpos));
    out.feed_rate = st.feed_rate;
    out.feed_ovr = st.overrides.feed;
    out.spindle_ovr = st.overrides.spindle;
    out.rapid_ovr = st.overrides.rapid;
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

pub fn cmdRapidOverride(pct: u8) void {
    if (!boot_ok) return;
    rt.drv.cmdRapidOverride(pct);
}

pub fn cmdHomeAxis(axis_idx: u8) void {
    if (!boot_ok) return;
    rt.drv.cmdHomeAxis(axis_idx);
}

pub fn cmdZeroAxis(axis_idx: u8) bool {
    if (!boot_ok) return false;
    return rt.drv.cmdZeroAxis(axis_idx);
}

pub fn cmdZeroAll() bool {
    if (!boot_ok) return false;
    return rt.drv.cmdZeroAll();
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

pub const MaintMeters = struct {
    travel_mm: u32 = 0,
    spindle_sec: u32 = 0,
    run_sec: u32 = 0,
};

/// Live Driver.maint → settings Machine tab (not host tickMaint soft accrual).
pub fn maintMeters() MaintMeters {
    if (!boot_ok) return .{};
    return .{
        .travel_mm = rt.drv.maint.travel_mm,
        .spindle_sec = rt.drv.maint.spindle_sec,
        .run_sec = rt.drv.maint.run_sec,
    };
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
