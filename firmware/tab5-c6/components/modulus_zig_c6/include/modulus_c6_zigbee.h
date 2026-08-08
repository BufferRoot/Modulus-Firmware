#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Zigbee on C6; defers until esp_wifi up when exclusive. Idempotent. */
void modulus_c6_zigbee_init(void);

void modulus_c6_zigbee_poll(void);

bool modulus_c6_zigbee_ready(void);

/** 0=off/deferred, 1=ready (stack init, factory-new/disabled net), 2=error */
uint8_t modulus_c6_zigbee_status(void);

#ifdef __cplusplus
}
#endif
