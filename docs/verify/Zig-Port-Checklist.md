# Modulus Convert to ZIG — Port Checklist

**Date:** 2026-06-14 (Part A/B/F code complete; session UX/CNC/wireless polish)  
**Scope:** Cross-reference of 21 C++ M3/audit reports (`../Modulus Firmware/docs/`) against this repo.  
**Target:** Tab5 P4 (`firmware/tab5/`) + C6 slave (`firmware/tab5-c6/`) + Zig core (`src/modulus/`).

**Legend:** `[x]` done (code or verified) · `[x] code` implemented, field verify pending · `[~]` partial · `[ ]` open · `[—]` N/A to Zig v1 · **HW** = on-device verify (COM5/COM6)

**Related logs:** [soak_cycle1](soak_cycle1_com5_2026-06-07.log) · [soak_cycle2](soak_cycle2_com5_2026-06-07.log)

---

## At a glance (2026-06-15)

| Band | Progress | Done | Partial | Open |
|------|----------|------|---------|------|
| **Code / architecture** | **89%** (68/76) | 68 | 6 | 2 |
| **HW verify** | **23%** (6/26) | 6 | 9 | 11 |
| **Forensic (Part A)** | **100%** (8/8) | 8 | 0 | 0 |
| **Perf Part F (code)** | **100%** (34/34) | 34 | 0 | 0 |
| **Part B P0** | **86%** (6/7) | 6 | 1 | 0 |

**Latest build (workspace, 2026-06-15):** ELF `dbed1ea0c0ef8c930191c5840ee93927bda61485147f45d3b8335c2c97a96b18` · app `0x29a2a0` (~2.60 MiB) · factory **48% free** @ 5 MiB · macro editor, Tab 0 CNC, wireless icons, Tab 3 audio, Display ALS UX, idle-lock re-arm.

**Latest on device (COM6→COM5 dual, 2026-06-15):** P4 ELF `dbed1ea0c0ef8c930191c5840ee93927bda61485147f45d3b8335c2c97a96b18` · app `0x29a2a0` (~2.60 MiB) · factory **48% free** @ 5 MiB · C6 `network_adapter` **2.11.4** (esp_hosted 2.11.x Phase 8c) · **dual flash PASS** · **matches workspace** · cold boot `Wireless ready` / no SDIO 0x107 **operator pending**.

### Ship blockers (P0 + critical HW) — open only

- **Idle WDT 55 s** — regression gate on `dbed1ea0…` (post dual-flash).
- **F6 scroll soak** — fling Power (battery expanded), Storage (I2C open), Wireless→WiFi (≥8 APs); no freeze >100 ms, no WDT in 30 s.
- **WiFi STA + IP** — code done 2026-06-08; field connect on COM5 open.
- **RS-485 grblHAL motion soak** — needs physical controller.
- **PIN / deep sleep / restart walk** — `power_shim.c` + `security_shim.c` wired; device walk open.
- **P0-5 cold boot (post dual-flash)** — power-cycle Tab5; confirm `Wireless ready`, no SDIO 0x107 (dual flash COM6→COM5 **PASS** 2026-06-15).

### Code complete — major wins

- **Part A forensic** — C1–C5, H2, H3, M7 fixed in shims (`tcp_transport_shim.c`, `battery_shim.c`, `power_shim.c`, `wireless_shim.c`).
- **Part F perf** — F0–F3, F7 code complete; F5 removed; F-PPA/F-CPU explicitly deferred (IRAM).
- **P0-1** — 5 MiB factory partition; headroom no longer a ROM ship gate.
- **Transport & CNC** — NVS `cnc_jmode` at boot, CONT jog restore, `cnc_mxrpm` G-code S clamp (`driver.zig`, `envelope.zig`).
- **Settings UX** — lazy 10-tab panels, scroll timer pause (F2), opaque scrim (F-S1), wireless defer-rebuild (F-W1).
- **Audio** — Tab 3 parity: HAL mic gain, tone POP, scroll-preserved hardware ref, codec dimming (`ui_settings_tab_audio.c`).
- **P2 polish** — security idle lock + boot re-arm (`security_shim.c`); CNC tab EVT session refresh; i18n EN-only per user skip.
- **Display** — auto-brightness honest UX (no ALS on Tab5); `modulus_display_has_ambient_light_sensor()` → disabled toggle + detail row.
- **Tab 0 CNC** — transport summaries, live disconnect row, BLE/I2C/CAN modal NVS + reinit, $$ browser (`ui_settings_tab_cnc.c`).
- **Macro** — Dashboard tab modal editor → NVS `cnc_macro` (127); run via `cmdRunMacro` + spindle clamp.
- **Status bar** — wireless icons (Wi-Fi/BLE/ESP-NOW), change-gated via `modulus_wireless_*` (`ui_status_bar_data.c`).
- **WiFi honesty** — `modulus_wireless_wifi_disable()` calls `esp_wifi_stop()`.

### Operator HW soak — COM5 / COM6

| Port | When | Pass criteria |
|------|------|---------------|
| **COM5** | After every `idf.py build` + flash | Record ELF SHA256 in Part E; idle dashboard ≥55 s zero WDT |
| **COM5** | F6 perf soak | `scripts/soak_tab5_perf.ps1`; scroll + FPS targets in Part F6 |
| **COM5** | P1 consolidated pass | Dashboard, handwheel, CNC tab, RS-485, audio, power, security, storage |
| **COM6 → COM5** | C6/esp_hosted/wireless slave changes | `scripts/flash_tab5_dual.ps1`; cold boot `Wireless ready`, no SDIO 0x107 |

### Deferred / v2 / N/A

- **Deferred (lab):** F-PPA hardware rotation, F-CPU 400 MHz, LVGL `-O3` — IRAM/PSRAM not proven; stay 360 MHz + `sw_rotate`.
- **v2 / PLANNED:** connection profiles, USB HID/Gamepad, OTA A/B (`ota_0`/`ota_1`).
- **N/A Zig v1:** ESP-NOW tuning keys (no C6 opcodes), fan from controller `\|A:\|` bit.

---

## Progress summary (2026-06-14)

| Band | Done | Partial | Open |
|------|------|---------|------|
| **Code / architecture** | 68 | 6 | 2 |
| **HW verify** | 6 | 9 | 11 |

**Session wins (2026-06-14–15):** Part A/B/F code complete. Session polish: idle lock, Tab 3 audio, Display ALS UX, wireless status-bar icons, macro editor, Tab 0 CNC. **2026-06-15** dual flash COM6→COM5 **PASS** — P4 ELF `dbed1ea0…` @ `0x29a2a0`, C6 `network_adapter` 2.11.4. Cold boot wireless verify + F6 soak **open**. **Part G** tab audit 2026-06-13.

**Authoritative backlog:** `MEMORY.md` (session wins + open TODO). This doc tracks M3-report parity.

---

## How to use this doc

1. Work **ship blockers** (above) before field WS-heavy or wireless releases.
2. Run **HW** rows on the **current ELF** after every `idf.py build` + flash (record SHA256 in Part E).
3. C++ M3 reports mark most UI items `[x]` — treat those as **design reference**; confirm Zig parity here.
4. Forensic section (2026-06-11) is **not** in M3 tab reports — do not skip.
5. **Part G** — Settings tab item audit (UI vs wiring); fix **BROKEN** rows before treating tab as ship-ready.

