# ASR-S03b — deadline inventory

Every wait in `Packages/AllnighterCore/Sources/AllnighterEngine/` that a background
daemon obligation depends on. One row per site, judged by reading the code, not by
name. Sites being deleted by a later slice (e.g. `CapacityResidentService` periodic
portion, ASR-S04) are listed and marked, not fixed.

## Verdicts

- **wake-safe** — re-evaluates wall clock at a bounded interval; detects a
  sleep-gap deadline miss within one nap boundary.
- **not wake-safe** — computes one duration up front and sleeps it in a single
  shot. A Mac that sleeps past the deadline wakes late by the full overshoot.
- **not an obligation** — short poll, subprocess timeout, test seam, or not a
  background daemon wait.
- **unknown** — cannot determine from the code; reason given.

## Daemon schedulers (resident loops that block on a deadline)

| File:line | What it waits for | Typical duration | Verdict |
|---|---|---|---|
| `LoopCoordinator.swift:2320` | `sleepClampedToDeadline` — retry grace wait clamped to `config.until`. Delegates to `sleeper` (default `WakeSafeWaiter`). Stores overshoot. | Variable (5s retry grace, clamped to `until`) | **wake-safe** |
| `LoopCoordinator.swift:2210` | `sleepUntil` — vendor park claim/adopt loop polls at 2s intervals clamped to `config.until`. Default `WakeSafeWaiter`. | 2s | **wake-safe** |
| `PendingWakeScheduler.swift:78` | `sleeper.sleep(until: nextWake)` — wake-ticket deadline. Default `WakeSafeWaiter`. Records overshoot. | Variable (planned wake time + 60s jitter) | **wake-safe** |
| `PendingWakeScheduler.swift:74` | `sleeper.sleep(until: now()+300)` — fallback when no pending items. Default `WakeSafeWaiter`. | 300s | **wake-safe** |
| `VendorBackoffReconciler.swift:114` | `sleeper.sleep(until: target)` — per-vendor backoff wake deadline. Default `DefaultPendingWakeSleeper`. | Variable (backoff plan) or 60s fallback | **not wake-safe** |
| `BoostSeedScheduler.swift:45` | `sleeper.sleep(until: next)` — exact calendar fire time. Default `DefaultPendingWakeSleeper`. | Hours (calendar-driven) | **not wake-safe** |
| `BoostSeedScheduler.swift:49` | `sleeper.sleep(until: now()+60)` — fallback poll when no seed scheduled. Default `DefaultPendingWakeSleeper`. | 60s | **not wake-safe** |
| `CapacityRefreshScheduler.swift:161` | `sleeper.sleep(until: sleepUntil)` — periodic capacity tick. Default `DefaultPendingWakeSleeper`. | 300s (normal) or variable backoff | **not wake-safe** |
| `NotificationScheduler.swift:126` | `sleeper.sleep(until: now()+pollInterval)` — notification poll tick. Default `DefaultPendingWakeSleeper`. | 10s | **not wake-safe** |
| `PMTurnWakeScheduler.swift:193` | `sleeper.sleep(until: now()+pollInterval)` — PM turn wake hook poll. Default `DefaultPendingWakeSleeper`. | 5s | **not wake-safe** |
| `ProbeRecordRefreshScheduler.swift:70` | `sleeper.sleep(until: sleepUntil)` — periodic probe smoke. Default `DefaultPendingWakeSleeper`. | 300s | **not wake-safe** |

> All six `DefaultPendingWakeSleeper` sites compute one `timeIntervalSinceNow`
> duration up front and sleep it in a single `Task.sleep`. A system sleep that
> outlasts the interval is not detected until the full original duration
> elapses. None of these six schedulers would be affected by a 5-hour park
> because their intervals are seconds/minutes, but any sleep longer than the
> computed interval leaves the scheduler unresponsive for `overshoot - interval`
> after wake.

| File:line | What it waits for | Typical duration | Verdict |
|---|---|---|---|
| `RemoteMacAgentCoordinator.swift:127` | `sleeper.sleep(for: delay)` — command drain poll loop. Default `DefaultRemoteMacAgentSleeper` (one-shot `Task.sleep`). | 5s (normal), up to 60s (backoff) | **not wake-safe** |
| `SandboxHandoffRunner.swift:207` | `Task.sleep(for: .seconds(pollSeconds))` — mailbox watcher poll. Default 2s. | 2s | **not an obligation** — fixed 2s poll interval is a short re-check loop, not a deadline-driven wait. |
| `CapacityResidentService.swift:425` | `waitForFire(deadline:)` — resident capacity scheduler tick. Uses `monotonicNow()` (system uptime, which pauses during sleep). Depends on `notifyWake()` for sleep detection. | ~30 min (scheduleInterval) | **not wake-safe** — monotonic clock pauses during sleep; wake detection relies on `notifyWake()` observer, not clock evaluation. **Being removed by ASR-S04.** |
| `CapacityResidentService.swift:494` | `sleep(remaining)` — acquire floor delay. One-shot `Task.sleep` with wall-clock `timeIntervalSince`. | Up to 120s | **not wake-safe** — one-shot sleep, compute interval once. **Being removed by ASR-S04.** |
| `ExecutionLane.swift:266` | `Task.sleep(for: .milliseconds(200))` — waiter reconcile poll in `waitToAcquire`. Re-evaluates conditions each iteration. | 200ms | **not an obligation** — short poll, re-checks conditions each 200ms. Loop itself is the guardrail. |
| `ExecutionLane.swift:286` | `Task.sleep(for: timeout, clock: ContinuousClock())` — write-lock timeout backstop. Uses `ContinuousClock` which is immune to system sleep. | 1800s (configurable) | **wake-safe** — `ContinuousClock` is explicitly sleep-immune. |
| `ServeDaemonAdmission.swift:149` | `Thread.sleep(forTimeInterval: 0.2)` — SIGTERM grace poll for superseded daemon stop. Re-evaluates `isAlive()` each iteration. | 200ms × up to 5s | **not an obligation** — synchronous blocking sleep only at daemon startup during process supersession. Not a resident scheduler. |
| `ServeDaemonAdmission.swift:156` | `Thread.sleep(forTimeInterval: 0.2)` — SIGKILL grace poll. Re-evaluates `isAlive()` each iteration. | 200ms × up to 2s | **not an obligation** — same rationale as above. |
| `AsyncTeamService.swift:457` | `Thread.sleep(forTimeInterval: 0.05)` — idempotency replay wait. Re-evaluates `Date()` each iteration; uses blocking `Thread.sleep`. | 50ms × up to 5s | **not an obligation** — short synchronous poll, not a resident scheduler wait. |
| `RemoteIOSThreadMirrorExecutor.swift:103` | `Task.sleep(nanoseconds: 1_000_000_000)` — settle poll for run to appear in store. | 1s × up to 1800 iterations | **not an obligation** — short poll, re-checks `runStore.load()` each iteration. |
| `RemoteIOSThreadMirrorExecutor.swift:118` | `Task.sleep(nanoseconds: 1_000_000_000)` — settle poll for run to become terminal. | 1s × up to 1800 iterations | **not an obligation** — same rationale. |

