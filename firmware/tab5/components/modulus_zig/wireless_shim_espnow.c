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

/* Full 2.4 GHz sweep: the S3 takes any 1-13 from its own console and cannot
 * announce where it parked, so probing only {en_chan,1,6,11} leaves a bridge on
 * ch3/4/5/... permanently undiscoverable. 13 x 250 ms fits inside the window. */
#define MODULUS_ESPNOW_CHANNEL_MAX 13
#define ESPNOW_SCAN_WINDOW_MS 5000
#define ESPNOW_SCAN_DWELL_MS  250

/* Channel the sweep is probing right now (0 = use configured en_chan). */
static uint8_t s_scan_probe_ch;

/* RAM mirror of en_chan — never read NVS from SDIO RX / espnow_stack_evt (lock abort). */
static uint8_t s_bridge_ch_cached;

static uint8_t espnow_channel_from_nvs(void)
{
    uint8_t ch = (uint8_t)(modulus_nvs_get_u8("en_chan", 0) + 1);
    if (ch < 1 || ch > MODULUS_ESPNOW_CHANNEL_MAX) {
        ch = 1;
    }
    return ch;
}

void modulus_wireless_espnow_channel_reload(void)
{
    s_bridge_ch_cached = espnow_channel_from_nvs();
}

void modulus_wireless_espnow_set_channel(uint8_t channel)
{
    if (channel < 1 || channel > MODULUS_ESPNOW_CHANNEL_MAX) {
        return;
    }
    s_bridge_ch_cached = channel;
    modulus_nvs_set_u8("en_chan", (uint8_t)(channel - 1));
}

static SemaphoreHandle_t s_peer_sem;
static volatile bool s_peer_wait_ok;
static volatile bool s_peer_wait_armed;

static bool espnow_add_peer_wait(const uint8_t mac[6], uint8_t ch, bool encrypt, uint32_t timeout_ms);
static bool espnow_ping_locate_peer(const uint8_t peer[6], uint8_t *found_ch);

static bool espnow_apply_bridge_peer_ex(bool locate_if_dark);
/** Configured channel only — safe for boot / SDIO (no channel sweep). */
static bool espnow_apply_bridge_peer(void);
static void schedule_bridge_reapply(void);
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

static bool espnow_radio_usable(void)
{
    return modulus_wireless_ready() && modulus_wireless_transport_up() &&
           modulus_wireless_wifi_sta_running();
}

