/*
 * Phase 8c — invoke Modulus after esp_hosted_coprocessor_init() (hosted app_main).
 * Keeps upstream SDIO/Wi-Fi transport in C. Zig C6 runtime is opt-in only.
 */
#include "modulus_c6_hosted_hook.h"

#include "modulus_c6_ble.h"
#include "modulus_c6_espnow.h"
#include "modulus_c6_thread.h"
#include "modulus_c6_zigbee.h"
#include "modulus_c6_runtime.h"
#include "esp_log.h"
#include "sdkconfig.h"

static const char *TAG = "modulus_c6_hosted";

void modulus_c6_hosted_after_init(void)
{
    ESP_LOGI(TAG, "esp_hosted slave up - Modulus radio hooks");
    /* C policy stubs / BLE HCI — run even when Zig runtime is off. */
    modulus_c6_ble_init();
    modulus_c6_espnow_init();
#if CONFIG_OPENTHREAD_ENABLED
    /* SDIO thread_handler.c owns OpenThread — do not start modulus_c6_thread. */
    ESP_LOGI(TAG, "OpenThread owned by SDIO thread_handler — skip modulus_c6_thread_init");
#else
    modulus_c6_thread_init();
#endif
    modulus_c6_zigbee_init();

#if CONFIG_MODULUS_ZIG_C6_RUNTIME
    modulus_c6_runtime_start_task();
#else
    ESP_LOGI(TAG, "Zig C6 runtime off (C handlers only)");
#endif
}
