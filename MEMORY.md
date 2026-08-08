# Modulus Convert to ZIG — project memory

*Updated: 2026-07-19 evening (zb_automation CNC↔OnOff; rebuild bins; Hackster draft)*

*Updated: 2026-07-19 afternoon (permit-join TC, UART ACK/NAK, zb_devdb, hub watchdog, ESP-NOW rate)*

*Updated: 2026-07-19 (NanoH2 Zigbee hub — Zigbee OFF C6; four-firmware policy; P4 UART host)*

*Updated: 2026-07-04 (C6 build policy + fix catalog; `-ZigbeeExclusive` canonical path; 175 tests green)*

*Updated: 2026-07-04 (re-sync: 175 tests green, wireless_shim trim 953L, evolver cycle)*

*Updated: 2026-07-03 afternoon (re-sync: ELF hash, C6 workspace bin, Open TODO, CBM index)*

*Updated: 2026-07-03 morning (ABI 18, LinuxCNC/Mach3 engines, UI shim splits, accent palettes, 175 host tests)*

**Codebase sync (2026-07-19 evening):**

| Item | Detail |
|------|--------|
| **ABI epoch** | **18** (unchanged) |
| **NanoH2 hub** | `modulus_nanoh2.bin` **0x96100** (~600 KiB); ELF `be8e69b14bda8c75548f5681b58b14c2be75b86d1e7deaf1b06f20ac2166a5e0`; `zigbee_hub.c` **1292L** |
| **P4 app** | `modulus_tab5.bin` **0x2fe0e0** (~2.99 MB, **~60%** of 5 MB factory); ELF `60ab02fd0f09c77b56bf7113784442b872e7164472a83318d4429107a384da79` |
| **zb_automation** | New `zb_automation.c` (**134L**) — per-slot NVS `zbN_auto`: off / follow CNC / inverse; `modulus_zb_auto_poll` ~1 Hz from 802.15.4 loop; UI cycle in `ui_settings_wireless_154.c` |
| **zb_devdb on P4** | `zb_devdb_data.c` **4611L** / ~373 KiB ROM (**4603** entries) linked into app — main driver of afternoon→evening size jump |
| **Wireless C debt** | `wireless_shim.c` **1075L**; `wireless_shim_802154.c` **986L**; `wireless_c6_rpc.c` **602L**; `zb_uart_host.c` **219L** |
| **Hackster** | `Modulus_Hackster_Documentation.md` (**354L**) — GIC 2026 draft; media/`[TBD]` placeholders; submit by **Aug 7, 2026 11:59 PM PST** |
| **C6 slave** | Workspace still **0x192590** (2026-07-03 ZigbeeExclusive-era) — rebuild **without** ZigbeeExclusive before dual flash |
| **Git** | Full untracked tree — no commits yet |

**Codebase sync (2026-07-19 afternoon):**

| Item | Detail |
|------|--------|
| **ABI epoch** | **18** (unchanged) |
| **NanoH2 hub** | Was **0x95690** ELF `97fce383…` / `zigbee_hub.c` **1286L** — superseded by evening **0x96100** |
| **P4 app** | Was **0x2bd1f0** ELF `384b523d…` — superseded by evening **0x2fe0e0** |
| **UART protocol** | Max payload **256**; sequenced cmds `[seq][cmd][args]` → hub `EVT_ACK`/`EVT_NAK` (0x94/0x95); P4 `modulus_zb_uart_send_cmd` retries |
| **Permit-join fix** | Must call `esp_zb_zdo_permit_joining_req(dst=0x0000, tc_significance=1)` **+** `bdb_open_network` — BDB alone leaves Trust Center closed (empty scan) |
| **zb_devdb** | Generated `zb_devdb_data.c` (**4603** ModelIdentifier entries) via `tools/gen_zb_devdb.py`; NVS `zbN_md` persists ZCL model |
| **Hub watchdog** | `modulus_zb_uart_hub_offline()` after **3×** supervision windows (~210 s silence); UI + quick-settings ASCII warn |
| **ESP-NOW** | NVS `en_rate` default **6** (24M OFDM); adaptive drop to 11M floor / climb after 32 OK; C6 `ESPNOW_CMD_SET_RATE`; Thread off on product C6 |
| **Wireless C debt** | Was 802154 **963L** / rpc **589L** — see evening |
| **NanoH2 build** | `idf.py -C firmware/nanoh2 fullclean` PASS (2026-07-19); use IDF **6.2** python env — `export.ps1` can hang on outdated-tools scan |
| **Git** | Full untracked tree — no commits yet |

**Codebase sync (2026-07-19 morning):**

| Item | Detail |
|------|--------|
| **ABI epoch** | **18** (unchanged) |
| **Architecture** | **Zigbee moved off C6** → dedicated **M5 NanoH2** (ESP32-H2FH4S) ZBOSS coordinator over framed UART; C6 is **ESP-NOW / Wi-Fi / BLE** (+ Thread optional) only |
| **NanoH2 hub** | Was **0x266a0** — superseded via afternoon→evening (**0x96100**) |
| **P4 app** | Was **0x2bcc40** — superseded via afternoon→evening (**0x2fe0e0**) |
| **P4 Zigbee transport** | `zb_uart_host.c` + `wireless_c6_rpc.c` → UART2 **460800** (not SDIO `ESP_ZIGBEE_IF`) |
| **C6 Zigbee** | `zigbee_handler.c` = **SDIO stub** (`EVT_FAIL` 0x30); `esp-zigbee-lib` **removed**; `sdkconfig.defaults.zigbee` **DEPRECATED** |
| **C6 build command** | **`.\scripts\build_tab5_c6_modulus.ps1 -Action build|flash -Port COM6`** — no ZigbeeExclusive; never edit mirror |
| **Git** | Full untracked tree — no commits yet |

**Codebase sync (2026-07-04):**

| Item | Detail |
|------|--------|
| **ABI epoch** | **18** (unchanged) |
| **Host tests** | **175** pass (`zig build test --summary all` green 2026-07-04) |
| **P4 app (last workspace build)** | `modulus_tab5.bin` **0x2aa4c0** (~2.67 MB, **~53%** of 5 MB factory); ELF `ad4f51516c4aa82cb3e1e857e2359760517e1653597228b63d07a49395f547be` — superseded by 2026-07-19 **0x2bcc40** |
| **C6 slave (workspace build)** | `network_adapter.bin` **0x192590** (2.11.4 + then-ZigbeeExclusive / ZBOSS hub) — **superseded:** Zigbee now on NanoH2; rebuild C6 without ZigbeeExclusive |
| **C6 build command** | Was `-ZigbeeExclusive` — **DEPRECATED 2026-07-19** (coex failure on shared radio) |
| **Wireless C debt** | `wireless_shim.c` **953L** (was 1052L); grew again w/ NanoH2 path — see 2026-07-19 |
| **Git** | Full untracked tree — no commits yet |
| **Evolver** | `evolver run` cycle completed 2026-07-04 |

**Codebase sync (2026-07-03):**

| Item | Detail |
|------|--------|
| **ABI epoch** | **18** (`abi.zig`) — 17 = `abi_guard` null/len on exports + settings-dump defer cancel; 18 = `settings_dump_copy` writes caller buffer directly (fixes taskLVGL 16 KiB stack overflow on grbl `$$` modal) + serial RX chunk **2048 B** (was 512 — WS frames truncated) |
| **Host tests** | **175** pass (`zig build test` green 2026-07-03 afternoon) |
| **P4 app (workspace build)** | `modulus_tab5.bin` **0x2aa4c0** (~2.67 MB, **~53%** of 5 MB factory); ELF `ad4f51516c4aa82cb3e1e857e2359760517e1653597228b63d07a49395f547be` |
| **C6 slave (workspace build)** | `network_adapter.bin` **0x192590** (2.11.4 tree); **last dual-flash field** still **0x182440** — reflash C6 if slave sources changed since 2026-06-20 |
| **Multi-protocol CNC** | `protocol_engine.zig` facade — grblHAL (default) + **LinuxCNC** (`src/modulus/cnc/linuxcnc/`) + **Mach3/Mach4** (`src/modulus/cnc/mach3/`); NVS `cnc_proto` selects engine |
| **ExtEncoder Zig split** | `ext_encoder_state`, `ext_encoder_poll_ops`, `ext_encoder_jog`, `ext_encoder_trace`, `ext_encoder_const`, `ext_encoder_util` — Core 1 poll stays heap-free |
| **UI accent palettes** | `scripts/gen_ui_palettes.py` → `ui_palette_schemes.h` (9 dark/light schemes); `build_tab5.ps1` runs before IDF build |
| **C shim count** | `modulus_zig` CMake **102** `.c` sources (was ~72) — surgical splits, no orphans |
| **UI splits** | Settings tabs per-file (`ui_settings_tab_{cnc,display,power,system,dashboard,audio,security,machine,storage}`); `ui_status_bar_{helpers,data,build}`; `ui_power_menu_{build,shell,confirm}`; `ui_widget_dro_build`; wireless UI → `ui_settings_wireless_{state,kb,timer,nav,wifi,bt,154,espnow,misc,build,theme}` |
| **Wireless C debt** | `wireless_shim_espnow.c` (807L) + `wireless_shim_802154.c` (899L) extracted; **`wireless_shim.c` 953L** (WiFi/hosted core; was 1052L) |
| **New shims** | `touch_shim.c`, `estop_gpio_shim.c`, `cnc_trace_shim.c`, `ui_axes_preset.c` |
| **Stale partition warning** | `partitions.csv` = **5 MB** factory; devices flashed before 2026-06-14 may still boot **3 MB** table — reflash partition table + app when bin > 3 MB |
| **CBM** | Indexed 2026-07-03 afternoon (`fast` mode) — project `c-Users-BEAST MODE-Desktop-Modulus Convert to ZIG` |

*Updated: 2026-06-20 (Tab5 ESP-NOW CNC link fix — C6 local channel lock, no host SDIO RPC)*

*Updated: 2026-06-20 (SDIO v5 stale-counter fix — ESP-NOW blocked by transport fail)*

*Updated: 2026-06-20 (tab5-lib freestanding root + dual flash baseline + partition 5 MB)*

**Tab5 ESP-NOW CNC link fix (2026-06-20, field-verified):** Tab5 ↔ S3 bridge unicast failed (`send fail reason=0x01`) after SDIO `Wireless ready`. Peer add OK (`Bridge peer … ch1`) but CNC poll dead until fix + dual flash.

| Symptom | Cause |
|---------|--------|
| `RPC_Req [0x12e]` every ~500 ms during CNC poll | Host `esp_wifi_get_channel()` → esp_hosted **Req_WifiGetChannel** contends with ESP-NOW on SDIO |
| `Wi-Fi Home channel change` + send fail | C6 disconnected-STA drifts off bridge ch1 |
| `peerch=0` (older builds) | C6 `peer.channel=0` — reference uses **explicit ch** (`payload[6]`) |

| Fix | Where |
|-----|--------|
| C6 local channel lock | `firmware/tab5-c6/main/espnow_handler.c` — `espnow_lock_radio_channel()`: `WIFI_PS_NONE` + `esp_wifi_set_channel(ch)` on init/add_peer/send |
| Reference peer semantics | `peer.channel = ch`, `WIFI_IF_STA`; plain `esp_now_send` |
| Host align no-op | `wireless_shim_espnow.c` — `modulus_wireless_espnow_align_channel()` empty; never on hot path |
| No per-send RPC | `espnow_transport_shim.c` — no `align_channel` before `espnow_send_and_wait` |
| Discovery | `modulus_espnow_stack_probe()` = bcast peer + `MOD_PROBE` via `ESPNOW_CMD_SEND` (match `hal_wireless.cpp`) |
| Transport wake | One-shot `MOD_PROBE` on transport open → S3 NVS `tab5_mac` |

**Verify:** `flash_tab5_dual.ps1` COM6→COM5; power-cycle Tab5; SHA `04579a12…`; no `0x12e` flood; CNC Connected. S3 ch **1**, plain ESP-NOW. Ref: `Modulus Firmware C6/slave/espnow_handler.c`, `hal_wireless.cpp`.

**tab5-lib freestanding + flash baseline (2026-06-20):**

| Item | Detail |
|------|--------|
| **P4 app (latest flash)** | `modulus_tab5.bin` **0x2a1210**; ELF `04579a126103c003a41ae46f23987aad0595620b36aeb8365b1c66754de34974`; COM5 flash PASS (ESP-NOW fix) |
| **C6 slave (latest dual flash)** | `network_adapter` **2.11.4** **0x182080**; COM6 flash PASS (retry after BOOT/sync fail) |
| **Factory partition** | **5 MB** (`partitions.csv` `0x500000`, bumped 2026-06-14) — replaces prior 3 MB table; `build_tab5.ps1` warns at **85%** of factory |
| **tab5-lib root** | New `src/modulus/tab5_root.zig` — freestanding `std_options` (4 KiB page, no networking/stack trace) + `std_options_debug_io = Io.failing`; `build.zig` tab5-lib uses `tab5_root.zig` + `.single_threaded = true`; host tests stay on `root.zig` |
| **Zig 0.16 device fixes** | `monotonic_ms.zig` `@divTrunc`; `idf_battery.zig` `@enumFromInt`; `display.zig` module-level `lockHw`/`applyTimeouts`; `deferred_connect.zig` `fetchAdd` discard + `xTaskCreate` handle type |
| **ui_shim.c guard** | LVGL malloc compile guard uses `CONFIG_LV_USE_*` from `sdkconfig.h` (not bare `LV_USE_*`) — fail fast if builtin TLSF drifts |
| **C6 espnow fix** | `espnow_handler.c` — local `espnow_lock_radio_channel()` + explicit `peer.channel`; host must not RPC channel on send (see ESP-NOW CNC fix above) |
| **Flash scripts** | P4-only: `flash_tab5.ps1 -Port COM5`; C6→P4: `flash_tab5_dual.ps1 -C6Port COM6 -P4Port COM5`; C6-only: `build_tab5_c6_modulus.ps1 -Action flash -Port COM6` |
| **SDIO v5 stale counter (2026-06-20)** | Post-flush `post-flush align 463903` → transport fail → ESP-NOW dead. Fix: poll until `PACKET_LEN==0`; dual flash after rebuild |
| **COM5 flash ops** | Recurring **Access is denied** when monitor holds COM5 — close monitor first; flash-only: `flash_tab5.ps1 -Port COM5 -SkipAscii -SkipBuild` |

**SDIO v5 stale-counter fix (2026-06-20):** Log signature: `RX counter resync v5: post-flush align 463903` then `Not able to connect` / `0x107` on retry. Rebuild + **dual flash** (C6 then P4). Checksum mismatch = stale P4 — reflash matching ELF.

*Updated: 2026-06-17 (addTranslateC shims + host HTTP/WS probe tooling)*

*Updated: 2026-06-17 (Zig 0.16.0 adoption — Io, @trunc, parser fuzz, test timeouts)*

*Updated: 2026-06-16 (S3 ESP-NOW UART bridge in-repo + IDF6 build PASS)*

**S3 bridge (2026-06-16):** Field **ESP32-S3** ESP-NOW ↔ UART grblHAL relay — **canonical tree** `firmware/s3-bridge/` (vendored from `../Modulus Convert to ZIG core/ESP32S3_ESPNOW_UART_Bridge  (Works)`; sibling folder is archive only). **Third firmware** — not on Tab5; separate USB (default **COM8**).

| Item | Detail |
|------|--------|
| Build | `scripts/build_s3_bridge.ps1` — `build` / `flash` / `monitor` / `flash-monitor` / `fullclean` |
| Image | `s3_espnow_uart_bridge.bin` **0xb2e30** (732720 B, **30%** app partition free) — IDF **6.0.1** build PASS |
| IDF6 deltas vs Works | `main/CMakeLists.txt` → `esp_driver_uart/gpio/rmt`; `uart_config_t` zero-init; **`MOD_PROBE`→`MOD_ACK`** in `espnow_link.cpp` (Tab5 C6 scan) |
| UART | UART1 TX=GPIO8 (SDA_host) RX=GPIO9 (SCL_host) @ **115200** → grblHAL USART6; shell: `baud`, `txgpio`, `rxgpio`, `uartping`, `status` |
| LEDs | GPIO45 red (TX/send), GPIO46 green (RX/recv) — discrete GPIO, 80 ms pulse |
| Module | **ESP32-S3-MINI-1** (I2C_ESP32_Module handwheel board); was WROOM-1 GPIO17/18 + WS2812 GPIO48 |
| ESP-NOW | ch **1** default; bridge MAC on boot log → Tab5 Settings → Wireless → ESP-NOW peer; **PMK off** (plain ESP-NOW); CNC transport = ESP-NOW |
| Peer learn | Bridge NVS `tab5_mac` = **C6 STA MAC** (not P4); auto-learn on first data packet; clear via reflash erase or new Tab5 C6 |
| Stale flash | Checksum mismatch = flash old bin — always `build_s3_bridge.ps1 -Action flash` after source change |

**Four-firmware flash policy:**

| Device | When | Script / build | Port |
|--------|------|----------------|------|
| **NanoH2** | Zigbee hub / ZBOSS / UART link change | `idf.py -C firmware/nanoh2 build` then flash (hold BUTTON=GPIO9 + USB-C) | NanoH2 USB |
| **S3 bridge** | ESP-NOW field link / bridge code change | `build_s3_bridge.ps1 -Action flash` | COM8 |
| **Tab5 C6** | SDIO 0x107, wireless stale, esp_hosted / ESP-NOW change | `flash_tab5_dual.ps1` (**no** `-ZigbeeExclusive`) | COM6→COM5 |
| **Tab5 P4** | UI/Zig/P4-only (C6 already 2.11.4 + Wireless ready) | `flash_tab5.ps1` | COM5 |

Signal paths:
- CNC: Tab5 P4 → SDIO → C6 ESP-NOW → air → S3 bridge → UART → grblHAL
- Zigbee: Tab5 P4 → UART2 (M5BUS) → NanoH2 Grove → ZBOSS 802.15.4 (dedicated radio)

**NanoH2 Zigbee hub (2026-07-18/19):** Root cause of ESP-NOW drops was C6 **one** 2.4 GHz radio shared between Wi-Fi/ESP-NOW and 802.15.4 ZBOSS. Fix: move Zigbee to **M5Stack NanoH2** (SKU C149, ESP32-H2FH4S — docs header "C6FH4" is wrong).

| Item | Detail |
|------|--------|
| Tree | `firmware/nanoh2/` — `main.c`, `zigbee_hub.c` (**1292L**), `zb_uart_link.c`, `zb_proto.h` |
| Image | `modulus_nanoh2.bin` **0x96100**; partitions: factory + **zb_storage/zb_fct** (required) |
| UART frame | `[0xA5][len_lo][len_hi][payload][crc8 poly 0x07]`; max payload **256**; baud **460800** |
| Cmd reliability | Host→hub `[seq][cmd][args]` (seq 1..255); hub `EVT_ACK`/`EVT_NAK`; P4 retries via `modulus_zb_uart_send_cmd` |
| Permit-join | `esp_zb_zdo_permit_joining_req(…, tc_significance=1)` **+** `bdb_open_network` — BDB alone = empty scan |
| Wiring | Grove G1 white (H2 TX GPIO1) → M5BUS pin 15 / P4 **GPIO7** RX; Grove G2 yellow (H2 RX GPIO2) ← M5BUS pin 16 / P4 **GPIO6** TX; Grove 5V ← M5BUS pin 28 SYS_EXT5VO; GND common |
| P4 side | `zb_uart_host.c`, `TAB5_ZB_UART_*` in `tab5_hw.h`; `wireless_c6_rpc.c`; hub forms at NanoH2 boot; hub heartbeat HUB_STATE ~5 s |
| Hub offline | Silence ≥ **3** supervision windows (~210 s) → `hub_offline` UI warn (vs never-connected) |
| Device DB | `zb_devdb` — **4603** herdsman converters (`zb_devdb_data.c` ~373 KiB in P4); regenerate `tools/gen_zb_devdb.py`; NVS `zbN_md` caches model |
| Automation | `zb_automation.c` — NVS `zbN_auto` off/follow/inverse CNC↔OnOff; poll from `wireless_shim_802154` |
| Protocol | Cmd/evt IDs in `zb_proto.h` / `c6_zigbee_proto.h`: HUB_START 0x10, PERMIT_JOIN 0x11, … EVT_HUB_STATE 0x88, DEV_LQI 0x8E, ACK/NAK 0x94/0x95 |
| LED | Blink = forming; solid = formed + host alive; double-blink = formed but P4 link silent |
| Factory reset | Hold BUTTON (GPIO9) **>3 s** → `esp_zb_factory_reset()` |
| C6 stub | Legacy SDIO Zigbee → `EVT_FAIL` reason **0x30** (wrong-transport) |

