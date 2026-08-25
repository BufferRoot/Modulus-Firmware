/*
 * ESP32-S3 ESP-NOW <-> UART Bridge — ESP-NOW link
 *
 * Tab5 -> inbound queue -> worker -> uart_bridge_send -> grblHAL
 * grblHAL -> uart_rx_task -> outbound queue -> worker -> espnow_send_to_tab5
 */
#include "espnow_link.h"
#include "uart_bridge.h"
#include "halt_gpio.h"
#include "bridge_config.h"
#include "bridge_nvs.h"
#include "bridge_protocol.h"

#include <atomic>
#include <cstring>
#include <cstdio>

#include <esp_mac.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <esp_log.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/semphr.h>
#include <freertos/task.h>

static const char* TAG = "espnow";

/* 2.4 GHz channels 1-13 (Tab5 probe set); ch 14 is JP-only and unused here. */
static constexpr uint8_t kChannelMin = 1;
static constexpr uint8_t kChannelMax = 13;

typedef struct {
    uint16_t len;
    uint8_t  data[ESPNOW_MAX_PAYLOAD];
} inbound_pkt_t;

static uint8_t               s_channel = ESPNOW_DEFAULT_CHANNEL;
static uint8_t               s_tab5_mac[6] = {};
static bool                  s_tab5_known = false;
static char                  s_mac_str[18] = "not seen yet";
static bool                  s_espnow_ready = false;
static std::atomic<uint32_t> s_rx_count{0};
static std::atomic<uint32_t> s_tx_count{0};
static std::atomic<uint32_t> s_fail_count{0};
static std::atomic<uint32_t> s_inbound_drops{0};
static std::atomic<uint32_t> s_outbound_drops{0};
static SemaphoreHandle_t     s_tx_lock = nullptr; /* mutex: one in-flight send */
static SemaphoreHandle_t     s_tx_done = nullptr; /* binary: send-cb completion */
static SemaphoreHandle_t     s_peer_mu = nullptr; /* mutex: MAC / peer table */
static QueueHandle_t         s_inbound_q = nullptr;
static QueueHandle_t         s_outbound_q = nullptr;
static bool                  s_inbound_worker_started = false;
static bool                  s_outbound_worker_started = false;
/* MOD_ACK / peer learn must not block inside esp_now recv cb. */
static portMUX_TYPE          s_ack_spin = portMUX_INITIALIZER_UNLOCKED;
static bool                  s_ack_pending = false;
static uint8_t               s_ack_mac[6] = {};
static portMUX_TYPE          s_learn_spin = portMUX_INITIALIZER_UNLOCKED;
static bool                  s_learn_pending = false;
static uint8_t               s_learn_mac[6] = {};

static void mac_to_str(const uint8_t* mac, char* out)
{
    snprintf(out, 18, "%02X:%02X:%02X:%02X:%02X:%02X",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

static bool channel_ok(uint8_t ch)
{
    return ch >= kChannelMin && ch <= kChannelMax;
}

static void save_tab5_mac(void)
{
    bridge_nvs_t nvs = bridge_nvs_open(NVS_READWRITE);
    if (!nvs.ok) return;
    esp_err_t err = nvs_set_blob(nvs.h, NVS_KEY_TAB5_MAC, s_tab5_mac, 6);
    if (err == ESP_OK) err = nvs_commit(nvs.h);
    bridge_nvs_close(&nvs);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "save Tab5 MAC: %s", esp_err_to_name(err));
    }
}

static bool load_tab5_mac(void)
{
    bridge_nvs_t nvs = bridge_nvs_open(NVS_READONLY);
    if (!nvs.ok) return false;
    size_t sz = 6;
    esp_err_t err = nvs_get_blob(nvs.h, NVS_KEY_TAB5_MAC, s_tab5_mac, &sz);
    bridge_nvs_close(&nvs);
    return err == ESP_OK && sz == 6;
}

static bool save_channel_nvs(uint8_t ch)
{
    bridge_nvs_t nvs = bridge_nvs_open(NVS_READWRITE);
    if (!nvs.ok) return false;
    esp_err_t err = nvs_set_u8(nvs.h, NVS_KEY_CHANNEL, ch);
    if (err == ESP_OK) err = nvs_commit(nvs.h);
    bridge_nvs_close(&nvs);
    return err == ESP_OK;
}

