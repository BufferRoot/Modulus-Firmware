# C6 Zig scaffold (ESP-Hosted slave)

Modulus Tab5 uses **two firmware images**: P4 host (`firmware/tab5/`) and C6 wireless slave (`firmware/tab5-c6/`). The C6 image is **not** merged into the P4 IDF target.

## Zig entry points

| Path | Role |
|------|------|
| `src/modulus/main_c6.zig` | Exported `modulus_c6_main()` — C shim calls this after SDIO/hosted bring-up |
| `src/modulus/hal/bridge_c6.zig` | Logging + thin C bridge helpers for C6 |
| `src/modulus/core/c6/boot.zig` | Minimal C6 boot loop (host scaffold) |

## IDF / CMake

- C6 project root: `firmware/tab5-c6/`
- Zig static lib component: `firmware/tab5-c6/components/modulus_zig_c6/`
- Hosted hook: `modulus_c6_hosted_hook.c` wires ESP-Hosted slave control into Modulus

Build is **CMake-only** for the C6 Zig artifact today — run the tab5-c6 IDF build, not `zig build` alone, for a flashable C6 binary.

## Phase status

**P4-only until C6 phase completes.** Wireless on Tab5 must stay on the C6 SDIO path (`esp_hosted` / `esp_wifi_remote`); do not init native Wi-Fi on P4.

## Flash

C6 is a separate flash procedure from P4. See `docs/hardware/tab5/esp-hosted-sdio.md` and M5 Tab5 software guides for co-processor update flow.
