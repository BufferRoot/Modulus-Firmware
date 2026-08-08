#pragma once
/*
 * Host RPC to wireless co-processors.
 *
 * Zigbee (modulus_wireless_zb_*): NanoH2 UART via zb_uart_host.
 * Thread (modulus_wireless_th_*): C6 OpenThread via SDIO (c6_sdio_host).
 */

#include <stdbool.h>
#include <stdint.h>

#include "wireless_shim_802154.h"

void modulus_wireless_rpc_init(void);
void modulus_wireless_rpc_poll(void);
void modulus_wireless_rpc_poll_state(bool zigbee_on, bool thread_on);

bool modulus_wireless_zb_join(void);
bool modulus_wireless_zb_leave(void);
bool modulus_wireless_zb_permit_join(uint8_t seconds);
bool modulus_wireless_zb_set_level(const modulus_zb_device_t *dev, uint8_t level);
bool modulus_wireless_zb_cover(const modulus_zb_device_t *dev, uint8_t op);
bool modulus_wireless_zb_thermo_sp(const modulus_zb_device_t *dev, uint16_t sp_c_x10);
bool modulus_wireless_zb_ic_add(const char *ieee_hex, const char *code_hex);
bool modulus_wireless_zb_read_sensors(const modulus_zb_device_t *dev);
bool modulus_wireless_zb_identify(const modulus_zb_device_t *dev, uint8_t seconds);
/* Groups (0x0004): membership + one-cast group control. */
bool modulus_wireless_zb_group_set(const modulus_zb_device_t *dev,
                                          uint16_t group_id, bool add);
bool modulus_wireless_zb_group_onoff(uint16_t group_id, uint8_t op);
bool modulus_wireless_zb_dev_leave(const char *ieee_hex);
bool modulus_wireless_zb_energy_scan(void);
/* Color Control (0x0300): mode 0 = CCT (a=mireds, b=trans ds), mode 1 = hue/sat. */
bool modulus_wireless_zb_color(const modulus_zb_device_t *dev, uint8_t mode,
                                      uint16_t a, uint16_t b);
/* Interview cache: mfr/model strings for a joined device (false = not seen). */
bool modulus_wireless_zb_dev_info(uint16_t short_addr,
                                         const char **mfr, const char **model);
/* Seed RAM interview cache from NVS-restored model (boot / re-pair). */
void modulus_wireless_zb_seed_dev_info(uint16_t short_addr, const char *model);
uint8_t modulus_wireless_zb_permit_remaining(void);
bool modulus_wireless_zb_hub_fw(void);
/* True after ~3 missed UART supervision windows following a live link. */
bool modulus_wireless_zb_hub_offline(void);
bool modulus_wireless_th_attach(void);
bool modulus_wireless_th_detach(void);

bool modulus_wireless_zb_set_onoff(const modulus_zb_device_t *dev, bool on);
bool modulus_wireless_th_refresh_devices(void);

/* True while the NanoH2 hub UART link is alive (frames within window). */
bool modulus_wireless_zb_link_up(void);

const char *modulus_wireless_zb_network_text(void);
const char *modulus_wireless_th_network_text(void);

bool modulus_wireless_zb_joined(void);
bool modulus_wireless_th_attached(void);
