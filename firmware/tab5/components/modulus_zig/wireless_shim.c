/*
 * Tab5 wireless shim — esp_hosted SDIO + esp_wifi_remote on P4 (C6 slave radio).
 */
#include "wireless_shim.h"
#include "ble_host.h"
#include "espnow_debug.h"
#include "transport_shim.h"
#include "wireless_rpc.h"
#include "wireless_shim_802154.h"

#include "bsp/m5stack_tab5.h"
#include "c6_sdio_host.h"
#include "tab5_pi4ioe.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/portmacro.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "lwip/ip4_addr.h"
#include "nvs_shim.h"
#include "rtc_shim.h"
#include "esp_hosted_host_fw_ver.h"
#include "esp_timer.h"
#include "sdkconfig.h"
#include "tab5_hw.h"
#include "transport_drv.h"
#include "zb_automation.h"

#include <stdio.h>
#include <string.h>

static const char *TAG = "wireless_shim";
static bool s_ready = false;
static bool s_wifi_stack_started = false;
static bool s_wifi_sta_running = false;
static bool s_transport_up = false;
static bool s_ext_antenna = false;
static esp_netif_t *s_sta_netif = NULL;
/* Taken by the task that starts a radio op and released by the worker or the
 * 1 Hz poll that finishes it. A FreeRTOS mutex records an owner and asserts in
 * xTaskPriorityDisinherit when given by any other task, so this hand-off token
 * must be an ownerless binary semaphore. */
static SemaphoreHandle_t s_radio_op_sem;
static SemaphoreHandle_t s_host_init_mux;

static void host_init_mux_init(void)
{
    if (!s_host_init_mux) {
        s_host_init_mux = xSemaphoreCreateMutex();
    }
}

static bool wireless_ensure_sta_netif(void)
{
    if (s_sta_netif) {
        return true;
    }
    esp_netif_t *existing = esp_netif_get_handle_from_ifkey("WIFI_STA_DEF");
    if (existing) {
        ESP_LOGW(TAG, "Adopt STA netif from registry (partial init recovery)");
        s_sta_netif = existing;
        return true;
    }
    s_sta_netif = esp_netif_create_default_wifi_sta();
    if (!s_sta_netif) {
        ESP_LOGE(TAG, "esp_netif_create_default_wifi_sta failed");
        return false;
    }
    return true;
}

static void radio_op_init(void)
{
    if (!s_radio_op_sem) {
        s_radio_op_sem = xSemaphoreCreateBinary();
        if (s_radio_op_sem) {
            xSemaphoreGive(s_radio_op_sem); /* created empty — start available */
        }
    }
}

bool modulus_wireless_radio_op_try_take(uint32_t timeout_ms)
{
    radio_op_init();
    if (!s_radio_op_sem) {
        return false;
    }
    return xSemaphoreTake(s_radio_op_sem, pdMS_TO_TICKS(timeout_ms)) == pdTRUE;
}

void modulus_wireless_radio_op_give(void)
{
    if (s_radio_op_sem) {
        /* Already-available give returns pdFALSE — harmless, keeps the double
         * release paths (collect_results + worker tail) from corrupting state. */
        (void)xSemaphoreGive(s_radio_op_sem);
    }
}

#define WIFI_MAX_SCAN    MODULUS_WIFI_MAX_SCAN

static portMUX_TYPE s_wifi_mux = portMUX_INITIALIZER_UNLOCKED;
static bool s_wifi_enabled = false;
static bool s_wifi_connected = false;
static bool s_wifi_connecting = false;
static bool s_user_disconnect = false;
static int s_wifi_disc_reason = 0;
static bool s_scan_done = false;
static int s_scan_n = 0;
static volatile bool s_scan_busy;
static volatile bool s_scan_ev_ready;
static wifi_event_sta_scan_done_t s_scan_done_ev;
static modulus_wifi_ap_t s_scan_buf[WIFI_MAX_SCAN];
static char s_wifi_ssid[33] = "";
static char s_wifi_ip[16] = "";
static bool s_zb_on = false;
static volatile bool s_zb_join_pending = false;
static int64_t s_zb_join_deadline_us = 0;
static volatile bool s_wifi_enable_busy = false;
static volatile bool s_ble_enable_busy = false;
static volatile bool s_ble_enable_fail = false;
static bool s_th_on = false;
static bool s_event_handlers_registered = false;

#define C6_WIFI_RPC_SETTLE_MS 1500
#define C6_WIFI_SOFT_RETRIES  4

static bool wireless_host_init(bool aggressive);
static bool wireless_transport_ready(void);
static void wireless_zigbee_stop_hub(void);
static void wifi_event_handler(void *arg, esp_event_base_t base, int32_t event_id, void *event_data);
static bool wireless_wait_wifi_stack(uint32_t timeout_ms);
static void wifi_scan_collect_results(const wifi_event_sta_scan_done_t *ev);
static void wifi_scan_results_worker(void *arg);

static void wireless_invalidate_transport(void)
{
    if (!s_transport_up && !s_wifi_stack_started) {
        return;
    }
    ESP_LOGW(TAG, "SDIO transport lost — clearing Wi-Fi stack state");
    s_transport_up = false;
    s_wifi_stack_started = false;
    s_wifi_sta_running = false;
    modulus_c6_sdio_quiesce(15000);
}

static void wireless_refresh_transport_state(void)
{
    if ((s_transport_up || s_wifi_stack_started) && !wireless_transport_ready()) {
        wireless_invalidate_transport();
    }
}

/** Drop host bookkeeping only — no SDIO RPC (link wedged or before WLAN_PWR). */
static void wireless_abandon_host_stack(void)
{
    if (s_event_handlers_registered) {
        esp_event_handler_unregister(WIFI_EVENT, ESP_EVENT_ANY_ID, wifi_event_handler);
        esp_event_handler_unregister(IP_EVENT, IP_EVENT_STA_GOT_IP, wifi_event_handler);
        s_event_handlers_registered = false;
    }

    if (s_sta_netif) {
        esp_netif_destroy(s_sta_netif);
        s_sta_netif = NULL;
    }

    taskENTER_CRITICAL(&s_wifi_mux);
    s_wifi_enabled = false;
    s_wifi_connected = false;
    s_wifi_connecting = false;
    s_wifi_ip[0] = '\0';
    s_wifi_stack_started = false;
    s_wifi_sta_running = false;
    s_transport_up = false;
    taskEXIT_CRITICAL(&s_wifi_mux);

    s_zb_on = false;
    s_th_on = false;
    s_ready = false;
}

/** Tear down partial or full host stack (safe when !s_ready). */
static void wireless_teardown_host_stack(bool quiesce_radios)
{
    if (quiesce_radios && s_ready && wireless_transport_ready()) {
        modulus_wireless_prepare_for_sleep();
    } else if (quiesce_radios && s_ready) {
        ESP_LOGW(TAG, "Skip radio quiesce — SDIO transport down");
    }

    if (s_event_handlers_registered) {
        esp_event_handler_unregister(WIFI_EVENT, ESP_EVENT_ANY_ID, wifi_event_handler);
        esp_event_handler_unregister(IP_EVENT, IP_EVENT_STA_GOT_IP, wifi_event_handler);
        s_event_handlers_registered = false;
    }

    if (wireless_transport_ready()) {
        esp_err_t err = esp_wifi_deinit();
        if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
            ESP_LOGW(TAG, "esp_wifi_deinit: %s", esp_err_to_name(err));
        }
        vTaskDelay(pdMS_TO_TICKS(300));
    } else {
        ESP_LOGW(TAG, "Skip esp_wifi_deinit — SDIO transport down");
    }

    if (s_sta_netif) {
        esp_netif_destroy(s_sta_netif);
        s_sta_netif = NULL;
    }

    taskENTER_CRITICAL(&s_wifi_mux);
    s_wifi_enabled = false;
    s_wifi_connected = false;
    s_wifi_connecting = false;
    s_wifi_ip[0] = '\0';
    s_wifi_stack_started = false;
    s_wifi_sta_running = false;
    s_transport_up = false;
    taskEXIT_CRITICAL(&s_wifi_mux);

    s_zb_on = false;
    s_th_on = false;
    s_ready = false;
}

