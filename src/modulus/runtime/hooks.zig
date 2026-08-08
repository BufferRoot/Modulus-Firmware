//! Boot `HalHooks` thunks bound to `Runtime` instances.

const boot = @import("../core/boot.zig");
const settings_store = @import("../core/settings_store.zig");
const power_mod = @import("../hal/platform/power.zig");
const state = @import("hooks_state.zig");
const boot_hooks = @import("hooks_boot.zig");
const settings_hooks = @import("hooks_settings.zig");
const power_hooks = @import("hooks_power.zig");

const Runtime = @import("runtime.zig").Runtime;

pub fn bind(rt: *Runtime) void {
    state.bind(rt);
}

pub fn setSpawnHandler(handler: *const fn () bool) void {
    state.setSpawnHandler(handler);
}

pub fn invokeSpawnHandler() bool {
    return state.invokeSpawnHandler();
}

pub fn makeHalHooks() boot.HalHooks {
    return boot_hooks.makeHalHooks();
}

pub fn rtPtr() ?*Runtime {
    return state.rtPtr();
}

pub fn makeSettingsOpenHooks() settings_store.InitHooks {
    return settings_hooks.makeSettingsOpenHooks();
}

pub fn makePowerHooks() power_mod.SleepHooks {
    return power_hooks.makePowerHooks();
}

test "runtime: hal hooks wire touch_init and dsp_init" {
    const defaults = boot.HalHooks{};
    const wired = makeHalHooks();
    try @import("std").testing.expect(wired.touch_init != defaults.touch_init);
    try @import("std").testing.expect(wired.dsp_init != defaults.dsp_init);
}
