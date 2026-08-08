# Tab5 interconnect — firmware bus map

## I2C (two independent controllers)

| Logical bus | IDF port | SDA | SCL | Physical access |
|-------------|----------|-----|-----|-----------------|
| **Internal M-Bus** | I2C **0** (`CONFIG_BSP_I2C_NUM`) | G31 | G32 | Onboard only; **ExtPort2** pins 5–6; **M5-Bus** pins 17–18 |
| **Port A Grove** | I2C **1** (`TAB5_EXT_I2C_PORT`) | G53 | G54 | **Port A** Grove header only |

### Internal M-Bus devices (typical scan)

| Addr | Device |
|------|--------|
| 0x10 | ES8388 |
| 0x40 | ES7210 |
| 0x14 | GT911 |
| 0x55 | ST7123 |
| 0x68 | BMI270 |
| 0x32 | RX8130 |
| 0x41 | INA226 |
| 0x43 | PI4IOE1 (EXP1) |
| 0x44 | PI4IOE2 (EXP2) |

### Port A devices (typical scan)

| Addr | Device |
|------|--------|
| 0x59 | M5 Unit ExtEncoder (handwheel MPG) |
| 0x50+ | User I2C modules / I2C CNC transport (configurable) |

**EXT 5V** must be ON for powered Grove units (encoder, many Units). Controlled via PI4IOE1 P2; default ON in NVS.

## RS-485

UART **1**: TX=G20, RX=G21, DE=G34. Transceiver A/B on **ExtPort2** and screw terminal.

## Power rails (expansion-relevant)

| Rail | Control | Connectors |
|------|---------|------------|
| EXT 5V | PI4IOE1 P2 / NVS `ext5v` | Port A pin 2, ExtPort1 bottom |
| USB 5V Out | PI4IOE2 P3 / NVS `usb5v` | USB Type-A |
| HVIN | Battery / barrel path | ExtPort1/2, M5-Bus |
| 3V3 / SYS-5V | PMIC | ExtPort1, COM.X, M5-Bus |

## Firmware modules

| Concern | File |
|---------|------|
| Constants | `tab5_hw.h` |
| Port A I2C1 init | `tab5_ext_i2c.c` |
| Bus scan | `mbus_shim.c`, `i2c_scan_shim.c` |
| ExtEncoder | `ext_encoder_shim.c` |
| RS-485 transport | `serial_shim.c` / grblHAL path |
| EXT5V rail | `tab5_pi4ioe.c`, `power_shim.c` |

## Port A — GPIO matrix vs I2C controller

Schematic nets **STD_GPIO53/54** are **not** “non-I2C.” ESP32-P4 muxes **I2C1** onto those pins in firmware (`i2c_new_master_bus` with `i2c_port=1`). Same pattern as G31/G32 + I2C0 on the internal M-Bus.

| Mistake | Symptom |
|---------|---------|
| Use **I2C0** on G53/G54 | `ESP_ERR_TIMEOUT`, empty Port A scan |
| Skip **I2C driver init** (treat as raw GPIO) | No clock on SCL, probe timeout |
| **CAN transport** active on Port A | TWAI owns G53/G54 — conflicts with I2C (`canbus_shim.c`) |

## Common mistakes

1. **ExtEncoder on M5-Bus or ExtPort2** — must use **Port A Grove** (G53/G54).
2. **EXT 5V off** — Port A scan empty; enable in Power settings.
3. **Confusing ExtPort1 with Port A** — ExtPort1 is GPIO_EXT (G0/G1/G49/G50), not I2C53/54.
4. **Expecting separate rear I2C** — M5-Bus Int SDA/SCL is the **same** I2C0 as onboard sensors.
5. **Schematic STD_GPIO label** — still requires **I2C1 init**; label describes silicon pin type, not host protocol.