static bool tab5_c6_keep_rail_on_boot(void)
{
    switch (esp_reset_reason()) {
    case ESP_RST_POWERON:
    case ESP_RST_EXT:
    case ESP_RST_DEEPSLEEP:
    /* USB-serial monitor open resets P4 only — C6 SDIO slave keeps running. */
    case ESP_RST_USB:
    case ESP_RST_JTAG:
        return true;
    default:
        return false;
    }
}

static bool wireless_try_esp_wifi_init(const wifi_init_config_t *cfg)
{
    (void)tab5_pi4ioe_ensure_wlan_pwr_on();
    /* esp_wifi_init always GPIO15-resets C6 — pre-wait on a stale WLAN_PWR anchor
     * is misleading; only settle if transport is already up from a prior session. */
    if (wireless_transport_ready()) {
        tab5_pi4ioe_wait_c6_sdio_ready();
        vTaskDelay(pdMS_TO_TICKS(C6_WIFI_RPC_SETTLE_MS));
    }
    esp_err_t err = esp_wifi_init(cfg);
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        ESP_LOGW(TAG, "esp_wifi_init: %s", esp_err_to_name(err));
        wireless_invalidate_transport();
        return false;
    }
    /* esp_hosted GPIO15 reset inside esp_wifi_init reboots C6 — the WLAN_PWR
     * anchor from display init is stale; wait the full boot margin again. */
    tab5_pi4ioe_note_c6_reset();
    tab5_pi4ioe_wait_c6_sdio_ready();
    /* C6 slave needs time after GPIO15 flush before CMD53 RPC succeeds. */
    for (int wait = 0; wait < 40 && !wireless_transport_ready(); wait++) {
        vTaskDelay(pdMS_TO_TICKS(500));
    }
    return wireless_transport_ready();
}

static void wireless_prime_sta_config(void)
{
    char ssid[33] = {};
    char pass[65] = {};
    if (!modulus_nvs_get_str("wf_ssid", ssid, sizeof(ssid)) || !ssid[0]) {
        /* No saved STA — skip RPC set_config during boot (ESP-NOW / idle). */
        return;
    }
    wifi_config_t cfg = {};
    strncpy((char *)cfg.sta.ssid, ssid, sizeof(cfg.sta.ssid) - 1);
    if (modulus_nvs_get_str("wf_pass", pass, sizeof(pass)) && pass[0]) {
        strncpy((char *)cfg.sta.password, pass, sizeof(cfg.sta.password) - 1);
        cfg.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;
    } else {
        cfg.sta.threshold.authmode = WIFI_AUTH_OPEN;
    }
    esp_err_t err = esp_wifi_set_config(WIFI_IF_STA, &cfg);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "prime STA config: %s", esp_err_to_name(err));
    }
}

static bool wireless_transport_ready(void)
{
    return is_transport_tx_ready() != 0;
}

static bool wireless_ensure_wifi_stack_started(void)
{
    wireless_refresh_transport_state();
    if (s_wifi_stack_started) {
        return s_transport_up;
    }
    if (!wireless_transport_ready()) {
        ESP_LOGW(TAG, "esp_wifi_start skipped — SDIO transport down");
        return false;
    }
    /* C6 may have been reset by esp_wifi_init / SDIO probe — re-wait before RPC. */
    tab5_pi4ioe_wait_c6_sdio_ready();
    if (!wireless_transport_ready()) {
        ESP_LOGW(TAG, "esp_wifi_start aborted — transport lost after settle");
        return false;
    }
    wireless_prime_sta_config();
    esp_err_t err = esp_wifi_start();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        ESP_LOGE(TAG, "esp_wifi_start: %s", esp_err_to_name(err));
        wireless_invalidate_transport();
        return false;
    }
    if (!wireless_transport_ready()) {
        ESP_LOGW(TAG, "esp_wifi_start returned but SDIO transport down");
        wireless_invalidate_transport();
        return false;
    }
    s_wifi_stack_started = true;
    s_wifi_sta_running = true;
    s_transport_up = true;
    ESP_LOGI(TAG, "esp_wifi started (SDIO transport up)");
    return true;
}

static void tab5_c6_ensure_power(void)
{
    if (!tab5_pi4ioe_ensure_init()) {
        ESP_LOGE(TAG, "PI4IOE init failed — C6 power skipped");
        return;
    }
    if (tab5_c6_keep_rail_on_boot()) {
        /* Re-drive WLAN_PWR (BSP may have left E2.P0 High-Z) without cycling rail. */
        if (tab5_pi4ioe_ensure_wlan_pwr_on()) {
            ESP_LOGI(TAG, "C6 SDIO: boot — WLAN_PWR ensured (rst=%d)", (int)esp_reset_reason());
        } else {
            ESP_LOGW(TAG, "C6 SDIO: boot — WLAN_PWR ensure failed");
        }
        return;
    }
    /* SW restart / WDT / panic: P4 rebooted while C6 may still hold SDIO — cycle rail. */
    ESP_LOGI(TAG, "C6 SDIO: P4 abnormal reboot (%d) — WLAN_PWR cycle", (int)esp_reset_reason());
    tab5_pi4ioe_cycle_wlan_pwr();
}

static bool wireless_wait_wifi_stack(uint32_t timeout_ms)
{
    const TickType_t deadline = xTaskGetTickCount() + pdMS_TO_TICKS(timeout_ms);
    while (xTaskGetTickCount() < deadline) {
        wireless_refresh_transport_state();
        if (s_ready && wireless_ensure_wifi_stack_started() && s_wifi_sta_running) {
            return true;
        }
        tab5_pi4ioe_wait_c6_sdio_ready();
        vTaskDelay(pdMS_TO_TICKS(250));
    }
    return s_ready && wireless_ensure_wifi_stack_started() && s_wifi_sta_running;
}

/* wifi_ap_record_t is ~600 B × 12 — must not live on a 4 KB worker stack. */
static wifi_ap_record_t s_wifi_scan_records[WIFI_MAX_SCAN];

static void wifi_scan_collect_results(const wifi_event_sta_scan_done_t *ev)
{
    if (s_scan_done) {
        return;
    }
    if (ev && ev->status != 0) {
        ESP_LOGW(TAG, "WiFi scan failed status=%u", (unsigned)ev->status);
        taskENTER_CRITICAL(&s_wifi_mux);
        s_scan_n = 0;
        s_scan_done = true;
        taskEXIT_CRITICAL(&s_wifi_mux);
        s_scan_busy = false;
        modulus_wireless_radio_op_give();
        return;
    }
    uint16_t n = 0;
    if (ev && ev->number > 0) {
        n = ev->number;
    } else {
        esp_err_t nerr = esp_wifi_scan_get_ap_num(&n);
        if (nerr != ESP_OK) {
            ESP_LOGW(TAG, "WiFi scan get_ap_num: %s", esp_err_to_name(nerr));
            n = 0;
        }
    }
    if (n > WIFI_MAX_SCAN) {
        n = WIFI_MAX_SCAN;
    }
    memset(s_wifi_scan_records, 0, sizeof(s_wifi_scan_records));
    if (n == 0) {
        n = WIFI_MAX_SCAN;
    }
    {
        uint16_t fetch = n;
        esp_err_t rerr = esp_wifi_scan_get_ap_records(&fetch, s_wifi_scan_records);
        if (rerr != ESP_OK) {
            ESP_LOGW(TAG, "WiFi scan get_ap_records: %s", esp_err_to_name(rerr));
            n = 0;
        } else {
            n = fetch;
        }
    }
    taskENTER_CRITICAL(&s_wifi_mux);
    s_scan_n = 0;
    for (int i = 0; i < (int)n && s_scan_n < WIFI_MAX_SCAN; i++) {
        if (s_wifi_scan_records[i].ssid[0] == '\0') {
            continue;
        }
        strncpy(s_scan_buf[s_scan_n].ssid, (const char *)s_wifi_scan_records[i].ssid,
                sizeof(s_scan_buf[s_scan_n].ssid) - 1);
        s_scan_buf[s_scan_n].ssid[sizeof(s_scan_buf[s_scan_n].ssid) - 1] = '\0';
        s_scan_buf[s_scan_n].rssi = s_wifi_scan_records[i].rssi;
        s_scan_buf[s_scan_n].channel = s_wifi_scan_records[i].primary;
        s_scan_buf[s_scan_n].auth = (uint8_t)s_wifi_scan_records[i].authmode;
        s_scan_n++;
    }
    s_scan_done = true;
    taskEXIT_CRITICAL(&s_wifi_mux);
    s_scan_busy = false;
    modulus_wireless_radio_op_give();
    ESP_LOGI(TAG, "WiFi scan done: %d AP(s) (raw fetch %u)", s_scan_n, (unsigned)n);
}

