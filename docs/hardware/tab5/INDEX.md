# Tab5 hardware reference (local corpus)

Updated: 2026-06-14

| Topic | File |
|-------|------|
| Connector pinouts (headers) | [pinmap.md](pinmap.md) |
| I2C / RS485 / power bus map | [interconnect.md](interconnect.md) |
| ExtEncoder handwheel (Port A) | [ext-encoder.md](ext-encoder.md) |
| RS-485 grblHAL soak | [rs485-grblhal-soak.md](rs485-grblhal-soak.md) |

Firmware constants: `firmware/tab5/components/modulus_zig/include/tab5_hw.h`  
UI + diagnostics: Settings → **Storage & Diagnostics** → expansion port map + I2C scanner.

Official: [M5Stack Tab5](https://docs.m5stack.com/en/core/Tab5)

## Sensors (internal I2C0)

| Device | Addr | Role |
|--------|------|------|
| BMI270 | 0x68 | IMU (motion wake) |
| INA226 | 0x41 | Battery monitor |
| RX8130CE | 0x32 | RTC |
| ES8388 / ES7210 | 0x10 / 0x40 | Audio codec / AEC ADC |
| PI4IOE5V6408 x2 | 0x43 / 0x44 | IO expander |

**No ambient light sensor (ALS)** on Tab5. Backlight is manual PWM only; camera (SC2356) is not used as a light proxy. Settings -> Display shows auto-brightness disabled with this reason.
