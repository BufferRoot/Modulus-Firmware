//! CNC protocol driver — thread-safe snapshot over grblHAL engine.

const std = @import("std");
const cnc_config = @import("cnc_config.zig");
const cnc_state = @import("cnc_state.zig");
const envelope = @import("envelope.zig");
const settings_dump_mod = @import("settings_dump.zig");
const settings_keys = @import("../core/settings_keys.zig");
const settings_store = @import("../core/settings_store.zig");
const event_bus = @import("../core/event_bus.zig");
const system_events = @import("../core/system_events.zig");
const types = @import("driver_types.zig");
const driver_ops = @import("driver_ops.zig");
const gating = @import("driver_gating.zig");
const session = @import("driver_session.zig");
const commands = @import("driver_commands.zig");
const maintenance = @import("maintenance.zig");
const probe_engine_mod = @import("probe_engine.zig");

pub const Engine = types.Engine;
pub const SendFn = types.SendFn;
pub const HomingBlockReason = types.HomingBlockReason;
pub const Config = types.Config;

pub const Driver = struct {
    engine: Engine = undefined,
    snapshot: cnc_state.MachineStatus = .{},
    mutex: std.atomic.Mutex = .unlocked,
    initialized: bool = false,
    mpg_user_wants_off: bool = false,
    mpg_local_armed: bool = false,
    apply_defaults_pending: bool = false,
    last_evt_state: cnc_state.MachineState = .disconnected,
    store: ?*settings_store.Store = null,
    bus: ?*event_bus.EventBus = null,
    limits: cnc_config.MachineLimits = .{},
    soft_limits: envelope.SoftLimits = .{},
    settings_dump: settings_dump_mod.SettingsDump = .{},
    sync_lines: [4][32]u8 = undefined,
    sync_line_lens: [4]u8 = .{0} ** 4,
    sync_line_count: u8 = 0,
    sync_line_next: u8 = 0,
    sync_pending: bool = false,
    poll_interval_cached: u16 = 250,
    poll_interval_loaded: bool = false,
    poll_interval_reload_ms: u32 = 0,
    limits_loaded: bool = false,
    limits_reload_ms: u32 = 0,
    protocol_supported: bool = true,
    maint: maintenance.Tracker = .{},
    last_maint_tick_ms: u32 = 0,
    probe: probe_engine_mod.Engine = .{},

    pub fn init(cfg: Config) Driver {
        var d: Driver = .{
            .store = cfg.store,
            .bus = cfg.bus,
        };
        d.engine = Engine.init(null);
        d.snapshot.state = .disconnected;
        d.snapshot.active_axis = .x;
        d.snapshot.step_size = .step_0_01;
        if (cfg.store) |s| {
            const jmode = s.getU8(settings_keys.cnc_jmode, 0);
            d.snapshot.jog_mode = switch (jmode) {
                1 => .cont,
                2 => .velo,
                else => .step,
            };
            var wcs_idx = s.getU8(settings_keys.cnc_wcs, 0);
            if (wcs_idx >= @intFromEnum(cnc_state.WCS._count)) wcs_idx = 0;
            d.snapshot.wcs = @enumFromInt(wcs_idx);
            d.snapshot.overrides.feed = driver_ops.clampOverridePct(s.getU8(settings_keys.cnc_feedovr, 100));
            d.snapshot.overrides.rapid = 100;
            d.snapshot.overrides.spindle = driver_ops.clampOverridePct(s.getU8(settings_keys.cnc_spindovr, 100));
            d.snapshot.units_mm = s.getBool(settings_keys.cnc_unit, true);
        } else {
            d.snapshot.jog_mode = .step;
            d.snapshot.overrides = .{ .feed = 100, .rapid = 100, .spindle = 100 };
        }
        d.limits = envelope.loadLimits(cfg.store);
        d.soft_limits = envelope.loadSoftLimits(cfg.store);
        if (cfg.store) |s| d.maint.loadFromStore(s);
        d.reloadProtocol();
        d.initialized = true;
        return d;
    }

    pub fn reloadProtocol(self: *Driver) void {
        var proto: cnc_config.Protocol = .grblhal;
        if (self.store) |s| {
            const idx = s.getU8(settings_keys.cnc_proto, cnc_config.k_default_cnc_proto);
            if (idx < @intFromEnum(cnc_config.Protocol._count)) {
                proto = @enumFromInt(idx);
            }
        }
        self.protocol_supported = cnc_config.protocolImplemented(proto);
        self.engine.setProtocol(proto);
        if (proto == .linux_cnc) {
            var cpw: [16]u8 = undefined;
            var epw: [16]u8 = undefined;
            @memset(&cpw, 0);
            @memset(&epw, 0);
            if (self.store) |s| {
                _ = s.getStr(settings_keys.lcnc_cpw, &cpw);
                _ = s.getStr(settings_keys.lcnc_epw, &epw);
            }
            const connect_pw: []const u8 = if (cpw[0] != 0)
                std.mem.sliceTo(&cpw, 0)
            else
                @import("linuxcnc/session.zig").k_default_connect_pw;
            const enable_pw: []const u8 = if (epw[0] != 0)
                std.mem.sliceTo(&epw, 0)
            else
                @import("linuxcnc/session.zig").k_default_enable_pw;
            self.engine.setLinuxCncPasswords(connect_pw, enable_pw);
        }
        if (proto == .masso) {
            var sn_buf: [32]u8 = undefined;
            @memset(&sn_buf, 0);
            if (self.store) |s| {
                _ = s.getStr(settings_keys.masso_sn, &sn_buf);
            }
            self.engine.setMassoExpectedSerial(parseMassoSerialDigits(&sn_buf));
        }
    }

    fn parseMassoSerialDigits(raw: []const u8) u16 {
        const z = std.mem.indexOfScalar(u8, raw, 0) orelse raw.len;
        const s = raw[0..z];
        if (s.len == 0) return 0;
        // G3-12345 → digits after last '-'; plain "12345" → all digits.
        const slice = if (std.mem.lastIndexOfScalar(u8, s, '-')) |dash|
            s[dash + 1 ..]
        else
            s;
        var n: u32 = 0;
        var any = false;
        for (slice) |c| {
            if (c >= '0' and c <= '9') {
                any = true;
                n = n * 10 + (c - '0');
                if (n > 65535) return 0;
            }
        }
        return if (any) @truncate(n) else 0;
    }

    pub fn reloadLimits(self: *Driver) void {
        const now = self.engine.nowTickMs();
        if (self.limits_loaded and now -% self.limits_reload_ms < 1000) return;
        self.limits = envelope.loadLimits(self.store);
        self.soft_limits = envelope.loadSoftLimits(self.store);
        self.limits_loaded = true;
        self.limits_reload_ms = now;
    }

    pub fn setSendFn(self: *Driver, send_fn: ?SendFn) void {
        gating.lockEngine(self);
        defer gating.unlockEngine(self);
        self.engine.setSendFn(send_fn);
    }

    pub fn poll(self: *Driver, tick_ms: u32) void {
        if (!self.initialized) {
            @branchHint(.unlikely);
            return;
        }

        // Engine poll + interval reload must stay outside snapshot lock: they TX
        // over the transport and can run for many SDIO frames after ESP-NOW connect.
        session.applyPollInterval(self, tick_ms);
        self.engine.poll(tick_ms);
        if (self.probe.busy()) {
            self.probe.poll(tick_ms, self);
        }

        var publish_status = false;
        if (!gating.isConnected(self)) {
            gating.lockSnapshot(self);
            defer gating.unlockSnapshot(self);
            if (self.last_evt_state != .disconnected) {
                self.snapshot.state = .disconnected;
                self.last_evt_state = .disconnected;
                if (self.bus) |b| b.publish(system_events.EVT_CNC_STATUS_UPDATE, "");
            }
            if (self.store) |s| self.maint.flush(s);
            self.last_maint_tick_ms = 0;
            return;
        }

        var maint_snap: cnc_state.MachineStatus = .{};
        var do_maint = false;
        {
            gating.lockSnapshot(self);
            defer gating.unlockSnapshot(self);

            const active_axis = self.snapshot.active_axis;
            const step_size = self.snapshot.step_size;
            const jog_mode = self.snapshot.jog_mode;
            const units_mm = self.snapshot.units_mm;

            self.snapshot = self.engine.status();
            self.snapshot.active_axis = active_axis;
            self.snapshot.step_size = step_size;
            self.snapshot.jog_mode = jog_mode;
            self.snapshot.units_mm = units_mm;

            if (self.snapshot.mpg_remote) {
                self.snapshot.mpg_active = !self.mpg_user_wants_off;
            } else {
                self.snapshot.mpg_active = self.mpg_local_armed;
            }

            if (self.snapshot.state != self.last_evt_state) {
                self.last_evt_state = self.snapshot.state;
                publish_status = true;
            }

            maint_snap = self.snapshot;
            do_maint = true;
        }

        if (do_maint) {
            const dt: u32 = if (self.last_maint_tick_ms == 0) 0 else tick_ms -% self.last_maint_tick_ms;
            self.last_maint_tick_ms = tick_ms;
            self.maint.tick(self.store, self.bus, maint_snap, tick_ms, dt);
        }

        // MUST run with the snapshot lock released: applySessionDefaults()
        // re-acquires lockSnapshot() for its own writes, and the gating mutex is
        // a non-reentrant spin lock. Calling it inside the locked region above
        // self-deadlocks Core 1 (sys_task) on the first poll after the session
        // reaches .ready post-connect -> IDLE1 starved -> task WDT.
        session.applySessionDefaults(self);

        if (publish_status) {
            if (self.bus) |b| b.publish(system_events.EVT_CNC_STATUS_UPDATE, "");
        }
    }

    pub fn feed(self: *Driver, data: []const u8) void {
        self.feedAt(data, self.engine.nowTickMs());
    }

    pub fn feedAt(self: *Driver, data: []const u8, tick_ms: u32) void {
        {
            gating.lockSnapshot(self);
            defer gating.unlockSnapshot(self);
            self.engine.feed(data, tick_ms);
        }
        if (self.probe.busy()) {
            const evt = self.engine.last_event();
            gating.lockSnapshot(self);
            var st = self.engine.status();
            self.probe.onEvent(evt, &st, self);
            gating.unlockSnapshot(self);
        }
        // Sync queue advances may TX — keep outside snapshot lock (Core 0 UI reads).
        session.onRxProcessed(self);
    }

    pub fn onConnect(self: *Driver, tick_ms: u32) void {
        self.reloadProtocol();
        if (!self.protocol_supported) return;
        gating.lockSnapshot(self);
        defer gating.unlockSnapshot(self);
        self.apply_defaults_pending = true;
        self.engine.onConnect(tick_ms);
    }

    pub fn onDisconnect(self: *Driver) void {
        if (self.store) |s| self.maint.flush(s);
        self.last_maint_tick_ms = 0;
        self.probe.cancel();
        gating.lockSnapshot(self);
        defer gating.unlockSnapshot(self);
        self.apply_defaults_pending = false;
        self.engine.onDisconnect();
        self.snapshot.state = .disconnected;
    }

    pub fn maintResetCounters(self: *Driver) void {
        if (self.store) |s| self.maint.resetCounters(s);
    }

    pub fn maintFlush(self: *Driver) void {
        if (self.store) |s| self.maint.flush(s);
    }

    pub fn status(self: *Driver) cnc_state.MachineStatus {
        gating.lockSnapshot(self);
        defer gating.unlockSnapshot(self);
        return self.snapshot;
    }

    pub fn statusLocal(self: *Driver) *cnc_state.MachineStatus {
        comptime {
            if (!@import("builtin").is_test)
                @compileError("statusLocal is test-only; use status() in production");
        }
        return &self.snapshot;
    }

    pub fn enginePtr(self: *Driver) *Engine {
        return &self.engine;
    }

    pub fn lockSnapshot(self: *Driver) void {
        gating.lockSnapshot(self);
    }

    pub fn unlockSnapshot(self: *Driver) void {
        gating.unlockSnapshot(self);
    }

    pub fn isReady(self: *Driver) bool {
        return gating.isReady(self);
    }

    pub fn canSendCommands(self: *Driver) bool {
        return gating.canSendCommands(self);
    }

    pub fn isMachineBusy(self: *Driver) bool {
        return gating.isMachineBusy(self);
    }

    pub fn homingBlockReason(self: *Driver) HomingBlockReason {
        return gating.homingBlockReason(self);
    }

    pub fn canJog(self: *Driver) bool {
        return gating.canJog(self);
    }

    pub fn cmdCycleStart(self: *Driver) void {
        commands.cmdCycleStart(self);
    }

    pub fn cmdFeedHold(self: *Driver) void {
        commands.cmdFeedHold(self);
    }

    pub fn cmdHome(self: *Driver, axis: u8) void {
        commands.cmdHome(self, axis);
    }

    pub fn cmdHomeAxis(self: *Driver, axis_idx: u8) void {
        commands.cmdHomeAxis(self, axis_idx);
    }

    pub fn cmdZeroAxis(self: *Driver, axis_idx: u8) void {
        commands.cmdZeroAxis(self, axis_idx);
    }

    pub fn cmdZeroAll(self: *Driver) void {
        commands.cmdZeroAll(self);
    }

    pub fn cycleWcs(self: *Driver) void {
        commands.cycleWcs(self);
    }

    pub fn setActiveAxis(self: *Driver, axis_idx: u8) void {
        commands.setActiveAxis(self, axis_idx);
    }

    pub fn cmdUnlock(self: *Driver) void {
        commands.cmdUnlock(self);
    }

    pub fn cmdReset(self: *Driver) void {
        commands.cmdReset(self);
    }

    pub fn cmdSendGcode(self: *Driver, line: []const u8) void {
        commands.cmdSendGcode(self, line);
    }

    pub fn cmdRequestSettingsDump(self: *Driver) void {
        commands.cmdRequestSettingsDump(self);
    }

    pub fn settingsDumpCancel(self: *Driver) void {
        commands.settingsDumpCancel(self);
    }

    pub fn settingsDumpReady(self: *const Driver) bool {
        return commands.settingsDumpReady(self);
    }

    pub fn settingsDumpFailed(self: *const Driver) bool {
        return commands.settingsDumpFailed(self);
    }

    pub fn settingsDumpCopy(self: *const Driver, dst: []u8) usize {
        return commands.settingsDumpCopy(self, dst);
    }

    pub fn applyDumpEnvelope(self: *Driver) u8 {
        return commands.applyDumpEnvelope(self);
    }

    pub fn cmdSyncEnvelopeToController(self: *Driver) void {
        commands.cmdSyncEnvelopeToController(self);
    }

    pub fn cmdStop(self: *Driver) void {
        commands.cmdStop(self);
    }

    pub fn cmdEstop(self: *Driver) void {
        commands.cmdEstop(self);
    }

    pub fn cmdRapidOverride(self: *Driver, pct: u8) void {
        commands.cmdRapidOverride(self, pct);
    }

    pub fn cmdJog(self: *Driver, axis: u8, distance: f32, feed_rate: f32) void {
        commands.cmdJog(self, axis, distance, feed_rate);
    }

    pub fn cmdJogCancel(self: *Driver) void {
        commands.cmdJogCancel(self);
    }

    pub fn cmdFeedOverride(self: *Driver, delta: i8) void {
        commands.cmdFeedOverride(self, delta);
    }

    pub fn cmdSpindleOverride(self: *Driver, delta: i8) void {
        commands.cmdSpindleOverride(self, delta);
    }

    pub fn cmdSpindleToggle(self: *Driver) void {
        commands.cmdSpindleToggle(self);
    }

    pub fn cmdSpindleCw(self: *Driver) void {
        commands.cmdSpindleCw(self);
    }

    pub fn cmdSpindleCcw(self: *Driver) void {
        commands.cmdSpindleCcw(self);
    }

    pub fn cmdRunMacro(self: *Driver) void {
        commands.cmdRunMacro(self);
    }

    pub fn cmdCoolantToggle(self: *Driver) void {
        commands.cmdCoolantToggle(self);
    }

    pub fn cmdMistToggle(self: *Driver) void {
        commands.cmdMistToggle(self);
    }

    pub fn cmdFanToggle(self: *Driver) void {
        commands.cmdFanToggle(self);
    }

    pub fn cmdSingleStep(self: *Driver) void {
        commands.cmdSingleStep(self);
    }

    pub fn cmdMpgToggle(self: *Driver) void {
        commands.cmdMpgToggle(self);
    }

    pub fn setJogMode(self: *Driver, mode: cnc_state.JogMode) void {
        commands.setJogMode(self, mode);
    }

    pub fn setUnitsMm(self: *Driver, mm: bool) void {
        commands.setUnitsMm(self, mm);
    }

    pub fn setStepSize(self: *Driver, size: cnc_state.StepSize) void {
        commands.setStepSize(self, size);
    }

    pub fn setWcs(self: *Driver, w: cnc_state.WCS) void {
        commands.setWcs(self, w);
    }

    pub fn cmdProbeStart(self: *Driver, cycle: probe_engine_mod.Cycle) bool {
        return commands.cmdProbeStart(self, cycle);
    }

    pub fn cmdProbeCancel(self: *Driver) void {
        commands.cmdProbeCancel(self);
    }

    pub fn probeBusy(self: *const Driver) bool {
        return commands.probeBusy(self);
    }
};

test {
    _ = @import("driver_tests.zig");
}
