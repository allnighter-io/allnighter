# Phase 2 Run Log — GLM Serial Hardening Pass

Status: **partial — 20/22 findings; triage complete**
Updated: 2026-06-29

Follow-up master log: [`follow-up-recommendations.md`](follow-up-recommendations.md)

## Slice status

| ID | Task | Packet | Review | Verify | Notes |
| --- | --- | --- | --- | --- | --- |
| CR-07 | [task](tasks/CR-07-stalled-work-detector.md) | [packet](packets/CR-07.json) | **done** | — | [triaged](triage/CR-07-findings.md) |
| CR-11 | [task](tasks/CR-11-worker-runner-opencode.md) | [packet](packets/CR-11.json) | **done** | — | [findings](findings/CR-11.md) — passed retry |
| CR-14 | [task](tasks/CR-14-opencode-serve-client-stream.md) | [packet](packets/CR-14.json) | **failed** | — | ~21m; echoed prompt, no findings — GLM stream/tool issue (not 600s timeout) |
| CR-15 | [task](tasks/CR-15-advisory-review-terminal.md) | [packet](packets/CR-15.json) | **done** | — | retry5 passed |
| CR-16 | [task](tasks/CR-16-runqueue-compaction-bounds.md) | [packet](packets/CR-16.json) | **done** | — | retry4 passed |
| CR-17 | [task](tasks/CR-17-runqueue-deadline.md) | [packet](packets/CR-17.json) | **done** | — | retry4 passed |
| CR-18 | [task](tasks/CR-18-slice-gate-content.md) | [packet](packets/CR-18.json) | **done** | — | retry4 passed |
| CR-19 | [task](tasks/CR-19-checkresult-consumers.md) | [packet](packets/CR-19.json) | **done** | — | retry4 passed |
| CR-20 | [task](tasks/CR-20-subprocess-lifecycle.md) | [packet](packets/CR-20.json) | **done** | — | retry5 passed |
| CR-21 | [task](tasks/CR-21-driver-gate-liveness.md) | [packet](packets/CR-21.json) | **failed** | — | retry5 + solo retry: partial/empty output, no findings |
| CR-22 | [task](tasks/CR-22-runservice-opencode-branch.md) | [packet](packets/CR-22.json) | **done** | — | retry4 passed |
| CR-23 | [task](tasks/CR-23-pending-run-executor.md) | [packet](packets/CR-23.json) | **done** | — | retry4 passed |
| CR-24 | [task](tasks/CR-24-subprocess-resolution.md) | [packet](packets/CR-24.json) | **done** | — | retry5 passed |
| CR-25 | [task](tasks/CR-25-nudge-planner-prompts.md) | [packet](packets/CR-25.json) | **done** | — | retry4 passed |
| CR-12 | [task](tasks/CR-12-runservice-write-lock.md) | [packet](packets/CR-12.json) | **done** | — | retry4 passed |
| CR-13 | [task](tasks/CR-13-threads-viewmodel-reload.md) | [packet](packets/CR-13.json) | **done** | — | retry5 passed |
| CR-26 | [task](tasks/CR-26-timeline-threadturn-kinds.md) | [packet](packets/CR-26.json) | **done** | — | retry5 passed |
| CR-27 | [task](tasks/CR-27-threadstore-serializer.md) | [packet](packets/CR-27.json) | **done** | — | retry4 passed |
| CR-28 | [task](tasks/CR-28-threadview-scroll.md) | [packet](packets/CR-28.json) | **done** | — | retry5 passed |
| CR-29 | [task](tasks/CR-29-remote-snapshot-publisher.md) | [packet](packets/CR-29.json) | **done** | — | retry4 passed |
| CR-30 | [task](tasks/CR-30-resident-coordinator-probe.md) | [packet](packets/CR-30.json) | **done** | — | retry4 passed |
| CR-31 | [task](tasks/CR-31-directmode-command-server.md) | [packet](packets/CR-31.json) | **done** | — | retry4 passed |
| CR-32 | [task](tasks/CR-32-loopback-health-server.md) | [packet](packets/CR-32.json) | **done** | — | retry4 passed |

## Dispatch

```bash
PAIR_CR_PARALLEL=0 PAIR_CR_VERIFY=0 scripts/run_cr_phase1.sh Allnighter \
  11 14 15 18 19 21 16 17 22 12 23 20 24 25 13 26 27 28 29 30 31 32
```

Log: `output/cr-phase2-run-2026-06-28.log` (~8.5 min, retry3)

## Learnings (Phase 2 resume)

| Date | Lesson |
| --- | --- |
| 2026-06-28 | **Ship fixes before Phase 2** — OC-S02/CLASS-S03/DRIVER-S01 landed first; resume skips CR-07 (triaged) and re-reviews already-shipped areas (CR-15/16/17/18/21) for delta findings or confirmation. |
| 2026-06-28 | **Prebuilt `alln`** — rebuild after sprint landings; script uses `.build/arm64-apple-macosx/debug/alln`. |
| 2026-06-28 | **Retry2 0/21** (~10 min) — gate fix worked (no spawn timeouts). CR-14: 10m worker `.done`, 0 stream events, output = echoed prompt, no findings file. CR-15–32: instant `portOwnedByForeignProcess` — stale `opencode serve` from CR-14 blocked port 4096. **Next:** serve teardown between slices; re-run. |
| 2026-06-28 | **Retry3 0/21** (~8.5 min, serial, post-rebuild) — all CR-14–32 `status: failed`, `check.exitCode: 1`, no new `findings/CR-NN.md`. Fast per-slice (~24s avg) ⇒ workers not reaching findings write. **Next:** add `serveCoordinator.stop()` between OpenCode review slices; smoke CR-14 alone before full queue. |
| 2026-06-28 | **Retry5 6/7 passed** (~74 min) — after `workerTimeoutSeconds` + opencode-worker serve teardown fixes. Passed: CR-15,20,24,13,26,28. Failed: CR-21 (partial output). CR-14 still fails (echoed prompt @ ~21m). Log: `output/cr-phase2-retry5.log`. |
| 2026-06-28 | **Infra fixes** — `RunRequest.workerTimeoutSeconds` wires packet `stallTimeoutSeconds` (3600s); `usesOpenCodeServe` checks executor worker driver, not just team `executionSourceId`, so serve stops after GLM slices on `default_chat`. |

After each slice: archive `findings/CR-NN.md` → `triage/`, update
[`follow-up-recommendations.md`](follow-up-recommendations.md).

**Triage:** complete for CR-11–13,15–32 — see [`planner-triage-verdict-phase2.md`](planner-triage-verdict-phase2.md).
