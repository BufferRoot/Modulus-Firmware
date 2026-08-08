/*
 * ESP32-S3 ESP-NOW <-> UART Bridge — UART Implementation
 *
 * TX path (Tab5 -> grblHAL):
 *   espnow on_recv -> inbound queue -> inbound_worker -> uart_bridge_send() -> grblHAL
 *
 * RX path (grblHAL -> Tab5):
 *   grblHAL UART TX -> UART RX ring buffer -> uart_rx_task() -> espnow_send_to_tab5()
 *
 * Batching strategy in uart_rx_task:
 *   Up to UART_RX_BATCH_MAX (250) bytes are gathered per ESP-NOW packet.
 *   Phase 1 waits up to batch_ms for the first byte; phase 2 zero-timeout
 *   drains the UART ring until empty or the ESP-NOW payload cap.
 */
#include "uart_bridge.h"
#include "espnow_link.h"
#include "bridge_config.h"
#include "bridge_nvs.h"

#include <atomic>
#include <cstdint>

#include <driver/uart.h>
#include <driver/gpio.h>
#include <esp_log.h>
#include <esp_timer.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

static const char* TAG = "uart";

/* Max first-byte wait + read quantum so reinit pause covers in-flight uart_read. */
static constexpr uint32_t kReinitPauseMs = 50;

static uint32_t              s_baud     = UART_DEFAULT_BAUD;
static int                   s_tx_gpio  = UART_TX_GPIO;
static int                   s_rx_gpio  = UART_RX_GPIO;
static std::atomic<uint32_t> s_batch_ms{UART_RX_BATCH_MS};
static std::atomic<bool>     s_led_en{true};
static std::atomic<bool>     s_rx_paused{false};

static std::atomic<uint32_t> s_bytes_tx{0};
static std::atomic<uint32_t> s_bytes_rx{0};
static std::atomic<uint32_t> s_uart_tx_fails{0};

static esp_timer_handle_t s_led_tx_timer = nullptr;
static esp_timer_handle_t s_led_rx_timer = nullptr;

static void led_off_cb(void* arg)
{
    gpio_set_level(static_cast<gpio_num_t>(reinterpret_cast<intptr_t>(arg)), 0);
}

static void led_pulse(gpio_num_t pin, esp_timer_handle_t timer)
{
    if (!s_led_en.load(std::memory_order_relaxed) || !timer) return;
    gpio_set_level(pin, 1);
    esp_timer_stop(timer);
    esp_timer_start_once(timer, LED_PULSE_US);
}

static void activity_led_init()
{
    gpio_config_t io = {};
    io.intr_type    = GPIO_INTR_DISABLE;
    io.mode         = GPIO_MODE_OUTPUT;
    io.pin_bit_mask = (1ULL << LED_TX_GPIO) | (1ULL << LED_RX_GPIO);
    io.pull_up_en   = GPIO_PULLUP_DISABLE;
    io.pull_down_en = GPIO_PULLDOWN_DISABLE;
    gpio_config(&io);
    gpio_set_level(static_cast<gpio_num_t>(LED_TX_GPIO), 0);
    gpio_set_level(static_cast<gpio_num_t>(LED_RX_GPIO), 0);

    esp_timer_create_args_t tx_args = {};
    tx_args.callback = led_off_cb;
    tx_args.arg      = reinterpret_cast<void*>(static_cast<intptr_t>(LED_TX_GPIO));
    tx_args.name     = "led_tx_off";
    if (esp_timer_create(&tx_args, &s_led_tx_timer) != ESP_OK) {
        ESP_LOGE(TAG, "led_tx timer create failed");
        s_led_tx_timer = nullptr;
    }

    esp_timer_create_args_t rx_args = {};
    rx_args.callback = led_off_cb;
    rx_args.arg      = reinterpret_cast<void*>(static_cast<intptr_t>(LED_RX_GPIO));
    rx_args.name     = "led_rx_off";
    if (esp_timer_create(&rx_args, &s_led_rx_timer) != ESP_OK) {
        ESP_LOGE(TAG, "led_rx timer create failed");
        s_led_rx_timer = nullptr;
    }

    ESP_LOGI(TAG, "Activity LEDs: TX(send)=GPIO%d  RX(recv)=GPIO%d",
             LED_TX_GPIO, LED_RX_GPIO);
}

