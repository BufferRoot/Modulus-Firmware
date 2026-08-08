# ESP-IDF 6.0 — Driver & Component Map

## Removed legacy headers → replacement

| Peripheral | REMOVED (v6.0) | Component | NEW headers |
|------------|----------------|-----------|-------------|
| ADC | `driver/adc.h` | `esp_adc` | `esp_adc/adc_oneshot.h`, `adc_continuous.h`, `adc_cali.h`, `adc_cali_scheme.h` |
| DAC | `driver/dac.h` | `esp_driver_dac` | `driver/dac_oneshot.h`, `dac_continuous.h`, `dac_cosine.h` |
| I2S | `driver/i2s.h` | `esp_driver_i2s` | `driver/i2s_std.h`, `i2s_pdm.h`, `i2s_tdm.h` |
| Timer Group | `driver/timer.h` | `esp_driver_gptimer` | `driver/gptimer.h` |
| PCNT | `driver/pcnt.h` | `esp_driver_pcnt` | `driver/pulse_cnt.h` |
| MCPWM | `driver/mcpwm.h` | `esp_driver_mcpwm` | `driver/mcpwm_prelude.h` |
| RMT | `driver/rmt.h` | `esp_driver_rmt` | `driver/rmt_tx.h`, `rmt_rx.h`, `rmt_encoder.h` |
| Temp sensor | `driver/temp_sensor.h` | `esp_driver_tsens` | `driver/temperature_sensor.h` |
| Sigma-delta | `driver/sigmadelta.h` | `esp_driver_sdm` | `driver/sdm.h` |

## EOL (still in 6.0, removed v7.0)

| Peripheral | Header | Replacement |
|------------|--------|-------------|
| I2C legacy | `driver/i2c.h` | `driver/i2c_master.h`, `driver/i2c_slave.h` |

## Removed infrastructure headers

| Removed | Use instead |
|---------|-------------|
| `driver/periph_ctrl.h` | automatic in drivers |
| `driver/rtc_cntl.h` | `esp_private/rtc_ctrl.h` (internal) |
| `esp_spiram.h` | `esp_psram.h` |
| `esp_spi_flash.h` | `spi_flash_mmap.h` |
| `soc_memory_types.h` | `esp_memory_utils.h` |
| `intr_types.h` | `esp_intr_types.h` |

## Registry components (common)

```yaml
# main/idf_component.yml
dependencies:
  espressif/cjson:
    version: "^1.7.19"
  espressif/network_provisioning:
    version: "^1.1.0"
  espressif/esp-mqtt:
    version: "^2"
  espressif/esp_sysview:
    version: "^1"
  espressif/usb:
    version: "*"
  espressif/touch_element:
    version: "*"
```

CLI: `idf.py add-dependency "espressif/cjson^1.7.19"`

## Temperature sensor example (v6)

```c
#include "driver/temperature_sensor.h"

esp_err_t init_tsens(temperature_sensor_handle_t *out) {
    temperature_sensor_config_t cfg = TEMPERATURE_SENSOR_CONFIG_DEFAULT(10, 50);
    esp_err_t err = temperature_sensor_install(&cfg, out);
    if (err != ESP_OK) return err;
    return temperature_sensor_enable(*out);
}
```

CMake: `REQUIRES esp_driver_tsens`

## GPTimer example (v6)

```c
#include "driver/gptimer.h"

gptimer_handle_t gptimer = NULL;
gptimer_config_t timer_config = {
    .clk_src = GPTIMER_CLK_SRC_DEFAULT,
    .direction = GPTIMER_COUNT_UP,
    .resolution_hz = 1 * 1000 * 1000, // 1 MHz
};
ESP_RETURN_ON_ERROR(gptimer_new_timer(&timer_config, &gptimer), TAG, "new timer");
```

CMake: `REQUIRES esp_driver_gptimer`

## RMT TX example sketch (v6)

```c
#include "driver/rmt_tx.h"
#include "driver/rmt_encoder.h"

// rmt_new_tx_channel → rmt_enable → transmit with encoder
// Open-drain: gpio_od_enable(pin) — not io_od_mode in config
```

CMake: `REQUIRES esp_driver_rmt esp_driver_gpio`

## PSA hash example

```c
#include "psa/crypto.h"

psa_hash_operation_t op = PSA_HASH_OPERATION_INIT;
psa_status_t s = psa_hash_setup(&op, PSA_ALG_SHA_256);
// psa_hash_update → psa_hash_finish
```

## Project skeleton

```
firmware/
  CMakeLists.txt          # cmake_minimum_required; include($ENV{IDF_PATH}/tools/cmake/project.cmake)
  sdkconfig.defaults      # chip-specific defaults
  main/
    CMakeLists.txt        # REQUIRES with esp_driver_* 
    idf_component.yml     # registry deps
    main.c
  components/             # optional local components
```

Root `CMakeLists.txt`:

```cmake
cmake_minimum_required(VERSION 3.22)
include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(modulus_firmware)
```

## sdkconfig defaults (recommended)

```
CONFIG_COMPILER_DISABLE_DEFAULT_ERRORS=n
# CONFIG_LIBC_PICOLIBC=y  # default in 6.0
```

## References

- Peripherals migration: https://docs.espressif.com/projects/esp-idf/en/v6.0/esp32/migration-guides/release-6.x/6.0/peripherals.html
- Security/PSA: https://docs.espressif.com/projects/esp-idf/en/v6.0/esp32/migration-guides/release-6.x/6.0/security.html
- System/Picolibc: https://docs.espressif.com/projects/esp-idf/en/v6.0/esp32/migration-guides/release-6.x/6.0/system.html
- Build system: https://docs.espressif.com/projects/esp-idf/en/v6.0/esp32/migration-guides/release-6.x/6.0/build-system.html
- Provisioning: https://docs.espressif.com/projects/esp-idf/en/v6.0/esp32/migration-guides/release-6.x/6.0/provisioning.html
