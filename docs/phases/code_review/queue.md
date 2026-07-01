# Code Review Queue — Status Board

Updated: 2026-06-28

**Phase 2 GLM serial pass: TRIAGED (20/22)** — planner verdict: [`planner-triage-verdict-phase2.md`](planner-triage-verdict-phase2.md). **5 new sprints** promoted; CR-14 + CR-21 blocked (no findings).

**Master logs:** [`follow-up-recommendations.md`](follow-up-recommendations.md) · [`phase2-runlog.md`](phase2-runlog.md) · [`phase1-runlog.md`](phase1-runlog.md)

## Phase 1 — complete

| ID | Target | Status | Findings |
| --- | --- | --- | --- |
| [CR-01](tasks/CR-01-run-write-lock.md) | RunWriteLock | **triaged** | [archive](triage/CR-01-findings.md) → RUNLOCK-S01/S02 |
| [CR-02](tasks/CR-02-slice-terminal-classifier.md) | SliceTerminalClassifier | **triaged** | [archive](triage/CR-02-findings.md) |
| [CR-03](tasks/CR-03-slice-gate.md) | SliceGate | **triaged** | [archive](triage/CR-03-findings.md) |
| [CR-04](tasks/CR-04-check-runner.md) | CheckRunner | **triaged** | [archive](triage/CR-04-findings.md) → CHECK-S01 |
| [CR-05](tasks/CR-05-opencode-serve.md) | OpenCodeServeCoordinator | **triaged** | [archive](triage/CR-05-findings.md) → OC-S02 |
| [CR-06](tasks/CR-06-pair-queue-loop.md) | PairCoordinator.runQueue | **triaged** | [archive](triage/CR-06-findings.md) |
| [CR-07](tasks/CR-07-stalled-work-detector.md) | StalledWorkDetector | **triaged** | [archive](triage/CR-07-findings.md) |
| [CR-08](tasks/CR-08-driver-concurrency-gate.md) | DriverConcurrencyGate | **triaged** | [archive](triage/CR-08-findings.md) |
| [CR-09](tasks/CR-09-timeline-visibility.md) | TimelineVisibility | **triaged** | [archive](triage/CR-09-findings.md) |
| [CR-10](tasks/CR-10-streaming-write-path.md) | StreamingPartialBuffer | **triaged** | [archive](triage/CR-10-findings.md) |

## Phase 2 — serial hardening pass (ready)

| ID | Target | Status | Packet |
| --- | --- | --- | --- |
| [CR-07](tasks/CR-07-stalled-work-detector.md) | StalledWorkDetector | **ready** | [CR-07.json](packets/CR-07.json) |
| [CR-11](tasks/CR-11-worker-runner-opencode.md) | WorkerRunner OpenCode | **ready** | [CR-11.json](packets/CR-11.json) |
| [CR-14](tasks/CR-14-opencode-serve-client-stream.md) | OpenCodeServeClient | **ready** | [CR-14.json](packets/CR-14.json) |
| [CR-15](tasks/CR-15-advisory-review-terminal.md) | Classifier + advisory | **ready** | [CR-15.json](packets/CR-15.json) |
| [CR-18](tasks/CR-18-slice-gate-content.md) | SliceGate content | **ready** | [CR-18.json](packets/CR-18.json) |
| [CR-19](tasks/CR-19-checkresult-consumers.md) | CheckResult consumers | **ready** | [CR-19.json](packets/CR-19.json) |
| [CR-21](tasks/CR-21-driver-gate-liveness.md) | DriverConcurrencyGate | **ready** | [CR-21.json](packets/CR-21.json) |
| [CR-16](tasks/CR-16-runqueue-compaction-bounds.md) | runQueue compaction | **ready** | [CR-16.json](packets/CR-16.json) |
| [CR-17](tasks/CR-17-runqueue-deadline.md) | runQueue deadline | **ready** | [CR-17.json](packets/CR-17.json) |
| [CR-22](tasks/CR-22-runservice-opencode-branch.md) | RunService OpenCode | **ready** | [CR-22.json](packets/CR-22.json) |
| [CR-12](tasks/CR-12-runservice-write-lock.md) | RunService write lock | **ready** | [CR-12.json](packets/CR-12.json) |
| [CR-23](tasks/CR-23-pending-run-executor.md) | PendingRunExecutor | **ready** | [CR-23.json](packets/CR-23.json) |
| [CR-20](tasks/CR-20-subprocess-lifecycle.md) | Subprocess lifecycle | **ready** | [CR-20.json](packets/CR-20.json) |
| [CR-24](tasks/CR-24-subprocess-resolution.md) | Subprocess resolution | **ready** | [CR-24.json](packets/CR-24.json) |
| [CR-25](tasks/CR-25-nudge-planner-prompts.md) | Nudge / planner prompts | **ready** | [CR-25.json](packets/CR-25.json) |
| [CR-13](tasks/CR-13-threads-viewmodel-reload.md) | ThreadsViewModel | **ready** | [CR-13.json](packets/CR-13.json) |
| [CR-26](tasks/CR-26-timeline-threadturn-kinds.md) | Timeline + ThreadTurn | **ready** | [CR-26.json](packets/CR-26.json) |
| [CR-27](tasks/CR-27-threadstore-serializer.md) | ThreadStore serializer | **ready** | [CR-27.json](packets/CR-27.json) |
| [CR-28](tasks/CR-28-threadview-scroll.md) | ThreadView scroll | **ready** | [CR-28.json](packets/CR-28.json) |
| [CR-29](tasks/CR-29-remote-snapshot-publisher.md) | RemoteSnapshotPublisher | **ready** | [CR-29.json](packets/CR-29.json) |
| [CR-30](tasks/CR-30-resident-coordinator-probe.md) | ResidentCoordinatorProbe | **ready** | [CR-30.json](packets/CR-30.json) |
| [CR-31](tasks/CR-31-directmode-command-server.md) | DirectModeCommandServer | **ready** | [CR-31.json](packets/CR-31.json) |
| [CR-32](tasks/CR-32-loopback-health-server.md) | LoopbackHealthServer | **ready** | [CR-32.json](packets/CR-32.json) |

## Run order

See [`phase2-hardening-queue.md`](phase2-hardening-queue.md) and [`follow-up-recommendations.md`](follow-up-recommendations.md).

```bash
PAIR_CR_PARALLEL=0 PAIR_CR_VERIFY=0 scripts/run_cr_phase1.sh Allnighter \
  07 11 14 15 18 19 21 16 17 22 12 23 20 24 25 13 26 27 28 29 30 31 32
```

Triage: findings file exists → archive → update follow-up log → promote to sprint.
