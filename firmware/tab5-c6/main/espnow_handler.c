/*
 * ESP-NOW handler for ESP-Hosted slave (C6)
 * Bridges ESP-NOW operations between the P4 host and the C6 WiFi radio.
 *
 * Radio isolation: Zigbee lives on NanoH2; Thread is off in the Modulus
 * C6 image. This chip is Wi-Fi/ESP-NOW (+ optional BLE HCI) only — no
 * 802.15.4 time-slice. Fixed channel, PS_NONE, disconnected-STA PM off.
 */
#include "espnow_handler.h"
#include "esp_now.h"
#include "esp_wifi.h"
#include "esp_log.h"
#include "sdkconfig.h"
#include "esp_hosted_interface.h"
#include "esp_hosted_header.h"
#include "interface.h"
#include "freertos/FreeRTOS.h"
#include "freertos/portmacro.h"
#include <string.h>

static const char *TAG = "espnow_hdl";

/* Match S3 bridge (esp_wifi_set_max_tx_power(78) ≈ 19.5 dBm). */
#define ESPNOW_TX_POWER_QUARTER_DBM 78

/* CNC frames are small; 11 Mbps cuts airtime vs default 1 Mbps. */
#define ESPNOW_DEFAULT_RATE_IDX ESPNOW_RATE_11M

/* Fixed pool — Wi-Fi callbacks must not malloc. */
#define ESPNOW_POOL_N 8
#define ESPNOW_POOL_BYTES (1 + 6 + ESPNOW_MAX_PAYLOAD)

extern int send_to_host_queue(interface_buffer_handle_t *buf_handle, uint8_t queue_type);

static bool s_inited = false;
static uint8_t s_radio_ch = 1;
static uint8_t s_rate_idx = ESPNOW_DEFAULT_RATE_IDX;
static uint16_t s_max_payload = ESP_NOW_MAX_DATA_LEN;
static bool s_discover_mode;
static TickType_t s_discover_until;

static uint8_t s_pool[ESPNOW_POOL_N][ESPNOW_POOL_BYTES];
static uint8_t s_pool_busy;
static portMUX_TYPE s_pool_mux = portMUX_INITIALIZER_UNLOCKED;

uint8_t espnow_current_wifi_channel(void)
{
    return s_radio_ch;
}

static void *espnow_pool_alloc(uint16_t need)
{
    if (need > ESPNOW_POOL_BYTES) {
        return NULL;
    }
    taskENTER_CRITICAL(&s_pool_mux);
    for (int i = 0; i < ESPNOW_POOL_N; i++) {
        const uint8_t bit = (uint8_t)(1u << i);
        if ((s_pool_busy & bit) == 0) {
            s_pool_busy |= bit;
            taskEXIT_CRITICAL(&s_pool_mux);
            return s_pool[i];
        }
    }
    taskEXIT_CRITICAL(&s_pool_mux);
    return NULL;
}

static void espnow_pool_free(void *p)
{
    if (!p) {
        return;
    }
    taskENTER_CRITICAL(&s_pool_mux);
    for (int i = 0; i < ESPNOW_POOL_N; i++) {
        if (p == (void *)s_pool[i]) {
            s_pool_busy &= (uint8_t)~(1u << i);
            break;
        }
    }
    taskEXIT_CRITICAL(&s_pool_mux);
}

static bool espnow_rate_from_idx(uint8_t idx, wifi_phy_rate_t *out_rate,
                                 wifi_phy_mode_t *out_mode)
{
    switch (idx) {
    case ESPNOW_RATE_1M:
        *out_rate = WIFI_PHY_RATE_1M_L;
        *out_mode = WIFI_PHY_MODE_11B;
        return true;
    case ESPNOW_RATE_2M:
        *out_rate = WIFI_PHY_RATE_2M_L;
        *out_mode = WIFI_PHY_MODE_11B;
        return true;
    case ESPNOW_RATE_5M5:
        *out_rate = WIFI_PHY_RATE_5M_L;
        *out_mode = WIFI_PHY_MODE_11B;
        return true;
    case ESPNOW_RATE_11M:
        *out_rate = WIFI_PHY_RATE_11M_L;
        *out_mode = WIFI_PHY_MODE_11B;
        return true;
    case ESPNOW_RATE_6M:
        *out_rate = WIFI_PHY_RATE_6M;
        *out_mode = WIFI_PHY_MODE_11G;
        return true;
    case ESPNOW_RATE_12M:
        *out_rate = WIFI_PHY_RATE_12M;
        *out_mode = WIFI_PHY_MODE_11G;
        return true;
    case ESPNOW_RATE_24M:
        *out_rate = WIFI_PHY_RATE_24M;
        *out_mode = WIFI_PHY_MODE_11G;
        return true;
    case ESPNOW_RATE_MCS0:
        *out_rate = WIFI_PHY_RATE_MCS0_LGI;
        *out_mode = WIFI_PHY_MODE_HT20;
        return true;
    case ESPNOW_RATE_MCS3:
        *out_rate = WIFI_PHY_RATE_MCS3_LGI;
        *out_mode = WIFI_PHY_MODE_HT20;
        return true;
    default:
        return false;
    }
}

