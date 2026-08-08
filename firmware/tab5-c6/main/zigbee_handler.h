/*
 * Zigbee/Raw 802.15.4 handler for ESP-Hosted slave (C6)
 *
 * HARDWARE CONSTRAINT: ESP32-C6 has ONE 802.15.4 radio.
 *   - When CONFIG_OPENTHREAD_ENABLED=y, OpenThread FTD owns the radio.
 *     Zigbee is not available. EVT_FAIL with code RADIO_BUSY is returned.
 *   - When CONFIG_OPENTHREAD_ENABLED=n, this handler has direct radio access
 *     via the raw ieee802154 driver (raw 802.15.4 MAC frame forwarding).
 *
 * To select mode: disable OPENTHREAD in sdkconfig and rebuild.
 * The P4 receives EVT_RADIO_BUSY if Thread is active.
 *
 * Protocol  host → slave  [cmd:1][payload...]
 *   CMD_ENABLE        0x01  [channel:1][panid:2]  — initialize radio, set ch+pan
 *   CMD_DISABLE       0x02  []                    — disable radio
 *   CMD_GET_STATE     0x03  []                    — request current state
 *   CMD_SET_CHANNEL   0x04  [channel:1]           — change channel (11-26)
 *   CMD_SET_SHORT_ADDR 0x05 [short_addr:2]        — set device short address
 *   CMD_SET_PANID     0x06  [panid:2]             — change PAN ID
 *   CMD_TX_FRAME      0x07  [frame:N]             — transmit a 802.15.4 frame
 *   CMD_SET_PROMISCUOUS 0x08 [enable:1]           — enable/disable promiscuous
 *
 * Protocol  slave → host  [evt:1][payload...]
 *   EVT_OK            0x81  []
 *   EVT_FAIL          0x82  [err:1]
 *   EVT_STATE         0x83  [channel:1][panid:2][short_addr:2][active:1]
 *   EVT_RX_FRAME      0x84  [rssi:1][lqi:1][frame:N]
 *   EVT_TX_DONE       0x85  []
 *   EVT_TX_FAIL       0x86  [err:1]
 *   EVT_RADIO_BUSY    0x87  []  — Thread is using the radio; Zigbee unavailable
 */
#ifndef ZIGBEE_HANDLER_H
#define ZIGBEE_HANDLER_H

#include <stdint.h>
#include <stddef.h>

/* Commands from host */
#define ZIGBEE_CMD_ENABLE          0x01
#define ZIGBEE_CMD_DISABLE         0x02
#define ZIGBEE_CMD_GET_STATE       0x03
#define ZIGBEE_CMD_SET_CHANNEL     0x04
#define ZIGBEE_CMD_SET_SHORT_ADDR  0x05
#define ZIGBEE_CMD_SET_PANID       0x06
#define ZIGBEE_CMD_TX_FRAME        0x07
#define ZIGBEE_CMD_SET_PROMISCUOUS 0x08

/* Events to host */
#define ZIGBEE_EVT_OK              0x81
#define ZIGBEE_EVT_FAIL            0x82
#define ZIGBEE_EVT_STATE           0x83
#define ZIGBEE_EVT_RX_FRAME        0x84
#define ZIGBEE_EVT_TX_DONE         0x85
#define ZIGBEE_EVT_TX_FAIL         0x86
#define ZIGBEE_EVT_RADIO_BUSY      0x87  /* Thread is active; Zigbee unavailable */

/* ── Hub-mode protocol (Zigbee now runs on the NanoH2, not the C6) ────────
 * These command/event codes are the P4<->hub contract, kept here so the C6
 * SDIO stub and any legacy tooling share the same numbering. The live
 * implementation is firmware/nanoh2/main/zigbee_hub.c.
 * CMD_HUB_START    0x10  [channel:1]                 form/reopen network (0 = default ch 16)
 * CMD_PERMIT_JOIN  0x11  [seconds:1]                 open network for joining (0 = close)
 * CMD_ONOFF        0x12  [short:2BE][ep:1][op:1]     op: 0=off 1=on 2=toggle
 * CMD_LEVEL        0x13  [short:2BE][ep:1][level:1][trans_ds:2BE]  Level Control (with on/off)
 * EVT_HUB_STATE    0x88  [formed:1][channel:1][pan:2BE][permit_s:1]
 * EVT_DEV_JOINED   0x89  [short:2BE][ieee:8 MSB-first][cap:1]
 * EVT_DEV_LEFT     0x8A  [ieee:8 MSB-first]
 */
