#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MODULUS_EVENT_DATA_MAX 64
#define MODULUS_EVENT_QUEUE_LEN 16

/* Core system event IDs — C mirror of src/modulus/core/system_events.zig (0x00xx).
 * Keep values in sync with the Zig source of truth. */
#define EVT_SYSTEM_BOOT_COMPLETE 0x0001U
#define EVT_SYSTEM_SHUTDOWN      0x0002U
#define EVT_SYSTEM_DEEP_SLEEP    0x0003U
#define EVT_SYSTEM_WAKE          0x0004U

#define EVT_SCREEN_CHANGE        0x0301U

typedef struct {
    uint16_t id;
    uint8_t data[MODULUS_EVENT_DATA_MAX];
    uint32_t data_len;
} modulus_event_msg_t;

void modulus_event_init(void);
bool modulus_event_publish(uint16_t id, const uint8_t *data, uint32_t len);
bool modulus_event_receive(modulus_event_msg_t *out);

#ifdef __cplusplus
}
#endif
