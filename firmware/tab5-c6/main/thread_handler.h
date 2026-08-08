/*
 * Thread handler for ESP-Hosted slave (C6)
 * The C6 runs OpenThread as a Full Thread Device (FTD).
 * The P4 host controls the Thread network via commands over the
 * ESP_THREAD_IF SDIO channel.
 *
 * Protocol  host → slave  [cmd:1][payload...]
 *   CMD_ENABLE     0x01   []                    — init OT, form/join network
 *   CMD_DISABLE    0x02   []                    — leave network, deinit
 *   CMD_GET_STATE  0x03   []                    — request current state event
 *   CMD_SEND_UDP   0x04   [ip6:16][port:2][data:N]
 *   CMD_SET_CHANNEL 0x05  [channel:1]           — set 802.15.4 channel (11-26)
 *   CMD_SET_PANID  0x06   [panid:2]             — set PAN ID
 *
 * Protocol  slave → host  [evt:1][payload...]
 *   EVT_OK          0x81  []
 *   EVT_FAIL        0x82  [err:1]
 *   EVT_STATE       0x83  [role:1][channel:1][panid:2][ip6:16]
 *                         role: 0=Disabled,1=Detached,2=Child,3=Router,4=Leader
 *   EVT_UDP_RECV    0x84  [src_ip6:16][port:2][data:N]
 *   EVT_DEVICE_JOIN 0x85  [ext_addr:8]          — a device joined the network
 *   EVT_DEVICE_LEAVE 0x86 [ext_addr:8]          — a device left the network
 */
#ifndef THREAD_HANDLER_H
#define THREAD_HANDLER_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/* Commands from host (P4 → C6) */
#define THREAD_CMD_ENABLE      0x01
#define THREAD_CMD_DISABLE     0x02
#define THREAD_CMD_GET_STATE   0x03
#define THREAD_CMD_SEND_UDP    0x04
#define THREAD_CMD_SET_CHANNEL 0x05
#define THREAD_CMD_SET_PANID   0x06

/* Events to host (C6 → P4) */
#define THREAD_EVT_OK          0x81
#define THREAD_EVT_FAIL        0x82
#define THREAD_EVT_STATE       0x83
#define THREAD_EVT_UDP_RECV    0x84
#define THREAD_EVT_DEVICE_JOIN 0x85
#define THREAD_EVT_DEVICE_LEAVE 0x86

/**
 * Process a Thread command packet received from the host over SDIO.
 * @param payload  Command bytes (first byte is the command ID)
 * @param len      Length of payload
 */
void thread_process_host_cmd(const uint8_t *payload, uint16_t len);

/**
 * Returns true if Thread networking is currently enabled (radio in use).
 * Used by zigbee_handler to decide whether raw 802.15.4 is available.
 */
bool thread_is_networking(void);

#endif /* THREAD_HANDLER_H */
