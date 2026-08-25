/*
 * Wired E-stop on M5-Bus GPIO16 (Tab5 rear 30-pin, pin 2).
 *
 * Wiring (momentary NO push button):
 *   G16 (pin 2) — button — GND (pin 1/3/5)
 *   Idle:  internal pull-up → G16 HIGH
 *   Press: button shorts to GND → G16 LOW
 *
 * Toggle latch: each debounced press flips E-stop ON/OFF (must release
 * before the next press is accepted). ON → HALT_host + soft reset (0x18);
 * OFF → HALT release + $X unlock.
 *
 * AMP contract (P3):
 *   - Pinned Core 1, priority 8 (> zig_ui pri 5, > sys_task pri 5).
 *   - Never calls into LVGL / Zig Engine paint.
 *   - modulus_espnow_bridge_halt is non-blocking (skip if ESP-NOW not up).
 *   - modulus_zig_cmd_reset/unlock only touch CNC driver (mutex + TX).
 */
#include "estop_gpio_shim.h"
#include "cnc_cmd_exports.h"
#include "transport_shim.h"
#include "tab5_hw.h"

#include <driver/gpio.h>
#include <esp_log.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

static const char *TAG = "estop_gpio";

#define ESTOP_POLL_MS     10
#define ESTOP_DEBOUNCE_MS 30
/** Above zig_ui (5) and sys_task (5); below evt_dispatch (~10) is fine. */
#define ESTOP_TASK_PRIO   8
#define ESTOP_TASK_CORE   1
#define ESTOP_STACK       2048
static bool s_started = false;
static bool s_estop_active = false;

static void estop_poll_task(void *arg)
{
    (void)arg;
    unsigned press_ms = 0;
    bool await_release = false;

    for (;;) {
        const bool pressed = gpio_get_level(TAB5_MBUS_ESTOP_GPIO) == 0;

        if (pressed) {
            if (!await_release) {
                press_ms += ESTOP_POLL_MS;
                if (press_ms >= ESTOP_DEBOUNCE_MS) {
                    await_release = true;
                    press_ms = 0;
                    s_estop_active = !s_estop_active;
                    if (s_estop_active) {
                        (void)modulus_espnow_bridge_halt(true);
                        ESP_LOGW(TAG, "wired E-stop ON — HALT + soft reset");
                        modulus_zig_cmd_reset();
                    } else {
                        (void)modulus_espnow_bridge_halt(false);
                        ESP_LOGI(TAG, "wired E-stop OFF — HALT release + unlock");
                        modulus_zig_cmd_unlock();
                    }
                }
            }
        } else {
            press_ms = 0;
            await_release = false;
        }

        vTaskDelay(pdMS_TO_TICKS(ESTOP_POLL_MS));
    }
}

void modulus_estop_gpio_init(void)
{
    if (s_started) {
        return;
    }

    gpio_config_t io = {
        .pin_bit_mask = (1ULL << TAB5_MBUS_ESTOP_GPIO),
        .mode         = GPIO_MODE_INPUT,
        .pull_up_en   = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type    = GPIO_INTR_DISABLE,
    };
    if (gpio_config(&io) != ESP_OK) {
        ESP_LOGE(TAG, "GPIO%d config failed", (int)TAB5_MBUS_ESTOP_GPIO);
        return;
    }

    if (xTaskCreatePinnedToCore(estop_poll_task, "estop_gpio", ESTOP_STACK, NULL, ESTOP_TASK_PRIO, NULL, ESTOP_TASK_CORE) != pdPASS) {
        ESP_LOGE(TAG, "poll task create failed");
        return;
    }

    s_started = true;
    ESP_LOGI(TAG, "wired E-stop toggle on M5-Bus GPIO%d (NO to GND) core=%d prio=%d",
             (int)TAB5_MBUS_ESTOP_GPIO, ESTOP_TASK_CORE, ESTOP_TASK_PRIO);
}
