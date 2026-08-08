/*
 * FreeRTOS event queue for Modulus Zig event_bus (Core 0 dispatch, cross-core publish).
 */
#include "event_shim.h"

#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <string.h>

static QueueHandle_t s_queue = NULL;

void modulus_event_init(void)
{
    if (s_queue != NULL) {
        return;
    }
    s_queue = xQueueCreate(MODULUS_EVENT_QUEUE_LEN, sizeof(modulus_event_msg_t));
}

bool modulus_event_publish(uint16_t id, const uint8_t *data, uint32_t len)
{
    if (s_queue == NULL) {
        return false;
    }

    modulus_event_msg_t msg = {0};
    msg.id = id;
    if (data != NULL && len > 0) {
        uint32_t copy_len = len;
        if (copy_len > MODULUS_EVENT_DATA_MAX) {
            copy_len = MODULUS_EVENT_DATA_MAX;
        }
        memcpy(msg.data, data, copy_len);
        msg.data_len = copy_len;
    }

    /* Non-blocking: publishers include Core 1 sys_task (10 ms CNC tick) — the
     * previous 100 ms block on a full queue stalled CNC poll/jog for 10 ticks.
     * Drop-when-full matches the Zig event_bus contract; a full queue means the
     * pri-10 dispatch task is starving, which blocking cannot fix. */
    return xQueueSend(s_queue, &msg, 0) == pdTRUE;
}

bool modulus_event_receive(modulus_event_msg_t *out)
{
    if (s_queue == NULL || out == NULL) {
        return false;
    }
    return xQueueReceive(s_queue, out, portMAX_DELAY) == pdTRUE;
}