**Never** rebuild C6 with `-ZigbeeExclusive` / `sdkconfig.defaults.zigbee` — puts ZBOSS back on shared radio and reintroduces ESP-NOW coex failure.

**ESP-NOW post-Zigbee-off (2026-07-19):** C6 Thread off (`MODULUS_C6_THREAD=n`); no per-send channel lock; TX power 78; peer PHY via `ESPNOW_CMD_SET_RATE` + NVS `en_rate` (default **6**=24M OFDM, adaptive drop to 11M floor); SDIO `PRIO_Q_SERIAL` for ESP-NOW events; static 8-slot evt pool; BLE suspend while ESP-NOW CNC open; ESP-NOW v2 1470B (S3 mirrors).

*Updated: 2026-06-08 (ESP-NOW submenu E2E)*

**ESP-NOW submenu (2026-06-08):** `wireless_shim_espnow.c` + `espnow_transport_shim.c` + `ui_settings_wireless.c` + C6 `espnow_handler.c`. **Done:** MAC parse/validate; bridge peer NVS (`en_mac`); C6 SDIO probe (`ESPNOW_CMD_PROBE` / `EVT_DISCOVER`); live scan list (1 s timer, change-gated traffic/bridge labels); tap-to-set bridge peer; MAC modal + `modulus_ui_apply_keyboard_theme`; channel (`en_chan`) + PMK encrypt (`en_enc`, fixed `MODULUS_ENOW_PMK`); remove/clear peers; `modulus_wireless_espnow_transport_reinit` on NVS/radio change; disable deinits C6 stack + stops CNC transport; error beep on bad MAC/scan fail. **S3 bridge (2026-06-16):** in-repo `firmware/s3-bridge/` replies `MOD_ACK` to C6 `MOD_PROBE`; protocol ref in `espnow_handler.c`. **Field TODO:** two-device CNC transport TX/RX with grblHAL over bridge; confirm C6 STA MAC matches bridge NVS `tab5_mac`; encrypted peer must share PMK (incompatible with S3 plain bridge); C6 **must reflash** for probe/discover (`scripts/build_tab5_c6_modulus.ps1` or dual flash) — P4-only flash gets passive RECV discovery only. **ABI 14** unchanged.

*Updated: 2026-06-08 (WiFi submenu E2E)*

**WiFi submenu (2026-06-08):** Full audit + root-cause fixes on `wireless_shim.c` + `ui_settings_wireless.c`. **Done:** radio enable/disable + NVS restore; async scan w/ RSSI+auth; WPA2 connect modal (keyboard theme refresh preserved); open-network auto-connect; disconnect w/o auto-reconnect storm; forget saved network; saved-network page; IP display (`GOT_IP`); connecting state; disconnect-reason UI (`Auth failed` etc.); scan blocked while connecting; scan-complete rebuild no longer destroys connect modal (`wl_timer_stop_core` vs full stop). **TODO (field):** STA connect + IP on Tab5 COM5; enterprise WPA2-Enterprise; WPA3-only APs; static IP/DNS (`wf_dhcp` NVS key exists, UI coming-soon); multi-SSID profile list (single `wf_ssid` slot today). **ABI 14** unchanged. `zig build test` + `tab5-lib` + `idf.py build` PASS; P4 **0x2c6da0** (7% factory free); ELF `8ea0396f185468ef0468841c5a589284c57d94bcf1a8c7deb3828493bcb68223`; COM5 flash pending user.

*Updated: 2026-06-08 (LVGL memory audit)*

**LVGL memory policy (Tab5 MIPI-DSI, 2026-06-08):**

| Pool | Allocator | Caps / config | Size (this build) |
|------|-----------|---------------|-------------------|
| Widgets, layers, `lv_draw_buf_create` | `CONFIG_LV_USE_CLIB_MALLOC` → C heap | `CONFIG_SPIRAM_USE_MALLOC=y`; allocs >4 KiB → PSRAM | Unbounded PSRAM (32 MB) |
| Partial flush draw buffers | `esp_lvgl_port` `heap_caps_aligned_alloc` | `MALLOC_CAP_DMA \| MALLOC_CAP_SPIRAM` (`buff_dma`+`buff_spiram`) — ESP32-P4 supports DMA-from-PSRAM for DSI | 360 lines × 1280 × RGB565 × double ≈ **1800 KiB** PSRAM |
| LVGL task stack | `lvgl_port_init` | `MALLOC_CAP_INTERNAL` (16 KiB in `display_shim`) | Internal |
| Static assets (fonts, Phosphor ROM) | Linker / flash | — | Factory partition |

- **NOT** `CONFIG_LV_USE_BUILTIN_MALLOC` (64 KiB TLSF pool → `lv_tlsf_malloc` WDT under sw_rotate).
- **NOT** SPI/QSPI clock tweaks — Tab5 panel is MIPI-DSI (`BSP_LCD_MIPI_DSI_LANE_BITRATE_MBPS` in BSP), not SPI.
- Dashboard data timer: **33 / 40 / 50 ms** (NVS `refr_hz`); minimum **33 ms** — never 16 ms. `CONFIG_LV_DEF_REFR_PERIOD=33`.
- Settings scrim: **opaque** (`LV_OPA_COVER`) + dashboard refresh paused; power/quick may stay translucent with pause.
- Settings tabs: **lazy-build + hide/show** per tab panel (no `lv_obj_clean` on tab switch); tab timers pause/resume on switch/hide.
- Soak: idle dashboard **≥55 s** on COM5 before blaming overlay code.

*Updated: 2026-06-08 (MD3 compliance pass)*

**MD3 compliance R1+R2 complete (2026-06-08):** Added `surface_container_lowest`/`highest`, `primary_container`/`on_*`, `tertiary`/`on_tertiary`, `MOD_UI_STATE_LAYER_PRESSED` (12% press overlay via LVGL `LV_STATE_PRESSED` — no per-tick writes). Swept all `ui_*.c`: magic radii → `MOD_UI_SHAPE_*`, direct `lv_font_montserrat_*` → `MOD_UI_FONT_*` roles, modal close targets 48px, nav rail `surface_container_lowest`, elevated modals `surface_container_highest`, tonal chips/dropdowns `primary_container` pairing. Icons frozen. ABI **14** unchanged. Sheet slide anim skipped (WDT/compositing risk). `zig build test` + `tab5-lib` + `idf.py build` PASS; COM5 flash PASS; ELF `3c43ad9b…fc37fab7`; factory 3 MB **12.1%** free.

*Updated: 2026-06-07 (Architecture audit)*

**Architecture audit (2026-06-07):** Folder map verified — `src/modulus/` DAG (core→cnc/hal→runtime→firmware/ui); `firmware/tab5/components/modulus_zig/` **~102** `.c` all in CMake (no orphans; grew via 2026-07 UI/wireless splits); **P1 fix:** duplicate `tab5_pi4ioe.c` in CMakeLists removed; **partition trim:** dropped unused `MONTSERRAT_28` (sole use Power tab hero → `_24`) **−37,312 B** (`0x2a6b50`→`0x29d990`, **87.2%** factory, **12.8%** free); oversized files noted (`ui_settings_tabs_extra.c` 1047L, `wireless_shim.c` 613L) — **split done** (2026-07 wireless/status_bar/power_menu modules). C6 Zig scaffold (`src/modulus/main_c6.zig`, `firmware/tab5-c6/`) intentional, not P4 orphans. ABI was **14** then; current **18**. Builds + COM5 flash PASS; ELF `409c40d5…7d24075`.

**Full system audit (2026-06-07):** P0/P1 pass — no new code fixes required. **P0:** dashboard/settings/quick/power overlays change-gated; refresh timer pauses under scrims; settings tab timers (CNC/wireless/power/storage/system) stop on tab switch + overlay hide; Core 1 `systemTick` heap-free (64 KB boot arena only); `CONFIG_LV_USE_CLIB_MALLOC` + PSRAM; no parent-group opa on live dashboard. **P1:** Zig `device_runtime` boot/driver/transport/ext_encoder poll wired; shims (wireless, battery INA226, audio, power PMIC, security PIN) OK; `modulus_cnc_status_t` ↔ Zig `CncStatus` ABI **14** match; factory reset = `modulus` namespace erase only. **P2:** no causal-path dead code worth surgical trim this session. **P3 → TODO:** partition **88.4%** used (`0x2a6b50`, **11.6%** free — trim Montserrat tiers / Phosphor ROM / boot MP3 before new assets); BLE bond list; Zigbee/Thread QR wizards; OTA host; i18n; USB HID/Gamepad transport; WiFi STA + RS-485 field soak; BMI270 cold-wake; security idle-timeout (C++ `pin_tmo=0` immediate). C++ spot-check: `status_bar.cpp` parity OK (change-gate pattern matches); gaps unchanged (USB_HID dispatcher, `cnc_sim`, BMI270 disabled in ref). Builds: `zig build test` + `tab5-lib` + `idf.py build` PASS; P4 ELF `ed6fa02b…673bb1`; COM5 flash PASS (image already on device — verify OK).

**Battery INA226 (2026-06-07):** `battery_shim.c` bus voltage used `(raw>>3)*1.25mV` (8× low → 1.04V, N/A, no charge rate); fixed to match C++ `ina226.cpp` (`raw*1.25mV`), proper `calibrate(5mΩ,8.192A)`, power reg read, display current negated (charging +). ELF `ed6fa02b…673bb1`; COM5 flash OK.

**Status bar (2026-06-07):** Full audit vs C++ `status_bar.cpp` — all fields change-gated; added DOOR/CHECK/SLEEP/TOOL states + door→hold pill; feed+units single gate; 12h clock compact; MPG label static "MPG" (icon+colors only); batt pct recolors with icon; FEED caption; `invalidate`/`theme_refresh` bust full cache. **ABI 14** unchanged. ELF `84b82d1b…fa784d`; factory 3 MB **12%** free. Out-of-scope: wireless icon in bar (C++ has none), i18n state strings.

**CNC & Wireless tabs (2026-06-07):** CNC tab — C++ session hero (`Transport off`/`Starting…`/Connected), 1 s change-gated timer, serial modal baud/parity → `xport_maybe_reinit`, disconnect sets `cnc_conn=255` + `cmd_reset`; new `modulus_zig_active_transport()`. Wireless — Wi-Fi scan list rebuild on `SCAN_DONE`, tab-leave timer stop, ESP-NOW `en_chan`/`en_enc`/`en_mac` → transport reinit when `cnc_conn=0`. P4 flash COM5 OK; ELF `ec8192ee…b57de`; factory 3 MB **12%** free. Out-of-scope: protocol picker, USB HID/Gamepad transports, Zigbee/Thread QR wizards, BLE scan results list, Wi-Fi IP details page.

**ExtEncoder / MPG (2026-06-07):** Port A I2C0 @ **0x59** via `ext_encoder_shim.c`; Zig `ext_encoder.zig` poll on Core 1 sys_task reads count, applies NVS `cnc_encdiv` + `cnc_mpgpol`, feeds `cmdJog`/`cmdJogCancel` when status-bar MPG active. Dashboard tab: encdiv slider, per-axis inversion toggles, handwheel reference. **ABI epoch 14** unchanged. See `docs/hardware/tab5/ext-encoder.md`.

**Power rails NVS default (2026-06-07):** `ext5v` missing-key default was **0** in `power_shim.c` + Power tab UI — `modulus_power_init` turned EXT5V off after PI4IOE boot-high (Port A encoder dead on fresh NVS); fixed to **1** (C++ / `battery.zig` parity: ext5v on, usb5v off, chg_en on).

**Security tab (2026-06-07):** PIN modal errors+audio+digits-only; clear confirms+disables `pin_boot`/`pin_slp`; hero lock status; policy rows disabled without PIN; `Never` clears `pin_slp`; enabling wake lock auto-sets `pin_tmo=65535`. C++ idle timeout (0=immediate) still out-of-scope (`coming soon` row).

**SDIO verify (retry):** 2026-06-07 - `build_tab5_c6_modulus.ps1` build OK (`network_adapter` 2.11.4 `0x1817a0`); **COM6 flash PASS** (default baud, hash verified); COM6 UART monitor **no text** (Tab5 assembled / console not on COM6); P4 `ea73b3d6` skip reflash; COM5 cold boot **PASS** - `WLAN_PWR_EN noted`, `Card init success`, `Wireless ready`, `WiFi STA started`, **no** first-attempt `0x107` (GPIO15 reset log only).

**SDIO root-cause (2026-06-07):** P4-only flash + **stale/missing** C6 slave → `sdmmc_init_ocr` **0x107** loop; checksum mismatch = wrong/stale ELF (backtrace `Modulus Firmware/` path); GPIO15 conflict = **symptom** of esp_hosted transport retry (not shim double-init — `wireless_shim.c` PI4IOE only). Fixes: `flash_tab5.ps1` now runs `patch_tab5_idf6_deps.ps1` (was skipped — esp_hosted 2.11.4 RST hold + GPIO retry); patch targets `port_esp_hosted_host_os.c` (`gpio_reset_pin` before reconfig); `scripts/flash_tab5_dual.ps1` for **conditional** COM6→COM5 when C6/esp_hosted stale or SDIO fails. P4 ELF SHA256 post-GPIO-patch rebuild @ `0x2a2080` (run `Get-FileHash build/modulus_tab5.elf` before flash).

**Flash policy (Tab5 + S3 + NanoH2):** **NanoH2** — flash `firmware/nanoh2` when Zigbee hub / UART framing changes (USB download: hold BUTTON). **S3 bridge** — `scripts/build_s3_bridge.ps1` on **COM8** when bridge firmware or ESP-NOW field pairing changes. **Default `flash_tab5.ps1` (COM5 P4 only)** — UI/Zig/P4 app when C6 already matching **2.11.4** + `Wireless ready` and NanoH2 already flashed. **`flash_tab5_dual.ps1` (COM6→COM5) only when:** C6 slave stale/missing/wrong esp_hosted; SDIO **0x107**; first-time C6 install; ESP-NOW/Wi-Fi/hosted slave changes. **Do not** pass `-ZigbeeExclusive` (DEPRECATED 2026-07-19 — Zigbee is on NanoH2).

## C6 slave — canonical build & fix catalog (MUST read)

**Stay C.** Do not port C6 to Zig. Phase 8c: esp_hosted **2.11.4** SDIO `network_adapter` + injected Modulus handlers.

**2026-07-19 policy shift:** Zigbee **does not run on C6**. Product Zigbee = **NanoH2** UART hub. C6 `zigbee_handler.c` is a fail-stub; `hosted/sdkconfig.defaults.zigbee` is deprecated historical marker. Catalog rows below about PATH C / `-ZigbeeExclusive` / zb_storage on C6 are **historical** (pre-NanoH2) — keep for field triage of old flashes only.

### Canonical workflow (never bypass)

| Rule | Detail |
|------|--------|
| **Edit source here** | `firmware/tab5-c6/main/` (handlers), `firmware/tab5-c6/components/modulus_zig_c6/`, `firmware/tab5-c6/hosted/` (sdkconfig defaults, partition CSV) |
| **Never edit mirror** | `C:\modulus_tab5_c6_build\slave` is robocopied from `firmware/tab5/managed_components/espressif__esp_hosted/slave` + script injection — changes there are lost on next build |
| **Build / flash** | `.\scripts\build_tab5_c6_modulus.ps1 -Action build` then `-Action flash -Port COM6` — **no** `-ZigbeeExclusive` |
| **Zigbee firmware** | Edit/flash **`firmware/nanoh2/`** — not C6 |
| **Dual flash order** | C6 (COM6) **then** P4 (COM5); power-cycle Tab5 after both; NanoH2 independent USB flash |
| **Rollback (hosted-only)** | `.\scripts\build_tab5_c6.ps1` — no Modulus Zig/handlers |
| **NOT production** | `-ZigOnly` (no SDIO Wi-Fi / not `network_adapter`); **`-ZigbeeExclusive`** (DEPRECATED — reintroduces ESP-NOW coex fail) |

### What `-ZigbeeExclusive` did (DEPRECATED 2026-07-19)

Historical C6 image that put ZBOSS on the **shared** C6 radio (ESP-NOW dropped when Zigbee active). **Do not use.** Zigbee product path = NanoH2. File `hosted/sdkconfig.defaults.zigbee` retained as warning marker only.

<details><summary>Historical steps (do not rebuild)</summary>

1. **`SDKCONFIG_DEFAULTS`** added `hosted/sdkconfig.defaults.zigbee` → OT off, ZB on, ZCZR, coex
2. **`partitions_zigbee.csv`** → zb_storage + zb_fct on C6
3. Stale sdkconfig purge for partitions_zigbee
4. `esp-zigbee-lib` + `esp-zboss-lib` ~1.6.0 in C6 `idf_component.yml` (now **removed**)
5. Hub ran in `main/zigbee_handler.c` SDIO RPC (now stub)

</details>

### Script injection pipeline (every build)

`build_tab5_c6_modulus.ps1` → `Ensure-EspHostedSlave` + `Inject-ModulusIntoHostedMirror`:

| Step | Fix / purpose |
|------|----------------|
| Robocopy esp_hosted slave → `C:\modulus_tab5_c6_build\slave` | Space-free path; exclude stale `build/`/`sdkconfig` |
| Patch `sdio_slave_api.c` | IDF 6: `#include "hal/sdio_slave_periph.h"` (was `soc/…`) |
| Copy `modulus_zig_c6` + `modulus_c6_hosted_hook.h` + `sdkconfig.defaults.modulus` | Phase 8c Zig runtime on separate FreeRTOS task after hosted init |
| Patch top `CMakeLists.txt` | Add `modulus_zig_c6` component |
| Patch `esp_hosted_coprocessor.c` | `modulus_c6_hosted_after_init()` after `esp_hosted_coprocessor_init()` |
| Copy + wire **`espnow_handler.c`** | Upstream slave had **no** `ESP_ESPNOW_IF` — P4 `ESPNOW_CMD_*` dropped as "unknown type 8", probe/CNC timed out |
| Copy + wire **`zigbee_handler.c`** + **`thread_handler.c`** | Upstream had **no** `ESP_ZIGBEE_IF` / `ESP_THREAD_IF` — permit-join / hub-start RPCs dropped on slave |
| Patch `esp_hosted_interface.h` | Add `ESP_ESPNOW_IF`, `ESP_ZIGBEE_IF`, `ESP_THREAD_IF` enum values (host-aligned) |
| Patch `main/CMakeLists.txt` | Register handler `.c` sources |
| Patch dispatch in `esp_hosted_coprocessor.c` | Route SDIO packets to `espnow_process_host_cmd` / `zigbee_process_host_cmd` / `thread_process_host_cmd` |

### C6 issue → fix catalog (field-verified or code-audited)

