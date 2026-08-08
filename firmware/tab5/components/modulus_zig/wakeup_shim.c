/*
 * PMS150G E_TRG wake coordinator — BMI270 / RX8130 INT -> PMIC (hardware-only path).
 */
#include "wakeup_shim.h"
#include "imu_shim.h"
#include "nvs_shim.h"
#include "rx8130.h"

#include <esp_log.h>

static const char *TAG = "modulus_wakeup";

void modulus_wakeup_init(void)
{
    ESP_LOGI(TAG, "PMIC wake path: BMI270/RX8130 INT -> E_TRG (no ESP GPIO)");
}

void modulus_wakeup_arm(bool motion, bool rtc_timer)
{
    /* motion comes from Display→Wake on motion (wake_motion NVS), not Power touch bit. */
    if (motion) {
        modulus_imu_ensure_bringup();
        if (modulus_imu_arm_pms_wake()) {
            ESP_LOGI(TAG, "BMI270 any-motion INT1 armed -> PMS150G E_TRG");
        } else {
            ESP_LOGW(TAG, "BMI270 PMIC wake failed — display poll only");
        }
    }

    if (rtc_timer) {
        const uint16_t wt_min = modulus_nvs_get_u16("pwr_wtmin", 0);
        if (wt_min > 0 && rx8130_is_ready()) {
            const uint32_t sec = (uint32_t)wt_min * 60U;
            const uint16_t capped = (sec > 65535U) ? 65535U : (uint16_t)sec;
            rx8130_set_timer_irq(capped);
            ESP_LOGI(TAG, "RX8130 timer IRQ armed (%u s) -> E_TRG", (unsigned)capped);
        }
    }
}

void modulus_wakeup_disarm(void)
{
    if (rx8130_is_ready()) {
        rx8130_disable_irq();
        rx8130_clear_irq_flags();
    }
    modulus_imu_disarm_pms_wake();
}
