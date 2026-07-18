# Phase 2 — GLM Hardening Queue

Status: **active backlog**
Owner: Serial hardening pass program
Updated: 2026-06-27
SSOT playbook: [`docs/operations/GLM_Worker_Best_Practices.md`](../../operations/GLM_Worker_Best_Practices.md)

Phase 1 (CR-01–10) covered the **pair-programming control plane** and two hot GUI/engine
paths. It did **not** exhaust worth investigating. This doc is the next slice menu —
prioritized, bounded, ready for `packets/CR-NN.json` + `expand_cr_packet.py`.

**Rule:** one file or one function chunk per slice; inline sources; serial dispatch.

**Tracking:** [`follow-up-recommendations.md`](follow-up-recommendations.md) (all promotions/backlog) · [`phase2-runlog.md`](phase2-runlog.md) (dispatch status)

---

## Phase 1 completion

| ID | Target | Findings? | Top promoted insight |
| --- | --- | --- | --- |
| CR-01 | RunWriteLock | yes | RUNLOCK-S01/S02 (owner token, canonical key) |
| CR-02 | SliceTerminalClassifier | yes | Brittle compaction marker; empty-output-before-check |
| CR-03 | SliceGate | yes | `[""]` allowlist passes; default check.method |
| CR-04 | CheckRunner | yes | CHECK-S01 (full env → check subprocess) |
| CR-05 | OpenCodeServeCoordinator | yes | OC-S02 (child exit, pipes, port ownership) |
| CR-06 | PairCoordinator.runQueue | yes | Unbounded compaction/infraBackoff; deadline mid-slice |
| CR-07 | StalledWorkDetector | **no** | Re-run — only Phase 1 gap |
| CR-08 | DriverConcurrencyGate | yes | Cancelled waiters still run; no acquire timeout |
| CR-09 | TimelineVisibility | yes | O(n²) read-clear; team-run kind gap |
| CR-10 | StreamingPartialBuffer + serializer | yes | O(n²) truncation hot path; reentrant deadlock |

---

## Priority tiers

### Tier A — finish Phase 1 + dogfood blockers (do first)

| ID | Target | Lines / scope | Why now |
| --- | --- | --- | --- |
| **CR-07** | [`StalledWorkDetector`](../tasks/CR-07-stalled-work-detector.md) | 1–77 | [CR-07.json](../packets/CR-07.json) |
| **CR-11** | [`WorkerRunner`](../tasks/CR-11-worker-runner-opencode.md) | 251–331 | [CR-11.json](../packets/CR-11.json) |
| **CR-14** | [`OpenCodeServeClient`](../tasks/CR-14-opencode-serve-client-stream.md) | full | [CR-14.json](../packets/CR-14.json) |
| **CR-15** | [`Classifier + advisory`](../tasks/CR-15-advisory-review-terminal.md) | classifier + packet | [CR-15.json](../packets/CR-15.json) |

### Tier B — promote Phase 1 findings into adjacent code

| ID | Target | Lens |
| --- | --- | --- |
| **CR-16** | [`runQueue compaction`](../tasks/CR-16-runqueue-compaction-bounds.md) | [CR-16.json](../packets/CR-16.json) |
| **CR-17** | [`runQueue deadline`](../tasks/CR-17-runqueue-deadline.md) | [CR-17.json](../packets/CR-17.json) |
| **CR-18** | [`SliceGate`](../tasks/CR-18-slice-gate-content.md) | [CR-18.json](../packets/CR-18.json) |
| **CR-19** | [`CheckResult consumers`](../tasks/CR-19-checkresult-consumers.md) | [CR-19.json](../packets/CR-19.json) |
| **CR-20** | [`Subprocess lifecycle`](../tasks/CR-20-subprocess-lifecycle.md) | [CR-20.json](../packets/CR-20.json) |
| **CR-21** | [`DriverConcurrencyGate`](../tasks/CR-21-driver-gate-liveness.md) | [CR-21.json](../packets/CR-21.json) |