void modulus_wireless_espnow_on_wifi_stop(void)
{
    bool finish = false;
    taskENTER_CRITICAL(&s_en_mux);
    if (s_scan_active && !s_scan_done) {
        strncpy(s_scan_err, "WiFi stopped", sizeof(s_scan_err) - 1);
        s_scan_err[sizeof(s_scan_err) - 1] = '\0';
        s_scan_done = true;
        s_scan_active = false;
        finish = true;
    }
    taskEXIT_CRITICAL(&s_en_mux);
    if (finish) {
        espnow_scan_stop();
    }
    s_bridge_ok = false;
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

static bool espnow_bridge_mac_configured(void)
{
    char mac_str[20];
    uint8_t mac[6];
    modulus_wireless_espnow_peer_mac_str(mac_str, sizeof(mac_str));
    return modulus_wireless_espnow_parse_mac(mac_str, mac) && !mac_is_broadcast(mac);
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
    if (!modulus_wireless_espnow_bridge_ready()) {
        if (!espnow_bridge_mac_configured()) {
            modulus_espnow_debug_event("sync", "no bridge MAC — skip transport open");
            return;
        }
        if (!espnow_apply_bridge_peer()) {
            modulus_espnow_debug_event("sync", "bridge dark — skip transport open");
            return;
        }
    }
    /* Always full Zig reinit (Core 0 worker). Reapply-only left half-open
     * transports: Session stuck on Connecting after reboot / peer reselect. */
    if (modulus_espnow_transport_is_open()) {
        modulus_espnow_debug_event("sync", "stop then reinit (was open)");
        modulus_espnow_transport_stop();
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
    /* Do NOT saved_add here — transport restart / radio toggle used to resurrect
     * peers after Remove. Explicit save paths call set_peer_mac / saved_add. */
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

static bool s_scan_radio_held;

static void espnow_scan_finish_radio(void)
{
    if (!s_scan_radio_held) {
        return;
    }
    s_scan_radio_held = false;
    if (modulus_espnow_stack_scan_supported()) {
        modulus_espnow_stack_scan_end();
    }
    modulus_wireless_radio_op_give();
}

static uint8_t s_applied_mac[6];
static uint8_t s_applied_ch;
static bool s_applied_valid;

void modulus_wireless_espnow_check_channel_conflict(void)
{
    if (!modulus_wireless_wifi_is_connected()) {
        return;
    }
    wifi_ap_record_t ap = {};
    if (esp_wifi_sta_get_ap_info(&ap) != ESP_OK || ap.primary < 1 || ap.primary > 13) {
        return;
    }
    const uint8_t bridge_ch = modulus_wireless_espnow_channel();
    if (ap.primary == bridge_ch) {
        return;
    }
    /* This used to overwrite en_chan with the AP channel. That is unrecoverable:
     * the S3 bridge takes a channel only from its own USB console ("channel N")
     * and has no over-the-air handoff, so it can never follow us — and en_chan
     * is the only record of where the bridge actually lives. Persisting the AP
     * channel destroyed it for good (NVS survives reboot) and every unicast
     * then died with reason=0x01. One radio cannot serve two channels; say so
     * and leave the bridge channel alone. */
    static uint8_t s_warned_ap_ch;
    if (s_warned_ap_ch != ap.primary) {
        s_warned_ap_ch = ap.primary;
        ESP_LOGW(TAG, "Wi-Fi AP is ch%u but ESP-NOW bridge is ch%u — one radio "
                      "cannot serve both. Set the S3 to ch%u (console 'channel %u') "
                      "or join an AP on ch%u.",
                 (unsigned)ap.primary, (unsigned)bridge_ch,
                 (unsigned)ap.primary, (unsigned)ap.primary, (unsigned)bridge_ch);
    }
    modulus_espnow_debug_event("chan", "AP ch%u != bridge ch%u",
                               (unsigned)ap.primary, (unsigned)bridge_ch);
}

uint8_t modulus_wireless_espnow_channel(void)
{
    if (s_bridge_ch_cached < 1 || s_bridge_ch_cached > MODULUS_ESPNOW_CHANNEL_MAX) {
        s_bridge_ch_cached = espnow_channel_from_nvs();
    }
    return s_bridge_ch_cached;
}

/* Bridge channel candidates, best-first: configured, then S3 default (ch1),
 * then the rest. Shared by discovery sweep and ping-locate. */
static int espnow_channel_candidates(uint8_t *out, int cap)
{
    int n = 0;
    const uint8_t cfg = modulus_wireless_espnow_channel();
    if (cfg >= 1 && cfg <= MODULUS_ESPNOW_CHANNEL_MAX && n < cap) {
        out[n++] = cfg;
    }
    if (n < cap) {
        bool dup = false;
        for (int j = 0; j < n; j++) {
            if (out[j] == 1) {
                dup = true;
                break;
            }
        }
        if (!dup) {
            out[n++] = 1;
        }
    }
    static const uint8_t k_order[] = {6, 11, 2, 3, 4, 5, 7, 8, 9, 10, 12, 13};
    for (unsigned i = 0; i < sizeof(k_order) && n < cap; i++) {
        bool dup = false;
        for (int j = 0; j < n; j++) {
            if (out[j] == k_order[i]) {
                dup = true;
                break;
            }
        }
        if (!dup) {
            out[n++] = k_order[i];
        }
    }
    return n;
}

static bool espnow_verify_peer_air(const uint8_t mac[6], uint8_t ch)
{
    static const uint8_t k_probe[] = "MOD_PROBE";
    if (!espnow_add_peer_wait(mac, ch, false, 600)) {
        return false;
    }
    return modulus_espnow_stack_send_discovery(mac, k_probe, sizeof(k_probe) - 1);
}

static void scan_note_peer(const uint8_t mac[6], int8_t rssi)
{
    if (!mac || mac_is_broadcast(mac)) {
        return;
    }
    /* NVS/mutex before critical — sdio_process_rx must not lock inside s_en_mux. */
    const uint8_t note_ch = s_scan_probe_ch ? s_scan_probe_ch : modulus_wireless_espnow_channel();
    taskENTER_CRITICAL(&s_en_mux);
    for (int i = 0; i < s_scan_n; i++) {
        if (memcmp(s_scan_buf[i].mac_bytes, mac, 6) == 0) {
            if (note_ch >= 1 && note_ch <= 13) {
                s_scan_buf[i].channel = note_ch;
            }
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
        p->channel = note_ch;
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
        } else {
            schedule_bridge_reapply();
        }
        break;
    case ESPNOW_EVT_SEND_FAIL:
        /* reason=0x01 is MAC-layer ACK miss (PM/radio), not a stale peer table entry. */
        if (!payload || len < 7 || payload[6] != 0x01) {
            s_bridge_ok = false;
            if (!s_peer_wait_armed) {
                schedule_bridge_reapply();
            }
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
            espnow_scan_finish_radio();
        }
        break;
    case ESPNOW_EVT_PROBE_FAIL:
        /* Probe kick failed — keep listening until deadline so UI shows Scanning
         * and late DISCOVER frames still count. */
        if (s_scan_active) {
            if (payload && len >= 1) {
                modulus_espnow_debug_event("scan", "probe fail err=%u (window open)",
                                           (unsigned)payload[0]);
            } else {
                modulus_espnow_debug_event("scan", "probe fail (window open)");
            }
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

static bool espnow_apply_bridge_peer_ex(bool locate_if_dark)
{
    if (!espnow_radio_usable()) {
        s_bridge_ok = false;
        return false;
    }
    if (!espnow_bridge_mac_configured()) {
        s_bridge_ok = false;
        s_applied_valid = false;
        return false;
    }

    uint8_t mac[6];
    char mac_str[20];
    uint8_t ch = modulus_wireless_espnow_channel();
    const bool encrypt = modulus_nvs_get_u8("en_enc", 0) != 0;

    modulus_wireless_espnow_peer_mac_str(mac_str, sizeof(mac_str));
    if (!modulus_wireless_espnow_parse_mac(mac_str, mac) || mac_is_broadcast(mac)) {
        s_bridge_ok = false;
        s_applied_valid = false;
        return false;
    }

    modulus_espnow_stack_register();
    if (!modulus_espnow_stack_inited()) {
        if (!modulus_espnow_stack_ensure_inited(MODULUS_ESPNOW_INIT_WAIT_MS)) {
            s_bridge_ok = false;
            modulus_espnow_debug_event("bridge", "C6 init timeout");
            return false;
        }
    }

    if (s_bridge_ok && s_applied_valid && s_applied_ch == ch &&
        memcmp(s_applied_mac, mac, 6) == 0) {
        if (!locate_if_dark || espnow_verify_peer_air(mac, ch)) {
            return true;
        }
        s_applied_valid = false;
        s_bridge_ok = false;
    }

    modulus_espnow_debug_event("bridge", "apply peer %s ch%u", mac_str, (unsigned)ch);

    s_bridge_ok = false;
    uint8_t live_ch = ch;

    if (!locate_if_dark) {
        /* LVGL hal_wireless::espnow::enable — add_peer on configured channel only. */
        if (!espnow_add_peer_wait(mac, ch, encrypt, 600)) {
            return false;
        }
        ESP_LOGI(TAG, "Bridge peer %s ch%u (added)", mac_str, (unsigned)ch);
    } else if (!espnow_verify_peer_air(mac, ch) &&
               !espnow_ping_locate_peer(mac, &live_ch)) {
        modulus_espnow_debug_event("bridge", "peer dark on all channels");
        ESP_LOGW(TAG, "Bridge %s not reachable (check S3 power + channel)", mac_str);
        return false;
    } else if (live_ch != ch && live_ch >= 1 && live_ch <= 13) {
        ch = live_ch;
        modulus_wireless_espnow_set_channel(ch);
        ESP_LOGI(TAG, "Bridge peer %s ch%u (located)", mac_str, (unsigned)ch);
    } else {
        ESP_LOGI(TAG, "Bridge peer %s ch%u", mac_str, (unsigned)ch);
    }

    modulus_espnow_debug_event("bridge", "peer ready");
    memcpy(s_applied_mac, mac, 6);
    s_applied_ch = ch;
    s_applied_valid = true;
    s_bridge_ok = true;
    return true;
}

static bool espnow_apply_bridge_peer(void)
{
    return espnow_apply_bridge_peer_ex(false);
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
    espnow_scan_finish_radio();
}

bool modulus_wireless_espnow_enable(void)
{
    if (s_espnow_on) {
        if (espnow_bridge_mac_configured()) {
            schedule_bridge_reapply();
        }
        return true;
    }
    /* LVGL hal_wireless::espnow::enable — init stack + ESPNOW_CMD_INIT, no wake. */
    modulus_wireless_espnow_channel_reload();
    if (!modulus_wireless_ready() && !modulus_wireless_init()) {
        modulus_espnow_debug_event("radio", "enable fail (wireless init)");
        return false;
    }
    if (!modulus_wireless_ensure_wifi_stack()) {
        modulus_espnow_debug_event("radio", "enable fail (wifi stack)");
        return false;
    }
    modulus_espnow_stack_register();
    modulus_espnow_stack_set_evt_hook(espnow_stack_evt, NULL);
    modulus_wireless_espnow_check_channel_conflict();
    if (!modulus_espnow_stack_ensure_inited(MODULUS_ESPNOW_INIT_WAIT_MS)) {
        modulus_espnow_debug_event("radio", "enable fail (C6 ESP-NOW init)");
        return false;
    }
    {
        uint8_t c6mac[6] = {0};
        esp_err_t merr = esp_wifi_get_mac(WIFI_IF_STA, c6mac);
        ESP_LOGI(TAG, "C6 STA MAC %02X:%02X:%02X:%02X:%02X:%02X (%s) - bridge must expect THIS",
                 c6mac[0], c6mac[1], c6mac[2], c6mac[3], c6mac[4], c6mac[5],
                 esp_err_to_name(merr));
    }
    s_espnow_on = true;
    modulus_nvs_set_u8("espnow", 1);
    /* Bridge peer apply deferred to transport start / user Connect — boot
     * add_peer + MOD_PROBE while S3 is dark wedges SDIO (0x107). */
    modulus_espnow_debug_event("radio", "enabled");
    ESP_LOGI(TAG, "ESP-NOW radio enabled");
    return true;
}

int modulus_wireless_espnow_enable_zi(void)
{
    return modulus_wireless_espnow_enable() ? 1 : 0;
}

void modulus_wireless_espnow_disable(void)
{
    modulus_espnow_debug_event("radio", "disabled");
    espnow_scan_stop();
    s_espnow_on = false;
    s_bridge_ok = false;
    s_applied_valid = false;
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
    /* Remove must stick: clear bridge MAC if this was the active peer, otherwise
     * radio/transport restart re-seeded the saved list from en_mac. */
    char active[20];
    modulus_wireless_espnow_peer_mac_str(active, sizeof(active));
    if (target[0] && strcmp(active, target) == 0) {
        uint8_t raw[6];
        if (modulus_wireless_espnow_parse_mac(target, raw)) {
            (void)modulus_espnow_stack_del_peer(raw);
        }
        modulus_nvs_set_str("en_mac", "FF:FF:FF:FF:FF:FF");
        s_bridge_ok = false;
        modulus_espnow_transport_stop();
    }
    return true;
}

bool modulus_wireless_espnow_set_peer_mac(const char *mac_str)
{
    /* User-facing save (scan tap / Activate / Add MAC) — persist into saved list. */
    if (!mac_str || !mac_str[0]) {
        return false;
    }
    uint8_t mac[6];
    if (!modulus_wireless_espnow_parse_mac(mac_str, mac) || mac_is_broadcast(mac)) {
        return false;
    }
    char norm[18];
    modulus_wireless_espnow_format_mac(mac, norm, sizeof(norm));
    if (!modulus_wireless_espnow_commit_peer_mac(norm, true)) {
        return false;
    }
    saved_add(norm);
    return true;
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

static void espnow_scan_worker(void *arg)
{
    (void)arg;
    modulus_wireless_espnow_check_channel_conflict();
    const uint8_t ch = modulus_wireless_espnow_channel();

    if (!s_espnow_on) {
        taskENTER_CRITICAL(&s_en_mux);
        strncpy(s_scan_err, "Radio off", sizeof(s_scan_err) - 1);
        s_scan_active = false;
        s_scan_done = true;
        taskEXIT_CRITICAL(&s_en_mux);
        espnow_scan_finish_radio();
        vTaskDelete(NULL);
        return;
    }

    if (!espnow_radio_usable()) {
        taskENTER_CRITICAL(&s_en_mux);
        strncpy(s_scan_err, "WiFi stopped", sizeof(s_scan_err) - 1);
        s_scan_err[sizeof(s_scan_err) - 1] = '\0';
        s_scan_active = false;
        s_scan_done = true;
        taskEXIT_CRITICAL(&s_en_mux);
        espnow_scan_finish_radio();
        vTaskDelete(NULL);
        return;
    }

    if (!modulus_wireless_ensure_wifi_stack()) {
        taskENTER_CRITICAL(&s_en_mux);
        strncpy(s_scan_err, "WiFi stack down", sizeof(s_scan_err) - 1);
        s_scan_active = false;
        s_scan_done = true;
        taskEXIT_CRITICAL(&s_en_mux);
        espnow_scan_finish_radio();
        vTaskDelete(NULL);
        return;
    }

    tab5_pi4ioe_wait_c6_sdio_ready();

    if (ch < 1 || ch > 13) {
        taskENTER_CRITICAL(&s_en_mux);
        strncpy(s_scan_err, "Invalid channel", sizeof(s_scan_err) - 1);
        s_scan_active = false;
        s_scan_done = true;
        taskEXIT_CRITICAL(&s_en_mux);
        espnow_scan_finish_radio();
        vTaskDelete(NULL);
        return;
    }

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
        espnow_scan_finish_radio();
        vTaskDelete(NULL);
        return;
    }

    if (modulus_espnow_stack_scan_supported()) {
        (void)modulus_espnow_stack_scan_begin(ESPNOW_SCAN_WINDOW_MS);
    }

    /* A single-channel probe misses any bridge parked elsewhere. Sweep the whole
     * band when no STA link owns the PHY; hopping while associated would drop
     * the AP, so then we can only probe the channel the radio is already on. */
    uint8_t sweep[MODULUS_ESPNOW_CHANNEL_MAX];
    int sweep_n = 1;
    sweep[0] = ch;
    if (!modulus_wireless_wifi_is_connected()) {
        sweep_n = espnow_channel_candidates(sweep, (int)sizeof(sweep));
    }

    for (int i = 0; i < sweep_n; i++) {
        s_scan_probe_ch = sweep[i];
        modulus_espnow_debug_event("scan", "probe ch%u (%d/%d)", (unsigned)sweep[i], i + 1,
                                   sweep_n);
        /* Probe kick is best-effort — window stays open until poll_scan deadline. */
        if (!modulus_espnow_stack_probe(sweep[i])) {
            modulus_espnow_debug_event("scan", "probe ch%u send fail", (unsigned)sweep[i]);
        }
        vTaskDelay(pdMS_TO_TICKS(ESPNOW_SCAN_DWELL_MS));
    }

    s_scan_probe_ch = 0;
    /* Do not snap back to stale en_chan after the sweep found the bridge elsewhere. */
    uint8_t lock_ch = ch;
    uint8_t bridge_mac[6];
    char mac_str[20];
    modulus_wireless_espnow_peer_mac_str(mac_str, sizeof(mac_str));
    if (modulus_wireless_espnow_parse_mac(mac_str, bridge_mac) &&
        !mac_is_broadcast(bridge_mac)) {
        taskENTER_CRITICAL(&s_en_mux);
        int8_t best_rssi = -128;
        for (int i = 0; i < s_scan_n; i++) {
            if (memcmp(s_scan_buf[i].mac_bytes, bridge_mac, 6) != 0) {
                continue;
            }
            if (s_scan_buf[i].channel >= 1 && s_scan_buf[i].channel <= 13 &&
                s_scan_buf[i].rssi >= best_rssi) {
                best_rssi = s_scan_buf[i].rssi;
                lock_ch = s_scan_buf[i].channel;
            }
        }
        taskEXIT_CRITICAL(&s_en_mux);
        if (lock_ch != ch && lock_ch >= 1 && lock_ch <= 13) {
            modulus_wireless_espnow_set_channel(lock_ch);
            s_applied_valid = false;
            s_bridge_ok = false;
            ESP_LOGI(TAG, "ESP-NOW channel follows scan hit ch%u", (unsigned)lock_ch);
        }
    }
    if (sweep_n > 1 || lock_ch != ch) {
        (void)modulus_espnow_stack_lock_channel(lock_ch);
    }
    vTaskDelete(NULL);
}

bool modulus_wireless_espnow_scan_start(void)
{
    if (!s_espnow_on) {
        return false;
    }
    if (!espnow_radio_usable()) {
        taskENTER_CRITICAL(&s_en_mux);
        strncpy(s_scan_err, "WiFi stopped", sizeof(s_scan_err) - 1);
        s_scan_err[sizeof(s_scan_err) - 1] = '\0';
        s_scan_active = false;
        s_scan_done = true;
        taskEXIT_CRITICAL(&s_en_mux);
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

    taskENTER_CRITICAL(&s_en_mux);
    if (s_scan_active && !s_scan_done) {
        taskEXIT_CRITICAL(&s_en_mux);
        return true; /* already scanning */
    }
    s_scan_active = true;
    s_scan_done = false;
    s_scan_n = 0;
    s_scan_err[0] = '\0';
    /* Must outlast the full 13-channel sweep (13 x ESPNOW_SCAN_DWELL_MS). */
    s_scan_deadline = xTaskGetTickCount() + pdMS_TO_TICKS(ESPNOW_SCAN_WINDOW_MS);
    taskEXIT_CRITICAL(&s_en_mux);

    if (!modulus_wireless_radio_op_try_take(0)) {
        taskENTER_CRITICAL(&s_en_mux);
        strncpy(s_scan_err, "Radio busy", sizeof(s_scan_err) - 1);
        s_scan_err[sizeof(s_scan_err) - 1] = '\0';
        s_scan_active = false;
        s_scan_done = true;
        taskEXIT_CRITICAL(&s_en_mux);
        return false;
    }
    s_scan_radio_held = true;

    /* Off UI thread: ensure_inited / probe can block >1 s. */
    if (xTaskCreate(espnow_scan_worker, "en_scan", 4096, NULL, 5, NULL) != pdPASS) {
        taskENTER_CRITICAL(&s_en_mux);
        strncpy(s_scan_err, "Scan worker fail", sizeof(s_scan_err) - 1);
        s_scan_active = false;
        s_scan_done = true;
        taskEXIT_CRITICAL(&s_en_mux);
        espnow_scan_finish_radio();
        return false;
    }
    return true;
}

bool modulus_wireless_espnow_scan_done(void)
{
    taskENTER_CRITICAL(&s_en_mux);
    /* Idle (!active) counts as done for LVGL button state; while active,
     * only s_scan_done ends the window. Async start sets active before return
     * so a same-frame poll cannot false-complete. */
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
    /* A peer found mid-sweep lives off the configured channel — follow it, or the
     * saved MAC is unreachable. A STA link owns the PHY channel, so skip then. */
    if (peer.channel >= 1 && peer.channel <= 13 && !modulus_wireless_wifi_is_connected()) {
        if (modulus_wireless_espnow_channel() != peer.channel) {
            modulus_wireless_espnow_set_channel(peer.channel);
            s_applied_valid = false;
            s_bridge_ok = false;
            (void)modulus_espnow_stack_lock_channel(peer.channel);
            ESP_LOGI(TAG, "ESP-NOW channel follows discovered peer ch%u",
                     (unsigned)peer.channel);
        }
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
    /* Drop saved list + bridge MAC — otherwise en_mac re-seeds the list on
     * radio/transport restart (Remove/Clear looked temporary). */
    const int n = saved_count_raw();
    for (int i = 0; i < n; i++) {
        char key[8];
        saved_key(i, key, sizeof(key));
        modulus_nvs_set_str(key, "");
    }
    modulus_nvs_set_u8("en_pn", 0);
    (void)modulus_wireless_espnow_remove_bridge_peer();
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
    if (!espnow_radio_usable()) {
        modulus_wireless_espnow_on_wifi_stop();
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
    if (!espnow_radio_usable()) {
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
    if (!s_bridge_ok && espnow_bridge_mac_configured()) {
        (void)espnow_apply_bridge_peer();
    }
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
    if (!espnow_bridge_mac_configured()) {
        return false;
    }
    if (modulus_nvs_get_u8("espnow", 0) != 0) {
        return true;
    }
    return modulus_nvs_get_u8("cnc_conn", 4) == 0;
}

/* en_chan drifts (manual change, bridge reconfigured) and a saved peer only
 * answers on its own channel, so a failed probe means "wrong channel" at least
 * as often as it means "absent". Retry across the channels before declaring the
 * bridge dark. Returns the channel that answered. */
static bool espnow_ping_locate_peer(const uint8_t peer[6], uint8_t *found_ch)
{
    /* MOD_PROBE, not a private "MOD_PING": the S3 only special-cases PROBE /
     * HALT and forwards every other payload straight to grblHAL, so a bespoke
     * liveness word gets injected into the CNC serial stream as garbage. PROBE
     * also makes the bridge re-learn our MAC, which the S3->Tab5 path needs. */
    static const uint8_t k_probe[] = "MOD_PROBE";
    uint8_t sweep[MODULUS_ESPNOW_CHANNEL_MAX];
    int n = 1;
    sweep[0] = modulus_wireless_espnow_channel();
    if (!modulus_wireless_wifi_is_connected()) {
        n = espnow_channel_candidates(sweep, (int)sizeof(sweep));
        /* ponytail: 13-ch sweep when S3 is dark hammers SDIO → 0x107 / Core abort */
        if (n > 2) {
            n = 2;
        }
    }
    int dark_streak = 0;
    for (int i = 0; i < n; i++) {
        if (!modulus_c6_sdio_ready() || !modulus_wireless_transport_up()) {
            ESP_LOGW(TAG, "SDIO down — abort ESP-NOW channel locate");
            return false;
        }
        if (!espnow_add_peer_wait(peer, sweep[i], false, 600)) {
            continue;
        }
        if (modulus_espnow_stack_send_discovery(peer, k_probe, sizeof(k_probe) - 1)) {
            *found_ch = sweep[i];
            return true;
        }
        if (modulus_espnow_stack_last_send_fail_reason() == 0x01) {
            if (++dark_streak >= 2) {
                return false;
            }
        } else {
            dark_streak = 0;
        }
        vTaskDelay(pdMS_TO_TICKS(200));
    }
    return false;
}

static bool boot_reconnect_once(const char *phase)
{
    if (!boot_reconnect_wanted()) {
        modulus_espnow_debug_event("boot", "skip (%s): no saved peer/radio", phase);
        return true;
    }
    if (!espnow_radio_usable()) {
        modulus_espnow_debug_event("boot", "reconnect (%s): WiFi/SDIO down", phase);
        return false;
    }
    if (!modulus_wireless_espnow_is_enabled()) {
        if (!modulus_wireless_espnow_enable()) {
            modulus_espnow_debug_event("boot", "reconnect (%s): radio not ready", phase);
            return false;
        }
    }
    /* Radio + C6 ESP-NOW INIT only — peer add / transport open on user Connect. */
    modulus_espnow_debug_event("boot", "reconnect (%s): radio up, peer deferred", phase);
    return true;
}

/* Slow cadence — probe is enough; avoid thrashing reinit. */

static void deferred_boot_reconnect_task(void *arg)
{
    (void)arg;
    static const uint16_t k_delays_ms[] = {3000, 8000, 15000};
    for (int attempt = 0; attempt < (int)(sizeof(k_delays_ms) / sizeof(k_delays_ms[0]));
         attempt++) {
        vTaskDelay(pdMS_TO_TICKS(k_delays_ms[attempt]));
        modulus_espnow_debug_event("boot", "reconnect retry %d/%d", attempt + 1,
                                   (int)(sizeof(k_delays_ms) / sizeof(k_delays_ms[0])));
        if (boot_reconnect_once("retry")) {
            break;
        }
    }
    vTaskDelete(NULL);
}

static void schedule_bridge_reapply(void)
{
    /* Boot-time SDIO peer apply removed — transport_start / user Connect only. */
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
