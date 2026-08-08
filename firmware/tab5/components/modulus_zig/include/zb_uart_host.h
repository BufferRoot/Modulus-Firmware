#pragma once
/*
 * P4 host UART link to the NanoH2 Zigbee hub.
 *
 * Zigbee moved off the C6 (which shared ONE 2.4 GHz radio between Wi-Fi/
 * ESP-NOW and 802.15.4 — the root cause of "ESP-NOW drops when Zigbee is
 * active") onto a dedicated ESP32-H2. This link replaces the SDIO
 * ESP_ZIGBEE_IF channel; the byte protocol (zb_link_proto.h) is unchanged.
 *
 * Wiring (Tab5 M5BUS <-> NanoH2 Grove):
 *   M5BUS pin 16 G14/TXD2 (P4 GPIO6)  -> Grove G2 yellow (H2 RX)
 *   M5BUS pin 15 G13/RXD2 (P4 GPIO7) <-  Grove G1 white  (H2 TX)
 *   M5BUS GND (1/3/5) -> Grove GND;  M5BUS pin 28 SYS_EXT5VO -> Grove 5V
 *
 * Frame: [0xA5][len_lo][len_hi][payload:len][crc8(payload), poly 0x07]
 * Cmds:  [seq:1][cmd:1][args...] with EVT_ACK/NAK replies (retries here).
 */
#include <stdbool.h>
#include <stdint.h>

typedef void (*modulus_zb_rx_fn)(const uint8_t *payload, uint16_t len, void *ctx);

/* Install UART2 + RX task. Idempotent. rx runs in the link RX task. */
void modulus_zb_uart_init(modulus_zb_rx_fn rx, void *ctx);

/* Raw frame TX (events path / internal). Prefer send_cmd for host commands. */
bool modulus_zb_uart_send(const uint8_t *payload, uint16_t len);

/*
 * Send sequenced cmd [seq][cmd...][args], ACK/retry on zb_uart_cmd worker.
 * Non-blocking: queues and returns true if accepted (UI-safe).
 */
bool modulus_zb_uart_send_cmd(const uint8_t *cmd_payload, uint16_t len);

/*
 * Same as send_cmd but waits for ACK on the calling thread.
 * Only call from non-LVGL tasks (e.g. zb_auto worker).
 */
bool modulus_zb_uart_send_cmd_sync(const uint8_t *cmd_payload, uint16_t len);

/* RX path: feed ACK/NAK from zigbee_rx so send_cmd can unblock. */
void modulus_zb_uart_note_ack(uint8_t seq, bool nak, uint8_t reason);

/* True if a valid frame from the hub arrived within the supervision window.
 * Hub heartbeats HUB_STATE every ~5 s when formed. */
bool modulus_zb_uart_ready(void);

/* Sustained loss after we had link: silence >= 3 supervision windows (~210 s).
 * Distinct from never-connected (ready false, last_rx never set). */
bool modulus_zb_uart_hub_offline(void);
