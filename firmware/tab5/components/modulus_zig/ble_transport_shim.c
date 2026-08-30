/*
 * BLE NUS CNC transport + settings — NimBLE GATT client on P4 (VHCI to C6).
 */
#include "ble_host.h"
#include "transport_shim.h"
#include "wireless_shim.h"

#include "nvs_shim.h"

#include <esp_log.h>
#include <esp_random.h>
#include <freertos/FreeRTOS.h>
#include <freertos/portmacro.h>
#include <freertos/task.h>
#include <sdkconfig.h>
#include <stdio.h>
#include <string.h>

#if CONFIG_BT_NIMBLE_ENABLED
#include "host/ble_gap.h"
#include "host/ble_gatt.h"
#include "host/ble_hs.h"
#include "host/ble_sm.h"
#include "host/ble_store.h"
#include "host/ble_uuid.h"
#include "host/util/util.h"
#include "os/os_mbuf.h"
#endif

static const char *TAG = "ble_transport";

#define BLE_PK_NONE     0
#define BLE_PK_INPUT    1
#define BLE_PK_DISPLAY  2
#define BLE_PK_CONFIRM  3

#define BLE_SET_IDLE    0
#define BLE_SET_CONNECT 1
#define BLE_SET_CONN    2
#define BLE_SET_FAIL    3

static bool s_bt_on;
static bool s_suspended_for_espnow;
static bool s_open;
static bool s_nus_connected;
static bool s_scan_done = true;
static bool s_settings_scanning;
static int s_scan_n;
static char s_target[32] = "grblHAL";

#if CONFIG_BT_NIMBLE_ENABLED

typedef struct {
    char name[32];
    ble_addr_t addr;
    int8_t rssi;
    bool named; /* name came from an AD field, not the MAC fallback */
} ble_scan_entry_t;

static ble_scan_entry_t s_scan_entries[MODULUS_BLE_MAX_SCAN];
static portMUX_TYPE s_ble_mux = portMUX_INITIALIZER_UNLOCKED;

static const ble_uuid128_t s_nus_svc_uuid = BLE_UUID128_INIT(
    0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0,
    0x93, 0xf3, 0xa3, 0xb5, 0x01, 0x00, 0x40, 0x6e);
static const ble_uuid128_t s_nus_tx_uuid = BLE_UUID128_INIT(
    0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0,
    0x93, 0xf3, 0xa3, 0xb5, 0x02, 0x00, 0x40, 0x6e);
static const ble_uuid128_t s_nus_rx_uuid = BLE_UUID128_INIT(
    0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0,
    0x93, 0xf3, 0xa3, 0xb5, 0x03, 0x00, 0x40, 0x6e);

static uint16_t s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
static uint16_t s_tx_val_handle;
static uint16_t s_rx_val_handle;
static uint8_t s_settings_conn_state;
static uint8_t s_passkey_state;
static uint32_t s_passkey_value;
static uint16_t s_passkey_conn;
static char s_connected_name[32] = "";
static char s_bonded_name[32] = "";

static void ble_addr_to_str(const ble_addr_t *addr, char *buf, size_t len)
{
    if (!addr || !buf || len < 18) {
        return;
    }
    snprintf(buf, len, "%02X:%02X:%02X:%02X:%02X:%02X",
             addr->val[5], addr->val[4], addr->val[3],
             addr->val[2], addr->val[1], addr->val[0]);
}

static void ble_scan_sort_by_rssi(void)
{
    for (int i = 0; i < s_scan_n - 1; i++) {
        for (int j = i + 1; j < s_scan_n; j++) {
            if (s_scan_entries[j].rssi > s_scan_entries[i].rssi) {
                const ble_scan_entry_t tmp = s_scan_entries[i];
                s_scan_entries[i] = s_scan_entries[j];
                s_scan_entries[j] = tmp;
            }
        }
    }
}

static int ble_scan_find_addr(const ble_addr_t *addr)
{
    for (int i = 0; i < s_scan_n; i++) {
        if (memcmp(&s_scan_entries[i].addr, addr, sizeof(*addr)) == 0) {
            return i;
        }
    }
    return -1;
}

