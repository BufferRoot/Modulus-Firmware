#pragma once

#include <stdint.h>

/* Shared with firmware/tab5-c6/main/thread_handler.h */

#define THREAD_CMD_ENABLE      0x01
#define THREAD_CMD_DISABLE     0x02
#define THREAD_CMD_GET_STATE   0x03
#define THREAD_CMD_SEND_UDP    0x04
#define THREAD_CMD_SET_CHANNEL 0x05
#define THREAD_CMD_SET_PANID   0x06

#define THREAD_EVT_OK          0x81
#define THREAD_EVT_FAIL        0x82
#define THREAD_EVT_STATE       0x83
#define THREAD_EVT_UDP_RECV    0x84
#define THREAD_EVT_DEVICE_JOIN 0x85
#define THREAD_EVT_DEVICE_LEAVE 0x86

/* otDeviceRole: 0=Disabled,1=Detached,2=Child,3=Router,4=Leader */