| # | Symptom / issue | Root cause | Fix (where) |
|---|-----------------|------------|-------------|
| 1 | SDIO `sdmmc_card_init` **0x107**, `Wireless not ready` | P4-only flash; C6 slave missing/stale/wrong esp_hosted version | Dual flash COM6→COM5; C6 must be 2.11.4 modulus image via `build_tab5_c6_modulus.ps1` |
| 2 | Same 0x107 after "fix" timing patches | **GPIO15 held LOW** — `patch_tab5_idf6_deps.ps1` stripped final reset ACTIVE write; C6 `EN` stuck in reset | Restore final `H_RESET_VAL_ACTIVE` in esp_hosted `sdio_drv.c`; **never re-add reset-stripping patch** (P4 side) |
| 3 | `gpio: conflict GPIO[15]` on transport retry | Symptom of esp_hosted SDIO retry loop, not double-init in `wireless_shim.c` | Fix C6 enumeration (rows 1–2); PI4IOE-only WLAN path on P4 |
| 4 | `RX counter resync v5: post-flush align …` → transport fail → ESP-NOW dead | SDIO v5 stale counter after flush | Rebuild + dual flash; poll until `PACKET_LEN==0` (esp_hosted) |
| 5 | ESP-NOW unicast **send fail reason=0x01**; probe no reply | Host `esp_wifi_get_channel()` RPC contended with ESP-NOW on SDIO; C6 disconnected-STA channel drift; `peer.channel=0` | **C6** `espnow_lock_radio_channel()` local only (`espnow_handler.c`); explicit `peer.channel` from host byte; host `modulus_wireless_espnow_align_channel()` **no-op** |
| 6 | ESP-NOW still fails on esp_hosted 2.11.4 | `CONFIG_ESP_WIFI_STA_DISCONNECTED_PM_ENABLE=y` sleeps radio between ops for unassociated STA | **`hosted/sdkconfig.defaults.modulus`:** `CONFIG_ESP_WIFI_STA_DISCONNECTED_PM_ENABLE=n` + `CONFIG_WIFI_RMT_STA_DISCONNECTED_PM_ENABLE=n` |
| 7 | ESP-NOW callback stolen / double-init | `modulus_c6_espnow.c` autonomous path vs SDIO handler — one global recv/send callback | **`CONFIG_MODULUS_C6_ESPNOW=n`** in modulus defaults; SDIO `espnow_handler.c` owns esp_now |
| 8 | P4 "unknown type 8" / ESP-NOW timeout | Upstream esp_hosted slave lacks ESP-NOW SDIO handler | Script injects `espnow_handler.c` + dispatch (row in pipeline table) |
| 9 | Zigbee permit-join / hub RPC timeout | No `ESP_ZIGBEE_IF` handler on slave | Script injects `zigbee_handler.c` + dispatch |
| 10 | Thread RPC timeout | No `ESP_THREAD_IF` handler | Script injects `thread_handler.c` + dispatch |
| 11 | Zigbee pairing empty; `esp_zb_start` fail | Default partition table lacks `zb_storage`/`zb_fct` | **`-ZigbeeExclusive`** + `partitions_zigbee.csv`; stale sdkconfig delete |
| 12 | Thread + Zigbee both needed on one radio | ESP32-C6 has **one** 802.15.4 MAC | **Mutually exclusive:** `-ZigbeeExclusive` (ZBOSS) **or** default Thread MTD — not both |
| 13 | Hub joinable 24/7 without user action | BDB steering auto-opens 180 s permit window | `s_user_permit` gate in `zigbee_handler.c` — close unrequested permit-join |
| 14 | Hub init wedge silent on P4 | ZB task crash aborted whole coprocessor | No `ESP_ERROR_CHECK` on hub path; `ZIGBEE_EVT_FAIL` with reason codes to host |
| 15 | `esp_zb_lock` before stack ready | Commands between task create and `SKIP_STARTUP` | `s_stack_ready` volatile gate; permit/onoff/level require formed network |
| 16 | ZB task stack overflow at formation | 5120 B marginal for ZC + logging | `HUB_ZB_TASK_STACK` **8192** in `zigbee_handler.c` |
| 17 | `espnow_handler.c` compile error (2026-06-20) | `s_bcast_mac` used before declare in probe cleanup | Moved statics to file top (probe path later simplified — P4 uses `ESPNOW_CMD_SEND` + `MOD_PROBE` via `modulus_espnow_stack_probe()`, not `ESPNOW_CMD_PROBE`) |
| 18 | CNC ESP-NOW transport `ESP_ERR_ESPNOW_NOT_FOUND` (0x69) | `s_peer` left zero when bridge peer pre-added via settings UI | P4 `espnow_transport_shim.c`: always resolve NVS peer MAC into `s_peer` before open |
| 19 | RPC **12298** / `ESP_ERR_WIFI_SSID` on cold boot | `esp_wifi_start` at boot with empty SSID | P4 defer `esp_wifi_start` until NVS Wi-Fi/ESP-NOW enabled (not C6) |
| 20 | Zigbee raw promiscuous scan on P4 | Thread holds radio callbacks | Thread off in ZigbeeExclusive build; or `thread_process_host_cmd` DISABLE before Zigbee raw (PATH B) |

### C6 source files (what each owns)

| File | Role |
|------|------|
| `main/espnow_handler.c` | SDIO `ESP_ESPNOW_IF`: init/deinit, peer add/del, send, PMK; local channel lock; events to P4 — **C6 is ESP-NOW-only for 802.15.4-adjacent RF** |
| `main/zigbee_handler.c` | **Stub (2026-07-19):** SDIO Zigbee → `EVT_FAIL` 0x30; live hub = `firmware/nanoh2/main/zigbee_hub.c` |
| `main/thread_handler.c` | SDIO `ESP_THREAD_IF`: OpenThread FTD when compiled; stub FAIL when Thread off |
| `components/modulus_zig_c6/modulus_c6_hosted_hook.c` | After hosted init: BLE init, ESP-NOW policy hook, Thread/Zigbee policy init, Zig runtime task |
| `components/modulus_zig_c6/modulus_c6_zigbee.c` | Logs "Zigbee not on C6"; no ZBOSS link |
| `hosted/sdkconfig.defaults.modulus` | SDIO queue depth, BLE, Thread default, ESP-NOW PM fix, `CONFIG_MODULUS_C6_ESPNOW=n` |
| `hosted/sdkconfig.defaults.zigbee` | **DEPRECATED** — do not use (NanoH2 owns Zigbee) |
| `hosted/partitions_zigbee.csv` | Historical C6 ZBOSS NVRAM — unused on product C6 image |

### Verify after C6 flash

- COM6 (if UART exposed): `Slave FW 2.11.4`, `Transport used :: SDIO only`
- COM5 cold boot: `WLAN_PWR_EN`, `Card init success`, `wireless_shim: Wireless ready` — **no** persistent 0x107
- ZigbeeExclusive: early log `ZBOSS HUB PATH compiled`; after P4 Settings → Zigbee → start hub: `Formed network pan 0x….`
- ESP-NOW CNC: no `RPC_Req [0x12e]` channel flood; bridge peer `ch1`; send OK not reason 0x01

**Flash verify (I2C0 fix):** 2026-06-07 COM5+COM6 — Port A **I2C0** (was I2C1=BSP collision); mbus map OK, INA226/PI4IOE clean; SDIO 0x107 persists → `esp_wifi_init` ESP_FAIL until C6 slave enumerates (power-cycle Tab5).

Short notes for **this repo** (Zig conversion workspace). Pipeline tools (CBM, Token Savior, Ruflo, Evolver) are global under `~/.cursor/`.

## Project

- **Goal:** Port **Modulus OS** (M5Stack Tab5 CNC MPG pendant) from C++/ESP-IDF to **Zig 0.16+**, preserving behavior, NVS schema, and dual-core architecture.
- **Reference firmware (read-only source of truth):** `../Modulus Convert to ZIG core/`
  - P4 app: `Modulus Firmware/` — ESP-IDF 5.5.3, project `modulus`, ~138 files under `main/`
  - C6 slave: `Modulus Firmware C6/slave/` — ESP-Hosted 1.4.0 `network_adapter` — **stay C**, do not port
  - S3 bridge: **`firmware/s3-bridge/`** (canonical; archive `ESP32S3_ESPNOW_UART_Bridge  (Works)` in core tree)
- **This repo layout (target):**
  - `build.zig`, `build.zig.zon` — host tests + CI leak gate
  - `src/modulus/core/` — `system_events`, `event_bus`, `settings_store`, `boot`, `str_util`
  - `src/modulus/testing/leak_guard.zig` — `LeakGuard`, `withNoLeaks`
  - `src/modulus/tab5_root.zig` — freestanding tab5-lib root (`std_options`, re-exports `root.zig`)
  - `src/modulus/core/` — event bus, settings, boot (Phase 1)
  - `src/modulus/cnc/` — config, state, grblhal engine/parser/cmd, driver (Phase 2)
  - `src/modulus/hal/transport/` — dispatcher, serial, stream + `idf_stream.zig` device backends (Phase 3)
  - `src/modulus/hal/platform/` — display, power, battery, i2c_coex, ext_encoder (Phase 4)
  - `src/modulus/hal/wireless/` — SDIO pins, mock ESP-Hosted, wireless API (Phase 4)
  - `src/modulus/runtime/` — `Runtime`, `HalHooks` thunks, wired boot (post-Phase 4)
  - `src/modulus/firmware/` — `abi.zig`, `device_runtime.zig`, `host_tests.zig`; C ABI + 64KB arena runtime
  - `src/modulus/core/idf_nvs.zig` — ESP-IDF NVS via `firmware/tab5/components/modulus_zig/nvs_shim.c`
  - `src/modulus/hal/transport/idf_serial.zig` — RS-485 UART via `serial_shim.c` (UART1 TX20/RX21/DE34)
  - `src/modulus/hal/platform/idf_display.zig` — MIPI-DSI 1280×720 via `display_shim.c` (m5stack_tab5 BSP + LVGL)
  - `build.zig` — `-Ddevice-nvs` via `build_options` (host=false, tab5=true)
  - `firmware/tab5/` — ESP-IDF 6.0 scaffold (P4, `m5stack_tab5` BSP, links `libmodulus_zig.a`)
  - `firmware/nanoh2/` — **NanoH2 Zigbee ZBOSS hub** (ESP32-H2FH4S; UART to P4; not on Tab5 PCB)
  - `firmware/s3-bridge/` — ESP32-S3 ESP-NOW ↔ UART grblHAL bridge (field hardware)
  - `scripts/build_s3_bridge.ps1` — `idf.py build` / flash / monitor for S3 bridge
  - `scripts/build_tab5.ps1` — ASCII check + `zig build tab5-lib` + optional `idf.py build`
  - `scripts/check_ui_ascii.ps1` — Montserrat-safe ASCII gate on `modulus_zig/ui_*.c`
  - `scripts/flash_tab5.ps1` — **default** P4 flash (COM5); patch + rebuild + `idf.py flash`
  - `scripts/flash_tab5_dual.ps1` — **conditional** COM6 C6 then COM5 P4 (C6/esp_hosted stale or SDIO fail only; **no** ZigbeeExclusive)
  - `.github/workflows/tab5-idf.yml` — CI: `zig build test`, `tab5-lib`, `idf.py build`
  - `src/modulus/ui/` — manager, idf_ui bridge, boot/dashboard/pin_lock (Phase 5)
  - `firmware/tab5/components/modulus_zig/ui_*.c` — LVGL M3 dark/light screens (C shim; NVS `darkmode`)
  - `.agents/skills/` — zig-core, zig-build, **zig-port**
  - `.cursor/rules/` — modulus-zig, **zig-pitfalls**, **lvgl-tab5-ui-pitfalls**, tab5, idf6

## Layer boundaries (repo folders)

| Path | Role | Links to |
|------|------|----------|
| `src/modulus/core/` | Events, NVS keys, boot order | `firmware/…/nvs_shim.c`, `event_shim.c` |
| `src/modulus/cnc/` | Multi-protocol client (grblHAL / LinuxCNC / Mach3) via `protocol_engine.zig` | `modulus_zig.h` CNC cmd exports (ABI **18**) |
| `src/modulus/hal/transport/` | Serial/WS/Telnet/I2C/CAN/ESP-NOW/BLE dispatch | `*_transport_shim.c`, `serial_shim.c` |
| `src/modulus/hal/platform/` | Display, power, battery, audio, RTC, storage, IMU | `display_shim.c`, `battery_shim.c`, … |
| `src/modulus/hal/wireless/` | SDIO pins, Wi-Fi API (hosted) | `wireless_shim.c`, `c6_sdio_host.c` |
| `src/modulus/runtime/` + `firmware/` | `Runtime`, `device_runtime`, Core 1 task | `libmodulus_zig_core.a` via CMake |
| `src/modulus/ui/` | Host UI manager (device: C `ui_*.c`) | `ui_shim.c` ↔ Zig status/cmd ABI |
| `firmware/tab5/components/modulus_zig/` | C shims + LVGL screens | IDF component; one `tab5-lib` Zig archive |
| `firmware/tab5-c6/` | C6 slave Wi-Fi/ESP-NOW/BLE (stay C; Zigbee stub) | Separate flash (`flash_tab5_dual.ps1`) |
| `firmware/nanoh2/` | NanoH2 Zigbee ZBOSS hub (ESP32-H2) | UART to P4; USB flash (hold BUTTON) |
| `scripts/` | Build/flash/patch/icon gen | `build_tab5.ps1`, `flash_tab5.ps1`, `patch_tab5_idf6_deps.ps1` |

**Rule:** Zig owns logic + ABI; C owns BSP/LVGL/IDF drivers. No circular `build.zig` imports; no heap in Core 1 hot path.

## Architecture (from C++ reference — preserve in Zig)

- **Product:** grblHAL **client** only (not on-device motion planner). Default transport: **RS485** (`cnc_conn` = 4).
- **Sovereign core:** Core 0 = LVGL/event bus; Core 1 = `system_task` ~100 Hz (`cnc_driver::poll`, `hal_dsp::process`).
- **Wireless:** P4 ↔ C6 **SDIO2** (CLK12 CMD13 D0–11 D1–10 D2–9 D3–8 RST15) for Wi-Fi/BLE/ESP-NOW. Field CNC over **ESP-NOW:** C6 ↔ **S3 bridge** ↔ UART ↔ grblHAL. **Zigbee:** P4 ↔ **NanoH2** UART2 (GPIO6/7 ↔ Grove) ↔ ZBOSS (dedicated 802.15.4) — **not** on C6. Hosted custom if_types still ESPNOW=8, ZIGBEE=9 (stub), THREAD=10.
- **NVS:** namespace `"modulus"`, ~90 keys, max key len 15. Do not rename during port.
- **Boot order:** event_bus → display → settings → HAL chain → cnc_driver → hal_transport → hal_wireless → ext_encoder → UI → Core1 task.
- **Gaps in C++:** BMI270 disabled, OTA stub, USB_HID/Gamepad not in transport dispatcher, `cnc_sim` unused.

## Zig port plan (skill `zig-port`)


| Phase | Layer                                                                                  | Status         |
| ----- | -------------------------------------------------------------------------------------- | -------------- |
| 0     | Scaffold `build.zig` + `src/modulus/` + leak CI                                        | **done**       |
| 1     | `core/` (event_bus, settings_store, boot)                                              | **done**       |
| 2     | `cnc/` + grblhal + **linuxcnc** + **mach3** via `protocol_engine.zig` + driver       | **done**       |
| 3     | HAL transports (serial, ws, telnet, espnow, i2c, can, ble stub)                         | **done**       |
| 4     | HAL platform + wireless (host mocks; device `@cImport` later)                          | **done**       |
| 4b    | `runtime/` wired boot + `firmware/tab5` IDF scaffold + `tab5-lib`                      | **done**       |
| 4c    | Device NVS shim + `modulus_zig_boot` → full `Runtime`                                  | **done**       |
| 4d    | Device RS-485 UART shim (`serial_shim.c` + `idf_serial.zig`)                           | **done**       |
| 4e    | Core 0 `evt_dispatch` + `event_shim.c` cross-core queue                                | **done**       |
| 4f    | Tab5 display BSP (`display_shim.c` + `idf_display.zig`)                                | **done**       |
| 4g    | LVGL activity timer (dim/sleep) + deferred CNC connect (11 s)                          | **done**       |
| 5     | UI / LVGL screens (boot → dashboard, PIN lock, DRO refresh)                            | **done** (MVP) |
| 5b    | Dashboard ops — status bar, jog selector, action buttons, CNC cmd ABI                  | **done**       |
| 5c    | Override sliders + settings overlay (CNC/Display/Power/System tabs)                    | **done**       |
| 5d    | DRO HOME/ZERO axis cards + status bar WCS/tool/feed/spindle/clock                      | **done**       |
| 5e    | Quick settings sheet + power menu overlay                                              | **done**       |
| 5f    | Settings 10-tab parity (MVP stubs for audio/wireless/storage)                          | **done**       |
| 5h    | Settings overlay C++/photo parity — top header, full sidebar, M3 rows, LV_OPA_60 scrim | **done**       |


**Baseline:** ABI **18**, P4 app **0x2aa4c0** (~2.67 MB, **~53% of 5 MB factory**; factory bumped 3 MB→5 MB 2026-06-14), C6 workspace **0x192590** / last field flash **0x182440** (2.11.4); Phases 0–5h + C6 wireless + alt transports + **LinuxCNC/Mach3 engines** done; **175** host tests; PSRAM LVGL heap + hosted link verified; tab5-lib freestanding via `tab5_root.zig`. Field verify (WiFi STA, RS-485 motion, BMI270 wake, ESP-NOW grblHAL E2E, LinuxCNC/Mach3 handshake) still open.

## TODO — Tab5 port backlog

### Done (session wins)

