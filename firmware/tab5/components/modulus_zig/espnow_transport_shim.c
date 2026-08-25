/*
 * ESP-NOW CNC transport + C6 SDIO stack (esp_hosted ESP_ESPNOW_IF ch8).
 */
#include "c6_espnow_proto.h"
#include "c6_sdio_host.h"
#include "cnc_cmd_exports.h"
#include "espnow_debug.h"
#include "espnow_stack.h"
#include "tab5_pi4ioe.h"
#include "transport_shim.h"
#include "wireless_shim.h"

#include "esp_hosted_interface.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "nvs_shim.h"

#include <stdio.h>
#include <string.h>

static const char *TAG = "espnow_tx";

static bool s_open;
static bool s_inited;
static uint8_t s_peer[6];
static int8_t s_bridge_rssi;
static bool s_bridge_rssi_valid;
static uint8_t s_channel = 1;
static bool s_encrypt;
static modulus_espnow_stack_evt_fn s_evt_hook;
static void *s_evt_ctx;
static SemaphoreHandle_t s_send_sem;
static SemaphoreHandle_t s_send_lock; /* serializes senders (Core 1 CNC vs Core 0 HALT/probe) */
static bool s_send_ok;
static uint8_t s_last_send_reason; /* 0x01 = transient ACK miss; other = stale peer/fatal */

/* Adaptive PHY rate: prefer NVS en_rate (default 24M OFDM); drop one tier after
 * 3 consecutive send fails at OFDM/MCS; climb back after N clean sends. */
#define RATE_FAIL_DROP   3
#define RATE_OK_CLIMB    32
#define RATE_FLOOR       ESPNOW_RATE_11M /* never fall below 11b max-compat */
static uint8_t s_rate_pref = ESPNOW_RATE_24M;
static uint8_t s_rate_cur = ESPNOW_RATE_24M;
static uint8_t s_rate_fail_streak;
static uint8_t s_rate_ok_streak;

static uint8_t rate_tier_down(uint8_t r)
{
    /* Speed order: MCS3 > MCS0 > 24M > 12M > 6M > 11M. */
    if (r >= ESPNOW_RATE_MCS3) {
        return ESPNOW_RATE_MCS0;
    }
    if (r == ESPNOW_RATE_MCS0) {
        return ESPNOW_RATE_24M;
    }
    if (r > RATE_FLOOR) {
        return (uint8_t)(r - 1);
    }
    return RATE_FLOOR;
}

static uint8_t rate_tier_up(uint8_t r, uint8_t pref)
{
    if (r >= pref) {
        return pref;
    }
    if (r == ESPNOW_RATE_MCS0) {
        return (pref >= ESPNOW_RATE_MCS3) ? ESPNOW_RATE_MCS3 : pref;
    }
    if (r >= ESPNOW_RATE_6M && r < ESPNOW_RATE_MCS0) {
        return (uint8_t)(r + 1);
    }
    if (r < ESPNOW_RATE_6M) {
        return ESPNOW_RATE_6M;
    }
    return pref;
}

static void rate_apply(const uint8_t mac[6], uint8_t rate)
{
    if (!mac || rate == s_rate_cur) {
        return;
    }
    if (modulus_espnow_stack_set_rate(mac, rate)) {
        ESP_LOGI(TAG, "ESP-NOW rate %u -> %u", (unsigned)s_rate_cur, (unsigned)rate);
        s_rate_cur = rate;
    }
}

static void rate_on_send_result(const uint8_t mac[6], bool ok)
{
    /* Only adapt against the configured CNC bridge peer — probe/bcast ignores. */
    if (!mac || memcmp(mac, s_peer, 6) != 0) {
        return;
    }
    if (ok) {
        s_rate_fail_streak = 0;
        if (s_rate_cur >= s_rate_pref) {
            s_rate_ok_streak = 0;
            return;
        }
        if (++s_rate_ok_streak >= RATE_OK_CLIMB) {
            s_rate_ok_streak = 0;
            rate_apply(mac, rate_tier_up(s_rate_cur, s_rate_pref));
        }
        return;
    }
    s_rate_ok_streak = 0;
    /* Only fall back when flying OFDM/MCS — 11b already is the floor. */
    if (s_rate_cur < ESPNOW_RATE_6M) {
        return;
    }
    if (++s_rate_fail_streak < RATE_FAIL_DROP) {
        return;
    }
    s_rate_fail_streak = 0;
    rate_apply(mac, rate_tier_down(s_rate_cur));
}