static esp_err_t espnow_apply_peer_rate(const uint8_t mac[6], uint8_t rate_idx)
{
    wifi_phy_rate_t phy_rate;
    wifi_phy_mode_t phy_mode;
    if (!espnow_rate_from_idx(rate_idx, &phy_rate, &phy_mode)) {
        return ESP_ERR_INVALID_ARG;
    }
    esp_now_rate_config_t cfg = {
        .phymode = phy_mode,
        .rate = phy_rate,
        .ersu = false,
        .dcm = false,
    };
    return esp_now_set_peer_rate_config(mac, &cfg);
}

/* Lock Wi-Fi PHY to ESP-NOW channel + PS_NONE. Call on init / add_peer / explicit
 * LOCK_CHANNEL — not on every SEND (no coex retune anymore). */
static esp_err_t espnow_lock_radio_channel(uint8_t ch)
{
    (void)esp_wifi_set_ps(WIFI_PS_NONE);
    if (ch < 1 || ch > 13) {
        ch = 1;
    }
    s_radio_ch = ch;

    uint8_t primary = 0;
    wifi_second_chan_t second = WIFI_SECOND_CHAN_NONE;
    if (esp_wifi_get_channel(&primary, &second) == ESP_OK && primary == ch) {
        return ESP_OK;
    }
    esp_err_t err = esp_wifi_set_channel(ch, WIFI_SECOND_CHAN_NONE);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "set_channel(%u): %s", (unsigned)ch, esp_err_to_name(err));
    }
    return err;
}

static void send_evt_to_host(uint8_t evt, const uint8_t *data, uint16_t data_len)
{
    uint16_t total = 1 + data_len;
    uint8_t *buf = (uint8_t *)espnow_pool_alloc(total);
    if (!buf) {
        ESP_LOGE(TAG, "evt pool empty for 0x%02x", evt);
        return;
    }
    buf[0] = evt;
    if (data && data_len) {
        memcpy(buf + 1, data, data_len);
    }

    interface_buffer_handle_t buf_handle = {0};
    buf_handle.if_type = ESP_ESPNOW_IF;
    buf_handle.if_num = 0;
    buf_handle.payload = buf;
    buf_handle.payload_len = total;
    buf_handle.priv_buffer_handle = buf;
    buf_handle.free_buf_handle = espnow_pool_free;

    /* Highest SDIO TX tier — CNC HALT / SEND_OK must beat misc RPC. */
    if (send_to_host_queue(&buf_handle, PRIO_Q_SERIAL) != 0) {
        ESP_LOGE(TAG, "Failed to queue evt 0x%02x to host", evt);
        espnow_pool_free(buf);
    }
}

static void espnow_send_cb(const uint8_t *mac_addr, esp_now_send_status_t status);

static void espnow_send_cb_v55(const esp_now_send_info_t *info, esp_now_send_status_t status)
{
    if (!info || !info->des_addr) {
        return;
    }
    espnow_send_cb(info->des_addr, status);
}

