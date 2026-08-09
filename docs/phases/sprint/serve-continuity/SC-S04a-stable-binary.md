# SC-S04a — Stage stable CLI binary (copy)

Status: **done** (2026-08-09) — commit `ef75ec50`; Works Test 7/7  
Slice: SC-S04a (tiny)  
Run: `7072A0A3-65EB-4736-A638-4B749167E207` (DeepSeek V4 Pro — capacity gate false-fail on None; Kimi was actually ~31%)  
SSOT: [`docs/phases/Serve_Continuity.md`](../../Serve_Continuity.md) §6 founder rulings + §4 SC-S04a  
Executor: prefer Kimi K3 if 5h remaining ≥15%; else `model_opencode_deepseek_v4_pro`  
(Note: menu has no DeepSeek V5 Pro — V4 Pro is the fallback.)

## Goal

One pure helper that **copies** the running `alln` binary to a stable product
path under Application Support (not a symlink into the debug build). No
LaunchAgent, no enable/disable, no install-cli wiring yet (S04b / S02).

## Copy-paste prompt

```text
You are implementing Serve Continuity slice SC-S04a only — smallest possible.

Read ONLY:
- docs/phases/sprint/serve-continuity/SC-S04a-stable-binary.md (this file)
- docs/phases/Serve_Continuity.md §6 (founder: stable binary YES) and §4 SC-S04a
- Packages/AllnighterCore/Sources/AllnighterCore/InstallCLI.swift (resolvedRunningBinary patterns only — do not change unless required)
- docs/operations/Execution-Playbook.md § Green Wall — FILTERED tests ONLY

Touch ONLY:
- New: Packages/AllnighterCore/Sources/AllnighterEngine/ServeStableBinary.swift
  - default destination: Application Support/Allnighter/CLI/alln (via AllnighterPaths if one exists; else FileManager URLs matching other Allnighter support dirs)
  - stage(from sourceURL) -> Result: copy atomically (temp + replace), set executable bit
  - NEVER symlink to the source
  - injectable FileManager / destination URL for tests
  - return staged URL + whether bytes were replaced
- New test: Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeStableBinaryTests.swift
  - temp dir fixtures only
  - proves copy not symlink
  - proves overwrite updates content
  - proves executable bit

Do NOT:
- LaunchAgent / serve enable / disable / repair changes
- InstallCLI / rebuild_cli wiring (SC-S02)
- Mac app changes
- SMAppService
- Unfiltered swift-test or check.sh — ONLY:
  scripts/swift-test.sh --filter ServeStableBinaryTests
- Leave uncommitted — explicit-path commit when green

Works Test:
  scripts/swift-test.sh --filter ServeStableBinaryTests

Done when:
- [ ] Stage copies (not symlink)
- [ ] Overwrite works
- [ ] Executable bit set
- [ ] Filtered tests green
- [ ] Explicit-path commit

Follow Execution-Playbook. Commit your own work.
```

## Capacity gate (PM)

Before dispatch: `alln capacity` — Kimi `shortRemainingPercent` must be ≥ 15.
Else use `model_opencode_deepseek_v4_pro`.

## Works Test

```bash
scripts/swift-test.sh --filter ServeStableBinaryTests
```
