#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    float voltage;
    float current;
    float power;
    uint8_t percent;
    uint8_t charge_state;
    float cpu_temp;
    float rate_mA;
    int32_t time_to_empty;
    int32_t time_to_full;
} modulus_battery_status_t;

void modulus_battery_init(void);
bool modulus_battery_get_status(modulus_battery_status_t *out);
bool modulus_battery_is_low_warn(const modulus_battery_status_t *st);
void modulus_battery_set_charge_en(bool en);
void modulus_battery_set_low_warn_pct(uint8_t pct);
/** NP-F pack preset index 0..4 (F550/F550 3500/F750/F950/F970). Affects time estimates only. */
void modulus_battery_set_pack_type(uint8_t idx);
uint8_t modulus_battery_get_pack_type(void);
const char *modulus_battery_pack_label(uint8_t idx);
/** Pause INA226 poll during deep sleep (avoids I2C coex contention). */
void modulus_battery_set_poll_paused(bool paused);
bool modulus_battery_is_poll_paused(void);
/** When bat_adapt NVS is on, tighten dim/screen timeouts while discharging. */
void modulus_battery_set_adaptive(bool on);
bool modulus_battery_is_adaptive(void);
void modulus_battery_apply_display_policy(void);

#ifdef __cplusplus
}
#endif
