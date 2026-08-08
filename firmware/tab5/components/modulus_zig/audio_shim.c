/*
 * ES8388/ES7210 via m5stack_tab5 BSP — MP3 boot/shutdown + procedural UI tones.
 * Port of C++ hal_audio.cpp (chmorgan esp-audio-player + I2S sine generator task).
 */
#include "audio_shim.h"
#include "nvs_shim.h"
#include "tab5_pi4ioe.h"

#include <audio_player.h>
#include <bsp/m5stack_tab5.h>
#include <driver/i2s_std.h>
#include <esp_log.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/task.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

static const char *TAG = "modulus_audio";

extern const uint8_t boot_sound_mp3_start[] asm("_binary_boot_sound_mp3_start");
extern const uint8_t boot_sound_mp3_end[] asm("_binary_boot_sound_mp3_end");
extern const uint8_t shutdown_sfx_mp3_start[] asm("_binary_shutdown_sfx_mp3_start");
extern const uint8_t shutdown_sfx_mp3_end[] asm("_binary_shutdown_sfx_mp3_end");

typedef struct {
    const uint8_t *start;
    const uint8_t *end;
} sound_entry_t;

typedef enum {
    WAVEFORM_SINE = 0,
    WAVEFORM_SQUARE,
} waveform_t;

typedef struct {
    waveform_t waveform;
    float freq_hz;
    float freq_end_hz;
    uint16_t duration_ms;
    uint16_t fade_in_ms;
    uint16_t fade_out_ms;
    float attack_level;
    bool exp_decay;
} tone_spec_t;

enum {
    SOUND_BOOT = 0,
    SOUND_SHUTDOWN,
    SOUND_MP3_COUNT,
    UI_SOUND_COUNT = 4,
    TONE_PROFILE_COUNT = 4,
    K_UI_SOUND_BASE = 0x80,
    K_SAMPLE_RATE = 48000,
    K_CHUNK_SAMPLES = 256,
};

static sound_entry_t s_mp3_sounds[SOUND_MP3_COUNT];
static esp_codec_dev_handle_t s_spk_dev = NULL;
static esp_codec_dev_handle_t s_mic_dev = NULL;
static uint8_t s_volume = 60;
static uint8_t s_tone_prof = 0;
static bool s_tsound = true;
static float s_mic_gain = 50.0f;
static volatile bool s_playing = false;
static QueueHandle_t s_play_queue = NULL;
static bool s_ready = false;
static uint32_t s_last_sound_ms = 0;
static bool s_spk_open = false;
static uint32_t s_spk_rate = 0;
static uint32_t s_spk_bits = 0;
static i2s_slot_mode_t s_spk_mode = I2S_SLOT_MODE_STEREO;

static const float k_mic_gain_vals[] = {0.0f, 25.0f, 50.0f, 75.0f, 100.0f};
static const int k_mic_gain_count = 5;

static const tone_spec_t k_tone_sets[TONE_PROFILE_COUNT][UI_SOUND_COUNT] = {
    {
        {WAVEFORM_SQUARE, 3000.0f, 0.0f, 30, 0, 10, 0.80f, false},
        {WAVEFORM_SINE, 880.0f, 0.0f, 60, 0, 0, 1.00f, true},
        {WAVEFORM_SINE, 600.0f, 400.0f, 80, 0, 20, 1.00f, false},
        {WAVEFORM_SINE, 1200.0f, 2400.0f, 120, 5, 10, 1.00f, false},
    },
    {
        {WAVEFORM_SINE, 1800.0f, 0.0f, 45, 2, 18, 0.75f, false},
        {WAVEFORM_SINE, 520.0f, 0.0f, 90, 3, 0, 0.90f, false},
        {WAVEFORM_SINE, 400.0f, 320.0f, 100, 0, 30, 1.00f, false},
        {WAVEFORM_SINE, 800.0f, 1200.0f, 150, 8, 20, 1.00f, false},
    },
    {
        {WAVEFORM_SQUARE, 4200.0f, 0.0f, 18, 0, 6, 0.90f, false},
        {WAVEFORM_SINE, 1200.0f, 0.0f, 35, 0, 0, 1.00f, false},
        {WAVEFORM_SINE, 900.0f, 700.0f, 45, 0, 12, 1.00f, false},
        {WAVEFORM_SINE, 2000.0f, 3200.0f, 70, 2, 8, 1.00f, false},
    },
    {
        {WAVEFORM_SQUARE, 2200.0f, 0.0f, 40, 0, 12, 0.85f, false},
        {WAVEFORM_SINE, 440.0f, 0.0f, 50, 0, 0, 1.00f, false},
        {WAVEFORM_SQUARE, 500.0f, 350.0f, 60, 0, 15, 1.00f, false},
        {WAVEFORM_SQUARE, 800.0f, 1600.0f, 100, 3, 12, 1.00f, false},
    },
};

