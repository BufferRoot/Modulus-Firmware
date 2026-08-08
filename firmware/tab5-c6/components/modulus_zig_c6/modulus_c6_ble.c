/*
 * Phase 9 — BLE on C6 via esp_hosted HCI controller (not NimBLE host on slave).
 * Controller init/enable is host-driven only: P4 esp_hosted_bt_controller_* RPC
 * -> slave_bt.c init_bluetooth/enable_bluetooth. Do not call those locally.
 * GAP name "MODULUS_TAB5" is set on P4 NimBLE host (modulus_ble_periph).
 */
#include "modulus_c6_ble.h"

#include "esp_log.h"
#include "sdkconfig.h"

#if CONFIG_MODULUS_C6_BLE && CONFIG_BT_ENABLED
#include "esp_bt.h"
#endif

static const char *TAG = "modulus_c6_ble";

static bool s_init_attempted;
static uint8_t s_status; /* 0 off, 1 ready, 2 error */

void modulus_c6_ble_init(void)
{
    if (s_init_attempted) {
        return;
    }
    s_init_attempted = true;

#if !CONFIG_MODULUS_C6_BLE
    ESP_LOGI(TAG, "BLE disabled (CONFIG_MODULUS_C6_BLE=n)");
    return;
#elif !CONFIG_BT_ENABLED
    ESP_LOGI(TAG, "BLE unavailable (CONFIG_BT_ENABLED=n on slave)");
    return;
#else
    ESP_LOGI(TAG, "BLE HCI slave ready for P4 RPC (no local init_bluetooth)");
    if (esp_bt_controller_get_status() == ESP_BT_CONTROLLER_STATUS_ENABLED) {
        s_status = 1;
    }
#endif
}

bool modulus_c6_ble_ready(void)
{
#if CONFIG_MODULUS_C6_BLE && CONFIG_BT_ENABLED
    if (esp_bt_controller_get_status() == ESP_BT_CONTROLLER_STATUS_ENABLED) {
        s_status = 1;
        return true;
    }
#endif
    return s_status == 1;
}

uint8_t modulus_c6_ble_status(void)
{
#if CONFIG_MODULUS_C6_BLE && CONFIG_BT_ENABLED
    if (esp_bt_controller_get_status() == ESP_BT_CONTROLLER_STATUS_ENABLED) {
        s_status = 1;
    }
#endif
    return s_status;
}
