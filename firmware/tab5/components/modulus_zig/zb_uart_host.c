/*
 * P4 UART link to the NanoH2 Zigbee hub. See zb_uart_host.h.
 * Mirror framing with firmware/nanoh2/main/zb_uart_link.c.
 *
 * Cmd ACK wait runs on zb_uart_cmd worker (Core 1) — never on LVGL/Core 0.
 */
#include "zb_uart_host.h"
#include "tab5_hw.h"

#include "driver/uart.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#include <string.h>

static const char *TAG = "zb_uart";

#define LINK_UART           UART_NUM_2
#define LINK_BAUD           460800
#define LINK_SOF            0xA5
#define ZB_LINK_MAX_PAYLOAD 256u
#define LINK_RX_BUF         2048
#define LINK_SUPERV_US      (70LL * 1000 * 1000)
#define LINK_OFFLINE_US     (3LL * LINK_SUPERV_US)
#define CMD_ACK_TIMEOUT_MS  250
#define CMD_MAX_RETRIES     3
#define CMD_QUEUE_DEPTH     16

typedef struct {
    uint16_t len;
    uint8_t payload[ZB_LINK_MAX_PAYLOAD];
    SemaphoreHandle_t done; /* NULL = fire-and-forget */
    bool *ok_out;           /* optional result slot (set before give done) */
    uint32_t token;         /* sync wait generation; 0 = async */
} zb_cmd_job_t;

static modulus_zb_rx_fn  s_rx_fn;
static void             *s_rx_ctx;
static SemaphoreHandle_t s_tx_mux;
static SemaphoreHandle_t s_ack_sem;
static QueueHandle_t     s_cmd_q;
static SemaphoreHandle_t s_sync_done; /* reused; never delete from waiter */
static bool              s_sync_ok;
static volatile bool     s_sync_busy;
static volatile uint32_t s_sync_token;
static volatile int64_t  s_last_rx_us = -1;
static bool              s_had_rx;
static bool              s_inited;
static uint8_t           s_tx_seq;
static volatile uint8_t  s_wait_seq;
static volatile uint8_t  s_ack_seq;
static volatile bool     s_ack_nak;
static volatile uint8_t  s_ack_reason;

static uint8_t crc8(const uint8_t *p, uint16_t n)
{
    uint8_t c = 0;
    while (n--) {
        c ^= *p++;
        for (int i = 0; i < 8; i++) {
            c = (uint8_t)((c & 0x80) ? (c << 1) ^ 0x07 : (c << 1));
        }
    }
    return c;
}

bool modulus_zb_uart_send(const uint8_t *payload, uint16_t len)
{
    if (!payload || len == 0 || len > ZB_LINK_MAX_PAYLOAD || !s_inited) {
        return false;
    }
    uint8_t frame[3 + ZB_LINK_MAX_PAYLOAD + 1];
    frame[0] = LINK_SOF;
    frame[1] = (uint8_t)(len & 0xFF);
    frame[2] = (uint8_t)(len >> 8);
    memcpy(&frame[3], payload, len);
    frame[3 + len] = crc8(payload, len);

    xSemaphoreTake(s_tx_mux, portMAX_DELAY);
    const int w = uart_write_bytes(LINK_UART, frame, (size_t)(4 + len));
    xSemaphoreGive(s_tx_mux);
    return w == (int)(4 + len);
}

void modulus_zb_uart_note_ack(uint8_t seq, bool nak, uint8_t reason)
{
    if (!s_ack_sem || seq == 0 || seq != s_wait_seq) {
        return;
    }
    s_ack_seq = seq;
    s_ack_nak = nak;
    s_ack_reason = reason;
    xSemaphoreGive(s_ack_sem);
}

