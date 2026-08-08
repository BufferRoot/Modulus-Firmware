/*
 * Phase 10 — ESP-NOW on C6 alongside esp_hosted SDIO Wi-Fi + BLE HCI.
 * Wi-Fi starts via esp_hosted RPC when P4 host calls esp_wifi_init/start — not at C6 boot.
 * Poll modulus_c6_espnow_poll() until Wi-Fi up, then esp_now_init.
 * Channel: match esp_wifi_get_channel or default 1. Coex: CONFIG_ESP_COEX_SW_COEXIST_ENABLE.
 */
#include "modulus_c6_espnow.h"

#include "esp_log.h"
#include "esp_now.h"
#include "esp_wifi.h"
#include "sdkconfig.h"
#include <string.h>

static const char *TAG = "modulus_c6_espnow";

#if !CONFIG_MODULUS_C6_ESPNOW

/* ESP-NOW on C6 is owned by the host-driven SDIO command handler
 * (main/espnow_handler.c). esp_now permits only one recv/send callback
 * globally, so this autonomous path is compiled out to avoid stealing the
 * callbacks and double-initializing esp_now. */
void modulus_c6_espnow_init(void)
{
    ESP_LOGI(TAG, "ESP-NOW disabled (host-driven SDIO handler owns esp_now)");
}
void modulus_c6_espnow_poll(void) {}
bool modulus_c6_espnow_ready(void) { return false; }
uint8_t modulus_c6_espnow_status(void) { return 0; }
void modulus_c6_espnow_send_test(void) {}

#else

static const uint8_t s_broadcast_mac[ESP_NOW_ETH_ALEN] = {
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
};

static const uint8_t s_modulus_pmk[ESP_NOW_KEY_LEN] = {
    'M', 'O', 'D', 'U', 'L', 'U', 'S', '_', 'E', 'N', 'O', 'W', '_', 'P', 'M', 'K',
};

static bool s_init_done;
static bool s_test_sent;
static uint8_t s_status; /* 0 off/deferred, 1 ready, 2 error */
static uint8_t s_channel;

static void modulus_c6_espnow_recv_cb(const esp_now_recv_info_t *info, const uint8_t *data, int len)
{
    if (info == NULL || data == NULL || len <= 0) {
        return;
    }
    ESP_LOGI(TAG, "recv %d bytes on ch%u", len, s_channel);
}

static void modulus_c6_espnow_send_cb(const esp_now_send_info_t *tx_info, esp_now_send_status_t status)
{
    (void)tx_info;
    ESP_LOGI(TAG, "send %s", status == ESP_NOW_SEND_SUCCESS ? "ok" : "fail");
}

static bool modulus_c6_espnow_wifi_up(void)
{
    wifi_mode_t mode = WIFI_MODE_NULL;
    if (esp_wifi_get_mode(&mode) != ESP_OK) {
        return false;
    }
    return mode != WIFI_MODE_NULL;
}

static esp_err_t modulus_c6_espnow_align_channel(void)
{
    uint8_t primary = 0;
    wifi_second_chan_t second = WIFI_SECOND_CHAN_NONE;

    if (esp_wifi_get_channel(&primary, &second) == ESP_OK && primary != 0) {
        s_channel = primary;
        ESP_LOGI(TAG, "channel %u (Wi-Fi active)", (unsigned)s_channel);
        return ESP_OK;
    }

    s_channel = 1;
    esp_err_t err = esp_wifi_set_channel(s_channel, WIFI_SECOND_CHAN_NONE);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "set_channel(1) failed: %s — using reported channel", esp_err_to_name(err));
    } else {
        ESP_LOGI(TAG, "channel %u (default, Wi-Fi idle)", (unsigned)s_channel);
    }
    return ESP_OK;
}

static esp_err_t modulus_c6_espnow_add_broadcast_peer(void)
{
    esp_now_peer_info_t peer = {0};
    memcpy(peer.peer_addr, s_broadcast_mac, ESP_NOW_ETH_ALEN);
    peer.channel = s_channel;
    peer.ifidx = WIFI_IF_STA;
    peer.encrypt = false;

    esp_err_t err = esp_now_add_peer(&peer);
    if (err == ESP_ERR_ESPNOW_EXIST) {
        return ESP_OK;
    }
    return err;
}

static void modulus_c6_espnow_mark_error(const char *step, esp_err_t err)
{
    ESP_LOGE(TAG, "%s failed: %s", step, esp_err_to_name(err));
    s_status = 2;
    s_init_done = true;
}

static void modulus_c6_espnow_do_init(void)
{
#if !CONFIG_MODULUS_C6_ESPNOW
    return;
#else
    if (s_init_done) {
        return;
    }
    if (!modulus_c6_espnow_wifi_up()) {
        return;
    }

    esp_err_t err = esp_now_init();
    if (err != ESP_OK) {
        modulus_c6_espnow_mark_error("esp_now_init", err);
        return;
    }

    err = esp_now_set_pmk(s_modulus_pmk);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "esp_now_set_pmk failed: %s", esp_err_to_name(err));
    }

    err = esp_now_register_recv_cb(modulus_c6_espnow_recv_cb);
    if (err != ESP_OK) {
        modulus_c6_espnow_mark_error("register recv_cb", err);
        return;
    }

    err = esp_now_register_send_cb(modulus_c6_espnow_send_cb);
    if (err != ESP_OK) {
        modulus_c6_espnow_mark_error("register send_cb", err);
        return;
    }

    modulus_c6_espnow_align_channel();

    err = modulus_c6_espnow_add_broadcast_peer();
    if (err != ESP_OK) {
        modulus_c6_espnow_mark_error("add broadcast peer", err);
        return;
    }

    s_status = 1;
    s_init_done = true;
    ESP_LOGI(TAG, "ESP-NOW ready ch%u peer-ready (coex w/ Wi-Fi+BLE)", (unsigned)s_channel);

#if CONFIG_MODULUS_C6_ESPNOW_SEND_TEST
    modulus_c6_espnow_send_test();
#endif
#endif
}

void modulus_c6_espnow_init(void)
{
#if !CONFIG_MODULUS_C6_ESPNOW
    ESP_LOGI(TAG, "ESP-NOW disabled (CONFIG_MODULUS_C6_ESPNOW=n)");
    return;
#else
    modulus_c6_espnow_do_init();
#endif
}

void modulus_c6_espnow_poll(void)
{
#if CONFIG_MODULUS_C6_ESPNOW
    if (s_status != 1) {
        modulus_c6_espnow_do_init();
    }
#endif
}

bool modulus_c6_espnow_ready(void)
{
#if CONFIG_MODULUS_C6_ESPNOW
    return s_status == 1;
#else
    return false;
#endif
}

uint8_t modulus_c6_espnow_status(void)
{
    return s_status;
}

void modulus_c6_espnow_send_test(void)
{
#if CONFIG_MODULUS_C6_ESPNOW
    if (s_status != 1 || s_test_sent) {
        return;
    }
    static const uint8_t payload[] = "MODULUS";
    esp_err_t err = esp_now_send(s_broadcast_mac, payload, sizeof(payload) - 1);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "test broadcast failed: %s", esp_err_to_name(err));
    } else {
        s_test_sent = true;
        ESP_LOGI(TAG, "test broadcast sent (MODULUS)");
    }
#endif
}

#endif /* CONFIG_MODULUS_C6_ESPNOW */
