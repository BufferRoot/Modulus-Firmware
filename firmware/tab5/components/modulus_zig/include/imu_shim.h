#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

void modulus_imu_init(void);
bool modulus_imu_wake_on_motion(void);
bool modulus_imu_is_ready(void);
bool modulus_imu_is_init_running(void);
void modulus_imu_ensure_bringup(void);
bool modulus_imu_poll_motion_wake(void);
void modulus_imu_set_wake_on_motion(bool enabled);
/** Arm BMI270 any-motion INT1 -> PMS150G E_TRG via bmi2 (display poll fallback). */
bool modulus_imu_arm_pms_wake(void);
/** Disarm PMS any-motion and allow poll-path IMU re-bringup. */
void modulus_imu_disarm_pms_wake(void);

#ifdef __cplusplus
}
#endif
