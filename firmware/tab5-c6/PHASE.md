# Tab5 C6 slave firmware phase

P4 Zig UI (this repo’s `firmware/tab5`) is production path. RF stays on C6 via
ESP-Hosted SDIO2 (Tab5 pins CLK12 CMD13 D0–D3 RST15).

## Done on P4 host

- `c6_sdio_host` TX/RX + health counters (`stream_drop` / `queue_stall` / `pad_skip`)
- Zig System tab: C6 health chip + SDIO counter detail
- Wireless radios via `esp_wifi_remote` / hosted VHCI

## Remaining (multi-sprint)

1. Flash / own `firmware/tab5-c6` image matched to hosted 2.x + Tab5 pin map
2. Soak: Wi-Fi connect, ESP-NOW CNC, BLE, Thread/Zigbee as product needs
3. Document dual-flash procedure (P4 + C6) in operator guide

Scaffold tree already lives under `firmware/tab5-c6/` (ESP-Hosted slave example
+ Modulus C6 components). This file marks the phase boundary — not a claim that
slave bring-up is complete.
