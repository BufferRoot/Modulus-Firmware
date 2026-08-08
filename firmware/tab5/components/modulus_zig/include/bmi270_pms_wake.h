#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Configure BMI270 any-motion on INT1 for PMS150G E_TRG (PMIC-only wake path). */
bool bmi270_pms_arm_any_motion(void);
/** Release PMS I2C claim so poll-path IMU can re-own the bus after wake. */
void bmi270_pms_disarm_any_motion(void);
bool bmi270_pms_is_armed(void);

#ifdef __cplusplus
}
#endif
