//! Pendant-side maintenance meters — travel mm, spindle-on sec, RUN-state sec.
//! Accrues from live `MachineStatus` (no controller ODO required).
//! ponytail: fixed state on Driver; no heap; NVS flush ≤30 s.

const std = @import("std");
const cnc_state = @import("cnc_state.zig");
const settings_keys = @import("../core/settings_keys.zig");
const settings_store = @import("../core/settings_store.zig");
const event_bus = @import("../core/event_bus.zig");
const system_events = @import("../core/system_events.zig");

pub const persist_interval_ms: u32 = 30_000;
/// Reject Δmpos larger than this (mm) as WCS/reconnect glitch.
pub const max_step_mm: f32 = 50.0;

pub const Meter = enum(u8) {
    travel = 0,
    spindle = 1,
    run = 2,
};

pub const Tracker = struct {
    travel_mm: u32 = 0,
    travel_x_mm: u32 = 0,
    travel_y_mm: u32 = 0,
    travel_z_mm: u32 = 0,
    travel_a_deg: u32 = 0,
    travel_b_deg: u32 = 0,
    travel_c_deg: u32 = 0,
    spindle_sec: u32 = 0,
    run_sec: u32 = 0,
    spindle_ms_accum: u32 = 0,
    run_ms_accum: u32 = 0,
    last_mpos: ?cnc_state.Position = null,
    dirty: bool = false,
    last_persist_ms: u32 = 0,
    /// 0 = none, 1 = warn%, 2 = 100% due — per meter.
    warn_latched: [3]u8 = .{ 0, 0, 0 },
    loaded: bool = false,

    pub fn loadFromStore(self: *Tracker, store: *settings_store.Store) void {
        self.travel_mm = readU32(store, settings_keys.cnc_odo_h, settings_keys.cnc_odo_l);
        self.travel_x_mm = readU32(store, settings_keys.cnc_odx_h, settings_keys.cnc_odx_l);
        self.travel_y_mm = readU32(store, settings_keys.cnc_ody_h, settings_keys.cnc_ody_l);
        self.travel_z_mm = readU32(store, settings_keys.cnc_odz_h, settings_keys.cnc_odz_l);
        self.travel_a_deg = readU32(store, settings_keys.cnc_oda_h, settings_keys.cnc_oda_l);
        self.travel_b_deg = readU32(store, settings_keys.cnc_odb_h, settings_keys.cnc_odb_l);
        self.travel_c_deg = readU32(store, settings_keys.cnc_odc_h, settings_keys.cnc_odc_l);
        self.spindle_sec = readU32(store, settings_keys.cnc_sph_h, settings_keys.cnc_sph_l);
        self.run_sec = readU32(store, settings_keys.cnc_run_h, settings_keys.cnc_run_l);
        self.spindle_ms_accum = 0;
        self.run_ms_accum = 0;
        self.warn_latched = .{ 0, 0, 0 };
        self.dirty = false;
        self.loaded = true;
        self.last_mpos = null;
    }

    pub fn flush(self: *Tracker, store: *settings_store.Store) void {
        if (!self.dirty) return;
        store.beginBatch();
        defer store.endBatch();
        writeU32(store, settings_keys.cnc_odo_h, settings_keys.cnc_odo_l, self.travel_mm);
        writeU32(store, settings_keys.cnc_odx_h, settings_keys.cnc_odx_l, self.travel_x_mm);
        writeU32(store, settings_keys.cnc_ody_h, settings_keys.cnc_ody_l, self.travel_y_mm);
        writeU32(store, settings_keys.cnc_odz_h, settings_keys.cnc_odz_l, self.travel_z_mm);
        writeU32(store, settings_keys.cnc_oda_h, settings_keys.cnc_oda_l, self.travel_a_deg);
        writeU32(store, settings_keys.cnc_odb_h, settings_keys.cnc_odb_l, self.travel_b_deg);
        writeU32(store, settings_keys.cnc_odc_h, settings_keys.cnc_odc_l, self.travel_c_deg);
        writeU32(store, settings_keys.cnc_sph_h, settings_keys.cnc_sph_l, self.spindle_sec);
        writeU32(store, settings_keys.cnc_run_h, settings_keys.cnc_run_l, self.run_sec);
        self.dirty = false;
    }

    pub fn resetCounters(self: *Tracker, store: *settings_store.Store) void {
        self.travel_mm = 0;
        self.travel_x_mm = 0;
        self.travel_y_mm = 0;
        self.travel_z_mm = 0;
        self.travel_a_deg = 0;
        self.travel_b_deg = 0;
        self.travel_c_deg = 0;
        self.spindle_sec = 0;
        self.run_sec = 0;
        self.spindle_ms_accum = 0;
        self.run_ms_accum = 0;
        self.warn_latched = .{ 0, 0, 0 };
        self.last_mpos = null;
        self.dirty = true;
        self.flush(store);
    }

    /// Accrue meters for `dt_ms`. Call only while connected.
    pub fn tick(
        self: *Tracker,
        store: ?*settings_store.Store,
        bus: ?*event_bus.EventBus,
        status: cnc_state.MachineStatus,
        now_ms: u32,
        dt_ms: u32,
    ) void {
        if (dt_ms == 0 or dt_ms > 5000) {
            self.last_mpos = status.mpos;
            return;
        }
        if (store) |s| {
            if (!self.loaded) self.loadFromStore(s);
        }

        const moving = switch (status.state) {
            // Accrue on any active motion state. Also idle: LCNC/Mach3 often leave
            // state=idle while jogging (no JOG token) — still count valid Δmpos.
            .disconnected, .alarm, .sleep, .door => false,
            else => true,
        };
        if (moving) {
            if (self.last_mpos) |prev| {
                // Path + linear axes (mm). Do not mix rotary degrees into path.
                const dx = status.mpos.x - prev.x;
                const dy = status.mpos.y - prev.y;
                const dz = status.mpos.z - prev.z;
                const dist = @sqrt(dx * dx + dy * dy + dz * dz);
                if (dist > 0 and dist <= max_step_mm) {
                    const add: u32 = @intFromFloat(@min(dist, 65535.0));
                    self.travel_mm = saturatingAdd(self.travel_mm, add);
                    const ax: u32 = @intFromFloat(@min(@abs(dx), 65535.0));
                    const ay: u32 = @intFromFloat(@min(@abs(dy), 65535.0));
                    const az: u32 = @intFromFloat(@min(@abs(dz), 65535.0));
                    if (ax > 0) self.travel_x_mm = saturatingAdd(self.travel_x_mm, ax);
                    if (ay > 0) self.travel_y_mm = saturatingAdd(self.travel_y_mm, ay);
                    if (az > 0) self.travel_z_mm = saturatingAdd(self.travel_z_mm, az);
                    self.dirty = true;
                }
                // Rotary A/B/C: absolute angular travel (degrees).
                if (accrueAbsDelta(&self.travel_a_deg, status.mpos.a - prev.a)) self.dirty = true;
                if (accrueAbsDelta(&self.travel_b_deg, status.mpos.b - prev.b)) self.dirty = true;
                if (accrueAbsDelta(&self.travel_c_deg, status.mpos.c - prev.c)) self.dirty = true;
            }
        }
        self.last_mpos = status.mpos;

        const spindle_on = status.spindle_dir != .stop or
            status.spindle_speed > 0 or
            status.spindle_actual > 0;
        if (spindle_on) {
            self.spindle_ms_accum += dt_ms;
            while (self.spindle_ms_accum >= 1000) {
                self.spindle_ms_accum -= 1000;
                self.spindle_sec = saturatingAdd(self.spindle_sec, 1);
                self.dirty = true;
            }
        }

        if (status.state == .run) {
            self.run_ms_accum += dt_ms;
            while (self.run_ms_accum >= 1000) {
                self.run_ms_accum -= 1000;
                self.run_sec = saturatingAdd(self.run_sec, 1);
                self.dirty = true;
            }
        }

        if (store) |s| {
            self.checkWarn(s, bus);
            if (self.dirty and (self.last_persist_ms == 0 or now_ms -% self.last_persist_ms >= persist_interval_ms)) {
                self.flush(s);
                self.last_persist_ms = now_ms;
            }
        }
    }

    pub fn checkWarn(self: *Tracker, store: *settings_store.Store, bus: ?*event_bus.EventBus) void {
        const warn_pct = std.math.clamp(store.getU8(settings_keys.cnc_mnt_warn, 90), @as(u8, 10), @as(u8, 100));

        const odo_m = store.getU16(settings_keys.cnc_mnt_odo, 500);
        if (odo_m > 0) {
            const limit_mm: u64 = @as(u64, odo_m) * 1000;
            self.evalMeter(.travel, self.travel_mm, limit_mm, warn_pct, bus);
        } else {
            self.warn_latched[@intFromEnum(Meter.travel)] = 0;
        }

        const sph_h = store.getU16(settings_keys.cnc_mnt_sph, 100);
        if (sph_h > 0) {
            const limit_sec: u64 = @as(u64, sph_h) * 3600;
            self.evalMeter(.spindle, self.spindle_sec, limit_sec, warn_pct, bus);
        } else {
            self.warn_latched[@intFromEnum(Meter.spindle)] = 0;
        }

        const run_h = store.getU16(settings_keys.cnc_mnt_run, 200);
        if (run_h > 0) {
            const limit_sec: u64 = @as(u64, run_h) * 3600;
            self.evalMeter(.run, self.run_sec, limit_sec, warn_pct, bus);
        } else {
            self.warn_latched[@intFromEnum(Meter.run)] = 0;
        }
    }

    fn evalMeter(
        self: *Tracker,
        meter: Meter,
        value: u32,
        limit: u64,
        warn_pct: u8,
        bus: ?*event_bus.EventBus,
    ) void {
        if (limit == 0) return;
        const idx = @intFromEnum(meter);
        const warn_at: u64 = limit * @as(u64, warn_pct) / 100;
        const v: u64 = value;
        var level: u8 = 0;
        if (v >= limit) {
            level = 2;
        } else if (v >= warn_at) {
            level = 1;
        }
        if (level > self.warn_latched[idx]) {
            self.warn_latched[idx] = level;
            std.log.scoped(.cnc).warn("maintenance meter={d} level={d}", .{ @intFromEnum(meter), level });
            if (bus) |b| {
                const payload = [_]u8{@intFromEnum(meter)};
                b.publish(system_events.EVT_CNC_MAINT_WARN, &payload);
            }
        }
    }
};

