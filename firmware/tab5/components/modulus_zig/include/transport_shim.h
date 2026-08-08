#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Zig ABI — RX reuses serial feed; connect/disconnect notify CNC driver */
extern void modulus_zig_serial_rx(const uint8_t *data, size_t len);
extern void modulus_zig_transport_on_connect(void);
extern void modulus_zig_transport_on_disconnect(void);

/* WebSocket (lwIP TCP + minimal RFC6455 client) */
bool modulus_ws_start(const char *host, uint16_t port, const char *path, bool tls);
void modulus_ws_stop(void);
bool modulus_ws_send(const uint8_t *data, size_t len);
bool modulus_ws_is_connected(void);

/* Telnet (raw TCP byte stream) */
bool modulus_telnet_start(const char *host, uint16_t port);
void modulus_telnet_stop(void);
bool modulus_telnet_send(const uint8_t *data, size_t len);
bool modulus_telnet_is_connected(void);

/* Masso Link UDP (send 11000–11050, recv 65535) */
bool modulus_masso_udp_start(const char *host, uint16_t tx_port, uint16_t rx_port);
void modulus_masso_udp_stop(void);
bool modulus_masso_udp_send(const uint8_t *data, size_t len);
bool modulus_masso_udp_is_connected(void);

/* I2C master transport (ext bus, register framing) */
bool modulus_i2c_transport_start(uint8_t addr, uint8_t spd_idx);
void modulus_i2c_transport_stop(void);
bool modulus_i2c_transport_send(const uint8_t *data, size_t len);

/* CAN bus (TWAI, fragmented frames) */
bool modulus_canbus_start(uint8_t brate_idx, uint8_t nid, uint8_t mode_idx);
void modulus_canbus_stop(void);
bool modulus_canbus_send(const uint8_t *data, size_t len);

/* ESP-NOW (C6 radio via esp_now on esp_wifi_remote) */
bool modulus_espnow_transport_start(const char *mac_str, uint8_t channel, bool encrypt);
void modulus_espnow_transport_stop(void);
bool modulus_espnow_transport_send(const uint8_t *data, size_t len);
bool modulus_espnow_transport_is_open(void);

/** Side-band HALT_host on S3 bridge (MOD_HALT1/MOD_HALT0). Works without CNC transport open. */
bool modulus_espnow_bridge_halt(bool assert);

/* BLE NUS transport — P4 NimBLE host over esp_hosted VHCI (C6 controller) */
bool modulus_ble_transport_start(const char *target_name);
void modulus_ble_transport_stop(void);
bool modulus_ble_transport_send(const uint8_t *data, size_t len);
bool modulus_ble_transport_is_connected(void);

/* BLE settings shell (NVS bt toggle; scan/pair list via ble_transport_shim) */
bool modulus_ble_settings_enable(void);
void modulus_ble_settings_disable(void);
bool modulus_ble_settings_is_enabled(void);

/** Soft-pause BLE HCI while ESP-NOW is CNC transport (no NVS flip). */
void modulus_ble_suspend_for_espnow(void);
void modulus_ble_resume_after_espnow(void);

const char *modulus_ble_settings_status_text(void);
const char *modulus_ble_settings_paired_text(void);
bool modulus_ble_settings_scan_start(void);
void modulus_ble_settings_scan_stop(void);
bool modulus_ble_settings_scan_done(void);
int modulus_ble_settings_scan_count(void);
bool modulus_ble_settings_scan_get(int idx, char *name, size_t name_len, int8_t *rssi_out,
                                   char *addr_out, size_t addr_len);
bool modulus_ble_settings_connect(int idx);
void modulus_ble_settings_disconnect(void);
bool modulus_ble_settings_is_connecting(void);
bool modulus_ble_settings_is_connected(void);
uint8_t modulus_ble_settings_passkey_state(void);
uint32_t modulus_ble_settings_passkey_value(void);
bool modulus_ble_settings_passkey_submit(uint32_t passkey);
bool modulus_ble_settings_passkey_confirm(void);
void modulus_ble_settings_passkey_cancel(void);
void modulus_ble_settings_clear_paired(void);

#ifdef __cplusplus
}
#endif
