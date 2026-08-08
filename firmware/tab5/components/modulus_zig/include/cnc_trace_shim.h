#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** grblHAL outbound trace @ ESP_LOGV (Settings → Log level = Verbose). */
void modulus_cnc_trace_tx(const uint8_t *data, size_t len);

#ifdef __cplusplus
}
#endif
