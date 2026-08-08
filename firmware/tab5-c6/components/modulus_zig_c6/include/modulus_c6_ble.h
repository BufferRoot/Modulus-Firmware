#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** NimBLE controller + GAP name; safe after esp_hosted_coprocessor_init(). Idempotent. */
void modulus_c6_ble_init(void);

bool modulus_c6_ble_ready(void);

/** 0=off/disabled, 1=ready, 2=error (see detail in logs). */
uint8_t modulus_c6_ble_status(void);

#ifdef __cplusplus
}
#endif
