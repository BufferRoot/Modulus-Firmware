# MMBP bridge for Mach3/Mach4

TCP text bridge matching Tab5 Mach3 client (`src/modulus/cnc/mach3/`).

```powershell
cd tools/mmbp_bridge
python mmbp_bridge.py --port 7878 --backend mock
```

Pendant: MCS **Mach3/Mach4**, Transport **Telnet**, host = PC IP, port **7878**.

| Backend | Notes |
|---------|--------|
| `mock` | In-process machine state — jog/status without Mach installed |
| `mach3` | Optional `pywin32` COM (`Mach4.Document` / Mach3) — install-specific |

Mach has no stable public network API; this bridge is the supported pendant path.
