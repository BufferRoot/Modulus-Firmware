# RS-485 + grblHAL field soak checklist

Code-side gates (host `zig build test`) cover deferred connect, session FSM, status
snapshot, and command gating without a physical controller. This checklist is for
**on-bench soak with real grblHAL** over Tab5 RS-485 (SIT3088, UART1 TX20/RX21/DE34).

## Preconditions

- P4 image flashed after `zig build test`, `zig build tab5-lib`, `idf.py build`
- Settings: CNC connection = RS-485, auto-connect ON (11 s defer after boot)
- grblHAL controller powered, DE/termination matched to bench wiring
- Monitor ≥55 s idle dashboard (no IDLE0 WDT) before motion tests

## Boot / connect

- [ ] Cold boot: status bar grey/yellow until ~11 s, then green when session ready
- [ ] Serial log: deferred connect task, `$I`/`?` handshake, no transport spam before defer
- [ ] Disconnect controller: status OFFLINE, DRO holds last values, jog/cycle gated

## Status bar + DRO

- [ ] State pill tracks Idle/Run/Hold/Jog/Alarm from live `?` reports
- [ ] WCS pill matches controller (G54–G59)
- [ ] DRO WPos/MPos update at configured refresh (30–50 ms); no WDT under idle refresh
- [ ] Feed/spindle override pills reflect controller after `$I` defaults applied

## Command gating

- [ ] Cycle/Hold/Home disabled or no-op when disconnected (UI + no UART TX)
- [ ] Jog blocked when alarm or session not ready
- [ ] Power menu Reset CNC / Clear Alarm / E-Stop reach controller when connected
- [ ] PIN lock overlay blocks dashboard actions until unlock

## Motion (requires physical controller — do not jog without machine safe)

- [ ] Single-axis jog step + continuous (small distance, low feed)
- [ ] Feed hold during jog; cycle start from hold
- [ ] Spindle/coolant toggles if mapped on controller
- [ ] E-Stop from power menu: controller alarm, UI reflects ALARM

## Soak

- [ ] Idle dashboard ≥55 s (no WDT)
- [ ] Connected idle ≥30 min: DRO/status stable, no heap growth in log
- [ ] Repeated connect/disconnect (controller power cycle) ×10: session recovers

## Notes

- No motion verification possible in CI/host tests; mock UART only validates parser/session.
- BLE/Wi-Fi transports are out of scope for this RS-485 checklist.
