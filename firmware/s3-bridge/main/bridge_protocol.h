#pragma once
#include <stddef.h>

/* Tab5 ↔ S3 side-band — must match espnow_transport_shim.c / espnow_stack.h */
#define BRIDGE_MOD_PROBE     "MOD_PROBE"
#define BRIDGE_MOD_ACK       "MOD_ACK"
#define BRIDGE_MOD_HALT_ON   "MOD_HALT1"
#define BRIDGE_MOD_HALT_OFF  "MOD_HALT0"
#define BRIDGE_MOD_PROBE_LEN 9
#define BRIDGE_MOD_ACK_LEN   7
#define BRIDGE_MOD_HALT_LEN  9
