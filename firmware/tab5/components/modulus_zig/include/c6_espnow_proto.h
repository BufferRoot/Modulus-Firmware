#pragma once



#include <stdint.h>



/* Shared with firmware/tab5-c6/main/espnow_handler.h */



#define ESPNOW_CMD_INIT       0x01

#define ESPNOW_CMD_DEINIT     0x02

#define ESPNOW_CMD_ADD_PEER   0x03

#define ESPNOW_CMD_DEL_PEER   0x04

#define ESPNOW_CMD_SEND       0x05

#define ESPNOW_CMD_SET_PMK    0x06

#define ESPNOW_CMD_PROBE      0x07

#define ESPNOW_CMD_LOCK_CHANNEL 0x08

#define ESPNOW_CMD_SET_RATE   0x09



#define ESPNOW_RATE_1M   0

#define ESPNOW_RATE_2M   1

#define ESPNOW_RATE_5M5  2

#define ESPNOW_RATE_11M  3
#define ESPNOW_RATE_6M   4  /* OFDM 11g */
#define ESPNOW_RATE_12M  5
#define ESPNOW_RATE_24M  6
#define ESPNOW_RATE_MCS0 7  /* HT20 11n */
#define ESPNOW_RATE_MCS3 8



#define ESPNOW_MAX_PAYLOAD 1470



#define ESPNOW_EVT_INIT_OK    0x81

#define ESPNOW_EVT_INIT_FAIL  0x82

#define ESPNOW_EVT_SEND_OK    0x83

#define ESPNOW_EVT_SEND_FAIL  0x84

#define ESPNOW_EVT_RECV       0x85

#define ESPNOW_EVT_DISCOVER   0x86

#define ESPNOW_EVT_PEER_OK    0x87

#define ESPNOW_EVT_PEER_FAIL  0x88

#define ESPNOW_EVT_PROBE_FAIL 0x89
#define ESPNOW_EVT_RSSI       0x8A /* [src_mac:6][rssi:s8] throttled link quality */


