# Modulus Firmware

**Version:** 0.1.0 (beta)  
**Author:** D. McLean / BufferRoot  
**Platform:** M5Stack Tab5 (ESP32-P4 + ESP32-C6)  
**Stack:** Zig 0.16 + ESP-IDF 6  
**Hackster:** [Modulus pendant](https://www.hackster.io/BufferRoot/modulus-the-ultimate-universal-smart-cnc-pendant-2587ed)  
**License:** TBD

Modulus is a wireless CNC **pendant OS** for the Tab5. It moves the machine interface off a stationary terminal onto a handheld DRO + MPG — shop-floor mobility without giving up the latency precision machining needs.

Built primarily around **grblHAL** (also Grbl, FluidNC, LinuxCNC, Mach3/Mach4, Masso), Modulus splits UI and motion-side work across the P4’s dual cores and keeps RF on dedicated coprocessors so the HMI never fights the control loop.

---

## Dual-core architecture

Wireless CNC fails when the HMI starves the motion path. Modulus pins responsibilities:

### Core 0 — Multimedia & HMI

- **UI:** 1280×720 MIPI-DSI via LVGL — DRO, overrides, settings, connect flows
- **Audio:** ES8388 cues for alarms / feedback
- **Persistence:** NVS for settings, peers, PIN policy — off the control loop

### Core 1 — Real-time control

- **Session engine:** ~100 Hz poll — machine state, offsets, overrides, modal mirror
- **Jog path:** ExtEncoder (I²C) with 0.001 / 0.01 / 0.1 / 1.0 mm steps; heap-free dispatch
- **DSP:** 1024-point FFT pipeline on-device (esp-dsp); **on-screen FFT UI is roadmap**, not shipped in beta UI
- **Power:** INA226 battery telemetry (V / A / %)

Radios are split on purpose: **C6** = ESP-NOW / Wi-Fi / BLE; **NanoH2** = Zigbee shop IoT — motion RF and accessories do not share one radio stack.

---

## Features

### Precision control & jogging

- Real-time jog via external I²C handwheel
- Dynamic step scaling: 0.001–1.0 mm
- MPG-aware sync with controller state (buffer overrun avoidance)
- 3–6 axis UI with active WCS tracking

### Transport layer

Transport-agnostic; switch from Settings for shop RF / wiring:

| Path | Role |
|------|------|
| **ESP-NOW** (C6 → S3 bridge) | Primary low-latency wireless (field-verified Connected) |
| Telnet / WebSocket | TCP/IP |
| BLE NUS | Wireless UART-style link |
| RS-485 / Serial | Wired field bus (COMMU for extra RS-485 / TTL / CAN / I2C) |

### Diagnostics & telemetry

- Core 1 DSP / FFT pipeline (UI surface still roadmap)
- INA226 power tab — voltage, current, pack %
- Aggressive `$I+` / `?` parsing → local modal / feed / spindle mirror

### Security & reliability

- Dual-core isolation — UI work cannot starve the ~100 Hz path
- Configurable PIN lock in NVS
- Settings (MAC/IP peers, brightness, units, transport) survive reboot / deep sleep
- Soft fail-safes; keep the machine E-Stop in reach (beta)

---

## Wireless data flow (ESP-NOW primary)

```
Tab5 (P4 UI + Core 1)
   │  SDIO → C6 (ESP-NOW)
   ▼
ESP32-S3 bridge  ──UART / TCP──►  CNC controller (e.g. grblHAL)
```

Flash matching C6 + P4 images together. Lock ESP-NOW to channel 1 / 6 / 11. Never rebuild C6 with `-ZigbeeExclusive` (Zigbee belongs on NanoH2).

---

## Directory layout

```
src/modulus/         Zig: state, jog math, cnc_proto, envelope, ABI
firmware/tab5/       P4 app: IDF / BSP / LVGL C shims + modulus_zig
firmware/nanoh2/     H2 Zigbee coordinator
firmware/s3-bridge/  ESP-NOW ↔ UART bridge
scripts/             Build / flash PowerShell helpers
```

On-device Settings covers transport, peers, PIN, display, and units — no rebuild required for day-to-day config.

---

## Build & flash

### Prerequisites

- Zig **0.16+**
- ESP-IDF **6.0**
- Target: `esp32p4` (Tab5 host)

### Host checks

```bash
git clone https://github.com/BufferRoot/Modulus-Firmware.git
cd Modulus-Firmware
zig build test
```

### Device (Windows)

```powershell
zig build tab5-lib
.\scripts\build_tab5.ps1
.\scripts\flash_tab5.ps1 -Port COM5
.\scripts\flash_tab5_dual.ps1 -C6Port COM6 -P4Port COM5   # never -ZigbeeExclusive
# NanoH2: idf.py -C firmware/nanoh2 flash (hold BUTTON). Enable EXT5V.
.\scripts\build_s3_bridge.ps1 -Action flash -Port COM8
```

More detail (BOM, pinout, contest write-up): `Modulus_Hackster_Documentation.md`.
