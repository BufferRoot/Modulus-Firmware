//! Power HAL — sleep policy, deep-sleep sequence (host-traced).

const std = @import("std");
const build_options = @import("build_options");
const settings_keys = @import("../../core/settings_keys.zig");
const settings_store = @import("../../core/settings_store.zig");
const idf_power_mod = if (build_options.device_nvs)
    @import("idf_power.zig")
else
    struct {};

pub const SleepMode = enum(u8) {
    display_only = 0,
    deep_sleep,
    _count,
};

pub const WakeSource = struct {
    pub const touch: u8 = 1 << 0;
    pub const timer: u8 = 1 << 1;
    pub const usb: u8 = 1 << 2;
};

pub const SleepState = struct {
    brightness: u8 = 0,
    ext5v_was_on: bool = false,
    usb5v_was_on: bool = false,
    wifi_was_on: bool = false,
    sleep_enter_us: u64 = 0,
    sleep_exit_us: u64 = 0,
};

pub const SleepStep = enum(u8) {
    snapshot,
    display_off,
    deep_sleep_event,
    transport_deinit,
    ext_encoder_deinit,
    gate_rails,
    wireless_prepare,
    wireless_deinit,
    c6_power_off,
};

pub const SleepHooks = struct {
    transport_deinit: ?*const fn () void = null,
    ext_encoder_deinit: ?*const fn () void = null,
    wireless_prepare: ?*const fn () void = null,
    wireless_deinit: ?*const fn () void = null,
    display_brightness: ?*const fn (u8) void = null,
    get_brightness: ?*const fn () u8 = null,
    ext5v_was_on: ?*const fn () bool = null,
    usb5v_was_on: ?*const fn () bool = null,
};

pub const Power = struct {
    store: ?*settings_store.Store = null,
    hooks: SleepHooks = .{},
    sleep_mode: SleepMode = .display_only,
    wake_sources: u8 = WakeSource.touch,
    deep_sleep_timeout_sec: u16 = 120,
    wake_timer_min: u16 = 0,
    gate_wifi: bool = true,
    gate_ext5v: bool = true,
    gate_usb5v: bool = false,
    deep_sleeping: bool = false,
    state: SleepState = .{},
    trace: ?*std.ArrayListUnmanaged(SleepStep) = null,
    trace_allocator: ?std.mem.Allocator = null,

    pub fn init(self: *Power, store: *settings_store.Store) void {
        self.store = store;
        var mode = store.getU8(settings_keys.pwr_mode, 0);
        if (mode >= @intFromEnum(SleepMode._count)) mode = 0;
        self.sleep_mode = @enumFromInt(mode);
        self.wake_sources = store.getU8(settings_keys.pwr_wake, WakeSource.touch);
        self.deep_sleep_timeout_sec = store.getU16(settings_keys.pwr_dsto, 120);
        self.wake_timer_min = store.getU16(settings_keys.pwr_wtmin, 0);
        self.gate_wifi = store.getBool(settings_keys.pwr_gwifi, true);
        self.gate_ext5v = store.getBool(settings_keys.pwr_gext, true);
        self.gate_usb5v = store.getBool(settings_keys.pwr_gusb, false);
        if (build_options.device_nvs) {
            idf_power_mod.hwInit();
        }
    }

    pub fn enterDeepSleep(self: *Power, enter_us: u64) void {
        if (self.deep_sleeping) return;
        self.deep_sleeping = true;
        self.record(.snapshot);
        self.state.brightness = if (self.hooks.get_brightness) |get_b| get_b() else 100;
        self.state.ext5v_was_on = if (self.hooks.ext5v_was_on) |get_e| get_e() else true;
        self.state.usb5v_was_on = if (self.hooks.usb5v_was_on) |get_u| get_u() else false;
        self.state.wifi_was_on = true;
        self.state.sleep_enter_us = enter_us;

        self.record(.display_off);
        if (self.hooks.display_brightness) |set_b| set_b(0);

        self.record(.deep_sleep_event);

        self.record(.transport_deinit);
        if (self.hooks.transport_deinit) |deinit_t| deinit_t();

        self.record(.ext_encoder_deinit);
        if (self.hooks.ext_encoder_deinit) |deinit_e| deinit_e();

        self.record(.gate_rails);

        if (self.gate_wifi) {
            self.record(.wireless_prepare);
            if (self.hooks.wireless_prepare) |prep| prep();
            self.record(.wireless_deinit);
            if (self.hooks.wireless_deinit) |deinit_w| deinit_w();
            self.record(.c6_power_off);
        }
    }

    pub fn wake(self: *Power, exit_us: u64) void {
        if (!self.deep_sleeping) return;
        self.deep_sleeping = false;
        self.state.sleep_exit_us = exit_us;
    }

    pub fn isDeepSleeping(self: *const Power) bool {
        return self.deep_sleeping;
    }

    fn record(self: *Power, step: SleepStep) void {
        if (self.trace) |t| {
            if (self.trace_allocator) |alloc| t.append(alloc, step) catch {
                @branchHint(.cold);
                return;
            };
        }
    }
};

test "hal: power deep sleep step order" {
    const a = std.testing.allocator;
    var store = settings_store.Store.init(a);
    defer store.deinit();
    var trace: std.ArrayListUnmanaged(SleepStep) = .empty;
    defer trace.deinit(a);

    var pwr: Power = .{ .store = &store, .trace = &trace, .trace_allocator = a };
    pwr.init(&store);
    pwr.enterDeepSleep(1000);
    try std.testing.expect(pwr.isDeepSleeping());

    var transport_idx: ?usize = null;
    var prepare_idx: ?usize = null;
    var deinit_idx: ?usize = null;
    for (trace.items, 0..) |step, i| {
        if (step == .transport_deinit) transport_idx = i;
        if (step == .wireless_prepare) prepare_idx = i;
        if (step == .wireless_deinit) deinit_idx = i;
    }
    try std.testing.expect(transport_idx != null);
    try std.testing.expect(prepare_idx != null);
    try std.testing.expect(deinit_idx != null);
    try std.testing.expect(transport_idx.? < prepare_idx.?);
    try std.testing.expect(prepare_idx.? < deinit_idx.?);
}
