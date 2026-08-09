# SC-S04b — Product-owned serve enable / disable (LaunchAgent → staged binary)

Run: 
Status: in_progress  
Slice: SC-S04b (small)  
SSOT: [`docs/phases/Serve_Continuity.md`](../../Serve_Continuity.md) §6 + §4 SC-S04b  
Executor: Kimi K3 if 5h remaining ≥15%; else DeepSeek V4 Pro

## Goal

`alln serve enable` / `alln serve disable`: product-owned LaunchAgent for
`com.allnighter.resident-coordinator` that runs the **staged** stable binary
(`ServeStableBinary` destination). Migrate/replace any leftover CODE_RED plist.
Default remains **opt-in** (enable is explicit). No install-cli wiring yet (S02).

## Copy-paste prompt

```text
You are implementing Serve Continuity slice SC-S04b only — keep it small.

Read ONLY:
- docs/phases/sprint/serve-continuity/SC-S04b-enable-disable.md (this file)
- docs/phases/Serve_Continuity.md §6 (login helper YES) and §4 SC-S04b
- Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift
- Packages/AllnighterCore/Sources/AllnighterEngine/ServeStableBinary.swift
- Packages/AllnighterCore/Sources/AllnighterEngine/ServeLaunchAgentStatus.swift
- Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift (runServe / repair pattern)
- docs/operations/Execution-Playbook.md — FILTERED tests ONLY

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift
  (add enable/disable; keep remove/repair)
  - enable: require staged binary exists (or call ServeStableBinary.stage from current executable if missing — injectable);
    write product plist ProgramArguments = [stagedPath, "serve"], KeepAlive=true, RunAtLoad=true;
    bootout old label if present; bootstrap gui/$UID plist;
    never point at ~/.local/bin debug symlink
  - disable: bootout + delete plist (reuse remove)
  - injectable bootout/bootstrap/writePlist for tests — NO live launchctl in unit tests
- Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift
  - `alln serve enable [--json]` / `alln serve disable [--json]`
  - enable stages binary if needed then enable; disable calls disable
- ContractRegistry+Milestone1 serve subcommands additive only; help one line max
- Tests: Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeLifecycleEnableTests.swift
  (fixtures only)

Do NOT:
- install-cli / rebuild_cli hooks (SC-S02)
- SMAppService APIs this slice — product-owned LaunchAgent plist is the approved dogfood shape until app-bundled agent exists
- Capacity* / ServeAutoLaunch call-site changes
- Unfiltered swift-test or check.sh — ONLY:
  scripts/swift-test.sh --filter ServeLifecycleEnableTests
- Leave uncommitted

Works Test:
  scripts/swift-test.sh --filter ServeLifecycleEnableTests

Done when:
- [ ] enable writes plist aimed at staged binary + bootstrap (injected)
- [ ] disable removes agent
- [ ] enable never uses debug symlink path as ProgramArguments
- [ ] Filtered tests green
- [ ] Explicit-path commit

Follow Execution-Playbook. Commit your own work.
```

## Capacity gate (PM)

`alln capacity` → Kimi `shortRemainingPercent` ≥ 15 → `model_kimi_k3`.  
Else → `model_opencode_deepseek_v4_pro` (no V5 in menu). Treat missing short% as **re-probe once**, not auto-fail.
