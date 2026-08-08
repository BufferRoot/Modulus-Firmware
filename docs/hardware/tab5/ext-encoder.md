# M5 Unit ExtEncoder (Port A handwheel)

Tab5 **HY2.0-4P Port A** Grove (4-pin): **GND | EXT 5V | G53 SDA | G54 SCL** — I2C1.  
**Not** ExtPort1/2 or M5-Bus Int I2C (G31/G32). See [pinmap.md](pinmap.md) / [interconnect.md](interconnect.md).

## Unit

| Item | Value |
|------|-------|
| MCU | STM32F030 on ExtEncoder PCB |
| I2C address | **0x59** (7-bit) |
| Speed | 100 kHz |
| Power | **EXT 5V** on Tab5 (Power settings) + unit 5V pin for AB quadrature handwheel |

## I2C register map (firmware v2+)

| Reg | Type | Description |
|-----|------|-------------|
| 0x00 | int32 LE | Raw quadrature count (`encoder_countAB`) |
| 0x10 | int32 LE | Distance mm x1000 (needs perimeter) |
| 0x30 | write | Reset count to 0 |
| 0x40 | int32 LE | Wheel perimeter mm x1000 |
| 0x50 | int32 LE | Pulses per revolution / 2 |
| 0x60 | int32 LE | Zero-pulse counter |
| 0x70 | uint8 | Zero signal mode |
| 0xFE | uint8 | Firmware version |
| 0xFF | uint8 | Changeable I2C address |

Modulus uses **0x00** only for MPG jog; **0xFE** for probe.

## STM32 slave behavior ([internal FW](https://github.com/m5stack/M5Unit-ExtEncoder-Internal-FW))

| Item | Value |
|------|-------|
| MCU I2C | STM32F030 **I2C1** slave, Grove side PA9=SCL PA10=SDA |
| 7-bit address | **0x59** (flash-backed; reg `0xFF` can change) |
| FW version | **2** (`FIRMWARE_VERSION` in `main.c`) |
| Clock stretch | Enabled (`LL_I2C_EnableClockStretching`) |

**Register read protocol (host must match):**

- **Count `0x00`:** M5 Arduino lib uses **repeated-start** (`endTransmission(false)` + `requestFrom`) — OK with `i2c_master_transmit_receive`.
- **FW `0xFE`:** STM32 prepares TX data on **write**; host must **STOP**, then **separate read** — matches `getFirmwareVersion()` in [M5Unit-ExtEncoder](https://github.com/m5stack/M5Unit-ExtEncoder). Repeated-start on `0xFE` fails probe.

**Tab5 host requirements:** Port A **I2C1** (not I2C0) on G53/G54, **EXT5V ON**, ~500 ms settle after rail enable, 100 kHz.

## Firmware path

```
ext_encoder_shim.c (I2C read @ 50-100 Hz, Core 1 sys_task)
  -> ext_encoder.zig poll (cnc_encdiv, cnc_mpgpol from NVS)
  -> driver.cmdJog / cmdJogCancel
  -> grblHAL $J= when MPG active + Idle/Jog
```

NVS: `cnc_encdiv` (1-16 counts per jog step, default 2), `cnc_mpgpol` (per-axis invert bits).

## Handwheel jog prerequisites

1. **EXT5V ON** (Power settings) — Grove pin 2 powers Port A modules.
2. **ExtEncoder @ 0x59** on Port A I2C1 (G53/G54) — confirm via Storage → Scan Port A.
3. **CNC transport connected** — grblHAL session `.ready` (or `.locked` / `.mpg_blocked` with local MPG).
4. **MPG ON** — status-bar toggle (local) or controller `|MPG:1|` in status reports.
5. **Machine Idle or Jog** — not Run/Hold/Alarm.

## Serial debug (Settings → Log level = Verbose)

| Tag | Content |
|-----|---------|
| `ext_encoder` | probe, heartbeat, wheel delta, block codes (1=MPG off, 2=no axis, 3=bad state, 4=session, 5=encdiv sub-step) |
| `grblhal` | outbound `$J=` jog lines and RT bytes (e.g. `0x85` cancel, `0x8B` MPG toggle) |
| `tab5_ext_i2c` | Port A I2C1 init (`BSP_EXT_I2C_NUM`) |

Refs: [M5 ExtEncoder docs](https://docs.m5stack.com/en/unit/ExtEncoder%20Unit), [M5Unit-ExtEncoder](https://github.com/m5stack/M5Unit-ExtEncoder).
