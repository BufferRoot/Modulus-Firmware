# Project hooks

## This PC (global + project)

| Layer | File | Hooks |
|-------|------|-------|
| **Global** | `~/.cursor/hooks.json` | RTK `preToolUse`, Token Savior `postToolUse`, Evolver `sessionStart` / `afterFileEdit` / `stop` |
| **Project** | `.cursor/hooks.json` | `sessionStart` → `session-pipeline.ps1` (repo context) |

Global Evolver scripts live in `~/.cursor/hooks/`. Copies in this folder are for **portability** when cloning to another machine.

## Portable clone (no global hooks)

1. Copy `hooks.pipeline.template.json` → `.cursor/hooks.json` (adjust Token Savior python path).
2. Install: RTK (`rtk init -g`), Token Savior, Evolver, Node.
3. Reload Cursor.

## Verify

Cursor → Settings → Hooks → confirm events show green. Hooks output channel for errors.

## First commit

Evolver `stop` hook records outcomes from **git diff**. Run `git commit` at least once or session-end memory stays inactive.
