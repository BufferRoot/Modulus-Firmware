/*
 * Zig <-> C bridge for ESP32-C6 Modulus coprocessor (minimal — no P4 HAL).
 */
#include "modulus_bridge_c6.h"

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "modulus_c6";
static bool s_hal_ready;

void modulus_bridge_c6_set_hal_ready(bool ready)
{
    s_hal_ready = ready;
}

bool modulus_bridge_c6_hal_ready(void)
{
    return s_hal_ready;
}

void modulus_bridge_c6_delay_ms(uint32_t ms)
{
    vTaskDelay(pdMS_TO_TICKS(ms));
}

void modulus_bridge_c6_log_info(const char *msg)
{
    ESP_LOGI(TAG, "%s", msg);
}

void modulus_bridge_c6_log_heartbeat(uint32_t tick)
{
    ESP_LOGI(TAG, "heartbeat %lu", (unsigned long)tick);
}
