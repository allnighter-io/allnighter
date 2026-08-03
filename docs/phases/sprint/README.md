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

### Hygiene queue (doc truth + help fidelity — one slice per commit)

PM assigns **one** row at a time. Report Gemini context % after each slice; stop
delegating below 10%.

| Order | Doc | Status |
| --- | --- | --- |
| HY-S01 | [phases README vocab](hygiene/HY-S01-phases-readme-vocab.md) | **ready** ← start here |
| HY-S03 | [help loop step truth](hygiene/HY-S03-help-loop-step-truth.md) | ready (after S01) |
| HY-S04 | contract retired handoff summary (not yet written) | queued |
| HY-S05 | loop comment scrub Core (not yet written) | queued |

All other work orders are archived under
[`docs/archive/phases/sprint/`](../../archive/phases/sprint/).

### Founder-blocked (archived, not active engineering)

| Order | Doc | Status |
| --- | --- | --- |
| TRR-S00 | [Growth scorecard](../../archive/phases/sprint/team-run-receipt/TRR-S00-scorecard.md) | **awaiting founder disposition** — scaffold done; does not block product |

## Recently archived (2026-08-01 cleanup)

| Topic | Location | Notes |
| --- | --- | --- |
| Team Run Receipt TRR-S00 | `archive/phases/sprint/team-run-receipt/` | Founder disposition only; TRR-S01+ already archived |
| OpenCode OC-S01b–d | `archive/phases/sprint/opencode/` | Superseded by AgentOS HTTP driver (`OpenCodeServeClient`) |
| Menu Not Router MR-S01–S06 | `archive/phases/sprint/menu-not-router/` | Complete 2026-07-20 |
| Design Lane DL-S01–S03 | `archive/phases/sprint/design-lane/` | Complete 2026-07-31 |
| Code review CR-01–CR10 + phase 2 | `archive/phases/sprint/` topic folders | Complete 2026-07-31 |
| Pair-programming PPT | `archive/phases/sprint/pair/` | Historical — slice queue deleted R-S09 |

## Creating a new work order

```text
docs/phases/sprint/<topic>/<SLICE-ID>-<short-name>.md
```

Add a row to this README. Link from the phase SSOT implementation section.