static void apply_volume(void);

static esp_codec_dev_sample_info_t sample_info_from_i2s(uint32_t rate, uint32_t bits, i2s_slot_mode_t mode)
{
    return (esp_codec_dev_sample_info_t){
        .bits_per_sample = (uint8_t)bits,
        .channel = (uint8_t)((mode == I2S_SLOT_MODE_MONO) ? 1 : 2),
        .channel_mask = 0,
        .sample_rate = rate,
        .mclk_multiple = 0,
    };
}

static esp_err_t spk_open_format(uint32_t rate, uint32_t bits, i2s_slot_mode_t mode)
{
    if (!s_spk_dev) {
        return ESP_FAIL;
    }

    if (s_spk_open && s_spk_rate == rate && s_spk_bits == bits && s_spk_mode == mode) {
        return ESP_OK;
    }

    if (s_spk_open) {
        esp_codec_dev_close(s_spk_dev);
        s_spk_open = false;
    }

    esp_codec_dev_sample_info_t fs = sample_info_from_i2s(rate, bits, mode);
    if (esp_codec_dev_open(s_spk_dev, &fs) != ESP_CODEC_DEV_OK) {
        return ESP_FAIL;
    }

    s_spk_open = true;
    s_spk_rate = rate;
    s_spk_bits = bits;
    s_spk_mode = mode;

    if (esp_codec_dev_set_out_vol(s_spk_dev, (int)s_volume) != ESP_CODEC_DEV_OK) {
        return ESP_FAIL;
    }

    return ESP_OK;
}

/*
 * Idle the output by MUTING only — keep the codec device open.
 *
 * disable_when_closed=false means esp_codec_dev_close never powered the amp
 * down (mute is the actual hiss/snow killer), it only disabled the shared I2S
 * TX channel. Closing then reopening for the next tone made esp_codec_dev_open's
 * internal set_fmt pre-disable an already-disabled channel -> "i2s_channel_disable:
 * not enabled yet" ERROR, and churned the channel (button-press distortion).
 * Boot MP3 and UI tones are all 48 kHz, so the held-open device is reused with no
 * reconfigure. Format changes (e.g. 44.1 kHz shutdown sfx) still reopen via
 * spk_open_format below.
 */
static void spk_release_output(void)
{
    if (!s_spk_dev) {
        return;
    }
    esp_codec_dev_set_out_mute(s_spk_dev, true);
}

/** Open at UI rate + unmute — only when output path is actually needed. */
static esp_err_t spk_prepare_ui_output(void)
{
    if (spk_open_format(K_SAMPLE_RATE, 16, I2S_SLOT_MODE_STEREO) != ESP_OK) {
        return ESP_FAIL;
    }
    if (esp_codec_dev_set_out_mute(s_spk_dev, false) != ESP_CODEC_DEV_OK) {
        return ESP_FAIL;
    }
    apply_volume();
    return ESP_OK;
}

static void apply_volume(void)
{
    if (!s_spk_dev) {
        return;
    }
    esp_codec_dev_set_out_vol(s_spk_dev, (int)s_volume);
}

static void apply_mic_gain(void)
{
    if (!s_mic_dev) {
        return;
    }
    esp_codec_dev_set_in_gain(s_mic_dev, s_mic_gain);
}

static esp_err_t mute_cb(AUDIO_PLAYER_MUTE_SETTING setting)
{
    if (!s_spk_dev) {
        return ESP_FAIL;
    }
    if (esp_codec_dev_set_out_mute(s_spk_dev, setting == AUDIO_PLAYER_MUTE) != ESP_CODEC_DEV_OK) {
        return ESP_FAIL;
    }
    return ESP_OK;
}

static esp_err_t clk_set_cb(uint32_t rate, uint32_t bits_cfg, i2s_slot_mode_t ch)
{
    return spk_open_format(rate, bits_cfg, ch);
}

