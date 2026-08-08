/*

 * ESP-NOW handler for ESP-Hosted slave

 * Receives commands from host (P4) over SDIO ESP_ESPNOW_IF channel,

 * executes ESP-NOW operations locally on the C6 radio,

 * and forwards received ESP-NOW data back to the host.

 *

 * Protocol (host → slave):

 *   [cmd:1][payload...]

 *     CMD_INIT       0x01

 *     CMD_DEINIT     0x02

 *     CMD_ADD_PEER   0x03  [mac:6][channel:1][encrypt:1]

 *     CMD_DEL_PEER   0x04  [mac:6]

 *     CMD_SEND       0x05  [dst_mac:6][data:N]

 *     CMD_SET_PMK    0x06  [pmk:16]

 *     CMD_PROBE      0x07  [channel:1]  broadcast Modulus probe

 *     CMD_LOCK_CH    0x08  reassert WiFi ch + PS_NONE (compat)

 *     CMD_SET_RATE   0x09  [mac:6][rate_idx:1]  see ESPNOW_RATE_*

 *

 * Protocol (slave → host):

 *   [evt:1][payload...]

 *     EVT_INIT_OK    0x81

 *     EVT_INIT_FAIL  0x82  [err:1]

 *     EVT_SEND_OK    0x83  [mac:6]

 *     EVT_SEND_FAIL  0x84  [mac:6][reason:1] esp_err or esp_now_send_status_t

 *     EVT_RECV       0x85  [src_mac:6][data:N]

 *     EVT_DISCOVER   0x86  [src_mac:6][rssi:1]

 *     EVT_PEER_OK    0x87  [mac:6]

 *     EVT_PEER_FAIL  0x88  [mac:6][err:1]

 */

#ifndef ESPNOW_HANDLER_H

#define ESPNOW_HANDLER_H



#include <stdint.h>

#include <stddef.h>



/* Commands from host */

#define ESPNOW_CMD_INIT       0x01

#define ESPNOW_CMD_DEINIT     0x02

#define ESPNOW_CMD_ADD_PEER   0x03

#define ESPNOW_CMD_DEL_PEER   0x04

#define ESPNOW_CMD_SEND       0x05

#define ESPNOW_CMD_SET_PMK    0x06

#define ESPNOW_CMD_PROBE      0x07

#define ESPNOW_CMD_LOCK_CHANNEL 0x08

#define ESPNOW_CMD_SET_RATE   0x09



/* Rate idx for CMD_SET_RATE / NVS en_rate.
 * 0-3: 802.11b long preamble (max compat / range).
 * 4-6: OFDM (11g) - ~5-20x less airtime per frame than 11b for CNC traffic.
 * 7-8: HT20 MCS (11n) - highest throughput; receiver must have bgn enabled
 *      (S3 bridge default protocol mask includes b/g/n, so all decode). */

#define ESPNOW_RATE_1M   0

#define ESPNOW_RATE_2M   1

#define ESPNOW_RATE_5M5  2

#define ESPNOW_RATE_11M  3
#define ESPNOW_RATE_6M   4
#define ESPNOW_RATE_12M  5
#define ESPNOW_RATE_24M  6
#define ESPNOW_RATE_MCS0 7
#define ESPNOW_RATE_MCS3 8



/* v2 ceiling; C6 clamps to negotiated esp_now version at init */

#define ESPNOW_MAX_PAYLOAD 1470



/* Events to host */

#define ESPNOW_EVT_INIT_OK    0x81

#define ESPNOW_EVT_INIT_FAIL  0x82

#define ESPNOW_EVT_SEND_OK    0x83

#define ESPNOW_EVT_SEND_FAIL  0x84

#define ESPNOW_EVT_RECV       0x85

#define ESPNOW_EVT_DISCOVER   0x86

#define ESPNOW_EVT_PEER_OK    0x87

#define ESPNOW_EVT_PEER_FAIL  0x88

#define ESPNOW_EVT_PROBE_FAIL 0x89  /* [err:1] esp_err from probe path */
#define ESPNOW_EVT_RSSI       0x8A  /* [src_mac:6][rssi:s8] throttled link quality */



/**

 * Process an ESP-NOW command packet received from the host.

 * @param payload  Command data (first byte is the command ID)

 * @param len      Length of payload

 */

void espnow_process_host_cmd(const uint8_t *payload, uint16_t len);



/* Current Wi-Fi primary channel ESP-NOW is locked to (1-13). */

uint8_t espnow_current_wifi_channel(void);



#endif /* ESPNOW_HANDLER_H */


