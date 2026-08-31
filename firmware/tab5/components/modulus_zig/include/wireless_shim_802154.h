#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "zb_devdb.h"

#define MODULUS_ZB_MAX_DEVICES 8
#define MODULUS_ZB_MAX_SCAN    8
#define MODULUS_TH_MAX_DEVICES 8
#define MODULUS_TH_MAX_SCAN    8

typedef struct {
    char id[17];
    char name[24];
    /* ZCL Basic ModelIdentifier (attr 0x0005) — zigbee2mqtt/devdb key.
     * Persisted in NVS (zbN_md) so quirks survive reboot without re-interview. */
    char model[17];
    uint8_t endpoint;
    bool on;
    int8_t rssi;
    /* NWK neighbor-table link quality (0-255, from EVT_DEV_LQI); 0 = unknown.
     * RAM only — refreshed by the periodic REFRESH_LQI poll. */
    uint8_t lqi;
    /* Hub mode (NanoH2 Zigbee coordinator): NWK short address learned from the
     * device-announce, and last commanded Level Control brightness (0-254). */
    uint16_t short_addr;
    uint8_t level;
    /* ZIGBEE_CAP_* bits from ZDO Simple Descriptor discovery; 0 = unknown
     * (legacy raw firmware or discovery pending) -> On/Off assumed. */
    uint8_t caps;
    /* Live sensor readings (RAM only, from CMD_READ_SENSORS). Raw ZCL values;
     * Tuya-family scaling: V/10 volts, I in mA, P/10 watts, E/100 kWh. */
    uint16_t volt_raw;
    uint16_t curr_raw;
    int16_t power_raw;
    uint32_t energy_raw;
    uint8_t sensors_seen; /* bit0 V, bit1 I, bit2 P, bit3 E */
    /* IAS ZoneStatus (0x0500/0x0002); bit0 Alarm1 = door/contact open typical.
     * RAM only — from reports / zone-status-change notifications. */
    uint16_t zone_status;
    bool zone_seen;
} modulus_zb_device_t;

typedef struct {
    char ext_addr[17];
    char name[24];
    bool on;
} modulus_th_device_t;

void modulus_wireless_802154_poll(void);

const char *modulus_wireless_zigbee_scan_text(void);
bool modulus_wireless_zigbee_scan_start(void);
void modulus_wireless_zigbee_scan_stop(void);
bool modulus_wireless_zigbee_scan_done(void);
int modulus_wireless_zigbee_scan_count(void);
bool modulus_wireless_zigbee_scan_get(int idx, modulus_zb_device_t *out);
bool modulus_wireless_zigbee_scan_select(int idx);

int modulus_wireless_zigbee_device_count(void);
bool modulus_wireless_zigbee_device_get(int idx, modulus_zb_device_t *out);
bool modulus_wireless_zigbee_device_toggle(int idx);
bool modulus_wireless_zigbee_device_set_level(int idx, uint8_t level);
bool modulus_wireless_zigbee_device_remove(int idx);
bool modulus_wireless_zigbee_device_add(const char *name, const char *ieee, uint8_t endpoint,
                                        const char *install_code);
void modulus_wireless_zigbee_devices_clear(void);
bool modulus_wireless_zigbee_can_control(void);

const char *modulus_wireless_thread_scan_text(void);
bool modulus_wireless_thread_scan_start(void);
void modulus_wireless_thread_scan_stop(void);
bool modulus_wireless_thread_scan_done(void);
int modulus_wireless_thread_scan_count(void);
bool modulus_wireless_thread_scan_get(int idx, modulus_th_device_t *out);
bool modulus_wireless_thread_scan_select(int idx);

int modulus_wireless_thread_device_count(void);
bool modulus_wireless_thread_device_get(int idx, modulus_th_device_t *out);
bool modulus_wireless_thread_device_toggle(int idx);
bool modulus_wireless_thread_device_remove(int idx);
bool modulus_wireless_thread_device_add(const char *name, const char *ext_addr);
void modulus_wireless_thread_devices_clear(void);
bool modulus_wireless_thread_can_control(void);

/* Hub-mode announcements from the NanoH2 ZBOSS coordinator. */
void modulus_wireless_zb_note_device_joined(uint16_t short_addr, const uint8_t ieee_msb[8]);
void modulus_wireless_zb_note_device_left(const uint8_t ieee_msb[8]);
void modulus_wireless_zb_note_device_caps(uint16_t short_addr, uint8_t endpoint,
                                                 uint8_t caps, uint16_t device_id);
/* Interview: mfr/model + optional devdb match; upgrades auto-names only. */
void modulus_wireless_zb_note_device_info(uint16_t short_addr, const char *mfr,
                                                 const char *model,
                                                 const zb_devdb_entry_t *db);
/* Live attribute report: cluster 0x0006 -> on/off, 0x0008 -> level. */
void modulus_wireless_zb_note_device_state(uint16_t short_addr, uint16_t cluster,
                                                  uint16_t value);
void modulus_wireless_zb_note_device_sensor(uint16_t short_addr, uint16_t cluster,
                                                   uint16_t attr, uint32_t value);
/* NWK neighbor-table link quality for a joined device (EVT_DEV_LQI). */
void modulus_wireless_zb_note_device_lqi(uint16_t short_addr, uint8_t lqi,
                                                int8_t rssi);
bool modulus_wireless_zigbee_device_cover(int idx, uint8_t op);
bool modulus_wireless_zigbee_device_color(int idx, uint8_t mode, uint16_t a, uint16_t b);
bool modulus_wireless_zigbee_device_ic_add(int idx, const char *code_hex);
bool modulus_wireless_zigbee_device_rename(int idx, const char *name);
bool modulus_wireless_zigbee_device_read_sensors(int idx);
bool modulus_wireless_zigbee_device_identify(int idx);
/* Force leave on hub + drop local row (IEEE hex from device id). */
bool modulus_wireless_zigbee_device_leave(int idx);
/* Diag: energy detect ch 11-26; text updates after ENERGY_DONE. */
bool modulus_wireless_zigbee_energy_scan(void);
const char *modulus_wireless_zigbee_energy_text(void);
void modulus_wireless_zb_note_energy_ch(uint8_t ch, int8_t energy_dbm);
void modulus_wireless_zb_note_energy_done(uint8_t best_ch, int8_t best_dbm);
uint32_t modulus_wireless_zigbee_state_gen(void);
void modulus_wireless_th_note_device_join(const uint8_t ext[8]);
void modulus_wireless_th_note_device_leave(const uint8_t ext[8]);
