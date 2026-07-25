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


### Team Run Receipt (TRR)

| Order | Doc | Status |
| --- | --- | --- |
| 1 | [TRR-S01 — artifact CLI](team-run-receipt/TRR-S01-artifact-cli.md) | **done** |
| 2 | [TRR-S01b — Floor open](team-run-receipt/TRR-S01b-floor-open.md) | **ready** |
| 3 | [TRR-S03 — artifact export](team-run-receipt/TRR-S03-artifact-export.md) | **ready** |
| 4 | [TRR-S01c — live paint](team-run-receipt/TRR-S01c-live-paint.md) | **ready** |
| 5 | [TRR-S00 — growth scorecard](team-run-receipt/TRR-S00-scorecard-wo.md) | **ready** |

SSOT: `docs/phases/Team_Run_Receipt.md`. Audit: [TRR-S01-audit.md](team-run-receipt/TRR-S01-audit.md).

### OpenCode driver (OC-S01)

| Order | Doc | Status |
| --- | --- | --- |
| 1 | [OC-S01a — extractor tests + fixture](opencode/OC-S01a-extractor-tests.md) | **done** |
| 2 | [OC-S01b — WorkerRunner extractor wire](opencode/OC-S01b-worker-runner.md) | ready (after 01a) |
| 3 | [OC-S01c — serve coordinator](opencode/OC-S01c-serve-coordinator.md) | ready (after 01b) |
| 4 | [OC-S01d — detector smoke + coordinator hook](opencode/OC-S01d-detector-smoke.md) | ready (after 01c) |

SSOT: `docs/phases/setup/OpenCode_CLI_Support.md`

Pair-programming loop (supervisor + hammer, stall/nudge): historical — the
slice-queue system (`Pair_Programming_Team.md`) was deleted outright at R-S09;
the PM↔dev unattended loop it prototyped now lives in
[`docs/phases/PM_Relay.md`](../PM_Relay.md).

### Pair programming (PPT) — historical, slice queue deleted (R-S09)

| Order | Doc | Status |
| --- | --- | --- |
| smoke | [PPT-smoke.json](pair/PPT-smoke.json) | ready |
| S01 | [PPT-S01 — packet + parser](pair/PPT-S01-packet-parser.md) | **done** |

SSOT was `docs/phases/Pair_Programming_Team.md` (deleted R-S09); superseded by
`docs/phases/PM_Relay.md`.

### RunWriteLock (from code review CR-01)

| Order | Doc | Status |
| --- | --- | --- |
| 1 | [RUNLOCK-S01 — owner-token release](runlock/RUNLOCK-S01-owner-token-release.md) | **ready** |
| 2 | [RUNLOCK-S02 — canonical key symlinks](runlock/RUNLOCK-S02-canonical-key-symlinks.md) | **ready** |

Source: [`code_review/triage/CR-01-findings.md`](../code_review/triage/CR-01-findings.md)

### CheckRunner (from code review CR-04)

| Order | Doc | Status |
| --- | --- | --- |
| 1 | [CHECK-S01 — minimal subprocess env](checkrunner/CHECK-S01-minimal-subprocess-env.md) | **ready** |

Source: [`code_review/triage/CR-04-findings.md`](../code_review/triage/CR-04-findings.md)

### OpenCode serve hardening (from code review CR-05)

| Order | Doc | Status |
| --- | --- | --- |
| 1 | [OC-S02 — serve lifecycle hardening](opencode/OC-S02-serve-lifecycle-hardening.md) | **ready** |

Source: [`code_review/triage/CR-05-findings.md`](../code_review/triage/CR-05-findings.md). Do before re-enabling parallel CR fan-out.

### Classifier (from code review CR-02)

| Order | Doc | Status |
| --- | --- | --- |
| 1 | [CLASS-S02 — infraBackoff ordering](classifier/CLASS-S02-infra-backoff-ordering.md) | **ready** |
| 2 | [CLASS-S03 — advisory check before empty stall](classifier/CLASS-S03-advisory-check-before-empty.md) | **ready** |

