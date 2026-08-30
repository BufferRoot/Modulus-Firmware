#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void modulus_power_init(void);
void modulus_power_enter_deep_sleep(void);
bool modulus_power_is_deep_sleeping(void);

/** Deep-sleep timeout check, driven by the display activity esp_timer.
 *  @param inactive_ms authoritative idle time (LVGL's or the Zig shim's). */
void modulus_power_poll_deep_sleep(uint32_t inactive_ms);
void modulus_power_shutdown(void);
void modulus_power_request(bool reboot);
void modulus_power_set_sleep_policy(uint8_t mode, uint16_t dsto_sec);

void modulus_power_apply_rails(void);
void modulus_power_set_ext5v(bool en);
void modulus_power_set_usb5v(bool en);
void modulus_power_set_charge_en(bool en);
void modulus_power_set_quick_charge(bool en);
void modulus_power_set_wake_sources(uint8_t wake);
void modulus_power_set_wake_timer_min(uint16_t min);
void modulus_power_set_gate_wifi(bool en);
void modulus_power_set_gate_ext5v(bool en);
void modulus_power_set_gate_usb5v(bool en);

#ifdef __cplusplus
}
#endif
