# Tab5 expansion headers (pinout)

Physical connector order as silkscreened on Tab5. **G** = ESP32-P4 GPIO unless noted.

## Port A — HY2.0-4P Grove (front, 4×1)

| Pin | Signal |
|-----|--------|
| 1 | GND |
| 2 | **EXT 5V** (PI4IOE1 P2; Settings → Power → EXT 5V) |
| 3 | **G53** (I2C SDA, Port A / I2C controller **1**) |
| 4 | **G54** (I2C SCL) |

**Use for:** M5 Unit ExtEncoder (`0x59`), I2C CNC transport, Grove I2C units.  
**Not** the same connector as ExtPort1/2 or rear M5-Bus.

### Schematic `STD_GPIO53` / `STD_GPIO54` (not “non-I2C”)

On the [Tab5 schematic](https://m5stack-doc.oss-cn-shenzhen.aliyuncs.com/1132/Tab5_Schematics_PDF.pdf), Port A nets are labeled **STD_GPIO53** and **STD_GPIO54** because ESP32-P4 has a **GPIO matrix** — there are no dedicated “I2C-only” balls routed to this Grove header. Firmware must **mux** an I2C controller onto these pins in software.

| Layer | Port A | Internal M-Bus (contrast) |
|-------|--------|---------------------------|
| Schematic net | `STD_GPIO53`, `STD_GPIO54` | `STD_GPIO31`, `STD_GPIO32` (same pattern) |
| Physical header | HY2.0-4P Grove (front) | ExtPort2 pin 5–6, M5-Bus pin 17–18 |
| IDF I2C controller | **I2C1** (`TAB5_EXT_I2C_PORT`) | **I2C0** (`CONFIG_BSP_I2C_NUM`) |
| Init | `tab5_ext_i2c.c` / `bsp_ext_i2c_init()` | `bsp_i2c_init()` |

**M5Tab5-UserDemo BSP** ([`m5stack_tab5.h`](https://github.com/m5stack/M5Tab5-UserDemo/blob/main/platforms/tab5/components/m5stack_tab5/include/bsp/m5stack_tab5.h)): `BSP_EXT_I2C_NUM=1`, `BSP_EXT_I2C_SDA=GPIO53`, `BSP_EXT_I2C_SCL=GPIO54`.

**Wrong assumption:** “STD_GPIO ⇒ bit-bang GPIO, not I2C.” **Correct:** STD_GPIO ⇒ any HP peripheral (I2C1, TWAI, etc.) via matrix; Modulus uses **hardware I2C1 master** @ 100 kHz.

**Grove cable order** ([ExtEncoder docs](https://docs.m5stack.com/en/unit/ExtEncoder%20Unit)): Black GND, Red 5V, **Yellow SDA (G53)**, **White SCL (G54)**.

## ExtPort1 — GPIO_EXT (10-pin, 5×2)

| Row | Pins (left → right) |
|-----|---------------------|
| Top | HVIN, GND, 3V3, **G1**, **G50** |
| Bottom | GND, GND, **EXT 5V**, **G0**, **G49** |

**Use for:** GPIO bit-bang, ADC, custom shields. Shares **EXT 5V** rail with Port A (same PMIC path).

## ExtPort2 — GPIO_EXT + field bus (6×1)

| Pin | Signal |
|-----|--------|
| 1 | GND |
| 2 | HVIN |
| 3 | 485A (SIT3088 A) |
| 4 | 485B (SIT3088 B) |
| 5 | **G31** (Int **SDA** — onboard M-Bus I2C0) |
| 6 | **G32** (Int **SCL**) |

**Use for:** RS-485 (with 120 Ω termination switch) **or** tapping internal I2C.  
I2C scan here = same devices as **M-Bus system** scan in firmware.

## RS-485 — SIT3088 (screw terminal + ExtPort2)

| P4 GPIO | Role |
|---------|------|
| G20 | UART TX |
| G21 | UART RX |
| G34 | DE (driver enable / direction) |

120 Ω termination: switchable on terminal block.

## USB Type-A (host)

| Signal |
|--------|
| GND |
| USB2 D+ |
| USB2 D− |
| USB 5V Out (USB5V_EN via PI4IOE2) |

## USB Type-C (USB 2.0 OTG)

| Signal |
|--------|
| USB1_D+ |
| USB1_D− |
| GND |
| 5VIN |

## COM.X — STAMP pads

G46, G6, G31, G32, G33, G19, G18, G5, GND, 3V3, SYS-5V

## M5-Bus — rear 30-pin (15×2)

| Pin L | Signal | Pin R | Signal |
|-------|--------|-------|--------|
| 1 | GND | 2 | G16 |
| 3 | GND | 4 | G17 PB_IN |
| 5 | GND | 6 | RST / EN |
| 7 | MOSI **G18** | 8 | G45 |
| 9 | MISO **G19** | 10 | G52 PB_OUT |
| 11 | SCK **G5** | 12 | 3V3 |
| 13 | RXD0 **G38** | 14 | G37 TXD0 |
| 15 | PC_RX **G7** | 16 | G6 PC_TX |
| 17 | **Int SDA G31** | 18 | **Int SCL G32** |
| 19 | G3 | 20 | G4 |
| 21 | G2 | 22 | G48 |
| 23 | G47 | 24 | G35 |
| 25 | HVIN | 26 | G51 |
| 27 | HVIN | 28 | 5V |
| 29 | HVIN | 30 | BAT |

**Int I2C** on pins 17–18 = internal sensor bus (not Port A G53/G54).