---

## Executive snapshot

| Area | C++ reports (2026-06-07) | Zig port (this repo) |
|------|--------------------------|----------------------|
| 10-tab settings IA | Done (v2.0 shell) | **[x]** lazy tab panels, timer stop on switch (`ui_settings.c`) |
| M3 UI polish | Done per-tab | **[~]** MD3 tokens done; English literals; minimal `i18n_shim` |
| Dashboard / status bar / power menu | Done v1.1–v1.4 | **[x] code** · **HW** partial (MEMORY 2026-06-07) |
| Wireless WiFi/BT/ESP-NOW | Done v1.1–v2.0 | **[x] code** (2026-06-08) · **HW** open |
| Forensic C1–C5 (2026-06-11) | Not tracked in M3 | **[x] code** — C1–C5 + H2/H3 + M7 fixed 2026-06-14 |
| Factory partition | ~74% free (~2.6 MB) | **[x]** 5 MiB factory (`0x500000`); ~48% free @ workspace app `0x29a1f0` |
| Scroll / FPS | C++ wireless defer-rebuild; Power scroll pause | **[x] code** Part F complete (2026-06-14); **HW** F6 soak via `scripts/soak_tab5_perf.ps1` |
| i18n en/fr/es/zh + Noto | ~780 StringIds | **[~]** EN picker + `i18n_shim.c`; **EN only** — fr/es/zh deferred per user |

---

## Part A — Forensic audit (2026-06-11) vs Zig shims — **COMPLETE (code)**

*Source: `../Modulus Firmware/docs/Modulus-Forensic-Audit-2026-06-11.md`*

| ID | Finding | Zig status | Evidence / fix path |
|----|---------|------------|---------------------|
| **C1** | `lv_async_call()` without LVGL lock from non-LVGL tasks | **[x]** | F-C1/F-D1: removed async path; dashboard timer-only refresh (`ui_shim.c`). |
| **C2** | `vTaskDelete()` on tasks holding mutex / mid-I/O | **[x]** | **[x]** `serial_shim.c` cooperative stop + self-delete. **[x]** `i2c_transport_shim.c` `join_worker_task()`. **[x]** `tcp_transport_shim.c` — `shutdown` + join, self-delete (no external `vTaskDelete`). **[x]** `ext_encoder_shim.c` — poll-only, no RX task. |
| **C3** | Transport tasks feed grblHAL while Core 1 snapshots | **[x]** | `rx_ring.zig` + `device_runtime.zig`; all transports → `modulus_zig_serial_rx` → ring → `systemTick` drain. |
| **C4** | WebSocket no frame reassembly | **[x]** | `tcp_transport_shim.c` — 2 KiB accumulate buffer, multi-frame consume, PONG on 0x9, masked/unmasked server frames. |
| **C5** | Deep-sleep touch poll + battery still running | **[x]** | **[x]** `touch_shim.c:140` coex lock on poll. **[x]** `power_shim.c` — `modulus_battery_set_poll_paused(true)` + `modulus_wireless_prepare_for_sleep()` before sleep loop; touch poll only (no bat I2C). |
| **H2** | NVS reads in RT loops (encoder, poll) | **[x]** | F-H2: RAM cache in `ext_encoder.zig` + `modulus_zig_encoder_reload_settings()` on settings writes. |
| **H3** | NVS commit per slider tick | **[x]** | F-H3: brightness/volume/encdiv/jogspd commit on `LV_EVENT_RELEASED` only. |
| **M7** | `wifi::disable()` doesn't stop radio | **[x]** | **[x]** `modulus_wireless_wifi_disable()` — `esp_wifi_disconnect()` + `esp_wifi_stop()` when stack started. **[x]** `modulus_wireless_prepare_for_sleep()` unchanged (full quiesce before deep sleep). |

### Zig wins (ahead of C++ forensic recommendations)

- **[x] C3 RxRing** — `src/modulus/cnc/rx_ring.zig` (C++ report listed open at audit time).
- **[x] Serial RX cooperative shutdown** — `serial_shim.c` documents forensic rationale.
- **[x] TCP/WS cooperative shutdown** — `tcp_transport_shim.c` shutdown + join (2026-06-14).
- **[x] WS frame reassembly + PONG** — `tcp_transport_shim.c` 2 KiB accumulator (2026-06-14).
- **[x] Deep-sleep battery pause** — `battery_shim.c` `modulus_battery_set_poll_paused()` (2026-06-14).
- **[x] Touch poll in sleep** — I2C coex lock (C++ sleep loop did not).

### Remaining (Part A)

- **HW:** WS/Telnet transport soak with live grblHAL peer (code path fixed; field not logged).
- **HW:** Deep-sleep wake walk (touch + timer) on device after dual flash of `dbed1ea0…`.

---

## Part B — Priority checklist — **COMPLETE (code)** · HW soak open

> All code-fixable P0/P1/P2 items closed or honestly deferred. Operator **HW soak** (consolidated device pass, F6 scroll/WDT) remains on current ELF (Part E).

### P0 — Critical (before production / new ROM)

| # | Item | Status | Notes |
|---|------|--------|-------|
| P0-1 | Factory partition headroom | **[x]** | **5 MiB factory** (`partitions.csv` `0x500000`, 2026-06-14). App `0x295440` → ~48% free (~2.53 MiB). Optional F-ROM trim is P2 only. OTA still needs `ota_0`/`ota_1` layout later. |
| P0-2 | Forensic **C1** LVGL lock on async CNC refresh | **[x]** | F-C1: async removed; timer-only dashboard refresh |
| P0-3 | Forensic **C4** WS reassembly + PONG | **[x]** | `tcp_transport_shim.c` accumulate + PONG (2026-06-14) |
| P0-4 | Forensic **C2** tcp transport cooperative stop | **[x]** | `tcp_transport_shim.c` — shutdown + join (2026-06-14) |
| P0-5 | C6 + P4 dual-flash when wireless changes | **[~]** | **[x]** `scripts/flash_tab5_dual.ps1` + policy in MEMORY. **[x] HW** SDIO cold boot PASS (cycle 1, `Wireless ready`). **2026-06-15** dual flash COM6→COM5 **PASS** (exit 0; esptool verify both). **HW** cold boot re-check on `dbed1ea0` after power-cycle **pending**. |
| P0-6 | LVGL heap policy regression gate | **[x]** | `sdkconfig.defaults`: `CONFIG_LV_USE_CLIB_MALLOC=y`. **[x] HW** 58 s idle WDT PASS (swarm C, older ELF). **Re-check** on `dbed1ea0` after dual flash (pending operator 55 s soak). |
| P0-7 | Build-before-flash discipline | **[x]** | `scripts/build_tab5.ps1` / `flash_tab5.ps1`: ASCII check + `zig build tab5-lib` + `idf.py build`; headroom vs `0x500000`. Latest ELF `dbed1ea0` dual-flashed COM6→COM5 (Part E). |

### Remaining (P0)

- **P0-5 [~]** — dual flash done 2026-06-15; operator cold boot (`Wireless ready`, no 0x107) still open.

---

### P1 — Shop floor / operator

#### Consolidated device pass (Tab5 COM5; COM6 when wireless)