static void ble_scan_add(const ble_addr_t *addr, const char *name, int8_t rssi)
{
    if (!addr || s_scan_n >= MODULUS_BLE_MAX_SCAN) {
        return;
    }
    const int existing = ble_scan_find_addr(addr);
    if (existing >= 0) {
        ble_scan_entry_t *e = &s_scan_entries[existing];
        if (rssi > e->rssi) {
            e->rssi = rssi;
        }
        /* Most peripherals carry the name only in the SCAN_RSP, which arrives as
         * a second report for the same MAC — backfill it over the MAC fallback. */
        if (!e->named && name && name[0]) {
            strncpy(e->name, name, sizeof(e->name) - 1);
            e->name[sizeof(e->name) - 1] = '\0';
            e->named = true;
        }
        return;
    }
    ble_scan_entry_t *e = &s_scan_entries[s_scan_n];
    memset(e, 0, sizeof(*e));
    e->addr = *addr;
    e->rssi = rssi;
    if (name && name[0]) {
        strncpy(e->name, name, sizeof(e->name) - 1);
        e->named = true;
    } else {
        ble_addr_to_str(addr, e->name, sizeof(e->name));
    }
    s_scan_n++;
}

static void ble_save_bonded_peer(const char *name, const ble_addr_t *addr)
{
    if (name && name[0]) {
        strncpy(s_bonded_name, name, sizeof(s_bonded_name) - 1);
        modulus_nvs_set_str("ble_name", s_bonded_name);
    }
    /* N1: the bonded-peer MAC was written to NVS ("ble_mac") but never read
     * back anywhere — a dead write, removed. Only the bonded name is
     * persisted/restored. addr stays in the signature for callers. */
    (void)addr;
}

static void ble_load_bonded_peer(void)
{
    char nm[32] = {};
    if (modulus_nvs_get_str("ble_name", nm, sizeof(nm)) && nm[0]) {
        strncpy(s_bonded_name, nm, sizeof(s_bonded_name) - 1);
    } else {
        s_bonded_name[0] = '\0';
    }
}

static int ble_on_svc_disc(uint16_t conn_handle, const struct ble_gatt_error *error,
                           const struct ble_gatt_svc *svc, void *arg);

static void ble_start_nus_discovery(uint16_t conn_handle)
{
    s_tx_val_handle = 0;
    s_rx_val_handle = 0;
    ble_gattc_disc_svc_by_uuid(conn_handle, &s_nus_svc_uuid.u, ble_on_svc_disc, NULL);
}

static int ble_on_subscribe(uint16_t conn_handle, const struct ble_gatt_error *error,
                            struct ble_gatt_attr *attr, void *arg)
{
    (void)conn_handle;
    (void)attr;
    (void)arg;
    if (!error) {
        return 0;
    }
    if (error->status == 0) {
        s_nus_connected = true;
        modulus_zig_transport_on_connect();
        ESP_LOGI(TAG, "NUS subscribed — transport up");
    }
    return 0;
}

static int ble_on_chr_disc(uint16_t conn_handle, const struct ble_gatt_error *error,
                           const struct ble_gatt_chr *chr, void *arg)
{
    (void)arg;
    if (!error) {
        return 0;
    }
    if (error->status == BLE_HS_EDONE) {
        if (s_rx_val_handle) {
            uint8_t val[2] = {1, 0};
            ble_gattc_write_flat(conn_handle, s_rx_val_handle + 1, val, sizeof(val),
                                 ble_on_subscribe, NULL);
        }
        return 0;
    }
    if (error->status != 0) {
        return 0;
    }
    if (ble_uuid_cmp(&chr->uuid.u, &s_nus_tx_uuid.u) == 0) {
        s_tx_val_handle = chr->val_handle;
    }
    if (ble_uuid_cmp(&chr->uuid.u, &s_nus_rx_uuid.u) == 0) {
        s_rx_val_handle = chr->val_handle;
    }
    return 0;
}

