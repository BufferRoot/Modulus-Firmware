#pragma once

#ifdef __cplusplus
extern "C" {
#endif

void modulus_c6_runtime_start(void);

/** Spawn low-priority FreeRTOS task (Phase 8c hosted+Zig). Safe after esp_hosted_coprocessor_init(). */
void modulus_c6_runtime_start_task(void);

#ifdef __cplusplus
}
#endif
