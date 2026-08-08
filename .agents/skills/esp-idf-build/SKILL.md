---
name: esp-idf-build
description: >-
  ESP-IDF v6.0 build, flash, monitor, and environment setup for Modulus firmware.
  Use when running idf.py, configuring sdkconfig, setting target chip, or CI build.
---

# ESP-IDF Build & Environment

## Prerequisites

- ESP-IDF **v6.0** installed (`IDF_PATH` set)
- Export env each shell session:

```powershell
# Windows — adjust path to your IDF install
& "$env:IDF_PATH\export.ps1"
idf.py --version
```

## Standard workflow

```powershell
cd firmware
idf.py set-target esp32c6    # or esp32, esp32s3, etc.
idf.py menuconfig            # optional
idf.py build
idf.py flash monitor
idf.py size
idf.py build test            # if test components exist
```

## Clean rebuild

```powershell
idf.py fullclean
idf.py build
```

## Add registry dependency

```powershell
idf.py add-dependency "espressif/cjson^1.7.19"
idf.py add-dependency "espressif/network_provisioning^1.1.0"
```

Creates/updates `main/idf_component.yml` and fetches to `managed_components/`.

## CI checklist

```powershell
idf.py set-target <chip>
idf.py build                 # warnings = errors in 6.0
idf.py size-components
```

## sdkconfig management

- Commit `sdkconfig.defaults` for team defaults; avoid committing full `sdkconfig` if policy prefers per-dev.
- Key v6 defaults to preserve: warnings-as-errors ON, Picolibc ON.

## Troubleshooting

| Issue | Action |
|-------|--------|
| `driver/adc.h: No such file` | Migrate to `esp_adc`; add `REQUIRES esp_adc` |
| orphan section linker error | Linker fragment or remove unused section |
| `wifi_provisioning` not found | Add `espressif/network_provisioning` to `idf_component.yml` |
| mbedtls_sha256 undeclared | Migrate to PSA Crypto |
| FreeRTOS type unknown in driver file | Add explicit FreeRTOS includes |

## Agent pipeline

1. CBM index after `firmware/` sources added
2. Build via shell (`idf.py build`) — no dedicated ESP-IDF MCP in project
3. Token Savior for symbol nav in large components

## Version pin

Document target IDF in project README or `sdkconfig.defaults` comment:

```
# ESP-IDF v6.0 — do not use legacy v5.x driver headers
```