static void wifi_scan_results_worker(void *arg)
{
    wifi_event_sta_scan_done_t ev = {};
    if (arg) {
        ev = *(const wifi_event_sta_scan_done_t *)arg;
    }
    wifi_scan_collect_results(&ev);
    vTaskDelete(NULL);
}

static void wifi_event_handler(void *arg, esp_event_base_t base, int32_t event_id, void *event_data)
{
    (void)arg;
    if (base == WIFI_EVENT) {
        switch (event_id) {
        case WIFI_EVENT_STA_START:
            s_wifi_sta_running = true;
            ESP_LOGI(TAG, "WiFi STA started (remote via C6)");
            break;
        case WIFI_EVENT_STA_STOP:
            s_wifi_sta_running = false;
            s_wifi_stack_started = false;
            ESP_LOGW(TAG, "WiFi STA stopped (remote via C6)");
            modulus_wireless_espnow_on_wifi_stop();
            break;
        case WIFI_EVENT_STA_CONNECTED: {
            wifi_event_sta_connected_t *ev = event_data;
            taskENTER_CRITICAL(&s_wifi_mux);
            s_wifi_enabled = true;
            s_wifi_connecting = true;
            if (ev && ev->ssid[0]) {
                strncpy(s_wifi_ssid, (const char *)ev->ssid, sizeof(s_wifi_ssid) - 1);
            }
            taskEXIT_CRITICAL(&s_wifi_mux);
            modulus_wireless_espnow_check_channel_conflict();
            break;
        }
        case WIFI_EVENT_STA_DISCONNECTED: {
            wifi_event_sta_disconnected_t *ev = event_data;
            const int reason = ev ? (int)ev->reason : -1;
            ESP_LOGW(TAG, "WiFi disconnected (reason=%d)", reason);
            bool user_dc = false;
            taskENTER_CRITICAL(&s_wifi_mux);
            s_wifi_connected = false;
            s_wifi_connecting = false;
            s_wifi_ip[0] = '\0';
            s_wifi_disc_reason = reason;
            user_dc = s_user_disconnect;
            s_user_disconnect = false;
            taskEXIT_CRITICAL(&s_wifi_mux);
            if (!user_dc && modulus_nvs_get_u8("wf_arecon", 1) != 0) {
                esp_err_t rc = esp_wifi_connect();
                if (rc != ESP_OK) {
                    ESP_LOGW(TAG, "auto-reconnect: %s", esp_err_to_name(rc));
                } else {
                    taskENTER_CRITICAL(&s_wifi_mux);
                    s_wifi_connecting = true;
                    taskEXIT_CRITICAL(&s_wifi_mux);
                }
            }
            break;
        }
        case WIFI_EVENT_SCAN_DONE: {
            if (event_data) {
                s_scan_done_ev = *(const wifi_event_sta_scan_done_t *)event_data;
            } else {
                memset(&s_scan_done_ev, 0, sizeof(s_scan_done_ev));
            }
            s_scan_ev_ready = true;
            ESP_LOGI(TAG, "WiFi SCAN_DONE (status=%u n=%u busy=%d)",
                     (unsigned)s_scan_done_ev.status, (unsigned)s_scan_done_ev.number,
                     (int)s_scan_busy);
            /* Scan worker usually collects; fallback if it already timed out. */
            if (!s_scan_busy) {
                if (xTaskCreatePinnedToCore(wifi_scan_results_worker, "wf_scan_res", 6144,
                                            &s_scan_done_ev, 4, NULL, 1) != pdPASS) {
                    wifi_scan_collect_results(&s_scan_done_ev);
                }
            }
            break;
        }
        default:
            break;
        }
    } else if (base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *ev = event_data;
        char ip_str[16];
        snprintf(ip_str, sizeof(ip_str), IPSTR, IP2STR(&ev->ip_info.ip));
        taskENTER_CRITICAL(&s_wifi_mux);
        s_wifi_connected = true;
        s_wifi_connecting = false;
        s_wifi_disc_reason = 0;
        strncpy(s_wifi_ip, ip_str, sizeof(s_wifi_ip) - 1);
        taskEXIT_CRITICAL(&s_wifi_mux);
        ESP_LOGI(TAG, "Got IP: %s", ip_str);
        /* Keep power-save off while ESP-NOW is active (it needs the radio
         * always-on); only re-enable modem sleep for plain Wi-Fi STA use. */
        if (!modulus_wireless_espnow_is_enabled()) {
            esp_wifi_set_ps(WIFI_PS_MIN_MODEM);
        }
        modulus_wireless_espnow_check_channel_conflict();
        modulus_rtc_ntp_on_wifi_connected();
    }
}

bool modulus_wireless_init(void)
{
#if !CONFIG_MODULUS_WIFI_ENABLED
    return false;
#else
    return wireless_host_init(true);
#endif
}

