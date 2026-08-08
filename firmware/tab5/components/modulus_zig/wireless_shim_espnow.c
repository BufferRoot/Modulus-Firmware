/*
 * ESP-NOW settings layer — peer table, discovery scan, MAC validation (C6 SDIO stack).
 */
#include "wireless_shim.h"
#include "c6_espnow_proto.h"
#include "c6_sdio_host.h"
#include "cnc_cmd_exports.h"
#include "espnow_debug.h"
#include "espnow_stack.h"
#include "nvs_shim.h"
#include "tab5_pi4ioe.h"
#include "transport_shim.h"

#include "esp_log.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/portmacro.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

#include <stdio.h>
#include <string.h>

static const char *TAG = "wl_espnow";

static bool s_espnow_on;
static uint32_t s_en_tx;
static uint32_t s_en_rx;
static bool s_bridge_ok;

static portMUX_TYPE s_en_mux = portMUX_INITIALIZER_UNLOCKED;
static bool s_scan_active;
static bool s_scan_done;
static char s_scan_err[40];
static TickType_t s_scan_deadline;
static modulus_espnow_peer_t s_scan_buf[MODULUS_ESPNOW_MAX_SCAN];
static int s_scan_n;

static SemaphoreHandle_t s_peer_sem;
static volatile bool s_peer_wait_ok;
static volatile bool s_peer_wait_armed;

static bool espnow_add_peer_wait(const uint8_t mac[6], uint8_t ch, bool encrypt, uint32_t timeout_ms);

static bool espnow_apply_bridge_peer(void);
static void espnow_scan_stop(void);
static void saved_add(const char *norm);

void modulus_wireless_espnow_ensure_radio_awake(void)
{
    /* C6 sets WIFI_PS_NONE locally in espnow_handler (init/probe/send) and at
     * coprocessor boot. Host esp_wifi_set_ps() is an esp_hosted SDIO RPC that
     * contends with ESP-NOW commands — under CNC poll load it queues multiple
     * Req_WifiSetPs calls, times out, and breaks unicast (reason=0x01). */
}

