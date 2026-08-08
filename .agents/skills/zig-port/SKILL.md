---
name: zig-port
description: >-
  Modulus C++ → Zig port plan for Tab5 firmware. Layer order (core, cnc, hal, ui),
  verify gates, C++ reference paths, and per-phase pitfalls. Load when porting
  firmware from Modulus Convert to ZIG core or adding src/modulus/ modules.
---

# Modulus Zig Port

**Reference firmware (C++):** `../Modulus Convert to ZIG core/Modulus Firmware/main/`  
**Target Zig:** `src/modulus/` (host tests in root `build.zig`; device objects via IDF/CMake later)  
**C6 slave:** stays C (ESP-Hosted 1.4.0) — do not port `Modulus Firmware C6/`

Load **`zig-core`** for language mechanics; **`zig-build`** for commands/MCP; rule **`zig-pitfalls`** for issue-derived guardrails.

## Port principles

1. **Host-first:** every layer gets `zig build test` before IDF link.
2. **NVS schema frozen:** keep `"modulus"` namespace keys identical to `settings_store` (≤15 chars).
3. **Core affinity preserved:** Core 0 UI/event bus; Core 1 ~100 Hz CNC poll — document in module headers.
4. **No heap in hot paths:** Core 1 / ISR loops use fixed buffers or init-scoped arenas only.
5. **C for BSP/radio:** `m5stack_tab5`, `esp_hosted`, LVGL — `@cImport` or `addTranslateC` until bindings mature.

## Phase map

| Phase | C++ source | Zig target | Defer |
|-------|------------|------------|-------|
| 0 | — | `build.zig`, `build.zig.zon`, layout | — |
| 1 | `core/` | `src/modulus/core/` | — |
| 2 | `cnc/`, `cnc/grblhal/` | `src/modulus/cnc/` | — |
| 3 | `hal/hal_transport`, `hal_serial`, … | `src/modulus/hal/transport/` | wireless |
| 4 | `hal/hal_wireless`, `hal_espnow` | `src/modulus/hal/wireless/` | UI |
| 5 | `ui/`, `i18n/` | optional / last | LVGL bindings huge |

---

## Phase 0 — Scaffold

**Do:** `build.zig`, `build.zig.zon` with `minimum_zig_version = "0.16.0"`, `src/modulus/root.zig`, `src/modulus/testing/leak_guard.zig`, CI `.github/workflows/zig-test.yml`.

**Verify:**
```powershell
zig version          # 0.16.x
zig fmt --check src/
zig build test       # std.testing.allocator + LeakGuard — leaks fail build
```

**Pitfalls:** hand-edited `build.zig.zon` fingerprints → use `zig fetch --save`. Circular module imports → DAG only.

---

## Phase 1 — Core (`core/`)

**C++ files:** `modulus.cpp`, `event_bus.*`, `settings_store.*`, `system_events.h`, `str_util.h`

**Port order:**
1. `system_events.h` → comptime event IDs (`pub const EVT_*`)
2. `settings_store` → NVS key constants + typed getters (host: mock or file-backed tests)
3. `event_bus` → queue + subscribe; test dispatch without LVGL
4. `modulus.boot` → orchestration stub; spawn policy documented (no FreeRTOS yet on host)

**Must preserve:**
- Boot order from `modulus.cpp` (event_bus → settings → … → transport → wireless → UI)
- Event queue depth **16**, max payload **64**
- `EVT_CNC_STATUS_UPDATE` publish on state change

**Verify:**
```powershell
zig build test -- --test-filter "core"
```
- Unit tests: NVS key round-trip, event_bus pub/sub, boot phase ordering (mock HAL)

**Pitfalls:** `settings_store` without mutex (match C++); don't add subscribers for unused `SystemEvent` IDs without publishers.

---

## Phase 2 — CNC (`cnc/` + `grblhal/`)

**C++ files:** `cnc_config.h`, `cnc_state.*`, `cnc_driver.*`, `grblhal/*`, skip `cnc_sim` (unused)

**Port order:**
1. `cnc_config` enums + defaults (`kDefaultCncConn = RS485` = 4)
2. `MachineStatus` struct + state strings
3. `grblhal` parser → line buffer 256B, status report tags
4. `grblhal` engine → session FSM (WaitBanner → Querying → Ready/Locked/MPGBlocked)
5. `cnc_driver` → spinlock snapshot, `poll`/`feed`/`set_send_fn`, command gating

**Must preserve:**
- RT bytes: `0x80`, `0x87`, `0x81`–`0x85`, `0x8B`, override range `0x90`–`0x9D`
- 3s response timeout → session Disconnected
- `portMUX` / equivalent for Core 1 write, Core 0 read

**Verify:**
```powershell
zig build test -- --test-filter "cnc"
```
- Parser tests: sample `<Idle|MPos:…>`, `ok`, `ALARM:1`, welcome banner
- Session FSM tests: connect → Ready without hardware
- Feed/hold: mock `SendFn` records bytes