static void espnow_send_sem_init(void)
{
    if (!s_send_sem) {
        s_send_sem = xSemaphoreCreateBinary();
    }
    if (!s_send_lock) {
        s_send_lock = xSemaphoreCreateMutex();
    }
}

static bool espnow_send_and_wait(const uint8_t *mac, const uint8_t *data, size_t len)
{
    if (!mac || !data || len == 0 || len > ESPNOW_MAX_PAYLOAD || !modulus_c6_sdio_ready()) {
        return false;
    }
    espnow_send_sem_init();
    if (!s_send_sem || !s_send_lock) {
        return false;
    }
    /* Without this mutex, a Core 0 HALT/probe send racing a Core 1 CNC send
     * shares one binary semaphore and s_send_ok/s_last_send_reason — results
     * get cross-attributed and both retry loops corrupt. */
    if (xSemaphoreTake(s_send_lock, pdMS_TO_TICKS(2000)) != pdTRUE) {
        return false;
    }
    /* Drain a stale give: a SEND_OK/FAIL callback that arrived after a prior
     * timeout would otherwise release *this* wait with the old result. */
    (void)xSemaphoreTake(s_send_sem, 0);

    bool result = false;
    /* Serialized by s_send_lock — one static TX frame. */
    static uint8_t frame[1 + 6 + ESPNOW_MAX_PAYLOAD];
    frame[0] = ESPNOW_CMD_SEND;
    memcpy(frame + 1, mac, 6);
    memcpy(frame + 7, data, len);

    /* Retry up to 3× on reason=0x01 (transient MAC-layer ACK miss). Hardware
     * already retried ~7×; brief pause covers peer radio momentarily busy. */
    for (int attempt = 0; attempt < 3; attempt++) {
        s_send_ok = false;
        s_last_send_reason = 0xff;
        if (!modulus_c6_sdio_send(ESP_ESPNOW_IF, frame, (uint16_t)(1 + 6 + len))) {
            break;
        }
        if (xSemaphoreTake(s_send_sem, pdMS_TO_TICKS(1000)) != pdTRUE) {
            break; /* timeout waiting for send callback */
        }
        if (s_send_ok) {
            result = true;
            break;
        }
        /* Only retry for reason=0x01 (ACK miss); any other reason means wrong
         * peer/channel/state — retrying won't help. */
        if (s_last_send_reason != 0x01 || attempt == 2) {
            break;
        }
        vTaskDelay(pdMS_TO_TICKS(20));
    }
    rate_on_send_result(mac, result);
    xSemaphoreGive(s_send_lock);
    return result;
}

static bool mac_is_broadcast(const uint8_t mac[6])
{
    for (int i = 0; i < 6; i++) {
        if (mac[i] != 0xFF) {
            return false;
        }
    }
    return true;
}

static bool parse_mac(const char *mac_str, uint8_t out[6])
{
    if (!mac_str) {
        return false;
    }
    unsigned a[6];
    if (sscanf(mac_str, "%02x:%02x:%02x:%02x:%02x:%02x",
               &a[0], &a[1], &a[2], &a[3], &a[4], &a[5]) != 6) {
        return false;
    }
    for (int i = 0; i < 6; i++) {
        out[i] = (uint8_t)a[i];
    }
    return !mac_is_broadcast(out);
}

static bool espnow_send_cmd(uint8_t cmd, const uint8_t *args, uint16_t args_len)
{
    uint8_t buf[260];
    if (args_len + 1 > sizeof(buf)) {
        return false;
    }
    buf[0] = cmd;
    if (args && args_len) {
        memcpy(buf + 1, args, args_len);
    }
    return modulus_c6_sdio_send(ESP_ESPNOW_IF, buf, (uint16_t)(1 + args_len));
}