| Domain | Key checks | Code | HW |
|--------|------------|------|-----|
| Dashboard | HOME; STEP/CONT NVS; quick grid 1–4; Fan 0x8A; macro G-code | **[x] code** | **[ ]** |
| Handwheel | Port A 0x59; `cnc_encdiv` / `cnc_mpgpol` / `cnc_jogspd` live | **[x]** `ext_encoder_shim.c` + `ext_encoder.zig` | **[ ]** |
| CNC tab | 1 Hz hero; transport switch + NVS; ESP-NOW read-only + Wireless link | **[x]** `ui_settings_tab_cnc.c` | **[ ]** |
| RS-485 | Baud → reconnect → grblHAL soak | **[x]** `serial_shim.c` + checklist in MEMORY | **[ ]** |
| ESP-NOW | Two-device probe; peer persistence; CNC transport E2E | **[x]** 2026-06-08 submenu (MEMORY) | **[ ]** |
| WiFi | Scan; connect; IP; NTP; forget/disconnect modals | **[x]** 2026-06-08 (MEMORY) | **[~]** code done; STA+IP field open |
| Bluetooth | Scan/pair/unpair; passkey modal; connect/disconnect | **[x]** `ui_settings_wireless.c` + `ble_transport_shim.c` | **[ ]** |
| Audio | 4 tone profiles; touch sounds; vol 0%; boot/shutdown MP3 | **[x]** `audio_shim.c` + `ui_touch_sound.c` + codec dimming | **[ ]** |
| Power | Dim/sleep without BMI270; Sleep Now; deep sleep walk | **[x]** dim path; `power_shim.c` + `wakeup_shim.c` | **[~]** PIN/deep-sleep walk open |
| Security | PIN set/change/clear; wake lock + `pin_tmo`; tab timer cleanup | **[x]** `security_shim.c` + tabs_extra | **[ ]** |
| Storage | I2C scanner on demand; SD export; scroll with scanner expanded | **[x]** `storage_shim.c` + tabs_extra | **[ ]** |
| Status bar + power menu | No scroll bounce; conn dot; wireless icons; E-stop confirm; busy gating | **[x]** change-gated `ui_status_bar.c`; power menu parity | **[~] HW** power menu OK; wireless icon transitions open |

#### MEMORY-verified on device (re-run on ELF `dbed1ea0…` after dual flash)

| Item | Status | Source |
|------|--------|--------|
| Idle dashboard ≥55 s zero WDT | **[~] HW** | swarm C PASS on older ELF; **re-check** after Part A flash |
| Power menu + confirm modals | **[x] HW** | MEMORY done list |
| Settings — all 10 tabs open/scroll/switch | **[~] HW** | MEMORY 2026-06-07; **F2 scroll fixes unsoaked** on `dbed1ea0…` |
| C6+P4 hosted link (`Wireless ready`) | **[x] HW** | soak cycle 1; cycle 2 partial (SDIO 0x107) |
| I2C0 Port A + mbus + PI4IOE rails | **[x] HW** | MEMORY 6306bed6 / fcb32b66 |
| Quick settings scrim + refresh pause | **[x] HW** | 58 s WDT PASS (prior ELF) |
| RPC/flash regression (no 12298) | **[x] HW** | default NVS cold boot |
| Multi-cycle flash soak | **[~] HW** | cycle 1 PASS; cycle 2 partial |
| 5 MiB factory partition flash | **[x] HW** | COM5 2026-06-15; partition table verified; app `dbed1ea0…` dual-flashed (matches workspace) |
| WiFi STA connect + IP | **[~] HW** | code 2026-06-08; field open |
| RS-485 grblHAL motion soak | **[~] HW** | needs physical controller |
| PIN / deep sleep / restart walk | **[~] HW** | code wired; device walk open |

#### Transport & CNC features

| Item | C++ report | Zig | Status |
|------|------------|-----|--------|
| Transport reliability (RS485/WS/Telnet/BLE/I2C/CAN) | [~] | All shims in `CMakeLists.txt`; cooperative stop on serial/I2C/TCP/CAN | **[x] code** — `serial_shim.c`, `tcp_transport_shim.c`, `i2c_transport_shim.c`, `canbus_shim.c`, `ble_transport_shim.c`, `espnow_transport_shim.c` · **[ ] HW** |
| CONT jog + encoder path | [~] | NVS `cnc_jmode` at boot + CONT dispatch | **[x] code** — `driver.zig` init, `ext_encoder.zig` `dispatchCont`, `ui_widget_jog.c` NVS restore · **[ ] HW** |
| USB HID / Gamepad transport | [ ] deferred | PLANNED stub | **[—]** |
| grbl `$` settings browser | [x] | ADVANCED row + `settings_grbl_dump_modal_show()` | **[x] code** — `ui_settings_tab_cnc.c` + `modulus_zig_settings_dump_*` · **[ ] HW** |
| Connection profiles | [ ] P1 | PLANNED row | **[—]** v2 |
| `cnc_mxrpm` spindle command clamp | [~] | `envelope.clampGcodeSpindle` + `driver.cmdSendGcode` / `sendGcodeClamped` | **[x] code** — override % + direct `S` word clamp · **[ ] HW** |
| Sync work envelope to controller | [x] | Machine tab action row | **[x] code** — `modulus_zig_sync_envelope()` → `$110-$112`, `$30` on Idle · **[ ] HW** |
| Work envelope jog/override clamp | — | `envelope.zig` + `driver.zig` | **[x] code** |

#### Wireless honesty

| Item | Status |
|------|--------|
| ESP-NOW tuning keys UI (`en_rate`, coex, …) | **[x]** `en_rate` → `ESPNOW_CMD_SET_RATE` (2026-07-19) |
| Zigbee device registry + scan UI | **[~] code** — `ui_settings_wireless.c` zb_* modals; C6 esp-zb open |
| Thread device registry + attach shell | **[~] code** — th_* modals; QR/CoAP open |
| WiFi static IP / multi-SSID / enterprise | **[ ]** — coming-soon / P3 |
| WiFi disable stops C6 radio power draw | **[x] code** | `modulus_wireless_wifi_disable()` calls `esp_wifi_stop()` |

### Remaining (P1 — HW soak)

All consolidated device-pass **HW** columns above marked **[ ]** or **[~] HW** — operator pass on COM5 after dual flash of `dbed1ea0…`. See **Operator HW soak** at top.

---

### P2 — Product polish

