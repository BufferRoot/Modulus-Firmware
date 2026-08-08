---
name: zig-build
description: >-
  Build, test, and MCP tooling for Modulus Zig. Use when running zig build,
  configuring build.zig, setting up zig-mcp/ZLS, or validating Zig changes.
---

# Zig Build & Tooling

## Commands

```powershell
zig version
zig build
zig build test
zig build test -- --test-filter "partial name"
zig test src/foo.zig
zig fmt src/
zig ast-check src/main.zig
```

## Project layout (convention)

```
build.zig
build.zig.zon          # deps (if any)
src/modulus/           # application + host tests
test/
.zls.json              # ZLS workspace (zig_exe_path filled by setup script)
```

## ZLS + zig-mcp (recommended)

Requires **Zig 0.16+** on PATH. **ZLS** and **zig-mcp** are optional but improve diagnostics in Cursor.

### Lean MCP stack (zig-mcp + zigars)

Configured in `.cursor/mcp.json`:

| Server | Role |
|--------|------|
| `zig-mcp` | Primary — ZLS bridge, `zig build` / `zig test` (nzrsky) |
| `zigars` | Structured diagnostics, preview-first edits (`@zigars/mcp@0.2.0`) |

Refresh skills / prefetch zigars shim:

```powershell
.\scripts\setup_zig_mcp_stack.ps1 -PrefetchNpm
```

C++ reference skills: `cpp-pro`, `modern-c-programming` in `.agents/skills/`.

Not enabled (overlap or cost): `zignet`, `zig-language-intelligence` — see [zigars](https://mcpmarket.com/server/zigars).

### One-shot setup (Windows)

```powershell
.\scripts\setup_zls.ps1 -Build -BuildZigMcp -EnableMcp
```

| Step | Script / artifact |
|------|-------------------|
| Locate or build ZLS | `setup_zls.ps1` → `%LOCALAPPDATA%\zls` or PATH |
| Write workspace config | `.zls.json` (`zig_exe_path`, `build_on_save_step`: `test`) |
| Build zig-mcp | `-BuildZigMcp` → `%LOCALAPPDATA%\zig-mcp\zig-out\bin\zig-mcp.exe` |
| Enable MCP | `-EnableMcp` sets `"disabled": false` in `.cursor/mcp.json` |

**Restart Cursor** after enabling zig-mcp.

### Manual ZLS install (no compile)

1. Download **ZLS** release matching Zig 0.16: https://github.com/zigtools/zls/releases  
2. Add `zls.exe` to PATH (or place under `%LOCALAPPDATA%\zls\zig-out\bin\`).  
3. Run `.\scripts\setup_zls.ps1` (writes `zig_exe_path` into `.zls.json`).  
4. Build zig-mcp per section below; run `.\scripts\setup_zls.ps1 -EnableMcp`.

### Host vs device (Tab5 / ESP-IDF)

| Context | Zig target | ZLS notes |
|---------|------------|-----------|
| `zig build test` | Host native | Root `build.zig` + `src/modulus/` — full LSP |
| P4/C6 firmware objects | `freestanding` / `rv32` via CMake | Not in root `build.zig`; ZLS may not resolve IDF `@cImport` until a dedicated `check` target exists |

Espressif **RISC-V** toolchain is for firmware builds (`idf.py`), not for installing host `zig`.

### Build zig-mcp manually

```powershell
git clone https://github.com/nzrsky/zig-mcp.git "$env:LOCALAPPDATA\zig-mcp"
cd "$env:LOCALAPPDATA\zig-mcp"
zig build -Doptimize=ReleaseFast
```

Binary: `%LOCALAPPDATA%\zig-mcp\zig-out\bin\zig-mcp.exe`  
Project entry: `.cursor/mcp.json` → `zig-mcp` server (`disabled: true` until setup verifies ZLS).

### zig-mcp tools (when enabled)

| Tool | Purpose |
|------|---------|
| `zig_diagnostics` | Errors/warnings |
| `zig_test` | Run tests |
| `zig_build` | `zig build` with args |
| `zig_hover` / `zig_definition` | Symbol intel via ZLS |
| `zig_format` | `zig fmt` |

**Prefer zig-mcp** over raw shell for diagnostics and test runs once configured.

## Codebase-Memory (CBM) re-index

After large adds under `src/**/*.zig` or `firmware/**`:

```powershell
.\scripts\index_codebase.ps1              # moderate (default)
.\scripts\index_codebase.ps1 -Mode fast   # quick
.\scripts\index_codebase.ps1 -DryRun      # print CLI only
.\scripts\index_codebase.ps1 -Help
```

Optional after P4 firmware build:

```powershell
.\scripts\build_tab5.ps1 -IndexAfterBuild -IndexMode fast
```

Binary default: `%LOCALAPPDATA%\Programs\codebase-memory-mcp\codebase-memory-mcp.exe`  
Override: `$env:CBM_EXE`  
MCP tool: `index_repository` with `repo_path` = workspace root.

## CI

GitHub Actions: `.github/workflows/zig-test.yml` — `zig fmt --check src/` + `zig build test` on Ubuntu (Zig 0.16).

## Local verify

```powershell
zig fmt --check src/
zig build
zig build test
```