static void apply_peer_rate_11m(const uint8_t* mac)
{
    esp_now_rate_config_t cfg = {};
    cfg.phymode = WIFI_PHY_MODE_11B;
    cfg.rate = WIFI_PHY_RATE_11M_L;
    cfg.ersu = false;
    cfg.dcm = false;
    const esp_err_t err = esp_now_set_peer_rate_config(mac, &cfg);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "peer rate 11M: %s", esp_err_to_name(err));
    }
}

/* Caller holds s_peer_mu. */
static void register_tab5_peer_locked(const uint8_t* mac)
{
    if (esp_now_is_peer_exist(mac)) {
        esp_now_del_peer(mac);
    }

    esp_now_peer_info_t pi = {};
    memcpy(pi.peer_addr, mac, 6);
    pi.channel = s_channel;
    pi.ifidx   = WIFI_IF_STA;
    pi.encrypt = false;

    esp_err_t err = esp_now_add_peer(&pi);
    if (err == ESP_OK) {
        apply_peer_rate_11m(mac);
        ESP_LOGI(TAG, "Tab5 peer registered: %s ch%d rate11M", s_mac_str, s_channel);
    } else {
        ESP_LOGW(TAG, "add_peer failed: %s", esp_err_to_name(err));
    }
}

static void learn_tab5_mac(const uint8_t* mac)
{
    if (!s_peer_mu) return;

    xSemaphoreTake(s_peer_mu, portMAX_DELAY);
    if (s_tab5_known && memcmp(s_tab5_mac, mac, 6) == 0) {
        xSemaphoreGive(s_peer_mu);
        return;
    }

    const bool first = !s_tab5_known;
    memcpy(s_tab5_mac, mac, 6);
    mac_to_str(s_tab5_mac, s_mac_str);
    s_tab5_known = true;
    register_tab5_peer_locked(s_tab5_mac);
    xSemaphoreGive(s_peer_mu);

    save_tab5_mac();
    ESP_LOGI(TAG, "%s Tab5 MAC: %s", first ? "Learned" : "Updated", s_mac_str);
}

/*
 * Serialize all esp_now_send calls (UART path + MOD_ACK).
 * Binary s_tx_done starts empty; on_sent Gives; we wait after send.
 * Drain stale Give so a prior timeout cannot complete this wait early.
 */
static bool espnow_send_chunk(const uint8_t* mac, const uint8_t* data, size_t len)
{
    if (!mac || !data || len == 0 || len > ESPNOW_MAX_PAYLOAD) {
        return false;
    }
    if (!s_espnow_ready || !s_tx_lock || !s_tx_done) {
        return false;
    }

    if (xSemaphoreTake(s_tx_lock, pdMS_TO_TICKS(ESPNOW_TX_LOCK_MS)) != pdTRUE) {
        s_fail_count.fetch_add(1, std::memory_order_relaxed);
        return false;
    }

    (void)xSemaphoreTake(s_tx_done, 0);

    const esp_err_t err = esp_now_send(mac, data, len);
    if (err != ESP_OK) {
        xSemaphoreGive(s_tx_lock);
        s_fail_count.fetch_add(1, std::memory_order_relaxed);
        ESP_LOGW(TAG, "esp_now_send: %s", esp_err_to_name(err));
        return false;
    }

    if (xSemaphoreTake(s_tx_done, pdMS_TO_TICKS(ESPNOW_TX_WAIT_MS)) != pdTRUE) {
        ESP_LOGW(TAG, "TX timeout — dropping chunk (%u bytes)", (unsigned)len);
        s_fail_count.fetch_add(1, std::memory_order_relaxed);
        xSemaphoreGive(s_tx_lock);
        return false;
    }

    xSemaphoreGive(s_tx_lock);
    return true;
}

static void defer_learn_mac(const uint8_t* mac)
{
    taskENTER_CRITICAL(&s_learn_spin);
    memcpy(s_learn_mac, mac, 6);
    s_learn_pending = true;
    taskEXIT_CRITICAL(&s_learn_spin);
}

