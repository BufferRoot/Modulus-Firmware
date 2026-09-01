<p align="center">
  <img src="assets/modulus-firmware-hero.png" alt="Modulus Firmware — Tab5 CNC pendant" width="720">
</p>

<p align="center">
  <strong>English</strong> · <a href="README.de.md">Deutsch</a>
</p>

# Modulus Firmware

**Version:** 3.1.0  
**Author:** D. McLean / BufferRoot  
**Platform:** M5Stack Tab5 (ESP32-P4 + ESP32-C6)  
**Stack:** Zig 0.16 + ESP-IDF 6  
**Hackster:** [Modulus pendant](https://www.hackster.io/BufferRoot/modulus-the-ultimate-universal-smart-cnc-pendant-2587ed) · [M5Stack GIC 2026](https://m5stack.com/global-innovation-contest-2026)  
**License:** [MIT](LICENSE)

**One Device, One Software. Real control for any machine — no lag, no brand lock-in, no compromise.**

## Why this feature branch exists

The ESP32-C6 is the Tab5's wireless coprocessor, but updating it traditionally
requires a separate USB/bootloader connection. This branch adds a guarded
**C6 Update** page to the P4 user interface so a compatible C6 application can
be selected from the Tab5 SD card and transferred through the existing
ESP-Hosted SDIO link.

The intended maintenance sequence is therefore **P4 first, C6 second**: install
the P4 firmware that contains the updater, boot Modulus normally, then use
**M Panel → C6 Update** to update the C6. An image check, an explicit
confirmation step, a progress display, and a post-update restart button keep
the operation deliberate; C6 flashing never starts automatically.

Handheld DRO + MPG **client** on Tab5 — Zig dual-core anti-lag firmware talking to grblHAL (and other engines) over ESP-NOW or RS-485. It does not replace your motion controller.

Most M5 projects cram UI and radio onto one busy chip. Modulus uses Tab5 as designed: **P4** dual-core HMI/control, **C6** for Wi-Fi/BLE/ESP-NOW, **NanoH2** for Zigbee — so motion RF and shop-IoT RF never fight.

---

## Four-firmware architecture

```
                 [Operator touch UI + MPG wheel]
                              │
                              ▼
┌──────────────────── ESP32-P4 (Tab5 main MCU) ────────────────────┐
│  Core 0: LVGL 720p Material 3 UI · settings · audio (async)      │
│  Core 1: heap-free ~100 Hz MPG poll · envelope · command stream  │
└─────────┬──────────────────────┬───────────────────────┬─────────┘
          │ SDIO2                │ UART GPIO6/7          │ UART1
          ▼                      ▼                       ▼
┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐
│ ESP32-C6          │  │ NanoH2 (ESP32-H2) │  │ SIT3088 RS-485    │
│ Wi-Fi 6 / BLE /   │  │ ZBOSS Zigbee hub  │  │ wired field bus   │
│ ESP-NOW           │  │ shop automation   │  │                   │
└─────────┬─────────┘  └───────────────────┘  └───────────────────┘
          │ ESP-NOW
          ▼
┌───────────────────┐
│ ESP32-S3 bridge   │ ── UART ──► CNC controller (e.g. grblHAL)
└───────────────────┘
```

| Target | Job |
|--------|-----|
| **P4** | Core 0 = UI · Core 1 = heap-free ~100 Hz MPG / envelope / streams |
| **C6** | Wi-Fi 6, BLE, ESP-NOW only (never Zigbee-exclusive builds) |
| **NanoH2** | Zigbee coordinator @ 460800 baud UART — vacuums, lights, fans |
| **S3 bridge** | Cabinet ESP-NOW → UART to controller |

**Why Zig:** no GC. Core 1 never touches the allocator, so a heavy Core 0 frame cannot stall the handwheel. Error unions + `defer` for deterministic transport cleanup. Zig owns state/jog/ABI (`src/modulus/`); C shims own IDF/BSP/LVGL.

---

## Anti-lag design

| Shop failure | Fix |
|--------------|-----|
| UI redraw delays jog | Dual-core — Core 1 never blocks on LVGL |
| Wi-Fi reconnect freezes pendant | ESP-NOW is connectionless — drop bad frame, run next |
| Bridge backlog under RF hit | Bounded S3 queue — stale frames drop (50 ms TTL) |
| 10 clicks ≠ 10 steps | `envelope.zig` clamp + NVS divider/polarity before send |
| UI refresh starves Core 0 | Dashboard timer floor ≥ 33 ms (never 16 ms under `sw_rotate`) |

**Bench numbers** (grblHAL + ESP-NOW + S3):

| Metric | Value |
|--------|-------|
| Wheel-to-motion latency | **2 ms** |
| MPG poll (Core 1) | ~100 Hz |
| ESP-NOW RTT (P4↔S3) | **25 ms** |
| Late-frame drop TTL | 50 ms |
| UI refresh floor @ 720p | ≥ 33 ms |
| ESP-NOW PHY default | 24M OFDM |
| Cold boot → live DRO | ~16 s |
| Runtime per pack | 8–10+ h (NP-F hot-swap) |

---

## Features

| Feature | Notes |
|---------|--------|
| Live multi-axis DRO + MPG | ExtEncoder; 0.001–1.0 mm detent steps |
| Overrides / hold / cycle / macros | Native commands — no HID keyboard hacks |
| Multi-engine client | grblHAL, Grbl, FluidNC, LinuxCNC, Mach3/4, Masso |
| Multi-transport | ESP-NOW, RS-485, USB serial, WebSocket, Telnet, BLE |
| Zigbee shop IoT | NanoH2 hub — Run can start dust extraction; Hold/Alarm spins down |
| Material 3 UI | Dark/light + accents · 10 settings tabs · Quick Settings · PIN lock |
| Power | INA226 (%, V, A, W) · NP-F hot-swap · PMIC soft shutdown |

**Honest status:** pendant stack complete; **grblHAL over ESP-NOW (Tab5↔S3) field-verified**. Full motion soak + live Zigbee soak still open. Other engines/transports implemented, not all field-verified. Keep the machine E-Stop in reach.

### Transports (`cnc_conn`)

✅ field-verified · 🔧 implemented · ⏳ planned

| Transport | Path | Status |
|-----------|------|--------|
| ESP-NOW | C6 → air → S3 → UART | ✅ |
| RS-485 | UART1 TX20 / RX21 / DE34 | 🔧 |
| USB serial | Direct USB / UART | 🔧 |
| WebSocket | C6 Wi-Fi | 🔧 |
| Telnet | C6 Wi-Fi | 🔧 |
| BLE | NimBLE on C6 | 🔧 |
| I2C | Bus peer | 🔧 |
| CAN | via COMMU | ⏳ |

### Motion engines (`cnc_proto`)

| Engine | Typical transport | Status |
|--------|-------------------|--------|
| grblHAL | ESP-NOW / RS-485 | ✅ |
| Classic Grbl | RS-485 / serial | 🔧 |
| FluidNC | WebSocket | 🔧 |
| LinuxCNC | Telnet | 🔧 |
| Mach3 / Mach4 | Telnet | 🔧 |
| Masso | WebSocket / UDP | 🔧 |

### Safety

Pendant E-Stop is a **convenience layer**, not a safety-rated cutoff. It rides the active link (GPIO16 NO → feed-hold `!` then soft reset). **If the wireless link is down, pendant E-Stop will not stop the machine.** Machine mushroom E-Stop is primary. Software: `envelope.zig` soft limits, zero-while-running confirm, link-offline warnings, low-battery MPG lockout.

**Out of scope (roadmap):** SC2356 camera UI · on-screen FFT · OTA dual-partition · PCNT GPIO quadrature (replace I²C ExtEncoder).

---

## Directory layout

```
src/modulus/         Zig: state, jog math, cnc_proto, envelope, ABI
firmware/tab5/       P4 app: IDF/BSP/LVGL C shims + modulus_zig
firmware/tab5-c6/    C6 ESP-Hosted wireless slave
firmware/nanoh2/     H2 Zigbee coordinator (ZBOSS)
firmware/s3-bridge/  ESP-NOW → UART bridge
cad/                 STL + CAD (enclosure / mounts)
schematics/          Schematics + wiring diagrams
assets/              README media (hero image)
scripts/             Build / flash helpers
tools/               NVS manifest generator (used by zig build)
LICENSE              MIT
```

---

## Prebuilt flash images

Download **v3.1.0** assets (bootloader + partition table + app per target):

**https://github.com/BufferRoot/Modulus-Firmware/releases/tag/v3.1.0**

| Zip | Chip | What it is | Typical port |
|-----|------|------------|--------------|
| `modulus-tab5-p4-v3.1.0.zip` | ESP32-P4 | Pendant UI + control (Zig UI Engine) | COM5 (Tab5 USB) |
| `modulus-tab5-c6-v3.1.0.zip` | ESP32-C6 | ESP-Hosted / ESP-NOW radio | COM6 (C6 USB; hold **BOOT** if needed) |
| `modulus-nanoh2-v3.1.0.zip` | ESP32-H2 | Zigbee shop hub | NanoH2 USB-C (hold **BUTTON**) |
| `modulus-s3-bridge-v3.1.0.zip` | ESP32-S3 | Cabinet ESP-NOW → UART | COM8 (bridge board) |
| `SHA256SUMS.txt` | — | Checksums for every `.bin` | — |

### What you need

1. [esptool](https://docs.espressif.com/projects/esptool/) (`pip install esptool`) **or** ESP-IDF 6 `idf.py` / `python -m esptool`
2. USB cables + drivers for each chip
3. Unzip each package into its own folder (commands below assume you `cd` into that folder)

**Recommended order for this feature branch:** P4 → C6 through the on-device
updater → S3 bridge → NanoH2 (optional). The separate C6 USB procedure is a
recovery path, not the normal update method. Keep the machine E-Stop in reach.

COM ports on your PC may differ — change `-p COMx` to match Device Manager.

### 1. Tab5 P4 (main pendant and C6 updater)

The P4 must contain this feature branch before it can update the C6. Build this
branch with `scripts/build_tab5.ps1`, or use a P4 package produced from this
branch. Then flash its complete P4 set:

```powershell
cd path\to\tab5-p4
esptool.py --chip esp32p4 -p COM5 --before default-reset --after hard-reset write_flash `
  --flash-mode dio --flash-freq 40m --flash-size 16MB `
  0x2000 bootloader.bin `
  0x8000 partition-table.bin `
  0x10000 modulus_tab5.bin
```

Power-cycle the Tab5 and wait for the normal Modulus dashboard. Open **M Panel →
C6 Update** and confirm that the updater page is present before continuing.

### 2. Tab5 C6 through SDIO OTA (normal method)

Build the C6 application with `scripts/build_tab5_c6_modulus.ps1`. The file to
copy is:

```text
firmware/tab5-c6/build/network_adapter.bin
```

It may be renamed to a descriptive name such as
`modulus-c6-ota-2.12.12.bin`; renaming does not change its contents.

1. Format an SD card as FAT32.
2. Copy **only the C6 application image** (`network_adapter.bin`, or its renamed
   equivalent) to the SD-card root.
3. Insert the card into the running Tab5.
4. Open **M Panel → C6 Update**.
5. Select **Refresh SD**, choose the file, and select **Check image**.
6. Verify that the screen identifies an ESP32-C6 application and accepts its
   compatibility check.
7. Select **Flash C6** and confirm the warning. Do not remove power or the SD
   card while the progress bar is moving.
8. After activation succeeds, select **Restart Modulus**. Confirm that the
   dashboard returns and the C6/ESP-NOW connection is available.

> [!WARNING]
> Do **not** put a merged/full-flash image, release ZIP, `bootloader.bin`,
> `partition-table.bin`, or `ota_data_initial.bin` into the OTA updater. Those
> files belong to fixed flash offsets and are not valid OTA application images.

### C6 USB recovery (only if SDIO OTA cannot start)

Use this only if the C6 no longer boots far enough for ESP-Hosted/SDIO OTA.
Unzip the complete C6 flash package, connect the C6 USB bootloader, then run:

```powershell
cd path\to\tab5-c6
esptool.py --chip esp32c6 -p COM6 --before default-reset --after hard-reset write_flash `
  --flash-mode dio --flash-freq 80m --flash-size 4MB `
  0x0 bootloader.bin `
  0x8000 partition-table.bin `
  0xd000 ota_data_initial.bin `
  0x10000 network_adapter.bin
```

If the port never appears, hold **BOOT** on the C6 while connecting USB. After
recovery, power-cycle the Tab5.

### 3. ESP32-S3 bridge (cabinet)

Unzip `modulus-s3-bridge-v3.1.0.zip`, then:

```powershell
cd path\to\s3-bridge
esptool.py --chip esp32s3 -p COM8 --before default-reset --after hard-reset write_flash `
  --flash-mode dio --flash-freq 80m --flash-size 8MB `
  0x0 bootloader.bin `
  0x8000 partition-table.bin `
  0x10000 s3_espnow_uart_bridge.bin
```

Wire S3 UART to your CNC (grblHAL) serial. On the Tab5: **Settings → Wireless → ESP-NOW → enter S3 MAC**, lock channel **1 / 6 / 11**.

### 4. NanoH2 (Zigbee hub, optional)

Enable **EXT5V** for Grove/H2 power. Unzip `modulus-nanoh2-v3.1.0.zip`, hold **BUTTON** on the Stamp, then:

```powershell
cd path\to\nanoh2
esptool.py --chip esp32h2 -p COM7 --before default-reset --after hard-reset write_flash `
  --flash-mode dio --flash-freq 48m --flash-size 4MB `
  0x0 bootloader.bin `
  0x8000 partition-table.bin `
  0x10000 modulus_nanoh2.bin
```

UART to Tab5 is GPIO6 TX / GPIO7 RX @ 460800. **Never** flash C6 with Zigbee-exclusive builds — Zigbee stays on NanoH2.

### Verify

- Compare downloaded `.bin` hashes to `SHA256SUMS.txt`
- After P4+C6: idle dashboard ≥ ~55 s with no IDLE0 WDT
- ESP-NOW path: status shows **Connected** once S3 MAC/channel are set

Each zip also includes `FLASH.md` with the same offsets.

---

## Build from source

**Prerequisites:** Zig **0.16+** · ESP-IDF **6.0**

```bash
git clone https://github.com/BufferRoot/Modulus-Firmware.git
cd Modulus-Firmware
zig build test        # host logic + ABI parity
zig build tab5-lib    # freestanding Zig library
```

| Target | Command |
|--------|---------|
| Tab5 P4 | `.\scripts\build_tab5.ps1` then `.\scripts\flash_tab5.ps1 -Port COM5` |
| Tab5 C6 + P4 | `.\scripts\flash_tab5_dual.ps1 -C6Port COM6 -P4Port COM5` *(never `-ZigbeeExclusive`)* |
| NanoH2 | `idf.py -C firmware/nanoh2 flash` (hold BUTTON; enable EXT5V) |
| S3 bridge | `.\scripts\build_s3_bridge.ps1 -Action flash -Port COM8` |
| S3 XIAO | same image: USB shell `board xiao` (or factory ` -Board xiao`) then flash |

> **Use the build scripts — plain `idf.py build` is not supported for Tab5 P4.**
>
> `scripts/build_tab5.ps1` runs `scripts/patch_tab5_idf6_deps.ps1` first, which
> patches the *managed components* for ESP-IDF 6: `esp_hosted`'s CMakeLists for
> the moved `sdmmc` headers, a retry-safe `gpio_reset_pin` before GPIO
> reconfigure, and the Modulus SDIO diagnostics/drain constants. Those files
> live under `managed_components/`, which is gitignored and regenerated by the
> component manager — so the patches are reapplied on every build and are lost
> after `idf.py fullclean` or a dependency re-solve.
>
> Running `idf.py build` directly gives an image that either fails to compile or
> boots with a broken SDIO link to the C6 (`sdmmc_send_cmd returned 0x107`).
>
> `dependencies.lock` **is tracked** for every firmware. Do not delete it to
> "get newer components": an unpinned re-solve pulls releases that assume a
> newer IDF than 6.0.1 and the build breaks
> ([#2](https://github.com/BufferRoot/Modulus-Firmware/issues/2)).

Re-pack local builds into release zips: `.\scripts\package_flash_images.ps1`.

### Updating the Tab5 C6 from Modulus

The Tab5 **M Panel → C6 Update** page updates the ESP32-C6 over the internal
ESP-Hosted SDIO connection. Copy an ESP32-C6 **application image** (`.bin`) to
the root of a FAT32-formatted SD card, insert it, and open the page. For builds
from this repository, that application is
`firmware/tab5-c6/build/network_adapter.bin`. Use
**Refresh SD**, select the file, then **Check image**. Modulus verifies the ESP
image header and ESP32-C6 chip ID before enabling **Flash C6**.

Flashing never starts automatically. Keep power and the SD card connected while
the progress bar is active. After successful activation, **Restart Modulus** is
enabled so the P4 can reboot and reconnect to the updated C6 firmware.

Use an ESP-Hosted slave application image compatible with the host component
version pinned in `firmware/tab5/dependencies.lock`. Do not use a full-flash,
merged, bootloader, or partition-table image.

Recovery: if the C6 update is interrupted and SDIO no longer starts, restore a
complete C6 flash set through the C6 USB bootloader (`bootloader.bin`,
`partition-table.bin`, `ota_data_initial.bin`, and `network_adapter.bin` at the
documented offsets). The P4 OTA page cannot repair a C6 that no longer boots far
enough to provide ESP-Hosted OTA.

### Pinout (Tab5)

| Signal | Pin | Note |
|--------|-----|------|
| RS-485 TX / RX / DE | GPIO 20 / 21 / 34 | onboard SIT3088 |
| ExtEncoder MPG | Grove Port A (I2C) | powered via `EXT5V_EN` |
| Hardware E-Stop | GPIO16 (M5-Bus pin 2) | NO to GND, pull-up |
| NanoH2 UART | GPIO 6 TX / 7 RX | 460800 baud |

---

## BOM (short)

Tab5 · ExtEncoder + wheel · industrial NO E-Stop · Stamp NanoH2 · ESP32-S3 cabinet bridge · NP-F pack(s) · optional COMMU Module Extend.

Mechanical files: [`cad/`](cad/) · Wiring / schematics: [`schematics/`](schematics/).