## Subprocess timeouts (not daemon scheduler waits)

| File:line | What it waits for | Verdict |
|---|---|---|
| `ProcessGroupCommandRunner.swift:148` | `Task.sleep(for: timeout)` — non-streaming watchdog at dispatch. | **not an obligation** — subprocess timeout, lives with the spawned task. |
| `ProcessGroupCommandRunner.swift:314` | `Task.sleep(for: .seconds(sleep))` — streaming stall poll. 0.05–0.2s. | **not an obligation** — short poll inside a subprocess watcher. |
| `ProcessGroupCommandRunner.swift:323` | `Task.sleep(for: .seconds(0.5))` — streaming post-stall nap. | **not an obligation** — subprocess watcher detail. |
| `ProcessGroupCommandRunner.swift:333` | `Task.sleep(for: budget.totalDuration)` — streaming hard-total-duration backstop. | **not an obligation** — subprocess timeout. |
| `DesignBoardCapture.swift:103` | `Task.sleep(nanoseconds:)` — WebKit render timeout. | **not an obligation** — on-demand CLI/GUI capture, not daemon-resident. |
| `HandoffDoctor.swift:65` | `Task.sleep(for:)` — CLI doctor poll loop. | **not an obligation** — CLI tool, not daemon-resident. |

## Signal-based waits (not clock-based)

| File:line | What it waits for | Verdict |
|---|---|---|
| `ServeDaemon.swift:202` | `waitForShutdownSignal()` — `withCheckedContinuation` on SIGINT/SIGTERM. | **N/A** — signal-based, not a sleep. |
| `DesignBoardCapture.swift:274,309` | `bridge.waitUntilFinished()` — WebKit navigation callback. | **N/A** — continuation-based, not a sleep. |

## RunService write-lock acquires (per-root lock)

| File:line | What it waits for | Verdict |
|---|---|---|
| `RunService.swift:736` | `writeLock.waitToAcquire(lockKey, timeout: 1800s)` — vendor wake reacquire. | **wake-safe** — delegates to `ExecutionLane` with `ContinuousClock` timeout. |
| `RunService.swift:1050` | `writeLock.waitToAcquire(lockKey, timeout: 1800s)` — standard run dispatch. | **wake-safe** — same mechanism. |
| `RunService.swift:2240` | `writeLock.waitToAcquire(laneKey, timeout: 1800s)` — harness proof acquire. | **wake-safe** — same mechanism. |

## Sites verified as using WakeSafeWaiter (post-S03a/S03b)

| Scheduler | Default sleeper | Verdict |
|---|---|---|
| `PendingWakeScheduler` | `WakeSafeWaiter()` | **wake-safe** — S03a |
| `LoopCoordinator` | `WakeSafeWaiter()` | **wake-safe** — S03a (sleepUntil) + S03b (sleepClampedToDeadline) |

## Sites still using DefaultPendingWakeSleeper (not yet converted)

| Scheduler | Line | Interval | Wake-Gap Risk |
|---|---|---|---|
| `VendorBackoffReconciler` | 71 | Variable / 60s fallback | Vendor backoff deadlines; 5-hour park would be missed by hours |
| `BoostSeedScheduler` | 25 | Hourly+ / 60s fallback | Calendar fires could be delayed past the window |
| `CapacityRefreshScheduler` | 83 | 300s / variable backoff | Misses refresh tick after sleep > 5 min |
| `NotificationScheduler` | 80 | 10s | Minor — 10s poll recovers quickly |
| `PMTurnWakeScheduler` | 177 | 5s | Minor — 5s poll recovers quickly |
| `ProbeRecordRefreshScheduler` | 33 | 300s | Misses probe smoke tick after sleep > 5 min |

## Sites being removed by later slice

| Site | Slice | Note |
|---|---|---|
| `CapacityResidentService` periodic scheduler (`waitForFire`, acquire floor) | ASR-S04 §2.4 | Listed for completeness; do not fix. |