- Architecture audit (2026-06-07) — CMake duplicate `tab5_pi4ioe.c` removed; `MONTSERRAT_28` dropped (−37 KB); layer boundary table in MEMORY
- LVGL WDT — `CONFIG_LV_USE_CLIB_MALLOC` + PSRAM (not 64 KB builtin pool)
- Dashboard, status bar, Phosphor icons (Light/Fill pipeline)
- Power menu C++ parity (sections, confirms, busy guard) + true PMIC shutdown (`tab5_pi4ioe` PWROFF)
- Settings overlay rebuild (10 tabs, M3 rows, `LV_OPA_60` scrim) + full C++ structure — 2026-06-06
- Settings parity — transport reinit, PIN editor, wireless nav stack, transport/incr modals, NVS key fixes
- DRO axis tap fix, jog layout, dynamic cycle/hold colors; quick settings sheet + power menu overlays
- Audio HAL ES8388/ES7210 + MP3 boot/shutdown + UI touch tones; `audio_shim` write_cb fix; BSP 1.2.0 codec API
- RX8130 RTC + manual set; SNTP on WiFi GOT_IP (NTP needs C6 link)
- Factory reset NVS erase; quick buttons editor; machine name editor; zero-while-run confirm
- SD mount HAL + Storage tab live; I2C bus scanner (all/M-Bus/Port A/EXP1/EXP2)
- Battery status bar + Power tab — INA226 V/I + IP2326 CHG_STAT (PI4IOE E2.P6)
- Alt/stream transports on device — RS-485, Serial, WS, Telnet (`tcp_transport_shim.c` editors), I2C, CAN live
- C6 ESP-Hosted **2.11.4** + `build_tab5_c6_modulus.ps1`; SDIO boot anchor at WLAN_PWR (remainder wait) — PASS `0c1b58bd`
- C6 wireless — WiFi scan/connect/NVS, SNTP, settings hub; slave `espnow`/`zigbee`/`thread` handlers; **RPC 12298 fix + COM5 verify PASS** (375cbc2d, 1ece0553 — defer `esp_wifi_start`, no empty SSID on STA_START)
- BLE NimBLE scan/pair UI + **RPC/CNC transport** (swarm A; bond list partial) + Zigbee/Thread UI hubs — provision wizard still open
- `esp_wifi_remote` IDF6 stub; `tab5_pi4ioe` PMIC/rails/antenna; **PI4IOE1 (0x43) full pin map** — HP_DET P7, SPK_EN P1 (11ec0156); PI4IOE2 audit — fcb32b66
- **SDIO hosted link verified** — cold boot retry PASS (`0c1b58bd`, `375cbc2d`)
- I2C0 Port A fix (6306bed6) — mbus Port A G53/G54 on I2C0; work envelope, mbus map, i18n EN shim
- Quick settings sheet — `LV_OPA_50` scrim + `modulus_ui_pause_dashboard_refresh` (`ui_quick_settings.c`)
- PMS150G wakeup — `wakeup_shim` + RX8130 timer IRQ + BMI270 any-motion INT1→E_TRG code (swarm B; device verify open)
- Infra — `flash_tab5.ps1`, `check_ui_ascii`, `build_tab5` hook, `tab5-idf` CI
- Swarm A (7e907712) — WiFi credentials E2E code (`wireless_shim` scan/connect/NVS); BLE NimBLE RPC + CNC transport (`ble_transport_shim.c`, bond list partial); ESP-NOW dispatcher + peer editor (`espnow_transport_shim.c`); Zigbee/Thread RPC partial (no full wizard)
- Swarm B (24d5e617) — BMI270 any-motion INT1→E_TRG code (`imu_shim` + bmi2 patch); PIN lock `pin_tmo` fix; RS-485 soak checklist; PIN/deep-sleep/restart wiring retained
- Swarm C (5d8aa32d) — quick settings scrim **58 s idle WDT PASS**; COM5 flash PASS + `Wireless ready`; OTA honest stub PASS; partition headroom **WARNING** at **0x2a0ff0**
- Build fixes — BMI270 `sensor_bmi270` patch + `esp_hosted` include paths; P4 image grew to **0x2a0ff0** (87.6% used)
- **S3 ESP-NOW UART bridge in-repo (2026-06-16)** — `firmware/s3-bridge/` + `build_s3_bridge.ps1`; IDF6 driver fix; MOD_PROBE/ACK; bin **0xb2e30** build PASS
- **tab5-lib freestanding + 5 MB factory (2026-06-20)** — `tab5_root.zig`; Zig 0.16 device compile fixes; P4 **0x2a0c20** ~47% factory free; C6 **0x182440**; `espnow_handler.c` fix
- **ABI 18 + multi-protocol + UI splits (2026-07-03)** — `abi_guard` + settings-dump stack fix; LinuxCNC/Mach3 engines; ext_encoder module split; ~102 C shims; accent palette codegen; **175** host tests; P4 **0x2aa4c0** ~53% factory

### 1. Verify on device (priority)

- [x] Idle ≥55 s — quick settings scrim **58 s idle zero WDT** PASS (swarm C, P4 **0x2a0ff0**); re-check after each flash
- [x] Power menu + confirm modals (E-stop, restart, shutdown → PMIC off)
- [x] Settings — all 10 tabs open/scroll/switch; transport reinit + PIN + wireless nav
- [x] C6+P4 hosted link — `wireless_shim: Wireless ready`, `Card init success` (2.11.4; COM5 flash PASS swarm C; SDIO retry PASS `0c1b58bd`; first-attempt `0x107` without C6 flash still possible)
- [x] I2C0 Port A + mbus map + PI4IOE rails (6306bed6 / fcb32b66 audit)
- [x] Quick settings sheet — `LV_OPA_50` scrim + dashboard refresh pause/resume; **58 s idle WDT PASS** (`ui_quick_settings.c`, swarm C)
- [~] WiFi scan-connect credentials E2E — **code done** (swarm A: `wireless_shim` scan/connect/NVS + deferred `esp_wifi_start`); default NVS cold boot keeps WiFi off (no 12298); **field STA verify open** (enable radio + connect + IP)
- [~] RS-485 + real grblHAL motion/status E2E soak — **code + soak checklist done** (swarm B); **field motion verify open** (needs physical grblHAL controller)
- [~] PIN lock, deep sleep, restart — code wired + **`pin_tmo` fix done** (swarm B); `ui_pin_lock`, `power_shim` + `wakeup_shim`, power-menu confirm; **device walk verify open** on P4 **0x2a0ff0** + C6 2.11.4
- [~] Multi-cycle combined-image flash soak — **partial** (2026-06-07): 2 cycles run; cycle 1 **PASS** (COM6 flash retry, COM5, 60 s idle WDT, `Wireless ready` ELF `87970e6fa`); cycle 2 **PARTIAL** (COM6 connect fail ×2, COM5 OK, 60 s idle WDT OK, SDIO 0x107 / no wireless); settings tab walk **manual required**; P4 **0x2a1070** (87.6%), C6 **0x1817a0**
- [x] RPC/flash regression — no `rpc_rsp 12298`, no `ESP_ERR_WIFI_SSID` on default NVS cold boot (WiFi NVS off at boot)

### 2. UI / HAL still open

- [x] FAN / SINGLE STEP — grblHAL RT `0x8A` fan toggle + `0x89` single-step toggle wired in `driver.zig`/`engine.zig`/`cmd.zig`; UI: quick-btn FAN → `modulus_zig_cmd_fan_toggle`; single-step ABI export only (no dashboard tile yet); **field verify open** on real grblHAL controller
- [x] BLE NimBLE scan/pair UI (`ble_transport_shim.c` settings hub)
- [x] BLE NimBLE RPC + CNC transport — **code done** (swarm A); C6 NUS + dispatcher hook live; **bond list partial** (pair/unpair walk open)
- [x] Zigbee / Thread UI partial (radio toggle, join/leave/attach shells)
- [~] Zigbee / Thread device UI — **2026-06-08:** NVS device registry (`zb_*`/`th_*`), promiscuous Zigbee scan (raw 802.15.4 when Thread detached), install-code/manual-add modals, ON/OFF toggle (Zigbee raw TX stub; Thread cache-only). **Open:** esp-zb steering on C6 exclusive build; Thread `EVT_DEVICE_JOIN` + Matter/CoAP ON/OFF; QR operational-dataset wizard; field verify with real 802.15.4 gear
- [~] ESP-NOW CNC dispatcher + peer editor — **extended** (2026-06-08: discovery scan, MAC modal, clear/remove peers, C6 probe protocol; **2026-06-16:** S3 bridge in-repo w/ MOD_ACK); field grblHAL E2E over bridge **open**
- [ ] i18n full catalogs — EN live; DE/FR/ES/… strings not ported

### 3. Firmware gaps

- [x] OTA — System tab honest "coming-soon" stub PASS (swarm C); no P4 `ota.zig`/shim yet (deferred)
- [~] PMS150G BMI270 any-motion INT1 → E_TRG — **code done** (swarm B: `imu_shim` bmi2 any-motion + `wakeup_shim` E_TRG path + RX8130 timer IRQ); **device cold-wake verify open**
- [x] Partition headroom — factory **5 MB** (2026-06-14); app **~53% used** at **0x2aa4c0** (~47% free); prior 3 MB / 87%+ crisis resolved; still trim Phosphor dupes / boot MP3 before large new ROM
- [x] M5-Bus / HY2.0-4P — `mbus_shim` init/scan (Port A I2C0 G53/G54 + M-Bus map)
- [x] Work envelope enforcement — `envelope.zig` + driver clamp
- [x] Cold boot SDIO anchor — `MODULUS_C6_BOOT_DELAY_MS` at PI4IOE WLAN_PWR (`display_init`); `wireless_shim` waits remainder only

**Top 5 next:** (1) WiFi STA field verify (enable radio + credentials + IP), (2) RS-485 grblHAL field motion soak, (3) ESP-NOW grblHAL E2E over S3 bridge, (4) LinuxCNC/Mach3 handshake on RS-485 or WS, (5) BMI270 cold-wake + PIN/deep-sleep walk.

### Open TODO (consolidated — full audit 2026-06-07)

| Priority | Item | Notes |
|----------|------|-------|
| ~~P0-block~~ | Partition trim / bump | **Resolved** — factory **5 MB**; app **0x2aa4c0** ~53% used (~47% free) |
| P1-field | ESP-NOW grblHAL E2E over S3 bridge | S3 `firmware/s3-bridge/` + MOD_ACK; Tab5 peer MAC + ch1 + PMK off; C6 STA MAC = bridge NVS `tab5_mac`; rebuild C6 **without** ZigbeeExclusive so ESP-NOW owns radio |
| P1-field | WiFi STA E2E | Shim+UI complete (2026-06-08); field verify: scan/connect/IP/disconnect/reconnect on COM5 |
| P1-field | LinuxCNC / Mach3 handshake | Engines in `protocol_engine.zig` + NVS `cnc_proto`; field connect/status on RS-485 or WS open |
| P3 | WiFi enterprise WPA2-Enterprise | `WIFI_AUTH_WPA2_ENTERPRISE` shown in scan; connect unsupported |
| P3 | WiFi static IP/DNS | `wf_dhcp` NVS only; `esp_netif` static config not wired |
| P3 | WiFi multi-SSID profiles | Single `wf_ssid`/`wf_pass` slot; no profile list |
| P1-field | RS-485 grblHAL motion soak | Needs physical controller |
| P1-field | PIN / deep-sleep / restart walk | Code wired; device walk open |
| P1-field | BMI270 any-motion cold-wake | `imu_shim` + `wakeup_shim` code done |
| P2 | BLE bond list UI | Settings connect/pair/PIN live; multi-bond name list still NVS-backed (1 label) |
| P2-field | BLE pairing field verify | Phone/keyboard/HID device soak on Tab5 + C6 |
| P1-field | Zigbee NanoH2 E2E | Hub + UART ACK/NAK + TC permit-join + zb_devdb + zb_automation in tree; **open:** flash NanoH2 **0x96100** + P4 **0x2fe0e0**, Grove↔M5BUS, real device join + OnOff + CNC-follow soak; EXT5V on |
| P2-docs | Hackster / GIC 2026 | Draft `Modulus_Hackster_Documentation.md`; fill media/`[TBD]`; submit by **Aug 7, 2026** |
| P2 | Thread provision wizard | Product C6 Thread **off**; QR/CoAP only if Thread build re-enabled |
| P2 | USB HID / Gamepad transport | C++ not in dispatcher; settings stub |
| P2 | Security idle timeout | C++ `pin_tmo=0` immediate lock; Zig "coming soon" row |
| P3 | OTA host (`ota.zig` + shim) | System tab honest stub |
| P3 | i18n catalogs | EN only; DE/FR/ES not ported |
| P3 | Wireless icon in status bar | C++ has none; optional |
| ~~P3~~ | Split settings/wireless UI | **Done** — per-tab settings + `ui_settings_wireless_*`; `ui_settings_tabs_extra.c` gone |
| P3 | Split `wireless_shim.c` core | **1075L** (NanoH2 + hub_offline; 802154 **986L** / rpc **602L** extracted) |

**Never revert:** PSRAM LVGL heap (`CONFIG_LV_USE_CLIB_MALLOC`), change-gated LVGL updates, build-before-flash.

**Hybrid OK during port:** Zig core+cnc linked with C++ hal+ui via C ABI.

## Zig 0.16 rules

