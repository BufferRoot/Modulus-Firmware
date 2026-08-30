#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/** Bring up esp_netif + esp_wifi_remote (SDIO transport to C6). Idempotent. */
bool modulus_wireless_init(void);

/** True after successful modulus_wireless_init(). */
bool modulus_wireless_ready(void);

/** True after esp_wifi_start succeeds (esp_hosted SDIO transport up). */
bool modulus_wireless_transport_up(void);

/** True while C6 Wi-Fi STA is running (not after esp_wifi_stop / STA_STOP). */
bool modulus_wireless_wifi_sta_running(void);

/** Abort ESP-NOW scan when Wi-Fi STA stops (hosted STA_STOP / esp_wifi_stop). */
void modulus_wireless_espnow_on_wifi_stop(void);

/** Start esp_wifi if not already (SDIO up). Used by ESP-NOW/BLE radios. */
bool modulus_wireless_ensure_wifi_stack(void);

/** RF_PTH via PI4IOE1 P0 — low=internal, high=external MMCX. */
void modulus_wireless_set_antenna_external(bool external);
bool modulus_wireless_is_external_antenna(void);

/** Re-enable radios from NVS (wifi, espnow, zigbee, thread, bt). Call after init. */
void modulus_wireless_restore_settings(void);

/** Quiesce SDIO traffic before sleep (disable radios, stop Wi-Fi). */
void modulus_wireless_prepare_for_sleep(void);

/** Tear down esp_wifi / event handlers after prepare_for_sleep. */
void modulus_wireless_deinit(void);

/** Re-power C6, reset, and re-init hosted stack after deep sleep. */
bool modulus_wireless_wake_coprocessor(void);

/** Wait for C6 SDIO settle after restore — call before SD mount. */
void modulus_wireless_post_restore_settle(void);

/** Poll scan / ESP-NOW discovery (call from UI timer, ~1 s). */
void modulus_wireless_poll(void);

/** Serialize Wi-Fi scan, BLE enable, ESP-NOW scan on one C6 SDIO link. */
bool modulus_wireless_radio_op_try_take(uint32_t timeout_ms);
void modulus_wireless_radio_op_give(void);

/** Warn when the joined AP's channel differs from the ESP-NOW bridge channel.
 *  Never rewrites en_chan — the S3 bridge cannot follow a channel change. */
void modulus_wireless_espnow_check_channel_conflict(void);

/* ── Wi-Fi ─────────────────────────────────────────────────────── */

#define MODULUS_WIFI_MAX_SCAN 12

typedef struct {
    char ssid[33];
    int8_t rssi;
    uint8_t channel;
    uint8_t auth;
} modulus_wifi_ap_t;

bool modulus_wireless_wifi_enable(void);
void modulus_wireless_wifi_disable(void);
bool modulus_wireless_wifi_is_enabled(void);
bool modulus_wireless_wifi_is_connected(void);
bool modulus_wireless_wifi_is_connecting(void);

bool modulus_wireless_wifi_scan_start(void);
bool modulus_wireless_wifi_scan_done(void);
int modulus_wireless_wifi_scan_count(void);
bool modulus_wireless_wifi_scan_get(int idx, modulus_wifi_ap_t *out);

bool modulus_wireless_wifi_connect(const char *ssid, const char *pass);
/** Reconnect using `wf_ssid` / `wf_pass` from NVS (settings saved-network page). */
bool modulus_wireless_wifi_connect_saved(void);
bool modulus_wireless_wifi_disconnect(void);
void modulus_wireless_wifi_forget_saved(void);

/** Human-readable status for settings UI (static buffer). */
const char *modulus_wireless_wifi_radio_text(void);
const char *modulus_wireless_wifi_ssid_text(void);
const char *modulus_wireless_wifi_ip_text(void);
const char *modulus_wireless_wifi_error_text(void);
const char *modulus_wireless_wifi_scan_text(void);
bool modulus_wireless_wifi_ap_needs_pass(uint8_t auth);
const char *modulus_wireless_wifi_auth_text(uint8_t auth);

/* ── ESP-NOW (C6 SDIO channel 8) ─────────────────────────────── */

#define MODULUS_ESPNOW_MAX_SCAN 8
#define MODULUS_ESPNOW_MAX_PEERS 8

typedef struct {
    char mac[18];
    uint8_t mac_bytes[6];
    int8_t rssi;
    uint8_t channel;
} modulus_espnow_peer_t;

bool modulus_wireless_espnow_parse_mac(const char *mac_str, uint8_t out[6]);
void modulus_wireless_espnow_format_mac(const uint8_t mac[6], char *buf, size_t len);
uint8_t modulus_wireless_espnow_channel(void);
/** Persist bridge channel (1–13) to RAM + NVS — safe from SDIO RX context. */
void modulus_wireless_espnow_set_channel(uint8_t channel);
/** Reload channel cache after external NVS writes (settings dropdown). */
void modulus_wireless_espnow_channel_reload(void);