static int ble_on_svc_disc(uint16_t conn_handle, const struct ble_gatt_error *error,
                           const struct ble_gatt_svc *svc, void *arg)
{
    (void)arg;
    if (!error) {
        return 0;
    }
    if (error->status == BLE_HS_EDONE) {
        return 0;
    }
    if (error->status != 0) {
        return 0;
    }
    ble_gattc_disc_all_chrs(conn_handle, svc->start_handle, svc->end_handle,
                            ble_on_chr_disc, NULL);
    return 0;
}

static void ble_passkey_clear(void)
{
    taskENTER_CRITICAL(&s_ble_mux);
    s_passkey_state = BLE_PK_NONE;
    s_passkey_value = 0;
    s_passkey_conn = BLE_HS_CONN_HANDLE_NONE;
    taskEXIT_CRITICAL(&s_ble_mux);
}

static void ble_passkey_set(uint8_t state, uint32_t value, uint16_t conn)
{
    taskENTER_CRITICAL(&s_ble_mux);
    s_passkey_state = state;
    s_passkey_value = value;
    s_passkey_conn = conn;
    taskEXIT_CRITICAL(&s_ble_mux);
}

static void ble_on_gap_connected(uint16_t conn_handle, const ble_addr_t *peer_addr)
{
    s_conn_handle = conn_handle;
    s_settings_conn_state = BLE_SET_CONN;
    if (peer_addr) {
        /* Name may already be in scan list. */
        const int idx = ble_scan_find_addr(peer_addr);
        if (idx >= 0) {
            strncpy(s_connected_name, s_scan_entries[idx].name, sizeof(s_connected_name) - 1);
        } else {
            char mac[20];
            ble_addr_to_str(peer_addr, mac, sizeof(mac));
            strncpy(s_connected_name, mac, sizeof(s_connected_name) - 1);
        }
        ble_save_bonded_peer(s_connected_name, peer_addr);
    }
    if (ble_gap_security_initiate(conn_handle) != 0) {
        ESP_LOGW(TAG, "security_initiate failed");
    }
    if (s_open) {
        ble_start_nus_discovery(conn_handle);
    }
}

