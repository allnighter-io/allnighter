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

### Menu Not Router (MR-S01–S06) — archived Complete 2026-07-20

Sprint work orders moved to
[`docs/archive/phases/sprint/menu-not-router/`](../../archive/phases/sprint/menu-not-router/).
SSOT: archived [`Menu_Not_Router.md`](../../archive/phases/Menu_Not_Router.md).


### Design Lane (DL) — archived 2026-07-31

DL-S01–S03 all shipped; moved to
[`docs/archive/phases/sprint/design-lane/`](../../archive/phases/sprint/design-lane/).
SSOT: `docs/operations/Design_Lane.md`.

### Team Run Receipt (TRR)

| Order | Doc | Status |
| --- | --- | --- |
| 5 | [TRR-S00 — growth scorecard](team-run-receipt/TRR-S00-scorecard-wo.md) | **awaiting founder disposition** |

TRR-S01 / S01b / S03 / S01c + audits shipped and moved to
[`docs/archive/phases/sprint/team-run-receipt/`](../../archive/phases/sprint/team-run-receipt/).
SSOT (historical packet): archived `docs/archive/phases/Team_Run_Receipt.md`.
**Code SSOT:** `ArtifactProjector` / `ArtifactWriter` / `ArtifactCLI`.

### OpenCode driver (OC-S01)

| Order | Doc | Status |
| --- | --- | --- |
| 2 | [OC-S01b — WorkerRunner extractor wire](opencode/OC-S01b-worker-runner.md) | ready (after 01a) |
| 3 | [OC-S01c — serve coordinator](opencode/OC-S01c-serve-coordinator.md) | ready (after 01b) |
| 4 | [OC-S01d — detector smoke + coordinator hook](opencode/OC-S01d-detector-smoke.md) | ready (after 01c) |

OC-S01a shipped; moved to
[`docs/archive/phases/sprint/opencode/`](../../archive/phases/sprint/opencode/).
SSOT: `docs/phases/setup/OpenCode_CLI_Support.md`

Pair-programming loop (supervisor + hammer, stall/nudge): historical — the
slice-queue system (`Pair_Programming_Team.md`) was deleted outright at R-S09;
the PM↔dev unattended loop it prototyped shipped and archived as
[`PM_Relay.md`](../../archive/phases/PM_Relay.md) (current code SSOT:
`RelayCoordinator`, `PilotCLI`). Its PPT-smoke/PPT-S01 work orders shipped and
moved to
[`docs/archive/phases/sprint/pair/`](../../archive/phases/sprint/pair/).

### Code review triage batch (CR-01–CR-10) — all shipped, archived 2026-07-31

Every work order from this batch shipped, including two (CheckRunner/CR-04,
Streaming/CR-10) whose target subsystems were later deleted wholesale in
`686b3d10` (R-S09 slice-queue removal) — the fix logic itself was carried into
the replacement per that commit's message. All moved to
[`docs/archive/phases/sprint/`](../../archive/phases/sprint/) under their
topic folders: `runlock/` (CR-01), `classifier/` (CR-02, plus CLASS-S04 below),
`slicegate/` (CR-03), `checkrunner/` (CR-04), `opencode/OC-S02` (CR-05),
`queue/` (CR-06), `watchdog/` (CR-07), `spawn/` (CR-08), `timeline/` (CR-09),
`stream/` (CR-10).

Source: [`code_review/triage/`](../../archive/phases/code_review/triage/) `CR-01-findings.md` through `CR-10-findings.md` (that whole packet is archived).

### Phase 2 promotions (planner triage 2026-06-29) — all shipped, archived 2026-07-31

LOOPBACK-S01 (CR-31/32), SUBPROCESS-S04 (CR-24), SUBPROCESS-S03 (CR-20),
PENDING-S01 (CR-23), and CLASS-S04 (CR-15) all shipped; moved to
[`docs/archive/phases/sprint/`](../../archive/phases/sprint/) under their
respective topic folders.

Verdict: [`planner-triage-verdict-phase2.md`](../../archive/phases/code_review/planner-triage-verdict-phase2.md)

## Creating a new work order

```text
docs/phases/sprint/<topic>/<SLICE-ID>-<short-name>.md
```

Add a row to this README. Link from the phase SSOT implementation section.