| Item | Status | Notes |
|------|--------|-------|
| Full i18n (fr/es/zh) + Noto fonts | **[~]** | **[x]** EN picker + `i18n_shim.c` framework. **EN only** — fr/es/zh deferred per user. |
| Audio codec-unavailable dimming (`is_output_ready`) | **[x]** | `audio_sync_codec_ui()` dims volume/touch/tone/mic only; `modulus_audio_get_mic_gain_idx()`; tone POP; tab-leave ref reset |
| Macro G-code editor (Dashboard settings) | **[x] code** | `ui_settings_tab_dashboard.c` + `settings_macro_modal_*` in `ui_settings_modals.c`; NVS `cnc_macro` (127); run via `modulus_zig_cmd_run_macro()` |
| Security idle lock without display sleep | **[x] code** · **[ ] HW** | `pin_idle` + `pin_idle_tmo` NVS; `modulus_security_idle_lock_tick()` in `display_shim.c`; Security tab (`ui_settings_tabs_extra.c`); EVT_SCREEN_CHANGE → PIN overlay (`ui_pin_lock.c`); activity reset on unlock; timer re-arm in `security_shim.c` after `security_init` |
| Hot-settings RAM cache (H2) | **[x]** | Verified F-H2 encoder RAM cache + `modulus_zig_encoder_reload_settings()` |
| Deferred NVS commit on sliders (H3) | **[x]** | Verified F-H3 brightness/volume/encdiv/jogspd commit on `LV_EVENT_RELEASED` only |
| CNC event-bus → settings live rows | **[x]** | `modulus_ui_settings_cnc_on_status_event()` — session hero refresh on `EVT_CNC_STATUS_UPDATE` under display lock; 1 Hz timer retained as fallback |
| Settings search / filter | **[—]** | C++ P2 deferred |
| OTA host + partition table | **[~]** | **[x]** honest stub (`ui_settings_tab_system.c`). **[x]** factory 5 MiB (single-slot). **[ ]** `ota.zig` + `ota_0`/`ota_1` A/B layout deferred |
| Global reset strategy (except factory) | **[—]** | C++ P2 deferred; factory reset **[x]** |
| Split oversized files | **[ ]** | `ui_settings_tabs_extra.c` (~1300L), `wireless_shim.c` (~850L) — maintenance defer, not ship blocker |
| Repo dead-code purge | **[x]** | Verified esp-dsp **in use** (`dsp_shim.c` FFT/IIR); no CMake/sdkconfig removal warranted |

### Remaining (P2 — code / maintenance)

- **Full i18n (fr/es/zh)**, **OTA A/B**, **file splits** — honest open/deferred; none are P0 ship gates.

---

### P3 — Future / may not apply

| Item | Status |
|------|--------|
| Non-GrblHAL protocols | **[—]** |
| Haptics / AEC DSP | **[—]** PLANNED stubs (`dsp_shim.c` scaffold) |
| BMI270 motion wake UI | **[~] code** — `imu_shim` + `wakeup_shim`; **HW** cold-wake open |
| Auto-brightness | **[x] honest UX** | No ALS on Tab5; disabled toggle + detail row in Display tab |
| Home screen placeholder | **[—]** |
| C++ split `screen_net_settings.cpp` | **[—]** Zig uses `ui_settings_wireless.c` + shims |
| Fan state from controller `\|A:\|` bit | **[—]** local toggle OK |
| Section subtitles | **[—]** title-only accepted |
| Wireless icon in status bar | **[x] code** | Phosphor Light 24px Wi-Fi/BLE/ESP-NOW; change-gated `ui_status_bar_data.c`; **HW** open |

---

## Part B2 — Code-complete inventory (MEMORY + file audit)

*Items verified in tree; does not replace HW pass.*

### Architecture & phases (MEMORY Zig port plan)

| Item | Status |
|------|--------|
| Phases 0–5h (core, cnc, HAL, runtime, UI MVP) | **[x]** |
| ABI epoch 14 stable | **[x]** |
| Core 1 `systemTick` heap-free (64 KB arena) | **[x]** |
| `evt_dispatch` + `event_shim.c` cross-core queue | **[x]** |
| Settings lazy-build + hide/show tabs | **[x]** |
| Settings tab timers stop on switch/hide | **[x]** `ui_settings.c` |
| Dashboard refresh pause under scrims | **[x]** |
| Change-gated LVGL (status bar, DRO, jog, overrides, actions) | **[x]** |
| `CONFIG_LV_USE_CLIB_MALLOC` + PSRAM | **[x]** |
| MD3 compliance R1+R2 (tokens, fonts, press overlay) | **[x]** MEMORY 2026-06-08 |
| Phosphor icons pipeline | **[x]** |
| M5-Bus / Port A I2C0 @ 0x59 | **[x]** `mbus_shim.c`, `ext-encoder.md` |
| INA226 battery fix (bus voltage) | **[x]** MEMORY 2026-06-07 |
| EXT5V NVS default = 1 (encoder rail) | **[x]** MEMORY 2026-06-07 |
| Factory reset NVS erase | **[x]** |
| RX8130 RTC + SNTP on GOT_IP | **[x]** |
| Alt transports: RS-485, WS, Telnet, I2C, CAN, BLE, ESP-NOW | **[x]** shims |
| C6 esp_hosted 2.11.4 + `build_tab5_c6_modulus.ps1` | **[x]** |
| `flash_tab5.ps1` / `check_ui_ascii.ps1` / CI `tab5-idf.yml` | **[x]** |
| Factory partition 5 MiB (`partitions.csv` `0x500000`) | **[x]** 2026-06-14; `build_tab5.ps1` headroom gate |
| CMake duplicate `tab5_pi4ioe.c` removed | **[x]** MEMORY arch audit |
| Forensic C1–C5 + H2/H3 + M7 (Part A) | **[x]** 2026-06-14 |
| Audio codec-unavailable UI dimming | **[x]** `audio_shim.c` + `ui_settings_tab_audio.c` |

---

## Part C — M3 report index (C++ reference)

| Surface | Report | C++ ver | Zig parity |
|---------|--------|---------|------------|
| Settings shell | Settings-Interface v2.0 | 2.0 | **[x] code** · i18n/HW open |
| CNC & Connection | CNC-Connection v1.2 | 1.2 | **[x] code** · **HW** |
| Dashboard & Handwheel | Dashboard-Handwheel v1.4 | 1.4 | **[x] code** · **HW** |
| Main dashboard | Dashboard v1.1 | 1.1 | **[x] code** · **HW** |
| Display & Theme | Display-Themes v1.4 | 1.4 | **[x] code** · **HW** |
| Audio & Haptics | Audio-Haptics v1.6 | 1.6 | **[x] code** codec dimming · **HW** |
| Wireless hub | Wireless v1.3 | 1.3 | **[x] code** · **HW** |
| WiFi | WiFi v1.1 | 1.1 | **[x] code** · **HW** |
| Bluetooth | Bluetooth v1.1 | 1.1 | **[x] code** (passkey ahead of C++) · **HW** |
| ESP-NOW | ESP-NOW v2.0 | 2.0 | **[x] code** · **HW** |
| Zigbee | Zigbee v1.1 | 1.1 | **[~] code** |
| Thread | Thread v1.1 | 1.1 | **[~] code** |
| Power | Power v1.6 | 1.6 | **[x] code** · **HW** |
| Security | Security v1.3 | 1.3 | **[x] code** · idle lock **[x] code** |
| Machine | Machine v1.3 | 1.3 | **[x] code** · RPM clamp **[x] code** |
| Storage & Diagnostics | Storage v1.4 | 1.4 | **[x] code** · **HW** |
| System & About | System-About v1.3 | 1.3 | **[x] code** · OTA stub only |
| Status bar | Status-Bar v1.2 | 1.2 | **[x] code** · wireless icons · EN only · **HW** partial |
| Power menu | Status-Bar-Power-Menu v1.4 | 1.4 | **[x] code** · **[x] HW** |
| Tab5 performance | Tab5-Performance | 2026-06-07 | **[x] code** Part F complete; F-PPA/F-CPU deferred (IRAM); **HW** F6 soak open |
| Architecture | Firmware-Architecture v1.0 | 1.0 | Zig tree differs (no C++ orphans) |
| Forensic | Modulus-Forensic 2026-06-11 | — | Part A **[x] code** |

---

## Part D — Recommended execution order