static void espnow_send_cb(const uint8_t *mac_addr, esp_now_send_status_t status)
{
    if (status == ESP_NOW_SEND_SUCCESS) {
        send_evt_to_host(ESPNOW_EVT_SEND_OK, mac_addr, 6);
        return;
    }
    /* A no-ACK is either "peer absent" or "peer on another channel", and the
     * host cannot tell them apart without the radio/peer channel pair. */
    uint8_t fail[10] = {};
    memcpy(fail, mac_addr, 6);
    fail[6] = (uint8_t)status;
    uint8_t primary = 0;
    wifi_second_chan_t second = WIFI_SECOND_CHAN_NONE;
    if (esp_wifi_get_channel(&primary, &second) != ESP_OK) {
        primary = 0;
    }
    fail[7] = primary;
    esp_now_peer_info_t peer = {};
    fail[8] = (esp_now_get_peer(mac_addr, &peer) == ESP_OK) ? peer.channel : 0;
    send_evt_to_host(ESPNOW_EVT_SEND_FAIL, fail, sizeof(fail));
}

static void espnow_recv_cb(const esp_now_recv_info_t *info, const uint8_t *data, int len)
{
    if (!info || !data || len <= 0 || (uint16_t)len > s_max_payload) {
        return;
    }

    const bool discover = s_discover_mode && xTaskGetTickCount() < s_discover_until;
    if (discover) {
        uint8_t ev[7];
        memcpy(ev, info->src_addr, 6);
        ev[6] = info->rx_ctrl ? (uint8_t)(int8_t)info->rx_ctrl->rssi : 0;
        send_evt_to_host(ESPNOW_EVT_DISCOVER, ev, sizeof(ev));
        return;
    }

    /* Link-quality telemetry, throttled: emit EVT_RSSI on a >=6 dB move or
     * every 64th frame. Costs one small event, gives the P4 live signal bars
     * and early warning before sends start failing. */
    if (info->rx_ctrl) {
        static int8_t s_last_rssi = 127;
        static uint8_t s_rssi_ctr;
        const int8_t rssi = (int8_t)info->rx_ctrl->rssi;
        const int delta = (int)rssi - (int)s_last_rssi;
        if (s_last_rssi == 127 || delta >= 6 || delta <= -6 || ++s_rssi_ctr >= 64) {
            s_last_rssi = rssi;
            s_rssi_ctr = 0;
            uint8_t ev[7];
            memcpy(ev, info->src_addr, 6);
            ev[6] = (uint8_t)rssi;
            send_evt_to_host(ESPNOW_EVT_RSSI, ev, sizeof(ev));
        }
    }

    uint16_t total = 6 + (uint16_t)len;
    uint8_t *buf = (uint8_t *)espnow_pool_alloc(1 + total);
    if (!buf) {
        return;
    }

    buf[0] = ESPNOW_EVT_RECV;
    memcpy(buf + 1, info->src_addr, 6);
    memcpy(buf + 7, data, (size_t)len);

    interface_buffer_handle_t buf_handle = {0};
    buf_handle.if_type = ESP_ESPNOW_IF;
    buf_handle.if_num = 0;
    buf_handle.payload = buf;
    buf_handle.payload_len = 1 + total;
    buf_handle.priv_buffer_handle = buf;
    buf_handle.free_buf_handle = espnow_pool_free;

    if (send_to_host_queue(&buf_handle, PRIO_Q_SERIAL) != 0) {
        espnow_pool_free(buf);
    }
}

static void cmd_init(const uint8_t *payload, uint16_t len)
{
    if (len >= 1 && payload && payload[0] >= 1 && payload[0] <= 13) {
        s_radio_ch = payload[0];
    }

    if (s_inited) {
        (void)espnow_lock_radio_channel(s_radio_ch);
        const uint8_t caps = ESPNOW_PROTO_CAP_SCAN;
        send_evt_to_host(ESPNOW_EVT_INIT_OK, &caps, 1);
        return;
    }

    esp_err_t err = esp_now_init();
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "esp_now_init: %s", esp_err_to_name(err));
        uint8_t e = (uint8_t)err;
        send_evt_to_host(ESPNOW_EVT_INIT_FAIL, &e, 1);
        return;
    }

    uint32_t ver = 0;
    s_max_payload = ESP_NOW_MAX_DATA_LEN;
    if (esp_now_get_version(&ver) == ESP_OK && ver >= 2) {
        s_max_payload = ESP_NOW_MAX_DATA_LEN_V2;
    }

    (void)esp_wifi_set_max_tx_power(ESPNOW_TX_POWER_QUARTER_DBM);

    esp_err_t reg_err = esp_now_register_send_cb(espnow_send_cb_v55);
    if (reg_err != ESP_OK) {
        ESP_LOGE(TAG, "register_send_cb: %s", esp_err_to_name(reg_err));
        esp_now_deinit();
        uint8_t e = (uint8_t)reg_err;
        send_evt_to_host(ESPNOW_EVT_INIT_FAIL, &e, 1);
        return;
    }
    reg_err = esp_now_register_recv_cb(espnow_recv_cb);
    if (reg_err != ESP_OK) {
        ESP_LOGE(TAG, "register_recv_cb: %s", esp_err_to_name(reg_err));
        esp_now_deinit();
        uint8_t e = (uint8_t)reg_err;
        send_evt_to_host(ESPNOW_EVT_INIT_FAIL, &e, 1);
        return;
    }
    (void)espnow_lock_radio_channel(s_radio_ch);
    s_inited = true;
    ESP_LOGI(TAG, "ESP-NOW ready ch%u max=%u rate_idx=%u tx=%d",
             (unsigned)s_radio_ch, (unsigned)s_max_payload, (unsigned)s_rate_idx,
             ESPNOW_TX_POWER_QUARTER_DBM);
    {
        const uint8_t caps = ESPNOW_PROTO_CAP_SCAN;
        send_evt_to_host(ESPNOW_EVT_INIT_OK, &caps, 1);
    }
}