static void apply_deferred_learn(void)
{
    uint8_t mac[6];
    bool do_it = false;
    taskENTER_CRITICAL(&s_learn_spin);
    if (s_learn_pending) {
        memcpy(mac, s_learn_mac, 6);
        s_learn_pending = false;
        do_it = true;
    }
    taskEXIT_CRITICAL(&s_learn_spin);
    if (do_it) learn_tab5_mac(mac);
}

static void request_mod_ack(const uint8_t* dest_mac)
{
    taskENTER_CRITICAL(&s_ack_spin);
    memcpy(s_ack_mac, dest_mac, 6);
    s_ack_pending = true;
    taskEXIT_CRITICAL(&s_ack_spin);
}

static void flush_pending_mod_ack(void)
{
    uint8_t mac[6];
    bool send = false;
    taskENTER_CRITICAL(&s_ack_spin);
    if (s_ack_pending) {
        memcpy(mac, s_ack_mac, 6);
        s_ack_pending = false;
        send = true;
    }
    taskEXIT_CRITICAL(&s_ack_spin);
    if (!send) return;

    static const uint8_t ack[] = BRIDGE_MOD_ACK;
    if (!espnow_send_chunk(mac, ack, BRIDGE_MOD_ACK_LEN)) {
        ESP_LOGW(TAG, "MOD_ACK send failed");
    }
}

static bool enqueue_inbound(const uint8_t* data, int len)
{
    if (!s_inbound_q || len <= 0 || len > ESPNOW_MAX_PAYLOAD) {
        return false;
    }

    inbound_pkt_t pkt = {};
    pkt.len = (uint16_t)len;
    memcpy(pkt.data, data, (size_t)len);

    if (xQueueSend(s_inbound_q, &pkt, 0) == pdTRUE) {
        return true;
    }

    s_inbound_drops.fetch_add(1, std::memory_order_relaxed);
    return false;
}

static void inbound_worker(void*)
{
    inbound_pkt_t pkt;
    for (;;) {
        apply_deferred_learn();
        flush_pending_mod_ack();
        if (xQueueReceive(s_inbound_q, &pkt, pdMS_TO_TICKS(20)) == pdTRUE) {
            uart_bridge_send(pkt.data, pkt.len);
        }
    }
}

static void outbound_worker(void*)
{
    inbound_pkt_t pkt;
    for (;;) {
        apply_deferred_learn();
        flush_pending_mod_ack();
        if (xQueueReceive(s_outbound_q, &pkt, pdMS_TO_TICKS(20)) == pdTRUE) {
            (void)espnow_send_to_tab5(pkt.data, pkt.len);
        }
    }
}

static void on_recv(const esp_now_recv_info_t* info,
                    const uint8_t* data, int len)
{
    if (!info || len <= 0 || !data) {
        return;
    }

    if (len == BRIDGE_MOD_PROBE_LEN &&
        memcmp(data, BRIDGE_MOD_PROBE, BRIDGE_MOD_PROBE_LEN) == 0) {
        defer_learn_mac(info->src_addr);
        request_mod_ack(info->src_addr);
        return;
    }

    if (len == BRIDGE_MOD_HALT_LEN &&
        memcmp(data, BRIDGE_MOD_HALT_ON, BRIDGE_MOD_HALT_LEN) == 0) {
        defer_learn_mac(info->src_addr);
        halt_gpio_set(true);
        return;
    }

    if (len == BRIDGE_MOD_HALT_LEN &&
        memcmp(data, BRIDGE_MOD_HALT_OFF, BRIDGE_MOD_HALT_LEN) == 0) {
        defer_learn_mac(info->src_addr);
        halt_gpio_set(false);
        return;
    }

    defer_learn_mac(info->src_addr);

    s_rx_count.fetch_add(1, std::memory_order_relaxed);
    ESP_LOGD(TAG, "RX %d bytes from Tab5 -> queue", len);

    if (!enqueue_inbound(data, len)) {
        ESP_LOGW(TAG, "inbound queue full — dropped %d bytes", len);
    }
}

