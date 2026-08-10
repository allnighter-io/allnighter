# SC-S00 — Serve LaunchAgent honesty (doctor + health)

Status: **done** (2026-08-09) — commit `05afee05`; Works Test 14/14  
Slice: SC-S00  
Run: `2ADC34AF-DB8D-4712-8FE4-43DAE717EC0E` (Kimi K3; PM verified after stopping unfiltered suite)  
Historical packet: [`Serve_Continuity.md`](../../../archive/phases/Serve_Continuity.md) §3.4 + §4
Executor: Kimi K3 (`model_kimi_k3`) via `alln run --team build_slice --model model_kimi_k3`

## Goal

Fail closed when an orphan / wedged `com.allnighter.resident-coordinator`
LaunchAgent exists: never paint “KeepAlive / spawn scheduled” as healthy
supervision. Surface a clear recovery hint. No lifecycle register/repair yet
(that is SC-S01).

## Copy-paste prompt

```text
You are implementing Serve Continuity slice SC-S00 only.

Read ONLY:
- docs/phases/sprint/serve-continuity/SC-S00-launchagent-honesty.md (this file)
- docs/archive/phases/Serve_Continuity.md §3.4 and §4 (SC-S00 row + S00a verdict)
- Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemonProbe.swift
- Packages/AllnighterCore/Sources/AllnighterCore/CoordinatorHealth.swift
- Packages/AllnighterCore/Sources/AllnighterCore/DoctorReport.swift (coordinatorCheck)
- Packages/AllnighterCore/Sources/AllnighterCore/DoctorResult.swift (Check / Coordinator)

Touch ONLY (≤3 prod + ≤1 test unless contract forces one more):
- New: Packages/AllnighterCore/Sources/AllnighterEngine/ServeLaunchAgentStatus.swift
  (pure observation: plist present? launchd print parse → running | wedged | absent | unknown;
   inject Process runner for tests — no live launchctl required in unit tests)
- Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemonProbe.swift
  (compose observation into health + doctorCoordinator)
- Packages/AllnighterCore/Sources/AllnighterCore/CoordinatorHealth.swift
  (+ ContractSchema / registry bump ONLY if you add an additive Codable field;
   prefer optional `launchAgent` object omitted when absent)
- Packages/AllnighterCore/Sources/AllnighterCore/DoctorReport.swift
  (new doctor check e.g. serve.launchAgent — critical/degraded when wedged;
   fixCommand hint: "alln serve" for now; do NOT resurrect "serve install")
- One test file: Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLaunchAgentStatusTests.swift

Do NOT:
- Implement enable/disable/repair / SMAppService / bootout (SC-S01+)
- Widen ServeAutoLaunch call sites (SC-S03)
- Change ServeDaemonAdmission
- Touch CapacityRefreshScheduler
- Invent a second scheduler
- Call launchctl from tests (inject fixtures)
- Leave work uncommitted — commit this slice only with an explicit path commit

Behavior:
1. Label: com.allnighter.resident-coordinator
   Plist: ~/Library/LaunchAgents/com.allnighter.resident-coordinator.plist
2. Wedged = launchctl state indicates spawn scheduled (or equivalent inactive) AND
   (last exit 78 OR properties contain "needs LWCR" / "managed LWCR") AND no live job pid
   — OR: plist present + last exit 78 + active count 0. Encode the rule in one place.
3. When wedged: doctor check must NOT be .ok; serve --health must expose the wedge
   (additive field or force coordinator path that cannot read as "all fine").
4. When plist absent: no new failure (foregroundOnly without plist remains OK).
5. When agent running with live pid: observation reports running; do not fail closed
   solely because the plist is an orphan (orphan removal is SC-S01) — optional
   advisory detail allowed, but wedge is the fail-closed gate for S00.
6. Teaching: if HelpTopicRegistry has a serve/doctor topic, one sentence that a
   wedged LaunchAgent is unhealthy — only if you already touch help; else skip
   (SC-S01 can teach repair). Prefer not expanding file count.

Works Test:
  scripts/swift-test.sh --filter ServeLaunchAgentStatusTests

Done when:
- [ ] Wedged fixture → doctor check not ok + health exposes wedge
- [ ] Absent plist → no new failure
- [ ] Running fixture → not wedged
- [ ] Focused tests green
- [ ] Explicit-path git commit for this slice
- [ ] No scope creep into SC-S01+

Follow docs/operations/Execution-Playbook.md (commit your own work).
```

## Read only

Listed in the prompt.

## Touch only

Listed in the prompt allowlist.

## Do not read / do not touch

Capacity*, ServeAutoLaunch (except if probe already imports — do not change call sites),
Mac app, InstallCLI, rebuild_cli, AGENTS.md (PM owns board updates).

## Steps

1. Implement `ServeLaunchAgentStatus` with injectable listing/print.
2. Wire probe → health + doctor.
3. Additive contract only if needed; bump schemaVersion per repo norms.
4. Tests with fixtures (no live launchctl).
5. `scripts/swift-test.sh --filter ServeLaunchAgentStatusTests`
6. Commit explicit paths.

## Works Test

```bash
scripts/swift-test.sh --filter ServeLaunchAgentStatusTests
```

## Done when

Checkboxes in the prompt.

## SSOT

`docs/archive/phases/Serve_Continuity.md` §3.4 / §4 SC-S00.