static void activity_led_pulse_tx()
{
    led_pulse(static_cast<gpio_num_t>(LED_TX_GPIO), s_led_tx_timer);
}

static void activity_led_pulse_rx()
{
    led_pulse(static_cast<gpio_num_t>(LED_RX_GPIO), s_led_rx_timer);
}

static void save_config();

static void load_config()
{
    bridge_nvs_t nvs = bridge_nvs_open(NVS_READONLY);
    if (!nvs.ok) return;
    nvs_handle_t h = nvs.h;

    uint32_t baud = 0;
    if (nvs_get_u32(h, NVS_KEY_BAUD, &baud) == ESP_OK && baud > 0)
        s_baud = baud;

    bool migrated = false;
    int32_t gpio = 0;
    if (nvs_get_i32(h, NVS_KEY_TX_GPIO, &gpio) == ESP_OK && gpio >= 0) {
        if (gpio == 17) { s_tx_gpio = UART_TX_GPIO; migrated = true; }
        else s_tx_gpio = static_cast<int>(gpio);
    }
    if (nvs_get_i32(h, NVS_KEY_RX_GPIO, &gpio) == ESP_OK && gpio >= 0) {
        if (gpio == 18) { s_rx_gpio = UART_RX_GPIO; migrated = true; }
        else s_rx_gpio = static_cast<int>(gpio);
    }

    uint32_t batch = 0;
    if (nvs_get_u32(h, NVS_KEY_BATCH_MS, &batch) == ESP_OK &&
        batch >= 1 && batch <= 20) {
        s_batch_ms.store(batch, std::memory_order_relaxed);
    }

    uint8_t led = 1;
    if (nvs_get_u8(h, NVS_KEY_LED_EN, &led) == ESP_OK) {
        s_led_en.store(led != 0, std::memory_order_relaxed);
    }

    bridge_nvs_close(&nvs);
    if (migrated) {
        ESP_LOGI(TAG, "Migrated UART GPIOs from WROOM defaults (17/18) -> MINI-1 (8/9)");
        save_config();
    }
}

static void save_config()
{
    bridge_nvs_t nvs = bridge_nvs_open(NVS_READWRITE);
    if (!nvs.ok) return;
    esp_err_t err = nvs_set_u32(nvs.h, NVS_KEY_BAUD, s_baud);
    if (err == ESP_OK) err = nvs_set_i32(nvs.h, NVS_KEY_TX_GPIO, static_cast<int32_t>(s_tx_gpio));
    if (err == ESP_OK) err = nvs_set_i32(nvs.h, NVS_KEY_RX_GPIO, static_cast<int32_t>(s_rx_gpio));
    if (err == ESP_OK) err = nvs_set_u32(nvs.h, NVS_KEY_BATCH_MS,
                                         s_batch_ms.load(std::memory_order_relaxed));
    if (err == ESP_OK) {
        err = nvs_set_u8(nvs.h, NVS_KEY_LED_EN,
                         s_led_en.load(std::memory_order_relaxed) ? 1 : 0);
    }
    if (err == ESP_OK) err = nvs_commit(nvs.h);
    bridge_nvs_close(&nvs);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "save_config: %s", esp_err_to_name(err));
    }
}