static void on_sent(const esp_now_send_info_t* info, esp_now_send_status_t status)
{
    if (status == ESP_NOW_SEND_SUCCESS) {
        s_tx_count.fetch_add(1, std::memory_order_relaxed);
    } else {
        s_fail_count.fetch_add(1, std::memory_order_relaxed);
        if (info) {
            ESP_LOGD(TAG, "TX failed to %02X:%02X:%02X:%02X:%02X:%02X",
                     info->des_addr[0], info->des_addr[1], info->des_addr[2],
                     info->des_addr[3], info->des_addr[4], info->des_addr[5]);
        }
    }
    if (s_tx_done) {
        xSemaphoreGive(s_tx_done);
    }
}

bool espnow_send_to_tab5(const uint8_t* data, size_t len)
{
    if (!s_espnow_ready || !data || len == 0 || !s_peer_mu) {
        return false;
    }

    uint8_t mac[6];
    xSemaphoreTake(s_peer_mu, portMAX_DELAY);
    if (!s_tab5_known) {
        xSemaphoreGive(s_peer_mu);
        return false;
    }
    memcpy(mac, s_tab5_mac, 6);
    xSemaphoreGive(s_peer_mu);

    size_t offset = 0;
    while (offset < len) {
        const size_t chunk = (len - offset > ESPNOW_MAX_PAYLOAD)
                                 ? ESPNOW_MAX_PAYLOAD
                                 : (len - offset);
        if (!espnow_send_chunk(mac, data + offset, chunk)) {
            return false;
        }
        offset += chunk;
    }
    return true;
}

bool espnow_queue_to_tab5(const uint8_t* data, size_t len)
{
    if (!s_outbound_q || !data || len == 0 || len > ESPNOW_MAX_PAYLOAD) {
        return false;
    }

    inbound_pkt_t pkt = {};
    pkt.len = (uint16_t)len;
    memcpy(pkt.data, data, len);

    if (xQueueSend(s_outbound_q, &pkt, 0) == pdTRUE) {
        return true;
    }

    inbound_pkt_t junk;
    (void)xQueueReceive(s_outbound_q, &junk, 0);
    s_outbound_drops.fetch_add(1, std::memory_order_relaxed);
    return xQueueSend(s_outbound_q, &pkt, 0) == pdTRUE;
}

void espnow_init()
{
    bridge_nvs_t nvs = bridge_nvs_open(NVS_READONLY);
    if (nvs.ok) {
        uint8_t ch = 0;
        if (nvs_get_u8(nvs.h, NVS_KEY_CHANNEL, &ch) == ESP_OK && channel_ok(ch)) {
            s_channel = ch;
        }
        bridge_nvs_close(&nvs);
    }

    if (load_tab5_mac()) {
        mac_to_str(s_tab5_mac, s_mac_str);
        s_tab5_known = true;
        ESP_LOGI(TAG, "Tab5 MAC restored from NVS: %s ch%d", s_mac_str, s_channel);
    }

    wifi_init_config_t wcfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&wcfg));
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_start());
    ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE));
    ESP_ERROR_CHECK(esp_wifi_set_max_tx_power(78));
    ESP_ERROR_CHECK(esp_wifi_set_channel(s_channel, WIFI_SECOND_CHAN_NONE));

    uint8_t my_mac[6];
    esp_read_mac(my_mac, ESP_MAC_WIFI_STA);
    printf("\r\n=====================================================\r\n");
    printf("  S3 UART Bridge MAC: %02X:%02X:%02X:%02X:%02X:%02X\r\n",
           my_mac[0], my_mac[1], my_mac[2], my_mac[3], my_mac[4], my_mac[5]);
    printf("  -> Tab5 Settings > Wireless > ESP-NOW peer\r\n");
    printf("  ESP-NOW channel : %d (must match Tab5)\r\n", s_channel);
    printf("=====================================================\r\n\r\n");

    s_tx_lock = xSemaphoreCreateMutex();
    s_tx_done = xSemaphoreCreateBinary();
    s_peer_mu = xSemaphoreCreateMutex();
    ESP_ERROR_CHECK((s_tx_lock && s_tx_done && s_peer_mu) ? ESP_OK : ESP_ERR_NO_MEM);

    s_inbound_q = xQueueCreate(ESPNOW_QUEUE_DEPTH, sizeof(inbound_pkt_t));
    ESP_ERROR_CHECK(s_inbound_q ? ESP_OK : ESP_ERR_NO_MEM);
    s_outbound_q = xQueueCreate(ESPNOW_OUTBOUND_DEPTH, sizeof(inbound_pkt_t));
    ESP_ERROR_CHECK(s_outbound_q ? ESP_OK : ESP_ERR_NO_MEM);

    ESP_ERROR_CHECK(esp_now_init());
    ESP_ERROR_CHECK(esp_now_register_recv_cb(on_recv));
    ESP_ERROR_CHECK(esp_now_register_send_cb(on_sent));

    if (s_tab5_known) {
        xSemaphoreTake(s_peer_mu, portMAX_DELAY);
        register_tab5_peer_locked(s_tab5_mac);
        xSemaphoreGive(s_peer_mu);
    }

    s_espnow_ready = true;
    ESP_LOGI(TAG, "ESP-NOW initialised (channel %d)", s_channel);
}

