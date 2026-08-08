#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef void (*modulus_c6_rx_fn)(const uint8_t *payload, uint16_t len, void *ctx);

/** True when esp_hosted SDIO TX path is up (post esp_wifi_start). */
bool modulus_c6_sdio_ready(void);

/** Send raw payload on custom SDIO IF (ESP_ESPNOW_IF / ZIGBEE / THREAD). */
bool modulus_c6_sdio_send(uint8_t if_type, const uint8_t *payload, uint16_t len);

void modulus_c6_sdio_register_rx(uint8_t if_type, modulus_c6_rx_fn fn, void *ctx);

/** Called from patched esp_hosted sdio_process_rx_task for custom IF types. */
void modulus_c6_sdio_rx_dispatch(uint8_t if_type, const uint8_t *payload, uint16_t len);

void modulus_c6_sdio_host_init(void);

/** Cumulative SDIO health counters (updated from patched esp_hosted sdio_drv). */
typedef struct {
    uint32_t stream_drop;
    uint32_t queue_stall;
    uint32_t pad_skip;
} modulus_c6_sdio_health_t;

void modulus_c6_sdio_health(uint32_t stream_drop, uint32_t queue_stall, uint32_t pad_skip);
void modulus_c6_sdio_health_get(modulus_c6_sdio_health_t *out);
