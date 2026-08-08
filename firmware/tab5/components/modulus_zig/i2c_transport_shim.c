/*
 * I2C CNC transport — Port A ext bus (GPIO 53 SDA / 54 SCL), register framing.
 */
#include "transport_shim.h"
#include "mbus_shim.h"

#include "driver/i2c_master.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

#include <string.h>

static const char *TAG = "i2c_transport";

static bool s_open = false;
static i2c_master_dev_handle_t s_dev = NULL;
static TaskHandle_t s_poll_task = NULL;
static uint8_t s_addr = 0x50;

static void join_worker_task(TaskHandle_t *task)
{
    if (!task || !*task) {
        return;
    }
    for (int i = 0; i < 20; i++) {
        const eTaskState st = eTaskGetState(*task);
        if (st == eDeleted || st == eInvalid) {
            break;
        }
        vTaskDelay(pdMS_TO_TICKS(10));
    }
    *task = NULL;
}

static void i2c_poll_task(void *arg)
{
    (void)arg;
    uint8_t hdr[2];
    uint8_t buf[256];
    while (s_open) {
        vTaskDelay(pdMS_TO_TICKS(20));
        if (!s_dev) {
            continue;
        }
        if (i2c_master_receive(s_dev, hdr, 2, 100) != ESP_OK) {
            continue;
        }
        uint16_t len = ((uint16_t)hdr[0] << 8) | hdr[1];
        if (len == 0 || len > 256) {
            continue;
        }
        if (i2c_master_receive(s_dev, buf, len, 100) == ESP_OK) {
            modulus_zig_serial_rx(buf, len);
        }
    }
    vTaskDelete(NULL);
}

bool modulus_i2c_transport_start(uint8_t addr, uint8_t spd_idx)
{
    if (s_open) {
        modulus_i2c_transport_stop();
    }
    static const uint32_t speeds[] = {100000, 400000, 1000000};
    uint32_t hz = (spd_idx < 3) ? speeds[spd_idx] : 400000;
    s_addr = addr;

    if (!modulus_mbus_port_a_ensure()) {
        ESP_LOGE(TAG, "Port A I2C bus unavailable");
        return false;
    }
    i2c_master_bus_handle_t bus = modulus_mbus_port_a_bus();
    if (!bus) {
        return false;
    }

    i2c_device_config_t dev_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = s_addr,
        .scl_speed_hz = hz,
    };
    if (i2c_master_bus_add_device(bus, &dev_cfg, &s_dev) != ESP_OK) {
        ESP_LOGE(TAG, "add_device failed");
        return false;
    }

    s_open = true;
    if (s_poll_task == NULL) {
        (void)xTaskCreatePinnedToCore(i2c_poll_task, "i2c_tx_rx", 3072, NULL, 6, &s_poll_task, 1);
    }
    modulus_zig_transport_on_connect();
    ESP_LOGI(TAG, "I2C transport 0x%02X @ %lu Hz (Port A)", s_addr, (unsigned long)hz);
    return true;
}

void modulus_i2c_transport_stop(void)
{
    if (!s_open) {
        return;
    }
    s_open = false;
    join_worker_task(&s_poll_task);
    if (s_dev) {
        i2c_master_bus_rm_device(s_dev);
        s_dev = NULL;
    }
    modulus_zig_transport_on_disconnect();
}

bool modulus_i2c_transport_send(const uint8_t *data, size_t len)
{
    if (!s_open || !s_dev || !data || len == 0 || len > 256) {
        return false;
    }
    uint8_t frame[258];
    frame[0] = (uint8_t)(len >> 8);
    frame[1] = (uint8_t)(len & 0xFF);
    memcpy(frame + 2, data, len);
    return i2c_master_transmit(s_dev, frame, len + 2, 100) == ESP_OK;
}
