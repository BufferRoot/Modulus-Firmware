/*
 * Zigbee handler stub (C6).
 *
 * Zigbee has moved OFF the C6 to a dedicated ESP32-H2 (NanoH2) reached over a
 * framed UART link from the P4 — the C6 no longer touches 802.15.4 at all.
 * This eliminates the Wi-Fi/802.15.4 coexistence that caused ESP-NOW to drop
 * whenever Zigbee was active on the shared radio.
 *
 * The ESP_ZIGBEE_IF SDIO channel is retained only so a stale P4 build that
 * still routes Zigbee over SDIO gets a clean EVT_FAIL instead of silence.
 * New P4 firmware sends Zigbee over the NanoH2 UART link and never reaches
 * this path.
 */
#include "zigbee_handler.h"
#include "esp_log.h"
#include "esp_hosted_interface.h"
#include "interface.h"
#include <stdlib.h>
#include <string.h>

static const char *TAG = "zigbee_hdl";

extern int send_to_host_queue(interface_buffer_handle_t *buf_handle, uint8_t queue_type);

void zigbee_process_host_cmd(const uint8_t *payload, uint16_t len)
{
    if (!payload || len < 1) {
        return;
    }
    ESP_LOGW(TAG, "Zigbee cmd 0x%02x ignored — Zigbee runs on NanoH2 now", payload[0]);

    /* Reply EVT_FAIL(reason 0x30 = wrong-transport) so a legacy host doesn't
     * hang waiting on a response. */
    uint8_t msg[2] = {ZIGBEE_EVT_FAIL, 0x30};
    uint8_t *buf = (uint8_t *)malloc(sizeof(msg));
    if (!buf) {
        return;
    }
    memcpy(buf, msg, sizeof(msg));

    interface_buffer_handle_t bh = {0};
    bh.if_type            = ESP_ZIGBEE_IF;
    bh.if_num             = 0;
    bh.payload            = buf;
    bh.payload_len        = sizeof(msg);
    bh.priv_buffer_handle = buf;
    bh.free_buf_handle    = free;

    if (send_to_host_queue(&bh, PRIO_Q_OTHERS) != 0) {
        free(buf);
    }
}
