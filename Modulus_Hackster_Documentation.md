# Modulus — The Ultimate Universal Smart CNC Pendant

> **Hackster:** [Modulus pendant](https://www.hackster.io/BufferRoot/modulus-the-ultimate-universal-smart-cnc-pendant-2587ed) · **Contest:** [M5Stack GIC 2026](https://m5stack.com/global-innovation-contest-2026)  
> **Authors:** D. McLean / BufferRoot (solo) · **Firmware:** v0.1.0 beta · **Repo:** [github.com/BufferRoot/Modulus-Firmware](https://github.com/BufferRoot/Modulus-Firmware) · **License:** [TBD]

**Submit:** Google Form by **Aug 7, 2026 11:59 PM PST**. Paste checklist: Appendix C.

---

## Cover media

Embed first on Hackster:

1. **Video** — 2–3 min shop demo (script: Appendix B)
2. **Hero photo** — enclosure + lit DRO at a real machine
3. Optional short jog teaser (30–60 s)

UI / hardware stills to upload: annotated dashboard · ExtEncoder wheel · ESP-NOW Connected · NanoH2 wiring · themes / Quick Settings / PIN · assembled unit / internals · power bay

---

## Tagline

**One Device, One Software. Real control for any machine — no lag, no brand lock-in, no compromise.**

Handheld DRO + MPG client on **M5Stack Tab5**. Zig dual-core firmware: UI on Core 0, heap-free jog on Core 1. Speaks grblHAL, Grbl, FluidNC, LinuxCNC, Mach3/Mach4, and Masso over ESP-NOW, RS-485, Serial, WebSocket, Telnet, BLE, I2C, or CAN (COMMU module for extra RS485/TTL/CAN/I2C). Radios split on purpose — C6 for ESP-NOW / Wi-Fi / BLE, NanoH2 for Zigbee shop IoT — so motion RF and accessories never fight one chip.

---

## The Problem

Shop setups usually mean a **laptop by the chip tray**, a **blind MPG** with no DRO, or a **$350+** proprietary console locked to one brand.

1. **Contamination** — chips, coolant, and oil kill consumer keyboards and screens.
2. **No feedback** — cheap pendants jog blind; overrides and work offsets stay on the PC.
3. **Lag / buffer bloat** — Wi-Fi tablets or soft UI freezes queue jog packets; the machine keeps moving after your hand stops.

> *I retrofit mills and routers on busy floors. Operators all asked for the same thing: a tough control surface with real DRO and overrides — without parking a laptop in the chips.*

### Why not just buy one?

| Option | Cost | DRO | Overrides | Wireless | Locked to one brand |
|--------|------|-----|-----------|----------|---------------------|
| Consumer wireless MPG | ~$30–60 | No | No | Sometimes | No, but jogs blind |
| FluidNC / ESP3D web pendant | Free | Yes | Some | Wi-Fi (reconnect lag) | Grbl-family only |
| Proprietary shop console | $350+ | Yes | Yes | Wired | **Yes** |
| **Modulus** | **~$[TBD] in parts** | Yes | Yes | ESP-NOW / RS-485 / Wi-Fi / BLE | **No — open client** |

Nothing on the shelf gives real DRO, overrides, *and* an open protocol layer in one rugged handheld. That gap is the project.

---

## What It Does

**Modulus** turns the **M5Stack Tab5** into a rugged **MPG + DRO pendant**. It is a **client only** — it does not replace grblHAL / Grbl / FluidNC / LinuxCNC / Mach / Masso. Your controller stays the motion brain.

Built in **Zig 0.16** on **ESP-IDF 6**: no garbage collection on the jog path, explicit memory, UI and control on **separate cores**.

| You get | Notes |
|---------|--------|
| Live multi-axis DRO + MPG jog | ExtEncoder wheel, 0.001–1.0 mm steps |
| Overrides, hold, cycle, macros | Touch + quick tiles (not HID keyboard hacks) |
| Multi-engine CNC client | grblHAL, Grbl, FluidNC, LinuxCNC, Mach3/Mach4, Masso |
| Multi-transport link | ESP-NOW, RS-485, Serial USB, WebSocket, Telnet, BLE, I2C, CAN (USB HID/Gamepad stub) |
| ESP-NOW wireless CNC | Via C6 → S3 bridge; link field-verified (Connected) |
| Wired field bus | RS-485 default; I2C / CAN / TTL via M5Stack **COMMU** when needed |
| Zigbee shop IoT | NanoH2 hub — vacuum, lights, fans (no cloud); soak ongoing |
| One enclosure | Tab5 + wheel + E-Stop + NanoH2; hot-swap NP-F (**8+ h**/pack) |

**What “works” means (beta):** Pendant stack is complete — jog math, DRO, overrides, connect UI, fail-safes, four firmwares in tree. ESP-NOW Tab5↔S3 link verified in-field (CNC Connected). Full motion soak and live Zigbee device soak remain open field work (honest Execution). Always keep the machine E-Stop in reach.

---

## How Tab5 Is Used (required)

One product, **four firmwares**:

| Piece | Chip | Job |
|-------|------|-----|
| Pendant UI + control | **ESP32-P4** | Core 0 = LVGL 720p UI · Core 1 = heap-free ~100 Hz MPG + streams |
| Wireless radio | **ESP32-C6** (SDIO2) | **Wi-Fi 6, BLE, ESP-NOW only** — not Zigbee |
| Zigbee hub | **NanoH2 (ESP32-H2)** | ZBOSS coordinator over UART (in the enclosure) |
| Machine bridge | **ESP32-S3** | ESP-NOW → controller UART (**required** for wireless CNC) |

Also on Tab5: **RS-485** path (UART1 TX20 / RX21 / DE34), **Grove Port A** ExtEncoder + `EXT5V_EN`, **INA226** battery sense, **NP-F** power. For extra field buses (RS-485 / TTL UART / CAN / I2C breakouts), add an **M5Stack COMMU Module Extend** on the M5-Bus — see Connectivity.

**Software split:** Zig (`src/modulus/`) owns state, jog math, ABI. C shims (`firmware/tab5/components/modulus_zig/`) own IDF/BSP/LVGL. Compile-time ABI checks keep C/Zig layouts honest.

**Why Zig:** No GC pause on stop/jog; Core 1 stays heap-free so a heavy UI frame cannot stall the handwheel.

**Flash policy (when to reflash what):**

| Device | When | Script / build |
|--------|------|----------------|
| **NanoH2** | Zigbee hub / UART link | `idf.py -C firmware/nanoh2` (hold BUTTON=GPIO9 + USB-C) |
| **S3 bridge** | ESP-NOW field link | `scripts/build_s3_bridge.ps1` |
| **Tab5 C6** | SDIO / wireless / ESP-NOW | `flash_tab5_dual.ps1` — **never** `-ZigbeeExclusive` |
| **Tab5 P4** | UI / Zig / P4-only | `flash_tab5.ps1` |

---

## Anti-Lag Design

```
Core 0 — LVGL UI, audio, settings (async)
Core 1 — MPG poll, envelope, transport (~100 Hz, heap-free)
```

| Shop failure | Modulus fix |
|--------------|-------------|
| UI redraw delays jog | Dual-core isolation — Core 1 never waits on LVGL |
| Wi-Fi reconnect freezes the pendant | ESP-NOW is connectionless — bad frame, next frame continues |
| Bridge backlog under RF hit | Bounded inbound queue on S3 bridge; overflow drops rather than endless queue |
| 10 clicks ≠ 10 steps | `envelope.zig` + NVS divider/polarity before send |
| UI refresh starving Core 0 | Dashboard timer floor **≥33 ms** (NVS 33 / 40 / 50) — never 16 ms under `sw_rotate` |

**MPG hardware:** ExtEncoder (STM32F030) counts quadrature; P4 reads deltas over I2C. Sleep cuts **`EXT5V_EN`** (no STM32 battery bleed); wake restores the rail, then Core 1 polls.

### Measured / fixed (bench or firmware)

| Metric | Value | How |
|--------|-------|-----|
| MPG poll rate (Core 1) | ~100 Hz | firmware timer |
| UI refresh floor @ 720p | ≥33 ms | NVS `refr_hz` + `CONFIG_LV_DEF_REFR_PERIOD` |
| ESP-NOW PHY default | 24M OFDM (`en_rate` = 6) | NVS; adaptive drop toward 11M under fails |
| Runtime per NP-F pack | 8+ h | full-charge soak |
| Wheel-to-motion latency | **[measure if you want a number]** | scope step pin vs detent |
| Free heap / PSRAM at run | **[optional]** | `esp_get_free_heap_size` |
| Cold boot to live DRO | **[optional]** | stopwatch |

---

## Connectivity

### Demo path — ESP-NOW

1. P4 packs binary motion frames.
2. Frames go **SDIO2 → C6**.
3. C6 sends connectionless **ESP-NOW** to the **S3** in the cabinet (`firmware/s3-bridge/`).
4. S3 outputs **UART1** (TX GPIO8 / RX GPIO9 @ **115200**) to **grblHAL**.

**vs Wi-Fi:** A RF hit that forces a long Wi-Fi reconnect freezes a soft pendant. ESP-NOW drops a bad frame and continues on the next one — no “Connecting…” stall on the jog path.

Optional: NVS `en_rate` adaptive PHY (prefer higher OFDM, fall back under fails). Peer channel locked on C6 (field fix 2026-06-20 — CNC Connected without host channel RPC storms).

### CNC transports (`cnc_conn`)

Settings pick one active link. Default in firmware: **RS-485**. Demo path above: **ESP-NOW**.

| Transport | How it leaves Tab5 | Notes |
|-----------|-------------------|--------|
| **RS-485** | UART1 TX20 / RX21 / DE34 | Default wired / high-EMI (VFD shops) |
| **ESP-NOW** | C6 → air → S3 bridge → UART | Wireless CNC; needs S3 in cabinet |
| **Serial USB** | USB / UART serial | Direct serial to controller |
| **WebSocket** | C6 Wi-Fi → IP | Preferred hint for FluidNC / Masso Link |
| **Telnet** | C6 Wi-Fi → IP | Preferred hint for LinuxCNC / Mach |
| **BLE HID** | NimBLE on C6 | BLE peer / NUS-style CNC path |
| **I2C** | Bus transport | Field / custom controller link |
| **CAN Bus** | CAN transport | Industrial bus peers |
| **USB HID** / **USB Gamepad** | USB host path | Settings stubs — not full field dispatcher yet |

**Hardware note — M5Stack COMMU Module Extend:** Tab5 alone covers wireless (C6) and the on-board RS-485 pinout. For **additional** wired transports — **RS-485**, **TTL UART**, **CAN**, or **I2C** breakouts on the M5-Bus — you may need an [**M5Stack COMMU Module Extend**](https://docs.m5stack.com/en/module/commu) (RS485 / TTL / CAN / I2C ports). Pair shielded cable with the transport you select in Settings → CNC.

| If you use… | Also need… |
|-------------|------------|
| ESP-NOW | ESP32-S3 bridge (`firmware/s3-bridge/`) |
| RS-485 | Shielded twisted-pair; COMMU (or equivalent transceiver) if not already on your wiring |
| Serial USB | Compatible USB-UART / controller port |
| WebSocket / Telnet | Working AP + controller IP service |
| BLE | Compatible BLE peer/receiver |
| I2C / CAN | COMMU (or equivalent) + correct bus termination / pull-ups |
| Zigbee accessories | NanoH2 flashed + Zigbee end devices (not a CNC motion transport) |

### Motion control systems (`cnc_proto`)

Modulus is a **client** — the motion planner stays on the machine controller. NVS `cnc_proto` selects the dialect:

| Engine | Role | Typical transport hint |
|--------|------|------------------------|
| **grblHAL** (default / demo) | Status poll, alarms, `$$`, realtime bytes | RS-485 or ESP-NOW |
| **Classic Grbl** | Stock Grbl 1.1 dialect | RS-485 / serial |
| **FluidNC** | Grbl-family + web-friendly | WebSocket |
| **LinuxCNC** | linuxcncrsh-style | Telnet |
| **Mach3 / Mach4** | MMBP-style binary | Telnet |
| **Masso** | Masso Link (status/keepalive; DRO XYZ limited in RE'd packets) | WebSocket / UDP path |

User may override transport per machine — hints are UI defaults, not hard locks. LinuxCNC / Mach / Masso field handshake still open soak work; grblHAL is the proven demo engine.

### Zigbee shop IoT (NanoH2) — not CNC motion

Early builds ran Zigbee on the **C6** next to ESP-NOW — one radio, coexistence bugs, ESP-NOW drops. Zigbee moved to **NanoH2 (H2)** over UART.

**Wiring (enclosure):** Grove G1 (H2 TX GPIO1) → M5BUS / P4 **GPIO7** RX; Grove G2 (H2 RX GPIO2) ← P4 **GPIO6** TX; Grove 5V ← SYS_EXT5VO; GND common. Baud **460800**. Hub heartbeat; offline warn after ~210 s silence. On-device ModelIdentifier DB (~**4603** entries). Dashboard: pair commercial gear (no cloud). **Run** can follow CNC→OnOff (blast gate / vacuum); automation slots in NVS (`zb_automation`). Real-device soak still open field work.

---

## Enclosure, Battery & Ergonomics

One shell holds Tab5, ExtEncoder, wheel, E-Stop, and NanoH2.

| Spec | Detail |
|------|--------|
| CAD | STL + Fusion 360 — **[TBD]** |
| Print | **ABS or ASA recommended** |
| Battery | Hot-swap NP-F · **8+ h**/pack · swap while ON if on **external power** |
| Mount | **[TBD — mag / 1/4-20]** |

---

## Safety

1. **Machine mushroom E-Stop** — primary, always in reach.
2. **Pendant E-Stop** — M5-Bus **GPIO16** (rear 30-pin pin 2), momentary NO to GND, internal pull-up. Poll 10 ms / debounce 30 ms. Toggle latch: ON → bridge HALT + soft reset (`0x18`); OFF → HALT release + unlock. Convenience path, not the only layer.
3. Soft: envelope clamp, zero-confirm while Running, link/hub offline warn, low-battery **MPG lockout**.
4. **Beta:** if pendant crashes mid-jog, re-arm before trusting motion again. Keep the machine E-Stop first.

---

## Operator OS (UI / UX)

Full pendant OS, not a single screen:

### Control
- MPG jog with detent scaling (`envelope.zig`) and EXT5V sleep gating
- 2–6 axis DRO (**XYZABC**), named G54–G59 + lock
- FRO/SSO, hold/cycle, action grid + 1–4 quick tiles
- Machine maintenance counters (travel / spindle hours)

### UI & security
- Material 3 dark/light + accent palettes (glove-friendly, shop lighting)
- 10 Settings tabs: CNC, Dashboard, Display, Audio, Wireless, Power, Security, Machine, Storage, System
- Quick Settings sheet (radios, brightness, Zigbee tiles) without leaving the spindle
- Power menu: machine vs device actions, confirm modals
- PIN lock at boot/wake

### Power & storage
- INA226 Power tab (%, V, A, W)
- Dim/sleep; PMIC soft shutdown; BMI270 lift-to-wake (field polish ongoing)
- SD: `modulus_diag.txt` + settings import/export

### Audio
- Tone profiles: Standard / Soft / Crisp / Industrial (ES8388)

**Out of scope (honest Execution):** no SC2356 camera UI · no on-screen FFT yet · OTA dual-partition = roadmap

---

## Things Used

**In enclosure:** Tab5 ×1 · ExtEncoder ×1 · encoder wheel ×1 · E-Stop (NO, M5-Bus G16) ×1 · NanoH2 ×1 · NP-F pack(s)

**For ESP-NOW:** ESP32-S3 bridge ×1 (cabinet) — e.g. ESP32-S3-MINI-1 module board

**For wired field buses (as needed):** [M5Stack COMMU Module Extend](https://docs.m5stack.com/en/module/commu) ×1 — RS485 / TTL / CAN / I2C ports on M5-Bus · shielded twisted-pair · BLE peer · Wi-Fi AP · Zigbee end devices

**Software / CAD:** [Modulus-Firmware](https://github.com/BufferRoot/Modulus-Firmware) · STL/Fusion **[TBD]** · Zig 0.16 + ESP-IDF 6 · 3D printer (ABS/ASA) · Fusion 360

**Approx parts cost:** ~$[TBD] total (Tab5 + ExtEncoder + wheel + E-Stop + NanoH2 + S3 bridge + optional COMMU) vs **$350+** for a single-brand console.

Also add each part in Hackster **Things used** (store-name match + Tab5 as required contest platform).

---

## Build & Reproduce

```bash
git clone https://github.com/BufferRoot/Modulus-Firmware.git
cd Modulus-Firmware
zig build test          # host logic + ABI — 175 tests last full sync
```

```powershell
zig build tab5-lib
.\scripts\build_tab5.ps1
.\scripts\flash_tab5.ps1 -Port COM5
.\scripts\flash_tab5_dual.ps1 -C6Port COM6 -P4Port COM5   # never -ZigbeeExclusive
# NanoH2: idf.py -C firmware/nanoh2 flash (hold BUTTON). Enable EXT5V.
.\scripts\build_s3_bridge.ps1 -Action flash -Port COM8
# Settings → Wireless → ESP-NOW → S3 MAC; lock ch 1/6/11
```

Assemble enclosure **[TBD STL]**; set encoder steps; Settings → CNC for `cnc_conn` / `cnc_proto`. Optional: COMMU on M5-Bus for RS-485 / TTL / CAN / I2C; native RS-485 pins TX20/RX21/DE34 when wired that way.

**Repo map:**

```
src/modulus/         Zig: state, jog math, cnc_proto, envelope, abi
firmware/tab5/       P4 app: IDF/BSP/LVGL C shims + modulus_zig
firmware/nanoh2/     H2 Zigbee coordinator (ZBOSS)
firmware/s3-bridge/  ESP-NOW → UART bridge
scripts/             build/flash PowerShell
```

**Pinout (Tab5 side):**

| Signal | Pin | Note |
|--------|-----|------|
| RS-485 TX / RX / DE | 20 / 21 / 34 | → SIT3088 |
| ExtEncoder | Grove Port A (I2C) | rail via `EXT5V_EN` |
| Pendant E-Stop | **GPIO16** (M5-Bus pin 2) | NO to GND, pull-up |
| NanoH2 UART | GPIO6 TX / GPIO7 RX | 460800; Grove on H2 |

**Validation:** `zig build test` (ABI C↔Zig, envelope, protocol engines). Bench: ESP-NOW Connected after dual flash; idle dashboard ≥55 s with no WDT before blaming UI.

---

## Challenges & Lessons

**Zigbee killed ESP-NOW on one radio.** C6 shared 2.4 GHz between Wi-Fi/ESP-NOW and ZBOSS → drops under load. Fix: move Zigbee to **NanoH2**; C6 stays ESP-NOW / Wi-Fi / BLE only. Never rebuild C6 with `-ZigbeeExclusive`.

**SDIO 0x107 looked like “Wi-Fi broken.”** Root cause was C6 held in reset (GPIO15) after a bad esp_hosted patch, not missing WLAN power. Dual flash + correct reset polarity fixed enumeration. Lesson: flash matching ELF from *this* tree; checksum mismatch = wrong binary.

**Power menu froze Core 0.** Synchronous full-overlay build inside a click handler starved IDLE0 under 1280×720 `sw_rotate`. Fix: cache overlay, defer first build, pause dashboard refresh, change-gate LVGL writes. Same class of bug as 16 ms refresh + tiny LVGL heap — use PSRAM CLIB malloc and ≥33 ms floor.

**ESP-NOW “peer OK, CNC dead.”** Host channel RPC on SDIO fought ESP-NOW. Fix: lock channel on C6 locally; no per-send align from P4. Field result: CNC Connected.

These fights are why the architecture looks “overbuilt” — P4 dual-core, C6 motion RF, NanoH2 IoT, S3 bridge — each piece earned its keep.

---

## What's Next

- Replace I2C ExtEncoder with P4 **PCNT** GPIO quadrature (EMI-proof, ~0% CPU)
- Longer EMI / ESP-NOW motion soaks · NanoH2 real-device join + OnOff soak
- OTA partitions · richer LinuxCNC/Mach field profiles · G-code progress · FFT UI
- BMI270 wake polish · **[TBD: mount, CAD link, license]**

---

## Credits

D. McLean / BufferRoot · [Firmware](https://github.com/BufferRoot/Modulus-Firmware) · [Hackster](https://www.hackster.io/BufferRoot/modulus-the-ultimate-universal-smart-cnc-pendant-2587ed) · License **[TBD]** · CAD **[TBD]** · Thanks: M5Stack, Espressif, LVGL, grblHAL

---

## Appendix A — Judging criteria map

| Criterion | Where this page answers |
|-----------|-------------------------|
| **Creativity & Originality** | Tagline · How Tab5 Is Used · Anti-Lag · NanoH2 radio split · Challenges |
| **Functionality & Execution** | What It Does · Connectivity · Safety · Build · Challenges (honest beta) |
| **Documentation & Presentation** | Cover media · Things Used · Build · Operator OS · Appendix B–C |
| **Impact & Usefulness** | Problem · hot-swap shifts · open multi-engine client · Challenges as reuse pattern |

**Contest requirements:** Tab5 controller · original work · Hackster 2026 · description · video/photos · build + repo · how Tab5 is used.

---

## Appendix B — Video script (~3 min)

*Demo path: **grblHAL + ESP-NOW + S3**. Show end-to-end.*

| Time | Show | Criterion |
|------|------|-----------|
| 0:00–0:15 | Hook — DRO live on machine | Impact |
| 0:15–0:30 | Problem — laptop / lag | Impact |
| 0:30–0:55 | MPG jog + multi-axis DRO | Functionality |
| 0:55–1:15 | Overrides + quick tile | Functionality |
| 1:15–1:30 | Theme / Quick Settings | Documentation / UI |
| 1:30–1:45 | PIN or zero-confirm + E-Stop | Functionality / Safety |
| 1:45–2:10 | Untethered ESP-NOW (Connected; no Wi-Fi reconnect story) | Creativity / Functionality |
| 2:10–2:25 | Power % + hot-swap | Usefulness |
| 2:25–2:40 | Zigbee / NanoH2 (if soaked) or architecture diagram | Clever M5 / Impact |
| 2:40–3:00 | Four-firmware diagram + GitHub | Documentation |

---

## Appendix C — Submit checklist

### Creativity & Originality
- [ ] Story states what is *new* (anti-lag client + radio split + Zig)
- [ ] How Tab5 Is Used shows P4 / C6 / NanoH2 / ExtEncoder

### Functionality & Execution
- [ ] Video shows real jog + DRO + ESP-NOW on grblHAL
- [ ] Enclosure / internals photo
- [ ] Safety / beta note present
- [ ] Roadmap does not hide unfinished soaks as “done”

### Documentation & Presentation
- [ ] Hero + ≥6 UI/hardware photos uploaded
- [ ] Video embedded at top
- [ ] GitHub public · Build steps work · BOM in Things used
- [ ] UI/UX screenshots (theme, Quick Settings, PIN, DRO)
- [ ] CAD/STL linked when ready

### Impact & Usefulness
- [ ] Problem is personal and shop-real
- [ ] Scalable/open message (fork / multi-engine)
- [ ] Hot-swap / shift use called out

### Admin / paste box (do not invent)

| Still TBD | Your value |
|-----------|------------|
| License | |
| CAD / STL URL | |
| Mag / 1/4-20 mount | |
| Approx parts $ | |
| Hero + demo video files | |
| Extra UI/hardware stills | |
| Optional: wheel-to-motion ms | |

- [ ] Hackster published **2026** · Google Form submitted · license set when ready
