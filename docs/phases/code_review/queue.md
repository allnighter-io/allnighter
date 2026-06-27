# Code Review Queue — Status Board

Updated: 2026-06-27

| ID | Target | Lens | Est. read | Status | Findings |
| --- | --- | --- | --- | --- | --- |
| [CR-01](tasks/CR-01-run-write-lock.md) | `RunWriteLock` + registry | Concurrency invariant | ~120 lines | **done** | [triaged](triage/CR-01-findings.md) → RUNLOCK-S01/S02 |
| [CR-02](tasks/CR-02-slice-terminal-classifier.md) | `SliceTerminalClassifier` | Compaction ≠ stall (F2) | ~65 lines | **done** | [triaged](triage/CR-02-findings.md) |
| [CR-03](tasks/CR-03-slice-gate.md) | `SliceGate` | Scope + danger enforcement | ~60 lines | **done** | [triaged](triage/CR-03-findings.md) |
| [CR-04](tasks/CR-04-check-runner.md) | `CheckRunner` | Subprocess boundary safety | ~70 lines | **ready** | — |
| [CR-05](tasks/CR-05-opencode-serve.md) | `OpenCodeServeCoordinator` | GLM serve lifecycle | ~95 lines | **ready** | — |
| [CR-06](tasks/CR-06-pair-queue-loop.md) | `PairCoordinator.runQueue` | Retry / escalate / compact | ~250 lines | **ready** | — |
| [CR-07](tasks/CR-07-stalled-work-detector.md) | `StalledWorkDetector` (worker turns) | False stall vs pair loop | ~80 lines | **ready** | — |
| [CR-08](tasks/CR-08-driver-concurrency-gate.md) | `DriverConcurrencyGate` | Spawn limits + OpenCode | ~80 lines | **ready** | — |
| [CR-09](tasks/CR-09-timeline-visibility.md) | `TimelineVisibility.swift` | Scroll / read-clear perf | ~250 lines | **ready** | — |
| [CR-10](tasks/CR-10-streaming-write-path.md) | `StreamingPartialBuffer` + `ThreadStoreWriteSerializer` | Hot-path write coalescing | ~95 lines | **ready** | — |

## Phase 2 — large-file chunks

| ID | Target | Lens | Est. read | Status |
| --- | --- | --- | --- | --- |
| [CR-11](tasks/CR-11-worker-runner-opencode.md) | `WorkerRunner.runOpenCode` (251–331) | GLM HTTP path | ~80 lines | **ready** |
| [CR-12](tasks/CR-12-runservice-write-lock.md) | `RunService.run` lock (226–292) | Acquire/release | ~67 lines | **ready** |
| [CR-13](tasks/CR-13-threads-viewmodel-reload.md) | `ThreadsViewModel` (199–257) | PERF-S01 reload | ~60 lines | **ready** |

## Suggested run order

1. **Safety first:** CR-01 → CR-02 → CR-03 → CR-04 (control-plane invariants)
2. **GLM's own chair:** CR-05 → CR-06 (pair loop GLM sits in)
3. **False-positive overlap:** CR-07 (stall detector vs slice classifier)
4. **Throughput:** CR-08 → CR-10 (spawn + streaming)
5. **GUI perf:** CR-09 (dogfood scroll jank)

## Batch overnight

```bash
# Expand then dispatch (see scripts/run_cr_phase1.sh)
python3 scripts/expand_cr_packet.py . docs/phases/code_review/packets/CR-01.json
alln pair slice docs/phases/code_review/packets/CR-01.expanded.json --project Allnighter
```

Triage `findings/CR-*.md` in the morning; promote P0/P1 to `docs/phases/sprint/`.
