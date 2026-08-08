#pragma once
/*
 * Framed UART link to the Tab5 (ESP32-P4) host.
 *
 * Wiring (NanoH2 Grove <-> Tab5 M5BUS):
 *   Grove G1 (white,  H2 TX) -> M5BUS pin 15 G13/RXD2 (P4 GPIO7)
 *   Grove G2 (yellow, H2 RX) <- M5BUS pin 16 G14/TXD2 (P4 GPIO6)
 *   Grove GND                -> M5BUS pin 1/3/5 GND
 *   Grove 5V                 -> M5BUS pin 28 SYS_EXT5VO (EXT5V_EN gated)
 *
 * Frame: [0xA5][len_lo][len_hi][payload:len][crc8(payload), poly 0x07]
 * len 1..ZB_LINK_MAX_PAYLOAD. Receiver resyncs on the 0xA5 marker.
 *
 * Host cmds carry [seq][cmd][args]; hub ACKs/NAKs (see zb_proto.h).
 */
#include <stdbool.h>
#include <stdint.h>

#define ZB_LINK_MAX_PAYLOAD 256u

typedef void (*zb_link_rx_fn)(const uint8_t *payload, uint16_t len);

/* Start UART + RX task. on_cmd runs in the RX task context. */
void zb_uart_link_init(zb_link_rx_fn on_cmd);

/* Frame + transmit one payload. Thread-safe (internal mutex). */
bool zb_uart_link_send(const uint8_t *payload, uint16_t len);

/* True if a valid frame arrived within the supervision window. */
bool zb_uart_link_host_alive(void);
