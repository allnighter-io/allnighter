# Phase 1 Run Log — GLM Code Review (CR-01–10)

Status: **Phase 1 complete (CR-07 gap); Phase 2 queued**
Updated: 2026-06-27

## Durable findings archive

Raw GLM output lives in `findings/` (gitignored). **Committed copies**:

| ID | Archive | Promoted |
| --- | --- | --- |
| CR-01 | [`triage/CR-01-findings.md`](triage/CR-01-findings.md) | RUNLOCK-S01, RUNLOCK-S02 |
| CR-02 | [`triage/CR-02-findings.md`](triage/CR-02-findings.md) | backlog (compaction marker brittleness) |
| CR-03 | [`triage/CR-03-findings.md`](triage/CR-03-findings.md) | backlog (allowlist content check) |
| CR-04 | [`triage/CR-04-findings.md`](triage/CR-04-findings.md) | [CHECK-S01](../sprint/checkrunner/CHECK-S01-minimal-subprocess-env.md) |
| CR-05 | [`triage/CR-05-findings.md`](triage/CR-05-findings.md) | [OC-S02](../sprint/opencode/OC-S02-serve-lifecycle-hardening.md) |
| CR-06 | [`triage/CR-06-findings.md`](triage/CR-06-findings.md) | backlog (runQueue liveness) |
| CR-07 | — | **re-run** (no findings file) |
| CR-08 | [`triage/CR-08-findings.md`](triage/CR-08-findings.md) | backlog (DriverConcurrencyGate) |
| CR-09 | [`triage/CR-09-findings.md`](triage/CR-09-findings.md) | backlog (timeline perf) |
| CR-10 | [`triage/CR-10-findings.md`](triage/CR-10-findings.md) | backlog (streaming write path) |

Next queue: [`phase2-hardening-queue.md`](phase2-hardening-queue.md) · [`follow-up-recommendations.md`](follow-up-recommendations.md)

## Dogfood learnings

| Learning | Resolution |
| --- | --- |
| Inlined sources work | `expand_cr_packet.py` mandatory |
| GLM produces useful findings even when slice fails | **Triage on findings file**, not slice JSON |
| Parallel batch hurt more than helped | **Default serial** (`PAIR_CR_PARALLEL=0`) |
| 10 min OpenCode timeout too aggressive for reasoning reviews | Packets → `stallTimeoutSeconds: 3600`; manifest timeout separate (OC path) |
| Check pass / slice fail (empty stream) | Worker may finish writing after timeout — re-run check before triage |
| Phantom P0 (TOCTOU) | **Rejected** in CR-01 final findings |
| Phantom symbol in packet | Auto symbols in expand |
| Findings gitignored | Copy to `triage/` on triage |
| CR-05 found the chair GLM sits in | Coordinator child-exit + pipe drain → OC-S02 |

## CR-04 triage (CheckRunner)

| Claim | Verdict | Sprint |
| --- | --- | --- |
| P0 full env → `/bin/sh -c` check (secret exfiltration) | **Promote** | CHECK-S01 |
| P0 arbitrary shell — trust boundary upstream | **Promote** (provenance doc) | CHECK-S03 backlog |
| P1 skipped GUI branch sets `exitCode: 0` | **Promote** | CHECK-S02 backlog |
| P1 nil exitCode spawn failure silent | Backlog | — |
| P2 tail char vs byte limit | Archive | — |

## CR-05 triage (OpenCodeServeCoordinator)

| Claim | Verdict | Sprint |
| --- | --- | --- |
| P0 `spawnedPID` never cleared on child exit | **Promote** | OC-S02 |
| P0 health trusts any :4096 2xx (no ownership) | **Promote** | OC-S02 |
| P1 loser waits 10s for failed spawn | **Promote** | OC-S02 |
| P1 Process handle discarded; no `stop()` | **Promote** | OC-S02 |
| P1 stdout/stderr pipes never drained | **Promote** | OC-S02 (explains silent hangs) |
| P2 port/URL drift, poll timing, CancellationError | Archive / fold into OC-S02 | — |

**Meta:** CR-05 is the most actionable Round 2 result — it explains serve contention,
zombie children, and misleading `healthCheckTimedOut` during parallel dogfood.

## CR-01 triage (final)

| Claim | Verdict | Sprint |
| --- | --- | --- |
| P0 TOCTOU waiter registration | **Rejected** — false alarm | — |
| P1 owner-token `release` | **Promote** | RUNLOCK-S01 |
| P1 symlink/case canonical key | **Promote** | RUNLOCK-S02 |
| P1 holder crash leaks key | Backlog | — |

## CR-02 / CR-03 (summary — see triage archives)

**CR-02:** F2 protected but `contains("compaction")` is brittle; empty-output-before-check can stall file-writing workers.

**CR-03:** Gate fail-closed; P1 = allowlist content not validated (`[""]` passes).

## Run status

| ID | Review | Verify | Notes |
| --- | --- | --- | --- |
| CR-01 | triaged | — | RUNLOCK-S01/S02 |
| CR-02 | triaged | pending | classifier backlog |
| CR-03 | triaged | pending | SliceGate backlog |
| CR-04 | triaged | pending | CHECK-S01 |
| CR-05 | triaged | pending | OC-S02 |
| CR-06–10 | triaged | partial | CR-07 missing; see phase2 queue |

## Phase 2

See [`phase2-hardening-queue.md`](phase2-hardening-queue.md) — CR-07, CR-11–32.