Source: [`planner-triage-verdict.md`](../code_review/planner-triage-verdict.md). **CLASS-S03 before re-running GLM reviews.**

### SliceGate (from code review CR-03)

| Order | Doc | Status |
| --- | --- | --- |
| 1 | [GATE-S01 — allowlist + check.method](slicegate/GATE-S01-allowlist-content.md) | **ready** |

### CheckRunner follow-up (from code review CR-04)

| Order | Doc | Status |
| --- | --- | --- |
| 2 | [CHECK-S02 — skipped exitCode](checkrunner/CHECK-S02-skipped-exitcode.md) | **ready** |

### Pair queue (from code review CR-06)

| Order | Doc | Status |
| --- | --- | --- |
| 1 | [QUEUE-S01 — compaction/backoff caps](queue/QUEUE-S01-compaction-backoff-caps.md) | **ready** |
| 2 | [QUEUE-S02 — mid-slice deadline](queue/QUEUE-S02-mid-slice-deadline.md) | **ready** |

### Driver spawn gate (from code review CR-08)

| Order | Doc | Status |
| --- | --- | --- |
| 1 | [DRIVER-S01 — cancel + timeout](spawn/DRIVER-S01-gate-cancel-timeout.md) | **ready** |

### Timeline (from code review CR-09)

| Order | Doc | Status |
| --- | --- | --- |
| 1 | [TIMELINE-S01 — read-clear perf](timeline/TIMELINE-S01-readclear-perf.md) | **ready** |

### Streaming (from code review CR-10)

| Order | Doc | Status |
| --- | --- | --- |
| 1 | [STREAM-S01 — newestSuffix O(n)](stream/STREAM-S01-newest-suffix-on.md) | **ready** |
| 2 | [STREAM-S02 — serializer reentrancy](stream/STREAM-S02-serializer-reentrant.md) | **ready** |

### Watchdog (from code review CR-07)

| Order | Doc | Status |
| --- | --- | --- |
| 1 | [WATCHDOG-S01 — slow GLM threshold](watchdog/WATCHDOG-S01-slow-glm-threshold.md) | **ready** |

### Phase 2 promotions (planner triage 2026-06-29)

| Order | Doc | Status | Source |
| --- | --- | --- | --- |
| 1 | [LOOPBACK-S01 — single-close stop](loopback/LOOPBACK-S01-single-close-stop.md) | **done** | CR-31/32 |
| 2 | [SUBPROCESS-S04 — stdin throwing write](subprocess/SUBPROCESS-S04-stdin-throwing-write.md) | **done** | CR-24 |
| 3 | [SUBPROCESS-S03 — cancel watchdog](subprocess/SUBPROCESS-S03-cancel-watchdog.md) | **done** | CR-20 |
| 4 | [PENDING-S01 — settle before transcript](pending/PENDING-S01-settle-before-transcript.md) | **done** | CR-23 |
| 5 | [CLASS-S04 — reviewVerify requires signal](classifier/CLASS-S04-reviewverify-requires-signal.md) | **done** | CR-15 |

Verdict: [`planner-triage-verdict-phase2.md`](../code_review/planner-triage-verdict-phase2.md)

**Suggested implement order:** LOOPBACK-S01 → SUBPROCESS-S04 → SUBPROCESS-S03 → OC-S02 → CLASS-S03 → DRIVER-S01 → QUEUE-S01/S02 → CHECK-S01 → GATE-S01 → PENDING-S01 → STREAM → TIMELINE → WATCHDOG → RUNLOCK → CLASS-S04 (when verify enabled).

## Creating a new work order

```text
docs/phases/sprint/<topic>/<SLICE-ID>-<short-name>.md
```

Add a row to this README. Link from the phase SSOT implementation section.