**Pitfalls:** no `packed struct` returns @ ReleaseSafe ([#35634](https://codeberg.org/ziglang/zig/issues/35634)). Avoid `i24` and odd-width ints in parser ([#35597](https://codeberg.org/ziglang/zig/issues/35597)). No float in `poll` loop.

---

## Phase 3 — HAL transports

**C++ files:** `hal_transport.cpp`, `hal_serial.*`, `hal_websocket.*`, `hal_telnet.*`, `hal_ble.*`, `hal_i2c_transport.*`, `hal_canbus.*`, `hal_espnow.*` (transport only)

**Port order:**
1. `hal_transport` dispatcher (`cnc_conn` NVS index)
2. `hal_serial` (RS485 default: UART1 TX20/RX21/DE34) — mock UART for tests
3. Remaining transports one at a time (WebSocket, Telnet, BLE, I2C, CAN, ESP-NOW)
4. Wire `feed` + `set_send_fn` + `on_connect`/`on_disconnect` to `cnc_driver`

**Must preserve:**
- Single active transport from NVS `cnc_conn`
- `USB_HID` / `USB_Gamepad` — **not** in dispatcher (UI only)

**Verify:**
- Per-transport unit tests with mock I/O
- Integration test: dispatcher selects RS485 by default

**Pitfalls:** bool FFI to C ([#35373](https://codeberg.org/ziglang/zig/issues/35373)) — prefer `c_int` for new shims. I2C transport without `hal_i2c_coex` — document bus contention with ext encoder.

---

## Phase 4 — HAL platform (display, power, wireless, …)

**Subset first:** `hal_display`, `hal_power`, `hal_battery`, `hal_i2c_coex`, `hal_ext_encoder`  
**Later:** audio, storage, security, DSP, IMU stub

**Wireless last in HAL:** `hal_wireless` + `hal_espnow` — requires `esp_hosted` translate-C module.

**Must preserve:**
- C6 SDIO: CLK12, CMD13, D0–D3=11/10/9/8, RST=15
- Custom channels: ESP_ESPNOW_IF=8, ZIGBEE_IF=9, THREAD_IF=10
- Sleep: `hal_transport::deinit` → `prepare_for_sleep` → `deinit` before C6 power gate

**Verify:**
- Host: mock `esp_hosted` or skip wireless tests until translate-C wired
- IDF: link single Zig object + existing C HAL alongside (hybrid build)

**Pitfalls:** large BSS (framebuffers) — watch ELF linker ([#31580](https://codeberg.org/ziglang/zig/issues/31580)). `no_builtin` / soft-float on freestanding ([#32125](https://codeberg.org/ziglang/zig/issues/32125)).

---

## Phase 5 — UI / LVGL (MVP done)

**Shipped:** `src/modulus/ui/` + `firmware/tab5/components/modulus_zig/ui_*.c` — boot splash, MPG dashboard (DRO + overrides), PIN lock overlay, M3-dark theme, event-driven screen change / deep-sleep.

## Phase 5b — Dashboard operations (done)

**Shipped:** status bar (conn/session dot, state badge, MPG toggle, feed %, battery), jog STEP/CONT + increment tiles, action buttons (cycle/hold/home-all), Zig `modulus_zig_cmd_*` ABI epoch 10.

## Phase 5c — Overrides + settings (done)

**Shipped:** `ui_widget_overrides.c` (feed/spindle columns), `ui_settings.c` + `ui_settings_tabs.c` (CNC/Display/Power/System), settings gear on status bar, `modulus_zig_cmd_feed_override` / `modulus_zig_cmd_spindle_override`, ABI epoch 11.

## Phase 5d — DRO + status bar extras (done)

**Shipped:** `ui_widget_dro.c` (per-axis HOME/ZERO, active highlight), status bar WCS/tool/feed/spindle/clock, `modulus_zig_cmd_home_axis` / `zero_axis` / `cycle_wcs`, extended `CncStatus`, ABI epoch 12.

## Phase 5e — Quick settings + power menu (done)

**Shipped:** `ui_quick_settings.c` (brightness, transport, open settings), `ui_power_menu.c` (reset/unlock/restart/sleep), gear long-press + power button on status bar, `modulus_zig_cmd_reset` / `cmd_unlock`, ABI epoch 13.

## Phase 5f — Settings 10-tab MVP (done)

**Shipped:** `ui_settings_tabs_extra.c` — Dashboard, Audio, Wireless, Security, Machine, Storage tabs; Power tab deep-sleep policy; scrollable 10-tab sidebar.

## Phase 5g — Dashboard reference layout (done)

**Shipped:** 4-axis DRO (`cnc_axes` NVS), purple accent selections, jog `xN` increment labels, feed/spindle override columns, actions grid + `modulus_zig_cmd_spindle/coolant/fan/single_step`; `CncStatus` +A axis; ABI epoch 14. FAN/single-step stub offline.

**Still deferred vs C++ reference:** full settings tab depth (PIN editor, Wi-Fi scan, SD diag), i18n, home screen, PMIC shutdown, RX8130 RTC.

If extending: host-only policy tests in `ui/manager.zig`; never mutate LVGL except under display lock / Core 0 (`evt_dispatch`).

## LVGL render budget (taskLVGL Core-0 watchdog)

Hard-won (2026-06-06). Full rule: **`.cursor/rules/lvgl-tab5-ui-pitfalls.mdc`** (auto-loaded). Ruflo `patterns`: **`lvgl-heap-psram`**, `lvgl-layout-pitfalls`, `status-bar-regressions`, `phosphor-icons-pipeline`, `tab5-flash-build`.

0. **Check sdkconfig heap FIRST on recurring WDT.** Never `CONFIG_LV_USE_BUILTIN_MALLOC=y` + 64 KB pool on Tab5 1280×720 `sw_rotate` — use `CONFIG_LV_USE_CLIB_MALLOC=y` + PSRAM C heap (`CONFIG_SPIRAM_USE_MALLOC=y`). Symptom: idle dashboard WDT ~every 5 s, backtrace `lv_tlsf_malloc` / `lv_draw_buf_create` (decode with matching ELF; not mp3/settings stale symbols). Overlay/menu refactors do **not** fix heap exhaustion.
1. **Never fake big fonts with `lv_style_transform_scale`.** Under `sw_rotate` 1280x720 every transformed label is an affine-scaled layer → huge per-frame redraw. Enable the real `CONFIG_LV_FONT_MONTSERRAT_*` tier (m3_theme: 12/16/22/24/28/36/44) and set `lv_obj_set_style_text_font`. Fonts cost flash → `partitions.csv` factory = 3 MB (16 MB flash).
2. **Change-gate every `update()`.** `lv_label_set_text` / `lv_obj_set_style_*` ALWAYS invalidate (no content compare). Cache last value per field (`static`), skip the LVGL call when unchanged — exactly like the C++ reference `status_bar::update` / `widget_dro::update`. Unconditional per-tick rewrites = continuous full-screen invalidation = WDT.
3. **Opaque scrims, per-leaf opacity.** Full-screen translucent overlays + live dashboard refresh, parent group `lv_obj_set_style_opa`, and `LV_SCR_LOAD_ANIM_FADE_IN` force extra compositing layers — use `LV_OPA_COVER` scrims and leaf-level dim only.
4. **Never `lv_pct(100)` on children of `LV_SIZE_CONTENT` flex cols** — collapses to zero width (status-bar stat columns).
5. **Build before flash** — `idf.py build` then `idf.py -p COM5 flash`; nested `powershell -Command` breaks `$env:IDF_PATH`.
6. **Phosphor icons** — Light (status bar) + Fill (dashboard actions); regen `scripts/gen_phosphor_icons.mjs`; GearSix 40 px settings; dynamic battery stem + recolor.

Also: refresh period floor ≥30 ms; idle ≥55 s zero-WDT soak after sdkconfig heap change; C-shim (`ui_*.c`) / sdkconfig changes → **no ABI epoch bump** unless `CncStatus` touched.

---

## IDF / device link (after host tests green)

| Context | Target | Tooling |
|---------|--------|---------|
| Host tests | native | `zig build test` |
| P4 firmware | `riscv32-freestanding-none` | CMake + `idf.py`; `addTranslateC` for IDF headers |
| ZLS | host only until `check` target exists | `zig-build` skill |

**translate-C rules:** same `-target` as link; one header bundle per binary; `linkLibC()` when using libc.

**Optimize modes:** Debug host tests; **ReleaseSafe** first for device objects; audit **ReleaseSmall** separately ([#35560](https://codeberg.org/ziglang/zig/issues/35560)).

---

## Hybrid coexistence (during port)

Allowed: Zig `core` + `cnc` linked with C++ `hal` + `ui` via C ABI exports (`export fn`, `extern "C"`).

**Freeze C++ NVS/event IDs** while Zig core lands. Do not rename `cnc_conn` keys.

---

## Done criteria (full port)

- [ ] `zig build test` green (host)
- [ ] `zig fmt --check src/` clean
- [ ] NVS key table matches C++ `settings_store` inventory
- [ ] grblHAL session + parser tests pass without controller
- [ ] RS485 transport feeds parser (hardware or mock)
- [ ] P4 image boots through `modulus::boot` equivalent
- [ ] C6 still ESP-Hosted 1.4.0; SDIO unchanged
- [ ] Core 1 loop ≤10 ms; no heap in poll path

---

## Reference docs

| Need | Location |
|------|----------|
| C++ architecture | `../Modulus Convert to ZIG core/Modulus Firmware/instructions.md` |
| Agent instructions | `instructions.md` in reference tree |
| Zig issues guardrails | `.cursor/rules/zig-pitfalls.mdc` |
| Tab5 pins | `.cursor/rules/modulus-tab5.mdc`, `docs/hardware/tab5/` |
