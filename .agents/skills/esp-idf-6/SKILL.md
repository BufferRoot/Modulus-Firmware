---
name: esp-idf-6
description: >-
  ESP-IDF v6.0 firmware architecture and v5.x breaking changes — new esp_driver_*
  APIs, Picolibc, PSA Crypto, strict warnings-as-errors, managed component registry.
  Use when writing, reviewing, or migrating ESP32 firmware, CMakeLists, or sdkconfig.
---

# ESP-IDF 6.0 Core

## v5 → v6 at a glance

| Area | v5.x (dead in 6.0) | v6.0 requirement |
|------|-------------------|------------------|
| ADC | `driver/adc.h` | `esp_adc/adc_oneshot.h`, `adc_continuous.h`, `adc_cali*.h` → `esp_adc` |
| DAC | `driver/dac.h` | `driver/dac_oneshot.h`, `dac_continuous.h`, `dac_cosine.h` → `esp_driver_dac` |
| I2S | `driver/i2s.h` | `driver/i2s_std.h`, `i2s_pdm.h`, `i2s_tdm.h` → `esp_driver_i2s` |
| Timer | `driver/timer.h` | `driver/gptimer.h` → `esp_driver_gptimer` |
| PCNT | `driver/pcnt.h` | `driver/pulse_cnt.h` → `esp_driver_pcnt` |
| MCPWM | `driver/mcpwm.h` | `driver/mcpwm_prelude.h` → `esp_driver_mcpwm` |
| RMT | `driver/rmt.h` | `driver/rmt_tx.h`, `rmt_rx.h`, `rmt_encoder.h` → `esp_driver_rmt` |
| Temp | `driver/temp_sensor.h` | `driver/temperature_sensor.h` → `esp_driver_tsens` |
| Provisioning | `wifi_provisioning` / `wifi_prov_*` | Registry `espressif/network_provisioning` / `network_prov_*` |
| JSON | in-tree `cjson` | Registry `espressif/cjson` |
| LibC | Newlib default | **Picolibc** default |
| Crypto | `mbedtls_sha*`, etc. | **PSA Crypto** (`psa_*`) via Mbed TLS 4.x / TF-PSA-Crypto |
| Compiler | warnings optional | **warnings = errors** by default |

**I2C note:** `driver/i2c.h` is **EOL** in 6.0 (removed v7.0). Migrate to `driver/i2c_master.h` / `i2c_slave.h` now.

## Driver overhaul

Legacy umbrella `driver` component no longer re-exports `esp_driver_*`. Each peripheral needs explicit `REQUIRES`:

```cmake
idf_component_register(
    SRCS "main.c"
    INCLUDE_DIRS "."
    REQUIRES esp_driver_gptimer esp_driver_gpio nvs_flash
)
```

**Init lifecycle (all new drivers):**

1. Fill `*_config_t` struct (defaults via `*_DEFAULT()` macros where provided)
2. `*_new_*` / `*_install` → receive opaque handle
3. Optional channel/encoder setup (RMT, MCPWM)
4. `*_enable` before use
5. On teardown: `*_disable` → `*_del` / `*_uninstall`

**Removed manual concerns:**