static void cmd_deinit(void)
{
    if (s_inited) {
        esp_now_deinit();
        s_inited = false;
        ESP_LOGI(TAG, "ESP-NOW deinitialized");
    }
}

static void cmd_add_peer(const uint8_t *payload, uint16_t len)
{
    if (len < 8) {
        return;
    }

    uint8_t peer_ch = (payload[6] >= 1 && payload[6] <= 13) ? payload[6] : s_radio_ch;
    (void)espnow_lock_radio_channel(peer_ch);

    if (esp_now_is_peer_exist(payload)) {
        const bool want_encrypt = (len >= 8 && payload[7] != 0);
        esp_now_peer_info_t existing = {0};
        if (esp_now_get_peer(payload, &existing) == ESP_OK &&
            existing.channel == peer_ch && existing.encrypt == want_encrypt) {
            (void)espnow_apply_peer_rate(payload, s_rate_idx);
            send_evt_to_host(ESPNOW_EVT_PEER_OK, payload, 6);
            return;
        }
    }

    esp_now_peer_info_t peer = {0};
    memcpy(peer.peer_addr, payload, 6);
    peer.channel = peer_ch;
    peer.ifidx = WIFI_IF_STA;
    /* Encryption needs a real LMK: [mac:6][ch][encrypt][lmk:16 optional].
     * encrypt without an LMK was a latent bug (zero-key "encryption") —
     * refuse it honestly and add the peer in the clear instead. */
    if (payload[7] && len >= 24) {
        memcpy(peer.lmk, payload + 8, ESP_NOW_KEY_LEN);
        peer.encrypt = true;
    } else {
        if (payload[7]) {
            ESP_LOGW(TAG, "add_peer: encrypt requested without LMK — adding unencrypted");
        }
        peer.encrypt = false;
    }

    esp_now_del_peer(peer.peer_addr);

    esp_err_t err = esp_now_add_peer(&peer);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "add_peer: %s", esp_err_to_name(err));
        uint8_t fail[7];
        memcpy(fail, peer.peer_addr, 6);
        fail[6] = (uint8_t)err;
        send_evt_to_host(ESPNOW_EVT_PEER_FAIL, fail, sizeof(fail));
        return;
    }

    err = espnow_apply_peer_rate(peer.peer_addr, s_rate_idx);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "peer rate: %s", esp_err_to_name(err));
    }

    ESP_LOGI(TAG, "Peer added: %02X:%02X:%02X:%02X:%02X:%02X ch%d rate%u",
             peer.peer_addr[0], peer.peer_addr[1], peer.peer_addr[2],
             peer.peer_addr[3], peer.peer_addr[4], peer.peer_addr[5],
             peer.channel, (unsigned)s_rate_idx);
    send_evt_to_host(ESPNOW_EVT_PEER_OK, peer.peer_addr, 6);
}

static void cmd_del_peer(const uint8_t *payload, uint16_t len)
{
    if (len < 6) {
        return;
    }
    esp_now_del_peer(payload);
}

