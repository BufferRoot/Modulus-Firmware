//! Settings NVS open hooks — brightness, flip, display timeouts, theme.

const settings_store = @import("../core/settings_store.zig");
const display_mod = @import("../hal/platform/display.zig");
const build_options = @import("build_options");
const state = @import("hooks_state.zig");
const boot_hooks = @import("hooks_boot.zig");

extern fn modulus_ui_theme_apply() void;

pub fn makeSettingsOpenHooks() settings_store.InitHooks {
    return .{
        .apply_brightness = boot_hooks.hookApplyBrightness,
        .apply_flip = applyFlip,
        .apply_timeouts = applyDisplayTimeouts,
        .apply_theme = applyTheme,
    };
}

fn applyFlip(flipped: bool) void {
    const rt = state.rtPtr() orelse return;
    rt.display.setRotationFlip(flipped);
}

fn applyDisplayTimeouts(dim_sec: u16, sleep_sec: u16) void {
    const rt = state.rtPtr() orelse return;
    rt.display.dim_timeout_sec = dim_sec;
    rt.display.sleep_timeout_sec = sleep_sec;
    if (build_options.device_nvs and rt.display.hw_ready) {
        display_mod.applyTimeouts(dim_sec, sleep_sec);
    }
}

fn applyTheme() void {
    if (build_options.device_nvs) {
        modulus_ui_theme_apply();
    }
}