static void espnow_rx(const uint8_t *payload, uint16_t len, void *ctx)
{
    (void)ctx;
    if (!payload || len < 1) {
        return;
    }
    const uint8_t evt = payload[0];
    const uint8_t *body = payload + 1;
    const uint16_t body_len = (uint16_t)(len - 1);

    if (s_evt_hook) {
        s_evt_hook(evt, body, body_len, s_evt_ctx);
    }

    if (modulus_espnow_log_level() >= MODULUS_ESPNOW_LOG_VERBOSE) {
        ESP_LOGD(TAG, "rx evt 0x%02x body=%u", (unsigned)evt, (unsigned)body_len);
    }

    switch (evt) {
    case ESPNOW_EVT_INIT_OK:
        s_inited = true;
        modulus_espnow_debug_event("c6", "ESP-NOW init OK");
        ESP_LOGI(TAG, "C6 ESP-NOW init OK");
        break;
    case ESPNOW_EVT_INIT_FAIL:
        s_inited = false;
        modulus_espnow_debug_event("c6", "ESP-NOW init fail");
        ESP_LOGW(TAG, "C6 ESP-NOW init fail");
        break;
    case ESPNOW_EVT_SEND_OK:
        s_send_ok = true;
        if (s_send_sem) {
            xSemaphoreGive(s_send_sem);
        }
        break;
    case ESPNOW_EVT_SEND_FAIL:
        s_send_ok = false;
        s_last_send_reason = (body_len >= 7) ? body[6] : 0xff;
        if (s_send_sem) {
            xSemaphoreGive(s_send_sem);
        }
        if (body_len >= 10) {
            ESP_LOGW(TAG, "C6 ESP-NOW send fail dst=%02X:%02X:%02X:%02X:%02X:%02X "
                     "reason=0x%02x radioch=%u peerch=%u",
                     body[0], body[1], body[2], body[3], body[4], body[5],
                     (unsigned)body[6], (unsigned)body[7], (unsigned)body[8]);
        } else if (body_len >= 7) {
            ESP_LOGW(TAG, "C6 ESP-NOW send fail dst=%02X:%02X:%02X:%02X:%02X:%02X reason=0x%02x",
                     body[0], body[1], body[2], body[3], body[4], body[5],
                     (unsigned)body[6]);
        } else {
            ESP_LOGW(TAG, "C6 ESP-NOW send fail");
        }
        break;
    case ESPNOW_EVT_PROBE_FAIL:
        if (body_len >= 1) {
            ESP_LOGW(TAG, "C6 ESP-NOW probe fail err=%u", (unsigned)body[0]);
        } else {
            ESP_LOGW(TAG, "C6 ESP-NOW probe fail");
        }
        break;
    case ESPNOW_EVT_RSSI:
        /* Throttled link quality from the C6 ([mac:6][rssi:s8]). Cache for
         * the settings UI; only track the configured bridge peer. */
        if (body_len >= 7 && memcmp(body, s_peer, 6) == 0) {
            s_bridge_rssi = (int8_t)body[6];
            s_bridge_rssi_valid = true;
        }
        break;
    case ESPNOW_EVT_RECV:
        if (len > 7 && s_open && body_len >= 6 &&
            memcmp(body, s_peer, 6) == 0) {
            modulus_wireless_espnow_rx_inc();
            if (modulus_espnow_log_level() >= MODULUS_ESPNOW_LOG_VERBOSE) {
                modulus_espnow_debug_event("rx", "CNC %u bytes", (unsigned)(len - 7));
            }
            modulus_zig_serial_rx(payload + 7, len - 7);
        }
        break;
    default:
        break;
    }
}

void modulus_espnow_stack_register(void)
{
    static bool registered;
    if (registered) {
        return;
    }
    registered = true;
    modulus_c6_sdio_register_rx(ESP_ESPNOW_IF, espnow_rx, NULL);
}

void modulus_espnow_stack_set_evt_hook(modulus_espnow_stack_evt_fn fn, void *ctx)
{
    s_evt_hook = fn;
    s_evt_ctx = ctx;
}

bool modulus_espnow_stack_init(void)
{
    modulus_espnow_stack_register();
    if (!modulus_c6_sdio_ready()) {
        return false;
    }
    /* Force wait for a fresh INIT_OK — stale true after C6 reset caused probe races. */
    s_inited = false;
    return espnow_send_cmd(ESPNOW_CMD_INIT, NULL, 0);
}

