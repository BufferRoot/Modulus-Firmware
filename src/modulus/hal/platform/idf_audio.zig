//! ES8388/ES7210 codec shim — `audio_shim.c`.

const c = @import("modulus_shims");

pub fn hwInit() void {
    c.modulus_audio_init();
}

pub fn hwSetVolume(percent: u8) void {
    c.modulus_audio_set_volume(percent);
}

pub fn hwGetVolume() u8 {
    return c.modulus_audio_get_volume();
}

pub fn hwSetMicGainIdx(idx: u8) void {
    c.modulus_audio_set_mic_gain_idx(idx);
}

pub fn hwGetMicGain() f32 {
    return c.modulus_audio_get_mic_gain();
}

pub fn hwSetToneProfile(profile: u8) void {
    c.modulus_audio_set_tone_profile(profile);
}

pub fn hwPlayBootSound() void {
    c.modulus_audio_play_boot();
}
