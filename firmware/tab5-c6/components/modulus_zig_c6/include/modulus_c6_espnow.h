#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** ESP-NOW on C6; requires esp_wifi started (esp_hosted init). Idempotent. */
void modulus_c6_espnow_init(void);

bool modulus_c6_espnow_ready(void);

/** 0=off/disabled, 1=ready, 2=error (see detail in logs). */
uint8_t modulus_c6_espnow_status(void);

/** Optional broadcast test payload "MODULUS"; no-op if not ready. */
void modulus_c6_espnow_send_test(void);

/** Retry init when esp_hosted RPC brings Wi-Fi up on C6. */
void modulus_c6_espnow_poll(void);

#ifdef __cplusplus
}
#endif