```
1. P0-1  Partition trim OR factory bump          [x]  5 MiB factory 2026-06-14
2. P0-2  C1 LVGL lock (ui_shim.c)                [x]
3. F-P0  Wireless defer-rebuild + scroll pause     [x]  Part F
4. P0-4  C2 tcp transport join                     [x]
5. P0-5  C6+P4 dual-flash when wireless changes  [x] flash PASS 2026-06-15; cold boot verify open
6. P1     Consolidated HW soak                     [~] partial logs exist — **soak on `dbed1ea0…`**
7. F-P1  Scroll timer pause on Storage/CNC/Sys   [x]  Part F
8. P0-3  C4 WS reassembly (if WS production)       [x]
9. F-P2  Idle-adaptive dashboard refresh         [x]  Part F F3
10. P2    Macro editor OR drop from dashboard spec [x]  ui_settings_modals.c
11. P2    i18n strategy                            [~]  EN only; fr/es/zh deferred per user
12. P2    H2/H3 hot-settings + deferred NVS        [x]
13. F-P3  PPA rotation / CPU 400 MHz (HW lab)      [—]  Part F — deferred IRAM; 360 MHz + sw_rotate baseline
14. P2    Audio is_output_ready                    [x]  audio_shim.c + ui_settings_tab_audio.c
15. P2    WiFi disable fix (M7)                    [x]  wireless_shim.c
16. P2    CNC event-bus settings rows              [x]  ui_settings_tab_cnc.c EVT refresh
17. P2    Security idle lock (pin_idle)            [x]  security_shim.c + display_shim.c; boot re-arm in security_init
18. P2    cnc_mxrpm direct S clamp                 [x]  envelope + driver
19. P2    Repo dead-code purge                     [x]  esp-dsp in use
20. F6    Operator perf soak on COM5               [ ]  scripts/soak_tab5_perf.ps1
20. G-1   Machine max feed/RPM NVS persist         [x]  Part G 2026-06-13
21. G-2   Quick button Macro handler               [x]  Part G — cnc_macro NVS
22. G-3   Quick button Spindle CCW (M4)            [x]  Part G 2026-06-13
23. G-4   smooth_anim consumer                     [x]  Part G 2026-06-13
24. G-5   ExtEncoder scan + I2C bus recover        [x]  Part G 2026-06-13
25. G-6   Power tab: adaptive/QC/wake/gate sync      [x]  Part G 2026-06-13
26. G-7   Machine tab: soft limits/$$/sync envelope  [x]  Part G 2026-06-13
```

---

## Part F — Performance, scroll responsiveness & FPS — **COMPLETE (code)**

*Sources: C++ `Tab5-Performance-Optimization-Report.md`, forensic H1/H2/H4, `MEMORY.md` LVGL/WDT lessons, live shim audit 2026-06-14.*

**Code status:** F0–F3, F7 (P0–P2) verified in tree. F4 lab knobs (400 MHz, PPA flush, stripe bump, `-O3`) **explicitly deferred** — IRAM/PSRAM buf layout not proven. **HW soak** remains operator pass via F6 + Part E.

### Remaining (Part F — HW only)

- **F6 operator soak** — idle WDT, scroll hitch, FPS, heap stability on COM5 with ELF `dbed1ea0…`.
- **F-PPA / F-CPU** — lab-only; not ship gates.

### F0 — Render pipeline baseline (keep these)

| Item | Status | Evidence |
|------|--------|----------|
| PSRAM-backed LVGL heap | **[x]** | `CONFIG_LV_USE_CLIB_MALLOC=y`; never revert to 64 KiB builtin |
| 120-line partial flush stripe | **[x]** | `display.zig` `draw_stripe_lines=120`; `display_shim.c` logs `stripe=120 lines` (~337 KiB double buf) |
| Dashboard refresh floor ≥33 ms | **[x]** | `ui_shim.c` `refresh_ms_from_hz` min 33 ms + `CONFIG_LV_DEF_REFR_PERIOD=33` |
| Change-gated dashboard widgets | **[x]** | status bar, DRO, jog, overrides, actions (`ui_status_bar.c`, `ui_widget_*.c`) |
| No `transform_scale` on labels | **[x]** | zero matches in `firmware/tab5/`; real Montserrat tiers in `sdkconfig.defaults` |
| Core 0 LVGL affinity + 24 KiB stack | **[x]** | `display_shim.c` `task_affinity=0`, `task_stack=24576` |
| Dashboard refresh paused under overlays | **[x]** | `ui_shim.c` pause/resume; settings/quick/power/zero confirm call `modulus_ui_pause_dashboard_refresh()` |
| Tab activity timers pause on tab switch | **[x]** | `ui_settings.c` `destroy_tab_activity` / `resume_tab_activity` CNC/wireless/power/storage/system |
| Software rotate (PPA deferred) | **[x]** | `display_shim.c` `sw_rotate=true`, `buff_spiram=true`; `CONFIG_LVGL_PORT_ENABLE_PPA=y` Kconfig only — flush path not flipped |

**Note:** `MEMORY.md` mentions a 360-line stripe target (~1.8 MiB) — **not deployed**. Runtime and `display.zig` use **120 lines** (C++ tear-fix parity). Do not bump stripe without scroll/FPS soak + PSRAM headroom check.

### F1 — Critical perf gaps (fix before tuning knobs)

| ID | Gap | Impact | Fix path | Pri |
|----|-----|--------|----------|-----|
| **F-C1** | **C1** — `lv_async_call(async_cnc_refresh)` without `modulus_display_lock()` | Rare LVGL corruption; frame spikes when Core 1 floods status events | **[x]** Timer-only refresh; event handler no-op (`ui_shim.c`) | **P0** |
| **F-W1** | Wireless `rebuild()` = full `lv_obj_clean(panel)` on scan/connect state change | 1 Hz timer + user scroll → mid-flick scroll hitch | **[x]** Defer rebuild while scrolling + scroll BEGIN/END hooks (`ui_settings_wireless.c`) | **P0** |
| **F-S1** | Settings scrim `LV_OPA_60` semi-transparent (`ui_settings.c`) | Full-screen re-blend risk under `sw_rotate` | **[x]** Opaque `#0A0C12` + `LV_OPA_COVER` | **P0** |
| **F-T1** | `modulus_ui_settings_theme_refresh()` rebuilds **all 10 tabs** | Theme toggle freezes UI 200–800 ms | **[x]** Active tab only; hidden tabs lazy-rebuild on visit | **P1** |
| **F-D1** | Dual dashboard refresh: timer **and** `EVT_CNC_STATUS_UPDATE` → async | Redundant invalidations when machine running | **[x]** Event path removed; 33–50 ms timer only | **P1** |
| **F-H2** | Encoder poll reads NVS every step (`ext_encoder.zig`) | Core 1 latency + flash traffic | **[x]** RAM cache + reload export | **P1** |
| **F-H3** | Brightness/volume NVS on `VALUE_CHANGED` | Flash wear + slider drag stalls | **[x]** NVS on `RELEASED`; live preview on `VALUE_CHANGED` | **P1** |

### F2 — Scroll responsiveness (settings-heavy)

