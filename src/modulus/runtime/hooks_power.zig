//! Deep-sleep / wake power hooks for transport, wireless, encoder, display.

const settings_keys = @import("../core/settings_keys.zig");
const power_mod = @import("../hal/platform/power.zig");
const state = @import("hooks_state.zig");
const boot_hooks = @import("hooks_boot.zig");

pub fn makePowerHooks() power_mod.SleepHooks {
    return .{
        .transport_deinit = thunkTransportDeinit,
        .ext_encoder_deinit = thunkEncoderDeinit,
        .wireless_prepare = thunkWirelessPrepare,
        .wireless_deinit = thunkWirelessDeinit,
        .display_brightness = boot_hooks.hookApplyBrightness,
        .get_brightness = getBrightness,
        .ext5v_was_on = ext5vWasOn,
        .usb5v_was_on = usb5vWasOn,
    };
}

fn thunkTransportDeinit() void {
    const rt = state.rtPtr() orelse return;
    rt.transport.deinit();
}

fn thunkEncoderDeinit() void {
    const rt = state.rtPtr() orelse return;
    rt.encoder.deinit();
}

fn thunkWirelessPrepare() void {
    const rt = state.rtPtr() orelse return;
    rt.wireless.prepareForSleep();
}

fn thunkWirelessDeinit() void {
    const rt = state.rtPtr() orelse return;
    rt.wireless.deinit();
    rt.markWirelessNotReady();
}

fn getBrightness() u8 {
    const rt = state.rtPtr() orelse return 100;
    return rt.display.getBrightness();
}

fn ext5vWasOn() bool {
    const rt = state.rtPtr() orelse return false;
    return rt.store.getBool(settings_keys.ext5v, true);
}

fn usb5vWasOn() bool {
    const rt = state.rtPtr() orelse return false;
    return rt.store.getBool(settings_keys.usb5v, true);
}
