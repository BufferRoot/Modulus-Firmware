# Tab5 Hardware Map

**Authoritative local copy:** [docs/hardware/tab5/pinmap.md](../../../docs/hardware/tab5/pinmap.md)

Source: [M5Stack Tab5 docs](https://docs.m5stack.com/en/core/Tab5)

## Processor & memory

| Item | Spec |
|------|------|
| SoC (main) | ESP32-P4NRW32, dual-core RISC-V @ 360MHz + LP core @ 40MHz |
| SoC (wireless) | ESP32-C6-MINI-1U |
| Flash | 16 MB |
| PSRAM | 32 MB Octal |
| RF | **C6 only** — Wi-Fi 6 2.4GHz, Thread, Zigbee |

## MIPI-DSI (LCD)

| P4 | Signal |
|----|--------|
| Dedicated DSI_CLKP/N | DSI clock |
| Dedicated DSI_DATAP0/N0 | Lane 0 |
| Dedicated DSI_DATAP1/N1 | Lane 1 |
| GPIO 22 | LEDA (backlight PWM) |

Panel drivers: ST7123 (current), ILI9881C (legacy batch), ST7121 (future revision per M5 changelog).

## MIPI-CSI (camera SC2356)

| P4 | CAM |
|----|-----|
| G32 / G31 | SCL / SDA |
| G36 | MCLK |
| CSI_* dedicated | D0/D1, CLK differential pairs |

## I²C bus (internal sensors)

Shared SCL=32, SDA=31:

| Device | Addr |
|--------|------|
| ES8388 | 0x10 |
| ES7210 | 0x40 |
| BMI270 | 0x68 |
| RX8130CE | 0x32 |
| INA226 | 0x41 |
| GT911 touch | 0x14 |
| ST7123 touch | 0x55 |
| PI4IOE5V6408 | 0x43, 0x44 |

## ESP32-C6 SDIO2

| P4 GPIO | C6 signal |
|---------|-----------|
| 11 | D0 |
| 10 | D1 |
| 9 | D2 |
| 8 | D3 |
| 13 | CMD |
| 12 | CLK |
| 15 | RESET |
| 14 | IO2 |

## microSD (SDIO1 — separate from C6)

| P4 | SD |
|----|-----|
| 39-44 | DAT0-3, CLK, CMD |

**Note:** C6 uses SDIO **host slot 2** on P4; SD card uses different pins — avoid slot conflicts in hosted config.

## RS485 (SIT3088)

| P4 | Signal |
|----|--------|
| G21 | RX |
| G20 | TX |
| G34 | DIR |

## USB

- Type-A: Host (USB5V_EN via expander)
- Type-C: USB 2.0 OTG

## Motion & wake

- BMI270 INT → PMS150G wake circuit (E_TRG)
- RX8130CE INT → same wake path

## Power UX

| Action | Method |
|--------|--------|
| Power on | Single press (battery or USB present) |
| Soft off | Double-press power |
| Download | Hold reset ~2s until green LED flashes |
| Post-crash boot | Wait 5s if IMU init fails after abrupt power loss |

## Expansion

| Connector | I2C / bus | Notes |
|-----------|-----------|--------|
| **Port A** Grove 4p | I2C1 G53/G54 + EXT5V | ExtEncoder, Grove units |
| **ExtPort2** 6p | Int I2C0 G31/G32 + RS-485 A/B | Same scan as M-Bus |
| **ExtPort1** 10p | GPIO G0/G1/G49/G50 | GPIO_EXT, shares EXT5V |
| **M5-Bus** 30p rear | Int I2C0 pins 17–18 | Not Port A |
| **COM.X** STAMP | Mixed GPIO + G31/G32 | See pinmap.md |

Full pinouts: [docs/hardware/tab5/pinmap.md](../../../docs/hardware/tab5/pinmap.md)

## Revision detection

Check product sticker for display driver generation (ILI9881C vs ST7123 vs ST7121). M5Unified/BSP probes at runtime where possible.