static bool wireless_host_init(bool aggressive)
{
#if !CONFIG_MODULUS_WIFI_ENABLED
    return false;
#else
    if (s_ready) {
        return true;
    }

    host_init_mux_init();
    if (xSemaphoreTake(s_host_init_mux, pdMS_TO_TICKS(120000)) != pdTRUE) {
        ESP_LOGW(TAG, "wireless_host_init blocked — init already running");
        return s_ready;
    }
    if (s_ready) {
        xSemaphoreGive(s_host_init_mux);
        return true;
    }

    /* Create single-threaded at boot: the lazy path in try_take can be entered
     * by the UI thread and a worker at once and build two tokens. */
    radio_op_init();

    ESP_LOGI(TAG, "esp_hosted host " ESP_HOSTED_VERSION_PRINTF_FMT,
             ESP_HOSTED_VERSION_MAJOR_1, ESP_HOSTED_VERSION_MINOR_1,
             ESP_HOSTED_VERSION_PATCH_1);

    tab5_c6_ensure_power();

    esp_err_t err = esp_netif_init();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        ESP_LOGE(TAG, "esp_netif_init: %s", esp_err_to_name(err));
        xSemaphoreGive(s_host_init_mux);
        return false;
    }
    err = esp_event_loop_create_default();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        ESP_LOGE(TAG, "esp_event_loop: %s", esp_err_to_name(err));
        xSemaphoreGive(s_host_init_mux);
        return false;
    }

    if (!wireless_ensure_sta_netif()) {
        xSemaphoreGive(s_host_init_mux);
        return false;
    }

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    bool transport_ok = false;
    const int outer_max = aggressive ? 3 : 1;
    const int soft_max = aggressive ? C6_WIFI_SOFT_RETRIES : 2;
    const int soft_delay_ms = aggressive ? 1500 : 2500;
    for (int attempt = 0; attempt < outer_max; attempt++) {
        if (attempt > 0) {
            /* Tear down partial esp_wifi / SDIO before rail cycle — cycling
             * WLAN_PWR while sdio_read is recovering causes CMD53 0x107 storms. */
            wireless_teardown_host_stack(false);
            vTaskDelay(pdMS_TO_TICKS(2000));
            tab5_pi4ioe_cycle_wlan_pwr();
            tab5_pi4ioe_wait_c6_sdio_ready();
            if (!wireless_ensure_sta_netif()) {
                xSemaphoreGive(s_host_init_mux);
                return false;
            }
        }
        for (int soft = 0; soft < soft_max; soft++) {
            ESP_LOGI(TAG, "C6 SDIO: esp_wifi_init attempt %d.%d (%s)",
                     attempt + 1, soft + 1, aggressive ? "boot" : "wake");
            transport_ok = wireless_try_esp_wifi_init(&cfg);
            if (transport_ok) {
                break;
            }
            ESP_LOGW(TAG, "esp_wifi_init attempt %d.%d failed — soft retry",
                     attempt + 1, soft + 1);
            if (wireless_transport_ready()) {
                (void)esp_wifi_deinit();
            } else {
                wireless_abandon_host_stack();
            }
            vTaskDelay(pdMS_TO_TICKS(soft_delay_ms));
        }
        if (transport_ok) {
            break;
        }
        ESP_LOGW(TAG, "esp_wifi_init attempt %d: transport not up", attempt + 1);
    }
    if (!transport_ok) {
        ESP_LOGE(TAG, "esp_wifi_init failed (transport down)");
        wireless_teardown_host_stack(false);
        xSemaphoreGive(s_host_init_mux);
        return false;
    }

    esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, wifi_event_handler, NULL);
    esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, wifi_event_handler, NULL);
    s_event_handlers_registered = true;

    err = esp_wifi_set_mode(WIFI_MODE_STA);
    if (err != ESP_OK) {
        xSemaphoreGive(s_host_init_mux);
        return false;
    }

    s_ext_antenna = modulus_nvs_get_u8("ant_ext", 0) != 0;
    tab5_pi4ioe_set_ext_antenna_enable(s_ext_antenna);
    ESP_LOGI(TAG, "Antenna: %s (PI4IOE1 P0)", s_ext_antenna ? "external MMCX" : "internal PCB");

    /* LVGL hal_wireless::init() always esp_wifi_start() — SDIO transport must be
     * up before ESP-NOW toggle; lazy start caused esp_wifi_start on UI thread. */
    if (!wireless_ensure_wifi_stack_started()) {
        ESP_LOGW(TAG, "esp_wifi_start deferred at init — retry on radio enable");
    }

    s_ready = true;
    modulus_wireless_rpc_init();
    modulus_zb_auto_start_task();
    ESP_LOGI(TAG, "Wireless ready (esp_hosted SDIO -> C6); flash C6 from firmware/tab5-c6 (must match host %u.%u.%u)",
             ESP_HOSTED_VERSION_MAJOR_1, ESP_HOSTED_VERSION_MINOR_1, ESP_HOSTED_VERSION_PATCH_1);
    xSemaphoreGive(s_host_init_mux);
    return true;
#endif
}

bool modulus_wireless_ensure_wifi_stack(void)
{
    return wireless_ensure_wifi_stack_started();
}

bool modulus_wireless_ready(void) { return s_ready; }

bool modulus_wireless_transport_up(void)
{
    wireless_refresh_transport_state();
    return s_transport_up;
}

bool modulus_wireless_wifi_sta_running(void)
{
    wireless_refresh_transport_state();
    return s_wifi_sta_running && s_transport_up;
}

void modulus_wireless_set_antenna_external(bool external)
{
    s_ext_antenna = external;
    (void)tab5_pi4ioe_ensure_init();
    tab5_pi4ioe_set_ext_antenna_enable(external);
    modulus_nvs_set_u8("ant_ext", external ? 1 : 0);
}

bool modulus_wireless_is_external_antenna(void) { return s_ext_antenna; }

void modulus_wireless_post_restore_settle(void)
{
    if (!s_ready || !s_wifi_stack_started) {
        return;
    }
    tab5_pi4ioe_wait_c6_sdio_ready();
    vTaskDelay(pdMS_TO_TICKS(500));
}

void modulus_wireless_restore_settings(void)
{
    if (!s_ready) {
        return;
    }
    if (!wireless_transport_ready() && !wireless_ensure_wifi_stack_started()) {
        ESP_LOGW(TAG, "Skip NVS radio restore — SDIO transport down");
        return;
    }
    if (modulus_nvs_get_u8("wifi", 0) != 0) {
        modulus_wireless_wifi_enable();
    }
    {
        bool espnow_on = modulus_nvs_get_u8("espnow", 0) != 0;
        if (!espnow_on && modulus_nvs_get_u8("cnc_conn", 4) == 0) {
            char mac[20];
            if (modulus_nvs_get_str("en_mac", mac, sizeof(mac)) && mac[0] &&
                strcmp(mac, "FF:FF:FF:FF:FF:FF") != 0) {
                espnow_on = true;
            }
        }
        if (espnow_on) {
            modulus_wireless_espnow_enable();
        }
    }
    if (modulus_nvs_get_u8("zigbee", 0) != 0) {
        modulus_wireless_zigbee_enable();
    }
    if (modulus_nvs_get_u8("thread", 0) != 0 && modulus_wireless_thread_supported()) {
        modulus_wireless_thread_enable();
    }
    if (modulus_nvs_get_u8("bt", 0) != 0) {
        modulus_wireless_ble_enable();
    }
    modulus_espnow_debug_apply_log_tags();
    modulus_wireless_espnow_boot_reconnect();
}

void modulus_wireless_prepare_for_sleep(void)
{
    if (!s_ready) {
        return;
    }
    ESP_LOGI(TAG, "Preparing wireless for sleep (quiesce SDIO traffic)");
    modulus_wireless_espnow_disable();
    modulus_wireless_ble_disable();
    wireless_zigbee_stop_hub(); /* preserves zb_auto so wake restores Zigbee */
    modulus_wireless_thread_disable();
    esp_wifi_disconnect();
    modulus_wireless_espnow_on_wifi_stop();
    if (s_wifi_stack_started) {
        esp_wifi_stop();
        s_wifi_stack_started = false;
        s_wifi_sta_running = false;
        vTaskDelay(pdMS_TO_TICKS(300));
    }
}

void modulus_wireless_deinit(void)
{
    if (!s_ready && !s_sta_netif && !s_event_handlers_registered) {
        return;
    }
    ESP_LOGI(TAG, "Tearing down wireless / esp_hosted host stack");
    wireless_teardown_host_stack(true);
    ESP_LOGI(TAG, "Wireless HAL deinitialized");
}

bool modulus_wireless_wake_coprocessor(void)
{
    /* A WLAN_PWR cycle mid-scan resets the C6 out from under the in-flight RPC. */
    if (s_scan_busy) {
        ESP_LOGW(TAG, "C6 wake blocked — Wi-Fi scan in progress");
        return false;
    }
    /* LVGL hal_wireless::wake_coprocessor: GPIO15 reset + poll init — NOT WLAN_PWR
     * (WLAN_PWR is cold-boot / P4-only-reboot only; runtime wake used GPIO15). */
    ESP_LOGI(TAG, "Waking C6 coprocessor — GPIO15 reset + hosted reinit");
    vTaskDelay(pdMS_TO_TICKS(150));
    if (!tab5_pi4ioe_ensure_init()) {
        ESP_LOGE(TAG, "C6 wake: PI4IOE init failed");
        return false;
    }
    (void)tab5_pi4ioe_ensure_wlan_pwr_on();
    if (s_ready || s_sta_netif || s_event_handlers_registered) {
        ESP_LOGW(TAG, "Stale wireless state before wake — local abandon (no RPC)");
        wireless_abandon_host_stack();
    }

    tab5_pi4ioe_c6_hardware_reset();
    tab5_pi4ioe_wait_c6_sdio_ready();

    for (uint32_t waited = 0; waited <= 5000; waited += 100) {
        if (waited > 0) {
            vTaskDelay(pdMS_TO_TICKS(100));
        }
        if (wireless_host_init(false) && wireless_ensure_wifi_stack_started()) {
            ESP_LOGI(TAG, "C6 coprocessor ready after %u ms", (unsigned)waited);
            return true;
        }
        if (s_ready || s_sta_netif || s_event_handlers_registered) {
            wireless_abandon_host_stack();
        }
    }
    ESP_LOGE(TAG, "C6 wake failed after 5 s");
    return false;
}

