#pragma once
/*
 * Zigbee host↔hub byte protocol (NanoH2 UART).
 * Keep in sync with firmware/nanoh2/main/zb_proto.h — wire IDs must match.
 */

#include <stdint.h>

/* Commands from host (P4) */
#define ZIGBEE_CMD_ENABLE          0x01 /* legacy alias of HUB_START */
#define ZIGBEE_CMD_DISABLE         0x02
#define ZIGBEE_CMD_GET_STATE       0x03
#define ZIGBEE_CMD_HUB_START       0x10 /* [channel:1] 0 = energy-scan pick */
#define ZIGBEE_CMD_PERMIT_JOIN     0x11
#define ZIGBEE_CMD_ONOFF           0x12
#define ZIGBEE_CMD_LEVEL           0x13
#define ZIGBEE_CMD_COVER           0x14
#define ZIGBEE_CMD_THERMO_SP       0x15
#define ZIGBEE_CMD_IC_ADD          0x16
#define ZIGBEE_CMD_READ_SENSORS    0x17
#define ZIGBEE_CMD_IDENTIFY        0x18
#define ZIGBEE_CMD_DEV_LEAVE       0x19 /* [ieee:8 MSB] */
#define ZIGBEE_CMD_GET_DEVICES     0x1A
#define ZIGBEE_CMD_GET_NEIGHBORS   0x1B
#define ZIGBEE_CMD_REFRESH_LQI     0x1C
#define ZIGBEE_CMD_ENERGY_SCAN     0x1D
#define ZIGBEE_CMD_GROUP_SET       0x1E /* [short:2BE][ep][group:2BE][1=add 0=remove] */
#define ZIGBEE_CMD_GROUP_ONOFF     0x1F /* [group:2BE][op: 0=off 1=on 2=toggle] */
#define ZIGBEE_CMD_COLOR           0x20 /* [short:2BE][ep][mode][a:2BE][b:2BE]
                                         * mode 0: a=mireds, b=trans ds; mode 1: a=hue, b=sat */

/* Events to host (P4) */
#define ZIGBEE_EVT_OK              0x81
#define ZIGBEE_EVT_FAIL            0x82
#define ZIGBEE_EVT_STATE           0x83 /* legacy: [ch][pan:2BE][short:2][active] */
#define ZIGBEE_EVT_HUB_STATE       0x88 /* [formed][ch][pan:2BE][permit_s] */
#define ZIGBEE_EVT_DEV_JOINED      0x89 /* [short:2BE][ieee:8 MSB][cap] */
#define ZIGBEE_EVT_DEV_LEFT        0x8A /* [ieee:8 MSB] */
#define ZIGBEE_EVT_DEV_CAPS        0x8B /* [short:2BE][ep][caps][device_id:2BE] */
#define ZIGBEE_EVT_DEV_STATE       0x8C /* [short:2BE][cluster:2BE][value:2BE] */
#define ZIGBEE_EVT_DEV_SENSOR      0x8D /* [short:2BE][cluster:2BE][attr:2BE][value:4BE] */
#define ZIGBEE_EVT_DEV_LQI         0x8E /* [short:2BE][lqi][rssi:s8][age] */
#define ZIGBEE_EVT_DEV_ENTRY       0x8F /* [short:2BE][ieee:8][ep][caps][dev_id:2BE][lqi][rssi] */
#define ZIGBEE_EVT_NBR_ENTRY       0x90 /* [short:2BE][ieee:8][rel][lqi][rssi][age][depth] */
#define ZIGBEE_EVT_ENERGY_CH       0x91 /* [ch][energy_dbm:s8] */
#define ZIGBEE_EVT_ENERGY_DONE     0x92 /* [best_ch][best_energy:s8] */
#define ZIGBEE_EVT_TABLE_DONE      0x93 /* [kind:1][count:1] 0=devices 1=neighbors 2=lqi */
#define ZIGBEE_EVT_ACK             0x94 /* [seq:1] */
#define ZIGBEE_EVT_NAK             0x95 /* [seq:1][reason:1] */
#define ZIGBEE_EVT_DEV_INFO        0x96 /* [short:2BE][mfr\0model\0] — zigbee2mqtt DB key */

/*
 * Host→hub wire format (sequenced):
 *   [seq:1][cmd:1][args...]   seq 1..255 (never 0)
 * Hub replies with EVT_ACK / EVT_NAK carrying the same seq.
 * Unsolicited hub→host events stay [evt][args...] (no seq).
 */

/* Capability bits (EVT_DEV_CAPS) */
#define ZIGBEE_CAP_ONOFF           0x01
#define ZIGBEE_CAP_LEVEL           0x02
#define ZIGBEE_CAP_COVER           0x04
#define ZIGBEE_CAP_THERMOSTAT      0x08
#define ZIGBEE_CAP_SENSOR          0x10
#define ZIGBEE_CAP_POWER           0x20
#define ZIGBEE_CAP_METER           0x40
#define ZIGBEE_CAP_COLOR           0x80

