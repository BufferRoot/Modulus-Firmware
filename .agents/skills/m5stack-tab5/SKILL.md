---
name: m5stack-tab5
description: >-
  M5Stack Tab5 (ESP32-P4 + ESP32-C6) hardware architecture — dual-chip SDIO hosted
  wireless, ST7123 MIPI-DSI 1280x720, SC2356 CSI, ES8388/ES7210 audio, BMI270 IMU
  shutdown constraint, INA226/RX8130 power. Use with M5Unified, M5GFX, or esp-bsp
  m5stack_tab5. Use when building Tab5 firmware, UI, camera, audio, or networking.
---

# M5Stack Tab5 Hardware

**Local reference (read first):** `docs/hardware/tab5/INDEX.md` — specs, pinmap, interconnect, expander, hosted SDIO, power rules, BSP constants, GitHub index.

## Dual-chip topology

```
┌─────────────────────────────────────────────────────────┐
│  ESP32-P4 (HOST)                                        │
│  App, UI, LVGL/M5GFX, MIPI-DSI/CSI, USB, RS485, I2C    │
│  NO Wi-Fi / BLE / 802.15.4 radio                        │
└───────────────────────┬─────────────────────────────────┘
                        │ SDIO2 (4-bit)
                        │ CLK12 CMD13 D0-11 D1-10 D2-9 D3-8
                        │ RESET15
┌───────────────────────▼─────────────────────────────────┐
│  ESP32-C6-MINI-1U (SLAVE / co-processor)                │
│  Wi-Fi 6, Thread, Zigbee — ESP-Hosted slave firmware    │
└─────────────────────────────────────────────────────────┘
```

| Chip | Role | Memory |
|------|------|--------|
| ESP32-P4NRW32 | Application processor | 16MB Flash, 32MB Octal PSRAM |
| ESP32-C6-MINI-1U | Wireless co-processor | Own flash (hosted slave image) |

**Critical:** P4 cannot drive RF. All `WiFi.*`, `esp_wifi_*`, BLE, Thread stack traffic goes to C6 through **ESP-Hosted-MCU** RPC over SDIO.

## Wireless data path (conceptual)

Application on P4 wants HTTP GET:

1. **P4 app** calls normal API (`WiFi.h`, `esp_http_client`, sockets on `esp_netif`).
2. **esp_wifi_remote** presents a Wi-Fi/netif façade on P4; real driver runs on C6.
3. **esp_hosted** serializes RPC (connect, scan, TX/RX frames) over **SDIO2** to C6.
4. **C6 slave** executes Wi-Fi 6 stack, TCP/IP (split per hosted config), returns payloads.
5. **P4 lwIP** receives data as if local — app unchanged at high level.

**Prerequisites before any network call:**

- C6 powered (`WLAN_PWR_EN` via PI4IOE5V6408)
- SDIO transport initialized (`esp_hosted` link up / `WiFi.setPins()` + hosted init)
- Slave firmware compatible with host `esp_hosted` version

**Do not:** bit-bang Wi-Fi on P4, talk to C6 with ad-hoc UART for production Wi-Fi, or use P4-Function-EV-Board SDIO pin defaults.

## Tab5 SDIO2 pin map (non-default)

| Signal | P4 GPIO |
|--------|---------|
| CLK | 12 |
| CMD | 13 |
| D0 | 11 |
| D1 | 10 |
| D2 | 9 |
| D3 | 8 |
| RESET | 15 |
| IO2 | 14 |

Antenna: PI4IOE `RF_PTH_L_INT_H_EXT` — low=internal 3D, high=external MMCX.

## Display & touch

| Spec | Value |
|------|-------|
| Panel | 5″ IPS 1280×720 |
| Interface | MIPI-DSI (2 lane), backlight GPIO22 |
| Driver IC | **ST7123** (integrated touch, Oct 2025+ units) |
| Legacy | ILI9881C + GT911 (I²C 0x14) |
| Future | ST7121 (per M5 revision notes — verify sticker) |