bool modulus_wireless_espnow_enable(void);
void modulus_wireless_espnow_apply_bridge_peer(void);
void modulus_wireless_espnow_boot_reconnect(void);
/** No-op on P4 — C6 owns PS/channel for ESP-NOW (see espnow_handler.c). */
void modulus_wireless_espnow_ensure_radio_awake(void);
/** Lock esp_wifi_remote STA to channel 1–13 (scan + CNC transport). */
void modulus_wireless_espnow_align_channel(uint8_t channel);
void modulus_wireless_espnow_disable(void);
bool modulus_wireless_espnow_is_enabled(void);
bool modulus_wireless_espnow_bridge_ready(void);
/** True when cnc_conn is ESP-NOW and the CNC transport shim is open (TX/RX active). */
bool modulus_wireless_espnow_transport_active(void);
void modulus_wireless_espnow_peer_mac_str(char *buf, size_t len);
bool modulus_wireless_espnow_set_peer_mac(const char *mac_str);
/** NVS bridge MAC only (no saved-list append). Used by CNC transport start so
 * radio toggle cannot resurrect a peer after Remove. User save → set_peer_mac. */
bool modulus_wireless_espnow_commit_peer_mac(const char *mac_str, bool sync_transport);
uint32_t modulus_wireless_espnow_tx_count(void);
uint32_t modulus_wireless_espnow_rx_count(void);
void modulus_wireless_espnow_tx_inc(void);
void modulus_wireless_espnow_rx_inc(void);

const char *modulus_wireless_espnow_bridge_text(void);
const char *modulus_wireless_espnow_scan_text(void);
bool modulus_wireless_espnow_scan_start(void);
bool modulus_wireless_espnow_scan_done(void);
bool modulus_wireless_espnow_scan_failed(void);
int modulus_wireless_espnow_scan_count(void);
bool modulus_wireless_espnow_scan_get(int idx, modulus_espnow_peer_t *out);
bool modulus_wireless_espnow_select_scan_peer(int idx);
bool modulus_wireless_espnow_remove_bridge_peer(void);
void modulus_wireless_espnow_clear_peers(void);

/* Saved peer list — persisted, switch/delete from settings UI. */
int modulus_wireless_espnow_saved_count(void);
bool modulus_wireless_espnow_saved_get(int idx, modulus_espnow_peer_t *out);
bool modulus_wireless_espnow_saved_is_active(int idx);
bool modulus_wireless_espnow_activate_saved(int idx);
bool modulus_wireless_espnow_delete_saved(int idx);
void modulus_wireless_espnow_poll_scan(void);
void modulus_wireless_espnow_transport_reinit(void);

/** Debug log level — see espnow_debug.h (`en_log` NVS). */
uint8_t modulus_wireless_espnow_log_level(void);
void modulus_wireless_espnow_log_set_level(uint8_t level);
bool modulus_wireless_espnow_debug_active(void);
const char *modulus_wireless_espnow_debug_snapshot(void);
const char *modulus_wireless_espnow_debug_last_event(void);

/* ── Bluetooth LE (NimBLE host on P4, VHCI to C6) ────────────── */

#define MODULUS_BLE_MAX_SCAN 12

const char *modulus_wireless_ble_status_text(void);
const char *modulus_wireless_ble_paired_text(void);
bool modulus_wireless_ble_enable(void);
void modulus_wireless_ble_disable(void);
bool modulus_wireless_ble_is_enabled(void);
/** One-shot latch: async enable worker failed (NimBLE/C6). */
bool modulus_wireless_ble_enable_failed(void);
bool modulus_wireless_ble_is_connecting(void);
bool modulus_wireless_ble_is_connected(void);
bool modulus_wireless_ble_scan_start(void);
void modulus_wireless_ble_scan_stop(void);
bool modulus_wireless_ble_scan_done(void);
int modulus_wireless_ble_scan_count(void);
bool modulus_wireless_ble_scan_get(int idx, char *name, size_t name_len, int8_t *rssi_out,
                                   char *addr_out, size_t addr_len);
bool modulus_wireless_ble_connect(int idx);
void modulus_wireless_ble_disconnect(void);
uint8_t modulus_wireless_ble_passkey_state(void);
uint32_t modulus_wireless_ble_passkey_value(void);
bool modulus_wireless_ble_passkey_submit(uint32_t passkey);
bool modulus_wireless_ble_passkey_confirm(void);
void modulus_wireless_ble_passkey_cancel(void);
void modulus_wireless_ble_clear_paired(void);

/* ── Zigbee = NanoH2 UART (ESP32-H2); Thread = C6 SDIO — not the same radio */

#include "wireless_shim_802154.h"

const char *modulus_wireless_zigbee_status_text(void);
const char *modulus_wireless_thread_status_text(void);
const char *modulus_wireless_zigbee_network_text(void);
const char *modulus_wireless_thread_network_text(void);
bool modulus_wireless_zigbee_enable(void);
void modulus_wireless_zigbee_disable(void);
/** False when C6 image has OpenThread disabled (default Modulus C6). */
bool modulus_wireless_thread_supported(void);
bool modulus_wireless_thread_enable(void);
void modulus_wireless_thread_disable(void);

/* Zig freestanding — c_int 0/1 (Zig #35373); wrap bool radio enable/wake. */
int modulus_wireless_wake_coprocessor_zi(void);
int modulus_wireless_wifi_enable_zi(void);
int modulus_wireless_ble_enable_zi(void);
int modulus_wireless_espnow_enable_zi(void);
int modulus_wireless_zigbee_enable_zi(void);
int modulus_wireless_thread_enable_zi(void);

bool modulus_wireless_zigbee_join(void);
/** True while async join is waiting for hub HUB_STATE. */
bool modulus_wireless_zigbee_join_pending(void);
void modulus_wireless_zigbee_join_poll(void);
bool modulus_wireless_zigbee_leave(void);
bool modulus_wireless_thread_attach(void);
bool modulus_wireless_thread_detach(void);