static int ble_gap_event(struct ble_gap_event *event, void *arg)
{
    (void)arg;
    switch (event->type) {
    case BLE_GAP_EVENT_DISC: {
        char name[32] = {};
        struct ble_hs_adv_fields fields;
        if (ble_hs_adv_parse_fields(&fields, event->disc.data, event->disc.length_data) == 0 &&
            fields.name && fields.name_len > 0) {
            const int n = fields.name_len < 31 ? (int)fields.name_len : 31;
            memcpy(name, fields.name, (size_t)n);
            name[n] = '\0';
        }
        /* Always add — nameless ADs use MAC (old parse-fail path dropped all). */
        if (s_settings_scanning) {
            ble_scan_add(&event->disc.addr, name[0] ? name : NULL, event->disc.rssi);
        }
        if (s_open && !s_settings_scanning && name[0] && s_target[0]) {
            if (strcmp(name, s_target) == 0) {
                uint8_t own = 0;
                (void)ble_hs_id_infer_auto(0, &own);
                (void)ble_gap_disc_cancel();
                s_settings_conn_state = BLE_SET_CONNECT;
                (void)ble_gap_connect(own, &event->disc.addr, 30000, NULL, ble_gap_event, NULL);
            }
        }
        break;
    }
    case BLE_GAP_EVENT_DISC_COMPLETE:
        if (s_settings_scanning) {
            s_settings_scanning = false;
            ble_scan_sort_by_rssi();
            s_scan_done = true;
        }
        break;
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status == 0) {
            struct ble_gap_conn_desc desc;
            if (ble_gap_conn_find(event->connect.conn_handle, &desc) == 0) {
                ble_on_gap_connected(event->connect.conn_handle, &desc.peer_id_addr);
            } else {
                ble_on_gap_connected(event->connect.conn_handle, NULL);
            }
        } else {
            ESP_LOGE(TAG, "connect failed status=%d", event->connect.status);
            s_settings_conn_state = BLE_SET_FAIL;
            s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
        }
        break;
    case BLE_GAP_EVENT_DISCONNECT:
        s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
        s_tx_val_handle = 0;
        s_rx_val_handle = 0;
        s_settings_conn_state = BLE_SET_IDLE;
        s_connected_name[0] = '\0';
        ble_passkey_clear();
        if (s_nus_connected) {
            s_nus_connected = false;
            modulus_zig_transport_on_disconnect();
        }
        break;
    case BLE_GAP_EVENT_ENC_CHANGE:
        if (event->enc_change.status == 0) {
            ESP_LOGI(TAG, "pairing complete (encrypted)");
        } else {
            ESP_LOGW(TAG, "encryption failed status=%d", event->enc_change.status);
            s_settings_conn_state = BLE_SET_FAIL;
        }
        break;
    case BLE_GAP_EVENT_PASSKEY_ACTION: {
        const uint8_t action = event->passkey.params.action;
        if (action == BLE_SM_IOACT_INPUT) {
            ble_passkey_set(BLE_PK_INPUT, 0, event->passkey.conn_handle);
        } else if (action == BLE_SM_IOACT_NUMCMP) {
            ble_passkey_set(BLE_PK_CONFIRM, event->passkey.params.numcmp,
                            event->passkey.conn_handle);
        } else if (action == BLE_SM_IOACT_DISP) {
            const uint32_t pk = (uint32_t)(esp_random() % 1000000U);
            ble_passkey_set(BLE_PK_DISPLAY, pk, event->passkey.conn_handle);
        } else {
            struct ble_sm_io pkey = {};
            pkey.action = action;
            pkey.numcmp_accept = 1;
            (void)ble_sm_inject_io(event->passkey.conn_handle, &pkey);
        }
        break;
    }
    case BLE_GAP_EVENT_NOTIFY_RX: {
        struct os_mbuf *om = event->notify_rx.om;
        uint16_t len = OS_MBUF_PKTLEN(om);
        if (len > 0 && len < 512) {
            uint8_t buf[512];
            os_mbuf_copydata(om, 0, len, buf);
            modulus_zig_serial_rx(buf, len);
        }
        break;
    }
    default:
        break;
    }
    return 0;
}

static void ble_transport_task(void *arg)
{
    (void)arg;
    while (!ble_hs_synced()) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    if (!s_target[0]) {
        vTaskDelete(NULL);
        return;
    }
    uint8_t own = 0;
    if (ble_hs_id_infer_auto(0, &own) != 0) {
        ESP_LOGW(TAG, "infer own addr failed — skip NUS disc");
        vTaskDelete(NULL);
        return;
    }
    struct ble_gap_disc_params dp = {};
    dp.passive = 0;
    dp.filter_duplicates = 1;
    (void)ble_gap_disc(own, BLE_HS_FOREVER, &dp, ble_gap_event, NULL);
    vTaskDelete(NULL);
}

static void ble_start_nus_connect(void)
{
    if (!modulus_ble_host_ready() || !s_target[0]) {
        return;
    }
    if (s_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
        if (s_open) {
            ble_start_nus_discovery(s_conn_handle);
        }
        return;
    }
    xTaskCreate(ble_transport_task, "ble_nus", 4096, NULL, 5, NULL);
}

static void ble_cancel_active_scan(void)
{
    if (s_settings_scanning) {
        (void)ble_gap_disc_cancel();
        s_settings_scanning = false;
        s_scan_done = true;
    }
}

#endif /* CONFIG_BT_NIMBLE_ENABLED */

bool modulus_ble_settings_enable(void)
{
#if CONFIG_BT_NIMBLE_ENABLED
    ble_load_bonded_peer();
    if (!modulus_ble_host_ensure()) {
        ESP_LOGW(TAG, "BLE host init failed");
        return false;
    }
#endif
    s_bt_on = true;
    modulus_nvs_set_u8("bt", 1);
#if CONFIG_BT_NIMBLE_ENABLED
    ESP_LOGI(TAG, "BLE radio on (NimBLE VHCI)");
#else
    ESP_LOGW(TAG, "BLE disabled (CONFIG_BT_NIMBLE_ENABLED=n)");
#endif
    return true;
}