static esp_err_t codec_write_all(const void *audio_buffer, size_t len, size_t *bytes_written)
{
    if (!s_spk_dev || !bytes_written) {
        return ESP_ERR_INVALID_ARG;
    }

    uint8_t *cursor = (uint8_t *)audio_buffer;
    size_t remaining = len;

    for (int attempt = 0; attempt < 12 && remaining > 0; attempt++) {
        const int ret = esp_codec_dev_write(s_spk_dev, cursor, (int)remaining);
        if (ret == ESP_CODEC_DEV_OK) {
            *bytes_written = len;
            return ESP_OK;
        }
        if (attempt > 0) {
            vTaskDelay(pdMS_TO_TICKS(2));
        }
    }

    *bytes_written = 0;
    return ESP_FAIL;
}

static esp_err_t write_cb(void *audio_buffer, size_t len, size_t *bytes_written, uint32_t timeout_ms)
{
    (void)timeout_ms;
    return codec_write_all(audio_buffer, len, bytes_written);
}

static void player_event_cb(audio_player_cb_ctx_t *ctx)
{
    if (ctx->audio_event == AUDIO_PLAYER_CALLBACK_EVENT_IDLE ||
        ctx->audio_event == AUDIO_PLAYER_CALLBACK_EVENT_COMPLETED_PLAYING_NEXT) {
        s_playing = false;
    }
}

static float amplitude_scale(void)
{
    return ((float)s_volume / 100.0f) * 8192.0f;
}

static float wave_sample(waveform_t wf, float phase_rad)
{
    if (wf == WAVEFORM_SQUARE) {
        return (sinf(phase_rad) >= 0.0f) ? 1.0f : -1.0f;
    }
    return sinf(phase_rad);
}

static float envelope_at(const tone_spec_t *spec, int sample_idx, int total_samples)
{
    const float t_ms = ((float)sample_idx * 1000.0f) / (float)K_SAMPLE_RATE;
    const float dur_ms = (float)spec->duration_ms;

    if (spec->fade_in_ms > 0 && t_ms < (float)spec->fade_in_ms) {
        return (t_ms / (float)spec->fade_in_ms) * spec->attack_level;
    }

    if (spec->fade_out_ms > 0 && t_ms > (dur_ms - (float)spec->fade_out_ms)) {
        const float rem = dur_ms - t_ms;
        return (rem / (float)spec->fade_out_ms) * spec->attack_level;
    }

    if (spec->exp_decay) {
        const float norm = t_ms / dur_ms;
        return spec->attack_level * expf(-5.0f * norm);
    }

    if (spec->fade_out_ms == 0 && t_ms > (dur_ms * 0.75f)) {
        const float tail = dur_ms - (dur_ms * 0.75f);
        const float rem = dur_ms - t_ms;
        return spec->attack_level * (rem / tail);
    }

    return spec->attack_level;
}

static float freq_at(const tone_spec_t *spec, int sample_idx, int total_samples)
{
    if (spec->freq_end_hz <= 0.0f || spec->freq_hz == spec->freq_end_hz) {
        return spec->freq_hz;
    }
    const float t = (float)sample_idx / (float)(total_samples > 1 ? total_samples - 1 : 1);
    return spec->freq_hz + (spec->freq_end_hz - spec->freq_hz) * t;
}

static void stop_mp3_if_active(void)
{
    if (!s_playing) {
        return;
    }
    audio_player_stop();
    vTaskDelay(pdMS_TO_TICKS(30));
    audio_player_delete();
    spk_release_output();
    s_playing = false;
}

static void play_ui_tone(uint8_t sound)
{
    if (sound >= UI_SOUND_COUNT) {
        return;
    }

    const uint8_t prof = (s_tone_prof < TONE_PROFILE_COUNT) ? s_tone_prof : 0;
    const tone_spec_t spec = k_tone_sets[prof][sound];

    if (!s_spk_dev) {
        ESP_LOGW(TAG, "Codec not ready, skip UI tone %u", sound);
        return;
    }

    if (spk_prepare_ui_output() != ESP_OK) {
        ESP_LOGW(TAG, "Speaker prep failed, skip UI tone %u", sound);
        return;
    }

    const int total_samples = (K_SAMPLE_RATE * spec.duration_ms) / 1000;
    const float amp = amplitude_scale();
    float phase = 0.0f;

    s_playing = true;

    for (int pos = 0; pos < total_samples;) {
        const int n = (total_samples - pos) < K_CHUNK_SAMPLES ? (total_samples - pos) : K_CHUNK_SAMPLES;
        int16_t chunk[K_CHUNK_SAMPLES * 2];

        for (int i = 0; i < n; i++) {
            const int idx = pos + i;
            const float freq = freq_at(&spec, idx, total_samples);
            const float env = envelope_at(&spec, idx, total_samples);
            const float sample = wave_sample(spec.waveform, phase) * env * amp;
            phase += (2.0f * (float)M_PI * freq) / (float)K_SAMPLE_RATE;

            const int16_t s = (int16_t)sample;
            chunk[i * 2] = s;
            chunk[i * 2 + 1] = s;
        }

        const int chunk_bytes = n * 2 * (int)sizeof(int16_t);
        size_t written = 0;
        if (codec_write_all(chunk, (size_t)chunk_bytes, &written) != ESP_OK || written != (size_t)chunk_bytes) {
            ESP_LOGW(TAG, "UI tone write failed at sample %d", pos);
            break;
        }
        pos += n;
    }

    spk_release_output();
    s_playing = false;
}

