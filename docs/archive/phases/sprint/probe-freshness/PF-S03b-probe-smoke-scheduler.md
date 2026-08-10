# PF-S03b — Serve-hosted periodic probe smoke (founder B)

Run: `28A5D3B3-A034-45E8-83A3-888108EFF270` (DeepSeek V4 Pro)
Status: **done** (2026-08-09) — commits `fed8f447` + docs; Works Test 13/13 verified  
Slice: PF-S03b (small)  
SSOT: [`docs/archive/phases/Probe_Freshness.md`](../../Probe_Freshness.md) §PF-S03 missing decision + founder B (2026-08-09)  
Executor: `model_opencode_deepseek_v4_pro` (founder-routed)

## Goal

`alln serve` periodically runs a real `full: true` source probe when probe
records are stale, so `lastProbeAt` stays honest evidence without inventing
timestamps on the cheap path. Founder ruled **B** (quota spend OK).

## Copy-paste prompt

```text
You are implementing Probe Freshness slice PF-S03b only — keep it small.

Founder ruling 2026-08-09: Option B — permit periodic full smoke on the serve
freshness clock. Spending tiny quota is approved; inventing lastProbeAt without
smoke is not. Option A (lastDetectedAt split) already shipped — do not reopen it.
Cheap/full:false must still never advance lastProbeAt.

Read ONLY:
- docs/phases/sprint/probe-freshness/PF-S03b-probe-smoke-scheduler.md (this file)
- docs/archive/phases/Probe_Freshness.md §PF-S03 “Missing decision” + header note on B
- Packages/AllnighterCore/Sources/AllnighterEngine/CapacityRefreshScheduler.swift (pattern)
- Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemon.swift (wire site)
- Packages/AllnighterCore/Sources/AllnighterEngine/SourceProbeService.swift
- Packages/AllnighterCore/Sources/AllnighterCore/ProbeFreshnessGate.swift (gateInterval)
- docs/operations/Execution-Playbook.md — FILTERED tests ONLY

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/ProbeRecordRefreshScheduler.swift (NEW)
  - tickInterval = 5 minutes (match capacity scheduler check cadence)
  - shouldSmoke(records:now:): true when records empty OR any non-parked
    headless-CLI-relevant record has lastProbeAt age >= ProbeFreshnessGate.gateInterval
    (30m). Prefer reading SetupStore().load().records via injectable loader.
  - run(isCancelled:): loop like CapacityRefreshScheduler — if shouldSmoke, call
    injectable smoke() once, then sleep tickInterval (+ optional small jitter injectable as 0 in tests)
  - default smoke(): construct SourceProbeService from Runtime-ish defaults
    (ModelCatalog + DriverRegistry + version identity) and await probe(SourceProbeRequest(full: true))
    — keep default thin; tests NEVER call live vendors
  - Do NOT write lastProbeAt yourself — CensusIngest / SourceProbeService full path owns persistence
  - Do NOT invent timestamps on cheap path
- Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemon.swift
  - addTask { await ProbeRecordRefreshScheduler().run { shutdown.isCancelled } }
    alongside CapacityRefreshScheduler (comment: Probe_Freshness founder B 2026-08-09)
- Packages/AllnighterCore/Tests/AllnighterEngineTests/ProbeRecordRefreshSchedulerTests.swift
  - fixtures only: shouldSmoke true when stale/empty; false when all fresh;
    run invokes smoke when due and not when fresh; cancel stops loop;
    NEVER live SourceProbeService / launchctl / network

Do NOT:
- Change ProbeFreshnessGate / lastDetectedAt semantics
- CapacityRefreshScheduler behavior (capacity store stays separate)
- Unfiltered suite or check.sh — ONLY:
  scripts/swift-test.sh --filter ProbeRecordRefreshSchedulerTests
- Leave uncommitted

Works Test:
  scripts/swift-test.sh --filter ProbeRecordRefreshSchedulerTests

Done when:
- [ ] Serve hosts ProbeRecordRefreshScheduler
- [ ] shouldSmoke uses ProbeFreshnessGate.gateInterval against lastProbeAt
- [ ] Smoke is full:true path only (injected in tests)
- [ ] Filtered tests green
- [ ] Explicit-path commit

Follow Execution-Playbook. Commit your own work.
```
