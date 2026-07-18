# Planner Triage Verdict — Phase 1 Backlog (22 items)

Status: **complete**
Reviewer: Composer (planner) — no human in loop
Updated: 2026-06-28

## Pipeline (your model — correct)

```text
GLM review → findings.md → Planner triage (verify vs source + triage archive)
    → sprint work order when upheld → GLM/hammer implement
```

There is **no separate human review**. The planner must:

1. Read GLM evidence in `triage/CR-NN-findings.md`
2. Spot-check claims against inlined source (or repo read where bounded)
3. Reject phantoms, merge duplicates, defer items needing more GLM context
4. Author `docs/phases/sprint/*.md` for **promote** items only

Phase 2 GLM reviews (CR-11+) are **optional sharpening**, not a gate — planner can promote when evidence is already sufficient.

---

## Verdict summary

| Verdict | Count | Meaning |
| --- | --- | --- |
| **Already sprint** | 4 | RUNLOCK-S01/S02, CHECK-S01, OC-S02 |
| **Promote now** | 11 | Sprint doc authored this pass |
| **Defer (Phase 2 GLM first)** | 4 | Need CR-26 / CLASS-S01 / cross-file GLM |
| **Defer (lower priority)** | 3 | Real but small or hard; batch later |
| **Merge into promoted** | 0 | Merged into combined sprint docs |

---

## Item-by-item verdict

| # | Backlog ID | Source | Planner verdict | Sprint doc |
| --- | --- | --- | --- | --- |
| 1 | RUNLOCK-S03 | CR-01 | **Defer** — real (holder crash leaks key) but needs process watchdog / TTL design; not a one-screen slice | — |
| 2 | CLASS-S01 | CR-02 | **Defer** — needs CLI structured compaction contract; GLM CR-11/14 may inform; not a quick code-only fix | — |
| 3 | CLASS-S02 | CR-02 | **Promote** — verified: `isInfraBackoff` runs before `.done` check (`SliceTerminalClassifier.swift:32`) | [`CLASS-S02`](../sprint/classifier/CLASS-S02-infra-backoff-ordering.md) |
| 4 | CLASS-S03 | CR-02 | **Promote** — verified: empty `visible` → `.stalled` at `:42` before check at `:43-46`; breaks tool-only review | [`CLASS-S03`](../sprint/classifier/CLASS-S03-advisory-check-before-empty.md) |
| 5 | GATE-S01 | CR-03 | **Promote** — verified: `!touchAllowlist.isEmpty` at `:33` allows `[""]` | [`GATE-S01`](../sprint/slicegate/GATE-S01-allowlist-content.md) |
| 6 | GATE-S02 | CR-03 | **Promote** — merged into GATE-S01: `default: break` at `:41-42` | ↑ same doc |
| 7 | CHECK-S02 | CR-04 | **Promote** — verified: `.guiFixture` returns `exitCode: 0, skipped: true` (`CheckRunner.swift:57`) | [`CHECK-S02`](../sprint/checkrunner/CHECK-S02-skipped-exitcode.md) |
| 8 | CHECK-S03 | CR-04 | **Defer** — needs `CommandRunner` / subprocess path (CR-20 GLM); planner cannot fully verify | — |
| 9 | CHECK-S04 | CR-04 | **Defer** — policy/doc + packet provenance; no single-file bounded fix | — |
| 10 | QUEUE-S01 | CR-06 | **Promote** — verified: `executorAttempt -= 1` on `.compacting`/`.infraBackoff` (`PairCoordinator.swift:285,290`) with no cap | [`QUEUE-S01`](../sprint/queue/QUEUE-S01-compaction-backoff-caps.md) |
| 11 | QUEUE-S02 | CR-06 | **Promote** — verified: `until` only at outer loop `:188-191` | [`QUEUE-S02`](../sprint/queue/QUEUE-S02-mid-slice-deadline.md) |
| 12 | QUEUE-S03 | CR-06 | **Defer** — real; bundle with QUEUE-S02 in implementation or follow-on | — |
| 13 | QUEUE-S04 | CR-06 | **Defer** — metadata polish on escalate; lower than liveness | — |
| 14 | DRIVER-S01 | CR-08 | **Promote** — verified: `Never` continuation + no cancel drop (`DriverConcurrencyGate.swift:46`); no timeout | [`DRIVER-S01`](../sprint/spawn/DRIVER-S01-gate-cancel-timeout.md) |
| 15 | DRIVER-S02 | CR-08 | **Promote** — merged into DRIVER-S01 (acquire timeout) | ↑ same doc |
| 16 | DRIVER-S03 | CR-08 | **Defer** — `withPermit` throw-safety is future-proofing; `body` is non-throwing today | — |
| 17 | TIMELINE-S01 | CR-09 | **Promote** — GLM evidence strong; O(n²) + double `report()`; bounded fix in one file | [`TIMELINE-S01`](../sprint/timeline/TIMELINE-S01-readclear-perf.md) |
| 18 | TIMELINE-S02 | CR-09 | **Promote** — merged into TIMELINE-S01 | ↑ same doc |
| 19 | TIMELINE-S03 | CR-09 | **Promote** — merged into TIMELINE-S01 | ↑ same doc |
| 20 | TIMELINE-S04 | CR-09 | **Defer** — needs `ThreadTurn.Kind` enum (CR-26 GLM); planner deferred cross-file | — |
| 21 | STREAM-S01 | CR-10 | **Promote** — GLM complexity analysis plausible; hot path; bounded single file | [`STREAM-S01`](../sprint/stream/STREAM-S01-newest-suffix-on.md) |
| 22 | STREAM-S02 | CR-10 | **Promote** — verified: `queue.sync` with no reentrancy guard (`ThreadStoreWriteSerializer.swift:26`) | [`STREAM-S02`](../sprint/stream/STREAM-S02-serializer-reentrant.md) |
| 23 | WATCHDOG-S01 | CR-07 | **Promote** — verified: `workerChatSeconds = 30*60`; ignores `input.runs`; pair GLM risk | [`WATCHDOG-S01`](../sprint/watchdog/WATCHDOG-S01-slow-glm-threshold.md) |

*(22 backlog rows + STREAM-S02 counted in CR-10 triage = 23 lines; table includes all.)*

---

## Implementation priority (planner)

1. **OC-S02** — unblock GLM runner (already sprinted)
2. **CLASS-S03** — fix false `stalled` on successful review slices
3. **DRIVER-S01** — gate deadlocks / cancel
4. **QUEUE-S01/S02** — pair queue liveness
5. **CHECK-S01/S02** — subprocess safety
6. **GATE-S01** — packet gate hygiene
7. **STREAM-S01/S02** — streaming perf + deadlock
8. **TIMELINE-S01** — scroll jank
9. **WATCHDOG-S01** — false stall UX
10. **CLASS-S02** — classifier ordering nit
11. **RUNLOCK-S01/S02** — write lock

---

## Changelog

| Date | Change |
| --- | --- |
| 2026-06-28 | Initial planner triage of 22 backlog items; 11 new sprint docs |
