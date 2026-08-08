/*
 * BMI270 motion wake via espressif/bmi270 + accel magnitude delta.
 */
#include "imu_shim.h"
#include "bmi270_pms_wake.h"
#include "i2c_coex_shim.h"
#include "nvs_shim.h"

#include <bmi270.h>
#include <bsp/m5stack_tab5.h>
#include <driver/i2c_master.h>
#include <esp_log.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

static const char *TAG = "modulus_imu";

static bool s_ready = false;
static bool s_wake_on_motion = false;
static bool s_init_running = false;
static uint32_t s_init_defer_ms = 2000;
static bmi270_handle_t *s_bmi = NULL;

static float s_accel_baseline = 0.0f;
static bool s_accel_baseline_valid = false;

static bool poll_accel_motion(void)
{
    if (!s_bmi) {
        return false;
    }

    float ax = 0.0f, ay = 0.0f, az = 0.0f;
    if (bmi270_get_acce_data(s_bmi, &ax, &ay, &az) != ESP_OK) {
        return false;
    }

    const float mag = ax * ax + ay * ay + az * az;
    if (!s_accel_baseline_valid) {
        s_accel_baseline = mag;
        s_accel_baseline_valid = true;
        return false;
    }

    float delta = mag - s_accel_baseline;
    if (delta < 0.0f) {
        delta = -delta;
    }
    s_accel_baseline = (s_accel_baseline * 15.0f + mag) / 16.0f;

    static const float k_motion_delta = 0.04f;
    return delta >= k_motion_delta;
}

static void finish_imu_init(void)
{
    i2c_master_bus_handle_t bus = bsp_i2c_get_handle();
    if (!bus) {
        ESP_LOGW(TAG, "M-Bus I2C handle missing");
        s_init_running = false;
        return;
    }

    if (!modulus_i2c_coex_lock(8000)) {
        ESP_LOGW(TAG, "IMU init skipped — M-Bus busy");
        s_init_running = false;
        return;
    }

    const bmi270_driver_config_t drv_cfg = {
        .addr = BMI270_I2C_ADDRESS_L,
        .interface = BMI270_USE_I2C,
        .i2c_bus = bus,
    };

    esp_err_t err = bmi270_create(&drv_cfg, &s_bmi);
    if (err != ESP_OK) {
        const bmi270_driver_config_t alt = {
            .addr = BMI270_I2C_ADDRESS_H,
            .interface = BMI270_USE_I2C,
            .i2c_bus = bus,
        };
        err = bmi270_create(&alt, &s_bmi);
    }

    if (err != ESP_OK || s_bmi == NULL) {
        ESP_LOGW(TAG, "BMI270 create failed (%s)", esp_err_to_name(err));
        modulus_i2c_coex_unlock();
        s_init_running = false;
        return;
    }

    const bmi270_config_t cfg = {
        .acce_odr = BMI270_ACC_ODR_25_HZ,
        .acce_range = BMI270_ACC_RANGE_4_G,
        .gyro_odr = BMI270_GYR_ODR_25_HZ,
        .gyro_range = BMI270_GYR_RANGE_500_DPS,
    };
    err = bmi270_start(s_bmi, &cfg);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "BMI270 start failed (%s)", esp_err_to_name(err));
        bmi270_delete(s_bmi);
        s_bmi = NULL;
        modulus_i2c_coex_unlock();
        s_init_running = false;
        return;
    }

    s_accel_baseline_valid = false;
    modulus_i2c_coex_unlock();
    s_ready = true;
    s_init_running = false;
    ESP_LOGI(TAG, "BMI270 ready (wake_motion=%d)", s_wake_on_motion);
}

static void defer_imu_init_delay(void)
{
    uint32_t remaining = s_init_defer_ms;
    while (remaining > 0) {
        const uint32_t slice = remaining > 250 ? 250 : remaining;
        vTaskDelay(pdMS_TO_TICKS(slice));
        remaining -= slice;
    }
}

static void imu_init_task(void *arg)
{
    (void)arg;
    defer_imu_init_delay();
    finish_imu_init();
    vTaskDelete(NULL);
}

static void start_imu_init_task(uint32_t defer_ms)
{
    if (s_init_running || s_ready) {
        return;
    }
    s_init_defer_ms = defer_ms;
    s_init_running = true;
    BaseType_t ok = xTaskCreatePinnedToCore(imu_init_task, "imu_init", 4096, NULL, 1, NULL, 0);
    if (ok != pdPASS) {
        s_init_running = false;
        ESP_LOGW(TAG, "IMU init task spawn failed");
    }
}

void modulus_imu_init(void)
{
    s_wake_on_motion = modulus_nvs_get_u8("wake_motion", 0) != 0;
    s_accel_baseline_valid = false;
    s_ready = false;
    s_init_running = false;
    s_bmi = NULL;
    ESP_LOGI(TAG, "IMU init (wake_motion=%d)", s_wake_on_motion);
}

void modulus_imu_set_wake_on_motion(bool enabled)
{
    s_wake_on_motion = enabled;
    modulus_nvs_set_u8("wake_motion", enabled ? 1 : 0);
    if (enabled && !s_ready && !s_init_running) {
        start_imu_init_task(2000);
    }
}

bool modulus_imu_arm_pms_wake(void)
{
    if (!s_wake_on_motion) {
        return false;
    }

    if (s_bmi) {
        (void)bmi270_stop(s_bmi);
        bmi270_delete(s_bmi);
        s_bmi = NULL;
        s_ready = false;
        s_accel_baseline_valid = false;
    }

    if (bmi270_pms_arm_any_motion()) {
        return true;
    }

    /* Fallback: keep poll path for display-only wake if bmi2 arm fails. */
    modulus_imu_ensure_bringup();
    return s_ready;
}

void modulus_imu_disarm_pms_wake(void)
{
    bmi270_pms_disarm_any_motion();
    if (s_wake_on_motion && !s_ready && !s_init_running) {
        modulus_imu_ensure_bringup();
    }
}

bool modulus_imu_wake_on_motion(void)
{
    return s_wake_on_motion;
}

bool modulus_imu_is_ready(void)
{
    return s_ready;
}

bool modulus_imu_is_init_running(void)
{
    return s_init_running;
}

void modulus_imu_ensure_bringup(void)
{
    if (!s_wake_on_motion || s_ready || s_init_running) {
        return;
    }
    start_imu_init_task(1000);
}

bool modulus_imu_poll_motion_wake(void)
{
    /* PMS any-motion owns the BMI270 bus while armed — do not dual-drive. */
    if (bmi270_pms_is_armed()) {
        return false;
    }
    if (s_init_running || !s_ready || !s_wake_on_motion) {
        return false;
    }
    if (!modulus_i2c_coex_lock(50)) {
        return false;
    }
    const bool motion = poll_accel_motion();
    modulus_i2c_coex_unlock();
    taskYIELD();
    return motion;
}
