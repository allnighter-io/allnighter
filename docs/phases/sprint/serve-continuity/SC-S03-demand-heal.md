# SC-S03 — Demand heal: ensure serve on `alln run` + Mac app launch

Status: ready  
Slice: SC-S03  
SSOT: [`docs/phases/Serve_Continuity.md`](../../Serve_Continuity.md) §3.3 + §4  
Executor: Kimi K3 via `alln run --team build_slice --model model_kimi_k3`

## Goal

After serve dies, the next ordinary bench action brings it back — without
reboot and without waiting for Loop. Wire existing `ServeAutoLaunch.ensureRunning`
into **`alln run`** (mutating/default path) and **Mac app launch**. Preserve
`--no-auto-serve` / `ALLN_NO_AUTO_SERVE`. Do not invent a second scheduler.

## Why S03 before S02

SC-S00a refuted H1 on post-bootstrap agents; SC-S02 (install-cli re-register)
and SC-S04 (SMAppService enable) need founder rulings. Demand heal unblocks
weekly-reboot / app-closed dogfood **now**.

## Copy-paste prompt

```text
You are implementing Serve Continuity slice SC-S03 only.

Read ONLY:
- docs/phases/sprint/serve-continuity/SC-S03-demand-heal.md (this file)
- docs/phases/Serve_Continuity.md §3.3 and §4 SC-S03
- Packages/AllnighterCore/Sources/AllnighterEngine/ServeAutoLaunch.swift
- Packages/AllnighterCore/Sources/AllnighterCLI/ServeAutoLaunchCLI.swift
- Packages/AllnighterCore/Sources/AllnighterCLI/RunCLI.swift (dispatch entry — where run starts)
- Apps/AllnighterMac/Sources/AllnighterMacApp.swift (launch / capacity enable path)
- docs/operations/Execution-Playbook.md § Green Wall (FILTERED tests ONLY)

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterCLI/RunCLI.swift
  (call ServeAutoLaunchCLI.ensureRunning + reportToStderr early on real dispatch;
   honor --no-auto-serve; never fail the run on ensureRunning .failed)
- Apps/AllnighterMac/Sources/AllnighterMacApp.swift
  (on launch, ensure serve via ServeAutoLaunch.ensureRunning(optedOut: false) or a thin Mac helper;
   do not block UI — fire-and-forget Task is fine; keep CapacityResidentService)
- Prefer reusing ServeAutoLaunchCLI from Engine/CLI; if Mac cannot import CLI, call ServeAutoLaunch from Engine directly (already public)
- Tests: extend ServeAutoLaunchTests OR add RunCLI ensureRunning spy test — ONE test file touch max
  Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeAutoLaunchTests.swift preferred

Do NOT:
- SMAppService / serve enable / repair changes (S01 done; S04 later)
- install-cli / rebuild_cli (S02)
- CapacityRefreshScheduler changes
- Unfiltered swift-test.sh or check.sh — ONLY:
  scripts/swift-test.sh --filter ServeAutoLaunchTests
- Leave uncommitted

Behavior:
1. alln run (team build_slice / default mutating path that actually dispatches work) must attempt ensureRunning unless opted out
2. Mac app launch must attempt ensureRunning once
3. Opt-out: --no-auto-serve and ALLN_NO_AUTO_SERVE still skip
4. Failure to launch serve must not change run exit code (existing ServeAutoLaunch contract)

Works Test:
  scripts/swift-test.sh --filter ServeAutoLaunchTests

Done when:
- [ ] ensureRunning invoked from RunCLI dispatch path (test or clear call site)
- [ ] Mac app launch invokes ensureRunning
- [ ] Opt-out preserved
- [ ] Filtered tests green
- [ ] Explicit-path commit

Follow Execution-Playbook. Commit your own work.
```

## Works Test

```bash
scripts/swift-test.sh --filter ServeAutoLaunchTests
```

## SSOT

`docs/phases/Serve_Continuity.md` §3.3 / §4 SC-S03.
