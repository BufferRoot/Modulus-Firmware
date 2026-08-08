#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/** OpenThread on C6; defers until esp_wifi up (coex with Wi-Fi/BLE). Idempotent. */
void modulus_c6_thread_init(void);

void modulus_c6_thread_poll(void);

bool modulus_c6_thread_ready(void);

/** 0=off/deferred, 1=ready (stack+radio, detached), 2=error */
uint8_t modulus_c6_thread_status(void);

/**
 * Border-router / network attach — not implemented on default 8c image.
 * MTD stays detached (CONFIG_OPENTHREAD_BORDER_ROUTER=n) for Wi-Fi/BLE coex.
 */
esp_err_t modulus_c6_thread_request_attach(void);

#ifdef __cplusplus
}
#endif