static void cmd_send(const uint8_t *payload, uint16_t len)
{
    if (len < 7) {
        return;
    }

    const uint8_t *mac = payload;
    const uint8_t *data = payload + 6;
    uint16_t data_len = len - 6;

    if (data_len > s_max_payload) {
        ESP_LOGW(TAG, "send: data too long (%u > %u)", data_len, (unsigned)s_max_payload);
        uint8_t fail[7];
        memcpy(fail, mac, 6);
        fail[6] = (uint8_t)ESP_ERR_INVALID_SIZE;
        send_evt_to_host(ESPNOW_EVT_SEND_FAIL, fail, sizeof(fail));
        return;
    }

    esp_err_t err = esp_now_send(mac, data, data_len);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "esp_now_send: %s", esp_err_to_name(err));
        uint8_t fail[7];
        memcpy(fail, mac, 6);
        fail[6] = (uint8_t)err;
        send_evt_to_host(ESPNOW_EVT_SEND_FAIL, fail, sizeof(fail));
    }
}

static void cmd_set_pmk(const uint8_t *payload, uint16_t len)
{
    if (len < 16) {
        return;
    }
    esp_now_set_pmk(payload);
    ESP_LOGI(TAG, "PMK set");
}

static void cmd_set_rate(const uint8_t *payload, uint16_t len)
{
    if (len < 7) {
        return;
    }
    const uint8_t *mac = payload;
    uint8_t idx = payload[6];
    wifi_phy_rate_t dummy;
    wifi_phy_mode_t dummy_mode;
    if (!espnow_rate_from_idx(idx, &dummy, &dummy_mode)) {
        ESP_LOGW(TAG, "set_rate: bad idx %u", (unsigned)idx);
        return;
    }
    s_rate_idx = idx;
    if (!esp_now_is_peer_exist(mac)) {
        ESP_LOGI(TAG, "set_rate idx=%u (peer not yet added)", (unsigned)idx);
        return;
    }
    esp_err_t err = espnow_apply_peer_rate(mac, idx);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "set_rate: %s", esp_err_to_name(err));
    } else {
        ESP_LOGI(TAG, "set_rate idx=%u ok", (unsigned)idx);
    }
}

static void cmd_scan_begin(const uint8_t *payload, uint16_t len)
{
    uint16_t ms = 3500;
    if (len >= 2 && payload) {
        ms = (uint16_t)payload[0] | ((uint16_t)payload[1] << 8);
        if (ms < 500) {
            ms = 500;
        }
        if (ms > 10000) {
            ms = 10000;
        }
    }
    s_discover_mode = true;
    s_discover_until = xTaskGetTickCount() + pdMS_TO_TICKS(ms);
    ESP_LOGI(TAG, "scan discover window %u ms", (unsigned)ms);
}

static void cmd_scan_end(void)
{
    s_discover_mode = false;
}

void espnow_process_host_cmd(const uint8_t *payload, uint16_t len)
{
    if (!payload || len < 1) {
        return;
    }

    uint8_t cmd = payload[0];
    const uint8_t *args = payload + 1;
    uint16_t args_len = len - 1;

    switch (cmd) {
    case ESPNOW_CMD_INIT:
        cmd_init(args, args_len);
        break;
    case ESPNOW_CMD_DEINIT:
        cmd_deinit();
        break;
    case ESPNOW_CMD_ADD_PEER:
        cmd_add_peer(args, args_len);
        break;
    case ESPNOW_CMD_DEL_PEER:
        cmd_del_peer(args, args_len);
        break;
    case ESPNOW_CMD_SEND:
        cmd_send(args, args_len);
        break;
    case ESPNOW_CMD_SET_PMK:
        cmd_set_pmk(args, args_len);
        break;
    case ESPNOW_CMD_LOCK_CHANNEL:
        if (args_len >= 1 && args && args[0] >= 1 && args[0] <= 13) {
            (void)espnow_lock_radio_channel(args[0]);
        } else {
            (void)espnow_lock_radio_channel(s_radio_ch);
        }
        break;
    case ESPNOW_CMD_SET_RATE:
        cmd_set_rate(args, args_len);
        break;
    case ESPNOW_CMD_SCAN_BEGIN:
        cmd_scan_begin(args, args_len);
        break;
    case ESPNOW_CMD_SCAN_END:
        cmd_scan_end();
        break;
    default:
        ESP_LOGW(TAG, "Unknown ESP-NOW cmd: 0x%02x", cmd);
        break;
    }
}
