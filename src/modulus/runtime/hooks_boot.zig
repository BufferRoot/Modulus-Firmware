//! Boot-phase `HalHooks` thunks bound to `Runtime`.

const boot = @import("../core/boot.zig");
const display_mod = @import("../hal/platform/display.zig");
const driver_mod = @import("../cnc/driver.zig");
const dispatcher_mod = @import("../hal/transport/dispatcher.zig");
const build_options = @import("build_options");
const ui_mod = @import("../ui/manager.zig");
const state = @import("hooks_state.zig");

extern fn modulus_estop_gpio_init() void;

pub fn makeHalHooks() boot.HalHooks {
    return .{
        .display_init = hookDisplayInit,
        .apply_brightness = hookApplyBrightness,
        .i18n_init = hookI18nInit,
        .i2c_coex_init = hookI2cCoexInit,
        .touch_init = hookTouchInit,
        .audio_init = hookAudioInit,
        .play_boot_sound = hookPlayBootSound,
        .battery_init = hookBatteryInit,
        .storage_init = hookStorageInit,
        .system_init = hookSystemInit,
        .power_init = hookPowerInit,
        .cnc_driver_init = hookCncDriverInit,
        .transport_init = hookTransportInit,
        .wireless_restore = hookWirelessRestore,
        .ext_encoder_init = hookExtEncoderInit,
        .display_unlock = hookDisplayUnlock,
        .security_init = hookSecurityInit,
        .dsp_init = hookDspInit,
        .imu_init = hookImuInit,
        .ui_init = hookUiInit,
        .ui_boot_screen = hookUiBootScreen,
        .ui_boot_arm = hookUiBootArm,
    };
}

fn hookDisplayInit(ctx: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    rt.display.init(ctx.store);
}

pub fn hookApplyBrightness(pct: u8) void {
    const rt = state.rtPtr() orelse return;
    rt.display.setBrightness(pct);
}

fn hookI18nInit(_: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    rt.i18n.init();
}

fn hookI2cCoexInit(_: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    rt.coex.init();
}

fn hookTouchInit(_: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    rt.touch.init();
}

fn hookAudioInit(ctx: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    rt.audio.init(ctx.store);
}

fn hookPlayBootSound(_: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    rt.audio.playBootSound();
}

fn hookBatteryInit(ctx: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    rt.battery.init(ctx.store);
    rt.battery.bindBus(ctx.bus);
}

fn hookStorageInit(_: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    rt.storage.init();
}

fn hookSystemInit(_: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    rt.rtc.init();
}

fn hookPowerInit(ctx: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    rt.power.init(ctx.store);
    rt.syncPowerHooks();
}

fn hookCncDriverInit(ctx: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    rt.drv = driver_mod.Driver.init(.{ .store = ctx.store, .bus = ctx.bus });
    if (build_options.device_nvs) {
        modulus_estop_gpio_init();
    }
}

fn hookTransportInit(ctx: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    rt.transport = dispatcher_mod.Dispatcher{
        .store = ctx.store,
        .drv = &rt.drv,
    };
    dispatcher_mod.registerDeviceRxHandler();
    rt.transport.init();
    // Only mark ready when a transport actually opened (active_conn set).
    if (rt.transport.activeConnection() != dispatcher_mod.none_active) {
        rt.markTransportReady();
    }
    rt.syncPowerHooks();
}

fn hookWirelessRestore(ctx: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    if (!rt.wireless.init()) return;
    rt.wireless.restoreSettings(ctx.store);
    rt.wireless.postRestoreSettle();
    rt.markWirelessReady();
    _ = rt.storage.mount();
}

fn hookExtEncoderInit(ctx: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    rt.encoder.init(&rt.coex, &rt.drv, ctx.store);
    rt.markEncoderReady();
}

fn hookDisplayUnlock(_: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    if (build_options.device_nvs and rt.display.hw_ready) {
        rt.display.unlock();
    }
}

fn hookSecurityInit(_: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    rt.security.init();
}

fn hookDspInit(_: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    rt.dsp.init();
}

fn hookImuInit(_: *boot.BootContext) void {
    const rt = state.rtPtr() orelse return;
    rt.imu.init();
}

fn hookUiInit(ctx: *boot.BootContext) void {
    ui_mod.init(ctx);
}

fn hookUiBootScreen(_: *boot.BootContext) void {
    ui_mod.showBootScreen();
}

fn hookUiBootArm(_: *boot.BootContext) void {
    ui_mod.armBootTransition();
}