- Peripheral clock gating — handled inside drivers (don't call removed `periph_ctrl.h` APIs)
- `io_loop_back` — bind same GPIO in TX/RX drivers instead

## Picolibc transition

- Default libc is **Picolibc** (smaller flash/stack vs Newlib on I/O).
- **Breaking:** cannot redefine stdin/stdout/stderr per-task; streams are global (POSIX).
- `CONFIG_LIBC_PICOLIBC_NEWLIB_COMPATIBILITY` (default **y**) — thread-local stdio shims; disable only if no Newlib-built libs linked.
- Switch back to Newlib: `CONFIG_LIBC` → Newlib in menuconfig (not recommended for new projects).
- `assert(X)` under `NDEBUG`: expression **not evaluated** by default (`CONFIG_COMPILER_ASSERT_NDEBUG_EVALUATE=n`) — C standard compliant.

**Firmware implications:** prefer bounded buffers, avoid heavy `printf` float formatting in hot paths, watch stack on stdio.

## PSA Crypto API

ESP-IDF 6.0 → Mbed TLS **4.x**; cryptography lives in **TF-PSA-Crypto**. Legacy `mbedtls_*` crypto primitives largely **removed**.

**Rules:**

- New crypto code: `#include "psa/crypto.h"` — use `psa_*` APIs.
- IDF init calls `psa_crypto_init()` during normal boot; **early init** (pre-startup, custom boot) must call it explicitly before any crypto (including cert/key parse, TLS handshake).
- Hardware ECDSA: use `esp_ecdsa_opaque_key_t` + `psa_import_key()`, not removed `esp_ecdsa_pk_conf_t` helpers.
- RNG callback params removed from several APIs — PSA RNG used internally.
- Avoid `mbedtls/private/*` and private struct field access.
- TLS 1.2: finite-field DHE / RSA key exchange without FS removed; curves < 250 bits unsupported in certs/TLS.

```c
#include "psa/crypto.h"

void early_crypto_setup(void) {
    psa_status_t status = psa_crypto_init();
    if (status != PSA_SUCCESS) { /* handle */ }
    // psa_hash_*, psa_sign_*, psa_import_key, etc.
}
```

## Strict compilation

- `CONFIG_COMPILER_DISABLE_DEFAULT_ERRORS` default **N** → treat compiler warnings as errors.
- Default C **gnu23**, C++ **gnu++26** — may surface new warnings.
- Orphan linker sections → **error** (was tolerated); fix with linker fragments or remove dead sections.
- Global constructor order now ascending via `__libc_init_array()` — don't rely on reverse `.ctors` order on Xtensa.

**Do not** disable warnings to ship code. Fix root cause.

Temporary migration escape hatch (discouraged): `CONFIG_COMPILER_DISABLE_DEFAULT_ERRORS=y`.

## Managed component registry

Components moved out of ESP-IDF tree — declare in `main/idf_component.yml`:

```yaml
dependencies:
  espressif/cjson:
    version: "^1.7.19"
  espressif/network_provisioning:
    version: "^1.1.0"
  espressif/esp-mqtt:
    version: "^2"
```

**network_provisioning API renames (sample):**

| Legacy | v6 |
|--------|-----|
| `wifi_prov_mgr_is_provisioned` | `network_prov_mgr_is_wifi_provisioned` |
| `wifi_prov_mgr_reset_provisioning` | `network_prov_mgr_reset_wifi` |

For v5→v6 hybrid: `set(EXCLUDE_COMPONENTS wifi_provisioning)` in project `CMakeLists.txt`.

Also registry-moved: `esp_sysview`, `esp_gcov`, `touch_element`, `usb` — add via `idf.py add-dependency "espressif/<name>"`.

## Error safety (IDF pattern)

Every driver/API returns `esp_err_t`. Unchecked returns cause silent firmware bugs.

```c
#define CHECK(x) do { \
    esp_err_t __e = (x); \
    if (__e != ESP_OK) { \
        ESP_LOGE(TAG, "%s:%d %s", __func__, __LINE__, esp_err_to_name(__e)); \
        return __e; \
    } \
} while (0)
```

Prefer IDF macros: `ESP_RETURN_ON_ERROR`, `ESP_GOTO_ON_ERROR`, `ESP_ERROR_CHECK` (only when abort acceptable).

**Resource cleanup on error:** reverse-order teardown matching init; use `goto fail` label with centralized cleanup (IDF equivalent of errdefer).

**Error return traces:** ESP-IDF uses `esp_err_t` chains + logging, not Zig-style traces. Log at boundary with context (tag, line, `esp_err_to_name`).

## Anti-patterns (v5 habits)

| v5 habit | v6 fix |
|----------|--------|
| `#include "driver/adc.h"` | `esp_adc/adc_oneshot.h` + `REQUIRES esp_adc` |
| `i2s_set_adc_mode()` | removed — use ADC + I2S std driver separately |
| `component: cjson` in CMake | `idf_component.yml` → `espressif/cjson` |
| `mbedtls_sha256_*` | `psa_hash_setup/update/finish` |
| Skip `esp_err_t` on init | Always check; abort boot or enter safe mode |
| Implicit `freertos/semphr.h` via driver | Explicit `#include` |

## Deep dive

See [driver-map.md](driver-map.md) for full legacy→new header table and example CMake deps.

Migration index: https://docs.espressif.com/projects/esp-idf/en/v6.0/esp32/migration-guides/release-6.x/6.0/index.html
