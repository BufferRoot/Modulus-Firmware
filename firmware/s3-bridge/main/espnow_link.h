#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Initialise ESP-NOW radio (WiFi STA, channel from NVS, peer auto-learned) */
void     espnow_init();

/* Start Tab5→UART worker (call after uart_bridge_init) */
void     espnow_start_inbound_worker();

/* Flush deferred MOD_ACK (safe from task context; no-op if none pending) */
void     espnow_flush_pending_ack();

/* Live channel change (persists NVS, re-registers Tab5 peer) */
bool     espnow_set_channel(uint8_t ch);

/* Boot self-check + counter reset */
bool     espnow_self_check();
void     espnow_reset_stats();
bool     espnow_send_to_tab5(const uint8_t* data, size_t len);
/* Non-blocking UART→Tab5 queue (drops oldest on full). */
bool     espnow_queue_to_tab5(const uint8_t* data, size_t len);

/* Accessors used by the status shell */
uint8_t  espnow_get_channel();
const char* espnow_tab5_mac_str();
uint32_t espnow_rx_count();
uint32_t espnow_tx_count();
uint32_t espnow_fail_count();
uint32_t espnow_inbound_drops();
uint32_t espnow_inbound_pending();
uint32_t espnow_outbound_drops();
uint32_t espnow_outbound_pending();

#ifdef __cplusplus
}
#endif