void espnow_flush_pending_ack()
{
    apply_deferred_learn();
    flush_pending_mod_ack();
}

void espnow_start_inbound_worker()
{
    if (s_inbound_q && !s_inbound_worker_started) {
        xTaskCreatePinnedToCore(inbound_worker, "espnow_in",
                                4096, nullptr, 6, nullptr, 1);
        s_inbound_worker_started = true;
    }
    if (s_outbound_q && !s_outbound_worker_started) {
        xTaskCreatePinnedToCore(outbound_worker, "espnow_out",
                                4096, nullptr, 6, nullptr, 1);
        s_outbound_worker_started = true;
    }
}

bool espnow_set_channel(uint8_t ch)
{
    if (!channel_ok(ch) || !s_espnow_ready || !s_peer_mu) {
        return false;
    }
    if (esp_wifi_set_channel(ch, WIFI_SECOND_CHAN_NONE) != ESP_OK) {
        return false;
    }

    s_channel = ch;
    if (!save_channel_nvs(ch)) {
        ESP_LOGW(TAG, "channel NVS save failed (live ch=%d)", ch);
    }

    xSemaphoreTake(s_peer_mu, portMAX_DELAY);
    if (s_tab5_known) {
        register_tab5_peer_locked(s_tab5_mac);
    }
    xSemaphoreGive(s_peer_mu);
    return true;
}

bool espnow_self_check()
{
    if (!s_espnow_ready || !s_inbound_q || !s_outbound_q || !s_tx_lock ||
        !s_tx_done || !s_peer_mu || !s_inbound_worker_started ||
        !s_outbound_worker_started) {
        return false;
    }

    uint8_t primary = 0;
    wifi_second_chan_t second = WIFI_SECOND_CHAN_NONE;
    if (esp_wifi_get_channel(&primary, &second) != ESP_OK) {
        return false;
    }
    return primary == s_channel;
}

void espnow_reset_stats()
{
    s_rx_count.store(0, std::memory_order_relaxed);
    s_tx_count.store(0, std::memory_order_relaxed);
    s_fail_count.store(0, std::memory_order_relaxed);
    s_inbound_drops.store(0, std::memory_order_relaxed);
    s_outbound_drops.store(0, std::memory_order_relaxed);
}

uint8_t espnow_get_channel()
{
    return s_channel;
}

const char* espnow_tab5_mac_str()
{
    return s_mac_str;
}

uint32_t espnow_rx_count()
{
    return s_rx_count.load(std::memory_order_relaxed);
}

uint32_t espnow_tx_count()
{
    return s_tx_count.load(std::memory_order_relaxed);
}

uint32_t espnow_fail_count()
{
    return s_fail_count.load(std::memory_order_relaxed);
}

uint32_t espnow_inbound_drops()
{
    return s_inbound_drops.load(std::memory_order_relaxed);
}

uint32_t espnow_inbound_pending()
{
    return s_inbound_q ? uxQueueMessagesWaiting(s_inbound_q) : 0;
}

uint32_t espnow_outbound_drops()
{
    return s_outbound_drops.load(std::memory_order_relaxed);
}

uint32_t espnow_outbound_pending()
{
    return s_outbound_q ? uxQueueMessagesWaiting(s_outbound_q) : 0;
}