static void play_mp3(uint8_t id)
{
    if (id >= SOUND_MP3_COUNT) {
        return;
    }

    const sound_entry_t *snd = &s_mp3_sounds[id];
    if (!snd->start || snd->end <= snd->start) {
        return;
    }

    if (!s_spk_dev) {
        ESP_LOGW(TAG, "Codec not ready, skip MP3 %u", id);
        return;
    }

    if (spk_prepare_ui_output() != ESP_OK) {
        ESP_LOGW(TAG, "Speaker prep failed, skip MP3 %u", id);
        return;
    }

    audio_player_config_t cfg = {
        .mute_fn = mute_cb,
        .clk_set_fn = clk_set_cb,
        .write_fn = write_cb,
        .priority = 8,
        .coreID = 1,
    };

    if (audio_player_new(cfg) != ESP_OK) {
        ESP_LOGE(TAG, "audio_player_new failed");
        return;
    }

    audio_player_callback_register(player_event_cb, NULL);

    const size_t mp3_size = (size_t)(snd->end - snd->start);
    FILE *fp = fmemopen((void *)snd->start, mp3_size, "rb");
    if (!fp || audio_player_play(fp) != ESP_OK) {
        ESP_LOGE(TAG, "MP3 play failed id=%u", id);
        if (fp) {
            fclose(fp);
        }
        audio_player_delete();
        return;
    }

    s_playing = true;

    int wait_ms = 0;
    while (s_playing && wait_ms < 10000) {
        vTaskDelay(pdMS_TO_TICKS(50));
        wait_ms += 50;
    }

    if (s_playing) {
        ESP_LOGW(TAG, "MP3 id=%u wait timeout — forcing stop", id);
        audio_player_stop();
        vTaskDelay(pdMS_TO_TICKS(100));
    }

    audio_player_delete();
    spk_release_output();
    s_playing = false;
}

static void audio_task(void *arg)
{
    (void)arg;
    uint8_t req_id;

    while (true) {
        if (xQueueReceive(s_play_queue, &req_id, portMAX_DELAY) != pdTRUE) {
            continue;
        }

        uint8_t dummy;
        while (xQueueReceive(s_play_queue, &dummy, 0) == pdTRUE) {
        }

        if (req_id >= K_UI_SOUND_BASE) {
            stop_mp3_if_active();
            play_ui_tone((uint8_t)(req_id - K_UI_SOUND_BASE));
        } else {
            play_mp3(req_id);
        }
    }
}

static void queue_sound(uint8_t id)
{
    if (!s_play_queue) {
        return;
    }
    xQueueSend(s_play_queue, &id, 0);
}