bool modulus_espnow_stack_ensure_inited(uint32_t timeout_ms)
{
    modulus_espnow_stack_register();
    tab5_pi4ioe_wait_c6_sdio_ready();

    if (modulus_espnow_stack_inited()) {
        return true;
    }

    for (int attempt = 0; attempt < 2; attempt++) {
        if (!modulus_c6_sdio_ready()) {
            ESP_LOGW(TAG, "C6 SDIO TX not ready (init attempt %d)", attempt + 1);
            vTaskDelay(pdMS_TO_TICKS(250));
            continue;
        }
        if (!modulus_espnow_stack_init()) {
            vTaskDelay(pdMS_TO_TICKS(250));
            continue;
        }
        if (modulus_espnow_stack_wait_inited(timeout_ms)) {
            return true;
        }
        ESP_LOGW(TAG, "C6 ESP-NOW init timeout (attempt %d/%d)", attempt + 1, 2);
    }
    return false;
}

void modulus_espnow_stack_deinit(void)
{
    espnow_send_cmd(ESPNOW_CMD_DEINIT, NULL, 0);
    s_inited = false;
}

bool modulus_espnow_stack_inited(void)
{
    return s_inited;
}

bool modulus_espnow_stack_wait_inited(uint32_t timeout_ms)
{
    const TickType_t deadline = xTaskGetTickCount() + pdMS_TO_TICKS(timeout_ms);
    while (xTaskGetTickCount() < deadline) {
        if (s_inited) {
            return true;
        }
        vTaskDelay(pdMS_TO_TICKS(25));
    }
    return s_inited;
}

void modulus_espnow_stack_set_pmk(const uint8_t pmk[16])
{
    if (!pmk) {
        return;
    }
    espnow_send_cmd(ESPNOW_CMD_SET_PMK, pmk, 16);
}

bool modulus_espnow_stack_set_rate(const uint8_t mac[6], uint8_t rate_idx)
{
    if (!mac || !modulus_c6_sdio_ready()) {
        return false;
    }
    uint8_t args[7];
    memcpy(args, mac, 6);
    args[6] = rate_idx;
    return espnow_send_cmd(ESPNOW_CMD_SET_RATE, args, sizeof(args));
}

bool modulus_espnow_stack_add_peer(const uint8_t mac[6], uint8_t channel, bool encrypt)
{
    if (!mac || !modulus_c6_sdio_ready()) {
        return false;
    }
    /* [mac:6][ch][encrypt][lmk:16 optional] — the C6 refuses encrypt without
     * an LMK, so only claim encryption when NVS en_lmk (32 hex chars) parses. */
    uint8_t peer_args[24];
    uint16_t args_len = 8;
    memcpy(peer_args, mac, 6);
    peer_args[6] = channel;
    peer_args[7] = 0;
    if (encrypt) {
        char hex[33];
        if (modulus_nvs_get_str("en_lmk", hex, sizeof(hex)) && strlen(hex) == 32) {
            bool ok = true;
            for (int i = 0; i < 16 && ok; i++) {
                unsigned v;
                ok = sscanf(&hex[i * 2], "%2x", &v) == 1;
                peer_args[8 + i] = (uint8_t)v;
            }
            if (ok) {
                peer_args[7] = 1;
                args_len = 24;
            } else {
                ESP_LOGW(TAG, "en_lmk not valid hex — peer added unencrypted");
            }
        } else {
            ESP_LOGW(TAG, "encrypt requested but en_lmk unset — peer added unencrypted");
        }
    }
    if (!espnow_send_cmd(ESPNOW_CMD_ADD_PEER, peer_args, args_len)) {
        return false;
    }
    /* NVS en_rate: 0-3 = 11b (1/2/5.5/11M), 4-6 = OFDM (6/12/24M),
     * 7-8 = HT20 MCS0/MCS3. Default 24M OFDM; adaptive fallback drops tiers. */
    uint8_t rate = modulus_nvs_get_u8("en_rate", ESPNOW_RATE_24M);
    if (rate > ESPNOW_RATE_MCS3) {
        rate = ESPNOW_RATE_24M;
    }
    s_rate_pref = rate;
    s_rate_cur = rate;
    s_rate_fail_streak = 0;
    s_rate_ok_streak = 0;
    (void)modulus_espnow_stack_set_rate(mac, rate);
    return true;
}

bool modulus_espnow_stack_del_peer(const uint8_t mac[6])
{
    if (!mac || !modulus_c6_sdio_ready()) {
        return false;
    }
    espnow_send_cmd(ESPNOW_CMD_DEL_PEER, mac, 6);
    return true;
}