static volatile bool s_sdio_recover_busy;

static void sdio_recovery_worker(void *arg)
{
    (void)arg;
    ESP_LOGW(TAG, "SDIO bus dead — GPIO15 C6 recovery");
    modulus_c6_sdio_quiesce(60000);
    (void)modulus_wireless_wake_coprocessor();
    s_sdio_recover_busy = false;
    vTaskDelete(NULL);
}

void modulus_wireless_poll(void)
{
    wireless_refresh_transport_state();

    static uint8_t s_sdio_down_streak;
    if (!wireless_transport_ready()) {
        if (s_sdio_down_streak < 255) {
            s_sdio_down_streak++;
        }
    } else {
        s_sdio_down_streak = 0;
    }

    /* Debounce: brief TX-ready flaps must not drop Connecting mid-handshake. */
    if (s_sdio_down_streak >= 12 && modulus_espnow_transport_is_open()) {
        ESP_LOGW(TAG, "SDIO down — closing ESP-NOW transport");
        modulus_espnow_transport_stop();
    }
    if (s_sdio_down_streak >= 10 && s_ready && !wireless_transport_ready() &&
        !s_sdio_recover_busy) {
        static TickType_t s_last_recover;
        const TickType_t now = xTaskGetTickCount();
        if (now - s_last_recover > pdMS_TO_TICKS(120000)) {
            s_last_recover = now;
            s_sdio_recover_busy = true;
            if (xTaskCreate(sdio_recovery_worker, "sdio_rec", 4096, NULL, 3, NULL) != pdPASS) {
                s_sdio_recover_busy = false;
            }
        }
    }
    /* HCI reset loops leave s_bt_on + "Starting" forever — force Off after dwell. */
    if (s_sdio_down_streak >= 24 && !s_ble_enable_busy && modulus_ble_settings_is_enabled() &&
        (modulus_ble_host_failed() || !wireless_transport_ready())) {
        ESP_LOGW(TAG, "BLE host dead (HCI/SDIO) — forcing radio off");
        modulus_ble_settings_disable();
        modulus_ble_host_reset();
        s_ble_enable_fail = true;
    }
    modulus_wireless_rpc_poll_state(s_zb_on, s_th_on);
    modulus_wireless_zigbee_join_poll();
    modulus_wireless_802154_poll();
    modulus_wireless_espnow_poll_scan();
}

static void wifi_enable_worker(void *arg)
{
    (void)arg;
    if (!s_ready || !wireless_ensure_wifi_stack_started()) {
        s_wifi_enable_busy = false;
        vTaskDelete(NULL);
        return;
    }
    taskENTER_CRITICAL(&s_wifi_mux);
    s_wifi_enabled = true;
    taskEXIT_CRITICAL(&s_wifi_mux);
    modulus_nvs_set_u8("wifi", 1);

    char ssid[33] = {};
    char pass[65] = {};
    if (modulus_nvs_get_u8("wf_auto", 1) != 0 &&
        modulus_nvs_get_str("wf_ssid", ssid, sizeof(ssid)) && ssid[0]) {
        modulus_nvs_get_str("wf_pass", pass, sizeof(pass));
        (void)modulus_wireless_wifi_connect(ssid, pass);
    }
    s_wifi_enable_busy = false;
    vTaskDelete(NULL);
}

bool modulus_wireless_wifi_enable(void)
{
    if (!s_ready) {
        return false;
    }
    if (s_wifi_enable_busy) {
        return true; /* already starting */
    }
    s_wifi_enable_busy = true;
    /* Heavy C6 settle + esp_wifi_start off LVGL thread. */
    if (xTaskCreatePinnedToCore(wifi_enable_worker, "wifi_en", 4096, NULL, 3, NULL, 0) !=
        pdPASS) {
        s_wifi_enable_busy = false;
        return false;
    }
    return true;
}

void modulus_wireless_wifi_disable(void)
{
    s_user_disconnect = true;
    esp_wifi_disconnect();
    modulus_wireless_espnow_on_wifi_stop();
    if (s_ready && s_wifi_stack_started) {
        esp_err_t err = esp_wifi_stop();
        if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
            ESP_LOGW(TAG, "esp_wifi_stop on disable: %s", esp_err_to_name(err));
        }
        s_wifi_stack_started = false;
        s_wifi_sta_running = false;
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    taskENTER_CRITICAL(&s_wifi_mux);
    s_wifi_enabled = false;
    s_wifi_connected = false;
    s_wifi_connecting = false;
    s_wifi_ip[0] = '\0';
    taskEXIT_CRITICAL(&s_wifi_mux);
    modulus_nvs_set_u8("wifi", 0);
}

bool modulus_wireless_wifi_is_enabled(void)
{
    /* Enable worker is async — treat in-flight start as On so Zig UI mirror
     * does not flip the toggle off before s_wifi_enabled latches. */
    taskENTER_CRITICAL(&s_wifi_mux);
    bool v = s_wifi_enabled || s_wifi_enable_busy;
    taskEXIT_CRITICAL(&s_wifi_mux);
    return v;
}

bool modulus_wireless_wifi_is_connected(void)
{
    taskENTER_CRITICAL(&s_wifi_mux);
    bool v = s_wifi_connected;
    taskEXIT_CRITICAL(&s_wifi_mux);
    return v;
}

bool modulus_wireless_wifi_is_connecting(void)
{
    taskENTER_CRITICAL(&s_wifi_mux);
    bool v = s_wifi_connecting && !s_wifi_connected;
    taskEXIT_CRITICAL(&s_wifi_mux);
    return v;
}

static void wifi_scan_worker(void *arg)
{
    (void)arg;
    bool started = false;

    if (s_ble_enable_busy) {
        ESP_LOGW(TAG, "WiFi scan: waiting for BLE enable to finish");
        for (int i = 0; i < 20 && s_ble_enable_busy; i++) {
            vTaskDelay(pdMS_TO_TICKS(250));
        }
        if (s_ble_enable_busy) {
            ESP_LOGW(TAG, "WiFi scan: BLE enable still busy");
            goto done;
        }
    }

    /* Wait for SDIO + STA — do not tear down Wi-Fi (disconnect/stop) on a slow RPC. */
    if (!wireless_wait_wifi_stack(10000)) {
        ESP_LOGE(TAG, "WiFi scan: stack not ready after wait");
        goto done;
    }

    if (!s_wifi_enabled && !s_wifi_enable_busy) {
        taskENTER_CRITICAL(&s_wifi_mux);
        s_wifi_enabled = true;
        taskEXIT_CRITICAL(&s_wifi_mux);
        modulus_nvs_set_u8("wifi", 1);
    }

    vTaskDelay(pdMS_TO_TICKS(400));

    ESP_LOGI(TAG, "WiFi scan_start (default dwell)");
    esp_err_t err = esp_wifi_scan_start(NULL, false);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "WiFi scan_start: %s — settle + retry", esp_err_to_name(err));
        vTaskDelay(pdMS_TO_TICKS(1000));
        err = esp_wifi_scan_start(NULL, false);
        if (err != ESP_OK) {
            wireless_refresh_transport_state();
            if (!s_ready || !wireless_transport_ready()) {
                ESP_LOGW(TAG, "WiFi scan: transport dead — waking C6");
                wireless_invalidate_transport();
                if (modulus_espnow_transport_is_open()) {
                    modulus_espnow_transport_stop();
                }
                if (!modulus_wireless_wake_coprocessor() || !wireless_wait_wifi_stack(15000)) {
                    ESP_LOGE(TAG, "WiFi scan: C6 wake failed (dual-flash C6 if persistent)");
                    goto done;
                }
                vTaskDelay(pdMS_TO_TICKS(600));
                err = esp_wifi_scan_start(NULL, false);
            }
            if (err != ESP_OK) {
                ESP_LOGE(TAG, "WiFi scan_start retry: %s", esp_err_to_name(err));
                goto done;
            }
        }
    }
    started = true;

    /* esp_hosted often completes scan on C6 before P4 sees SCAN_DONE — poll here. */
    for (uint32_t waited_ms = 0; waited_ms < 45000 && !s_scan_done; waited_ms += 200) {
        vTaskDelay(pdMS_TO_TICKS(200));
        if (s_scan_ev_ready) {
            wifi_scan_collect_results(&s_scan_done_ev);
            break;
        }
        if (waited_ms >= 2500) {
            uint16_t n = 0;
            esp_err_t perr = esp_wifi_scan_get_ap_num(&n);
            if (perr == ESP_OK) {
                wifi_event_sta_scan_done_t ev = { .status = 0, .number = n };
                wifi_scan_collect_results(&ev);
                break;
            }
        }
    }
    if (!s_scan_done) {
        ESP_LOGW(TAG, "WiFi scan: no results after 45s — forcing collect");
        wifi_scan_collect_results(NULL);
    }
    if (!s_scan_done) {
        taskENTER_CRITICAL(&s_wifi_mux);
        s_scan_n = 0;
        s_scan_done = true;
        taskEXIT_CRITICAL(&s_wifi_mux);
        s_scan_busy = false;
        modulus_wireless_radio_op_give();
    }

