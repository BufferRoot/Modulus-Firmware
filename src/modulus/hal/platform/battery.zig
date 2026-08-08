//! Battery HAL — INA226 / NP-F curve host stub.

const std = @import("std");
const build_options = @import("build_options");
const settings_keys = @import("../../core/settings_keys.zig");
const settings_store = @import("../../core/settings_store.zig");
const event_bus = @import("../../core/event_bus.zig");
const system_events = @import("../../core/system_events.zig");
const idf_battery_mod = if (build_options.device_nvs)
    @import("idf_battery.zig")
else
    struct {};

pub const ChargeState = enum(u8) {
    discharging = 0,
    charging,
    full,
    no_battery,
};

pub const Status = struct {
    voltage: f32 = 0,
    current: f32 = 0,
    power: f32 = 0,
    percent: u8 = 0,
    charge_state: ChargeState = .discharging,
    cpu_temp: f32 = 0,
    rate_mA: f32 = 0,
    time_to_empty: i32 = -1,
    time_to_full: i32 = -1,
};

const VoltPct = struct { v: f32, pct: u8 };
const npf_curve = [_]VoltPct{
    .{ .v = 8.40, .pct = 100 },
    .{ .v = 8.20, .pct = 90 },
    .{ .v = 8.00, .pct = 80 },
    .{ .v = 7.80, .pct = 70 },
    .{ .v = 7.60, .pct = 60 },
    .{ .v = 7.40, .pct = 50 },
    .{ .v = 7.20, .pct = 40 },
    .{ .v = 7.00, .pct = 30 },
    .{ .v = 6.80, .pct = 20 },
    .{ .v = 6.40, .pct = 10 },
    .{ .v = 6.00, .pct = 0 },
};

pub fn voltageToPercent(v: f32) u8 {
    if (v >= npf_curve[0].v) return 100;
    if (v <= npf_curve[npf_curve.len - 1].v) return 0;
    var i: usize = 0;
    while (i + 1 < npf_curve.len) : (i += 1) {
        if (v >= npf_curve[i + 1].v and v <= npf_curve[i].v) {
            const hi = npf_curve[i];
            const lo = npf_curve[i + 1];
            const t = (v - lo.v) / (hi.v - lo.v);
            const raw = @as(f32, @floatFromInt(lo.pct)) + t * @as(f32, @floatFromInt(hi.pct - lo.pct));
            return @trunc(raw);
        }
    }
    return 0;
}

pub const Battery = struct {
    store: ?*settings_store.Store = null,
    bus: ?*event_bus.EventBus = null,
    status: Status = .{},
    low_warn_pct: u8 = 15,
    adaptive: bool = false,
    charge_enabled: bool = true,
    quick_charge: bool = false,
    ext5v_enabled: bool = true,
    usb5v_enabled: bool = false,
    low_warned: bool = false,

    pub fn init(self: *Battery, store: *settings_store.Store) void {
        self.store = store;
        self.low_warn_pct = store.getU8(settings_keys.bat_warn, 15);
        self.adaptive = store.getBool(settings_keys.bat_adapt, false);
        self.charge_enabled = store.getBool(settings_keys.chg_en, true);
        self.quick_charge = store.getBool(settings_keys.qc, false);
        self.ext5v_enabled = store.getBool(settings_keys.ext5v, true);
        self.usb5v_enabled = store.getBool(settings_keys.usb5v, false);
        if (build_options.device_nvs) {
            idf_battery_mod.hwInit();
            idf_battery_mod.syncStatus(&self.status);
        } else {
            self.status = .{ .voltage = 8.0, .percent = voltageToPercent(8.0) };
        }
    }

    pub fn bindBus(self: *Battery, bus: *event_bus.EventBus) void {
        self.bus = bus;
    }

    pub fn poll(self: *Battery) void {
        if (build_options.device_nvs) {
            idf_battery_mod.syncStatus(&self.status);
        }
        self.checkLowWarn();
    }

    fn checkLowWarn(self: *Battery) void {
        if (self.low_warn_pct == 0) return;
        const discharging = self.status.charge_state == .discharging;
        if (discharging and self.status.percent <= self.low_warn_pct) {
            if (!self.low_warned) {
                self.low_warned = true;
                if (self.bus) |b| {
                    const pct = self.status.percent;
                    b.publish(system_events.EVT_BATTERY_LOW, &.{pct});
                }
            }
        } else {
            self.low_warned = false;
        }
    }

    pub fn getStatus(self: *const Battery) Status {
        return self.status;
    }

    pub fn setSample(self: *Battery, voltage: f32, current: f32) void {
        self.status.voltage = voltage;
        self.status.current = current;
        self.status.power = voltage * current;
        self.status.percent = voltageToPercent(voltage);
        self.status.rate_mA = current * 1000;
    }

    pub fn setLowWarnPct(self: *Battery, pct: u8) void {
        self.low_warn_pct = pct;
        if (self.store) |s| s.persistU8(settings_keys.bat_warn, pct);
    }

    pub fn setAdaptive(self: *Battery, on: bool) void {
        self.adaptive = on;
        if (self.store) |s| s.persistBool(settings_keys.bat_adapt, on);
    }

    pub fn setExt5vEnabled(self: *Battery, on: bool) void {
        self.ext5v_enabled = on;
        if (self.store) |s| s.persistBool(settings_keys.ext5v, on);
    }

    pub fn getExt5vEnabled(self: *const Battery) bool {
        return self.ext5v_enabled;
    }

    pub fn getUsb5vEnabled(self: *const Battery) bool {
        return self.usb5v_enabled;
    }
};

test "hal: battery npf curve" {
    try std.testing.expectEqual(@as(u8, 100), voltageToPercent(8.5));
    try std.testing.expectEqual(@as(u8, 0), voltageToPercent(5.9));
    try std.testing.expect(voltageToPercent(7.5) >= 50 and voltageToPercent(7.5) <= 60);
    // 8.33V on Tab5 bus: between 8.20 (90%) and 8.40 (100%) -> ~96%
    try std.testing.expectEqual(@as(u8, 96), voltageToPercent(8.33));
}
