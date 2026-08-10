# SC-S01 — ServeLifecycle: migrate orphan LaunchAgent

Status: **done** (2026-08-09) — commit `867d72e3`; Works Test 8/8  
Slice: SC-S01  
Run: `19045F88-081F-4CBE-B252-9353B7CA6621`  
Historical packet: [`Serve_Continuity.md`](../../../archive/phases/Serve_Continuity.md) §3.2 + §4
Executor: Kimi K3 via `alln run --team build_slice --model model_kimi_k3`

## Goal

Product-owned **removal** of the unsupported CODE_RED LaunchAgent
(`com.allnighter.resident-coordinator`) so thrash / fake supervision stops.
Wire `alln serve repair` to clear a wedge (bootout + delete plist) and leave
demand-start of serve for SC-S03 / existing manual `alln serve`.  
**Do not** SMAppService-register or resurrect `serve install` (founder ruling
+ SC-S04).

## Copy-paste prompt

```text
You are implementing Serve Continuity slice SC-S01 only.

Read ONLY:
- docs/phases/sprint/serve-continuity/SC-S01-lifecycle-migrate-orphan.md (this file)
- docs/archive/phases/Serve_Continuity.md §3.2–3.4 and §4 (SC-S01 row; SC-S00 done)
- Packages/AllnighterCore/Sources/AllnighterEngine/ServeLaunchAgentStatus.swift
- Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift (runServe only)
- Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift (serve command flags — additive repair only)
- docs/operations/Execution-Playbook.md § Commits + Green Wall (filtered tests only)

Touch ONLY:
- New: Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift
  (removeOrphan / repairWedged: bootout label if loaded, delete plist if present;
   injectable runners for launchctl + FileManager; never register/enable)
- Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift
  (alln serve repair [--json] — uses ServeLaunchAgentStatus; if wedged or plist present
   as unsupported orphan, call ServeLifecycle.remove; print honest result;
   if absent, no-op success; do NOT start serve here unless already trivial via
   existing ServeAutoLaunch — prefer NOT auto-start in S01)
- Contract/help only as needed for `serve repair` flag/subcommand discovery
  (ContractRegistry+Milestone1 serve command; HelpTopicRegistry one line max)
- One test: Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLifecycleTests.swift
  (fixtures only — never live launchctl bootout against the founder host in tests)

Do NOT:
- SMAppService / enable / disable / KeepAlive reinstall (SC-S04 + founder ruling)
- install-cli / rebuild_cli wiring (SC-S02)
- Widen ServeAutoLaunch to alln run / app (SC-S03)
- Change ServeDaemonAdmission or Capacity*
- Run unfiltered `scripts/swift-test.sh` or `check.sh` — ONLY:
  scripts/swift-test.sh --filter ServeLifecycleTests
- Resurrect "serve install" string in help
- Leave uncommitted — explicit-path git commit when Works Test green

Behavior:
1. Label + plist path = same as ServeLaunchAgentStatus.label
2. removeOrphan: attempt `launchctl bootout gui/$UID/label` (ignore not-loaded);
   delete plist if exists; return structured outcome (removed / absent / failed)
3. `alln serve repair`: observe status; if wedged OR plist present → removeOrphan;
   JSON + human lines; exit 0 on removed/absent; non-zero on failed
4. Reuse SC-S00 observation — do not duplicate wedge rule

Works Test:
  scripts/swift-test.sh --filter ServeLifecycleTests

Done when:
- [ ] Fixture: plist+wedged → remove deletes plist + attempts bootout (injected)
- [ ] Fixture: absent → no-op ok
- [ ] No live destructive launchctl in unit tests
- [ ] Focused tests green (FILTERED ONLY)
- [ ] Explicit-path commit
- [ ] No SMAppService / enable

Follow Execution-Playbook. Commit your own work.
```

## Works Test

```bash
scripts/swift-test.sh --filter ServeLifecycleTests
```

## SSOT

`docs/archive/phases/Serve_Continuity.md` §4 SC-S01.
