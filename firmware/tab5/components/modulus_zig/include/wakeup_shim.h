#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * PMS150G-U06 wake path (Tab5 schematic):
 *   BMI270 INT1 + RX8130 INT -> E_TRG (PMIC PA6/CIN-) — NOT wired to ESP GPIO.
 * Cold wake from PMIC power-off requires sensor IRQ arm before rail cut.
 * Display dim/sleep still uses software BMI270 poll (imu_shim).
 */
void modulus_wakeup_init(void);

/** Arm PMIC E_TRG sources before deep sleep or true shutdown. */
void modulus_wakeup_arm(bool motion, bool rtc_timer);

void modulus_wakeup_disarm(void);

#ifdef __cplusplus
}
#endif