static void uart_install(uint32_t baud, int tx, int rx)
{
    uart_driver_delete(UART_PORT_NUM);

    uart_config_t cfg = {};
    cfg.baud_rate = static_cast<int>(baud);
    cfg.data_bits = UART_DATA_8_BITS;
    cfg.parity = UART_PARITY_DISABLE;
    cfg.stop_bits = UART_STOP_BITS_1;
    cfg.flow_ctrl = UART_HW_FLOWCTRL_DISABLE;
    cfg.rx_flow_ctrl_thresh = 0;
    /* XTAL clock (40 MHz crystal) is decoupled from the APB bus.
     * UART_SCLK_DEFAULT (APB) can shift during WiFi TX bursts and
     * cause framing errors at 921600 baud. XTAL is rock-solid. */
    cfg.source_clk = UART_SCLK_XTAL;

    ESP_ERROR_CHECK(uart_param_config(UART_PORT_NUM, &cfg));
    ESP_ERROR_CHECK(uart_set_pin(UART_PORT_NUM, tx, rx,
                                 UART_RTS_GPIO, UART_CTS_GPIO));
    ESP_ERROR_CHECK(uart_driver_install(UART_PORT_NUM,
                                        UART_RX_BUF_SIZE,
                                        UART_TX_BUF_SIZE,
                                        0, NULL, 0));

    ESP_LOGI(TAG, "UART%d  %lu baud  TX=GPIO%d  RX=GPIO%d",
             UART_PORT_NUM, static_cast<unsigned long>(baud), tx, rx);
}

static int uart_drain_rx(uint8_t* buf, int have, int cap)
{
    while (have < cap) {
        int got = uart_read_bytes(UART_PORT_NUM, buf + have, cap - have, 0);
        if (got <= 0) break;
        have += got;
    }
    return have;
}

static void uart_rx_task(void* arg)
{
    (void)arg;
    uint8_t buf[UART_RX_BATCH_MAX];

    while (true) {
        while (s_rx_paused.load(std::memory_order_acquire)) {
            vTaskDelay(pdMS_TO_TICKS(10));
        }

        espnow_flush_pending_ack();

        const uint32_t batch_ms = s_batch_ms.load(std::memory_order_relaxed);
        int n = uart_read_bytes(UART_PORT_NUM, buf, 1, pdMS_TO_TICKS(batch_ms));
        if (n <= 0) continue;

        if (s_rx_paused.load(std::memory_order_acquire)) {
            continue;
        }

        n = uart_drain_rx(buf, n, static_cast<int>(sizeof(buf)));

        s_bytes_rx.fetch_add(static_cast<uint32_t>(n), std::memory_order_relaxed);
        ESP_LOGD(TAG, "UART RX %d bytes -> ESP-NOW", n);
        activity_led_pulse_rx();

        if (!espnow_send_to_tab5(buf, static_cast<size_t>(n))) {
            ESP_LOGW(TAG, "ESP-NOW send dropped %d UART RX bytes", n);
        }
    }
}

void uart_bridge_send(const uint8_t* data, size_t len)
{
    if (len == 0 || !data) return;
    if (s_rx_paused.load(std::memory_order_acquire)) {
        /* Driver may be mid-reinstall; drop rather than write into void. */
        s_uart_tx_fails.fetch_add(1, std::memory_order_relaxed);
        return;
    }

    size_t off = 0;
    while (off < len) {
        const int n = uart_write_bytes(UART_PORT_NUM, data + off, len - off);
        if (n <= 0) {
            s_uart_tx_fails.fetch_add(1, std::memory_order_relaxed);
            ESP_LOGW(TAG, "uart_write_bytes failed at offset %u", static_cast<unsigned>(off));
            return;
        }
        off += static_cast<size_t>(n);
    }

    s_bytes_tx.fetch_add(static_cast<uint32_t>(off), std::memory_order_relaxed);
    activity_led_pulse_tx();
    ESP_LOGD(TAG, "UART TX %u bytes -> grblHAL", static_cast<unsigned>(off));
}

void uart_bridge_reinit(uint32_t baud, int tx_gpio, int rx_gpio)
{
    /* Pause RX task so uart_driver_delete is not racing uart_read_bytes. */
    s_rx_paused.store(true, std::memory_order_release);
    vTaskDelay(pdMS_TO_TICKS(kReinitPauseMs));

    s_baud    = baud;
    s_tx_gpio = tx_gpio;
    s_rx_gpio = rx_gpio;
    save_config();
    uart_install(s_baud, s_tx_gpio, s_rx_gpio);

    s_rx_paused.store(false, std::memory_order_release);
    ESP_LOGI(TAG, "UART reconfigured: %lu baud TX=%d RX=%d",
             static_cast<unsigned long>(s_baud), s_tx_gpio, s_rx_gpio);
}