done:
    if (!started) {
        taskENTER_CRITICAL(&s_wifi_mux);
        s_scan_n = 0;
        s_scan_done = true;
        taskEXIT_CRITICAL(&s_wifi_mux);
        s_scan_busy = false;
        modulus_wireless_radio_op_give();
    }
    vTaskDelete(NULL);
}

bool modulus_wireless_wifi_scan_start(void)
{
    /* Allow scan while STA connecting/connected (ESP-IDF supports it). */
    if (s_scan_busy) {
        return true;
    }
    taskENTER_CRITICAL(&s_wifi_mux);
    s_scan_done = false;
    s_scan_n = 0;
    taskEXIT_CRITICAL(&s_wifi_mux);
    s_scan_ev_ready = false;
    memset(&s_scan_done_ev, 0, sizeof(s_scan_done_ev));
    s_scan_busy = true;
    if (!modulus_wireless_radio_op_try_take(0)) {
        ESP_LOGW(TAG, "WiFi scan: radio busy");
        s_scan_busy = false;
        taskENTER_CRITICAL(&s_wifi_mux);
        s_scan_done = true;
        taskEXIT_CRITICAL(&s_wifi_mux);
        return false;
    }
    /* Off UI thread: wake_coprocessor can block several seconds. */
    if (xTaskCreate(wifi_scan_worker, "wf_scan", 4096, NULL, 5, NULL) != pdPASS) {
        ESP_LOGE(TAG, "WiFi scan: worker create failed");
        s_scan_busy = false;
        modulus_wireless_radio_op_give();
        taskENTER_CRITICAL(&s_wifi_mux);
        s_scan_done = true;
        taskEXIT_CRITICAL(&s_wifi_mux);
        return false;
    }
    return true;
}

bool modulus_wireless_wifi_scan_done(void)
{
    taskENTER_CRITICAL(&s_wifi_mux);
    bool v = s_scan_done;
    taskEXIT_CRITICAL(&s_wifi_mux);
    return v;
}

int modulus_wireless_wifi_scan_count(void)
{
    taskENTER_CRITICAL(&s_wifi_mux);
    int n = s_scan_n;
    taskEXIT_CRITICAL(&s_wifi_mux);
    return n;
}

bool modulus_wireless_wifi_scan_get(int idx, modulus_wifi_ap_t *out)
{
    if (!out || idx < 0) {
        return false;
    }
    taskENTER_CRITICAL(&s_wifi_mux);
    if (idx >= s_scan_n) {
        taskEXIT_CRITICAL(&s_wifi_mux);
        return false;
    }
    *out = s_scan_buf[idx];
    taskEXIT_CRITICAL(&s_wifi_mux);
    return true;
}

bool modulus_wireless_wifi_connect(const char *ssid, const char *pass)
{
    if (!s_ready || !ssid || !ssid[0]) {
        return false;
    }
    if (!wireless_ensure_wifi_stack_started()) {
        return false;
    }
    s_user_disconnect = false;
    taskENTER_CRITICAL(&s_wifi_mux);
    s_wifi_enabled = true;
    s_wifi_connecting = true;
    s_wifi_disc_reason = 0;
    taskEXIT_CRITICAL(&s_wifi_mux);
    modulus_nvs_set_u8("wifi", 1);

    modulus_nvs_set_str("wf_ssid", ssid);
    modulus_nvs_set_str("wf_pass", pass ? pass : "");
    wireless_prime_sta_config();

    wifi_config_t cfg = {};
    strncpy((char *)cfg.sta.ssid, ssid, sizeof(cfg.sta.ssid) - 1);
    if (pass && pass[0]) {
        strncpy((char *)cfg.sta.password, pass, sizeof(cfg.sta.password) - 1);
        cfg.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;
    } else {
        cfg.sta.threshold.authmode = WIFI_AUTH_OPEN;
    }
    esp_wifi_disconnect();
    esp_wifi_set_config(WIFI_IF_STA, &cfg);
    if (esp_wifi_connect() != ESP_OK) {
        taskENTER_CRITICAL(&s_wifi_mux);
        s_wifi_connecting = false;
        taskEXIT_CRITICAL(&s_wifi_mux);
        return false;
    }
    taskENTER_CRITICAL(&s_wifi_mux);
    strncpy(s_wifi_ssid, ssid, sizeof(s_wifi_ssid) - 1);
    taskEXIT_CRITICAL(&s_wifi_mux);
    return true;
}

bool modulus_wireless_wifi_connect_saved(void)
{
    char ssid[33] = {};
    char pass[65] = {};
    if (!modulus_nvs_get_str("wf_ssid", ssid, sizeof(ssid)) || !ssid[0]) {
        return false;
    }
    (void)modulus_nvs_get_str("wf_pass", pass, sizeof(pass));
    return modulus_wireless_wifi_connect(ssid, pass);
}

bool modulus_wireless_wifi_disconnect(void)
{
    s_user_disconnect = true;
    taskENTER_CRITICAL(&s_wifi_mux);
    s_wifi_connected = false;
    s_wifi_connecting = false;
    taskEXIT_CRITICAL(&s_wifi_mux);
    return esp_wifi_disconnect() == ESP_OK;
}

void modulus_wireless_wifi_forget_saved(void)
{
    modulus_nvs_set_str("wf_ssid", "");
    modulus_nvs_set_str("wf_pass", "");
    (void)esp_wifi_clear_fast_connect();
    wifi_config_t zero = {};
    (void)esp_wifi_set_config(WIFI_IF_STA, &zero);
    taskENTER_CRITICAL(&s_wifi_mux);
    s_wifi_ssid[0] = '\0';
    taskEXIT_CRITICAL(&s_wifi_mux);
}

const char *modulus_wireless_wifi_radio_text(void)
{
    if (!s_ready) {
        return "C6 not ready";
    }
    if (!s_wifi_stack_started) {
        return "Idle (enable to start)";
    }
    if (!s_wifi_enabled) {
        return "Off";
    }
    if (s_wifi_connected) {
        return "Connected";
    }
    if (s_wifi_connecting) {
        return "Connecting...";
    }
    if (s_wifi_disc_reason != 0) {
        return modulus_wireless_wifi_error_text();
    }
    return "On (no IP)";
}

const char *modulus_wireless_wifi_ip_text(void)
{
    if (!s_wifi_connected || s_wifi_ip[0] == '\0') {
        return "No IP";
    }
    return s_wifi_ip;
}