| Tab / surface | Status | Implementation |
|---------------|--------|----------------|
| **Power** | **[x]** | Reference — `SCROLL_BEGIN`/`END` pauses battery timer |
| **Wireless** | **[x]** | F-W1 — defer rebuild + scroll pause wl timer + BLE scan stop |
| **Storage** | **[x]** | Scroll pause `s_stor_timer`; defer full rebuild; I2C list cap 8 + `+N more` |
| **CNC** | **[x]** | Scroll pause session timer; defer transport-action full rebuild |
| **System** | **[x]** | Scroll pause uptime/clock timer |
| **Machine / Security** | **[x]** | Static rows — no periodic timer |
| **Sidebar** | **[x]** | `settings_tune_scroll_container` momentum ON |
| **Theme refresh** | **[x]** | F-T1 — active tab only |

**Scroll soak (add to Part E):** With perf monitor visible, fling-scroll **Power** (battery expanded), **Storage** (I2C scanner open), **Wireless → WiFi** (scan list ≥8 APs). Pass = no visible freeze >100 ms and no WDT within 30 s continuous scroll.

### F3 — Dashboard FPS & idle CPU

| Lever | Status | Notes |
|-------|--------|-------|
| Idle-adaptive refresh | **[x]** | F-IDLE: 50 ms Idle/offline; 33 ms Run/Hold/Jog (`ui_shim.c`) |
| Event-driven updates | **[x]** | F-D1 timer-only; no async CNC refresh |
| `lv_async_call` on CNC status | **[x]** | F-C1 removed |
| Phosphor icons | **[x]** | A8 alpha masks + runtime recolor (`gen_phosphor_icons.mjs`; ~75% icon ROM) |
| Font ROM | **[x]** | Boot splash `_44` only; `MONTSERRAT_48` dropped (~37 KiB) |
| `CONFIG_LV_USE_PERF_MONITOR` | **[x]** | Off in `sdkconfig.defaults` (enable in sdkconfig for F6 lab) |
| `CONFIG_SPIRAM_MEMTEST` | **[x]** | Off in `sdkconfig.defaults` |
| Audio codec write back-pressure | **[x]** | `codec_write_all` retry + `spk_prepare_ui_output` before MP3 (`audio_shim.c`) |

### F4 — Platform / render hardware (lab-only — **deferred**, baseline locked)

| Item | C++ report | Zig status | Notes |
|------|------------|------------|-------|
| CPU 400 MHz + L2 512 KB | Deferred (IRAM) | **[—] deferred** — **360 MHz** shipped (`CONFIG_ESP_DEFAULT_CPU_FREQ_MHZ_360`) | F-CPU: re-benchmark only after `idf.py size` headroom; watch thermals |
| PPA hardware rotation (H4 Stage 2) | Planned | **[—] deferred** — `sw_rotate=true` at runtime | F-PPA: `CONFIG_LVGL_PORT_ENABLE_PPA=y` Kconfig staged; `display_shim.c` comment — PSRAM stripe + PPA scratch not validated; do not flip without F6 soak |
| Stripe 120 → 180 lines | C++ tested for tear | **[x] locked 120** | Intentional — fewer flushes not worth bytes/shift until PPA or headroom proof |
| LVGL `-O3` | Deferred IRAM overflow | **[—] deferred** — default `-O2` | Re-evaluate with `idf.py size` after ROM trim (F-ROM done) |
| Full-frame DPI buffer | ~1.8 MB PSRAM | **[x]** | BSP owns MIPI-DSI path; not optional |

### F6 — Measurement protocol

**Automation:** `scripts/soak_tab5_perf.ps1` — builds (optional), writes Part E template under `docs/verify/`, opens monitor on COM5.

| Metric | How | Target | Status |
|--------|-----|--------|--------|
| Idle WDT | Dashboard 55 s no touch | **PASS** (regression gate) | **[x] code** gate in CI/build discipline; **HW** re-check per ELF |
| LVGL CPU | `CONFIG_LV_USE_PERF_MONITOR=y` in sdkconfig (lab) | <70% avg idle dashboard | **[x] doc** — enable via menuconfig for soak |
| Scroll hitch | Visual + perf monitor during F2 soak | No sustained 100% taskLVGL | **[x] code** F2 fixes; **HW** operator pass |
| Frame time | perf monitor FPS readout | ≥25 FPS idle; ≥20 FPS settings scroll | **[x] doc** |
| Heap | Log after display init + after settings close | PSRAM largest block stable | **[x] code** — `display_shim.c` init log; system tab heap row |
| ELF | Record SHA256 per soak | Part E template | **[x]** `soak_tab5_perf.ps1` + Part E below |

### F7 — Prioritized perf backlog

| Pri | ID | Action | Files | Status |
|-----|-----|--------|-------|--------|
| **P0** | F-C1 | LVGL lock or remove async CNC refresh | `ui_shim.c` | **[x]** |
| **P0** | F-W1 | Defer wireless rebuild until scroll idle | `ui_settings_wireless.c` | **[x]** |
| **P0** | F-S1 | Opaque settings scrim or assert refresh pause | `ui_settings.c` | **[x]** |
| **P1** | F-SC | Scroll BEGIN/END timer pause on Storage, CNC, System, Wireless | tab `*_*.c` | **[x]** |
| **P1** | F-T1 | Theme refresh without nuking all tabs | `ui_settings.c` | **[x]** |
| **P1** | F-D1 | Coalesce timer + event dashboard refresh | `ui_shim.c` | **[x]** |
| **P1** | F-H2/H3 | NVS cache + slider RELEASED commit | `ext_encoder.zig`, display/audio tabs | **[x]** |
| **P2** | F-IDLE | Idle-adaptive `refr_hz` | `ui_shim.c` | **[x]** |
| **P2** | F-ROM | Font/icon trim | sdkconfig, `gen_phosphor_icons.mjs` | **[x]** |
| **P3** | F-PPA | PPA rotation flush path | `display_shim.c`, BSP | **[—] deferred** — IRAM/PSRAM buf2 + scratch; Kconfig only |
| **P3** | F-CPU | 400 MHz soak | `sdkconfig.defaults` | **[—] deferred** — stay 360 MHz until `idf.py size` green |

---

## Part G — Settings menu tab audit (2026-06-13)

*Source: static audit of `firmware/tab5/components/modulus_zig/ui_settings_*.c` + shims vs on-device reports. Shell = 10 lazy tabs in `ui_settings.c`.*

**Tag legend:** **CS** = explicit *Coming soon* row · **NI** = *Not implemented* row · **STUB** = UI ok, backend incomplete · **BROKEN** = mis-wired or known failing · **HW** = code path exists, field verify open · **OK** = wired, no known code gap

### Summary

| Category | Count | Action |
|----------|-------|--------|
| Explicit **Coming soon** | 9 | v2 / honest defer — do not treat as bugs (6 CS rows; BT Advanced ×4) |
| **Not implemented** | 2 | OTA (System tab) |
| **BROKEN** | 0 | G-1..G-7 fixed 2026-06-13 — **HW** ExtEncoder soak still open |
| **STUB / partial** | 6 | Zigbee/Thread/i18n backend gaps — document or wire C6 RPC |
| **HW verify open** | Most radios, transports, sleep/PIN, ExtEncoder | Part E / P1 soak |

### Priority fixes (code)