pub fn readU32(store: *settings_store.Store, key_hi: []const u8, key_lo: []const u8) u32 {
    const hi = store.getU16(key_hi, 0);
    const lo = store.getU16(key_lo, 0);
    return (@as(u32, hi) << 16) | lo;
}

pub fn writeU32(store: *settings_store.Store, key_hi: []const u8, key_lo: []const u8, val: u32) void {
    store.persistU16(key_hi, @truncate(val >> 16));
    store.persistU16(key_lo, @truncate(val));
}

fn saturatingAdd(a: u32, b: u32) u32 {
    const sum = @as(u64, a) + b;
    return if (sum > std.math.maxInt(u32)) std.math.maxInt(u32) else @intCast(sum);
}

/// Accrue |delta| when within glitch gate. Returns true if meter changed.
fn accrueAbsDelta(meter: *u32, delta: f32) bool {
    const ad = @abs(delta);
    if (ad <= 0 or ad > max_step_mm) return false;
    const add: u32 = @intFromFloat(@min(ad, 65535.0));
    if (add == 0) return false;
    meter.* = saturatingAdd(meter.*, add);
    return true;
}

/// Progress 0–100 for UI; null when interval disabled.
pub fn progressPct(value: u32, limit: u64) ?u8 {
    if (limit == 0) return null;
    const lim_u32: u32 = @intCast(@min(limit, std.math.maxInt(u32)));
    return @intCast(@min(100, (value * 100) / lim_u32));
}

