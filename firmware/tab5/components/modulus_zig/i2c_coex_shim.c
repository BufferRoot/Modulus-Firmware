#include "i2c_coex_shim.h"

#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>

static SemaphoreHandle_t s_mutex = NULL;

void modulus_i2c_coex_init(void)
{
    if (s_mutex == NULL) {
        s_mutex = xSemaphoreCreateMutex();
    }
}

bool modulus_i2c_coex_lock(uint32_t timeout_ms)
{
    /* Fail closed until init — early unlocked I2C races BMI270/INA226/PI4IOE. */
    if (!s_mutex) {
        return false;
    }
    return xSemaphoreTake(s_mutex, pdMS_TO_TICKS(timeout_ms)) == pdTRUE;
}

void modulus_i2c_coex_unlock(void)
{
    if (s_mutex) {
        xSemaphoreGive(s_mutex);
    }
}
