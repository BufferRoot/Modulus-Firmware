# Schematics & wiring

Electrical diagrams, photos, and wiring notes for Modulus (Tab5, ExtEncoder, E-Stop, NanoH2, S3 bridge, RS-485 / COMMU).

| File | Description |
|------|-------------|
| `IMG20260808000044.jpg` | Wiring / assembly photo |
| `Screenshot 2026-08-08 005107.png` | Schematic / interconnect capture |
| `Screenshot 2026-08-08 103910.png` | Schematic / interconnect capture |
| `Screenshot 2026-08-08 105146.png` | Schematic / interconnect capture |

Firmware sources of truth: `firmware/tab5/.../tab5_hw.h`, `firmware/nanoh2/main/nanoh2_hw.h`, `firmware/s3-bridge/main/bridge_config.h`. Quick Tab5 overview: root [README](../README.md#pinout-tab5).

---

## 1. Tab5 pendant — Port A, NanoH2, E-Stop

```
Handwheel ──► ExtEncoder 0x59 ──Port A Grove (I2C1)──► Tab5 front
NanoH2 Grove ── UART2 + 5V/GND ──────────────────────► Tab5 M5-Bus rear
E-Stop NO ── G16 ↔ GND ──────────────────────────────► Tab5 M5-Bus pin 2
```

Enable **EXT5V** in Power settings (PI4IOE1 P2) for Port A Grove and M5-Bus pin 28 (`SYS_EXT5VO`).

### ExtEncoder / handwheel → Port A (front HY2.0-4P)

I2C1 @ **0x59**. Use front Port A only — not rear M5-Bus.

| ExtEncoder (Grove) | Tab5 Port A | Signal |
|--------------------|-------------|--------|
| GND (black) | Pin 1 | GND |
| 5V (red) | Pin 2 | EXT5V |
| SDA (yellow) | Pin 3 **G53** | I2C1 SDA |
| SCL (white) | Pin 4 **G54** | I2C1 SCL |

### NanoH2 → M5-Bus (UART2)

Cross TX↔RX. GPIO6 shared with COM.X STAMP — leave STAMP empty.

| NanoH2 Grove | Tab5 M5-Bus | P4 GPIO | Notes |
|--------------|-------------|---------|-------|
| G1 white **TX** (GPIO1) | Pin **15** G13/RXD2 | **GPIO7** | H2 TX → P4 RX |
| G2 yellow **RX** (GPIO2) | Pin **16** G14/TXD2 | **GPIO6** | P4 TX → H2 RX |
| GND | Pin 1 / 3 / 5 | — | Common ground |
| 5V | Pin **28** SYS_EXT5VO | — | EXT5V_EN gated |

Default link baud: **460800**.

### E-Stop → M5-Bus

Momentary **NO** to GND. Firmware toggle-latches (press ON, press again OFF). Internal pull-up; press → G16 LOW.

| E-Stop | Tab5 M5-Bus | Behavior |
|--------|-------------|----------|
| One side | Pin **2** **G16** | Input, pull-up |
| Other side | Pin 1 / 3 / 5 **GND** | Press → LOW |

Pendant E-Stop is convenience only — machine mushroom is primary.

---

## 2. ESP32-S3 cabinet bridge → grblHAL

```
Tab5 P4 ──SDIO2──► C6 (ESP-NOW) ──air──► S3 bridge ──UART1──► Flexi-HAL
```

Board: ESP32-S3-MINI-1 on I2C_ESP32_Module / handwheel interface (pads SDA_host / SCL_host = UART). **3.3 V** logic — no level shifter. Cross TX↔RX.

### S3 ↔ Flexi-HAL UART (required)

| ESP32-S3 | Pad / role | Flexi-HAL (USART6) | Direction |
|----------|------------|--------------------|-----------|
| **GPIO8** | TX (SDA_host) | **PC7** USART6_RX | S3 → HAL (commands) |
| **GPIO9** | RX (SCL_host) | **PC6** USART6_TX | HAL → S3 (status / DRO) |
| GND | GND | GND | Common |

- Port: **UART1** (UART0 = USB shell)
- Default baud: **921600** (shell: `baud`, `txgpio`, `rxgpio`; NVS may hold an older rate)

### HALT_host

| ESP32-S3 | Signal | Note |
|----------|--------|------|
| **GPIO37** | HALT_host | Active **LOW**; pull-up on Flexi-HAL side |

Driven by Tab5 `MOD_HALT1` / `MOD_HALT0` over ESP-NOW.

### Activity LEDs (on board)

| GPIO | Silk | Meaning |
|------|------|---------|
| **45** | LED_R / D3 | Pulse on TX (S3 → HAL) |
| **46** | LED_G / D2 | Pulse on RX (HAL → S3) |

### ESP-NOW (no copper to Tab5)

| Item | Value |
|------|-------|
| Path | C6 ↔ S3 ESP-NOW (not P4-native Wi-Fi) |
| Channel | Match Tab5: **1 / 6 / 11** |
| Peer | Tab5 Settings → Wireless → ESP-NOW → **S3 MAC** |
| Encrypt | Plain ESP-NOW (PMK breaks CNC path) |

Bring-up: common GND → USB shell `board mini1` or `board xiao` (sets pinout, saved) → `uartping` → Tab5 ESP-NOW MAC + channel.

### Seeed XIAO ESP32-S3 (same firmware, `-Board xiao`)

ESP32-S3R8: **do not** use GPIO33–37 (octal PSRAM) or GPIO37 HALT from the MINI-1 map.

| XIAO | GPIO | Flexi-HAL / role |
|------|------|------------------|
| **D6 TX** | 43 | USART6_RX (commands) |
| **D7 RX** | 44 | USART6_TX (status) |
| **D0** | 1 | HALT_host active LOW |
| GND | GND | Common |
| User LED | 21 | TX+RX pulse (active LOW) |

Shell: USB-C Serial/JTAG. Build: `.\scripts\build_s3_bridge.ps1 -Board xiao`