| # | Tab | Item | File(s) | Status |
|---|-----|------|---------|--------|
| G-1 | Machine | **Max feed rate** / **Max spindle RPM** sliders persist on `RELEASED` + `modulus_zig_limits_reload()` | `ui_settings_tabs_extra.c`, `abi.zig` | **[x] 2026-06-13** |
| G-2 | Dashboard | **Quick button → Macro** runs NVS `cnc_macro` (default `M5`) | `driver.zig`, `ui_widget_actions.c` | **[x] 2026-06-13** |
| G-3 | Dashboard | **Spindle CCW** sends `M4 S…`; CW sends `M3 S…` (respects `cnc_spcw`) | `driver.zig`, `ui_widget_actions.c` | **[x] 2026-06-13** |
| G-4 | Display | **Smooth animations** drives scroll momentum + anim duration in `settings_tune_scroll_container` | `ui_settings_widgets.c`, `ui_settings_tab_display.c` | **[x] 2026-06-13** |
| G-5 | Storage / Dashboard | Port A: `scan_begin/end`, `i2c_master_bus_reset` recover (no delete+recreate wedge) | `ext_encoder_shim.c`, `mbus_shim.c` | **[x] 2026-06-13** · **HW** verify ExtEncoder |

---

### Tab 0 — CNC & Connection (`ui_settings_tab_cnc.c`)

| Item | Status | Notes |
|------|--------|-------|
| Transport dropdown (ESP-NOW … CAN Bus) | **[x] code** · **HW** | Default RS-485 (idx 4); `modulus_zig_transport_reinit()` |
| Session hero + EVT refresh | **[x] code** · **HW** | `modulus_ui_settings_cnc_on_status_event()` + 1 Hz timer; scroll pauses timer |
| Configure / Reconnect / Disconnect | **[x] code** · **HW** | Modal `ui_settings_modals.c`; disconnect row dims when session off |
| ESP-NOW peer summary (read-only) | **[x] code** | Config on Wireless tab |
| Transport parameter summaries | **[x] code** | RS-485/USB/WS/Telnet/BLE/I2C/CAN read-only rows on tab |
| Settings browser ($$) | **[x] code** · **HW** | ADVANCED row -> `settings_grbl_dump_modal_show()` / `modulus_zig_settings_dump_*` |
| Connection profiles | **CS** | |
| USB HID / Gamepad transport | **CS** | Distinct from **BLE HID** (transport idx 5) |
| BLE HID transport config | **[x] code** · **HW** | Modal: `ble_name` NVS + keyboard; pairing on C6/BLE path |
| CAN Bus transport | **[x] code** · **HW** | Modal: `can_brate` / `can_nid` / `can_mode` NVS + TWAI shim |
| I2C transport | **[x] code** · **HW** | Modal: hex `i2c_addr` + `i2c_spd`; shares Port A with ExtEncoder |

---

### Tab 1 — Dashboard & Handwheel (`ui_settings_tab_dashboard.c`)

| Item | Status | Notes |
|------|--------|-------|
| Jog increments / mode / axes / WCS | **[x] code** | NVS + Zig driver |
| Encoder counts/step | **[x] code** | NVS; commit on release (H3) |
| MPG axis inversion | **[x] code** | NVS `cnc_mpgpol` |
| Metric (mm) units | **[x] code** | `$13=` via driver |
| Configure Quick Buttons | **[x] code** | Modal; NVS `cnc_qbtn0..3` |
| Quick button → Macro | **[x] code** | G-2 — NVS `cnc_macro`; default `M5`; editor in Dashboard tab |
| Macro G-code editor | **[x] code** | Modal save -> NVS `cnc_macro`; reset clears macro |
| Quick button → Spindle CCW | **[x] code** | G-3 — `M4 S…` via `modulus_zig_cmd_spindle_ccw()` |
| Handwheel / ExtEncoder (MPG) | **[x] code** · **HW** | G-5 shim — field verify on COM5 |
| Handwheel reference block | **[x] code** | Info-only |

---

### Tab 2 — Display & Theme (`ui_settings_tab_display.c`)

| Item | Status | Notes |
|------|--------|-------|
| Brightness | **[x] code** | Preview + NVS on release |
| Dark mode / Accent | **[x] code** | F-T1 active-tab rebuild |
| Glove-friendly touch | **[x] code** | `touch_shim.c` |
| Wake on motion | **[x] code** · **HW** | `imu_shim.c`; cold-wake soak open |
| Flip display | **[x] code** | `modulus_display_set_flip()` |
| Left-handed layout | **[x] code** | Dashboard flex only |
| Dashboard refresh rate | **[x] code** | NVS `refr_hz`; min 33 ms |
| Smooth animations | **[x] code** | G-4 — momentum + anim duration from NVS |
| Auto-brightness | **[x] code** | Disabled toggle + "Not fitted" detail; `modulus_display_has_ambient_light_sensor()` false |

---

### Tab 3 — Audio & Haptics (`ui_settings_tab_audio.c`)

| Item | Status | Notes |
|------|--------|-------|
| Volume / touch sounds / tone profile | **[x] code** · **HW** | Per-leaf dim when `is_output_ready()`; vol NVS on `RELEASED` (H3) |
| Startup / shutdown sounds | **[x] code** | NVS `snd_up` / `snd_dn`; always editable (not output-gated) |
| Microphone gain | **[x] code** · **HW** | `modulus_audio_get_mic_gain_idx()` + ES7210 when input ready |
| Tone profile preview | **[x] code** | `MODULUS_UI_SOUND_POP` after `set_tone_profile()` (C++ parity) |
| Touch sounds toggle tick | **[x] code** | No duplicate tick — global indev `RELEASED` only |
| Hardware reference expand | **[x] code** | Scroll preserved on rebuild; ref collapsed on tab leave |
| Headphone jack detect | **[x] code** · **HW** | PI4IOE live row in expanded hardware ref |
| Haptic feedback | **CS** | |
| Acoustic echo cancellation | **CS** | ES7210 listed in reference; no runtime AEC toggle |
| Codec unavailable rows | **[x] code** | Output/input status detail rows |

---

### Tab 4 — Wireless (`ui_settings_wireless.c`)

| Item | Status | Notes |
|------|--------|-------|
| Hub: Wi-Fi / BT / ESP-NOW / Zigbee / Thread | **[x] code** · **HW** | C6 SDIO hosted |
| External MMCX antenna | **[x] code** | NVS `ant_ext` |
| Wi-Fi scan / connect / saved / forget | **[x] code** · **HW** | STA+IP field open |
| Static IP / DNS | **CS** | `wf_dhcp` shows mode; no IP fields |
| BT Advanced: idle off / bg scan / pairing confirm / block unknown | **CS** ×4 | |
| ESP-NOW peers / channel / PMK | **[x] code** · **HW** | PMK fixed string in UI |
| Zigbee join / scan / device registry | **[~] code** · **HW** | ON/OFF via C6 when joined |
| Thread attach / scan / registry | **[~] code** · **HW** | |
| Thread device ON/OFF toggles | **[~] STUB** | NVS cache only — *Matter/CoAP needs C6 RPC* (`wireless_shim_802154.c`) |
| Zigbee control when not joined | **[~] STUB** | Advanced: *Cache only* |

---

### Tab 5 — Power (`ui_settings_tab_power.c`)