const char *modulus_wireless_wifi_error_text(void)
{
    static char buf[40];
    switch (s_wifi_disc_reason) {
    case WIFI_REASON_AUTH_FAIL:
    case WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT:
    case WIFI_REASON_HANDSHAKE_TIMEOUT:
        return "Auth failed";
    case WIFI_REASON_NO_AP_FOUND:
        return "Network not found";
    case WIFI_REASON_ASSOC_FAIL:
        return "Association failed";
    case WIFI_REASON_CONNECTION_FAIL:
        return "Connection failed";
    case 0:
        return "";
    default:
        snprintf(buf, sizeof(buf), "Error %d", s_wifi_disc_reason);
        return buf;
    }
}

bool modulus_wireless_wifi_ap_needs_pass(uint8_t auth)
{
    return auth != WIFI_AUTH_OPEN && auth != WIFI_AUTH_OWE;
}

const char *modulus_wireless_wifi_auth_text(uint8_t auth)
{
    switch ((wifi_auth_mode_t)auth) {
    case WIFI_AUTH_OPEN:
        return "Open";
    case WIFI_AUTH_WEP:
        return "WEP";
    case WIFI_AUTH_WPA_PSK:
        return "WPA";
    case WIFI_AUTH_WPA2_PSK:
        return "WPA2";
    case WIFI_AUTH_WPA_WPA2_PSK:
        return "WPA/WPA2";
    case WIFI_AUTH_WPA2_ENTERPRISE:
        return "Enterprise";
    case WIFI_AUTH_WPA3_PSK:
        return "WPA3";
    case WIFI_AUTH_WPA2_WPA3_PSK:
        return "WPA2/WPA3";
    case WIFI_AUTH_WAPI_PSK:
        return "WAPI";
    case WIFI_AUTH_OWE:
        return "OWE";
    default:
        return "Secured";
    }
}

const char *modulus_wireless_wifi_ssid_text(void)
{
    if (!s_wifi_connected) {
        char ssid[33] = {};
        if (modulus_nvs_get_str("wf_ssid", ssid, sizeof(ssid)) && ssid[0]) {
            static char buf[48];
            snprintf(buf, sizeof(buf), "%.28s (saved)", ssid);
            return buf;
        }
        return "Not connected";
    }
    wifi_ap_record_t ap = {};
    if (esp_wifi_sta_get_ap_info(&ap) == ESP_OK) {
        static char buf[40];
        snprintf(buf, sizeof(buf), "%.32s", (const char *)ap.ssid);
        return buf;
    }
    return s_wifi_ssid[0] ? s_wifi_ssid : "Connected";
}

const char *modulus_wireless_wifi_scan_text(void)
{
    if (!s_wifi_enabled) {
        return "Radio off";
    }
    if (!s_scan_done) {
        return "Scanning...";
    }
    static char buf[24];
    snprintf(buf, sizeof(buf), "%d network(s)", s_scan_n);
    return buf;
}

/* ── Zigbee / Thread (802.15.4 radios on C6) ───────────────────── */

const char *modulus_wireless_ble_status_text(void)
{
    if (s_ble_enable_busy && !modulus_ble_settings_is_enabled()) {
        if (!wireless_transport_ready()) {
            return "C6 offline";
        }
        return "Starting...";
    }
    return modulus_ble_settings_status_text();
}

const char *modulus_wireless_ble_paired_text(void)
{
    return modulus_ble_settings_paired_text();
}

static void ble_enable_worker(void *arg)
{
    (void)arg;
    bool ok = false;
    const int64_t deadline = esp_timer_get_time() + 20000000LL; /* 20s hard cap */

    if (!s_ready) {
        goto done;
    }
    /* ESP-NOW CNC hammers SDIO — quiesce before BLE HCI on same C6 link. */
    if (modulus_espnow_transport_is_open()) {
        modulus_espnow_transport_stop();
    }
    if (modulus_wireless_espnow_is_enabled()) {
        modulus_wireless_espnow_disable();
        vTaskDelay(pdMS_TO_TICKS(500));
    }
    modulus_ble_host_reset();

    for (int attempt = 0; attempt < 3 && !ok; attempt++) {
        if (esp_timer_get_time() > deadline) {
            ESP_LOGE(TAG, "BLE enable: deadline exceeded");
            break;
        }
        if (attempt > 0) {
            ESP_LOGW(TAG, "BLE enable retry after wake");
            modulus_ble_host_reset();
            wireless_invalidate_transport();
            if (!modulus_wireless_wake_coprocessor()) {
                continue;
            }
            vTaskDelay(pdMS_TO_TICKS(500));
        }
        if (!wireless_ensure_wifi_stack_started()) {
            ESP_LOGW(TAG, "BLE enable: stack/SDIO down — waking C6");
            wireless_invalidate_transport();
            if (!modulus_wireless_wake_coprocessor() || !wireless_ensure_wifi_stack_started()) {
                ESP_LOGE(TAG, "BLE enable: C6 wake failed");
                continue;
            }
        }
        if (!wireless_transport_ready()) {
            ESP_LOGE(TAG, "BLE enable: transport still down");
            continue;
        }
        vTaskDelay(pdMS_TO_TICKS(300));
        ok = modulus_ble_settings_enable();
        if (!ok) {
            ESP_LOGW(TAG, "BLE enable: host init failed (attempt %d)", attempt + 1);
        } else if (modulus_ble_host_failed() || !modulus_ble_host_ready()) {
            /* Sync appeared then HCI died immediately. */
            ESP_LOGW(TAG, "BLE enable: host not stable after sync");
            ok = false;
            modulus_ble_settings_disable();
        }
    }

done:
    if (!ok) {
        modulus_ble_settings_disable();
        s_ble_enable_fail = true;
    }
    s_ble_enable_busy = false;
    modulus_wireless_radio_op_give();
    vTaskDelete(NULL);
}

bool modulus_wireless_ble_enable(void)
{
    if (!s_ready) {
        return false;
    }
    if (s_ble_enable_busy) {
        return true;
    }
    if (modulus_ble_settings_is_enabled() && modulus_ble_host_ready()) {
        return true;
    }
    s_ble_enable_fail = false;
    s_ble_enable_busy = true;
    if (!modulus_wireless_radio_op_try_take(0)) {
        ESP_LOGW(TAG, "BLE enable: radio busy");
        s_ble_enable_busy = false;
        return false;
    }
    /* Heavy: wake C6 + NimBLE host sync can take seconds — never on UI thread. */
    if (xTaskCreatePinnedToCore(ble_enable_worker, "ble_en", 8192, NULL, 3, NULL, 0) !=
        pdPASS) {
        s_ble_enable_busy = false;
        modulus_wireless_radio_op_give();
        return false;
    }
    return true;
}

void modulus_wireless_ble_disable(void)
{
    s_ble_enable_busy = false;
    modulus_ble_settings_disable();
}

bool modulus_wireless_ble_is_enabled(void)
{
    return modulus_ble_settings_is_enabled() || s_ble_enable_busy;
}

bool modulus_wireless_ble_enable_failed(void)
{
    bool v = s_ble_enable_fail;
    s_ble_enable_fail = false;
    return v;
}

bool modulus_wireless_ble_scan_start(void)
{
    if (!s_ready) {
        return false;
    }
    /* Radio may still be coming up (async enable) — kick it, then scan waits. */
    if (!modulus_ble_settings_is_enabled() && !s_ble_enable_busy) {
        if (!modulus_wireless_ble_enable()) {
            return false;
        }
    }
    return modulus_ble_settings_scan_start();
}

bool modulus_wireless_ble_scan_done(void)
{
    return modulus_ble_settings_scan_done();
}

int modulus_wireless_ble_scan_count(void)
{
    return modulus_ble_settings_scan_count();
}

void modulus_wireless_ble_scan_stop(void)
{
    modulus_ble_settings_scan_stop();
}

