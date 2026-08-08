/*
 * P4 NimBLE host over esp_hosted VHCI (C6 BLE HCI controller).
 */
#include "wireless_shim.h"

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
static uint8_t s_status;

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
    ESP_LOGI(TAG, "NimBLE host ready (VHCI)");
}

bool modulus_ble_host_ensure(void)
{
    if (s_status == 1) {
        return true;
    }
    if (s_init_attempted && s_status == 2) {
        return false;
    }
    if (!modulus_wireless_transport_up()) {
        if (!modulus_wireless_wifi_enable() && !modulus_wireless_espnow_enable()) {
            ESP_LOGW(TAG, "SDIO transport down — enable Wi-Fi or ESP-NOW first");
            return false;
        }
    }

    if (!s_init_attempted) {
        s_init_attempted = true;
        /* SDIO reset + boot delay owned by wireless_shim / esp_hosted — no GPIO15 here. */
        esp_err_t err = ble_hosted_controller_up();
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "hosted BT controller: %s", esp_err_to_name(err));
            s_status = 2;
            return false;
        }
        err = nimble_port_init();
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "nimble_port_init: %s", esp_err_to_name(err));
            s_status = 2;
            return false;
        }
        ble_hs_cfg.reset_cb = ble_on_reset;
        ble_hs_cfg.sync_cb = ble_on_sync;
        ble_hs_cfg.store_status_cb = ble_store_util_status_rr;
        (void)ble_svc_gap_device_name_set("MODULUS_TAB5");
        ble_store_config_init();
        nimble_port_freertos_init(ble_host_task);
    }

    for (int i = 0; i < 50 && s_status == 0; i++) {
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    return s_status == 1;
}

bool modulus_ble_host_ready(void)
{
    return s_status == 1 && ble_hs_synced();
}

#else

bool modulus_ble_host_ensure(void) { return false; }
bool modulus_ble_host_ready(void) { return false; }

#endif