#define ZIGBEE_CMD_HUB_START       0x10
#define ZIGBEE_CMD_PERMIT_JOIN     0x11
#define ZIGBEE_CMD_ONOFF           0x12
#define ZIGBEE_CMD_LEVEL           0x13

#define ZIGBEE_EVT_HUB_STATE       0x88
#define ZIGBEE_EVT_DEV_JOINED      0x89
#define ZIGBEE_EVT_DEV_LEFT        0x8A

/* Device capability discovery (hub mode): after a device announces, the C6
 * queries its ZDO Active Endpoints + Simple Descriptor and reports which
 * ZCL server clusters the device actually implements. The P4 gates UI
 * controls on these (a contact sensor gets no toggle; only Level devices
 * get a brightness slider).
 * EVT_DEV_CAPS  0x8B  [short:2BE][ep:1][caps:1][device_id:2BE]
 */
#define ZIGBEE_EVT_DEV_CAPS        0x8B

/* ── Hub extensions: covers, thermostats, install codes, live state ──────
 * CMD_COVER      0x14  [short:2BE][ep:1][op:1]        op: 0=open 1=close 2=stop
 * CMD_THERMO_SP  0x15  [short:2BE][ep:1][sp_x10:2BE]  heating setpoint, degC x10
 * CMD_IC_ADD     0x16  [ieee:8 MSB][len:1][code:N]    install code incl. CRC16
 * EVT_DEV_STATE  0x8C  [short:2BE][cluster:2BE][value:2BE]  attribute report
 */
#define ZIGBEE_CMD_COVER           0x14
#define ZIGBEE_CMD_THERMO_SP       0x15
#define ZIGBEE_CMD_IC_ADD          0x16

#define ZIGBEE_EVT_DEV_STATE       0x8C

/* ── Device exposes: sensor reads + identify ─────────────────────────────
 * CMD_READ_SENSORS 0x17 [short:2BE][ep:1]   ZCL Read Attr: Electrical
 *                  Measurement (0x0B04: V 0x0505, I 0x0508, P 0x050B) and
 *                  Metering (0x0702: energy 0x0000)
 * CMD_IDENTIFY     0x18 [short:2BE][ep:1][seconds:1]
 * EVT_DEV_SENSOR   0x8D [short:2BE][cluster:2BE][attr:2BE][value:4BE]
 * Scaling is device-family convention (Tuya plugs: V/10, I mA, P/10, E/100).
 */
#define ZIGBEE_CMD_READ_SENSORS    0x17
#define ZIGBEE_CMD_IDENTIFY        0x18
#define ZIGBEE_EVT_DEV_SENSOR      0x8D

#define ZIGBEE_CAP_POWER           0x20  /* Electrical Measurement (0x0B04) */
#define ZIGBEE_CAP_METER           0x40  /* Metering / energy (0x0702) */



#define ZIGBEE_CAP_ONOFF           0x01  /* On/Off server (0x0006): lights, plugs, sirens */
#define ZIGBEE_CAP_LEVEL           0x02  /* Level Control server (0x0008): dimmables */
#define ZIGBEE_CAP_COVER           0x04  /* Window Covering server (0x0102): blinds/curtains */
#define ZIGBEE_CAP_THERMOSTAT      0x08  /* Thermostat server (0x0201): TRVs */
#define ZIGBEE_CAP_SENSOR          0x10  /* IAS Zone (0x0500) or measurement-only device */



/**
 * Process a Zigbee command packet received from the host over SDIO.
 * @param payload  Command bytes (first byte is the command ID)
 * @param len      Length of payload
 */
void zigbee_process_host_cmd(const uint8_t *payload, uint16_t len);

#endif /* ZIGBEE_HANDLER_H */
