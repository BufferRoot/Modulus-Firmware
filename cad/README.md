# CAD — Tab5 enclosure

Mechanical CAD and printable parts for the Modulus Tab5 pendant shell (covers, buttons, battery bay / wheel mount geometry).

**Source of truth:** `M5_TAB5_rev2.step`. Export STLs from this STEP when regenerating prints; do not treat screenshots as dimensional references.

## Print notes

| Parameter | Guidance |
|-----------|----------|
| Material | **ABS** or **ASA** (heat / UV resistance on pendant) |
| Orientation | Match mating faces; keep button travel axes vertical when possible |
| Fasteners | **6×** 15 mm socket screws |
| Fit | Dry-fit covers before final fasteners; leave clearance for Tab5 PCB and connectors |

## Inventory

### Source

| File | Role |
|------|------|
| `M5_TAB5_rev2.step` | Canonical CAD (STEP, rev2) |

### Printables (STL)

| File | Part |
|------|------|
| `Front Cover.stl` | Front cover |
| `BACK COVER.stl` | Rear cover |
| `Back Button.stl` | Rear button |
| `Side Button.stl` | Side button |

### Reference captures

Assembly / CAD screenshots for visual check only (filenames are export timestamps).

| File |
|------|
| `Screenshot 2026-08-07 214138.png` |
| `Screenshot 2026-08-07 214200.png` |
| `Screenshot 2026-08-07 214233.png` |
| `Screenshot 2026-08-07 214254.png` |
| `Screenshot 2026-08-07 214322.png` |
| `Screenshot 2026-08-07 214335.png` |

Wiring and interconnect: see [schematics/README.md](../schematics/README.md).
