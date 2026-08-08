/*
 * RS-485 / UART bridge for Modulus Zig serial HAL.
 * Tab5: SIT3088 on UART1 TX20/RX21/DE34 (half-duplex RS-485).
 */
#include "serial_shim.h"
#include "tab5_hw.h"

#include <driver/gpio.h>
#include <driver/uart.h>
#include <esp_err.h>
#include <esp_log.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

static const char *TAG = "modulus_serial";

#define RS485_TX_PIN ((gpio_num_t)TAB5_RS485_TX_GPIO)
#define RS485_RX_PIN ((gpio_num_t)TAB5_RS485_RX_GPIO)
#define RS485_DE_PIN ((gpio_num_t)TAB5_RS485_DE_GPIO)
#define UART_RX_BUF 512
#define UART_TX_BUF 0

static bool s_open = false;
static uart_port_t s_uart_num = UART_NUM_1;
static volatile TaskHandle_t s_rx_task = NULL;
static volatile bool s_rx_stop = false;
static modulus_serial_rx_fn s_rx_handler = NULL;

#define RX_READ_BUF 256

static void serial_rx_task(void *arg)
{
    (void)arg;
    uint8_t buf[RX_READ_BUF];
    ESP_LOGI(TAG, "RX task started on UART%d (pri 6)", (int)s_uart_num);

    while (!s_rx_stop) {
        const int len = uart_read_bytes(s_uart_num, buf, sizeof(buf), pdMS_TO_TICKS(20));
        if (len > 0) {
            if (s_rx_handler) {
                s_rx_handler(buf, (size_t)len);
            }
        } else if (len < 0) {
            ESP_LOGW(TAG, "UART read error");
            vTaskDelay(pdMS_TO_TICKS(50));
        }
    }

    /* Self-delete: the task can never be destroyed while holding the UART
     * driver's internal rx mutex or mid-RX-handler (vTaskDelete from another
     * task could do both -> wedged driver / corrupt engine feed). */
    s_rx_task = NULL;
    vTaskDelete(NULL);
}

static void start_rx_task(void)
{
    if (s_rx_task != NULL) {
        return;
    }
    s_rx_stop = false;
    TaskHandle_t handle = NULL;
    (void)xTaskCreatePinnedToCore(serial_rx_task, "serial_rx", 3072, NULL, 6, &handle, 1);
    s_rx_task = handle;
}

static void stop_rx_task(void)
{
    if (s_rx_task == NULL) {
        return;
    }
    s_rx_stop = true;
    /* Bounded wait: read timeout is 20 ms; exceed -> force delete to avoid
     * uart_driver_delete/install deadlock wedging Core 1 transport reinit. */
    const TickType_t deadline = xTaskGetTickCount() + pdMS_TO_TICKS(500);
    while (s_rx_task != NULL && xTaskGetTickCount() < deadline) {
        vTaskDelay(pdMS_TO_TICKS(5));
    }
    if (s_rx_task != NULL) {
        /* Do not vTaskDelete from outside: races self-delete (freed TCB) and
         * can wedge uart driver if mid-read. Leave cooperative stop flag set;
         * next open waits again. Leak one stuck task only if UART hung. */
        ESP_LOGW(TAG, "RX task stop timeout — leave cooperative stop (no force delete)");
        return;
    }
    s_rx_stop = false;
}

void modulus_serial_set_rx_handler(modulus_serial_rx_fn handler)
{
    s_rx_handler = handler;
}

static uart_word_length_t map_data_bits(uint8_t bits)
{
    return (bits == 7) ? UART_DATA_7_BITS : UART_DATA_8_BITS;
}

static uart_parity_t map_parity(uint8_t p)
{
    switch (p) {
    case 1:
        return UART_PARITY_EVEN;
    case 2:
        return UART_PARITY_ODD;
    default:
        return UART_PARITY_DISABLE;
    }
}

static uart_stop_bits_t map_stop_bits(uint8_t s)
{
    return (s >= 2) ? UART_STOP_BITS_2 : UART_STOP_BITS_1;
}

bool modulus_serial_open(uint8_t port, uint32_t baud, uint8_t data_bits, uint8_t parity,
                         uint8_t stop_bits)
{
    if (s_open) {
        modulus_serial_close();
    }

    s_uart_num = (port == 0) ? UART_NUM_1 : UART_NUM_0;

    uart_config_t ucfg = {
        .baud_rate = (int)baud,
        .data_bits = map_data_bits(data_bits),
        .parity = map_parity(parity),
        .stop_bits = map_stop_bits(stop_bits),
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .rx_flow_ctrl_thresh = 122,
        .source_clk = UART_SCLK_DEFAULT,
    };

    esp_err_t err = uart_driver_install(s_uart_num, UART_RX_BUF, UART_TX_BUF, 0, NULL, 0);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "uart_driver_install failed: %s", esp_err_to_name(err));
        return false;
    }

    err = uart_param_config(s_uart_num, &ucfg);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "uart_param_config failed: %s", esp_err_to_name(err));
        uart_driver_delete(s_uart_num);
        return false;
    }

    if (port == 0) {
        err = uart_set_pin(s_uart_num, RS485_TX_PIN, RS485_RX_PIN, RS485_DE_PIN, UART_PIN_NO_CHANGE);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "uart_set_pin failed: %s", esp_err_to_name(err));
            uart_driver_delete(s_uart_num);
            return false;
        }
        err = uart_set_mode(s_uart_num, UART_MODE_RS485_HALF_DUPLEX);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "uart_set_mode failed: %s", esp_err_to_name(err));
            uart_driver_delete(s_uart_num);
            return false;
        }
        err = uart_set_rx_timeout(s_uart_num, 3);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "uart_set_rx_timeout failed: %s", esp_err_to_name(err));
            uart_driver_delete(s_uart_num);
            return false;
        }
    } else {
        err = uart_set_pin(s_uart_num, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE,
                           UART_PIN_NO_CHANGE);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "uart_set_pin failed: %s", esp_err_to_name(err));
            uart_driver_delete(s_uart_num);
            return false;
        }
    }

    s_open = true;
    start_rx_task();
    ESP_LOGI(TAG, "Opened %s @ %lu baud (%u%c%u)", (port == 0) ? "RS-485" : "Serial USB",
             (unsigned long)baud, data_bits, (parity == 0) ? 'N' : (parity == 1) ? 'E' : 'O',
             stop_bits);
    return true;
}

void modulus_serial_close(void)
{
    if (!s_open) {
        return;
    }
    stop_rx_task();
    if (s_rx_task != NULL) {
        /* RX still alive after timeout — deleting UART under it is unsafe. */
        ESP_LOGE(TAG, "close aborted: RX task still running");
        return;
    }
    uart_driver_delete(s_uart_num);
    s_open = false;
    ESP_LOGI(TAG, "Port closed (UART%d)", (int)s_uart_num);
}

bool modulus_serial_is_open(void)
{
    return s_open;
}

int modulus_serial_write(const uint8_t *data, size_t len)
{
    if (!s_open || !data || len == 0) {
        return -1;
    }
    return uart_write_bytes(s_uart_num, data, len);
}

int modulus_serial_read(uint8_t *buf, size_t max_len)
{
    if (!s_open || !buf || max_len == 0) {
        return -1;
    }
    return uart_read_bytes(s_uart_num, buf, max_len, 0);
}