void modulus_ble_settings_disable(void)
{
    s_bt_on = false;
    s_scan_done = true;
    s_scan_n = 0;
    s_suspended_for_espnow = false;
    modulus_nvs_set_u8("bt", 0);
    modulus_ble_settings_disconnect();
    modulus_ble_transport_stop();
    ESP_LOGI(TAG, "BLE radio off");
}

void modulus_ble_suspend_for_espnow(void)
{
    if (s_suspended_for_espnow || !s_bt_on) {
        return;
    }
    s_suspended_for_espnow = true;
    modulus_ble_settings_scan_stop();
    modulus_ble_settings_disconnect();
    modulus_ble_transport_stop();
    ESP_LOGI(TAG, "BLE suspended for ESP-NOW CNC");
}

void modulus_ble_resume_after_espnow(void)
{
    if (!s_suspended_for_espnow) {
        return;
    }
    s_suspended_for_espnow = false;
    if (modulus_nvs_get_u8("bt", 0) == 0) {
        return;
    }
    /* Async worker — never ble_host_ensure() on SDIO poll / transport_stop thread. */
    if (!modulus_wireless_ble_enable()) {
        ESP_LOGW(TAG, "BLE resume after ESP-NOW deferred");
    }
}

bool modulus_ble_settings_is_enabled(void) { return s_bt_on; }

bool modulus_ble_settings_is_connecting(void)
{
#if CONFIG_BT_NIMBLE_ENABLED
    return s_settings_conn_state == BLE_SET_CONNECT;
#else
    return false;
#endif
}

bool modulus_ble_settings_is_connected(void)
{
#if CONFIG_BT_NIMBLE_ENABLED
    return s_settings_conn_state == BLE_SET_CONN && s_conn_handle != BLE_HS_CONN_HANDLE_NONE;
#else
    return false;
#endif
}

uint8_t modulus_ble_settings_passkey_state(void)
{
#if CONFIG_BT_NIMBLE_ENABLED
    taskENTER_CRITICAL(&s_ble_mux);
    const uint8_t st = s_passkey_state;
    taskEXIT_CRITICAL(&s_ble_mux);
    return st;
#else
    return BLE_PK_NONE;
#endif
}

uint32_t modulus_ble_settings_passkey_value(void)
{
#if CONFIG_BT_NIMBLE_ENABLED
    taskENTER_CRITICAL(&s_ble_mux);
    const uint32_t v = s_passkey_value;
    taskEXIT_CRITICAL(&s_ble_mux);
    return v;
#else
    return 0;
#endif
}

const char *modulus_ble_settings_status_text(void)
{
    static char buf[48];
    if (!s_bt_on) {
        return "Off";
    }
#if CONFIG_BT_NIMBLE_ENABLED
    if (s_nus_connected) {
        return "NUS connected";
    }
    if (s_settings_conn_state == BLE_SET_CONNECT) {
        return "Connecting...";
    }
    if (s_settings_conn_state == BLE_SET_FAIL) {
        return "Connect failed";
    }
    if (s_settings_conn_state == BLE_SET_CONN && s_connected_name[0]) {
        snprintf(buf, sizeof(buf), "Connected: %.20s", s_connected_name);
        return buf;
    }
    if (modulus_ble_host_ready()) {
        return "Ready";
    }
    /* Never leave UI on Starting after HCI/SDIO death. */
    if (modulus_ble_host_failed() || !modulus_wireless_transport_up()) {
        return "C6 offline";
    }
    return "Starting";
#else
    return "NimBLE disabled";
#endif
}

static const char *ble_paired_text_from_nvs(void)
{
    static char buf[40];
    char nm[32] = {};
    if (modulus_nvs_get_str("ble_name", nm, sizeof(nm)) && nm[0]) {
        snprintf(buf, sizeof(buf), "1: %.24s", nm);
        return buf;
    }
    return "0 paired";
}

