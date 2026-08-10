# SC-S02 — install-cli / rebuild refresh staged binary + rebind when enabled

Run: `C9C3159E-0439-4A1A-8DC9-90DB8E176673` (model_opencode_deepseek_v4_pro)
Status: **done** (2026-08-09) — commit `5de87193`; Works Test 9/9  
Slice: SC-S02 (small)  
Historical packet: [`Serve_Continuity.md`](../../../archive/phases/Serve_Continuity.md) §6 + §4 SC-S02
Executor: Kimi K3 if 5h remaining ≥15%; else DeepSeek V4 Pro

## Goal

Whenever the user installs/rebuilds the CLI, refresh the **staged stable binary**
in the same transaction. If the product LaunchAgent is enabled (plist present),
re-bind it so KeepAlive restarts onto the new bytes — never leave an enabled
agent pinned to a stale image or the debug symlink.

`rebuild_cli.sh` already ends with `install-cli` — hook **only** the install-cli
success path (CLI layer), so rebuild inherits the refresh.

## Copy-paste prompt

```text
You are implementing Serve Continuity slice SC-S02 only — keep it small.

Read ONLY:
- docs/phases/sprint/serve-continuity/SC-S02-install-refresh.md (this file)
- docs/archive/phases/Serve_Continuity.md §6 (stable binary YES; refresh on install-cli/rebuild) + §4 SC-S02
- Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift
- Packages/AllnighterCore/Sources/AllnighterEngine/ServeStableBinary.swift
- Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift (runInstallCLI)
- Packages/AllnighterCore/Sources/AllnighterCore/InstallCLI.swift (outcomes only — do NOT move Engine into Core)
- scripts/rebuild_cli.sh (confirm it already calls install-cli; no shell change unless a one-line comment is needed)
- docs/operations/Execution-Playbook.md — FILTERED tests ONLY

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift
  Add `refreshAfterInstall()` (or equally small named method):
  1. ALWAYS stage from currentExecutableURL → stagedBinaryURL (even if file already exists) via injectable `stage`
  2. If plistExists(plistURL): bootout + write product plist ProgramArguments=[stagedPath,"serve"] KeepAlive/RunAtLoad + bootstrap (same shape as enable; refuse /.local/bin/)
  3. If plist absent: stage only — do NOT bootstrap (opt-in stays opt-in)
  4. Structured Codable result: staged, bytesReplaced, rebound (bool), outcome enum (refreshed / refreshedAndRebound / failed), detail
  5. All launchd/file effects injectable — NO live launchctl in unit tests
- Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift
  After successful InstallCLI.run (installed / repaired / alreadyInstalled — NOT printOnly / failed):
  call ServeLifecycle().refreshAfterInstall() best-effort; surface a one-line note on failure in human/json without failing the install itself (install-cli success must still succeed; refresh failure is additive warning, never roll back the symlink)
- Tests: Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeInstallRefreshTests.swift (fixtures only)
  Cover: stage-only when plist absent; stage+rebind when plist present; refuse local-bin; stage failure → failed; bootout/bootstrap failure → failed; install path not required in Engine tests

Do NOT:
- Change InstallCLI.swift to depend on AllnighterEngine
- SMAppService
- Change enable()/disable() semantics except shared helpers if tiny
- Capacity* / ServeAutoLaunch
- Unfiltered suite or check.sh — ONLY:
  scripts/swift-test.sh --filter ServeInstallRefreshTests
- Leave uncommitted

Works Test:
  scripts/swift-test.sh --filter ServeInstallRefreshTests

Done when:
- [ ] install success always refreshes staged binary
- [ ] enabled agent rebinds; disabled stays disabled (stage only)
- [ ] never ProgramArguments under /.local/bin/
- [ ] Filtered tests green
- [ ] Explicit-path commit

Follow Execution-Playbook. Commit your own work.
```

## Capacity gate (PM)

`alln capacity` → Kimi `shortRemainingPercent` ≥ 15 → `model_kimi_k3`.  
Else → `model_opencode_deepseek_v4_pro` (no V5 in menu). Treat missing short% as **re-probe once**, not auto-fail.