bool modulus_espnow_stack_lock_channel(void)
{
    if (!modulus_c6_sdio_ready()) {
        return false;
    }
    return espnow_send_cmd(ESPNOW_CMD_LOCK_CHANNEL, NULL, 0);
}

bool modulus_espnow_stack_send(const uint8_t mac[6], const uint8_t *data, size_t len)
{
    if (!mac || !data || len == 0 || len > ESPNOW_MAX_PAYLOAD || !s_inited) {
        return false;
    }
    return espnow_send_and_wait(mac, data, len);
}

bool modulus_espnow_stack_probe(uint8_t channel)
{
    static const uint8_t k_bcast[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    static const uint8_t k_probe[] = "MOD_PROBE";

    if (!modulus_c6_sdio_ready() || !s_inited) {
        return false;
    }
    if (channel < 1 || channel > 13) {
        channel = 1;
    }

    (void)modulus_espnow_stack_del_peer(k_bcast);
    if (!modulus_espnow_stack_add_peer(k_bcast, channel, false)) {
        return false;
    }
    return modulus_espnow_stack_send(k_bcast, k_probe, sizeof(k_probe) - 1);
}

static bool espnow_setup_bridge_peer(void)
{
    char mac_str[20];
    modulus_wireless_espnow_peer_mac_str(mac_str, sizeof(mac_str));
    if (!parse_mac(mac_str, s_peer)) {
        ESP_LOGW(TAG, "invalid bridge MAC '%s'", mac_str);
        return false;
    }
    s_bridge_rssi_valid = false; /* new peer/link — drop stale RSSI */

    s_channel = modulus_wireless_espnow_channel();
    /* S3 UART bridge uses plain ESP-NOW — PMK encryption breaks CNC transport. */
    s_encrypt = false;

    modulus_espnow_stack_register();
    if (!modulus_espnow_stack_inited()) {
        if (!modulus_espnow_stack_ensure_inited(MODULUS_ESPNOW_INIT_WAIT_MS)) {
            ESP_LOGW(TAG, "C6 ESP-NOW init timeout");
            return false;
        }
    }
    if (!modulus_espnow_stack_add_peer(s_peer, s_channel, s_encrypt)) {
        return false;
    }
    return true;
}

bool modulus_espnow_transport_start(const char *mac_str, uint8_t channel, bool encrypt)
{
    (void)encrypt;
    modulus_espnow_debug_event("txport", "start mac=%s ch=%u",
                               mac_str ? mac_str : "(nvs)", (unsigned)channel);
    modulus_espnow_stack_register();

    if (!modulus_wireless_espnow_is_enabled()) {
        if (!modulus_wireless_espnow_enable()) {
            modulus_espnow_debug_event("txport", "start fail: radio enable");
            return false;
        }
    }
    if (mac_str && mac_str[0]) {
        if (!modulus_wireless_espnow_commit_peer_mac(mac_str, false)) {
            modulus_espnow_debug_event("txport", "start fail: peer MAC");
            return false;
        }
    }
    modulus_wireless_espnow_apply_bridge_peer();
    if (channel > 0) {
        modulus_nvs_set_u8("en_chan", (uint8_t)(channel - 1));
    }
    /* S3 UART bridge uses plain ESP-NOW — PMK encryption breaks CNC transport. */
    modulus_nvs_set_u8("en_enc", 0);

    /* Always resolve the destination MAC into s_peer before opening. When the
     * bridge peer was already added via the wireless-settings path,
     * espnow_setup_bridge_peer() (the only other writer of s_peer) is gated
     * out below, which left s_peer = 00:00:00:00:00:00 and made every CNC
     * frame fail on the C6 with ESP_ERR_ESPNOW_NOT_FOUND (reason=0x69). */
    {
        char peer_mac[20];
        modulus_wireless_espnow_peer_mac_str(peer_mac, sizeof(peer_mac));
        if (!parse_mac(peer_mac, s_peer)) {
            modulus_espnow_debug_event("txport", "start fail: peer MAC unset");
            return false;
        }
        s_channel = modulus_wireless_espnow_channel();
    }

    if (!espnow_setup_bridge_peer()) {
        modulus_espnow_debug_event("txport", "start fail: bridge peer");
        return false;
    }

    /* Wake S3 bridge: MOD_PROBE → MOD_ACK updates Tab5 MAC in bridge NVS. */
    if (modulus_espnow_stack_probe(s_channel)) {
        vTaskDelay(pdMS_TO_TICKS(150));
    }

    /* Free BLE HCI coex airtime while ESP-NOW is the CNC link. */
    modulus_ble_suspend_for_espnow();

    s_open = true;
    modulus_espnow_debug_event("txport", "open -> on_connect");
    modulus_zig_transport_on_connect();
    modulus_zig_transport_espnow_attach();
    ESP_LOGI(TAG, "ESP-NOW transport open (C6 ch%u)", (unsigned)s_channel);
    return true;
}

void modulus_espnow_transport_stop(void)
{
    if (!s_open) {
        return;
    }
    /* Match C++ hal_espnow::deinit — session down only; keep C6 esp_now up for radio. */
    modulus_espnow_debug_event("txport", "stop -> on_disconnect");
    s_open = false;
    modulus_zig_transport_on_disconnect();
    modulus_ble_resume_after_espnow();
}

bool modulus_espnow_transport_send(const uint8_t *data, size_t len)
{
    if (!s_open || !data || len == 0) {
        return false;
    }

    size_t offset = 0;
    while (offset < len) {
        const size_t chunk = (len - offset > ESPNOW_MAX_PAYLOAD) ? ESPNOW_MAX_PAYLOAD
                                                                  : (len - offset);
        if (!espnow_send_and_wait(s_peer, data + offset, chunk)) {
            return false;
        }
        offset += chunk;
    }
    if (modulus_espnow_log_level() >= MODULUS_ESPNOW_LOG_VERBOSE) {
        modulus_espnow_debug_event("tx", "send %u bytes", (unsigned)len);
    }
    modulus_wireless_espnow_tx_inc();
    return true;
}

void modulus_espnow_transport_reapply_peer(void)
{
    if (!s_open) {
        return;
    }
    (void)espnow_setup_bridge_peer();
}

bool modulus_espnow_transport_is_open(void)
{
    return s_open;
}

bool modulus_espnow_bridge_halt(bool assert)
{
    /* Must match firmware/s3-bridge/main/bridge_protocol.h */
    static const uint8_t k_halt_on[]  = "MOD_HALT1";
    static const uint8_t k_halt_off[] = "MOD_HALT0";

    if (!modulus_c6_sdio_ready() || !modulus_wireless_ready()) {
        ESP_LOGW(TAG, "bridge HALT skipped: wireless not ready");
        return false;
    }

    char mac_str[20];
    uint8_t peer[6];
    modulus_wireless_espnow_peer_mac_str(mac_str, sizeof(mac_str));
    if (!parse_mac(mac_str, peer)) {
        ESP_LOGW(TAG, "bridge HALT skipped: peer MAC unset");
        return false;
    }

    modulus_espnow_stack_register();
    /* E-stop / Core-1 path calls this — never block waiting for ESP-NOW init
     * (ensure_inited can sleep up to MODULUS_ESPNOW_INIT_WAIT_MS). Soft reset
     * still runs from estop_gpio; HALT is best-effort if radio already up. */
    if (!modulus_espnow_stack_inited()) {
        ESP_LOGW(TAG, "bridge HALT skipped: ESP-NOW not inited (non-blocking)");
        return false;
    }

    const uint8_t ch = modulus_wireless_espnow_channel();
    if (!modulus_espnow_stack_add_peer(peer, ch, false)) {
        ESP_LOGW(TAG, "bridge HALT skipped: add_peer failed");
        return false;
    }

    const uint8_t *pkt = assert ? k_halt_on : k_halt_off;
    const bool ok = modulus_espnow_stack_send(peer, pkt, 9);
    if (!ok) {
        ESP_LOGW(TAG, "bridge HALT %ssend failed", assert ? "assert " : "release ");
    } else {
        ESP_LOGI(TAG, "bridge HALT %s sent", assert ? "assert" : "release");
    }
    return ok;
}

/* Last RSSI heard from the bridge (dBm), via throttled C6 EVT_RSSI.
 * false until the first report after boot/reinit. */
bool modulus_espnow_stack_bridge_rssi(int8_t *out_dbm)
{
    if (!s_bridge_rssi_valid) {
        return false;
    }
    if (out_dbm) {
        *out_dbm = s_bridge_rssi;
    }
    return true;
}