const char *modulus_ble_settings_paired_text(void)
{
    static char buf[40];
#if CONFIG_BT_NIMBLE_ENABLED
    if (!modulus_ble_host_ready()) {
        if (!s_bonded_name[0]) {
            ble_load_bonded_peer();
        }
        if (s_bonded_name[0]) {
            snprintf(buf, sizeof(buf), "1: %.24s", s_bonded_name);
            return buf;
        }
        return ble_paired_text_from_nvs();
    }
    ble_addr_t peers[4];
    int peer_n = 0;
    if (ble_store_util_bonded_peers(peers, &peer_n, 4) == 0 && peer_n > 0) {
        if (s_bonded_name[0]) {
            snprintf(buf, sizeof(buf), "%d: %.22s", peer_n, s_bonded_name);
        } else {
            snprintf(buf, sizeof(buf), "%d bonded", peer_n);
        }
        return buf;
    }
    if (s_bonded_name[0]) {
        snprintf(buf, sizeof(buf), "1: %.24s", s_bonded_name);
        return buf;
    }
#endif
    return "0 paired";
}

#if CONFIG_BT_NIMBLE_ENABLED
static volatile bool s_scan_busy;

static void ble_scan_worker(void *arg)
{
    (void)arg;
    bool started = false;

    /* Wait for radio on + NimBLE sync (enable may still be finishing). */
    for (int i = 0; i < 200; i++) {
        if (s_bt_on && modulus_ble_host_ready()) {
            break;
        }
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    if (!s_bt_on || !modulus_ble_host_ready()) {
        ESP_LOGW(TAG, "BLE scan: host not ready");
        goto done;
    }
    if (s_settings_conn_state == BLE_SET_CONNECT ||
        s_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
        ESP_LOGW(TAG, "BLE scan blocked: connecting/connected");
        goto done;
    }
    if (s_settings_scanning) {
        ble_cancel_active_scan();
        vTaskDelay(pdMS_TO_TICKS(50));
    }

    uint8_t own = 0;
    if (ble_hs_id_infer_auto(0, &own) != 0) {
        ESP_LOGE(TAG, "BLE scan: infer own addr failed");
        goto done;
    }

    s_scan_n = 0;
    s_settings_scanning = true;
    struct ble_gap_disc_params dp = {};
    dp.passive = 0;
    /* Duplicate filtering also drops the SCAN_RSP that carries the device name,
     * leaving the list showing bare MACs. 10 s bounded, so the extra reports
     * are affordable. */
    dp.filter_duplicates = 0;
    /* Duration in ms (ESP-IDF NimBLE). PUBLIC own-addr often fails on RPA-only. */
    int rc = ble_gap_disc(own, 10000, &dp, ble_gap_event, NULL);
    if (rc != 0) {
        ESP_LOGW(TAG, "ble_gap_disc rc=%d — retry random", rc);
        own = BLE_OWN_ADDR_RANDOM;
        rc = ble_gap_disc(own, 10000, &dp, ble_gap_event, NULL);
    }
    if (rc != 0) {
        ESP_LOGE(TAG, "ble_gap_disc failed rc=%d", rc);
        s_settings_scanning = false;
        goto done;
    }
    started = true;
    ESP_LOGI(TAG, "BLE discovery started (10s)");

done:
    if (!started) {
        s_settings_scanning = false;
        s_scan_done = true;
    }
    s_scan_busy = false;
    vTaskDelete(NULL);
}
#endif

bool modulus_ble_settings_scan_start(void)
{
#if CONFIG_BT_NIMBLE_ENABLED
    if (s_scan_busy || s_settings_scanning) {
        return true;
    }
    if (s_settings_conn_state == BLE_SET_CONNECT) {
        return false;
    }
    if (s_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
        ESP_LOGW(TAG, "scan blocked: already connected");
        return false;
    }
    s_scan_done = false;
    s_scan_n = 0;
    s_scan_busy = true;
    /* Off UI thread: host ensure / sync wait can take many seconds. */
    if (xTaskCreatePinnedToCore(ble_scan_worker, "ble_scan", 4096, NULL, 5, NULL, 0) !=
        pdPASS) {
        s_scan_busy = false;
        s_scan_done = true;
        return false;
    }
    return true;
#else
    s_scan_done = true;
    return false;
#endif
}

void modulus_ble_settings_scan_stop(void)
{
#if CONFIG_BT_NIMBLE_ENABLED
    ble_cancel_active_scan();
#else
    s_scan_done = true;
#endif
}

bool modulus_ble_settings_scan_done(void) { return s_scan_done; }
int modulus_ble_settings_scan_count(void) { return s_scan_done ? s_scan_n : 0; }

bool modulus_ble_settings_scan_get(int idx, char *name, size_t name_len, int8_t *rssi_out,
                                   char *addr_out, size_t addr_len)
{
#if CONFIG_BT_NIMBLE_ENABLED
    if (idx < 0 || idx >= s_scan_n || !name || name_len == 0) {
        return false;
    }
    strncpy(name, s_scan_entries[idx].name, name_len - 1);
    name[name_len - 1] = '\0';
    if (rssi_out) {
        *rssi_out = s_scan_entries[idx].rssi;
    }
    if (addr_out && addr_len > 0) {
        ble_addr_to_str(&s_scan_entries[idx].addr, addr_out, addr_len);
    }
    return true;
#else
    (void)idx;
    (void)name;
    (void)name_len;
    (void)rssi_out;
    (void)addr_out;
    (void)addr_len;
    return false;
#endif
}

bool modulus_ble_settings_connect(int idx)
{
#if CONFIG_BT_NIMBLE_ENABLED
    if (!s_bt_on || idx < 0 || idx >= s_scan_n) {
        return false;
    }
    if (!modulus_ble_host_ensure()) {
        return false;
    }
    if (s_settings_conn_state == BLE_SET_CONNECT || s_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
        return false;
    }
    ble_cancel_active_scan();
    s_settings_conn_state = BLE_SET_CONNECT;
    const ble_addr_t *addr = &s_scan_entries[idx].addr;
    strncpy(s_connected_name, s_scan_entries[idx].name, sizeof(s_connected_name) - 1);
    ESP_LOGI(TAG, "connecting to %s", s_connected_name);
    uint8_t own = 0;
    if (ble_hs_id_infer_auto(0, &own) != 0) {
        own = BLE_OWN_ADDR_PUBLIC;
    }
    if (ble_gap_connect(own, addr, 30000, NULL, ble_gap_event, NULL) != 0) {
        s_settings_conn_state = BLE_SET_FAIL;
        return false;
    }
    return true;
#else
    (void)idx;
    return false;
#endif
}

void modulus_ble_settings_disconnect(void)
{
#if CONFIG_BT_NIMBLE_ENABLED
    ble_cancel_active_scan();
    ble_passkey_clear();
    if (s_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
        (void)ble_gap_terminate(s_conn_handle, BLE_ERR_REM_USER_CONN_TERM);
        s_conn_handle = BLE_HS_CONN_HANDLE_NONE;
    }
#endif
    s_nus_connected = false;
    s_settings_conn_state = BLE_SET_IDLE;
    s_connected_name[0] = '\0';
}

bool modulus_ble_settings_passkey_submit(uint32_t passkey)
{
#if CONFIG_BT_NIMBLE_ENABLED
    taskENTER_CRITICAL(&s_ble_mux);
    const uint8_t st = s_passkey_state;
    const uint16_t conn = s_passkey_conn;
    taskEXIT_CRITICAL(&s_ble_mux);
    if (st != BLE_PK_INPUT || conn == BLE_HS_CONN_HANDLE_NONE) {
        return false;
    }
    struct ble_sm_io pkey = {};
    pkey.action = BLE_SM_IOACT_INPUT;
    pkey.passkey = passkey;
    if (ble_sm_inject_io(conn, &pkey) != 0) {
        return false;
    }
    ble_passkey_clear();
    return true;
#else
    (void)passkey;
    return false;
#endif
}

bool modulus_ble_settings_passkey_confirm(void)
{
#if CONFIG_BT_NIMBLE_ENABLED
    taskENTER_CRITICAL(&s_ble_mux);
    const uint8_t st = s_passkey_state;
    const uint16_t conn = s_passkey_conn;
    const uint32_t numcmp = s_passkey_value;
    taskEXIT_CRITICAL(&s_ble_mux);
    if ((st != BLE_PK_CONFIRM && st != BLE_PK_DISPLAY) || conn == BLE_HS_CONN_HANDLE_NONE) {
        return false;
    }
    struct ble_sm_io pkey = {};
    if (st == BLE_PK_CONFIRM) {
        pkey.action = BLE_SM_IOACT_NUMCMP;
        pkey.numcmp_accept = 1;
        pkey.passkey = numcmp;
    } else {
        pkey.action = BLE_SM_IOACT_DISP;
        pkey.passkey = numcmp;
    }
    if (ble_sm_inject_io(conn, &pkey) != 0) {
        return false;
    }
    ble_passkey_clear();
    return true;
#else
    return false;
#endif
}

void modulus_ble_settings_passkey_cancel(void)
{
#if CONFIG_BT_NIMBLE_ENABLED
    taskENTER_CRITICAL(&s_ble_mux);
    const uint16_t conn = s_passkey_conn;
    taskEXIT_CRITICAL(&s_ble_mux);
    ble_passkey_clear();
    if (conn != BLE_HS_CONN_HANDLE_NONE) {
        (void)ble_gap_terminate(conn, BLE_ERR_REM_USER_CONN_TERM);
    }
#endif
}

void modulus_ble_settings_clear_paired(void)
{
    modulus_ble_settings_disconnect();
#if CONFIG_BT_NIMBLE_ENABLED
    if (modulus_ble_host_ready()) {
        (void)ble_store_clear();
    }
#endif
    s_bonded_name[0] = '\0';
    modulus_nvs_set_str("ble_name", "");
    ESP_LOGI(TAG, "bonds cleared");
}

bool modulus_ble_transport_start(const char *target_name)
{
    if (!s_bt_on && !modulus_ble_settings_enable()) {
        return false;
    }
    if (target_name && target_name[0]) {
        strncpy(s_target, target_name, sizeof(s_target) - 1);
        modulus_nvs_set_str("ble_name", s_target);
    } else {
        char nm[32] = {};
        if (modulus_nvs_get_str("ble_name", nm, sizeof(nm)) && nm[0]) {
            strncpy(s_target, nm, sizeof(s_target) - 1);
        }
    }
    s_open = true;
#if CONFIG_BT_NIMBLE_ENABLED
    ble_start_nus_connect();
    ESP_LOGI(TAG, "BLE NUS transport target '%s'", s_target);
    return true;
#else
    ESP_LOGW(TAG, "BLE NUS unavailable (NimBLE off)");
    return false;
#endif
}

void modulus_ble_transport_stop(void)
{
    if (!s_open) {
        return;
    }
    s_open = false;
    if (s_nus_connected) {
        s_nus_connected = false;
        modulus_zig_transport_on_disconnect();
    }
    modulus_ble_settings_disconnect();
}

bool modulus_ble_transport_send(const uint8_t *data, size_t len)
{
#if CONFIG_BT_NIMBLE_ENABLED
    if (!s_open || !s_nus_connected || s_conn_handle == BLE_HS_CONN_HANDLE_NONE || !data || !len) {
        return false;
    }
    if (s_tx_val_handle == 0) {
        return false;
    }
    return ble_gattc_write_no_rsp_flat(s_conn_handle, s_tx_val_handle, data, len) == 0;
#else
    (void)data;
    (void)len;
    return false;
#endif
}

bool modulus_ble_transport_is_connected(void)
{
    return s_nus_connected;
}
