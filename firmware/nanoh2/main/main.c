/*
 * Modulus NanoH2 — dedicated Zigbee ZBOSS coordinator (ESP32-H2FH4S).
 * Talks to the Tab5 (P4) over the framed UART link; the 802.15.4 radio is
 * exclusively ours — no Wi-Fi silicon, no coexistence, no channel yielding.
 *
 * LED: blink = network not formed / forming; solid = formed;
 *      double-blink = formed but host link silent (P4 down or unwired).
 */
#include "nanoh2_hw.h"
#include "zb_uart_link.h"
#include "zigbee_hub.h"

#include "driver/gpio.h"
#include "esp_check.h"
#include "esp_zigbee_core.h" /* esp_zb_factory_reset */
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"

static const char *TAG = "nanoh2";

static esp_err_t board_gpio_init(void)
{
    const gpio_config_t out = {
        .pin_bit_mask = (1ULL << NANOH2_GPIO_LED) | (1ULL << NANOH2_GPIO_RGB_EN) |
                        (1ULL << NANOH2_GPIO_IR),
        .mode = GPIO_MODE_OUTPUT,
    };
    ESP_RETURN_ON_ERROR(gpio_config(&out), TAG, "out gpio");
    gpio_set_level(NANOH2_GPIO_RGB_EN, 0); /* WS2812 rail off */
    gpio_set_level(NANOH2_GPIO_IR, 0);
    gpio_set_level(NANOH2_GPIO_LED, 0);

    const gpio_config_t btn = {
        .pin_bit_mask = (1ULL << NANOH2_GPIO_BTN),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
    };
    ESP_RETURN_ON_ERROR(gpio_config(&btn), TAG, "btn gpio");
    return ESP_OK;
}

void app_main(void)
{
    ESP_LOGI(TAG, "Modulus NanoH2 Zigbee hub — ESP32-H2FH4S (dedicated 802.15.4)");
    ESP_ERROR_CHECK(board_gpio_init());

    /* ZBOSS persists network state in NVS + zb_storage. */
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ESP_ERROR_CHECK(nvs_flash_init());
    }

    zb_uart_link_init(zigbee_hub_process_cmd);

    /* Dedicated hub: form/rejoin at boot instead of waiting ~80 s for the
     * P4 to come up and send HUB_START. HUB_START stays idempotent. */
    zigbee_hub_start(0);

    /* Hold BUTTON >3 s at runtime -> factory reset the Zigbee network. */
    int btn_held_ms = 0;
    uint32_t tick = 0;
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(100));
        tick++;
        zigbee_hub_poll();

        if (gpio_get_level(NANOH2_GPIO_BTN) == 0) {
            btn_held_ms += 100;
            if (btn_held_ms == 3000) {
                ESP_LOGW(TAG, "Button held 3 s — Zigbee factory reset + reboot");
                esp_zb_factory_reset(); /* erases zb_storage, reboots */
            }
        } else {
            btn_held_ms = 0;
        }

        /* LED pattern (100 ms tick): solid=formed, blink=forming,
         * double-blink=formed but host link down. */
        bool led;
        if (zigbee_hub_formed()) {
            led = zb_uart_link_host_alive() ? true : ((tick & 7) < 2 && (tick & 1));
        } else {
            led = (tick & 7) < 4;
        }
        gpio_set_level(NANOH2_GPIO_LED, led);
    }
}
