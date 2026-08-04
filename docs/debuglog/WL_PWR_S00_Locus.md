# WL-PWR-S00 Locus Decision Record

Date: 2026-08-04  
Packet: `docs/phases/Write_Lock_Post_Worker_Release.md`  
Tests: `WriteLockPostWorkerTests` (`scripts/swift-test.sh --filter WriteLockPostWorker`)

## Studio incident — run `641A3C68` (Ikiro.Studio, 2026-08-04)

| Question | Evidence |
| --- | --- |
| Worker terminal before silence? | **No.** Journal `answers[0].result.status` = `cancelled`, `finishedAt` = null. Events: only `run.status_changed → running` and `worker.status_changed → running`; no worker terminal or answer deltas. |
| `lastActivityAt` advancing? | Stuck at `2026-08-04T17:41:18Z` for ~19m until manual clear at `18:00:52Z`. |
| `repoDelta` captured? | **No** (`repoDelta: null`) — `runExecution` never reached post-worker settlement persist. |
| Git truth | Commits `d93bdeca`, `cf9126f5` landed ~10:39 PT (operator-verified). |
| Kill / clear | Manual cancel; journal `cancelled` but `phase` still `working` (stale phase on cooperative kill). |

**Studio locus: M2 (in-prompt stream never reached terminal outcome).** Run used `cursor_agent` / `default_chat` with **no `threadId`** (cold streaming path, not warm ACP). Commits can land while the worker stream is still open; coordinator never builds `WorkerRunOutcome`, so no post-worker path runs and the outer `run()` lock is never released.

## Hermetic tests on `main` (2026-08-04)

| Test | Result on `main` | Mechanism |
| --- | --- | --- |
| **T-M1** `testTM1_…` | **FAIL** | M1 — worker `.done` + proof `sleep 8`; run B still blocked while coordinator in proof. |
| **T-M2** `testTM2_InPromptHang…` | **PASS** | M2 — slow worker keeps lane; documents that hang is pre-terminal. |
| **T-M2 kill** `testTM2_KillDuringInPromptHang…` | **FAIL** | M2+M3 — cooperative kill stamps journal but flock stays held until coordinator exits. |
| **T-M3** `testTM3_KillAfterWorkerTerminal…` | **FAIL** | M3 — kill after worker terminal, during proof sleep; flock not freed. |
| **T-PROOF** | **PASS** | Proof works on today's synchronous path (regression guard for S01). |
| **T-PARK** | **PASS** | Vendor park already releases lock before return. |

## Decision gate

```text
NOT pure M2 — M1 and M3 are also proven in code/tests.
Studio primary outage class: M2 (warm / in-prompt hang).
Secondary / compounding: M1 (post-worker settlement holds lock), M3 (kill frees journal not flock).
```

### Implementation order

1. **WL-PWR-S02 (L2)** — external terminal must free flock (T-M2 kill, T-M3). Required regardless of L1.
2. **WL-PWR-L3 pivot** — warm stream abort / turn-complete / idle bound (Studio M2). **Do not** claim L1 fixes warm hang.
3. **WL-PWR-S01 (L1)** — early release after worker terminal + pre-release git snapshot (T-M1). Fixes proof/settlement starvation; necessary but not sufficient for Studio.

### Reject list check

- L1 as **sole** fix for Studio: **REJECTED** (M2 primary).
- L1 for post-worker path: **ACCEPTED** (T-M1 fails on `main`).
- Metadata-only kill freeing lane: **REJECTED** (T-M3 fails on `main`).

## Open from spike

- Cooperative kill leaves `phase: working` on run `641A3C68` — separate RLR-L3 hygiene; note for S02.
- Queued run `attempts: []` starvation (slice E) — follow-up packet; not proven hermetically in S00.