void uart_bridge_mpg_activate()
{
    static const uint8_t mpg_toggle = 0x8B;
    uart_bridge_send(&mpg_toggle, 1);
    ESP_LOGI(TAG, "Sent 0x8B - MPG mode activation request");
}

void uart_bridge_init()
{
    load_config();
    uart_install(s_baud, s_tx_gpio, s_rx_gpio);

    /*
     * RX task on Core 1 — keeps UART I/O off Core 0 where the WiFi /
     * ESP-NOW stack lives.  Priority 7 sits just above the default task
     * priority (5) ensuring the task drains the UART ring buffer promptly.
     *
     * NOTE: 0x8B (CMD_MPG_MODE_TOGGLE) is NOT sent here.
     * The Tab5 owns the MPG mode lifecycle and sends 0x8B when it
     * connects.  The S3 bridge is a transparent relay only.
     */
    activity_led_init();
    espnow_start_inbound_worker();
    xTaskCreatePinnedToCore(uart_rx_task, "uart_rx",
                            4096, NULL, 7, NULL, 1);
    printf("  UART%d  %lu baud  TX=GPIO%d  RX=GPIO%d\r\n",
           UART_PORT_NUM, static_cast<unsigned long>(s_baud), s_tx_gpio, s_rx_gpio);
    if (s_baud == 115200) {
        printf("  Tip: run 'baud 921600' here + match grblHAL USART6 for max throughput\r\n");
    }
    printf("  UART batch trigger: %lu ms  LEDs: %s\r\n\r\n",
           static_cast<unsigned long>(s_batch_ms.load(std::memory_order_relaxed)),
           s_led_en.load(std::memory_order_relaxed) ? "on" : "off");
}

uint32_t uart_bridge_baud()     { return s_baud; }
int      uart_bridge_tx_gpio()  { return s_tx_gpio; }
int      uart_bridge_rx_gpio()  { return s_rx_gpio; }
uint32_t uart_bridge_bytes_tx() { return s_bytes_tx.load(std::memory_order_relaxed); }
uint32_t uart_bridge_bytes_rx() { return s_bytes_rx.load(std::memory_order_relaxed); }
uint32_t uart_bridge_uart_tx_fails() { return s_uart_tx_fails.load(std::memory_order_relaxed); }

size_t uart_bridge_rx_buffered()
{
    size_t n = 0;
    if (uart_get_buffered_data_len(UART_PORT_NUM, &n) != ESP_OK) return 0;
    return n;
}

uint32_t uart_bridge_batch_ms()
{
    return s_batch_ms.load(std::memory_order_relaxed);
}

void uart_bridge_set_batch_ms(uint32_t ms)
{
    if (ms < 1) ms = 1;
    if (ms > 20) ms = 20;
    s_batch_ms.store(ms, std::memory_order_relaxed);
    save_config();
}

bool uart_bridge_led_enabled()
{
    return s_led_en.load(std::memory_order_relaxed);
}

void uart_bridge_set_led_enabled(bool on)
{
    s_led_en.store(on, std::memory_order_relaxed);
    if (!on) {
        gpio_set_level(static_cast<gpio_num_t>(LED_TX_GPIO), 0);
        gpio_set_level(static_cast<gpio_num_t>(LED_RX_GPIO), 0);
    }
    save_config();
}

bool uart_bridge_self_check()
{
    if (!uart_is_driver_installed(UART_PORT_NUM)) return false;
    if (s_tx_gpio < 0 || s_rx_gpio < 0) return false;
    return true;
}

void uart_bridge_reset_stats()
{
    s_bytes_tx.store(0, std::memory_order_relaxed);
    s_bytes_rx.store(0, std::memory_order_relaxed);
    s_uart_tx_fails.store(0, std::memory_order_relaxed);
}