void modulus_audio_init(void)
{
    if (s_ready) {
        return;
    }

    /* display_init already ran tab5_pi4ioe_init (SPK/RST rails); re-assert amp enable. */
    if (tab5_pi4ioe_is_ready()) {
        tab5_pi4ioe_set_spk_en(true);
    }

    s_spk_dev = bsp_audio_codec_speaker_init();
    s_mic_dev = bsp_audio_codec_microphone_init();
    if (!s_spk_dev) {
        ESP_LOGW(TAG, "Speaker codec unavailable — output dimmed");
    }
    if (!s_mic_dev) {
        ESP_LOGW(TAG, "Microphone codec unavailable");
    }
    if (!s_spk_dev && !s_mic_dev) {
        ESP_LOGE(TAG, "BSP codec init failed spk=%p mic=%p", s_spk_dev, s_mic_dev);
        return;
    }

    if (s_spk_dev) {
        esp_codec_set_disable_when_closed(s_spk_dev, false);

        s_mp3_sounds[SOUND_BOOT] = (sound_entry_t){boot_sound_mp3_start, boot_sound_mp3_end};
        s_mp3_sounds[SOUND_SHUTDOWN] = (sound_entry_t){shutdown_sfx_mp3_start, shutdown_sfx_mp3_end};

        s_play_queue = xQueueCreate(4, sizeof(uint8_t));
        xTaskCreatePinnedToCore(audio_task, "audio_sfx", 4096, NULL, 6, NULL, 1);
    }

    s_volume = modulus_nvs_get_u8("vol", 60);
    s_tone_prof = modulus_nvs_get_u8("tone_prof", 0);
    if (s_tone_prof > 3) {
        s_tone_prof = 0;
    }
    s_tsound = modulus_nvs_get_u8("tsound", 1) != 0;

    uint8_t mic_idx = modulus_nvs_get_u8("mic_gain", 2);
    if (mic_idx >= (uint8_t)k_mic_gain_count) {
        mic_idx = 2;
    }
    s_mic_gain = k_mic_gain_vals[mic_idx];

    if (s_spk_dev) {
        apply_volume();
        spk_release_output();
    }
    if (s_mic_dev) {
        apply_mic_gain();
    }

    s_ready = true;
    ESP_LOGI(TAG, "Audio ready out=%d in=%d vol=%u%% mic=%.0f tone=%u",
             s_spk_dev != NULL, s_mic_dev != NULL, s_volume, s_mic_gain, s_tone_prof);
}

bool modulus_audio_is_ready(void)
{
    return s_ready;
}

bool modulus_audio_is_output_ready(void)
{
    return s_spk_dev != NULL;
}

bool modulus_audio_is_input_ready(void)
{
    return s_mic_dev != NULL;
}

void modulus_audio_set_volume(uint8_t percent)
{
    if (percent > 100) {
        percent = 100;
    }
    s_volume = percent;
    apply_volume();
}

uint8_t modulus_audio_get_volume(void)
{
    return s_volume;
}

void modulus_audio_set_mic_gain_idx(uint8_t idx)
{
    if (idx >= (uint8_t)k_mic_gain_count) {
        idx = 2;
    }
    s_mic_gain = k_mic_gain_vals[idx];
    apply_mic_gain();
}

uint8_t modulus_audio_get_mic_gain_idx(void)
{
    for (uint8_t i = 0; i < (uint8_t)k_mic_gain_count; i++) {
        if (s_mic_gain == k_mic_gain_vals[i]) {
            return i;
        }
    }
    return 2;
}

float modulus_audio_get_mic_gain(void)
{
    return s_mic_gain;
}

void modulus_audio_set_tone_profile(uint8_t profile)
{
    if (profile > 3) {
        profile = 0;
    }
    s_tone_prof = profile;
    modulus_nvs_set_u8("tone_prof", profile);
}

uint8_t modulus_audio_get_tone_profile(void)
{
    return s_tone_prof;
}

void modulus_audio_set_touch_sounds(bool enabled)
{
    s_tsound = enabled;
    modulus_nvs_set_u8("tsound", enabled ? 1 : 0);
}

bool modulus_audio_touch_sounds_enabled(void)
{
    return s_tsound;
}

void modulus_audio_set_mute(bool mute)
{
    if (!s_spk_dev) {
        return;
    }
    esp_codec_dev_set_out_mute(s_spk_dev, mute);
}

void modulus_audio_play_boot(void)
{
    if (!modulus_audio_is_output_ready()) {
        return;
    }
    queue_sound(SOUND_BOOT);
}

void modulus_audio_play_shutdown(void)
{
    if (!modulus_audio_is_output_ready()) {
        return;
    }
    queue_sound(SOUND_SHUTDOWN);
}

void modulus_audio_play_ui(uint8_t sound_id)
{
    if (!modulus_audio_is_output_ready() || sound_id >= UI_SOUND_COUNT) {
        return;
    }
    if (!s_tsound || s_volume == 0) {
        return;
    }

    const uint32_t now = xTaskGetTickCount() * portTICK_PERIOD_MS;
    if (sound_id == MODULUS_UI_SOUND_TICK && (now - s_last_sound_ms) < 50) {
        return;
    }

    s_last_sound_ms = now;
    queue_sound((uint8_t)(K_UI_SOUND_BASE | sound_id));
}

bool modulus_audio_is_playing(void)
{
    return s_playing;
}

void modulus_audio_stop(void)
{
    stop_mp3_if_active();
}

bool modulus_audio_headphone_inserted(void)
{
    return tab5_pi4ioe_get_headphone_detect();
}
