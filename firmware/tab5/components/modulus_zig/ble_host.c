/*
 * P4 NimBLE host over esp_hosted VHCI (C6 BLE HCI controller).
 */
#include "ble_host.h"
#include "wireless_shim.h"
#include "tab5_pi4ioe.h"

#include "esp_hosted_misc.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "host/ble_hs.h"
#include "host/ble_store.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "sdkconfig.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

#include <string.h>

#if CONFIG_BT_NIMBLE_ENABLED

static const char *TAG = "ble_host";

static bool s_init_attempted;
static bool s_ctrl_up;
/* nimble_port_init() is not re-entrant and there is no safe teardown here. */
static bool s_nimble_up;
static uint8_t s_status;
static uint8_t s_hci_fail_streak;

void ble_store_config_init(void);

static esp_err_t ble_hosted_controller_up(void)
{
    esp_err_t err = esp_hosted_bt_controller_init();
    if (err == ESP_ERR_INVALID_STATE) {
        (void)esp_hosted_bt_controller_disable();
        (void)esp_hosted_bt_controller_deinit(false);
        err = esp_hosted_bt_controller_init();
    }
    if (err != ESP_OK) {
        return err;
    }
    err = esp_hosted_bt_controller_enable();
    if (err == ESP_ERR_INVALID_STATE) {
        err = ESP_OK;
    }
    if (err == ESP_OK) {
        s_ctrl_up = true;
    }
    return err;
}

static void ble_host_task(void *param)
{
    (void)param;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

static void ble_on_reset(int reason)
{
    ESP_LOGW(TAG, "NimBLE reset reason=%d", reason);
    s_status = 2;
    if (s_hci_fail_streak < 255) {
        s_hci_fail_streak++;
    }
}

static void ble_on_sync(void)
{
    if (ble_hs_util_ensure_addr(0) != 0) {
        s_status = 2;
        return;
    }
    ble_svc_gap_init();
    ble_svc_gatt_init();
    s_status = 1;
    s_hci_fail_streak = 0;
    ESP_LOGI(TAG, "NimBLE host ready (VHCI)");
}

void modulus_ble_host_reset(void)
{
    ESP_LOGW(TAG, "BLE host reset (hosted controller + NimBLE reprobe)");
    /* Tearing down a controller that was never started logs two red -1 RPC
     * failures on the C6 every bring-up. A genuinely stale controller is still
     * recovered by ble_hosted_controller_up() via ESP_ERR_INVALID_STATE. */
    if (s_ctrl_up) {
        (void)esp_hosted_bt_controller_disable();
        (void)esp_hosted_bt_controller_deinit(false);
        s_ctrl_up = false;
    }
    s_init_attempted = false;
    s_status = 0;
    s_hci_fail_streak = 0;
}

bool modulus_ble_host_ensure(void)
{
    if (s_status == 1) {
        return true;
    }
    /* Prior fail with NimBLE port already up is fatal until reboot. */
    if (s_init_attempted && s_status == 2) {
        return false;
    }
    if (s_status == 2) {
        s_status = 0;
    }
    if (!modulus_wireless_transport_up()) {
        ESP_LOGW(TAG, "SDIO transport down — BLE host deferred");
        return false;
    }

    if (!s_init_attempted) {
        s_init_attempted = true;
        tab5_pi4ioe_wait_c6_sdio_ready();
        vTaskDelay(pdMS_TO_TICKS(300));
        esp_err_t err = ble_hosted_controller_up();
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "hosted BT controller: %s", esp_err_to_name(err));
            s_status = 2;
            s_init_attempted = false;
            return false;
        }
        /* Once per boot. A controller reset leaves the NimBLE host task and its
         * queues live, so re-running ble_hs_init() re-initialises a mqueue that
         * the running task holds — the queue spinlock is never released and
         * core 0 spins until the interrupt watchdog fires. */
        if (!s_nimble_up) {
            err = nimble_port_init();
            if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
                ESP_LOGE(TAG, "nimble_port_init: %s", esp_err_to_name(err));
                s_status = 2;
                return false;
            }
            s_nimble_up = true;
            if (err == ESP_OK) {
                ble_hs_cfg.reset_cb = ble_on_reset;
                ble_hs_cfg.sync_cb = ble_on_sync;
                ble_hs_cfg.store_status_cb = ble_store_util_status_rr;
                (void)ble_svc_gap_device_name_set("MODULUS_TAB5");
                ble_store_config_init();
                nimble_port_freertos_init(ble_host_task);
            }
        } else {
            /* The port outlives every controller cycle, so the re-enabled
             * controller needs an explicit host reset to redo the HCI handshake.
             * Without it sync_cb never fires again and s_status stays 0. */
            ble_hs_sched_reset(BLE_HS_ECONTROLLER);
        }
    }

    /* C6 BT controller + VHCI — bail early if SDIO dies mid-wait. */
    for (int i = 0; i < 80 && s_status == 0; i++) {
        if (!modulus_wireless_transport_up()) {
            ESP_LOGW(TAG, "NimBLE sync aborted — SDIO down");
            modulus_ble_host_reset();
            return false;
        }
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    if (s_status != 1) {
        ESP_LOGW(TAG, "NimBLE sync timeout (status=%u)", (unsigned)s_status);
        modulus_ble_host_reset();
        return false;
    }
    return true;
}

bool modulus_ble_host_ready(void)
{
    return s_status == 1 && ble_hs_synced();
}

bool modulus_ble_host_failed(void)
{
    /* HCI timeout streak (SDIO dead) or hard fail after init. */
    return s_status == 2 || s_hci_fail_streak >= 2;
}

#else

bool modulus_ble_host_ensure(void) { return false; }
bool modulus_ble_host_ready(void) { return false; }
bool modulus_ble_host_failed(void) { return true; }
void modulus_ble_host_reset(void) {}

#endif
