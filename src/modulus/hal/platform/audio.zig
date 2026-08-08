//! Audio HAL — ES8388 codec + ES7210 mic path (host stub, device via BSP shim).

const std = @import("std");
const build_options = @import("build_options");
const settings_keys = @import("../../core/settings_keys.zig");
const settings_store = @import("../../core/settings_store.zig");
const idf_audio_mod = if (build_options.device_nvs)
    @import("idf_audio.zig")
else
    struct {};

pub const mic_gain_levels = [_]f32{ 0.0, 25.0, 50.0, 75.0, 100.0 };
pub const mic_gain_count: u8 = 5;
pub const tone_profile_count: u8 = 4;

pub const Audio = struct {
    store: ?*settings_store.Store = null,
    volume: u8 = 60,
    mic_gain_idx: u8 = 2,
    tone_profile: u8 = 0,

    pub fn init(self: *Audio, store: *settings_store.Store) void {
        self.store = store;
        self.volume = store.getU8(settings_keys.vol, 60);
        self.mic_gain_idx = store.getU8(settings_keys.mic_gain, 2);
        if (self.mic_gain_idx >= mic_gain_count) self.mic_gain_idx = 2;
        self.tone_profile = store.getU8(settings_keys.tone_prof, 0);
        if (self.tone_profile >= tone_profile_count) self.tone_profile = 0;

        if (build_options.device_nvs) {
            idf_audio_mod.hwInit();
        }
    }

    pub fn setVolume(self: *Audio, percent: u8) void {
        const v = @min(percent, @as(u8, 100));
        self.volume = v;
        if (self.store) |s| s.persistU8(settings_keys.vol, v);
        if (build_options.device_nvs) {
            idf_audio_mod.hwSetVolume(v);
        }
    }

    pub fn getVolume(self: *const Audio) u8 {
        if (build_options.device_nvs) {
            return idf_audio_mod.hwGetVolume();
        }
        return self.volume;
    }

    pub fn setMicGainIdx(self: *Audio, idx: u8) void {
        const i = if (idx < mic_gain_count) idx else @as(u8, 2);
        self.mic_gain_idx = i;
        if (self.store) |s| s.persistU8(settings_keys.mic_gain, i);
        if (build_options.device_nvs) {
            idf_audio_mod.hwSetMicGainIdx(i);
        }
    }

    pub fn micGainDb(self: *const Audio) f32 {
        const idx = if (self.mic_gain_idx < mic_gain_count) self.mic_gain_idx else 2;
        if (build_options.device_nvs) {
            return idf_audio_mod.hwGetMicGain();
        }
        return mic_gain_levels[idx];
    }

    pub fn setToneProfile(self: *Audio, profile: u8) void {
        const p = if (profile < tone_profile_count) profile else @as(u8, 0);
        self.tone_profile = p;
        if (self.store) |s| s.persistU8(settings_keys.tone_prof, p);
        if (build_options.device_nvs) {
            idf_audio_mod.hwSetToneProfile(p);
        }
    }

    pub fn playBootSound(self: *const Audio) void {
        _ = self;
        if (build_options.device_nvs) {
            idf_audio_mod.hwPlayBootSound();
        }
    }
};

test "hal: audio mic gain index clamp" {
    const a = std.testing.allocator;
    var store = settings_store.Store.init(a);
    defer store.deinit();
    var audio = Audio{};
    audio.init(&store);
    audio.setMicGainIdx(99);
    try std.testing.expectEqual(@as(u8, 2), audio.mic_gain_idx);
    try std.testing.expectEqual(mic_gain_levels[2], audio.micGainDb());
}

test "hal: audio volume clamp" {
    const a = std.testing.allocator;
    var store = settings_store.Store.init(a);
    defer store.deinit();
    var audio = Audio{};
    audio.init(&store);
    audio.setVolume(150);
    try std.testing.expectEqual(@as(u8, 100), audio.volume);
}