test "cnc: maintenance travel accrues and rejects glitch" {
    var t: Tracker = .{};
    const idle = cnc_state.MachineStatus{ .state = .idle, .mpos = .{ .x = 0, .y = 0, .z = 0 } };
    t.tick(null, null, idle, 1000, 250);
    var jog = idle;
    jog.state = .jog;
    jog.mpos = .{ .x = 3, .y = 4, .z = 0 }; // 5 mm
    t.tick(null, null, jog, 1250, 250);
    try std.testing.expectEqual(@as(u32, 5), t.travel_mm);
    jog.mpos = .{ .x = 200, .y = 0, .z = 0 }; // glitch
    t.tick(null, null, jog, 1500, 250);
    try std.testing.expectEqual(@as(u32, 5), t.travel_mm);
}

test "cnc: maintenance accrues rotary A/B/C separately from path" {
    var t: Tracker = .{};
    var st = cnc_state.MachineStatus{ .state = .jog, .mpos = .{} };
    t.tick(null, null, st, 1000, 250);
    st.mpos = .{ .a = 10, .b = 5, .c = 2 };
    t.tick(null, null, st, 1250, 250);
    try std.testing.expectEqual(@as(u32, 0), t.travel_mm);
    try std.testing.expectEqual(@as(u32, 10), t.travel_a_deg);
    try std.testing.expectEqual(@as(u32, 5), t.travel_b_deg);
    try std.testing.expectEqual(@as(u32, 2), t.travel_c_deg);
}

