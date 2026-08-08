/*
 * Framed UART link (NanoH2 side). See zb_uart_link.h for wiring + framing.
 * Static buffers only — no heap in the hot path.
 */
#include "zb_uart_link.h"
#include "nanoh2_hw.h"

#include "driver/uart.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#include <string.h>

static const char *TAG = "zb_link";

#define LINK_UART        UART_NUM_1
#define LINK_BAUD        460800
#define LINK_SOF         0xA5
#define LINK_RX_BUF      2048
#define LINK_SUPERV_US   (70LL * 1000 * 1000) /* host traffic / keepalive */

static zb_link_rx_fn      s_on_cmd;
static SemaphoreHandle_t  s_tx_mux;
static volatile int64_t   s_last_rx_us = -1;

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

bool zb_uart_link_send(const uint8_t *payload, uint16_t len)
{
    if (!payload || len == 0 || len > ZB_LINK_MAX_PAYLOAD || !s_tx_mux) {
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

bool zb_uart_link_host_alive(void)
{
    return s_last_rx_us >= 0 && (esp_timer_get_time() - s_last_rx_us) < LINK_SUPERV_US;
}

/* Byte-stream frame parser: tolerant of garbage between frames (resync on
 * SOF), bounded state — a corrupt length can never overrun the buffer. */
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
                    st = ST_SOF; /* bad length — resync */
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
                    if (s_on_cmd) {
                        s_on_cmd(body, need);
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

void zb_uart_link_init(zb_link_rx_fn on_cmd)
{
    s_on_cmd = on_cmd;
    s_tx_mux = xSemaphoreCreateMutex();

    const uart_config_t cfg = {
        .baud_rate = LINK_BAUD,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };
    ESP_ERROR_CHECK(uart_driver_install(LINK_UART, LINK_RX_BUF, LINK_RX_BUF, 0, NULL, 0));
    ESP_ERROR_CHECK(uart_param_config(LINK_UART, &cfg));
    ESP_ERROR_CHECK(uart_set_pin(LINK_UART, NANOH2_UART_TX, NANOH2_UART_RX,
                                 UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));

    /* Prio 6: above the ZBOSS hub task (5) so host commands preempt the
     * stack main loop briefly; command handlers hand off via esp_zb_lock. */
    (void)xTaskCreate(rx_task, "zb_link_rx", 3072, NULL, 6, NULL);
    ESP_LOGI(TAG, "UART link up (uart%d tx=%d rx=%d %d baud)",
             LINK_UART, NANOH2_UART_TX, NANOH2_UART_RX, LINK_BAUD);
}
