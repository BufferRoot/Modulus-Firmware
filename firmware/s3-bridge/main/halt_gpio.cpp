#include "halt_gpio.h"
#include "bridge_board.h"

#include <atomic>

#include <driver/gpio.h>
#include <esp_log.h>

static const char *TAG = "halt_gpio";
static std::atomic<bool> s_asserted{false};
static int s_pin = -1;

static void configure_pin(int pin)
{
    gpio_config_t io = {};
    io.pin_bit_mask = (1ULL << pin);
    io.mode         = GPIO_MODE_OUTPUT;
    io.pull_up_en   = GPIO_PULLUP_DISABLE;
    io.pull_down_en = GPIO_PULLDOWN_DISABLE;
    io.intr_type    = GPIO_INTR_DISABLE;
    gpio_config(&io);
    gpio_set_level(static_cast<gpio_num_t>(pin), s_asserted.load() ? 0 : 1);
}

void halt_gpio_init(void)
{
    halt_gpio_rebind(bridge_board_get()->halt);
}

void halt_gpio_rebind(int pin)
{
    if (s_pin >= 0 && s_pin != pin) {
        gpio_reset_pin(static_cast<gpio_num_t>(s_pin));
    }
    s_pin = pin;
    configure_pin(s_pin);
    ESP_LOGI(TAG, "HALT_host on GPIO%d (active LOW)", s_pin);
}

void halt_gpio_set(bool assert)
{
    s_asserted.store(assert, std::memory_order_relaxed);
    if (s_pin < 0) return;
    gpio_set_level(static_cast<gpio_num_t>(s_pin), assert ? 0 : 1);
}

bool halt_gpio_is_asserted(void)
{
    return s_asserted.load(std::memory_order_relaxed);
}

int halt_gpio_pin(void)
{
    return s_pin;
}