void modulus_wireless_espnow_align_channel(uint8_t ch)
{
    (void)ch;
    /* Channel + PS owned locally on C6 espnow_handler (add_peer/send/init).
     * Host esp_wifi_get/set_channel are esp_hosted SDIO RPCs (Req 0x12e/0x12d)
     * that race ESP-NOW TX on the same SDIO bus and cause reason=0x01. */
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

static bool espnow_cnc_transport_selected(void)
{
    return modulus_nvs_get_u8("cnc_conn", 4) == 0;
}

static void espnow_sync_cnc_transport(void)
{
    if (!s_espnow_on || !espnow_cnc_transport_selected()) {
        return;
    }
    if (modulus_espnow_transport_is_open()) {
        modulus_espnow_debug_event("sync", "reapply peer (transport live)");
        modulus_espnow_transport_reapply_peer();
        return;
    }
    modulus_espnow_debug_event("sync", "transport reinit (cnc_conn=espnow)");
    modulus_zig_transport_reinit();
}

bool modulus_wireless_espnow_commit_peer_mac(const char *mac_str, bool sync_transport)
{
    if (!mac_str || !mac_str[0]) {
        return false;
    }
    uint8_t mac[6];
    if (!modulus_wireless_espnow_parse_mac(mac_str, mac)) {
        ESP_LOGW(TAG, "invalid MAC '%s'", mac_str);
        return false;
    }
    char norm[18];
    modulus_wireless_espnow_format_mac(mac, norm, sizeof(norm));
    modulus_nvs_set_str("en_mac", norm);
    saved_add(norm);
    if (s_espnow_on) {
        (void)espnow_apply_bridge_peer();
        if (sync_transport) {
            espnow_sync_cnc_transport();
        }
    }
    return true;
}

bool modulus_wireless_espnow_parse_mac(const char *mac_str, uint8_t out[6])
{
    if (!mac_str || !out) {
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
    return true;
}

void modulus_wireless_espnow_format_mac(const uint8_t mac[6], char *buf, size_t len)
{
    if (!mac || !buf || len < 18) {
        return;
    }
    snprintf(buf, len, "%02X:%02X:%02X:%02X:%02X:%02X",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

uint8_t modulus_wireless_espnow_channel(void)
{
    return (uint8_t)(modulus_nvs_get_u8("en_chan", 0) + 1);
}

static void scan_note_peer(const uint8_t mac[6], int8_t rssi)
{
    if (!mac || mac_is_broadcast(mac)) {
        return;
    }
    taskENTER_CRITICAL(&s_en_mux);
    for (int i = 0; i < s_scan_n; i++) {
        if (memcmp(s_scan_buf[i].mac_bytes, mac, 6) == 0) {
            if (rssi > s_scan_buf[i].rssi) {
                s_scan_buf[i].rssi = rssi;
            }
            taskEXIT_CRITICAL(&s_en_mux);
            return;
        }
    }
    if (s_scan_n < MODULUS_ESPNOW_MAX_SCAN) {
        modulus_espnow_peer_t *p = &s_scan_buf[s_scan_n++];
        memcpy(p->mac_bytes, mac, 6);
        modulus_wireless_espnow_format_mac(mac, p->mac, sizeof(p->mac));
        p->rssi = rssi;
        p->channel = modulus_wireless_espnow_channel();
    }
    taskEXIT_CRITICAL(&s_en_mux);
}

static void espnow_stack_evt(uint8_t evt, const uint8_t *payload, uint16_t len, void *ctx)
{
    (void)ctx;
    if (modulus_espnow_log_level() >= MODULUS_ESPNOW_LOG_VERBOSE) {
        ESP_LOGD(TAG, "stack evt 0x%02x len=%u", (unsigned)evt, (unsigned)len);
    }
    switch (evt) {
    case ESPNOW_EVT_DISCOVER:
        if (payload && len >= 6) {
            int8_t rssi = (len >= 7) ? (int8_t)payload[6] : 0;
            scan_note_peer(payload, rssi);
        }
        break;
    case ESPNOW_EVT_RECV:
        if (payload && len >= 6) {
            scan_note_peer(payload, 0);
        }
        break;
    case ESPNOW_EVT_PEER_OK:
        if (payload && len >= 6) {
            s_bridge_ok = true;
            char mac[20];
            modulus_wireless_espnow_format_mac(payload, mac, sizeof(mac));
            modulus_espnow_debug_event("bridge", "peer ok %s", mac);
            if (s_peer_wait_armed) {
                s_peer_wait_ok = true;
                if (s_peer_sem) {
                    xSemaphoreGive(s_peer_sem);
                }
            }
        }
        break;
    case ESPNOW_EVT_PEER_FAIL:
        s_bridge_ok = false;
        modulus_espnow_debug_event("bridge", "peer fail");
        if (s_peer_wait_armed) {
            s_peer_wait_ok = false;
            if (s_peer_sem) {
                xSemaphoreGive(s_peer_sem);
            }
        }
        break;
    case ESPNOW_EVT_SEND_FAIL:
        /* reason=0x01 is MAC-layer ACK miss (PM/radio), not a stale peer table entry. */
        if (!payload || len < 7 || payload[6] != 0x01) {
            s_bridge_ok = false;
        }
        if (payload && len >= 10) {
            modulus_espnow_debug_event("bridge",
                "send fail reason=0x%02x radioch=%u peerch=%u setch=0x%02x",
                (unsigned)payload[6], (unsigned)payload[7],
                (unsigned)payload[8], (unsigned)payload[9]);
        } else if (payload && len >= 7) {
            modulus_espnow_debug_event("bridge", "send fail reason=0x%02x",
                                       (unsigned)payload[6]);
        } else {
            modulus_espnow_debug_event("bridge", "send fail");
        }
        break;
    case ESPNOW_EVT_INIT_FAIL:
        s_bridge_ok = false;
        if (payload && len >= 1) {
            modulus_espnow_debug_event("stack", "init fail err=%u", (unsigned)payload[0]);
        } else {
            modulus_espnow_debug_event("stack", "init fail");
        }
        if (payload && len >= 1 && s_scan_active) {
            snprintf(s_scan_err, sizeof(s_scan_err), "Init fail %u", (unsigned)payload[0]);
            s_scan_done = true;
            s_scan_active = false;
        }
        break;
    case ESPNOW_EVT_PROBE_FAIL:
        if (s_scan_active) {
            if (payload && len >= 1) {
                snprintf(s_scan_err, sizeof(s_scan_err), "Probe fail %u", (unsigned)payload[0]);
            } else {
                strncpy(s_scan_err, "Probe fail", sizeof(s_scan_err) - 1);
            }
            s_scan_done = true;
            s_scan_active = false;
        }
        break;
    default:
        break;
    }
}

static bool espnow_add_peer_wait(const uint8_t mac[6], uint8_t ch, bool encrypt, uint32_t timeout_ms)
{
    if (!s_peer_sem) {
        s_peer_sem = xSemaphoreCreateBinary();
    }
    if (!s_peer_sem) {
        return false;
    }
    while (xSemaphoreTake(s_peer_sem, 0) == pdTRUE) {
    }
    s_peer_wait_ok = false;
    s_peer_wait_armed = true;
    if (!modulus_espnow_stack_add_peer(mac, ch, encrypt)) {
        s_peer_wait_armed = false;
        return false;
    }
    const bool got = xSemaphoreTake(s_peer_sem, pdMS_TO_TICKS(timeout_ms)) == pdTRUE;
    s_peer_wait_armed = false;
    return got && s_peer_wait_ok;
}

static bool espnow_apply_bridge_peer(void)
{
    uint8_t mac[6];
    char mac_str[20];
    const uint8_t ch = modulus_wireless_espnow_channel();

    modulus_espnow_stack_register();
    if (!modulus_espnow_stack_inited()) {
        if (!modulus_espnow_stack_ensure_inited(MODULUS_ESPNOW_INIT_WAIT_MS)) {
            s_bridge_ok = false;
            modulus_espnow_debug_event("bridge", "C6 init timeout");
            return false;
        }
    }

    modulus_wireless_espnow_peer_mac_str(mac_str, sizeof(mac_str));
    if (!modulus_wireless_espnow_parse_mac(mac_str, mac) || mac_is_broadcast(mac)) {
        s_bridge_ok = false;
        modulus_espnow_debug_event("bridge", "no bridge MAC — scan or enter S3 MAC");
        ESP_LOGW(TAG, "Bridge MAC unset — Settings > Wireless > ESP-NOW scan or enter S3 MAC");
        return false;
    }

    modulus_espnow_debug_event("bridge", "apply peer %s ch%u", mac_str, (unsigned)ch);

    s_bridge_ok = false;
    if (!espnow_add_peer_wait(mac, ch, false, 1500)) {
        modulus_espnow_debug_event("bridge", "add_peer timeout/fail");
        ESP_LOGW(TAG, "C6 add_peer failed for %s ch%u", mac_str, (unsigned)ch);
        return false;
    }
    ESP_LOGI(TAG, "Bridge peer %s ch%u", mac_str, (unsigned)ch);
    modulus_espnow_debug_event("bridge", "peer ready");
    return true;
}

void modulus_wireless_espnow_apply_bridge_peer(void)
{
    (void)espnow_apply_bridge_peer();
}

static void espnow_scan_stop(void)
{
    /* Match C++ hal_wireless::espnow::scan_stop — drop bcast peer after discovery. */
    const uint8_t bcast[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    (void)modulus_espnow_stack_del_peer(bcast);
    taskENTER_CRITICAL(&s_en_mux);
    s_scan_active = false;
    taskEXIT_CRITICAL(&s_en_mux);
}

bool modulus_wireless_espnow_enable(void)
{
    if (!modulus_wireless_ready() || !modulus_wireless_ensure_wifi_stack()) {
        modulus_espnow_debug_event("radio", "enable fail (wifi stack)");
        return false;
    }
    {
        /* The bridge filters/sends to a stored Tab5 MAC. If the C6 STA MAC here
         * does not match what the bridge has, the link is one-way at best. */
        uint8_t c6mac[6] = {0};
        esp_err_t merr = esp_wifi_get_mac(WIFI_IF_STA, c6mac);
        ESP_LOGI(TAG, "C6 STA MAC %02X:%02X:%02X:%02X:%02X:%02X (%s) - bridge must expect THIS",
                 c6mac[0], c6mac[1], c6mac[2], c6mac[3], c6mac[4], c6mac[5],
                 esp_err_to_name(merr));
    }
    modulus_espnow_stack_register();
    modulus_espnow_stack_set_evt_hook(espnow_stack_evt, NULL);
    s_espnow_on = true;
    modulus_nvs_set_u8("espnow", 1);
    (void)espnow_apply_bridge_peer();
    modulus_espnow_debug_event("radio", "enabled");
    ESP_LOGI(TAG, "ESP-NOW radio enabled");
    return true;
}

void modulus_wireless_espnow_disable(void)
{
    modulus_espnow_debug_event("radio", "disabled");
    espnow_scan_stop();
    s_espnow_on = false;
    s_bridge_ok = false;
    modulus_nvs_set_u8("espnow", 0);
    taskENTER_CRITICAL(&s_en_mux);
    s_scan_active = false;
    s_scan_done = false;
    s_scan_err[0] = '\0';
    s_scan_n = 0;
    taskEXIT_CRITICAL(&s_en_mux);
    modulus_espnow_stack_deinit();
    modulus_espnow_transport_stop();
}

bool modulus_wireless_espnow_is_enabled(void)
{
    return s_espnow_on;
}

bool modulus_wireless_espnow_bridge_ready(void)
{
    return s_espnow_on && s_bridge_ok;
}

void modulus_wireless_espnow_peer_mac_str(char *buf, size_t len)
{
    if (!buf || len == 0) {
        return;
    }
    if (!modulus_nvs_get_str("en_mac", buf, len)) {
        strncpy(buf, "FF:FF:FF:FF:FF:FF", len);
        buf[len - 1] = '\0';
    }
}

/* ── Saved peer list (NVS): en_pn = count, en_p0..en_pN = MAC strings ── */

static void saved_key(int i, char *buf, size_t len)
{
    snprintf(buf, len, "en_p%d", i);
}

static int saved_count_raw(void)
{
    int n = (int)modulus_nvs_get_u8("en_pn", 0);
    if (n > MODULUS_ESPNOW_MAX_PEERS) {
        n = MODULUS_ESPNOW_MAX_PEERS;
    }
    return n;
}

static bool saved_get_str(int i, char *out, size_t len)
{
    char key[8];
    saved_key(i, key, sizeof(key));
    return modulus_nvs_get_str(key, out, len) && out[0];
}

/* Append a normalized MAC to the saved list (dedupe, cap at MAX). */
static void saved_add(const char *norm)
{
    uint8_t mac[6];
    if (!modulus_wireless_espnow_parse_mac(norm, mac) || mac_is_broadcast(mac)) {
        return;
    }
    const int n = saved_count_raw();
    for (int i = 0; i < n; i++) {
        char ex[20];
        if (saved_get_str(i, ex, sizeof(ex)) && strcmp(ex, norm) == 0) {
            return;  /* already saved */
        }
    }
    if (n >= MODULUS_ESPNOW_MAX_PEERS) {
        return;  /* list full */
    }
    char key[8];
    saved_key(n, key, sizeof(key));
    modulus_nvs_set_str(key, norm);
    modulus_nvs_set_u8("en_pn", (uint8_t)(n + 1));
}

int modulus_wireless_espnow_saved_count(void)
{
    return saved_count_raw();
}

bool modulus_wireless_espnow_saved_get(int idx, modulus_espnow_peer_t *out)
{
    if (!out || idx < 0 || idx >= saved_count_raw()) {
        return false;
    }
    char mac[20];
    if (!saved_get_str(idx, mac, sizeof(mac))) {
        return false;
    }
    memset(out, 0, sizeof(*out));
    strncpy(out->mac, mac, sizeof(out->mac) - 1);
    (void)modulus_wireless_espnow_parse_mac(mac, out->mac_bytes);
    out->channel = modulus_wireless_espnow_channel();
    return true;
}

bool modulus_wireless_espnow_saved_is_active(int idx)
{
    modulus_espnow_peer_t p = {};
    if (!modulus_wireless_espnow_saved_get(idx, &p)) {
        return false;
    }
    char active[20];
    modulus_wireless_espnow_peer_mac_str(active, sizeof(active));
    return strcmp(active, p.mac) == 0;
}

bool modulus_wireless_espnow_activate_saved(int idx)
{
    modulus_espnow_peer_t p = {};
    if (!modulus_wireless_espnow_saved_get(idx, &p)) {
        return false;
    }
    return modulus_wireless_espnow_set_peer_mac(p.mac);
}

bool modulus_wireless_espnow_delete_saved(int idx)
{
    const int n = saved_count_raw();
    if (idx < 0 || idx >= n) {
        return false;
    }
    char target[20] = "";
    (void)saved_get_str(idx, target, sizeof(target));
    /* Compact: shift entries above idx down one slot. */
    for (int i = idx; i < n - 1; i++) {
        char nxt[20] = "";
        (void)saved_get_str(i + 1, nxt, sizeof(nxt));
        char key[8];
        saved_key(i, key, sizeof(key));
        modulus_nvs_set_str(key, nxt);
    }
    char last_key[8];
    saved_key(n - 1, last_key, sizeof(last_key));
    modulus_nvs_set_str(last_key, "");
    modulus_nvs_set_u8("en_pn", (uint8_t)(n - 1));
    /* If the deleted saved entry was active, drop C6 peer only — keep en_mac so
     * the user can re-save or scan without losing the bridge target. */
    char active[20];
    modulus_wireless_espnow_peer_mac_str(active, sizeof(active));
    if (target[0] && strcmp(active, target) == 0) {
        uint8_t raw[6];
        if (modulus_wireless_espnow_parse_mac(target, raw)) {
            (void)modulus_espnow_stack_del_peer(raw);
        }
        s_bridge_ok = false;
    }
    return true;
}

bool modulus_wireless_espnow_set_peer_mac(const char *mac_str)
{
    return modulus_wireless_espnow_commit_peer_mac(mac_str, true);
}

uint32_t modulus_wireless_espnow_tx_count(void)
{
    return s_en_tx;
}

uint32_t modulus_wireless_espnow_rx_count(void)
{
    return s_en_rx;
}

void modulus_wireless_espnow_tx_inc(void)
{
    s_en_tx++;
}

void modulus_wireless_espnow_rx_inc(void)
{
    s_en_rx++;
}

const char *modulus_wireless_espnow_bridge_text(void)
{
    static char buf[48];
    if (!s_espnow_on) {
        return "Radio off";
    }
    char mac[20];
    modulus_wireless_espnow_peer_mac_str(mac, sizeof(mac));
    uint8_t raw[6];
    if (!modulus_wireless_espnow_parse_mac(mac, raw) || mac_is_broadcast(raw)) {
        return "No bridge peer";
    }
    if (s_bridge_ok) {
        if (espnow_cnc_transport_selected() && modulus_espnow_transport_is_open()) {
            snprintf(buf, sizeof(buf), "%.17s CNC live", mac);
        } else if (espnow_cnc_transport_selected()) {
            snprintf(buf, sizeof(buf), "%.17s bridge ok", mac);
        } else {
            snprintf(buf, sizeof(buf), "%.17s bridge only", mac);
        }
        return buf;
    }
    snprintf(buf, sizeof(buf), "%.17s pending", mac);
    return buf;
}

bool modulus_wireless_espnow_transport_active(void)
{
    return espnow_cnc_transport_selected() && modulus_espnow_transport_is_open();
}

const char *modulus_wireless_espnow_scan_text(void)
{
    static char err_buf[40];
    if (!s_espnow_on) {
        return "Radio off";
    }
    taskENTER_CRITICAL(&s_en_mux);
    const bool active = s_scan_active;
    const bool done = s_scan_done;
    const int n = s_scan_n;
    err_buf[0] = '\0';
    if (s_scan_err[0]) {
        strncpy(err_buf, s_scan_err, sizeof(err_buf) - 1);
        err_buf[sizeof(err_buf) - 1] = '\0';
    }
    taskEXIT_CRITICAL(&s_en_mux);
    if (err_buf[0]) {
        return err_buf;
    }
    if (active && !done) {
        return "Scanning...";
    }
    static char buf[24];
    snprintf(buf, sizeof(buf), "%d peer(s)", n);
    return buf;
}

bool modulus_wireless_espnow_scan_failed(void)
{
    taskENTER_CRITICAL(&s_en_mux);
    const bool failed = s_scan_err[0] != '\0';
    taskEXIT_CRITICAL(&s_en_mux);
    return failed;
}

bool modulus_wireless_espnow_scan_start(void)
{
    if (!s_espnow_on) {
        return false;
    }
    if (modulus_espnow_transport_is_open()) {
        taskENTER_CRITICAL(&s_en_mux);
        strncpy(s_scan_err, "Disconnect CNC first", sizeof(s_scan_err) - 1);
        s_scan_err[sizeof(s_scan_err) - 1] = '\0';
        s_scan_active = false;
        s_scan_done = true;
        taskEXIT_CRITICAL(&s_en_mux);
        return false;
    }
    if (!modulus_wireless_ensure_wifi_stack()) {
        taskENTER_CRITICAL(&s_en_mux);
        strncpy(s_scan_err, "WiFi stack down", sizeof(s_scan_err) - 1);
        s_scan_done = true;
        s_scan_active = false;
        taskEXIT_CRITICAL(&s_en_mux);
        return false;
    }
    taskENTER_CRITICAL(&s_en_mux);
    s_scan_active = true;
    s_scan_done = false;
    s_scan_n = 0;
    s_scan_err[0] = '\0';
    s_scan_deadline = xTaskGetTickCount() + pdMS_TO_TICKS(3500);
    taskEXIT_CRITICAL(&s_en_mux);

    tab5_pi4ioe_wait_c6_sdio_ready();

    const uint8_t ch = modulus_wireless_espnow_channel();
    if (ch < 1 || ch > 13) {
        taskENTER_CRITICAL(&s_en_mux);
        strncpy(s_scan_err, "Invalid channel", sizeof(s_scan_err) - 1);
        s_scan_active = false;
        s_scan_done = true;
        taskEXIT_CRITICAL(&s_en_mux);
        return false;
    }
    /* Channel owned by C6 probe handler — avoid host esp_wifi_set_channel RPC. */

    if (!modulus_espnow_stack_ensure_inited(MODULUS_ESPNOW_INIT_WAIT_MS)) {
        taskENTER_CRITICAL(&s_en_mux);
        if (!s_scan_err[0]) {
            if (!modulus_c6_sdio_ready()) {
                strncpy(s_scan_err, "C6 SDIO down", sizeof(s_scan_err) - 1);
            } else {
                strncpy(s_scan_err, "ESP-NOW init timeout", sizeof(s_scan_err) - 1);
            }
        }
        s_scan_active = false;
        s_scan_done = true;
        taskEXIT_CRITICAL(&s_en_mux);
        return false;
    }

    modulus_espnow_debug_event("scan", "probe ch%u", (unsigned)ch);
    if (!modulus_espnow_stack_probe(ch)) {
        taskENTER_CRITICAL(&s_en_mux);
        strncpy(s_scan_err, "Probe send fail", sizeof(s_scan_err) - 1);
        s_scan_done = true;
        taskEXIT_CRITICAL(&s_en_mux);
        espnow_scan_stop();
        return false;
    }
    return true;
}

bool modulus_wireless_espnow_scan_done(void)
{
    taskENTER_CRITICAL(&s_en_mux);
    const bool v = s_scan_done || !s_scan_active;
    taskEXIT_CRITICAL(&s_en_mux);
    return v;
}

int modulus_wireless_espnow_scan_count(void)
{
    taskENTER_CRITICAL(&s_en_mux);
    const int n = s_scan_n;
    taskEXIT_CRITICAL(&s_en_mux);
    return n;
}

bool modulus_wireless_espnow_scan_get(int idx, modulus_espnow_peer_t *out)
{
    if (!out || idx < 0) {
        return false;
    }
    taskENTER_CRITICAL(&s_en_mux);
    if (idx >= s_scan_n) {
        taskEXIT_CRITICAL(&s_en_mux);
        return false;
    }
    *out = s_scan_buf[idx];
    taskEXIT_CRITICAL(&s_en_mux);
    return true;
}

bool modulus_wireless_espnow_select_scan_peer(int idx)
{
    modulus_espnow_peer_t peer = {};
    if (!modulus_wireless_espnow_scan_get(idx, &peer)) {
        return false;
    }
    return modulus_wireless_espnow_set_peer_mac(peer.mac);
}

bool modulus_wireless_espnow_remove_bridge_peer(void)
{
    uint8_t mac[6];
    char mac_str[20];
    modulus_wireless_espnow_peer_mac_str(mac_str, sizeof(mac_str));
    if (modulus_wireless_espnow_parse_mac(mac_str, mac)) {
        (void)modulus_espnow_stack_del_peer(mac);
    }
    modulus_nvs_set_str("en_mac", "FF:FF:FF:FF:FF:FF");
    s_bridge_ok = false;
    modulus_espnow_transport_stop();
    return true;
}

void modulus_wireless_espnow_clear_peers(void)
{
    /* Drop saved-peer list and scan results; keep bridge MAC (en_mac) so CNC
     * transport is not wiped by an advanced-menu housekeeping action. */
    const int n = saved_count_raw();
    for (int i = 0; i < n; i++) {
        char key[8];
        saved_key(i, key, sizeof(key));
        modulus_nvs_set_str(key, "");
    }
    modulus_nvs_set_u8("en_pn", 0);
    uint8_t bcast[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    (void)modulus_espnow_stack_del_peer(bcast);
    taskENTER_CRITICAL(&s_en_mux);
    s_scan_n = 0;
    s_scan_active = false;
    s_scan_done = false;
    s_scan_err[0] = '\0';
    taskEXIT_CRITICAL(&s_en_mux);
}

void modulus_wireless_espnow_poll_scan(void)
{
    if (!s_espnow_on) {
        return;
    }
    taskENTER_CRITICAL(&s_en_mux);
    if (!s_scan_active || s_scan_done) {
        taskEXIT_CRITICAL(&s_en_mux);
        return;
    }
    if (xTaskGetTickCount() >= s_scan_deadline) {
        s_scan_done = true;
        taskEXIT_CRITICAL(&s_en_mux);
        espnow_scan_stop();
        (void)espnow_apply_bridge_peer();
        return;
    }
    taskEXIT_CRITICAL(&s_en_mux);
}

void modulus_wireless_espnow_transport_reinit(void)
{
    if (!s_espnow_on) {
        return;
    }
    modulus_espnow_debug_event("reinit", "espnow transport reinit");
    if (!modulus_c6_sdio_ready()) {
        modulus_espnow_debug_event("reinit", "SDIO down — skip peer apply");
        if (modulus_espnow_transport_is_open()) {
            modulus_espnow_transport_stop();
        }
        return;
    }
    (void)espnow_apply_bridge_peer();
    if (modulus_espnow_transport_is_open() && modulus_c6_sdio_ready()) {
        modulus_espnow_debug_event("sync", "transport live — peer refreshed");
        return;
    }
    espnow_sync_cnc_transport();
}

uint8_t modulus_wireless_espnow_log_level(void)
{
    return modulus_espnow_log_level();
}

void modulus_wireless_espnow_log_set_level(uint8_t level)
{
    modulus_espnow_log_set_level(level);
}

bool modulus_wireless_espnow_debug_active(void)
{
    return modulus_espnow_log_active();
}

const char *modulus_wireless_espnow_debug_snapshot(void)
{
    return modulus_espnow_debug_snapshot();
}

const char *modulus_wireless_espnow_debug_last_event(void)
{
    return modulus_espnow_debug_last_event();
}

static bool boot_reconnect_wanted(void)
{
    if (modulus_nvs_get_u8("espnow", 0) != 0) {
        return true;
    }
    if (modulus_nvs_get_u8("cnc_conn", 4) != 0) {
        return false;
    }
    char mac[20];
    if (modulus_nvs_get_str("en_mac", mac, sizeof(mac)) && mac[0] &&
        strcmp(mac, "FF:FF:FF:FF:FF:FF") != 0) {
        return true;
    }
    return modulus_wireless_espnow_saved_count() > 0;
}

static bool boot_reconnect_once(const char *phase)
{
    if (!boot_reconnect_wanted()) {
        modulus_espnow_debug_event("boot", "skip (%s): no saved peer/radio", phase);
        return true;
    }
    if (!modulus_wireless_espnow_is_enabled()) {
        if (!modulus_wireless_espnow_enable()) {
            modulus_espnow_debug_event("boot", "reconnect (%s): radio not ready", phase);
            return false;
        }
    } else {
        modulus_wireless_espnow_apply_bridge_peer();
    }
    if (modulus_nvs_get_u8("cnc_conn", 4) == 0 && !modulus_espnow_transport_is_open()) {
        modulus_espnow_debug_event("boot", "reconnect (%s): transport reinit", phase);
        espnow_sync_cnc_transport();
    }
    return modulus_wireless_espnow_bridge_ready() ||
        modulus_wireless_espnow_is_enabled();
}

static void deferred_boot_reconnect_task(void *arg)
{
    (void)arg;
    for (int attempt = 1; attempt <= 8; attempt++) {
        vTaskDelay(pdMS_TO_TICKS(2000));
        modulus_espnow_debug_event("boot", "reconnect retry %d/8", attempt);
        if (boot_reconnect_once("retry")) {
            break;
        }
    }
    vTaskDelete(NULL);
}

void modulus_wireless_espnow_boot_reconnect(void)
{
    if (boot_reconnect_once("boot")) {
        return;
    }
    static bool started;
    if (started) {
        return;
    }
    started = true;
    xTaskCreate(deferred_boot_reconnect_task, "espnow_boot", 4096, NULL, 3, NULL);
}