| Item | Status | Notes |
|------|--------|-------|
| Battery telemetry | **[x] code** · **HW** | INA226 or *unavailable* row |
| EXT 5V / USB 5V rails | **[x] code** | EXT5V required for Port A modules |
| Dim / screen timeout / Sleep now | **[x] code** · **HW** | Deep-sleep walk open |
| System sleep / wake sources / gate rails | **[x] code** | Wake/timer/gate NVS sync runtime; USB wake via CHG_STAT edge |
| Battery pack / warn-at / charging | **[x] code** | |
| Adaptive battery | **[x] code** · **HW** | `bat_adapt` — tightens dim/scr timeout on battery (≤50% / ≤20%) |
| Quick charge (QC 2.0/3) | **[x] code** · **HW** | NVS `qc` → PI4IOE nCHG_QC; default on |
| SoC temperature row | **[x] code** | ESP32-P4 die via `temperature_sensor` (not pack) |

---

### Tab 6 — Security (`ui_settings_tabs_extra.c`)

| Item | Status | Notes |
|------|--------|-------|
| Set / change / clear PIN | **[x] code** · **HW** | `security_shim.c` |
| Lock after sleep timeout | **[x] code** | NVS `pin_tmo` |
| PIN on boot / PIN on wake | **[x] code** · **HW** | |
| Idle lock without display sleep | **[x] code** · **[ ] HW** | NVS `pin_idle`/`pin_idle_tmo`; `modulus_security_idle_lock_tick()` in `display_shim.c`; Security tab toggle + timeout; activity monitor re-armed in `modulus_security_init()` after boot-order fix |

---

### Tab 7 — Machine (`ui_settings_tabs_extra.c`)

| Item | Status | Notes |
|------|--------|-------|
| Default jog speed | **[x] code** | NVS on release; reloads encoder |
| Default feed / spindle override % | **[x] code** | `envelope.zig` |
| Max feed rate slider | **[x] code** | G-1 |
| Max spindle RPM slider | **[x] code** | G-1 |
| Machine name / type | **[x] code** | |
| Controller link (protocol / transport) | **[x] code** | Summary row + **CNC Connection** link (tab 0) |
| Allow CCW (M4) | **[x] code** | NVS `cnc_spcw` |
| Maintenance counters | **[x] code** | Local odometer / spindle hours |
| Soft limit enforcement on pendant | **[x] code** · **HW** | `cnc_slim` + travel NVS; jog clamp in `driver.zig` |
| On-device settings browser ($$) | **[x] code** · **HW** | Modal + `$$` capture |
| Sync work envelope to controller | **[x] code** · **HW** | `$110-$112`, `$30` queue on Idle session |
| `cnc_mxrpm` direct S-word clamp | **[x] code** | `envelope.clampGcodeSpindle` + `driver.cmdSendGcode` |

---

### Tab 8 — Storage & Diagnostics (`ui_settings_tabs_extra.c`)

| Item | Status | Notes |
|------|--------|-------|
| SD mount / eject / capacity | **[x] code** · **HW** | |
| Memory telemetry | **[x] code** | Live timer |
| Log level | **[x] code** | |
| Export diagnostics → SD | **[x] code** · **HW** | Needs mounted SD |
| Clear UI cache | **[x] code** | |
| USB host status | **[x] code** · **HW** | Read-only |
| I2C bus scanner (M-Bus / Port A / expanders) | **[x] code** · **HW** | G-5 scan coord; Port A field verify |
| Port map reference | **[x] code** | Info-only |

---

### Tab 9 — System & About (`ui_settings_tab_system.c`)

| Item | Status | Notes |
|------|--------|-------|
| Firmware / platform / RTC / uptime | **[x] code** | |
| Language picker | **[~] STUB** | fr/es/zh *(pending)*; ~6 strings in `i18n_shim.c`; rest English |
| Time zone / 12–24h / date format | **[x] code** | |
| Full-screen keyboard | **[x] code** | NVS `kb_full` |
| NTP / Sync now / manual time | **[x] code** · **HW** | |
| Restart / Shutdown / Factory reset | **[x] code** · **HW** | |
| Check for updates | **NI** | `modulus_zig_ota_status_text()` stub |
| Auto-update | **NI** | No `ota_0`/`ota_1` layout |

---

### Cross-tab / shell

| Item | Status | Notes |
|------|--------|-------|
| Settings search / filter | **[—]** | C++ P2 deferred |
| Full i18n (fr/es/zh + Noto) | **[~] STUB** | EN literals; see Tab 9 |
| Macro G-code editor | **[x] code** | Dashboard tab modal; NVS `cnc_macro`; quick button via G-2 |
| Wireless status-bar icon | **[x] code** · **[ ] HW** | Wi-Fi (off/idle/connecting/STA), BLE + ESP-NOW when radio on; `modulus_wireless_*` shims |
| Fan from controller `\|A:\|` bit | **[—] N/A v1** | Fan quick button = local toggle |

---

## Part E — Flash / soak log template

**Run:** `scripts/soak_tab5_perf.ps1 [-Port COM5] [-SkipBuild]` — emits dated template under `docs/verify/`.

```text
Date:
P4 ELF SHA256:
C6 image version:
Flash: COM5 only / dual COM6→COM5
Cold boot: Wireless ready Y/N  SDIO errors:
Idle dashboard 55s WDT: PASS/FAIL
LVGL CPU idle (perf monitor): ___%
Scroll soak (F2): PASS/FAIL
Frame FPS idle / scroll: ___ / ___
Heap PSRAM largest blk (init / settings close): ___ / ___
Notes:
```

**Last recorded (device, dual):** 2026-06-15 — `scripts/flash_tab5_dual.ps1 -C6Port COM6 -P4Port COM5`; C6 **exit 0** COM6 · P4 ELF `dbed1ea0c0ef8c930191c5840ee93927bda61485147f45d3b8335c2c97a96b18` (app `0x29a2a0`, **48%** factory free @ 5 MiB) · P4 **exit 0** COM5 · esptool **Hash of data verified** (C6 + P4) · script **exit 0** · **dual PASS** · **matches workspace** · cold boot wireless **not logged**.
**Prior recorded (device, COM5):** 2026-06-15 — `scripts/flash_tab5.ps1 -Port COM5`; flashed ELF `e9a60c21516712691257d85d43f87ea9279ddb1743409851363751b11a36fb24` (app `0x29a1f0`, **48%** factory free @ 5 MiB). **exit 0** · **COM5 flash PASS** · esptool **Hash of data verified** (bootloader/partition unchanged sectors verified). **Matches workspace**.

**Prior recorded (device, COM5):** 2026-06-14 - ELF `8510fad8cf2343cebc25ed3f4b0fe74b3ee8a3e12e90de17897aed4f2e6830a0` (app `0x29a020`, **48%** factory free). **Matches workspace** at that build.

**Prior soak:** 2026-06-07 cycle 1 — `Wireless ready`, 60 s idle WDT OK ([soak_cycle1](soak_cycle1_com5_2026-06-07.log)). 2026-06-14 — 5 MiB partition table flash PASS.

---

*Maintained from M3 cross-reference 2026-06-15. **Part A + Part B + Part F COMPLETE (code).** **Part G** Settings tab audit 2026-06-13; session polish in ELF `dbed1ea0…` dual-flashed COM6→COM5. HW cold boot + F6 soak open on current ELF. F5 Flash/XIP section removed (tracked under P0-1 / F-ROM). Sync with `MEMORY.md` after major sessions.*

**Code band methodology (2026-06-14 recount):** Part B2 (23) + Part C (21) + P1 code col (12) + P2 excl N/A (10) + Transport excl N/A (6) + Wireless honesty (4) = 76 trackable; `[—]`/CS/NI excluded.
