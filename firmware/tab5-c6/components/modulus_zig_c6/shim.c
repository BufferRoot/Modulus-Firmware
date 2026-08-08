/*
 * Modulus C6 runtime — delegates to Zig when CONFIG_MODULUS_ZIG_C6_RUNTIME=y.
 */
#include "modulus_c6_runtime.h"

#include "modulus_bridge_c6.h"
#include "modulus_c6_ble.h"
#include "modulus_c6_espnow.h"
#include "modulus_c6_thread.h"
#include "modulus_c6_zigbee.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "modulus_c6_rt";

#define MODULUS_C6_ZIG_TASK_STACK 4096
#define MODULUS_C6_ZIG_TASK_PRIO  1

static void modulus_c6_zig_task(void *arg)
{
    (void)arg;
    modulus_c6_runtime_start();
}

#if CONFIG_MODULUS_ZIG_C6_RUNTIME
extern void modulus_c6_main(void);
#endif

void modulus_c6_runtime_start_task(void)
{
#if CONFIG_MODULUS_ZIG_C6_RUNTIME
    BaseType_t ok = xTaskCreate(
        modulus_c6_zig_task,
        "modulus_zig",
        MODULUS_C6_ZIG_TASK_STACK,
        NULL,
        MODULUS_C6_ZIG_TASK_PRIO,
        NULL);
    if (ok != pdPASS) {
        ESP_LOGE(TAG, "failed to create Modulus Zig task");
    }
#else
    ESP_LOGW(TAG, "Zig runtime disabled — enable CONFIG_MODULUS_ZIG_C6_RUNTIME");
#endif
}

void modulus_c6_runtime_start(void)
{
#if CONFIG_MODULUS_ZIG_C6_RUNTIME
    ESP_LOGI(TAG, "entering Zig coprocessor runtime");
    modulus_c6_ble_init();
    modulus_c6_espnow_init();
    modulus_c6_thread_init();
    modulus_c6_zigbee_init();
    modulus_bridge_c6_set_hal_ready(true);
    modulus_c6_main();
#else
    ESP_LOGI(TAG, "Zig runtime disabled — enable CONFIG_MODULUS_ZIG_C6_RUNTIME");
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(5000));
        ESP_LOGI(TAG, "C6 runtime stub (Zig off)");
    }
#endif
}