bool modulus_wireless_ble_scan_get(int idx, char *name, size_t name_len, int8_t *rssi_out,
                                   char *addr_out, size_t addr_len)
{
    return modulus_ble_settings_scan_get(idx, name, name_len, rssi_out, addr_out, addr_len);
}

bool modulus_wireless_ble_is_connecting(void)
{
    return modulus_ble_settings_is_connecting();
}

bool modulus_wireless_ble_is_connected(void)
{
    return modulus_ble_settings_is_connected();
}

bool modulus_wireless_ble_connect(int idx)
{
    return modulus_ble_settings_connect(idx);
}

void modulus_wireless_ble_disconnect(void)
{
    modulus_ble_settings_disconnect();
}

uint8_t modulus_wireless_ble_passkey_state(void)
{
    return modulus_ble_settings_passkey_state();
}

uint32_t modulus_wireless_ble_passkey_value(void)
{
    return modulus_ble_settings_passkey_value();
}

bool modulus_wireless_ble_passkey_submit(uint32_t passkey)
{
    return modulus_ble_settings_passkey_submit(passkey);
}

bool modulus_wireless_ble_passkey_confirm(void)
{
    return modulus_ble_settings_passkey_confirm();
}

void modulus_wireless_ble_passkey_cancel(void)
{
    modulus_ble_settings_passkey_cancel();
}

void modulus_wireless_ble_clear_paired(void)
{
    modulus_ble_settings_clear_paired();
}

const char *modulus_wireless_zigbee_status_text(void)
{
    if (!s_zb_on) {
        return "Off";
    }
    if (modulus_wireless_zb_hub_offline()) {
        return "Hub offline - check wiring/power";
    }
    if (!modulus_wireless_zb_link_up()) {
        return "Hub not connected";
    }
    if (modulus_wireless_zb_joined()) {
        return "Joined (NanoH2)";
    }
    return "On (not joined)";
}

const char *modulus_wireless_thread_status_text(void)
{
    if (!modulus_wireless_thread_supported()) {
        return "Not supported";
    }
    if (!s_ready) {
        return "C6 not ready";
    }
    if (!s_th_on) {
        return "Off";
    }
    if (modulus_wireless_th_attached()) {
        return "Attached (SDIO)";
    }
    return "On (detached)";
}

const char *modulus_wireless_zigbee_network_text(void)
{
    if (!s_zb_on) {
        return "Not joined";
    }
    return modulus_wireless_zb_network_text();
}

const char *modulus_wireless_thread_network_text(void)
{
    if (!s_th_on) {
        return "Detached";
    }
    return modulus_wireless_th_network_text();
}

bool modulus_wireless_zigbee_enable(void)
{
    /* Zigbee runs on the dedicated NanoH2 hub — independent of the C6 SDIO
     * transport, Wi-Fi stack, and Thread. No shared radio, no arbitration. */
    s_zb_on = true;
    modulus_nvs_set_u8("zigbee", 1);
    ESP_LOGI(TAG, "Zigbee radio on (NanoH2 UART hub)");
    /* Reboot fix: the hub network only exists after HUB_START, and joining
     * was a UI-only action — after every reboot devices looked absent until
     * the user pressed "Join network". Replay the persisted intent. */
    if (modulus_nvs_get_u8("zb_auto", 0) != 0) {
        if (modulus_wireless_zigbee_join()) {
            ESP_LOGI(TAG, "Zigbee hub auto-start (zb_auto)");
        }
    }
    return true;
}

/* Internal: close the hub network on the NanoH2, WITHOUT touching the
 * zb_auto persistence (so sleep/wake preserves intent). */
static void wireless_zigbee_stop_hub(void)
{
    modulus_wireless_zigbee_scan_stop();
    if (modulus_wireless_zb_link_up()) {
        (void)modulus_wireless_zb_leave();
    }
    s_zb_on = false;
    modulus_nvs_set_u8("zigbee", 0);
}

void modulus_wireless_zigbee_disable(void)
{
    /* Explicit user toggle-off: close the hub network AND forget the
     * auto-rejoin intent so it stays off across reboots. (Sleep uses
     * wireless_zigbee_stop_hub, which preserves zb_auto for wake.) */
    wireless_zigbee_stop_hub();
    modulus_nvs_set_u8("zb_auto", 0);
}

bool modulus_wireless_thread_supported(void)
{
#if CONFIG_MODULUS_C6_THREAD_SUPPORTED
    return true;
#else
    return false;
#endif
}

bool modulus_wireless_thread_enable(void)
{
    if (!modulus_wireless_thread_supported()) {
        ESP_LOGW(TAG, "Thread enable: not supported on this C6 image");
        return false;
    }
    if (!s_ready) {
        return false;
    }
    if (!wireless_ensure_wifi_stack_started()) {
        ESP_LOGW(TAG, "Thread enable: SDIO transport not up");
        return false;
    }
    s_th_on = true;
    modulus_nvs_set_u8("thread", 1);
    ESP_LOGI(TAG, "Thread radio on (C6 OpenThread FTD)");
    return true;
}

void modulus_wireless_thread_disable(void)
{
    modulus_wireless_thread_scan_stop();
    s_th_on = false;
    modulus_nvs_set_u8("thread", 0);
}

bool modulus_wireless_zigbee_join(void)
{
    if (!s_zb_on) {
        ESP_LOGW(TAG, "Zigbee join: radio off");
        return false;
    }
    /* Queue HUB_START on UART worker — never block LVGL with 3 s poll. */
    if (!modulus_wireless_zb_join()) {
        ESP_LOGW(TAG, "Zigbee join: UART not inited");
        return false;
    }
    /* Persist auto-rejoin — Zig UI and LVGL both go through here (was
     * LVGL-only zb_auto write → reboot left radio On / hub not joined). */
    modulus_nvs_set_u8("zb_auto", 1);
    s_zb_join_deadline_us = esp_timer_get_time() + 3000000LL;
    s_zb_join_pending = true;
    ESP_LOGI(TAG, "Zigbee join: queued (async)");
    return true;
}

bool modulus_wireless_zigbee_join_pending(void)
{
    return s_zb_join_pending;
}

void modulus_wireless_zigbee_join_poll(void)
{
    if (!s_zb_join_pending) {
        return;
    }
    if (modulus_wireless_zb_link_up() && modulus_wireless_zb_joined()) {
        s_zb_join_pending = false;
        ESP_LOGI(TAG, "Zigbee join: hub up");
        return;
    }
    if (esp_timer_get_time() >= s_zb_join_deadline_us) {
        s_zb_join_pending = false;
        ESP_LOGW(TAG, "Zigbee join: timeout (NanoH2 link / Grove / EXT5V?)");
    }
}

bool modulus_wireless_zigbee_leave(void)
{
    if (!s_zb_on) {
        return false;
    }
    modulus_wireless_zigbee_scan_stop();
    s_zb_join_pending = false;
    modulus_nvs_set_u8("zb_auto", 0);
    return modulus_wireless_zb_leave();
}

bool modulus_wireless_thread_attach(void)
{
    if (!s_th_on || !modulus_wireless_transport_up()) {
        ESP_LOGW(TAG, "Thread attach: radio off or SDIO down");
        return false;
    }
    return modulus_wireless_th_attach();
}

bool modulus_wireless_thread_detach(void)
{
    if (!s_th_on) {
        return false;
    }
    modulus_wireless_thread_scan_stop();
    return modulus_wireless_th_detach();
}

int modulus_wireless_wake_coprocessor_zi(void)
{
    return modulus_wireless_wake_coprocessor() ? 1 : 0;
}

int modulus_wireless_wifi_enable_zi(void)
{
    return modulus_wireless_wifi_enable() ? 1 : 0;
}

int modulus_wireless_ble_enable_zi(void)
{
    return modulus_wireless_ble_enable() ? 1 : 0;
}

int modulus_wireless_zigbee_enable_zi(void)
{
    return modulus_wireless_zigbee_enable() ? 1 : 0;
}

int modulus_wireless_thread_enable_zi(void)
{
    return modulus_wireless_thread_enable() ? 1 : 0;
}