static bool send_cmd_blocking(const uint8_t *cmd_payload, uint16_t len)
{
    for (int attempt = 0; attempt < CMD_MAX_RETRIES; attempt++) {
        uint8_t seq = ++s_tx_seq;
        if (seq == 0) {
            seq = ++s_tx_seq;
        }

        uint8_t wire[1 + ZB_LINK_MAX_PAYLOAD];
        wire[0] = seq;
        memcpy(&wire[1], cmd_payload, len);

        s_wait_seq = seq;
        s_ack_seq = 0;
        while (xSemaphoreTake(s_ack_sem, 0) == pdTRUE) {
        }

        if (!modulus_zb_uart_send(wire, (uint16_t)(1 + len))) {
            s_wait_seq = 0;
            return false;
        }

        if (xSemaphoreTake(s_ack_sem, pdMS_TO_TICKS(CMD_ACK_TIMEOUT_MS)) == pdTRUE &&
            s_ack_seq == seq) {
            s_wait_seq = 0;
            if (s_ack_nak) {
                ESP_LOGW(TAG, "cmd 0x%02x NAK seq=%u reason=0x%02x",
                         cmd_payload[0], (unsigned)seq, (unsigned)s_ack_reason);
                return false;
            }
            return true;
        }
        ESP_LOGW(TAG, "cmd 0x%02x seq=%u ACK timeout (try %d/%d)",
                 cmd_payload[0], (unsigned)seq, attempt + 1, CMD_MAX_RETRIES);
    }
    s_wait_seq = 0;
    return false;
}

static void cmd_worker(void *arg)
{
    (void)arg;
    zb_cmd_job_t job;
    for (;;) {
        if (xQueueReceive(s_cmd_q, &job, portMAX_DELAY) != pdTRUE) {
            continue;
        }
        const bool ok = send_cmd_blocking(job.payload, job.len);
        if (job.token != 0 && job.token != s_sync_token) {
            continue; /* waiter abandoned this sync job */
        }
        if (job.ok_out) {
            *job.ok_out = ok;
        }
        if (job.done) {
            xSemaphoreGive(job.done);
        }
    }
}

static bool enqueue_cmd(const uint8_t *cmd_payload, uint16_t len, bool wait_result)
{
    if (!cmd_payload || len == 0 || len + 1u > ZB_LINK_MAX_PAYLOAD || !s_inited || !s_cmd_q) {
        return false;
    }

    zb_cmd_job_t job = {};
    job.len = len;
    memcpy(job.payload, cmd_payload, len);

    if (wait_result) {
        if (!s_sync_done || s_sync_busy) {
            return false;
        }
        s_sync_busy = true;
        s_sync_ok = false;
        const uint32_t token = s_sync_token + 1u;
        s_sync_token = token == 0 ? 1u : token;
        while (xSemaphoreTake(s_sync_done, 0) == pdTRUE) {
        }
        job.done = s_sync_done;
        job.ok_out = &s_sync_ok;
        job.token = s_sync_token;
    }

    if (xQueueSend(s_cmd_q, &job, pdMS_TO_TICKS(50)) != pdTRUE) {
        ESP_LOGW(TAG, "cmd queue full (drop 0x%02x)", cmd_payload[0]);
        if (wait_result) {
            s_sync_busy = false;
        }
        return false;
    }

    if (!wait_result) {
        return true; /* queued */
    }

    /* Sync wait — only from non-LVGL tasks (zb_auto worker). Static done-sem:
     * never delete while cmd_worker may still Give (UAF on timeout). */
    if (xSemaphoreTake(s_sync_done, pdMS_TO_TICKS(CMD_ACK_TIMEOUT_MS * CMD_MAX_RETRIES + 200)) !=
        pdTRUE) {
        ESP_LOGW(TAG, "cmd worker wait timeout 0x%02x", cmd_payload[0]);
        s_sync_token++; /* invalidate in-flight job */
        s_sync_ok = false;
        (void)xSemaphoreTake(s_sync_done, 0); /* drain late Give */
    }
    s_sync_busy = false;
    return s_sync_ok;
}

bool modulus_zb_uart_send_cmd(const uint8_t *cmd_payload, uint16_t len)
{
    /* Fire-and-forget from any thread (UI-safe). ACK handled on cmd worker. */
    return enqueue_cmd(cmd_payload, len, false);
}

bool modulus_zb_uart_send_cmd_sync(const uint8_t *cmd_payload, uint16_t len)
{
    return enqueue_cmd(cmd_payload, len, true);
}

bool modulus_zb_uart_ready(void)
{
    return s_inited && s_last_rx_us >= 0 &&
           (esp_timer_get_time() - s_last_rx_us) < LINK_SUPERV_US;
}

bool modulus_zb_uart_hub_offline(void)
{
    return s_inited && s_had_rx && s_last_rx_us >= 0 &&
           (esp_timer_get_time() - s_last_rx_us) >= LINK_OFFLINE_US;
}

