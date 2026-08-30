#pragma once

#include <driver/i2c_master.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Idempotent PI4IOE1+2 init (C++ bsp_io_expander_pi4ioe_init). */
bool tab5_pi4ioe_init(i2c_master_bus_handle_t bus);

/** True after successful tab5_pi4ioe_init(). */
bool tab5_pi4ioe_is_ready(void);

/** Ensure expander ready; returns false if bus missing. */
bool tab5_pi4ioe_ensure_init(void);

void tab5_pi4ioe_set_ext_5v_en(bool en);
void tab5_pi4ioe_set_usb_5v_en(bool en);
void tab5_pi4ioe_set_wifi_power_en(bool en);
/** Re-drive WLAN_PWR after BSP/display; re-anchor boot timer if rail was off/Hi-Z. */
bool tab5_pi4ioe_ensure_wlan_pwr_on(void);
void tab5_pi4ioe_set_ext_antenna_enable(bool en);
void tab5_pi4ioe_set_spk_en(bool en);
bool tab5_pi4ioe_get_headphone_detect(void);
void tab5_pi4ioe_set_charge_en(bool en);
void tab5_pi4ioe_set_charge_qc_en(bool en);
void tab5_pi4ioe_generate_poweroff_signal(void);

bool tab5_pi4ioe_get_charge_status(void);

/** Record first WLAN_PWR_EN (PI4IOE2 init or explicit enable). */
void tab5_pi4ioe_note_wlan_pwr_on(void);

/** Power-cycle WLAN_PWR_EN and re-anchor boot timer (P4 reboot while C6 still up). */
void tab5_pi4ioe_cycle_wlan_pwr(void);

/** Re-anchor SDIO boot timer after esp_hosted GPIO15 reset (or retry). */
void tab5_pi4ioe_note_c6_reset(void);

/** Active-low CHIP_EN pulse on GPIO15 — runtime C6 reset (LVGL hal_wireless wake path). */
void tab5_pi4ioe_c6_hardware_reset(void);

/** Wait until CONFIG_MODULUS_C6_BOOT_DELAY_MS elapsed since last anchor (reset or WLAN_PWR). */
void tab5_pi4ioe_wait_c6_sdio_ready(void);

#ifdef __cplusplus
}
#endif
