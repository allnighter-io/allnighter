# Sprint Work Orders

**For implementer agents (especially 32K-context models):** read **only** the
single sprint doc you were assigned. Do not read `AGENTS.md`, phase boards, or
the full driver SSOT unless the sprint doc links a specific section.

Phase docs (`docs/phases/…`) hold **law** — stable contracts. Sprint docs hold
**work orders** — one slice, explicit file allowlists, one proof command.

## When to use

| Situation | Read |
| --- | --- |
| Implement one bounded slice | **This folder** — one `*.md` work order |
| Understand full driver/feature contract | Phase SSOT (e.g. `setup/OpenCode_CLI_Support.md`) |
| Process, commits, deslop, audit | `docs/operations/Execution-Playbook.md` |

## Work order template

Each sprint file must fit on **one to two screens** and include:

1. **Goal** — one sentence
2. **Copy-paste prompt** — block for the implementer
3. **Read only** — ≤3 files (pattern references)
4. **Touch only** — explicit allowlist
5. **Do not read / do not touch**
6. **Steps** — numbered, 3–7 items
7. **Works Test** — one command
8. **Done when** — checkboxes
9. **SSOT link** — anchor into phase doc

## Rules

- **One slice = one session = one commit** (unless founder waives).
- **No scope creep.** If the slice needs another file, stop and open a new sprint doc.
- **Archive when done:** move to `docs/archive/phases/sprint/<topic>/`.
- **Status header** on each work order: `Status: ready | in_progress | done`.

## Active sprints

### OpenCode driver (OC-S01)

| Order | Doc | Status |
| --- | --- | --- |
| 1 | [OC-S01a — extractor tests + fixture](opencode/OC-S01a-extractor-tests.md) | **done** |
| 2 | [OC-S01b — WorkerRunner extractor wire](opencode/OC-S01b-worker-runner.md) | ready (after 01a) |
| 3 | [OC-S01c — serve coordinator](opencode/OC-S01c-serve-coordinator.md) | ready (after 01b) |
| 4 | [OC-S01d — detector smoke + coordinator hook](opencode/OC-S01d-detector-smoke.md) | ready (after 01c) |

SSOT: `docs/phases/setup/OpenCode_CLI_Support.md`

Pair-programming loop (supervisor + hammer, stall/nudge):
[`Pair_Programming_Team.md`](../Pair_Programming_Team.md)

### Pair programming (PPT)

| Order | Doc | Status |
| --- | --- | --- |
| smoke | [PPT-smoke.json](pair/PPT-smoke.json) | ready |
| S01 | [PPT-S01 — packet + parser](pair/PPT-S01-packet-parser.md) | **done** |

SSOT: `docs/phases/Pair_Programming_Team.md`

### RunWriteLock (from code review CR-01)

| Order | Doc | Status |
| --- | --- | --- |
| 1 | [RUNLOCK-S01 — owner-token release](runlock/RUNLOCK-S01-owner-token-release.md) | **ready** |
| 2 | [RUNLOCK-S02 — canonical key symlinks](runlock/RUNLOCK-S02-canonical-key-symlinks.md) | **ready** |

Source: [`code_review/triage/CR-01-findings.md`](../code_review/triage/CR-01-findings.md)

## Creating a new work order

```text
docs/phases/sprint/<topic>/<SLICE-ID>-<short-name>.md
```

Add a row to this README. Link from the phase SSOT implementation section.
