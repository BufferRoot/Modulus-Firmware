#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Procedural UI tone IDs — match C++ hal_audio::UiSound. */
enum {
    MODULUS_UI_SOUND_TICK = 0,
    MODULUS_UI_SOUND_POP = 1,
    MODULUS_UI_SOUND_DROP = 2,
    MODULUS_UI_SOUND_CHIRP = 3,
};

void modulus_audio_init(void);
bool modulus_audio_is_ready(void);
/** True when ES8388 speaker path initialized (C++ is_output_ready). */
bool modulus_audio_is_output_ready(void);
/** True when ES7210 mic path initialized. */
bool modulus_audio_is_input_ready(void);

void modulus_audio_set_volume(uint8_t percent);
uint8_t modulus_audio_get_volume(void);

void modulus_audio_set_mic_gain_idx(uint8_t idx);
/** Current mic gain index 0..4 (C++ get_mic_gain_index). */
uint8_t modulus_audio_get_mic_gain_idx(void);
float modulus_audio_get_mic_gain(void);

void modulus_audio_set_tone_profile(uint8_t profile);
uint8_t modulus_audio_get_tone_profile(void);

void modulus_audio_set_touch_sounds(bool enabled);
bool modulus_audio_touch_sounds_enabled(void);

void modulus_audio_set_mute(bool mute);

void modulus_audio_play_boot(void);
void modulus_audio_play_shutdown(void);
void modulus_audio_play_ui(uint8_t sound_id);

bool modulus_audio_is_playing(void);
void modulus_audio_stop(void);

/** PI4IOE1 E1.P7 — true when 3.5 mm jack inserted (C++ bsp_headphone_detect). */
bool modulus_audio_headphone_inserted(void);

#ifdef __cplusplus
}
#endif
