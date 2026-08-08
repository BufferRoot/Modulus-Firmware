#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void modulus_dsp_init(void);
void modulus_dsp_deinit(void);
void modulus_dsp_process(void);
bool modulus_dsp_is_ready(void);
void modulus_dsp_push_sample(float sample);
float modulus_dsp_peak_frequency(void);
uint32_t modulus_dsp_frame_count(void);

#ifdef __cplusplus
}
#endif
