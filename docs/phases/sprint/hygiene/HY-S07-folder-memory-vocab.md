# HY-S07 — Folder_Native_Memory doc vocabulary

Status: ready
Owner: hygiene / doc truth
Updated: 2026-08-03

## Goal

Human-layer vocabulary in `docs/phases/Folder_Native_Memory.md` — relay/worker
in product prose, not machine wire keys.

## Copy-paste prompt

```text
Implement HY-S07 only.

Touch ONLY: docs/phases/Folder_Native_Memory.md

Human-layer replacements:
- "every relay is a cold read" → "every loop is a cold read" (or equivalent)
- vendor "worker succeed" in product prose → "agent" where it means staffed seat
- "relay prompts" → "loop prompts" if present

Do NOT change code references to RelayState, pair relay, or machine JSON keys.
Do NOT edit other files.

Sanity: rg 'relay|worker' on the file — remaining hits should be historical/machine only.

Commit:
git add docs/phases/Folder_Native_Memory.md
git commit -m "docs: Folder_Native_Memory loop/agent vocabulary"
```

## Works Test

Docs-only.
