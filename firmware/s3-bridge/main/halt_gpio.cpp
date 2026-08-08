/*

 * grblHAL HALT_host — GPIO37 on ESP32-S3-MINI-1 handwheel board.

 * Active LOW with pull-up on the Flexi-HAL host side.

 */

#include "halt_gpio.h"

#include "bridge_config.h"



#include <atomic>



#include <driver/gpio.h>

#include <esp_log.h>



static const char *TAG = "halt_gpio";

static std::atomic<bool> s_asserted{false};



void halt_gpio_init(void)

{

    gpio_config_t io = {};

    io.pin_bit_mask = (1ULL << HALT_HOST_GPIO);

    io.mode         = GPIO_MODE_OUTPUT;

    io.pull_up_en   = GPIO_PULLUP_DISABLE;

    io.pull_down_en = GPIO_PULLDOWN_DISABLE;

    io.intr_type    = GPIO_INTR_DISABLE;

    gpio_config(&io);

    halt_gpio_set(false);

    ESP_LOGI(TAG, "HALT_host on GPIO%d (active LOW)", HALT_HOST_GPIO);

}



void halt_gpio_set(bool assert)

{

    s_asserted.store(assert, std::memory_order_relaxed);

    gpio_set_level(static_cast<gpio_num_t>(HALT_HOST_GPIO), assert ? 0 : 1);

    ESP_LOGI(TAG, "HALT_host %s", assert ? "ASSERTED" : "released");

}



bool halt_gpio_is_asserted(void)

{

    return s_asserted.load(std::memory_order_relaxed);

}