- Host: `pub fn main(init: std.process.Init) !void`; thread `init.gpa`, `init.io`.
- `ArrayList`: `.empty`, `append(allocator, …)`, `deinit(allocator)`.
- Prefer `addTranslateC` over `@cImport`; pin `minimum_zig_version = "0.16.0"`.
- **Leak policy:** all host tests use `std.testing.allocator` or `modulus.testing.LeakGuard`; `zig build test` + `.github/workflows/zig-test.yml` fail on unfreed allocs. 0.16: `DebugAllocator` not GPA.
- Pitfalls: see `.cursor/rules/zig-pitfalls.mdc` (packed struct ReleaseSafe, bool FFI, incremental /tmp, fetch fingerprints).
- Upstream issues: [codeberg.org/ziglang/zig](https://codeberg.org/ziglang/zig) (new ≥30000).

### Zig 0.16.0 release applicability (2026-06-17)

Ref: [0.16.0 release notes](https://ziglang.org/download/0.16.0/release-notes.html)

| Area | Status | Notes |
|------|--------|-------|
| Juicy Main + `init.gpa` | **done** | `host_main.zig` |
| `init.io` on host `Runtime` | **done** | `hostIo()`, exports → `core/host_io.zig` |
| `core/host_io.zig` | **done** | file + entropy helpers; `settings_dump.writeHostExport` |
| `core/host_diagnostics.zig` | **done** | snapshot + text report; `Runtime.exportHostDiagnostics` |
| Host OTA staging manifest | **done** | `ota.writeStagingManifest`; `Runtime.exportOtaStagingManifest` |
| `modulus-host` CLI | **done** | `--export-diagnostics`, `--export-ota-staging`, `--help` |
| Parser fuzz corpus | **done** | `parser_fuzz_corpus.zig` (40+ lines from tests + malformed edge cases) |
| Zig patch pin | **done** | `.github/zig-version` = `0.16.0`; verified in `zig-test` + `tab5-idf` CI |
| `std.testing.io` in host tests | **done** | runtime tests + parser fuzz RNG |
| `@trunc` / `@round` (not `@intFromFloat`) | **done** | battery, bracket, envelope, driver_commands |
| `std.mem.cutPrefix` (0.16 mem API) | **done** | `bracket.zig` tag stripping |
| Parser `std.testing.fuzz` corpus | **done** | `parser_fuzz.zig`; CI runs corpus on Windows |
| `zig build test` per-test timeout | **done** | CI: `zig build test -- --test-timeout 60s` |
| `addTranslateC` for IDF shims | **done** | `modulus_shims_bundle.h` + Tab5 `modulus_shims` module; host uses `shim_host_stub.zig` |
| `tab5_root.zig` freestanding std | **done** | 4 KiB page + `Io.failing` debug_io; host stays on `root.zig` |
| tab5-lib `-fsingle-threaded` | **done** | `build.zig` `.single_threaded = true` on tab5 module |
| `zig build translate-check` | **done** | CI-ready header translate gate for Tab5 target |
| `core/host_http.zig` | **done** | HTTP GET + WS handshake probe (matches `tcp_transport_shim.c`) |
| `modulus-host` HTTP CLI | **done** | `--http-get`, `--probe-ws` with optional `--out` |
| `Io.Group` / async on device | **never** | Core 1 hot path heap-free |
| `zig build --fuzz` on Windows | **N/A** | build_runner: `--fuzz` not on Windows; corpus fuzz tests still run under `test` |

**Priority backlog:** device OTA when `ota_0`/`ota_1` exist; add `rtc_shim.h` to translate bundle.

### Zig std / build corpus (2026-06-17)

Saved analysis: [`docs/zig/std-corpus-notes.md`](docs/zig/std-corpus-notes.md) — from [langref](https://ziglang.org/documentation/master/), [std](https://ziglang.org/documentation/master/std/), [build system](https://ziglang.org/learn/build-system/), [overview](https://ziglang.org/learn/overview/).

**Corpus advanced items #1–#20: done.** NVS manifest codegen (`gen-nvs-manifest`), `host-diag`/`install-headers`, inline-else dispatcher, full ABI `@offsetOf` proofs, overflow-safe overrides, cold export paths, arena CLI, limited I/O, scoped host log, error traces, DRO `@Vector` batch, encoder wrap/safety-off, Linux continuous fuzz CI, doctests.

### Zig creation playbook (swarm audit 2026-06-17)

Recall index for agents — full swarm read of std modules, langref (Memory/IB/Casting), build guide. **Rule:** load `modulus-zig.mdc` + this section before new Zig code.

#### std modules — use / avoid

| Module | Modulus today | Create code rule |
|--------|---------------|------------------|
| **HashMap** | Host only: `mock_nvs.zig` (`StringHashMapUnmanaged`) | Device NVS = C shim, **no map**. Unmanaged: `.empty`, `getOrPut(allocator, k)`, `deinit(allocator)`. Never managed `.init(allocator)`. |
| **Rings** | `event_bus` fixed `[16]`, `rx_ring` SPSC 1024 B atomics, device events = FreeRTOS queue | **No std ring.** Hot path = fixed array or SPSC atomics; never heap in Core 1. |
| **ArrayList** | Host HTTP, boot/power test traces | `.empty`, `append(allocator,x)`, `deinit(allocator)`, `Io.Writer.Allocating.fromArrayList`. Pre-`ensureTotalCapacity` on known sizes. **Never** `.init`, `.writer()`. |
| **json** | None in `src/` | Host-only when OTA/manifest needs structured parse. Device = fixed struct + bounded text. |
| **log** | `host_log.host`, `device_log.{settings,ui}` | Import scopes from `core/device_log.zig` / `host_log.zig` — **never** raw `std.log.scoped` in modules. **Never** log in Core 1 1 kHz loops. |
| **compress** | None | Host-only `std.compress` when OTA gzip lands; never in `systemTick`/ISR. |

#### Memory & illegal behavior (langref)

| Surface | Rule |
|---------|------|
| Host | `init.gpa` long-lived; `init.arena` CLI one-shots; `defer`/`errdefer` on every heap path |
| Tab5 Core 1 | 64 KB boot `FixedBufferAllocator` only; **no heap** in `systemTick`, encoder poll, ISR |
| Tests | `std.testing.allocator` or `LeakGuard` / `DebugAllocator` — not GPA |
| Build mode | Host tests **Debug**; Tab5 **`ReleaseSafe` pinned** — never `ReleaseSmall` on device UI (#35560) |
| Safety off | `@setRuntimeSafety(false)` only in documented hot slices (`ext_encoder_poll`); prefer `@branchHint(.cold)` on exports |
| Sentinel `[:0]` | NUL at `len` required; slicing `buf[0..n :0]` asserts in ReleaseSafe |
| Unchecked IB | No pointers to stack after return; document who frees heap slices |

#### C ABI & casting (new shims checklist)

1. C header first → Zig `extern struct` (not `struct`, not `packed struct`).
2. Prove in `firmware/abi_layout.zig`: `@sizeOf`, `@alignOf`, `@offsetOf`, field **type equality** vs translate-C.
3. **Flags in structs:** `u8` not `bool` (`CncStatus` model).
4. **New export params/returns:** prefer `c_int` 0/1 until bool FFI verified (#35373).
5. **Enums:** `enum(c_int)` only in FFI.
6. **Pointers:** C strings `[*:0]const u8`; buffers `[*]u8` + cap; `abi_guard` on exports.
7. **Casting:** no `@bitCast` in protocol code; `@ptrCast` + `@alignCast` for callback `ctx` only.
8. **Translate-C:** same `riscv32-freestanding-none` as link; update `shim_host_stub.zig` + run `translate-check`; bump `abi_epoch` on layout change.
9. **Odd-width ints:** never in protocol (#35597).

#### Build workflow

| Command | Output |
|---------|--------|
| `zig build test` | Host Debug tests + NVS codegen |
| `zig build ci` | test + fuzz + translate-check + tab5-lib + install-headers + gen-nvs |
| `zig build tab5-lib` | `libmodulus_zig_core.a` (ReleaseSafe rv32) |
| `zig build translate-check` | Shim headers compile for Tab5 |
| `zig build install-headers` | `zig-out/include/modulus/*.h` |
| `zig build run-host` / `host-diag` | Host tooling |

- **NVS keys:** `settings_keys.all_keys` = source of truth; `tools/gen_nvs_manifest.zig` → `addOutputFileArg` → `nvs_key_manifest` test sync. **Not `@embedFile`** (need typed `[]const u8` array).
- **Codegen tools:** always `b.graph.host` target (not cross-compiled).
- **Stuck builds:** `zig build -fno-incremental`; clean `zig-out/`.

#### Code improvements backlog (from audit)

| P | Item | Status |
|---|------|--------|
| P0 | Keep `abi_layout.zig` updated on every `ui_shim.h` field change | **ongoing process** |
| P1 | `rtc_shim.h` in translate bundle; reduce `shim_host_stub` drift | **done** — `rtc_shim_translate.h` + full RTC externs + `shim_bundle_manifest.zig` |
| P1 | New bool exports → `c_int` or Tab5-target `@sizeOf(bool)` gate | **done** — `abi_bool.zig` comptime gate + `prefer_c_int_for_new_exports` |
| P2 | `std.json` host OTA manifest parse when pipeline lands | **done** — `ota_manifest.zig` + JSON `writeStagingManifest` |
| P2 | `tab5-idf.yml` → `zig build ci` parity with `zig-test.yml` | **done** |
| P3 | Optional `fixed_ring.zig` DRY for `event_bus` + `rx_ring` patterns | **done** |

Ref docs: [`docs/zig/std-corpus-notes.md`](docs/zig/std-corpus-notes.md).

## Agent behavior (project-local)


| Need                                   | Where                                                         |
| -------------------------------------- | ------------------------------------------------------------- |
| Zig mechanics                          | skill `zig-core`                                              |
| Build / ZLS / zig-mcp / MCP stack      | skill `zig-build`; `.\scripts\setup_zig_mcp_stack.ps1`        |
| C++ reference / porting                | skills `cpp-pro`, `modern-c-programming`                      |
| Dependency / IDF / Zig upstream source | skill `**opensrc*`* (`npm i -g opensrc`, cache `~/.opensrc/`) |
| Port order + verify gates              | skill `**zig-port**`                                          |
| Issue guardrails                       | rule `zig-pitfalls`                                           |
| Tab5 LVGL / WDT / icons                | rule `**lvgl-tab5-ui-pitfalls**`                              |
| Tab5 pins / SDIO                       | rule `modulus-tab5`, `docs/hardware/tab5/`                    |
| IDF 6 drivers                          | rule `modulus-idf6`, skill `esp-idf-6`                        |
| Karpathy / refactor                    | rules `karpathy-guidelines`, `root-cause-refactor`            |
| Service vs action layering / dedup ops | skill `code-structure`                                        |
| Check PR/MR/CL review + checks         | skill `check-pr` (needs `gh`/`glab`/`p4` + auth)              |
| Loop a PR to 5/5 Greptile score        | skill `greploop` (needs `gh`/`glab` + Greptile on repo)       |
| Deepening / architecture review report | skill `improve-codebase-architecture` (+ `grill-with-docs`)   |
| Remove AI writing patterns from prose  | skill `stop-slop` (docs, comments, commits, user-facing text) |
| MD3 tokens, components, UI compliance audit | skill `material-3` (Compose-first; Tab5 LVGL M3-dark shims) |


## Per-repo pipeline

- **Hooks (project):** `.cursor/hooks.json` → `session-pipeline.ps1` on `sessionStart`; full portable template in `.cursor/hooks/hooks.pipeline.template.json`
- **Hooks (global, this PC):** `~/.cursor/hooks.json` → RTK `preToolUse`, Token Savior `postToolUse`, Evolver `sessionStart` / `afterFileEdit` / `stop`
- **CBM:** re-index after adding `src/**/*.zig` or large rule/skill changes
- **Ruflo:** namespace `patterns` — architecture + zig-port decisions stored via `memory_store`
- **Evolver:** `memory/YYYY-MM-DD.md` daily log; `evolver run` after substantive sessions
- **Token Savior:** re-index after new skills/rules
- **zig MCP:** `.cursor/mcp.json` — lean stack `zig-mcp` + `zigars`; `setup_zig_mcp_stack.ps1`

## Learning pipeline (2026-06-06)

Session UI/WDT/flash lessons persisted for future agents (no LLM weight retraining — rules + memory only):


| Layer            | Action                                                                                                                    |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Evolver          | `evolver run` cycle #0003 — signals: perf_bottleneck, recurring_error; local GEP (Hub 401 node_secret); daily log updated |
| Ruflo `patterns` | `lvgl-heap-psram`, `lvgl-layout-pitfalls`, `tab5-flash-build`, `phosphor-icons-pipeline`, `status-bar-regressions`        |
| Cursor rule      | `.cursor/rules/lvgl-tab5-ui-pitfalls.mdc` (`alwaysApply: true` + glob `firmware/tab5/components/modulus_zig/`**)          |
| Skill cross-ref  | `.agents/skills/zig-port/SKILL.md` § LVGL pitfalls                                                                        |


**Top pitfalls (one-liners):**

1. **Never 64 KB LVGL builtin pool on Tab5** — `CONFIG_LV_USE_CLIB_MALLOC=y`; WDT signature `lv_tlsf_malloc` / `lv_draw_buf_create`, repeats ~5 s even idle (not power-menu).
2. Never `transform_scale` labels under `sw_rotate` — change-gate all LVGL updates or Core-0 WDT.
3. Opaque scrims + per-leaf opacity — not translucent overlays or parent group opa under live dashboard.
4. Build before flash — stale binary → checksum mismatch / bogus backtraces (`mp3`/settings red herrings).
5. Factory partition 3 MB when fonts + Phosphor icon ROM push app >1 MB.

### 2026-06-06 evening — LVGL heap WDT (persisted)

- **Root cause:** `CONFIG_LV_USE_BUILTIN_MALLOC=y` + `CONFIG_LV_MEM_SIZE_KILOBYTES=64` — 64 KB internal LVGL pool exhausted/fragmented by 1280×720 `sw_rotate` layer draw buffers → `lv_tlsf_malloc` stalls → taskLVGL pins Core 0 → IDLE0 WDT every ~5 s (idle dashboard, no power press).
- **Wrong paths tried:** power-menu `transform_scale` fix, overlay cache, 2 ms defer timer, boot prewarm — helped other issues, **not** recurring crash.
- **Correct fix:** `CONFIG_LV_USE_BUILTIN_MALLOC=n` + `CONFIG_LV_USE_CLIB_MALLOC=y` (`sdkconfig.defaults`; needs PSRAM `CONFIG_SPIRAM_USE_MALLOC=y`). Defense: opaque scrims, no `FADE_IN` screen load, DRO per-leaf opacity not group opacity.
- **Verification:** addr2line on matching ELF; **55 s idle dashboard zero WDT** (was ~12 s + repeating); user confirmed power button works post-flash.

## Key decisions (2026-06-05)

1. Created `**zig-port`** skill + `**zig-pitfalls**` rule; updated `**modulus-zig.mdc**` for 0.16.
2. C6 firmware remains C (ESP-Hosted **2.11.4** version lock with P4 host).
3. Host-first testing before IDF `riscv32-freestanding` link.
4. UI port deferred — largest surface; C++ LVGL M3 stays until core+cnc+hal stable.

## Session log

- **2026-06-05:** Deep-reviewed C++ reference (`Modulus Convert to ZIG core`); Zig 0.16 SME pass; Codeberg issues/PR pitfalls catalog; seeded memory + pipeline stores.
- **2026-06-05:** Phase 2 complete — `cnc_config`, `cnc_state`, `grblhal/{parser,cmd,rt,session,engine}`, `driver`; host tests green (`zig build test`).
- **2026-06-05:** Phase 3 complete — `hal/transport/{dispatcher,serial,stream,link,mock_channel,espnow_config}`; RS485 default + full TX/RX integration test; 45 host tests.
- **2026-06-05:** Phase 4 complete — `hal/platform/{display,power,battery,i2c_coex,ext_encoder}`, `hal/wireless/{sdio_pins,mock_hosted,wireless}`; deep-sleep step order + encoder jog tests; 58 host tests.
- **2026-06-05:** Runtime + Tab5 scaffold — `runtime/{runtime,hooks}`, `host_main` full boot, `firmware/abi.zig` C exports, `firmware/tab5/` IDF 6.0 + `zig build tab5-lib` (riscv32 freestanding); display lock/unlock in boot hooks; **62 host tests**.
- **2026-06-05:** Phase 4c — `idf_nvs` + `nvs_shim.c`, `device_runtime` wired to `modulus_zig_boot`/`system_tick`, `modulus_zig_boot_ok`, ABI epoch 2; tab5-lib links full runtime; **64 host tests**.
- **2026-06-05:** Tab5 hardware build — `scripts/build_tab5.ps1` auto IDF 6.0.1 + `ZIG_EXE`; Zig CPU `generic_rv32+m+a+c+f+zicsr+zifencei-d-zcd-zcf` + `-fcompiler-rt`; `libmodulus_zig_core.a`; IDF link `-Wl,-u,modulus_nvs_init`; `**idf.py build` OK**.
- **2026-06-05:** Tab5 flash COM5 — `CONFIG_ESP32P4_SELECTS_REV_LESS_V3` + `REV_MIN_0` for P4 v1.3; 16MB flash; `**idf.py -p COM5 flash` OK**.
- **2026-06-06:** Tab5 boot verified COM5 — first capture: stack overflow in `modulus_zig_boot`; fix `CONFIG_ESP_MAIN_TASK_STACK_SIZE=32768`; log shows `Zig runtime boot OK`.
- **2026-06-06:** Core 1 `sys_task` — `firmware/system_task.zig` (`xTaskCreatePinnedToCore` core 1, 8192 words, pri 5, 10 ms); `app_main` Core 0 idle; ABI epoch 3; **65 host tests**.
- **2026-06-06:** Device RS-485 — `serial_shim.c` + `idf_serial.zig`; `serial.zig` comptime backend; sys_task polls UART RX (no separate RX task yet); ABI epoch 4; host tests green; `**idf.py build` OK**.
- **2026-06-06:** Core 0 `evt_dispatch` — `event_shim.c` FreeRTOS queue; `event_dispatch_task.zig` (core 0, pri 10, 4096 words); device `publish` cross-core safe; ABI epoch 5.
- **2026-06-06:** Display BSP — `display_shim.c` (`bsp_display_start_with_config`, 120-line PSRAM stripe, 90°/270° rotation); `display.zig` device backend; image ~830 KB; ABI epoch 6; `**idf.py build` OK**.
- **2026-06-06:** Display activity + CNC defer — LVGL 500 ms timer (`lv_display_get_inactive_time` dim/sleep/wake); `cnc/deferred_connect.zig` 11 s auto-connect on device; ABI epoch 7.
- **2026-06-06:** Phase 4h — BMI270 motion wake, PIN lock after sleep, serial RX task pri 6, INA226 battery + deep-sleep power; ABI epoch 8.
- **2026-06-06:** Phase 5 UI MVP — `ui_theme/boot/dashboard/pin_lock/shim.c`, Zig `ui/manager.zig` event wiring, `modulus_zig_fill_cnc_status`; boot splash 3 s → dashboard DRO; ABI epoch 9; image ~845 KB.
- **2026-06-06:** Tab5 display OOM fix — `sdkconfig.defaults` missing `CONFIG_SPIRAM=y` (32 MB hex PSRAM + LDO); without it MIPI-DSI DPI frame buffer fails `ESP_ERR_NO_MEM`. Rebuilt + flashed COM5; boot shows PSRAM 32 MB, ABI 9, display ready, boot screen.
- **2026-06-06:** Phase 5b — `ui_status_bar.c`, `ui_widget_jog.c`, `ui_widget_actions.c`; 3-col dashboard; Zig `modulus_zig_cmd_*` / jog setters; ABI epoch 10; image ~898 KB.
- **2026-06-06:** Phase 5c — `ui_widget_overrides.c`, `ui_settings.c` + `ui_settings_tabs.c`; feed/spindle UP/DOWN/RESET; settings gear on status bar; NVS display/power tabs; `modulus_zig_cmd_feed/spindle_override`; ABI epoch 11.
- **2026-06-06:** Phase 5d — `ui_widget_dro.c` (X/Y/Z HOME/ZERO, active axis); status bar WCS cycle, tool, feed rate, spindle RPM, clock; extended `CncStatus` + axis/WCS ABI; ABI epoch 12.
- **2026-06-06:** Phase 5e/5f — `ui_quick_settings.c`, `ui_power_menu.c`, 10-tab settings; `modulus_zig_cmd_reset/unlock`; ABI epoch 13.
- **2026-06-06:** Phase 5g — dashboard layout match reference: 4-axis DRO (NVS `cnc_axes`), purple accent jog/DRO, actions grid (cycle/hold/spindle/coolant/fan/single-step/home-all); `wpos_a`/`mpos_a` in `CncStatus`; ABI epoch 14.
- **2026-06-06:** **taskLVGL Core-0 watchdog fix** — root cause: dashboard "close-up widget pass" faked big fonts with `lv_style_transform_scale` (175-450% on montserrat_14) AND made every widget `update()` rewrite text+styles unconditionally each tick. Under `sw_rotate` 1280x720, each refresh became a full-screen multi-layer affine redraw → `lv_timer_handler` pinned Core 0, starving `IDLE0`. C++ reference never did either (real fonts + change-gated updates). Fix: enabled real Montserrat 12/16/22/24/28/36/44 in sdkconfig; removed all transform_scale; change-gated all updates (status bar, DRO, jog, overrides) with static caches; refresh floor 16→30 ms. Layout scaled to `m3_theme` reference (status bar 80, panel_left 420, panel_right 280, content pad/gap 24, DRO card min 128 + 100x48 HOME/ZERO, override circles 68, action btns 112/96). Fonts pushed app >1 MB → new `partitions.csv` 3 MB factory (16 MB flash). **No ABI change → epoch stays 14.** `zig build test` + `idf.py build` green (app 1.19 MB, 62% free). Not flashed (user flashes separately).
- **2026-06-06:** **Status-bar layout refine (photo + punch-list)** — aligned Zig status bar to reference photo / C++ `status_bar.cpp`: short captions `WCS/TOOL/FEED/SPINDLE`, center gap relocated between TOOL and FEED (FEED/SPINDLE now in right cluster), divider moved to RIGHT of WCS, settings(gear) before power. Merged `bar_stat_vu_col` into one `bar_stat_col(hdr,val,unit,...)` (unit optional) so all four columns share caption font (montserrat_12) + value baseline (montserrat_24, unit 14). Clock+battery `text_align CENTER`; battery font 16→22; power/settings glyphs montserrat_22→28 in 52×52 boxes; bar `pad_hor` 24→28. State/MPG remain stadium pills. **No ABI change → epoch stays 14** (only `ui_status_bar_build.c`/`_helpers.c`/`_priv.h` touched; `update`/`data` untouched). `zig build test` + `idf.py build` green (app 1.19 MB / 0x122b00, 62% free). Not flashed.
- **2026-06-06:** **Status-bar invisible text fix** — root cause: stat columns + pills kept default LVGL object height (~50–100px) after `remove_style_all`, so 80px bar vertically clipped captions (WCS/TOOL/FEED/SPINDLE) and pill labels (IDLE/MPG). Fix: `LV_SIZE_CONTENT` on col/vu, pill height 40 + `lv_obj_center`, vu cross-axis `CENTER` (was `END`), caption font 12→14, enabled `CONFIG_LV_FONT_MONTSERRAT_14` (unit labels were missing font). Caption restored to `FEED RATE`. **ABI epoch 14.** `zig build test` + `idf.py build` green (app 0x122b90, 62% free). Not flashed.
- **2026-06-06:** **Status-bar feed/spindle alignment** — FEED RATE/SPINDLE captions now right-align to unit label edge (`right_align` flag on `bar_stat_col`); value row `flex END` + 4px `pad_column`, removed `min_width(64)` on value labels (was forcing wide value–unit gap). WCS/TOOL unchanged (left-aligned, no unit). **ABI epoch 14.** `zig build test` + `zig build tab5-lib` PASS; `idf.py build` not run (IDF_PATH unset in agent shell). Not flashed.
- **2026-06-06:** **Phosphor Light UI icons** — replaced all `LV_SYMBOL_*` labels in Tab5 LVGL UI with pre-rendered Phosphor Light ARGB8888 assets (28 icons × 24/32 px). Added `ui_icons.h/c`, `assets/icons/generated/icon_assets_{24,32}.c`, generator `scripts/gen_phosphor_icons.mjs` (`@resvg/resvg-js`, `assets/light/`). Status bar, actions, DRO, overrides, settings tabs, power menu, PIN pad migrated. **ABI epoch 14** (no Zig ABI change). `zig build test` + `zig build tab5-lib` + `idf.py build` green; app **0x145eb0** (unchanged vs Duotone — fixed 24/32 ARGB8888 raster size). Not flashed.
- **2026-06-06:** **Status-bar icon + battery polish** — power/settings: no circle bg, 40 px icons in 48×48 touch targets (power `#FF4D4D`, settings `#E8EAED` via LVGL recolor). MPG icon white→`#0D0D12` when active pill. Battery: 32 px vertical Phosphor stems (full/high/medium/low/empty + charging + warning), 9 px icon–pct gap, dynamic swap on pct/charge/warn. `modulus_ui_icon_battery_for_pct()` + `modulus_battery_is_low_warn()` (≤NV `bat_warn` default 15% or no-pack `charge_state==3`). **BatteryPlusVertical deferred** (no saver mode). Added `icon_assets_40.c` (power/gear only), `ui_icons_battery.c`. **ABI epoch 14.** `zig build test` + `tab5-lib` + `idf.py build` PASS; app **0x14c5e0** (+0x6730 vs 0x145eb0, 57% free). Not flashed.
- **2026-06-06:** **Status-bar GearSix + battery color** — settings button: Phosphor `GearSix` 40 px (`MOD_UI_ICON_GEAR_SIX`; settings tabs keep `Gear` 24 px). Battery icon dynamic recolor via `modulus_ui_icon_battery_color_for_pct()` (charging/full green `#24D391`, high/medium white, low/warn amber `#FFB800`, empty red `#FF4D4D`). Regenerated icon assets (`gear-six-light.svg`). **ABI epoch 14.** `zig build test` + `tab5-lib` + `idf.py build` PASS; app **0x14e020** (+0x1a40 vs 0x14c5e0, 57% free). Not flashed.
- **2026-06-06:** **Dashboard color + icon weight tweaks** — CYCLE STOP (`state==2`) btn bg `#FF4D4D`; FEED RESUME (`state==3`) bg `#24D391`; HOME ALL label `#0D0D12`. Override arrows → Phosphor **regular** `arrow-up`/`arrow-down` white `#E8EAED`; DRO ZERO → regular `number-circle-zero` white. `gen_phosphor_icons.mjs` adds `regular` weight path (`assets/regular/{stem}.svg`). **ABI epoch 14.** `zig build test` + `tab5-lib` + `idf.py build` PASS; app **0x154810** (56% free). Not flashed.
- **2026-06-06:** **Actions grid icon polish** — 2x2 accessory tiles (SPINDLE CW/COOLANT/FAN/SINGLE STEP) icons recolored white `#E8EAED` via `modulus_ui_icon_recolor`. Single Step stem `skip-forward` → Phosphor light `steps`. **ABI epoch 14.** `zig build test` + `tab5-lib` + `idf.py build` PASS; app **0x154890** (+0x80 vs 0x154810, 56% free). Not flashed.
- **2026-06-06:** **CYCLE START darker green** — dark-mode `modulus_ui_color_cycle()` token `#4ADE80` → `#34D399` (C++ `m3_theme::state_run_bg()`); FEED RESUME `#24D391` unchanged. **ABI epoch 14.** Not flashed.
- **2026-06-06:** **Jog increment multiplier clipping fix** — root cause: `ui_widget_jog.c` jog card never set a height, so it kept the default LVGL object height (smaller than ~172 px content); with scroll removed the increment grid overflowed and the bottom mult line (`x1`..`x1000`) clipped. Prior 72→76 grid/tile bump made content taller against same clip box → still clipped. Fix: `lv_obj_set_height(card, LV_SIZE_CONTENT)` (mirrors C++`widget_jog.cpp:108`); removed asymmetric `pad_bottom 28` (uniform `pad_all 24` = even spacing); reverted grid + tile height 76→72 (C++ parity). Overrides/dashboard untouched (overrides container `flex_grow 1` absorbs remaining column height). **ABI epoch 14** (C-shim only). `zig build test` + `tab5-lib` + `idf.py build` PASS; app **0x154890** (56% free). Not flashed.
- **2026-06-06:** **Override arrow button size** — FEED/SPINDLE UP/DOWN circles 60→68 px (C++ `widget_overrides.cpp` parity); arrow icons 24→32 px (white regular Phosphor). **ABI epoch 14.** Not flashed.
- **2026-06-06:** **Power Menu WDT fix** — root cause: `modulus_ui_show_power_menu()` rebuilt full overlay (header + 5 rows + 60% full-screen backdrop + Phosphor icons) synchronously inside status-bar click handler; one `lv_timer_handler` pass never yielded → IDLE0 starved (same class as epoch-14 transform_scale WDT). C++ also rebuilds on hide but used lighter LV_SYMBOL draws; Zig Phosphor ARGB8888 + sw_rotate 1280×720 backdrop blend made first-open fatal. Fix: cache `s_menu` overlay (show/hide via `LV_OBJ_FLAG_HIDDEN`, no delete on dismiss); pause dashboard refresh before any work; defer first build to one-shot 2 ms LVGL timer so click handler returns immediately; build tree while overlay stays hidden then single reveal; `LV_SCROLLBAR_MODE_OFF` (fixed-height list, no layout thrash); change-gated device-row hints on each open; `machine_busy()` guard in restart/shutdown callbacks. Confirm modals unchanged (on-demand create/destroy). New `ui_power_menu_shell.c`. **ABI epoch 14.** `zig build test` + `tab5-lib` + `idf.py build` — user must re-flash matching checksum.
- **2026-06-06:** **Power Menu prewarm WDT fix** — root cause: prior 2 ms defer still ran full overlay build (60% full-screen backdrop + Phosphor ARGB8888 rows) in one `lv_timer_handler` pass on first power click while dashboard refresh timer active → IDLE0 starved (~27 s WDT); stale flash (checksum mismatch) masked fix. Fix: **prewarm** `modulus_ui_prewarm_power_menu()` at first `modulus_ui_show_dashboard` (after `dashboard_create`, before refresh timer) — overlay built hidden once at boot→dashboard; power click = `pause_dashboard` + change-gate busy rows + `lv_obj_clear_flag(HIDDEN)` only; removed defer timer; backdrop `LV_OPA_60`→`LV_OPA_40`; confirm modals still on-demand. Prewarm location: `ui_shim.c` `modulus_ui_show_dashboard`. **ABI epoch 14.** Flashed COM5.
- **2026-06-06:** **REAL recurring WDT root cause = 64 KB LVGL pool (not the power menu).** On-device monitor (ELF SHA `1e1cc43…` then `d18258…` confirmed latest, not stale flash) showed the **idle dashboard alone** WDTs ~3-4 s after load — no power press. taskLVGL pinned in `lv_tlsf_malloc`/`lv_draw_buf_create`/`buf_malloc` (decoded via addr2line), repeating every 5 s, never rebooting. Root cause: `CONFIG_LV_USE_BUILTIN_MALLOC` with `CONFIG_LV_MEM_SIZE_KILOBYTES=64` — the internal LVGL draw/layer pool is far too small for a 1280×720 `sw_rotate` UI; layer draw-buffer allocs exhaust/fragment the 64 KB pool until `lv_tlsf_malloc` stalls and starves IDLE0. **Fix:** `CONFIG_LV_USE_BUILTIN_MALLOC=n` + `CONFIG_LV_USE_CLIB_MALLOC=y` → LVGL allocates from the PSRAM-backed C-library heap (`CONFIG_SPIRAM_USE_MALLOC=y`, 32 MB) — eliminates the ceiling. Persisted in `sdkconfig.defaults`. Defense-in-depth (reduce per-frame layer pressure, all on the causal path): power-menu + confirm backdrops `LV_OPA_40/70`→**opaque** `LV_OPA_COVER` (`#0A0C12`, lets opaque-cover skip the dashboard); removed dashboard `LV_SCR_LOAD_ANIM_FADE_IN` (full-screen opacity layer under sw_rotate) → plain `lv_screen_load`; DRO disabled-button dim moved from parent group `lv_obj_set_style_opa` (forces a layer every frame) to per-leaf opacity (bg+image+label, no layer). Files: `ui_power_menu_shell.c`, `ui_power_menu_confirm.c`, `ui_shim.c`, `ui_widget_dro_build.c`, `sdkconfig(.defaults)`. **ABI epoch 14** (no Zig ABI change). `zig build test` + `tab5-lib` + `idf.py build` PASS (app 0x155110, 56 % free); flashed COM5; **verified on-device: 55 s idle dashboard, ZERO WDT** (was crashing by ~12 s + repeating). Power button not physically pressed by agent, but both the heap ceiling and the power-menu translucent-layer instance are fixed. ZIG_EXE/ZIG_LIB_DIR must be set for the CMake reconfigure a sdkconfig change triggers.
- **2026-06-06:** **Power Menu semi-transparent scrim** — backdrop `LV_OPA_COVER`→`LV_OPA_60` (confirm `LV_OPA_70`), black scrim matching C++ `ui_manager.cpp`; safe because `modulus_ui_pause_dashboard_refresh()` pauses the LVGL refresh timer (`lv_timer_pause`) before show and `resume` is gated on `modulus_ui_power_menu_visible()`. **ABI epoch 14.** Not flashed.
- **2026-06-06:** **Settings overlay C++ parity + scrim** — rebuilt the 10-tab System Settings overlay to match reference photos + C++`screen_settings*.cpp`. Was a basic version (right-side "Settings" header, 108 px icon-over-short-label sidebar, raw label/switch rows). Now matches C++ shell: top header bar (gear `MOD_UI_ICON_GEAR` primary + "System Settings" montserrat_24 + 44 px round X, surface_container_high, bottom divider) over a `surface_container_low` card (94%x92%, radius 20, clip_corner, outline border); body = 230 px sidebar (`surface_dim`, right border, 2-line wrapped labels "CNC &\nConnection" etc., icon+label row, active-tab highlight via bg + primary recolor) + scrollable content panel. New shared M3 widget kit (`ui_settings_widgets.c` + `ui_settings_widgets_ctl.c` + `include/ui_settings_priv.h`): `settings_section(title,subtitle)`, `settings_detail_row`, `settings_action_row` (ASCII `>` chevron — **no rotated/affine icon**, WDT-safe), `settings_destructive_row`, `settings_toggle_row`, `settings_slider_row`, `settings_dropdown_row`, all 48-52 px with hairline bottom divider (outline @ opa30), label montserrat_16 / value montserrat_14. **Scrim:** overlay `LV_OPA_70`→`**LV_OPA_60`** black matching power menu; dashboard refresh already paused via `modulus_ui_show_settings()` (ui_shim.c `pause` before show, `resume` gated on visible) — verified, no fix needed. **Lazy/cached:** shell built once; `select_tab` cleans + builds **only the active tab** (no 10-tab rebuild), scroll reset on switch; live values change-gated (rebuilt on open, not per-tick). Tabs: CNC (`ui_settings_tab_cnc.c` — hero Session/Transport, Protocol GrblHAL, transport dropdown→NVS `cnc_conn`, Reconnect/Test→`modulus_zig_cmd_reset`, Configure/Disconnect stubs labeled), System (`ui_settings_tab_system.c` — device hero card, Firmware `modulus_zig_version`, Platform, Language/TimeZone/TimeFormat dropdowns→NVS stub-labeled, ABI/Host/PSRAM), Display+Power (`ui_settings_tabs.c` — brightness/refresh/dark/flip; dim/sleep/deep-sleep; **refresh floor fixed**: dropped unsafe 16 ms, now 33/50/100 ms only), Dashboard/Audio/Wireless/Security/Machine/Storage (`ui_settings_tabs_extra.c` — wired to existing shims, stubs labeled). Wiring table: bright→`bright`+`set_brightness` ✓, refr_hz→`refr_hz`+`set_refresh_period_ms` ✓, darkmode/flip ✓, dim_to/scr_to→`set_timeouts` ✓, pwr_mode/pwr_dsto→`set_sleep_policy` ✓, lefty/cnc_unit/mic_gain→NVS ✓, security boot/sleep→`pin_boot`/`pin_slp` ✓, cnc_conn dropdown→NVS ✓ (no transport reinit shim — Configure/Disconnect stub); audio HAL/wireless C6/SD/i18n/PIN-editor/machine-name-editor = missing features, labeled in-UI. Files: `ui_settings.c` (shell), `ui_settings_widgets.c`, `ui_settings_widgets_ctl.c`, `ui_settings_tab_cnc.c`, `ui_settings_tab_system.c`, `ui_settings_tabs.c`, `ui_settings_tabs_extra.c`, `include/ui_settings_priv.h`, CMakeLists. **ABI epoch 14** (C-shim only, no Zig ABI change). `zig build test` + `tab5-lib` + `idf.py build` PASS; app **0x155e40** (~1.40 MB, 55% free). Not flashed.
- **2026-06-06:** **Power Menu overlay C++ parity** — rebuilt `ui_power_menu.c` to match reference photo + C++`ui_manager.cpp` `show_power_menu()`. Was a simpler 4-item flat list ("Power" title, no sections, col-stacked sub, no chevrons, "Sleep Now"). Now: header "Power Menu" (montserrat_24 + red power icon, 80 px, surface_container_high, bottom border) + 44 px round X; two sections **MACHINE CONTROL** (Reset CNC Connection, Clear Alarm, Emergency Stop "Confirm to stop" destructive) and **DEVICE POWER** (Restart Device "Reboot now", Shutdown Device "Power off" destructive). Rows 56 px, SPACE_BETWEEN, right-anchored hint (montserrat_14) + ASCII `>` chevron (montserrat_16), bottom divider (outline @ opa30), pressed bg. Section titles montserrat_22. Body `LV_SIZE_CONTENT` capped 520 px + scrollbar AUTO (list-only scroll). Wiring: Reset→`modulus_zig_cmd_reset`, Clear Alarm→`modulus_zig_cmd_unlock`, **Emergency Stop**→confirm→`modulus_zig_cmd_reset` (0x18 soft reset — exactly C++ `cmd_estop()` connected path; no new export needed), Restart→confirm→`esp_restart`, Shutdown→confirm→`modulus_power_enter_deep_sleep` (Zig has no true `hal_power::shutdown` yet — deep sleep is the soft-off equivalent; BMI270 5 s constraint unaffected by graceful sleep). Confirm modal (Cancel/Confirm, destructive=error bg) for E-stop/Restart/Shutdown; **busy guard** (Run/Hold/Jog) disables device-power rows — fixed prior bug that omitted Hold (was `state==2||4`, now `2||3||4`). Dashboard refresh paused while open. **Theme:** kept dark header (`surface_container_high` `#282A31`, not white) — photo's light title bar is camera glare/overexposure on the glossy panel, not an intended/regressed style; C++ uses dark `surface_container_high`. Split to satisfy ≤150-line rule: `ui_power_menu.c` (146), `ui_power_menu_build.c` (header+rows, 128), `ui_power_menu_confirm.c` (111) + `include/ui_power_menu_priv.h`. **ABI epoch 14** (no Zig ABI change). `zig build test` + `tab5-lib` + `idf.py build` PASS; app **0x154f90** (56% free). Not flashed.
- **2026-06-06:** **MEMORY TODO consolidated** — backlog section added after port plan (verify-on-device, UI stubs, firmware gaps, infra); baseline ABI 14 ~1.4 MB; session wins + top-5 + never-revert guardrails captured for next agent.
- **2026-06-06:** **Settings C++ structural parity (subagent cca34561)** — Tab5 settings overlay now matches C++ `screen_settings*.cpp` structure: CNC transport reinit from dropdown via `modulus_zig_transport_reinit`; PIN editor modals (set/change/clear); wireless tab nav stack + sub-screens (C6 scan/connect/provision actions remain stub); transport config modal; 10-tab section bodies (CNC/Display/Power/System/Dashboard/Audio/Wireless/Security/Machine/Storage) with shared M3 row kit. `zig build test` + `tab5-lib` + `idf.py build` green; **ABI epoch 14** unchanged. Flash pending device verify (all 10 tabs scroll/switch, transport switch reinit, PIN modals, wireless nav).
- **2026-06-07:** **M3 dark/light full-system theme** — root cause: `modulus_ui_theme_apply()` only repainted active screen; dashboard/boot/overlays/widgets used hardcoded dark hex (`#0E1016`, `MOD_UI_ICON_WHITE`/`DARK`). Fix: expanded `ui_theme.c` MD3 token palette (surface/on-surface/success/warning/icon_chrome/on_tinted_btn/state-pill contrast); `modulus_ui_theme_apply()` orchestrates `*_theme_refresh()` on dashboard, status bar, DRO/jog/overrides/actions, settings shell (+ active tab rebuild), quick settings, PIN lock, power menu, wireless connect modal, confirm overlays. Toggle: Settings → Display & Theme → **Dark mode** (`darkmode` NVS). **ABI epoch 14** unchanged. `zig build test` + `tab5-lib` PASS.
- **2026-06-07:** **System & About tab audit** — root cause: 1 Hz timer called unconditional `lv_label_set_text` on clock/NTP/uptime (LVGL invalidation under `sw_rotate`); manual NTP row used parent `lv_obj_set_style_opa` (layer compositing); factory reset painted black before NVS erase (stuck screen on failure); manual time modal did not refresh labels. Fix: `sys_set_lbl_if_changed` caches, per-leaf text opa, live PSRAM row, `modulus_ui_settings_system_tab_refresh()` after manual set, black screen only after successful erase, shorter confirm/OTA copy. **ABI epoch 14** unchanged. `zig build test` + `tab5-lib` PASS.
- **2026-06-07:** **Storage & Diagnostics tab audit** — root cause: 2 s timer unconditional `lv_label_set_text`/style on memory+SD+USB rows; export row parent `lv_obj_set_style_opa`; `loglvl` NVS off-by-one vs C++ (5-row dropdown + `lvl+1`, no boot restore). Fix: `stor_set_lbl_if_changed` + color caches, per-leaf text opa on export row, C++ 6-row log dropdown (index = `esp_log_level_t`), restore in `modulus_storage_init`, I2C scan touch tone. **ABI epoch 14** unchanged. P4 ELF `1feaaef…` app **0x2a2590** (12% factory free). COM5 flash PASS.
- **2026-06-07:** **C6 ESP-Hosted Phase 6 scaffold** — copied reference `Modulus Firmware C6/slave` → `firmware/tab5-c6/` (273 files); IDF 6.0 build green (`network_adapter.bin` 0x172960); fixes: absolute-path CMake for workspace spaces, `idf_component_register`, `esp_driver_sdmmc`/`WIFI_IF_STA` IDF6 API. P4 host: `esp_hosted` 1.4.0 + `sdkconfig.defaults` Tab5 SDIO2 (CLK12 CMD13 D0–11 D1–10 D2–9 D3–8 RST15) + **`CONFIG_ESP_HOSTED_SDIO_PRIV_PIN_D1_4BIT_BUS=10`** (was 15 → D1/RST collision); `wireless_shim.c`, `scripts/build_tab5_c6.ps1`, `scripts/patch_tab5_idf6_deps.ps1`. P4 `idf.py build` green (app 0x21e7e0). **COM6 C6 flash failed** (no serial data — hold BOOT/reset); **COM5 flashed** once; serial: `sdmmc_card_init failed` until C6 slave on bus + D1 fix reflashed. C6 radio/UI actions still stub.
- **2026-06-06:** **Audio MP3 boot/shutdown + UI touch tones** — full port of C++ `hal_audio.cpp` into `audio_shim.c`: embedded `boot_sound.mp3` (257 KB) + `shutdown_sfx.mp3` (28 KB) via `EMBED_FILES`; `chmorgan/esp-audio-player` 1.0.7 + Core-1 `audio_sfx` task (queue MP3 + procedural I2S sine/square tones, 4 tone profiles); boot queued non-blocking (`modulus_audio_play_boot`, `snd_up` gated in Zig boot); shutdown on `modulus_power_enter_deep_sleep` when `snd_dn` (wait ≤3 s, backlight off first); global pointer-indev touch feedback (`ui_touch_sound.c`, registered in `modulus_ui_init`); settings Audio tab POP/DROP/CHIRP calls live. **ABI epoch 14** unchanged. `zig build test` + `tab5-lib` + `check_ui_ascii` PASS; `idf.py build` blocked locally by IDF 6.0.1/6.2 esp_wifi_remote cmake mismatch (pre-existing env). Not flashed.
- **2026-06-06:** **Tab5 infra scripts + CI** — fixed `flash_tab5.ps1` cwd (zig from repo root); added `check_ui_ascii.ps1` (44 UI files, LVGL literal scan) hooked into `build_tab5.ps1`/`flash_tab5.ps1` (`-SkipAscii`); repaired `build_tab5.ps1` zig `lib_dir` regex parse bug; new `.github/workflows/tab5-idf.yml` (`zig build test` + `tab5-lib` + ESP-IDF 6.0.1 `idf.py build`, managed_components cache). No ABI change.
- **2026-06-06:** **RX8130 RTC (35570f0d)** — `rx8130.c` on M-Bus 0x32 (`bsp_i2c_get_handle`, coex lock); `rtc_shim.c` boot sync (`modulus_rtc_init` → VLF guard, RTC→`settimeofday`); System tab live clock/uptime + manual date/time modal (`ui_settings_time.c`); NTP deferred until C6 WiFi. Zig `rtc.zig` BCD tests + `idf_rtc.zig`. **ABI epoch 14** unchanged.
- **2026-06-06:** **Factory reset wired** — System tab confirm → feed-hold + black screen → `modulus_zig_factory_reset()` (`settings_store.factoryReset` → `nvs_erase_all` on `"modulus"` namespace, C++ parity — not full `nvs_flash_erase`); logs `esp_err_t` on failure, no restart on error. `nvs_shim.c` error-returning erase; host test `factory reset fails before open`. **ABI epoch 14** unchanged. `zig build test` + `tab5-lib` PASS; `idf.py build` not run (IDF_PATH unset). Not flashed.
- **2026-06-06:** **SD mount HAL + Storage tab** — `storage_shim.c` ports C++ `hal_storage.cpp`: `bsp_sdcard_init`/`deinit` @ `/sdcard` (SDMMC 4-bit, LDO power, Tab5 GPIO 39-44), boot lazy mount via `modulus_storage_init` wired to Zig `storage_init` phase; `modulus_storage_get_sd_info`/`get_mem_info`, diagnostics export to `/sdcard/modulus_diag.txt`, UI cache clear, USB-C detect proxy. Settings tab 8: live SD status/capacity (2 s timer), Mount/Eject with confirm modal, memory rows (SRAM/PSRAM/LVGL/min-free), log level→`esp_log_level_set`, export diagnostics, clear UI cache. Zig `storage.zig` + `idf_storage.zig`. **ABI epoch 14** unchanged. `zig build test` + `tab5-lib` PASS. `idf.py build` blocked by pre-existing `esp_wifi_remote_weak.c` cmake path on this agent run (not storage-related). Not flashed.
- **2026-06-06:** **True PMIC shutdown** — root cause: Shutdown paths called `modulus_power_enter_deep_sleep` (Zig step trace only, no PMIC cut). Ported C++ `hal_power::shutdown()` to `modulus_power_shutdown()` in `power_shim.c`: feed-hold, `EVT_SYSTEM_SHUTDOWN`, optional shutdown MP3 (`snd_dn`), display off, rail disable (`bsp_set_ext_5v_en`/`bsp_set_usb_5v_en`), `bsp_generate_poweroff_signal()` (PI4IOE2 P4 ×3 pulse), `esp_restart` fallback. Wired power-menu confirm + System tab shutdown; Settings Power "Sleep now" → `modulus_power_enter_deep_sleep` (audio stop, no shutdown SFX). Hardware supports true off per C++ BSP — not deep-sleep-only. **ABI epoch 14** unchanged. `zig build test` + `tab5-lib` PASS; `idf.py build` blocked by pre-existing `esp_wifi_remote` idf_v6.2 cmake path (not this diff). Not flashed.
- **2026-06-06:** **Quick buttons editor** — C++ parity: NVS `cnc_qbtn0`..`3` (defaults SpindleCW/Coolant/Fan/ZeroAll), Zig `settings_keys` + host round-trip test; new `ui_quick_grid.c` (1–4 dynamic layout + settings preview); settings modal (layout preview + Slot 1–4 dropdowns, immediate NVS save); Dashboard tab "Configure Quick Buttons"; dashboard actions panel reads NVS via `modulus_ui_actions_rebuild()`; dispatch Spindle/Coolant/Fan/ZeroAll (`modulus_zig_cmd_zero_all` → `G10 L20 P0 X0 Y0 Z0`); Macro/Fan driver stubs unchanged. **ABI epoch 14** (+`modulus_zig_cmd_zero_all` export only). `zig build test` + `tab5-lib` PASS. Not flashed.
- **2026-06-06:** **Zero-while-run confirm** — `ui_zero_confirm.c` gates DRO per-axis ZERO + quick Zero All when `MachineState::Run` (C++`widget_dro` parity); modal copy matches C++ i18n (`Zero axis…` / `Work offset will be updated.` / Apply); reuses `settings_confirm_show` + `LV_OPA_70` scrim + dashboard refresh pause; host policy test `ui/zero_confirm.zig`. **ABI epoch 14** unchanged. Not flashed.


- **2026-06-06:** **esp_wifi_remote IDF6 cmake fix** — root cause: registry `esp_wifi_remote` 0.8.5 only ships `idf_v5.x/`; IDF 6+ uses in-tree `esp_wifi/remote` (`CONFIG_ESP_WIFI_REMOTE_IN_IDF`). Fix: `main/idf_component.yml` `override_path` → `components/espressif__esp_wifi_remote` no-op stub + `firmware/tab5/CMakeLists.txt` injects `esp_driver_sdmmc` for `esp_hosted` 1.4.0. `zig build test` + `tab5-lib` + `idf.py build` PASS; `modulus_tab5.bin` 0x21e7e0 (2.21 MB). Note: local `esp-idf-v6.0.1` export reports IDF 6.2.0 — CI v6.0.1 still OK with stub. Not flashed.
- **2026-06-06:** **audio_shim BSP 1.2.0** — migrated `audio_shim.c` off removed `bsp_codec_*` to `bsp_audio_codec_speaker/microphone_init` + `esp_codec_dev_*` (vol/mic/mute/open/write); MP3 player `clk_set`/`write` adapters; UI tones via `esp_codec_dev_write`. **ABI epoch 14** unchanged. `zig build test` + `tab5-lib` + `idf.py build` PASS; app `modulus_tab5.bin` 0x21e7e0 (2.21 MB, 29% factory headroom). Not flashed.
- **2026-06-07:** **C6 bring-up flash (aa3b2131 follow-up)** — COM6 C6 flash **FAIL** @460800+115200 (`No serial data received`; hold BOOT on C6 USB); COM5 P4 **PASS** (`flash_tab5.ps1`); serial: `D1[10]` in sdio_wrapper GPIO log, `sdmmc_card_init failed` (0x107) until C6 slave on bus; COM6 monitor **NO_OUTPUT**.
- **2026-06-07:** **C6 COM6 flash PASS** (uild_tab5_c6.ps1 -Flash -Port COM6 @460800, verify OK); COM6 boot: ESP-Hosted-MCU Slave **1.4.0**, Transport used :: SDIO only, Slave init_config received from host + SDIO/WiFi events; COM5 passive monitor quiet (earlier: Not able to connect/GPIO15 conflict before C6 up).

- **2026-06-07:** **P4 COM5 hosted verify (post-C6 fec14ad2)** - COM5 reset/monitor ~45s: `sdio_wrapper` CLK12 CMD13 D0-11 **D1-10** D2-9 D3-8 RST15, SDIO enum (Type SDIO, Fn0/1 blk 512), **no** `sdmmc_card_init`/0x107; **hosted link FAIL** — `transport: Not able to connect with ESP-Hosted slave device` (~11s retry); retry-only `gpio: conflict GPIO[15]` (sdkconfig D1=10, RST=15); **no** `wireless_shim` / `Core 0 evt_dispatch` log in capture — transport handshake not up on P4 despite C6 slave ready on COM6.
- **2026-06-07:** **audio_shim write_cb** — root: `esp_codec_dev_write` returns `ESP_CODEC_DEV_OK` (0) not byte count; `write_cb` passed 0 to esp-audio-player → `to write 4608 != written 0` spam; fix: `*bytes_written=len` on OK, drop redundant MP3 pre-open (clk_set owns format), `esp_codec_set_disable_when_closed(false)`. **ABI epoch 14** unchanged. `zig build test` + `tab5-lib` + `idf.py build` PASS. Not flashed.
- **2026-06-07:** **P4 hosted transport fix** — root: BSP 1.2 never enabled `BSP_FEATURE_WIFI` (WLAN_PWR_EN) + wireless init ran post-UI in `main.c` while Zig boot used mock hosted; fix: `wireless_shim.c` PI4IOE WLAN_PWR + GPIO15 RST pulse before `esp_wifi_init`, init moved to `wireless_restore` hook (C++ phase 2l); COM5 flash PASS (`modulus_tab5.bin` 0x21ea00); COM5 monitor blocked in agent (port lock) — user verify `wireless_shim: Wireless ready`.
- **2026-06-07:** **P4 hosted verify (05e881c1 / flash 0x21ea00)** - killed stale COM5 monitors; RTS reset + 35s capture: C6 WLAN_PWR_EN on, C6 reset pulse GPIO15, SDIO 4-bit 40MHz + enum OK; **FAIL** - gpio: conflict GPIO[15] on every transport reset, 	ransport: Not able to connect with ESP-Hosted slave device (no wireless_shim: Wireless ready). Log: monitor_handshake_05e881c1.log.

- **2026-06-07:** **ESP-Hosted 2.11.4 bring-up (P4+C6 version lock)** — root: **1.4.0 host/slave mismatch** + ACTIVE_LOW reset wrong for Tab5 + parallel I2C/SDIO race + missing C6 boot delay. Upgraded P4 `espressif/esp_hosted: "2.11.4"`; synced `firmware/tab5-c6/` from managed `esp_hosted/slave` (2.11.4); IDF6 `hal/sdio_slave_periph.h` patch. Verified sdkconfig (P4):

| Setting | Value |
|---|---|
| `CONFIG_MODULUS_WIFI_ENABLED` | y |
| `CONFIG_MODULUS_C6_BOOT_DELAY_MS` | 4000 |
| `CONFIG_ESP_HOSTED_ENABLED` | y |
| `CONFIG_ESP_HOSTED_P4_DEV_BOARD_NONE` | y |
| `CONFIG_ESP_HOSTED_SDIO_RESET_ACTIVE_HIGH` | y |
| `CONFIG_ESP_HOSTED_SDIO_RESET_DELAY_MS` | 2000 |
| `CONFIG_ESP_WIFI_REMOTE_LIBRARY_HOSTED` | y |
| `CONFIG_ESP_HOSTED_TRANSPORT_RESTART_ON_FAILURE` | n |
| SDIO2 pins | CLK12 CMD13 D0=11 **D1=10** D2=9 D3=8 RST=15 |

Fixes: `wireless_shim.c` PI4IOE only (no GPIO15 pulse — esp_hosted owns RST); `boot.zig` **imu_init before wireless_restore**; `main/Kconfig.projbuild` for Modulus delays. Builds: `zig build test` PASS; P4 `modulus_tab5.bin` **0x232ce0**; C6 `network_adapter.bin` **0x1345d0**. Flash COM6+COM5 PASS. Monitor: COM6 **Slave FW 2.11.4** SDIO; COM5 2nd boot **`wireless_shim: Wireless ready`**, `Card init success`, **no GPIO15 conflict**; 1st cold attempt 0x107 then retry OK. Logs: `monitor_hosted_2_11_4.log`, `monitor_c6_2_11_4.log`. MANF 0092 string not in capture (Espressif IDF6 sdio log format).

- **2026-06-07 (SDIO 0x107 TRUE ROOT CAUSE — C6 held in reset, NOT power):** Timing fixes never worked because the C6 `CHIP_EN` (GPIO15) was being **held LOW = held in reset** after every esp_hosted reset pulse. `scripts/patch_tab5_idf6_deps.ps1` (lines 18-31) **stripped esp_hosted's final `H_RESET_VAL_ACTIVE` write** from `sdio_drv.c::transport_gpio_reset` ("Tab5: stay deasserted... omit final ACTIVE"). The reset GPIO is configured **ACTIVE HIGH** (`CONFIG_ESP_HOSTED_RESET_GPIO_ACTIVE_LOW` unset → `H_RESET_VAL_ACTIVE=1`), so removing the final write leaves GPIO15 at `INACTIVE=0` → C6 `EN` LOW → slave never enumerates → CMD5 timeout **0x107** forever. **WLAN_PWR (E2.P0) was correct all along** — it does power the rail (verified: `init_expander2` writes `OUT_SET=0b00000001`, matches C++ ref `bsp_set_wifi_power_enable`). **Why USB "fixed" it:** the C6's own USB/auto-reset circuit forces `EN` high, masking the held-low GPIO15; on the internal rail nothing overrides it. **Fix:** (1) restored final `H_RESET_VAL_ACTIVE` (HIGH=enable) in `sdio_drv.c` so the pulse ends `HIGH→LOW(10ms)→HIGH→boot-delay` (C6 enabled + 5500 ms to boot); (2) removed the inverted reset patch from `patch_tab5_idf6_deps.ps1` so fresh fetches keep correct upstream behavior; (3) added boot read-back log `WLAN_PWR_EN (E2.P0) -> 1 (OUT_SET=0x.. P0=1)` in `tab5_pi4ioe.c` init + `cycle_wlan_pwr`. Sequencing: E2.P0 high (early) → cycle → GPIO15 reset ending HIGH → 5500 ms → SDIO probe. Clean build PASS, **flashed==built ELF SHA256 `8464e472f6e94fe8f3f00900a5069f44703f2a44aac49e7ffd9cb396c4906891`** (COM5, Hash verified). Expected P4-only cold-boot lines: `WLAN_PWR_EN (E2.P0) -> 1 (OUT_SET=0x.. P0=1)` → `WLAN_PWR cycle` → `Reset slave using GPIO[15]` → `C6 SDIO: wait N ms` → `Wireless ready`. **Do NOT re-add the reset-stripping patch.**
- **2026-06-08:** **Boot splash early + backlight defer** — root: `display_init` turned backlight on while BSP lock blocked LVGL; splash created after ~5 s wireless/audio chain → white panel. Fix: `boot.zig` moves `ui_init` → `ui_boot_screen` → `display_unlock` immediately after `settings_init`; `ui_boot_arm` after `wireless_restore` starts 3 s dashboard timer; `display_shim.c` defers `bsp_display_backlight_on()` to first `lv_refr_now` in unlock; splash fonts Montserrat 14→18 (`CONFIG_LV_FONT_MONTSERRAT_18`).
- **2026-06-08:** **Boot sound before splash** — `audio_init` + `boot_sound` (`snd_up`) moved from post-`system_task_spawn` to immediately before `ui_boot_screen`; user hears MP3 as splash/backlight appear, not after heavy init/dashboard arm.

- **2026-06-07:** **SDIO cold-boot COM6-UART / P4-only** — root: (1) WLAN_PWR anchor at display_init **fully consumed** before `esp_wifi_init`; GPIO15 reset inside esp_hosted **reboots C6** but first probe had no post-reset re-wait; (2) P4-only reboot leaves C6 running from prior session; (3) user flashed **wrong tree** (`Modulus Firmware` → checksum mismatch); (4) COM6 UART attached masks race (queue drops) — fix must work UART disconnected. Fix: `tab5_pi4ioe_cycle_wlan_pwr()` re-anchors timer; wait before **every** SDIO probe (`C6 SDIO: wait N ms (anchor=X elapsed=Y required=Z)`); `note_c6_reset()` after failed init + full **5500 ms** retry; SD mount deferred; boot order sensors→power→ext_encoder→**wireless_restore** last; esp_hosted 2.11.4 log at init. Dual flash: `flash_tab5_dual.ps1 -C6Port COM6 -P4Port COM5`. Flash **this workspace** only — scripts print absolute path + ELF SHA256.

| Setting | Value |
|---|---|
| `CONFIG_MODULUS_C6_BOOT_DELAY_MS` | 5500 |
| `CONFIG_ESP_HOSTED_SDIO_RESET_DELAY_MS` | 5500 |
| `CONFIG_ESP_HOSTED_SDIO_RESET_ACTIVE_HIGH` | y |

**Boot timeline (after fix):** display_init WLAN_PWR (~2.3 s) → sensors + power + ext_encoder → wireless: **WLAN_PWR cycle** (fresh anchor) → `C6 SDIO: wait 5500 ms` → `esp_wifi_init` → GPIO15 reset → 5500 ms esp_hosted delay → SDIO probe → `wireless_shim: Wireless ready`. COM6 UART not required.

- **2026-06-07:** **SDIO cold-boot anchor (ref Modulus Zig → port)** — timer starts at first WLAN_PWR in `tab5_pi4ioe` init_expander2 (display_init); `wireless_shim` calls `tab5_pi4ioe_wait_c6_sdio_ready()` (remainder only, not full 4000 ms from wlan); `s_transport_up` on `esp_wifi_start`. Boot order unchanged: sync sensor hooks before `wireless_restore`; I2C0 Port A fix retained.

| Phase | Reference | Port (this repo) |
|-------|-----------|------------------|
| WLAN_PWR + timer anchor | `modulus_hal.c` → `modulus_hal_ioe_note_wlan_pwr_on()` after BSP expander | `display_shim` → `tab5_pi4ioe_init` → `init_expander2` → `tab5_pi4ioe_note_wlan_pwr_on()` |
| Sensor I2C before SDIO | `sensors_post` task → EventGroup → `wlan_post` | `boot.zig`: audio/battery/rtc/imu hooks before `wireless_restore` |
| SDIO wait | `modulus_hal_ioe_wait_c6_sdio_ready()` in `modulus_wifi_init` | `tab5_pi4ioe_wait_c6_sdio_ready()` in `modulus_wireless_init` |
| Transport up flag | `s_transport_up` in `modulus_wifi_hosted.c` | `s_transport_up` in `wireless_shim.c` |
| C6 delay config | `CONFIG_MODULUS_C6_BOOT_DELAY_MS=3500` (ref) / 4000 (port) | `sdkconfig.defaults` + Kconfig anchor help |

- **2026-06-07:** **C6 slave handlers linked (13d415cb, ESP-Hosted 2.11.4)** — reflash order COM6 then COM5; verified wireless_shim: Wireless ready, WiFi STA started (remote via C6) on COM5 monitor.

- **2026-06-07:** **C6 wireless Phase 6 complete (code)** — P4: `wireless_shim.c` WiFi scan/connect/status + `wireless_shim_espnow.c` SDIO ch8; `rtc_shim.c` SNTP on GOT_IP; `ui_settings_wireless.c` live hub (change-gated 1 s timer); CNC tab ESP-NOW peer read-only; Zig `idf_wireless.zig` + `hooks.zig` `modulus_wireless_restore_settings`. C6: `espnow_handler.c`/`zigbee_handler.c`/`thread_handler.c` in CMake + `esp_hosted_coprocessor.c` dispatch; `esp_hosted_interface.h` +`ESP_ESPNOW_IF`/`ZIGBEE`/`THREAD` (host+C6); OpenThread sdkconfig.defaults. **Partial/deferred:** BLE NimBLE RPC, Zigbee steering/join RPC, Thread QR attach wizard, ESP-NOW transport dispatcher. **ABI epoch 14** unchanged. C6 reflash if slave changed: `scripts/build_tab5_c6.ps1 -Flash -Port COM6`.

- **2026-06-07:** **Wireless settings Phase 7 (BLE/Zigbee/Thread UI + RPC 12298)** — `ui_settings_wireless.c`: Bluetooth hub (status hero, NVS `bt` toggle, paired list shell, scan stub, Advanced coming-soon); Zigbee/Thread partial hubs (radio toggle, join/leave or attach/detach honest stubs, Advanced stubs). `ble_transport_shim.c`: settings API (enable/disable/scan empty/log). `wireless_shim.c`: defer `esp_wifi_start` until wifi/espnow enabled; `wireless_prime_sta_config()` before start. **RPC 12298** = `Resp_WifiConnect` / `ESP_ERR_WIFI_SSID` from esp_hosted auto-connect on `STA_START` with empty SSID — fixed by not starting WiFi stack at boot unless NVS `wifi`/`espnow` on. **ABI 14** unchanged.

## Tab5 hardware wiring audit (2026-06-07)

Constants: `firmware/tab5/components/modulus_zig/include/tab5_hw.h`. PI4IOE: `tab5_pi4ioe.c` (ported from C++ BSP fork).

### PI4IOE1 @ 0x43 (E1) — user pin map

| Pin | Signal | Code path | Status |
|-----|--------|-------------|--------|
| P0 | RF_PTH_L_INT_H_EXT | `wireless_shim.c` → `tab5_pi4ioe_set_ext_antenna_enable` | **PASS** |
| P1 | NS4150B SPK_EN | `tab5_pi4ioe_init` OUT high + `audio_shim` `tab5_pi4ioe_set_spk_en(true)` | **PASS** |
| P2 | EXT5V_EN | `power_shim.c` → `tab5_pi4ioe_set_ext_5v_en` | **PASS** |
| P3 | (unused) | init OUT low | **PASS** |
| P4 | LCD_RST | `init_expander1` OUT high (deassert); C++ no pulse in `hal_display` | **PASS** |
| P5 | TP_RST | same as P4 | **PASS** |
| P6 | CAM_RST | same as P4 | **PASS** |
| P7 | HP_DET (input) | `tab5_pi4ioe_get_headphone_detect` → `modulus_audio_headphone_inserted` | **PASS** |

Boot: `display_shim` → `bsp_i2c_init` → `tab5_pi4ioe_init` (E1+E2) before `bsp_display_start_with_config`.

| Device | Code path | Addr / bus / pin | Status |
|--------|-----------|------------------|--------|
| ES8388 | `audio_shim.c` → BSP `bsp_audio_codec_*` | 0x10, I2C SCL32/SDA31 | **PASS** |
| ES7210 | `audio_shim.c` → BSP mic codec | 0x40, same I2C | **PASS** |
| GT911 / ST7123 | `display_shim.c` → `bsp_display_start_with_config` | 0x14 / 0x55, BSP auto-detect | **PASS** |
| BMI270 | `imu_shim.c` → `espressif/bmi270` | 0x68, M-Bus I2C | **PASS** (deferred init) |
| RX8130CE | `rtc_shim.c` + `rx8130.c` | 0x32, M-Bus I2C | **PASS** |
| INA226 | `battery_shim.c` | 0x41, M-Bus I2C | **PASS** |
| PI4IOE1 | `tab5_pi4ioe.c` | 0x43 | **PASS** (display init) |
| PI4IOE2 | `tab5_pi4ioe.c` | 0x44 | **PASS** |
| WLAN_PWR_EN | `tab5_pi4ioe.c` init_expander2 + `wireless_shim` ensure | E2.P0 | **PASS** (timer anchored at first assert) |
| EXT5V_EN | `power_shim.c` → E1.P2 | PI4IOE1 P2 (C++ ref; user table said E2 — **C++ wins**) | **PASS** |
| USB5V_EN | `power_shim.c` → E2.P3 | PI4IOE2 P3 | **PASS** |
| PWROFF_PULSE | `power_shim.c` shutdown → E2.P4 | PI4IOE2 P4 x3 | **PASS** (was deep-sleep fallback) |
| RF antenna | `wireless_shim.c` → E1.P0 | low=int, high=ext MMCX | **PASS** (was NVS-only) |
| CHG_EN / nCHG_QC | `tab5_pi4ioe.c` boot + Power tab | E2.P7 / E2.P5 | **PASS** |
| SIT3088 RS-485 | `serial_shim.c` | UART1 TX20/RX21/DE34 | **PASS** |
| SDIO2 C6 | esp_hosted sdkconfig | CLK12 CMD13 D0-11 D1-10 D2-9 D3-8 RST15 | **PASS** |
| SD card | `storage_shim.c` | SDMMC GPIO 39-44 | **PASS** |
| PMS150G wakeup | `wakeup_shim.c` + `rx8130_set_timer_irq` + `imu_shim` bmi2 any-motion | BMI270 INT1→E_TRG **code done** (swarm B); device verify open |
| M5-Bus / HY2.0 | `mbus_shim.c` Port A scan + map | **PASS** (rear = M-Bus alias) |
| I2C scanner UI | Storage tab async scan + device names | **PASS** |

**Boot order fix:** `display_shim` → `bsp_i2c_init` → `tab5_pi4ioe_init` (WLAN_PWR + C6 timer anchor, charge QC/EN) → BSP display; `boot.zig` sensors + `power_init` + `ext_encoder_init` before `wireless_restore` (C6 SDIO last); `wireless_shim` cycles WLAN_PWR + `tab5_pi4ioe_wait_c6_sdio_ready()` before each probe; SD mount deferred.

**Bug/Bloat/Fix (PI4IOE):** Bug = registry BSP 1.2 lacked `bsp_set_ext_5v_en` / PMIC / antenna / HP_DET → power shutdown fell back to deep sleep, rails/antenna NVS-only, headphone detect unreachable. Bloat = stub `bsp_set_*` no-ops in `power_shim.c`. Fix = `tab5_pi4ioe.c` from C++ fork; E1 pin map in `tab5_hw.h`; Settings Power/Wireless toggles call hardware; `modulus_audio_headphone_inserted` reads E1.P7; shutdown restores PMIC pulse sequence.

- **2026-06-07:** **Alt transport shim IDF fix** — `wireless_shim.c` `-Wformat-truncation` (`%.28s`/`%.32s`); `i2c_transport_shim.c` Port A `I2C_NUM_1` GPIO53/54 (not missing `bsp_ext_i2c_*`); `tab5_pi4ioe.c` in CMake; `espnow_transport_shim.c` stub (no `esp_now_*` on P4 remote). `zig build test` + `tab5-lib` + `check_ui_ascii` + `idf.py build` PASS; app **0x26ec30** (19% factory free).

- **2026-06-07:** **74587f2f backlog verify** - PMS150G/M5-Bus/envelope/C6-4000/i18n-partial TODO marked; `zig build test` + `tab5-lib` + `check_ui_ascii` + `idf.py build` PASS; COM5 flash PASS app **0x27a590**; monitor 30s: C6 delay 4000 OK, mbus shim OK (Port A I2C fail), wireless **FAIL** (`esp_wifi_init`).

| Transport | Device |
|-----------|--------|
| RS-485 / Serial USB | Live |
| WebSocket / Telnet | Live (needs WiFi IP) |
| ESP-NOW / I2C / CAN | Live (ESP-NOW dispatcher + peer editor — swarm A) |
| BLE HID | **Live** (NimBLE RPC + CNC transport; bond list partial) |
| USB HID / Gamepad | N/A |

- **2026-06-07:** **Battery status bar + Power tab** — `detect_charge_state` uses PI4IOE CHG_STAT (IP2326 E2.P6) + INA226 V/I per C++ `hal_battery.cpp`; boot prime sample; Power tab 2 s live hero; icon API `charge_state` tiers. **ABI 14** unchanged. `zig build test` + `tab5-lib` + `check_ui_ascii` + `idf.py build` PASS; app **0x27a590**.

- **2026-06-07:** **6306bed6 COM5 verify** - post COM6+COM5 flash, RTS COM5 48s: I2C bus-id collision clear; wireless FAIL SDIO 0x107/sdmmc_card_init → esp_wifi_init ESP_FAIL (no Wireless ready/WiFi STA); user full Tab5 power-cycle + COM6 BOOT-held reflash.
- **2026-06-07:** **947512d7 COM5 cold boot** - P4 0x27a640 WLAN_PWR timer anchor OK (noted, C6 SDIO: wait 2893 ms); **FAIL** first SDIO still 0x107 / card init failed, no Wireless ready; C6 **74961f32** modulus script on COM6 still required (not re-run here).
- **2026-06-07:** **MEMORY TODO refresh** — backlog reorganized (§1 Verify / §2 UI-HAL / §3 Firmware; infra folded into Done); baseline P4 **0x270fb0** (19% free), C6 2.11.4 **0x1817a0**; marked SDIO anchor, PI4IOE audit, I2C0 Port A, wireless hub, BLE/Zig/Thread partial UI, alt transports done; open: combined soak, RS-485 E2E, BLE RPC, ESP-NOW dispatcher, i18n, BMI270 INT, OTA; FAN/single-step driver done (field verify open).
- **2026-06-07:** **375cbc2d COM5 verify** - RPC 12298 fix + BLE/Zig/Thread UI; zig build tab5-lib + idf.py build PASS app **0x27b530**; COM5 flash (COM6 unchanged); RTS cold boot 52s default NVS (Wi-Fi/ESP-NOW off): **PASS** Wireless ready @9.3s, Coprocessor Boot-up, no `rpc_rsp 12298` / ESP_ERR_WIFI_SSID / STA_START; dashboard OK.
- **2026-06-07:** **FAN + single-step grblHAL cmds** — `cmdFanToggle`/`cmdSingleStep` send grblHAL RT bytes `0x8A` (FAN0_TOGGLE) / `0x89` (SINGLE_STEP_TOGGLE) when session ready; added `rt.zig`/`cmd.zig`/`engine.zig` builders + driver tests. Quick-btn FAN UI already wired; single-step ABI export only (no dashboard tile). **ABI epoch 14** unchanged. Field verify open on real controller.
- **2026-06-07:** **Swarm A/B/C backlog attempt** — streams [wireless RPC](7e907712-1de9-45ff-8e2a-34cca56ee4c9), [power/wake](24d5e617-2c53-42ac-8a87-4944f1b4bb66), [UI soak](5d8aa32d-acaa-4c03-80e6-5ccde373785b) launched; **tree inspection: no substantive diff landed** (git uncommitted). Honest status: quick settings scrim **done** in `ui_quick_settings.c`; WiFi connect/NVS **partial** (field E2E open); BLE/ESP-NOW/Zig-Thread RPC **open**; BMI270 poll-only **partial**; OTA coming-soon **open**; PIN/sleep/restart wired **partial** (device verify open); baseline P4 **0x27b530** unchanged (~17% free).
- **2026-06-07:** **Swarm A/B/C complete** — streams 7e907712 / 24d5e617 / 5d8aa32d finished. **A (wireless):** WiFi credentials E2E code done (field STA verify open — WiFi NVS off on default cold boot); BLE NimBLE RPC + CNC transport done (bond list partial); ESP-NOW dispatcher + peer editor done; Zigbee/Thread RPC partial (no full wizard). **B (power/wake):** BMI270 any-motion→E_TRG code done (bmi2 patch; device verify open); PIN lock/deep-sleep/restart partial (`pin_tmo` fix done); RS-485 code + soak checklist (field motion open). **C (UI soak):** quick settings scrim **58 s idle WDT PASS**; COM5 flash PASS + `Wireless ready`; OTA honest stub PASS; partition headroom **WARNING** 0x2a0ff0 87.6% used; WiFi STA field verify partial. **Build:** P4 **0x2a0ff0** (~12% free, CRITICAL); C6 2.11.4 unchanged; BMI270 patch + esp_hosted includes fixed. `zig build test` + `tab5-lib` + `idf.py build` green.
- **2026-06-07:** **Power settings tab** — C++ parity: discrete dim/scr/ds dropdowns, wake bitmask (touch/USB/timer), sleep gates NVS, bat warn dropdown wired to HAL, per-leaf disabled opa, scroll-pause battery timer, full reset defaults. ABI 14 unchanged.
- **2026-06-07:** **Machine settings tab** — C++ parity: work-envelope sliders (feed/RPM/jog/overrides), mach_type NVS, u32 maint counters + full reset, GrblHAL ref; defaults aligned (jog 1000, spcw on, name "My CNC"). ABI 14 unchanged.
- **2026-06-07:** **Audio & Haptics settings tab** — extracted `ui_settings_tab_audio.c`; C++ parity (tone_prof NVS in shim, vol `%` label + change-gate, mic/tone clamp); static tab, no timers. Haptics/AEC tuning out-of-scope. ABI 14 unchanged.
- **2026-06-07:** **UI tone profiles 0–3** — `k_tone_sets` in `audio_shim.c` aligned to spec (waveform/freq/duration/sweep); POP exp decay profile 0 only; Settings dropdown Standard/Soft/Crisp/Industrial; P4 **0x2a4600** ELF `a5ce7511ea03a1a516f11564051c1ad09c231eeb133851da5e2d52247f0a6749` COM5 flash PASS.
- **2026-06-07:** **Display & Themes settings tab** — extracted `ui_settings_tab_display.c`; accent NVS drives M3 palette (9 themes), glove touch via `touch_shim.c`, lefty layout live, `refr_hz` 60/30/20 Hz aligned to C++; full display reset. ABI 14 unchanged.
- **2026-06-07:** **Combined flash soak (2 cycles)** — builds green (`zig build test`, `tab5-lib`, C6 2.11.4 **0x1817a0**, P4 **0x2a1070** 87.6%); cycle 1 COM6 flash retry PASS → COM5 PASS → 60 s COM5 idle **PASS** (`WLAN_PWR_EN`, `Card init success`, `Wireless ready`, ELF `87970e6fa`, zero WDT); cycle 2 COM6 **FAIL** (no serial data ×2) → COM5 PASS → 60 s idle WDT OK but **wireless FAIL** (SDIO 0x107, `esp_wifi_init` ESP_FAIL, ELF `790a3a1d8`); settings walk not automated. Logs: `docs/verify/soak_cycle1_com5_2026-06-07.log`, `soak_cycle2_com5_2026-06-07.log`.
- **2026-06-07:** **Dashboard & Handwheel settings tab** — extracted `ui_settings_tab_dashboard.c`; `modulus_ui_dashboard_config_changed()` live-wires jog/DRO/quick/status; fixed `cnc_axes` AxesPreset NVS schema; ABI 14 unchanged; P4 **0x2a5590** ELF `de8d7e00c` COM5 flash PASS.
- **2026-06-07:** **Wireless submenus audit** — Wi-Fi/BT/ESP-NOW/Zigbee/Thread: async BLE scan, connect-modal back-nav, 1 s timers stop on leave, 802.15.4 GET_STATE poll; P4 **0x2a6a30** ELF `7f543f3ec` COM5 flash PASS (12% factory free).
- **2026-06-07:** **Full system audit** — P0/P1 pass, zero code fixes (prior tab passes cover change-gate LVGL, timer lifecycle, ABI 14, INA226, wireless/CNC/security). Partition **88.4%** (`0x2a6b50`); trim candidates documented. `zig build test` + `tab5-lib` + `idf.py build` PASS; ELF `ed6fa02b3a9b587cfb7dd18299b079a19abf848f248540039f718190e0673bb1`; COM5 flash PASS (verify-only, no sector change).
- **2026-06-07:** **Audio hiss/snow + ~10s pop fix** — root: [aaad98e7] `spk_prepare_ui_output()` unmuted ES8388 per UI tone but never re-muted; `esp_codec_dev_close` alone left amp hot (`disable_when_closed=false`) → idle snow; full I2S close/reopen every TICK → button-press distortion. No 10 s periodic timer touches audio — `play_mp3` 10 s watchdog is one-shot post-boot; perceived ~10 s = boot MP3 tail or watchdog stop pop. Fix: `spk_release_output()` (mute+close), format cache in `spk_open_format`, release after UI tone/MP3/stop; init ends muted. **ABI 14** unchanged. P4 **0x29df30** ELF `a9be909525b5cd0ce9b6a48a41d85fb1f1c89139331e2f0e352054afdc387e3b` COM5 flash PASS.
- **2026-06-08:** **Boot log noise triage (root-cause)** — (5) `i2s_channel_disable: not enabled` root: `esp_codec_dev_close` always disables the shared I2S TX (ignores `disable_when_closed`); next open's `set_fmt` pre-disables it → ERROR (+amp churn). Close never powered amp down (`disable_when_closed=false`), so `spk_release_output()` now **mute-only, keep codec open**; boot MP3 + UI tones both 48 kHz → reused, zero churn (one benign disable only on 44.1 kHz shutdown sfx reopen). (4) ext_encoder absent-on-Port-A i2c ERROR storm root: 2 s probe of floating Grove bus times out → IDF `i2c.master` ERROR + `clear bus failed`; fix back-off (3 fast probes → 30 s slow), scope-silence `i2c.master` only across the probe (coex lock held, Port A is I2C0 separate from internal I2C1 so battery/RTC unaffected), log absent once at INFO. (1) st7123 36h + (2) i2s dma_frame_num 240→256: benign 3rd-party BSP logs, not our code (BSP `bsp_audio_init` hardcodes `I2S_CHANNEL_DEFAULT_CONFIG`), not forkable cleanly — left as-is. (3) `H_SDIO_DRV Reset slave GPIO[15]`: expected working SDIO path — left. Files: `audio_shim.c`, `ext_encoder_shim.c`. **ABI 14** unchanged. P4 **0x29e060** (87.2% factory) ELF `d4c2fa83f33ee32d0968e633551fbe4fe782ed10ebd237e33c48ca1b3c377dde` COM5 flash PASS.
- **2026-06-08:** **Zigbee/Thread wireless settings (802.15.4 device layer)** — P4: `wireless_shim_802154.c` NVS schema (`zb_n`, `zb{i}_id/nm/ep/on`, `th_n`, `th{i}_id/nm/on`); promiscuous Zigbee scan via `ZIGBEE_CMD_SET_PROMISCUOUS` + `EVT_RX_FRAME` parse; Thread refresh via `GET_STATE` (join events wired, C6 not emitting yet); install-code + manual-add keyboard modals; saved-device ON/OFF (Zigbee `CMD_TX_FRAME` placeholder; Thread cache-only). `wireless_shim.c`: SDIO prereq on radio enable; scan stop on disable/leave. UI: discovery list change-gated rebuild, error beeps on failure. **ABI 14** unchanged. **C6 reflash not required** for P4-only layer; raw Zigbee scan needs Thread detached on current OT+C6 slave. P4 **0x2c6da0** (92.6% factory) ELF `8ea0396f185468ef0468841c5a589284c57d94bcf1a8c7deb3828493bcb68223` build PASS. **TODO:** esp-zb `CONFIG_MODULUS_C6_ZIGBEE_EXCLUSIVE` reflash for real join/steering; Thread operational-dataset QR; Matter bridge for Thread ON/OFF; ZCL frame builder on C6 RPC.
- **2026-06-20:** **tab5-lib Zig 0.16 freestanding unblock** — root cause: `zig build tab5-lib` failed silently during `flash_tab5.ps1` (stale `libmodulus_zig_core.a` flashed). Fixes: new `tab5_root.zig` (`page_size_min` 4096, `queryPageSize`, `networking=false`, `Io.failing` debug_io); `build.zig` tab5 module → `tab5_root.zig` + `single_threaded`; `monotonic_ms` `@divTrunc`; `idf_battery` `@enumFromInt`; `display` module-level `lockHw`/`applyTimeouts`; `deferred_connect` epoch/handle types; `ui_shim.c` `CONFIG_LV_USE_CLIB_MALLOC` guard. **ABI 14** unchanged. `zig build tab5-lib` + `zig build test` green.
- **2026-06-20:** **C6 espnow_handler compile fix** — `s_bcast_mac` used before declare in `espnow_probe_end_cleanup`; moved statics to file top. Dual flash COM6→COM5 PASS (`network_adapter` **0x182440**).
- **2026-06-20:** **P4 flash marathon (COM5)** — multiple builds/flashes; latest **0x2a0c20** ELF `e7c39a0d…` (~47% factory free @ 5 MB). Recurring COM5 **Access is denied** when monitor open — flash-only retry after close monitor.
- **2026-07-03:** **MEMORY sync (morning)** — ABI **18** (`settings_dump_copy` direct-to-caller buffer + 2048 B serial RX); `protocol_engine.zig` LinuxCNC/Mach3; ext_encoder Zig split; UI shim splits (102 `.c`); `gen_ui_palettes.py`; **175** host tests; P4 **0x2aa4c0**. Stale 3 MB partition table on old flashes — reflash `partitions.csv` when app > 3 MB.
- **2026-07-03:** **MEMORY re-sync (afternoon)** — P4 ELF `ad4f5151…` (bin still **0x2aa4c0**); workspace C6 **0x192590** vs last dual-flash **0x182440**; Open TODO: LinuxCNC/Mach3 field + `wireless_shim.c` 1052L debt; settings/wireless UI split marked done; CBM `fast` index PASS; `zig build test` green.
- **2026-07-04:** **MEMORY re-sync** — `zig build test --summary all` **175/175** PASS; ABI **18** unchanged; `wireless_shim.c` **953L** (was 1052L); C6 workspace **0x192590** (ZigbeeExclusive/ZBOSS hub); git untracked; `evolver run` cycle completed.
- **2026-07-04:** **C6 build policy + fix catalog** — documented canonical path `build_tab5_c6_modulus.ps1 -ZigbeeExclusive`; mirror injection pipeline; 20-item issue/fix table (SDIO 0x107, GPIO15 reset, ESP-NOW 0x01/PM/channel lock, ZBOSS partitions, permit-join security, handler injection); **`flash_tab5_dual.ps1` now passes `-ZigbeeExclusive` by default** (`-NoZigbeeExclusive` opt-out).
- **2026-07-19:** **NanoH2 Zigbee hub (Zigbee OFF C6)** — root cause: C6 one radio → ESP-NOW drops when ZBOSS active. Fix: `firmware/nanoh2/` ZBOSS coordinator on ESP32-H2FH4S; framed UART **460800** Grove↔M5BUS (P4 GPIO6/7); P4 `zb_uart_host.c` + `wireless_c6_rpc.c`; C6 `zigbee_handler.c` stub `EVT_FAIL` 0x30; remove esp-zigbee from C6 deps; **`-ZigbeeExclusive` DEPRECATED**. Four-firmware flash policy.
- **2026-07-19 afternoon:** **NanoH2 harden + ESP-NOW rate** — permit-join TC (`zdo_permit_joining_req` + tc_significance); UART seq ACK/NAK + max payload **256**; `zb_devdb` **4603** entries + NVS `zbN_md`; hub_offline ~210 s; adaptive `en_rate` (default 24M); C6 SET_RATE / Thread off. Bins then: NanoH2 **0x95690** / P4 **0x2bd1f0** — superseded evening.
- **2026-07-19 evening:** **MEMORY re-sync** — `zb_automation` (NVS `zbN_auto` follow/inverse CNC OnOff) + UI cycle; `zb_devdb_data.c` linked (~373 KiB) → P4 **0x2fe0e0** ELF `60ab02fd…` (~60% factory); NanoH2 **0x96100** ELF `be8e69b1…`; Hackster draft noted; C6 still stale **0x192590** (needs non-ZigbeeExclusive rebuild); CBM re-index this workspace.
