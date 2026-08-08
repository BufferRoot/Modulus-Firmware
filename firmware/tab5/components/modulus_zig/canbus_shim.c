/*
 * CAN bus CNC transport — TWAI on Port A G54 TX / G53 RX (same pins as I2C1).
 */
#include "transport_shim.h"
#include "tab5_hw.h"

#include "driver/gpio.h"
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wcpp"
#include "driver/twai.h"
#pragma GCC diagnostic pop
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <string.h>

static const char *TAG = "canbus";

static bool s_open = false;
static TaskHandle_t s_rx_task = NULL;
static uint32_t s_node_id = 1;

static uint8_t s_rx_buf[512];
static uint16_t s_rx_len = 0;

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

#define SEQ_FIRST  0x80
#define SEQ_CONT   0x00
#define SEQ_LAST   0x40
#define SEQ_SINGLE 0xC0

static void can_rx_task(void *arg)
{
    (void)arg;
    twai_message_t msg;
    while (s_open) {
        if (twai_receive(&msg, pdMS_TO_TICKS(50)) != ESP_OK) {
            continue;
        }
        if (msg.data_length_code == 0) {
            continue;
        }
        uint8_t seq = msg.data[0];
        uint8_t payload_len = msg.data_length_code - 1;
        if (seq & SEQ_FIRST) {
            s_rx_len = 0;
        }
        if (s_rx_len + payload_len <= sizeof(s_rx_buf)) {
            memcpy(s_rx_buf + s_rx_len, msg.data + 1, payload_len);
            s_rx_len += payload_len;
        }
        if (seq & SEQ_LAST) {
            if (s_rx_len > 0) {
                modulus_zig_serial_rx(s_rx_buf, s_rx_len);
            }
            s_rx_len = 0;
        }
    }
    vTaskDelete(NULL);
}

bool modulus_canbus_start(uint8_t brate_idx, uint8_t nid, uint8_t mode_idx)
{
    if (s_open) {
        modulus_canbus_stop();
    }
    s_node_id = nid ? nid : 1;

    const twai_timing_config_t tcfg =
        (brate_idx == 0) ? (twai_timing_config_t)TWAI_TIMING_CONFIG_125KBITS() :
        (brate_idx == 1) ? (twai_timing_config_t)TWAI_TIMING_CONFIG_250KBITS() :
        (brate_idx == 3) ? (twai_timing_config_t)TWAI_TIMING_CONFIG_1MBITS() :
                           (twai_timing_config_t)TWAI_TIMING_CONFIG_500KBITS();

    twai_mode_t mode = TWAI_MODE_NORMAL;
    if (mode_idx == 1) {
        mode = TWAI_MODE_LISTEN_ONLY;
    } else if (mode_idx == 2) {
        mode = TWAI_MODE_NO_ACK;
    }

    twai_general_config_t gcfg =
        TWAI_GENERAL_CONFIG_DEFAULT(TAB5_PORT_A_CAN_TX_GPIO, TAB5_PORT_A_CAN_RX_GPIO, mode);
    gcfg.rx_queue_len = 32;
    gcfg.tx_queue_len = 16;
    twai_filter_config_t fcfg = TWAI_FILTER_CONFIG_ACCEPT_ALL();

    if (twai_driver_install(&gcfg, &tcfg, &fcfg) != ESP_OK) {
        ESP_LOGE(TAG, "twai_driver_install failed");
        return false;
    }
    if (twai_start() != ESP_OK) {
        twai_driver_uninstall();
        return false;
    }

    s_open = true;
    if (s_rx_task == NULL) {
        (void)xTaskCreatePinnedToCore(can_rx_task, "can_rx", 3072, NULL, 6, &s_rx_task, 1);
    }
    modulus_zig_transport_on_connect();
    ESP_LOGI(TAG, "CAN node %lu brate_idx %u mode %u", (unsigned long)s_node_id, brate_idx, mode_idx);
    return true;
}

void modulus_canbus_stop(void)
{
    if (!s_open) {
        return;
    }
    s_open = false;
    join_worker_task(&s_rx_task);
    twai_stop();
    twai_driver_uninstall();
    modulus_zig_transport_on_disconnect();
}

bool modulus_canbus_send(const uint8_t *data, size_t len)
{
    if (!s_open || !data || len == 0) {
        return false;
    }
    size_t offset = 0;
    while (offset < len) {
        size_t remaining = len - offset;
        size_t chunk = (remaining > 7) ? 7 : remaining;
        bool is_first = (offset == 0);
        bool is_last = (offset + chunk >= len);

        twai_message_t msg = {};
        msg.identifier = s_node_id;
        msg.data_length_code = (uint8_t)(chunk + 1);
        if (is_first && is_last) {
            msg.data[0] = SEQ_SINGLE;
        } else if (is_first) {
            msg.data[0] = SEQ_FIRST;
        } else if (is_last) {
            msg.data[0] = SEQ_LAST;
        } else {
            msg.data[0] = SEQ_CONT;
        }
        memcpy(msg.data + 1, data + offset, chunk);
        if (twai_transmit(&msg, pdMS_TO_TICKS(50)) != ESP_OK) {
            return false;
        }
        offset += chunk;
    }
    return true;
}