### Tier C — execution path + write safety

| ID | Target | Lens |
| --- | --- | --- |
| **CR-12** | [`RunService write lock`](../tasks/CR-12-runservice-write-lock.md) | [CR-12.json](../packets/CR-12.json) |
| **CR-22** | [`RunService OpenCode`](../tasks/CR-22-runservice-opencode-branch.md) | [CR-22.json](../packets/CR-22.json) |
| **CR-23** | [`PendingRunExecutor`](../tasks/CR-23-pending-run-executor.md) | [CR-23.json](../packets/CR-23.json) |
| **CR-24** | [`Subprocess resolution`](../tasks/CR-24-subprocess-resolution.md) | [CR-24.json](../packets/CR-24.json) |
| **CR-25** | [`Nudge / planner`](../tasks/CR-25-nudge-planner-prompts.md) | [CR-25.json](../packets/CR-25.json) |

### Tier D — GUI perf + streaming (user-visible)

| ID | Target | Lens |
| --- | --- | --- |
| **CR-13** | [`ThreadsViewModel`](../tasks/CR-13-threads-viewmodel-reload.md) | [CR-13.json](../packets/CR-13.json) |
| **CR-26** | [`Timeline + ThreadTurn`](../tasks/CR-26-timeline-threadturn-kinds.md) | [CR-26.json](../packets/CR-26.json) |
| **CR-27** | [`ThreadStore serializer`](../tasks/CR-27-threadstore-serializer.md) | [CR-27.json](../packets/CR-27.json) |
| **CR-28** | [`ThreadView scroll`](../tasks/CR-28-threadview-scroll.md) | [CR-28.json](../packets/CR-28.json) |

### Tier E — remote, resident, distribution (when scoped)

| ID | Target | Lens |
| --- | --- | --- |
| **CR-29** | [`RemoteSnapshotPublisher`](../tasks/CR-29-remote-snapshot-publisher.md) | [CR-29.json](../packets/CR-29.json) |
| **CR-30** | [`ResidentCoordinatorProbe`](../tasks/CR-30-resident-coordinator-probe.md) | [CR-30.json](../packets/CR-30.json) |
| **CR-31** | [`DirectModeCommandServer`](../tasks/CR-31-directmode-command-server.md) | [CR-31.json](../packets/CR-31.json) |
| **CR-32** | [`LoopbackHealthServer`](../tasks/CR-32-loopback-health-server.md) | [CR-32.json](../packets/CR-32.json) |

---

## Suggested run order (serial hardening pass 2)

```text
CR-07  → CR-11 → CR-14 → CR-15     # close Phase 1 + streaming reliability
CR-18  → CR-19 → CR-21             # gate + check + spawn gate
CR-16  → CR-17 → CR-22             # pair queue liveness
CR-12  → CR-23 → CR-24             # run path substrate
CR-13  → CR-26 → CR-27 → CR-28     # GUI perf
CR-29–32 as needed                 # remote/resident
```

---

## How to add a slice

1. Copy a task stub from `tasks/CR-04-check-runner.md` (one screen).
2. Add `packets/CR-NN.json` with `readPaths`, lenses, `touchAllowlist` → findings only.
3. Set `stallTimeoutSeconds: 3600`.
4. Expand + serial dispatch per [`GLM_Worker_Best_Practices.md`](../../operations/GLM_Worker_Best_Practices.md).
5. Archive → `triage/` → promote to `docs/phases/sprint/`.

---

## What we deliberately did NOT slice yet

- Whole `PairCoordinator.swift` (only `runQueue` chunk done)
- Whole `WorkerRunner.swift` (only planned line range)
- Mac app views beyond timeline/thread reload
- iOS companion path
- MCP / CLI product spine JSON contracts
- Team assembly / substitution resolver
- Judgment / review board chain

Split god files by **invariant**, not by file boundary.

---

## Changelog

| Date | Change |
| --- | --- |
| 2026-06-27 | CR-14–32 tasks + packets; follow-up-recommendations.md master log |