static void rx_task(void *arg)
{
    (void)arg;
    enum { ST_SOF, ST_LEN0, ST_LEN1, ST_BODY, ST_CRC } st = ST_SOF;
    static uint8_t body[ZB_LINK_MAX_PAYLOAD];
    uint16_t need = 0, got = 0;
    uint8_t chunk[64];

    for (;;) {
        const int n = uart_read_bytes(LINK_UART, chunk, sizeof(chunk), pdMS_TO_TICKS(250));
        for (int i = 0; i < n; i++) {
            const uint8_t b = chunk[i];
            switch (st) {
            case ST_SOF:
                st = (b == LINK_SOF) ? ST_LEN0 : ST_SOF;
                break;
            case ST_LEN0:
                need = b;
                st = ST_LEN1;
                break;
            case ST_LEN1:
                need |= (uint16_t)b << 8;
                if (need == 0 || need > ZB_LINK_MAX_PAYLOAD) {
                    st = ST_SOF;
                } else {
                    got = 0;
                    st = ST_BODY;
                }
                break;
            case ST_BODY:
                body[got++] = b;
                if (got == need) {
                    st = ST_CRC;
                }
                break;
            case ST_CRC:
                if (crc8(body, need) == b) {
                    s_last_rx_us = esp_timer_get_time();
                    s_had_rx = true;
                    if (s_rx_fn) {
                        s_rx_fn(body, need, s_rx_ctx);
                    }
                } else {
                    ESP_LOGW(TAG, "frame CRC mismatch (len %u)", (unsigned)need);
                }
                st = ST_SOF;
                break;
            }
        }
    }
}

void modulus_zb_uart_init(modulus_zb_rx_fn rx, void *ctx)
{
    if (s_inited) {
        return;
    }
    s_rx_fn = rx;
    s_rx_ctx = ctx;
    s_tx_mux = xSemaphoreCreateMutex();
    s_ack_sem = xSemaphoreCreateBinary();
    s_sync_done = xSemaphoreCreateBinary();
    s_cmd_q = xQueueCreate(CMD_QUEUE_DEPTH, sizeof(zb_cmd_job_t));
    if (!s_tx_mux || !s_ack_sem || !s_sync_done || !s_cmd_q) {
        ESP_LOGE(TAG, "Zigbee UART sync objects alloc failed");
        if (s_tx_mux) {
            vSemaphoreDelete(s_tx_mux);
            s_tx_mux = NULL;
        }
        if (s_ack_sem) {
            vSemaphoreDelete(s_ack_sem);
            s_ack_sem = NULL;
        }
        if (s_sync_done) {
            vSemaphoreDelete(s_sync_done);
            s_sync_done = NULL;
        }
        if (s_cmd_q) {
            vQueueDelete(s_cmd_q);
            s_cmd_q = NULL;
        }
        return;
    }

    const uart_config_t cfg = {
        .baud_rate = LINK_BAUD,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };
    esp_err_t err = uart_driver_install(LINK_UART, LINK_RX_BUF, LINK_RX_BUF, 0, NULL, 0);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "uart_driver_install: %s — Zigbee link offline", esp_err_to_name(err));
        return;
    }
    err = uart_param_config(LINK_UART, &cfg);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "uart_param_config: %s", esp_err_to_name(err));
        (void)uart_driver_delete(LINK_UART);
        return;
    }
    err = uart_set_pin(LINK_UART, TAB5_ZB_UART_TX_GPIO, TAB5_ZB_UART_RX_GPIO,
                       UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "uart_set_pin: %s", esp_err_to_name(err));
        (void)uart_driver_delete(LINK_UART);
        return;
    }
    s_inited = true;

    (void)xTaskCreatePinnedToCore(rx_task, "zb_uart_rx", 3072, NULL, 6, NULL, 1);
    (void)xTaskCreatePinnedToCore(cmd_worker, "zb_uart_cmd", 3072, NULL, 5, NULL, 1);
    ESP_LOGI(TAG, "NanoH2 Zigbee link up (uart%d tx=%d rx=%d %d baud, async cmd+ACK)",
             LINK_UART, TAB5_ZB_UART_TX_GPIO, TAB5_ZB_UART_RX_GPIO, LINK_BAUD);
}
