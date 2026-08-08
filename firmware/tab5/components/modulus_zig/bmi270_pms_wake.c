/*
 * BMI270 any-motion INT1 -> PMS150G E_TRG (PMIC cold wake).
 * Uses Bosch bmi270_sensor prebuilt API; I2C via BSP M-Bus + coex lock.
 */
#include "bmi270_pms_wake.h"
#include "i2c_coex_shim.h"
#include "tab5_hw.h"

#include <bmi270_api.h>
#include <bsp/m5stack_tab5.h>

/* Config blob from espressif/bmi270 (imu_shim); avoid bmi270_image.h duplicate symbol. */
extern const uint8_t bmi270_config_file[];
#include <driver/i2c_master.h>
#include <esp_log.h>
#include <stdint.h>
#include <string.h>

extern int8_t bmi270_init(struct bmi2_dev *dev);

static const char *TAG = "bmi270_pms";

static i2c_master_dev_handle_t s_i2c_dev = NULL;
static struct bmi2_dev s_bmi2;
static bool s_armed = false;

static BMI2_INTF_RETURN_TYPE bmi_reg_read(uint8_t reg, uint8_t *data, uint32_t len, void *intf_ptr)
{
    (void)intf_ptr;
    if (!s_i2c_dev || !modulus_i2c_coex_lock(200)) {
        return BMI2_E_COM_FAIL;
    }
    const esp_err_t err = i2c_master_transmit_receive(s_i2c_dev, &reg, 1, data, len, 100);
    modulus_i2c_coex_unlock();
    return (err == ESP_OK) ? BMI2_INTF_RET_SUCCESS : BMI2_E_COM_FAIL;
}

static BMI2_INTF_RETURN_TYPE bmi_reg_write(uint8_t reg, const uint8_t *data, uint32_t len, void *intf_ptr)
{
    (void)intf_ptr;
    if (!s_i2c_dev || !modulus_i2c_coex_lock(200)) {
        return BMI2_E_COM_FAIL;
    }
    uint8_t buf[33];
    if (len + 1U > sizeof(buf)) {
        modulus_i2c_coex_unlock();
        return BMI2_E_COM_FAIL;
    }
    buf[0] = reg;
    memcpy(buf + 1, data, len);
    const esp_err_t err = i2c_master_transmit(s_i2c_dev, buf, len + 1U, 100);
    modulus_i2c_coex_unlock();
    return (err == ESP_OK) ? BMI2_INTF_RET_SUCCESS : BMI2_E_COM_FAIL;
}

static bool ensure_i2c_dev(uint8_t addr)
{
    if (s_i2c_dev) {
        return true;
    }
    const i2c_master_bus_handle_t bus = bsp_i2c_get_handle();
    if (!bus) {
        return false;
    }
    const i2c_device_config_t cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = addr,
        .scl_speed_hz = 400000,
    };
    return i2c_master_bus_add_device(bus, &cfg, &s_i2c_dev) == ESP_OK;
}

static int8_t configure_any_motion(bmi270_handle_t dev)
{
    struct bmi2_sens_config config = { 0 };
    struct bmi2_int_pin_config pin_config = { 0 };

    config.type = BMI2_ANY_MOTION;
    int8_t rslt = bmi270_get_sensor_config(&config, 1, dev);
    if (rslt != BMI2_OK) {
        return rslt;
    }

    rslt = bmi2_get_int_pin_config(&pin_config, dev);
    if (rslt != BMI2_OK) {
        return rslt;
    }

    config.cfg.any_motion.duration = BMI2_ANY_NO_MOT_DUR_80_MSEC;
    config.cfg.any_motion.threshold = UINT16_C(104); /* ~50 mg */

    rslt = bmi270_set_sensor_config(&config, 1, dev);
    if (rslt != BMI2_OK) {
        return rslt;
    }

    pin_config.pin_type = BMI2_INT1;
    pin_config.pin_cfg[0].input_en = BMI2_INT_INPUT_DISABLE;
    pin_config.pin_cfg[0].lvl = BMI2_INT_ACTIVE_LOW;
    pin_config.pin_cfg[0].od = BMI2_INT_PUSH_PULL;
    pin_config.pin_cfg[0].output_en = BMI2_INT_OUTPUT_ENABLE;
    pin_config.int_latch = BMI2_INT_NON_LATCH;

    return bmi2_set_int_pin_config(&pin_config, dev);
}

static int8_t enable_any_motion_int(bmi270_handle_t dev)
{
    const uint8_t sens_list[2] = { BMI2_ACCEL, BMI2_ANY_MOTION };
    const struct bmi2_sens_int_config sens_int = {
        .type = BMI2_ANY_MOTION,
        .hw_int_pin = BMI2_INT1,
    };

    int8_t rslt = bmi270_sensor_enable(sens_list, 2, dev);
    if (rslt != BMI2_OK) {
        return rslt;
    }

    rslt = configure_any_motion(dev);
    if (rslt != BMI2_OK) {
        return rslt;
    }

    return bmi270_map_feat_int(&sens_int, 1, dev);
}

bool bmi270_pms_arm_any_motion(void)
{
    if (s_armed) {
        return true;
    }

    if (!ensure_i2c_dev(TAB5_I2C_ADDR_BMI270)) {
        ESP_LOGW(TAG, "I2C dev add failed");
        return false;
    }
    if (!modulus_i2c_coex_lock(8000)) {
        ESP_LOGW(TAG, "M-Bus busy — any-motion arm skipped");
        return false;
    }

    memset(&s_bmi2, 0, sizeof(s_bmi2));
    s_bmi2.chip_id = BMI270_CHIP_ID;
    s_bmi2.intf = BMI2_I2C_INTF;
    s_bmi2.read = bmi_reg_read;
    s_bmi2.write = bmi_reg_write;
    s_bmi2.delay_us = bmi2_delay_us;
    s_bmi2.config_file_ptr = bmi270_config_file;
    s_bmi2.read_write_len = 32;

    int8_t rslt = bmi270_init(&s_bmi2);
    if (rslt != BMI2_OK) {
        if (s_i2c_dev) {
            i2c_master_bus_rm_device(s_i2c_dev);
            s_i2c_dev = NULL;
        }
        if (!ensure_i2c_dev(TAB5_I2C_ADDR_BMI270 + 1)) {
            modulus_i2c_coex_unlock();
            ESP_LOGW(TAG, "bmi270_init failed (%d)", rslt);
            return false;
        }
        rslt = bmi270_init(&s_bmi2);
    }
    if (rslt != BMI2_OK) {
        modulus_i2c_coex_unlock();
        ESP_LOGW(TAG, "bmi270_init failed (%d)", rslt);
        return false;
    }

    rslt = enable_any_motion_int(&s_bmi2);
    modulus_i2c_coex_unlock();
    if (rslt != BMI2_OK) {
        ESP_LOGW(TAG, "any-motion INT1 arm failed (%d)", rslt);
        return false;
    }

    s_armed = true;
    ESP_LOGI(TAG, "BMI270 any-motion INT1 -> E_TRG armed");
    return true;
}

void bmi270_pms_disarm_any_motion(void)
{
    if (!s_armed && !s_i2c_dev) {
        return;
    }
    /* Drop PMS I2C handle so poll-path imu_shim can own 0x68 again after wake. */
    if (s_i2c_dev) {
        (void)i2c_master_bus_rm_device(s_i2c_dev);
        s_i2c_dev = NULL;
    }
    s_armed = false;
    ESP_LOGI(TAG, "BMI270 any-motion disarmed (handle released)");
}

bool bmi270_pms_is_armed(void)
{
    return s_armed;
}
