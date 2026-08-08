//! Boot orchestration — order frozen from C++ `modulus.cpp`. Host: mock HAL hooks only.

const std = @import("std");
const event_bus = @import("event_bus.zig");
const settings_keys = @import("settings_keys.zig");
const settings_store = @import("settings_store.zig");
const system_events = @import("system_events.zig");

pub const Hook = *const fn (*BootContext) void;

pub const Phase = enum {
    event_bus,
    display_init,
    settings_init,
    i18n_init,
    i2c_coex_init,
    touch_init,
    audio_init,
    battery_init,
    storage_init,
    system_init,
    security_init,
    dsp_init,
    power_init,
    cnc_driver_init,
    transport_init,
    wireless_restore,
    ext_encoder_init,
    ui_init,
    ui_boot_screen,
    display_unlock,
    ui_boot_arm,
    system_task_spawn,
    boot_sound,
    boot_complete_event,
    imu_init,
};

/// Core 1 real-time task policy (FreeRTOS on device; documented stub on host).
pub const SystemTaskPolicy = struct {
    pub const core_affinity: u8 = 1;
    pub const stack_words: u16 = 8192;
    pub const priority: u8 = 5;
    pub const period_ms: u16 = 10;
    pub const name = "sys_task";
};

/// Core 0 event dispatch task — UI-safe subscriber callbacks (LVGL later).
/// stack_words is BYTES on ESP-IDF. UI event handlers run wireless/C6 RPC work
/// inline (ESP-NOW connect: apply_peer -> ensure_inited -> blocking RPC, plus
/// esp_wifi_set_ps); coinciding with an LVGL box-shadow render overflowed the
/// original 4096 B stack (evt_dispatch stack-protection fault).
pub const EventDispatchPolicy = struct {
    pub const core_affinity: u8 = 0;
    pub const stack_words: u16 = 12288;
    pub const priority: u8 = 10;
    pub const name = "evt_dispatch";
};

pub const HalHooks = struct {
    display_init: Hook = noop,
    apply_brightness: ?*const fn (u8) void = null,
    i18n_init: Hook = noop,
    i2c_coex_init: Hook = noop,
    touch_init: Hook = noop,
    audio_init: Hook = noop,
    play_boot_sound: Hook = noop,
    battery_init: Hook = noop,
    storage_init: Hook = noop,
    system_init: Hook = noop,
    security_init: Hook = noop,
    dsp_init: Hook = noop,
    power_init: Hook = noop,
    cnc_driver_init: Hook = noop,
    transport_init: Hook = noop,
    wireless_restore: Hook = noop,
    ext_encoder_init: Hook = noop,
    ui_init: Hook = noop,
    ui_boot_screen: Hook = noop,
    display_unlock: Hook = noop,
    ui_boot_arm: Hook = noop,
    imu_init: Hook = noop,
};

pub const BootContext = struct {
    allocator: std.mem.Allocator,
    store: *settings_store.Store,
    bus: *event_bus.EventBus,
    hal: HalHooks = .{},
    settings_hooks: settings_store.InitHooks = .{},
    trace: ?*std.ArrayListUnmanaged(Phase) = null,
    spawn_system_task: ?*const fn () void = null,
};

pub const expected_phases_with_sound = [_]Phase{
    .event_bus,      .display_init,      .settings_init,
    .ui_init,        .audio_init,        .boot_sound,
    .ui_boot_screen, .display_unlock,    .i18n_init,
    .i2c_coex_init,  .touch_init,        .battery_init,
    .storage_init,   .system_init,       .security_init,
    .dsp_init,       .power_init,        .cnc_driver_init,
    .transport_init, .ext_encoder_init,  .wireless_restore,
    .ui_boot_arm,    .system_task_spawn, .boot_complete_event,
    .imu_init,
};

pub const expected_phases_no_sound = [_]Phase{
    .event_bus,         .display_init,        .settings_init,
    .ui_init,           .audio_init,          .ui_boot_screen,
    .display_unlock,    .i18n_init,           .i2c_coex_init,
    .touch_init,        .battery_init,        .storage_init,
    .system_init,       .security_init,       .dsp_init,
    .power_init,        .cnc_driver_init,     .transport_init,
    .ext_encoder_init,  .wireless_restore,    .ui_boot_arm,
    .system_task_spawn, .boot_complete_event, .imu_init,
};

fn noop(_: *BootContext) void {}

fn record(ctx: *BootContext, phase: Phase) void {
    if (ctx.trace) |trace| {
        trace.append(ctx.allocator, phase) catch {
            @branchHint(.cold);
            return;
        };
    }
}

fn invoke(ctx: *BootContext, phase: Phase, hook: Hook) void {
    record(ctx, phase);
    hook(ctx);
}

