//! UI manager — screen lifecycle + event-driven overlays (device: LVGL via C shim).

const std = @import("std");
const build_options = @import("build_options");
const boot = @import("../core/boot.zig");
const system_events = @import("../core/system_events.zig");
const display_mod = @import("../hal/platform/display.zig");
const security_mod = @import("../hal/platform/security.zig");
const device_ui = @import("device_ui.zig");
const device_log = @import("../core/device_log.zig");

pub const Screen = enum(u8) {
    none,
    boot,
    dashboard,
    settings,
    pin_lock,
};

var active_screen: Screen = .none;

pub fn activeScreen() Screen {
    return active_screen;
}

pub fn init(ctx: *boot.BootContext) void {
    if (!build_options.device_nvs) return;

    device_ui.hwInit();
    trySubscribe(ctx, system_events.EVT_SCREEN_CHANGE, onScreenChange);
    trySubscribe(ctx, system_events.EVT_SYSTEM_DEEP_SLEEP, onDeepSleep);
    trySubscribe(ctx, system_events.EVT_SYSTEM_WAKE, onWake);
    trySubscribe(ctx, system_events.EVT_CNC_STATUS_UPDATE, onCncStatus);
}

pub fn showBootScreen() void {
    if (!build_options.device_nvs) {
        active_screen = .boot;
        return;
    }
    device_ui.showBootScreen();
    active_screen = .boot;
}

pub fn armBootTransition() void {
    if (!build_options.device_nvs) return;
    device_ui.armBootTransition();
}

fn withDisplayLock(comptime action: *const fn () void) void {
    if (build_options.device_nvs) {
        display_mod.lockHw();
        defer display_mod.unlockHw();
    }
    action();
}

fn trySubscribe(ctx: *boot.BootContext, id: system_events.EventId, handler: *const fn (system_events.EventId, []const u8) void) void {
    const log = device_log.ui;
    ctx.bus.subscribe(id, handler) catch |err| log.warn("subscribe {}: {}", .{ id, err });
}

fn pinLocked() bool {
    return security_mod.isLockedActive();
}

fn onScreenChange(_: system_events.EventId, _: []const u8) void {
    if (!build_options.device_nvs) return;
    if (pinLocked()) {
        withDisplayLock(device_ui.showPinLock);
        active_screen = .pin_lock;
    }
}

fn onDeepSleep(_: system_events.EventId, _: []const u8) void {
    if (!build_options.device_nvs) return;
    withDisplayLock(device_ui.onDeepSleep);
}

pub fn showSettings() void {
    if (!build_options.device_nvs) {
        active_screen = .settings;
        return;
    }
    withDisplayLock(device_ui.showSettings);
    active_screen = .settings;
}

pub fn showQuickSettings() void {
    if (!build_options.device_nvs) return;
    withDisplayLock(device_ui.showQuickSettings);
}

pub fn showPowerMenu() void {
    if (!build_options.device_nvs) return;
    withDisplayLock(device_ui.showPowerMenu);
}

pub fn hideSettings() void {
    if (!build_options.device_nvs) {
        active_screen = .dashboard;
        return;
    }
    withDisplayLock(device_ui.hideSettings);
    active_screen = .dashboard;
}

fn onWake(_: system_events.EventId, _: []const u8) void {
    if (!build_options.device_nvs) return;
    withDisplayLock(device_ui.onWake);
    if (pinLocked()) {
        withDisplayLock(device_ui.showPinLock);
        active_screen = .pin_lock;
    } else {
        active_screen = .dashboard;
    }
}

fn onCncStatus(_: system_events.EventId, _: []const u8) void {
    if (!build_options.device_nvs) return;
    device_ui.onCncStatusEvent();
}

test "ui: manager boot screen state" {
    showBootScreen();
    try std.testing.expectEqual(Screen.boot, activeScreen());
}
