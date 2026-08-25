#pragma once

#include <stdbool.h>
#include <stdint.h>

/** Register SDIO RX handler once. */
void modulus_espnow_stack_register(void);

/** Init/deinit C6 esp_now radio (SDIO commands). */
bool modulus_espnow_stack_init(void);
void modulus_espnow_stack_deinit(void);
bool modulus_espnow_stack_inited(void);

/** Apply PMK when encryption enabled. */
void modulus_espnow_stack_set_pmk(const uint8_t pmk[16]);

/** Add/delete peers on C6. Returns false if SDIO TX fails. */
bool modulus_espnow_stack_add_peer(const uint8_t mac[6], uint8_t channel, bool encrypt);
bool modulus_espnow_stack_del_peer(const uint8_t mac[6]);

/** Set peer PHY rate (ESPNOW_RATE_*). Applied after add_peer from NVS en_rate. */
bool modulus_espnow_stack_set_rate(const uint8_t mac[6], uint8_t rate_idx);

/** Unicast/broadcast send via C6 (waits for SEND_OK/FAIL). */
bool modulus_espnow_stack_send(const uint8_t mac[6], const uint8_t *data, size_t len);

/** Discovery: bcast peer + MOD_PROBE (matches reference hal_wireless scan). */
bool modulus_espnow_stack_probe(uint8_t channel);

/** Wait for C6 ESPNOW_EVT_INIT_OK after init (polls s_inited). */
bool modulus_espnow_stack_wait_inited(uint32_t timeout_ms);

/** SDIO settle + INIT with one retry; use after WiFi stack is up. */
/** C6 init budget — keep short; deferred reconnect retries if not ready. */
#define MODULUS_ESPNOW_INIT_WAIT_MS 1200U
bool modulus_espnow_stack_ensure_inited(uint32_t timeout_ms);

typedef void (*modulus_espnow_stack_evt_fn)(uint8_t evt, const uint8_t *payload, uint16_t len,
                                            void *ctx);

void modulus_espnow_stack_set_evt_hook(modulus_espnow_stack_evt_fn fn, void *ctx);

/** Re-apply bridge peer after NVS/channel change while transport open. */
void modulus_espnow_transport_reapply_peer(void);

/** C6: reassert WiFi channel + PS_NONE (compat; Zigbee/Thread no longer on C6). */
bool modulus_espnow_stack_lock_channel(void);

/** Bridge link RSSI in dBm from throttled C6 telemetry (false = none yet). */
bool modulus_espnow_stack_bridge_rssi(int8_t *out_dbm);