/// Run full boot sequence. Caller owns `store` and `bus` (already allocated).
pub fn run(ctx: *BootContext) !void {
    record(ctx, .event_bus);

    invoke(ctx, .display_init, ctx.hal.display_init);

    record(ctx, .settings_init);
    ctx.store.open(ctx.settings_hooks);

    invoke(ctx, .ui_init, ctx.hal.ui_init);
    invoke(ctx, .audio_init, ctx.hal.audio_init);
    if (ctx.store.getBool(settings_keys.snd_up, true)) {
        invoke(ctx, .boot_sound, ctx.hal.play_boot_sound);
    }
    invoke(ctx, .ui_boot_screen, ctx.hal.ui_boot_screen);
    invoke(ctx, .display_unlock, ctx.hal.display_unlock);

    invoke(ctx, .i18n_init, ctx.hal.i18n_init);
    invoke(ctx, .i2c_coex_init, ctx.hal.i2c_coex_init);
    invoke(ctx, .touch_init, ctx.hal.touch_init);
    invoke(ctx, .battery_init, ctx.hal.battery_init);
    invoke(ctx, .storage_init, ctx.hal.storage_init);
    invoke(ctx, .system_init, ctx.hal.system_init);
    invoke(ctx, .security_init, ctx.hal.security_init);
    invoke(ctx, .dsp_init, ctx.hal.dsp_init);
    invoke(ctx, .power_init, ctx.hal.power_init);
    invoke(ctx, .cnc_driver_init, ctx.hal.cnc_driver_init);
    invoke(ctx, .transport_init, ctx.hal.transport_init);
    invoke(ctx, .ext_encoder_init, ctx.hal.ext_encoder_init);
    invoke(ctx, .wireless_restore, ctx.hal.wireless_restore);
    invoke(ctx, .ui_boot_arm, ctx.hal.ui_boot_arm);

    record(ctx, .system_task_spawn);
    if (ctx.spawn_system_task) |spawn| spawn();

    record(ctx, .boot_complete_event);
    ctx.bus.publish(system_events.EVT_SYSTEM_BOOT_COMPLETE, &.{});

    // C++ parity: IMU after boot-complete (clears stale wake-on-motion NVS path)
    invoke(ctx, .imu_init, ctx.hal.imu_init);
}

test "core: boot phase order with startup sound" {
    const a = std.testing.allocator;
    var trace: std.ArrayListUnmanaged(Phase) = .empty;
    defer trace.deinit(a);

    var store = settings_store.Store.init(a);
    defer store.deinit();
    try store.setBool(settings_keys.snd_up, true);

    var bus = event_bus.EventBus.init();
    defer bus.deinit();

    var ctx = BootContext{
        .allocator = a,
        .store = &store,
        .bus = &bus,
        .trace = &trace,
    };
    try run(&ctx);

    try std.testing.expectEqual(expected_phases_with_sound.len, trace.items.len);
    try std.testing.expectEqualSlices(Phase, &expected_phases_with_sound, trace.items);
}

test "core: boot skips sound when snd_up false" {
    const a = std.testing.allocator;
    var trace: std.ArrayListUnmanaged(Phase) = .empty;
    defer trace.deinit(a);

    var store = settings_store.Store.init(a);
    defer store.deinit();
    try store.setBool(settings_keys.snd_up, false);

    var bus = event_bus.EventBus.init();
    defer bus.deinit();

    var ctx = BootContext{
        .allocator = a,
        .store = &store,
        .bus = &bus,
        .trace = &trace,
    };
    try run(&ctx);

    try std.testing.expectEqual(expected_phases_no_sound.len, trace.items.len);
    try std.testing.expectEqualSlices(Phase, &expected_phases_no_sound, trace.items);
}

test "core: boot publishes EVT_SYSTEM_BOOT_COMPLETE" {
    const a = std.testing.allocator;
    var store = settings_store.Store.init(a);
    defer store.deinit();
    var bus = event_bus.EventBus.init();
    defer bus.deinit();

    const Ctx = struct {
        var hits: usize = 0;
        fn onBoot(id: system_events.EventId, data: []const u8) void {
            _ = data;
            if (id == system_events.EVT_SYSTEM_BOOT_COMPLETE) hits += 1;
        }
    };

    try bus.subscribe(system_events.EVT_SYSTEM_BOOT_COMPLETE, Ctx.onBoot);

    var ctx = BootContext{
        .allocator = a,
        .store = &store,
        .bus = &bus,
    };
    try run(&ctx);
    bus.dispatchAll();

    try std.testing.expectEqual(@as(usize, 1), Ctx.hits);
}

test "core: boot spawns system task hook" {
    const a = std.testing.allocator;
    var store = settings_store.Store.init(a);
    defer store.deinit();
    var bus = event_bus.EventBus.init();
    defer bus.deinit();

    const Ctx = struct {
        var spawned: bool = false;
        fn spawn() void {
            spawned = true;
        }
    };

    var ctx = BootContext{
        .allocator = a,
        .store = &store,
        .bus = &bus,
        .spawn_system_task = Ctx.spawn,
    };
    try run(&ctx);
    try std.testing.expect(Ctx.spawned);
}
