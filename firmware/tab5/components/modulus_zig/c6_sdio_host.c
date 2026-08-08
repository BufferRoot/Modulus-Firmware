/*
 * P4 host SDIO bridge for Modulus custom IF channels (ESP-NOW / Zigbee / Thread).
 * TX via esp_hosted_tx; RX via patch in sdio_drv.c -> modulus_c6_sdio_rx_dispatch.
 *
 * Zigbee host cmds use NanoH2 UART (zb_uart_host), not this SDIO path.
 * Thread / ESP-NOW custom IF frames use this SDIO bridge.
 */
#include "c6_sdio_host.h"
#include "tab5_pi4ioe.h"

#include "esp_err.h"
#include "esp_hosted_interface.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/portmacro.h"
#include "transport_drv.h"

#include <assert.h>
#include <string.h>

static const char *TAG = "c6_sdio";

#define TX_POOL_N 4
/* Must fit ESP-NOW v2 frame: opcode + MAC + ESPNOW_MAX_PAYLOAD (1470). */
#define TX_POOL_MAX (1 + 6 + 1470)
_Static_assert(TX_POOL_MAX >= 1477, "TX pool smaller than ESP-NOW max frame");

typedef struct {
    modulus_c6_rx_fn fn;
    void *ctx;
} rx_slot_t;

typedef struct {
    uint8_t data[TX_POOL_MAX];
    bool in_use;
} tx_slot_t;

static rx_slot_t s_rx[ESP_MAX_IF];
static bool s_inited;
static modulus_c6_sdio_health_t s_health;
static tx_slot_t s_tx_pool[TX_POOL_N];
static portMUX_TYPE s_tx_mux = portMUX_INITIALIZER_UNLOCKED;

static void tx_pool_free(void *p)
{
    if (!p) {
        return;
    }
    taskENTER_CRITICAL(&s_tx_mux);
    for (int i = 0; i < TX_POOL_N; i++) {
        if (s_tx_pool[i].data == (uint8_t *)p) {
            s_tx_pool[i].in_use = false;
            break;
        }
    }
    taskEXIT_CRITICAL(&s_tx_mux);
}

static uint8_t *tx_pool_alloc(uint16_t len)
{
    if (len == 0 || len > TX_POOL_MAX) {
        return NULL;
    }
    taskENTER_CRITICAL(&s_tx_mux);
    for (int i = 0; i < TX_POOL_N; i++) {
        if (!s_tx_pool[i].in_use) {
            s_tx_pool[i].in_use = true;
            taskEXIT_CRITICAL(&s_tx_mux);
            return s_tx_pool[i].data;
        }
    }
    taskEXIT_CRITICAL(&s_tx_mux);
    return NULL;
}

bool modulus_c6_sdio_ready(void)
{
    return is_transport_tx_ready() != 0;
}

void modulus_c6_sdio_register_rx(uint8_t if_type, modulus_c6_rx_fn fn, void *ctx)
{
    if (if_type >= ESP_MAX_IF) {
        return;
    }
    s_rx[if_type].fn = fn;
    s_rx[if_type].ctx = ctx;
}

void modulus_c6_sdio_rx_dispatch(uint8_t if_type, const uint8_t *payload, uint16_t len)
{
    if (!payload || !len || if_type >= ESP_MAX_IF) {
        return;
    }
    if (s_rx[if_type].fn) {
        s_rx[if_type].fn(payload, len, s_rx[if_type].ctx);
        return;
    }
    ESP_LOGW(TAG, "IF %u rx %u bytes (no handler)", (unsigned)if_type, (unsigned)len);
}

bool modulus_c6_sdio_send(uint8_t if_type, const uint8_t *payload, uint16_t len)
{
    if (!payload || len == 0 || if_type >= ESP_MAX_IF) {
        return false;
    }
    if (!modulus_c6_sdio_ready()) {
        ESP_LOGW(TAG, "SDIO TX not ready (if=%u)", (unsigned)if_type);
        return false;
    }

    uint8_t *buf = tx_pool_alloc(len);
    if (!buf) {
        ESP_LOGW(TAG, "TX pool exhausted (if=%u len=%u)", (unsigned)if_type, (unsigned)len);
        return false;
    }
    memcpy(buf, payload, len);

    int rc = esp_hosted_tx(if_type, 0, buf, len, H_BUFF_NO_ZEROCOPY, buf, tx_pool_free, 0);
    if (rc != ESP_OK) {
        ESP_LOGW(TAG, "esp_hosted_tx if=%u: %d", (unsigned)if_type, rc);
        tx_pool_free(buf);
        return false;
    }
    return true;
}

void modulus_c6_sdio_host_init(void)
{
    if (s_inited) {
        return;
    }
    s_inited = true;
    ESP_LOGI(TAG, "C6 SDIO custom IF host ready (TX pool %dx%u)", TX_POOL_N, TX_POOL_MAX);
}

void modulus_c6_sdio_health(uint32_t stream_drop, uint32_t queue_stall, uint32_t pad_skip)
{
    s_health.stream_drop = stream_drop;
    s_health.queue_stall = queue_stall;
    s_health.pad_skip = pad_skip;
}

void modulus_c6_sdio_health_get(modulus_c6_sdio_health_t *out)
{
    if (!out) {
        return;
    }
    *out = s_health;
}
