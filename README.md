# Modulus Firmware

Universal smart CNC pendant firmware for **M5Stack Tab5** (ESP32-P4 + ESP32-C6), plus NanoH2 Zigbee hub and ESP32-S3 ESP-NOW bridge.

**Hackster:** [Modulus pendant](https://www.hackster.io/BufferRoot/modulus-the-ultimate-universal-smart-cnc-pendant-2587ed)  
**Stack:** Zig 0.16 + ESP-IDF 6 · License: TBD

## Repo map

| Path | Role |
|------|------|
| `src/modulus/` | Zig: state, jog math, CNC protocols, ABI |
| `firmware/tab5/` | P4 app (IDF/BSP/LVGL + `modulus_zig`) |
| `firmware/nanoh2/` | H2 Zigbee coordinator |
| `firmware/s3-bridge/` | ESP-NOW → UART bridge |
| `scripts/` | Build / flash PowerShell helpers |

## Host checks

```bash
git clone https://github.com/BufferRoot/Modulus-Firmware.git
cd Modulus-Firmware
zig build test
```

## Device build / flash (Windows)

```powershell
zig build tab5-lib
.\scripts\build_tab5.ps1
.\scripts\flash_tab5.ps1 -Port COM5
.\scripts\flash_tab5_dual.ps1 -C6Port COM6 -P4Port COM5   # never -ZigbeeExclusive
# NanoH2: idf.py -C firmware/nanoh2 flash (hold BUTTON). Enable EXT5V.
.\scripts\build_s3_bridge.ps1 -Action flash -Port COM8
```

Requires Zig **0.16+** and ESP-IDF **6.0**. Keep the machine E-Stop reachable; beta firmware — treat motion soaks as field work.

More detail: `Modulus_Hackster_Documentation.md`.