test "cnc: maintenance spindle and run gating" {
    var t: Tracker = .{};
    var st = cnc_state.MachineStatus{ .state = .idle, .spindle_dir = .cw, .spindle_speed = 1000 };
    t.tick(null, null, st, 1000, 1000);
    try std.testing.expectEqual(@as(u32, 1), t.spindle_sec);
    try std.testing.expectEqual(@as(u32, 0), t.run_sec);
    st.state = .run;
    t.tick(null, null, st, 2000, 1000);
    try std.testing.expectEqual(@as(u32, 2), t.spindle_sec);
    try std.testing.expectEqual(@as(u32, 1), t.run_sec);
    t.tick(null, null, st, 2250, 250);
    t.tick(null, null, st, 2500, 250);
    t.tick(null, null, st, 2750, 250);
    t.tick(null, null, st, 3000, 250);
    try std.testing.expectEqual(@as(u32, 3), t.spindle_sec);
    try std.testing.expectEqual(@as(u32, 2), t.run_sec);
}

test "cnc: maintenance warn latch and interval off" {
    var store = settings_store.Store.init(std.testing.allocator);
    defer store.deinit();
    store.persistU16(settings_keys.cnc_mnt_odo, 1); // 1 m = 1000 mm
    store.persistU8(settings_keys.cnc_mnt_warn, 90);
    store.persistU16(settings_keys.cnc_mnt_sph, 0);
    store.persistU16(settings_keys.cnc_mnt_run, 0);

    var bus = event_bus.EventBus.init();
    defer bus.deinit();
    var got: u8 = 0xFF;
    const Ctx = struct {
        var out: *u8 = undefined;
        fn cb(id: event_bus.EventId, data: []const u8) void {
            if (id == system_events.EVT_CNC_MAINT_WARN and data.len > 0) out.* = data[0];
        }
    };
    Ctx.out = &got;
    try bus.subscribe(system_events.EVT_CNC_MAINT_WARN, Ctx.cb);

    var t: Tracker = .{};
    t.loadFromStore(&store);
    t.travel_mm = 900;
    t.dirty = true;
    t.checkWarn(&store, &bus);
    bus.dispatchAll();
    try std.testing.expectEqual(@as(u8, @intFromEnum(Meter.travel)), got);
    try std.testing.expectEqual(@as(u8, 1), t.warn_latched[0]);

    got = 0xFF;
    t.checkWarn(&store, &bus);
    bus.dispatchAll();
    try std.testing.expectEqual(@as(u8, 0xFF), got);

    t.travel_mm = 1000;
    t.checkWarn(&store, &bus);
    bus.dispatchAll();
    try std.testing.expectEqual(@as(u8, @intFromEnum(Meter.travel)), got);
    try std.testing.expectEqual(@as(u8, 2), t.warn_latched[0]);
}

test "cnc: maintenance u32 hi/lo roundtrip" {
    var store = settings_store.Store.init(std.testing.allocator);
    defer store.deinit();
    writeU32(&store, settings_keys.cnc_odo_h, settings_keys.cnc_odo_l, 0x0001_2345);
    try std.testing.expectEqual(@as(u32, 0x0001_2345), readU32(&store, settings_keys.cnc_odo_h, settings_keys.cnc_odo_l));
}