**M5Unified + M5GFX** (latest) handle controller detection and init timing (incl. ST7123 post-SLPOUT delays on IDF 5.5+).

ESP-IDF path: `espressif/m5stack_tab5` BSP or `espp/m5stack-tab5` C++ HAL — auto-detect ILI9881 vs ST7123.

Touch I²C: SCL=32, SDA=31, INT=23 (GT911 path); ST7123 touch at 0x55 when integrated.

## Media peripherals

| Device | Interface | I²C / notes |
|--------|-----------|-------------|
| SC2356 camera | MIPI-CSI | 2MP 1600×1200; CAM I²C SCL=32 SDA=31 |
| ES8388 codec | I²S + I²C 0x10 | MCLK=30, BCLK=27, LRCK=29, DOUT=26 |
| ES7210 AEC | I²S + I²C 0x40 | Dual mic front-end; ASDOUT=28 |
| NS4150B speaker | Amp | SPK_EN via PI4IOE |
| Headphone | 3.5mm | HP_DET via PI4IOE |

Use BSP/`esp_codec_dev` or M5Unified audio helpers — do not raw-bitbang I²S without codec init sequence.

## Power, RTC, safeguards

| Component | Function |
|-----------|----------|
| INA226 (0x41) | Bus voltage/current monitor (I²C) |
| RX8130CE (0x32) | RTC + alarm wake (I²C) |
| IP2326 | Charge management (power-on required to charge) |
| NP-F550 | 7.4V removable battery |
| PI4IOE5V6408 ×2 | Rail enables, LCD/TP/CAM reset, **WLAN_PWR_EN**, **PWROFF** |

### IMU / shutdown constraint (MANDATORY)

Official M5 guidance:

- **Always soft-shutdown** (double-press power) before removing battery or cutting supply.
- If power lost **abruptly**, wait **≥5 seconds** before next boot.
- Reason: **BMI270** (0x68) voltage rails fault; IMU fails to reinit on next boot without delay.

Charging: Tab5 charges only when **powered on and initialized** — not when fully off.

## IO expander (PI4IOE5V6408)

Controls resets and power domains application code must not assume are default-on:

- `WLAN_PWR_EN` — C6 power
- `LCD_RST`, `TP_RST`, `CAM_RST`
- `PWROFF_PLUSE` — controlled shutdown pulse
- `EXT5V_EN`, `USB5V_EN`, `SPK_EN`

Initialize via M5Unified/BSP — do not skip expander setup.

## Framework choice

| Stack | Libraries |
|-------|-----------|
| **Arduino (recommended UI)** | M5Unified ≥0.2.8, M5GFX ≥0.2.11, board M5Tab5 or ESP32P4 + setPins |
| **ESP-IDF 6.0** | `espressif/m5stack_tab5`, `esp_hosted`, `esp_wifi_remote`, LVGL port |

Factory reference: M5 Tab5 ESP-IDF factory firmware + BSP examples on esp-bsp.

## Anti-patterns

| Wrong | Right |
|-------|-------|
| WiFi.begin() before M5.begin / hosted init | Board init → setPins → WiFi |
| EV-board SDIO pins on Tab5 | Tab5 SDIO2 table above |
| Hard power off | Soft shutdown + optional RTC save |
| Custom ILI9881 code on ST7123 unit | M5Unified/BSP auto-detect |
| Direct C6 UART for Wi-Fi in app | ESP-Hosted SDIO |

## Deep dive

- **Local corpus:** [docs/hardware/tab5/INDEX.md](../../../docs/hardware/tab5/INDEX.md)
- [hardware-map.md](hardware-map.md) — condensed pin tables (see local `pinmap.md` for authoritative)
- [wireless-hosted.md](wireless-hosted.md) — ESP-Hosted IDF setup
