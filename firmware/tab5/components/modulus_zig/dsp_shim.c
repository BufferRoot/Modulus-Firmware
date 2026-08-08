/*
 * DSP HAL — esp-dsp FFT/IIR pipeline on Core 1 (port of C++ hal_dsp.cpp).
 */
#include "dsp_shim.h"

#include <math.h>
#include <string.h>
#include <stdatomic.h>

#include <dsps_fft2r.h>
#include <dsps_wind_hann.h>
#include <dsps_biquad.h>
#include <dsps_biquad_gen.h>
#include <esp_heap_caps.h>
#include <esp_log.h>
#include <esp_timer.h>

static const char *TAG = "modulus_dsp";

enum {
    k_fft_size = 1024,
    k_spectrum_bins = k_fft_size / 2,
    k_ring_buf_len = 2048,
    k_sample_rate = 10000,
};

static bool s_initialised = false;
static int s_sample_rate = k_sample_rate;

static float s_ring[k_ring_buf_len];
static _Atomic uint32_t s_ring_wr;
static _Atomic uint32_t s_ring_rd;
static const uint32_t k_ring_mask = k_ring_buf_len - 1;

static float *s_fft_buf = NULL;
static float *s_window = NULL;
static float s_bq_coeffs[5] = {1, 0, 0, 0, 0};
static float s_bq_delay[2] = {0, 0};
static bool s_filter_active = false;
static float *s_raw_block = NULL;
static float *s_filtered = NULL;

typedef struct {
    float magnitude[k_spectrum_bins];
    float peak_freq;
    float peak_mag;
    float bin_resolution;
    uint32_t timestamp_ms;
    bool valid;
} spectrum_result_t;

static spectrum_result_t s_result_buf[2];
static _Atomic int s_result_idx;
static float s_filtered_val = 0.0f;
static uint32_t s_frame_count = 0;

void modulus_dsp_init(void)
{
    if (s_initialised) {
        return;
    }

    ESP_LOGI(TAG, "Initialising DSP: FFT=%d, ring=%d, Fs=%d Hz",
             k_fft_size, k_ring_buf_len, s_sample_rate);

    s_fft_buf = (float *)heap_caps_calloc(k_fft_size * 2, sizeof(float), MALLOC_CAP_SPIRAM);
    s_window = (float *)heap_caps_malloc(k_fft_size * sizeof(float), MALLOC_CAP_SPIRAM);
    if (!s_fft_buf || !s_window) {
        ESP_LOGE(TAG, "Failed to allocate DSP buffers in PSRAM");
        return;
    }

    s_raw_block = (float *)heap_caps_calloc(k_fft_size, sizeof(float), MALLOC_CAP_SPIRAM);
    s_filtered = (float *)heap_caps_calloc(k_fft_size, sizeof(float), MALLOC_CAP_SPIRAM);
    if (!s_raw_block || !s_filtered) {
        ESP_LOGE(TAG, "Failed to allocate DSP scratch buffers");
        return;
    }

    dsps_wind_hann_f32(s_window, k_fft_size);

    const esp_err_t err = dsps_fft2r_init_fc32(NULL, CONFIG_DSP_MAX_FFT_SIZE);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "FFT table init failed: %s", esp_err_to_name(err));
        return;
    }

    memset(s_result_buf, 0, sizeof(s_result_buf));
    atomic_store_explicit(&s_ring_wr, 0, memory_order_relaxed);
    atomic_store_explicit(&s_ring_rd, 0, memory_order_relaxed);

    s_initialised = true;
    ESP_LOGI(TAG, "DSP ready — bin resolution %.1f Hz",
             (float)s_sample_rate / (float)k_fft_size);
}

void modulus_dsp_deinit(void)
{
    if (!s_initialised) {
        return;
    }
    dsps_fft2r_deinit_fc32();
    heap_caps_free(s_fft_buf);
    s_fft_buf = NULL;
    heap_caps_free(s_window);
    s_window = NULL;
    heap_caps_free(s_raw_block);
    s_raw_block = NULL;
    heap_caps_free(s_filtered);
    s_filtered = NULL;
    s_initialised = false;
    ESP_LOGI(TAG, "DSP deinitialised");
}

bool modulus_dsp_is_ready(void)
{
    return s_initialised;
}

void modulus_dsp_push_sample(float sample)
{
    const uint32_t wr = atomic_load_explicit(&s_ring_wr, memory_order_relaxed);
    s_ring[wr & k_ring_mask] = sample;
    atomic_store_explicit(&s_ring_wr, wr + 1, memory_order_release);
}

static int samples_available(void)
{
    const uint32_t wr = atomic_load_explicit(&s_ring_wr, memory_order_acquire);
    const uint32_t rd = atomic_load_explicit(&s_ring_rd, memory_order_relaxed);
    return (int)(wr - rd);
}

void modulus_dsp_process(void)
{
    if (!s_initialised || samples_available() < k_fft_size) {
        return;
    }

    const uint32_t rd = atomic_load_explicit(&s_ring_rd, memory_order_relaxed);

    for (int i = 0; i < k_fft_size; i++) {
        const float raw = s_ring[(rd + (uint32_t)i) & k_ring_mask];
        s_fft_buf[i * 2] = raw * s_window[i];
        s_fft_buf[i * 2 + 1] = 0.0f;
    }

    if (s_filter_active) {
        for (int i = 0; i < k_fft_size; i++) {
            s_raw_block[i] = s_ring[(rd + (uint32_t)i) & k_ring_mask];
        }
        dsps_biquad_f32(s_raw_block, s_filtered, k_fft_size, s_bq_coeffs, s_bq_delay);
        s_filtered_val = s_filtered[k_fft_size - 1];
    } else {
        s_filtered_val = s_ring[(rd + (uint32_t)k_fft_size - 1) & k_ring_mask];
    }

    atomic_store_explicit(&s_ring_rd, rd + (uint32_t)k_fft_size, memory_order_release);

    dsps_fft2r_fc32(s_fft_buf, k_fft_size);
    dsps_bit_rev_fc32_ansi(s_fft_buf, k_fft_size);

    const int write_idx = 1 - atomic_load_explicit(&s_result_idx, memory_order_relaxed);
    spectrum_result_t *res = &s_result_buf[write_idx];

    float peak_mag = 0.0f;
    int peak_bin = 0;

    for (int k = 0; k < k_spectrum_bins; k++) {
        const float re = s_fft_buf[k * 2];
        const float im = s_fft_buf[k * 2 + 1];
        const float mag = sqrtf(re * re + im * im) / (float)k_fft_size;
        res->magnitude[k] = mag;

        if (k > 0 && mag > peak_mag) {
            peak_mag = mag;
            peak_bin = k;
        }
    }

    res->bin_resolution = (float)s_sample_rate / (float)k_fft_size;
    res->peak_freq = (float)peak_bin * res->bin_resolution;
    res->peak_mag = peak_mag;
    res->timestamp_ms = (uint32_t)(esp_timer_get_time() / 1000);
    res->valid = true;

    atomic_store_explicit(&s_result_idx, write_idx, memory_order_release);
    s_frame_count++;
}

float modulus_dsp_peak_frequency(void)
{
    const int idx = atomic_load_explicit(&s_result_idx, memory_order_acquire);
    return s_result_buf[idx].valid ? s_result_buf[idx].peak_freq : 0.0f;
}

uint32_t modulus_dsp_frame_count(void)
{
    return s_frame_count;
}
