---
name: root-cause-refactor
description: Root-cause analysis and radical refactor — no band-aids, delete bloat in fix scope, require Bug/Bloat/Fix summary on bug fixes and refactors.
---

# Root-Cause & Refactor

Project rule: `.cursor/rules/root-cause-refactor.mdc` (always on).

## When to use

- Bug reports and crash investigations
- Refactor or "clean up" requests
- Performance, race, or leak hunts
- Tech-debt passes (explicit user ask)

## Output template (required after fix/refactor)

- **The Bug:** root cause
- **The Bloat:** removed or simplified code
- **The Fix:** why the new code is correct and minimal

## Conflicts with Karpathy

Karpathy §3 limits drive-by edits. This skill **overrides** that for code on the causal fix path only. Unrelated dead code → mention, don't delete unless user expands scope.
