---
name: karpathy-guidelines
description: Behavioral guidelines to reduce LLM coding mistakes — think first, simplicity, surgical edits, verifiable success criteria. From Andrej Karpathy via multica-ai/andrej-karpathy-skills.
license: MIT
---

# Karpathy Guidelines

Project rule: `.cursor/rules/karpathy-guidelines.mdc` (always on).

Source: https://github.com/multica-ai/andrej-karpathy-skills

## When to use

- Writing or reviewing any code in this repo
- Before large edits — surface assumptions and tradeoffs
- When diffs grow beyond the requested scope

## Four principles

1. **Think before coding** — explicit assumptions; ask when ambiguous
2. **Simplicity first** — minimum code; no speculative abstractions
3. **Surgical changes** — touch only what's required (unless root-cause refactor applies)
4. **Goal-driven execution** — tests and verify steps, not vague "make it work"

## Pair with

`.cursor/rules/root-cause-refactor.mdc` — for bugs, refactors, and tech-debt work.
