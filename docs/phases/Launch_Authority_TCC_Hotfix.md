# Launch Authority TCC Hotfix

Status: HOTFIX, execution-ready
Owner: Mac app launch policy + Core setup detection
Updated: 2026-06-16

Founder intent:
Opening Allnighter must never produce macOS Documents, Downloads, or network
volume permission popups. If this remains true, the app is dead.

Product value:
Restore launch trust. The first user action is "use Allnighter", not "defend my
filesystem from Allnighter."

Trusted workflow slice:
Cold-launch the Mac app by `open`. The main window renders usable cached/unknown
team state. No shell, worker CLI, smoke probe, model call, protected-folder read,
or quota-bearing action runs until the user explicitly clicks setup/recheck/run.

Non-goals:
- Do not add Full Disk Access as the solution.
- Do not add broad entitlements or permission prompt copy as the solution.
- Do not hide the prompts by suppressing errors while work still runs.
- Do not remove `CLIDetector`, `SetupStore`, or health == runs.
- Do not build the full Setup WOW UI in this emergency slice.

## First Principles

Launch is a view act. It may read bundled app resources and Allnighter-owned
Application Support state. It may not explore the user's machine.

Readiness is not worth violating launch trust. A stale or unknown badge is better
than a surprise TCC dialog.

Smoke probes are work. They run real provider CLIs (`codex exec`, `claude -p`,
`grok -p`, `agy --print`), can spend quota, can touch auth/config/project state,
and must require explicit user intent.

PATH discovery is also authority. A login shell can read login profiles, version
manager hooks, mount helpers, and user folders. It must not run before UI.

## Current State

Three independent mechanisms can trigger TCC under Allnighter's identity:

| Layer | Current trigger | Symptom |
| --- | --- | --- |
| Dev bundle location | `scripts/dev.sh` launches `.app` from `~/Documents/.../.build/mac` | Documents prompt |
| Login-shell PATH capture | `AllnighterMacApp.init()` calls `LoginShell.applyToProcessEnvironment()` | Downloads/network volume prompt via shell profiles |
| Auto detection + smoke | `RootView.onAppear` calls `AppModel.runDetection()`, which calls `CLIDetector.probeAll(... smoke: true)` | Downloads/network/repo/config prompts plus quota-bearing smoke |

The June 16 `-lic` to `-lc` mitigation reduced interactive `.zshrc` exposure but
did not change when the app is allowed to spawn shells or CLIs. It was a symptom
reducer, not an authority fix.

## Truth Owner

- Launch authority policy: `AppModel` + `RootView` + `AllnighterMacApp`.
- Probe semantics: `CLIDetector`.
- Persisted setup truth: `SetupStore`.
- Runtime health == runs: cached `ToolInvocation` consumed by `WorkerRunner` and
  `TeamService`.

## Lie-Prone Layers

- `RootView.onAppear`: easy to treat as harmless UI setup while it starts live
  machine probing.
- `LoginShell.applyToProcessEnvironment()`: global process mutation hides a real
  shell spawn before first paint.
- Health badge/team dropdown: can imply "checking..." requires active probes.
- Dev `allapp`: looks like normal app launch but runs an app bundle from
  `~/Documents`.

## New Semantic Rules

1. App launch is process-quiet before explicit setup/recheck/run.
2. App launch renders only cached setup truth or unknown state.
3. Full smoke is explicit user intent only.
4. Login-shell PATH capture is explicit user intent only.
5. Any permitted probe uses a neutral CWD under Allnighter-owned scratch, never
   inherited repo/Documents CWD.
6. Dev builds used for launch/TCC testing must not live under Documents,
   Downloads, Desktop, iCloud Drive, or a network volume.
7. `installedNotProbed` is an honest launch state. Do not upgrade it to ready
   without a successful explicit smoke.
8. **Interactive resolve (`-lic`) is allowed ONLY on an explicit, user-initiated
   setup/recheck probe** (Track 0.1, founder-approved 2026-06-16). The earlier
   `-lic`→`-lc` change was a *launch-time* symptom reducer; it must NOT be
   re-applied to the explicit-setup path. Detection at explicit setup resolves
   through `-lic` so the user's `.zshrc` PATH (bun/asdf/custom prefixes) is seen —
   the one-time TCC prompt is acceptable because the user asked for it. The
   default (`ShellResolver(interactive: false)` / `-lc`) stays TCC-safe and is the
   only mode any launch/background path may use. `CLIDetector(interactive:)` makes
   this authority visible at every call site; do not flip it true except at
   explicit setup. Runs still reuse the cached absolute `ToolInvocation`, so no
   per-run shell is spawned (health == runs).

## Duplicate Truth To Delete

- The idea that GUI launch should be fresher than default `alln doctor`.
- The current setup spec line that launch can run a background full smoke. This
  hotfix supersedes it: launch can render cache; full smoke belongs to Setup,
  Re-check, or explicit Run recovery.
- Any UI copy/state that treats automatic launch probes as required for a usable
  first screen.

## Implementation Plan

### Slice H0 - Stop The Bleed

Goal:
Remove all automatic process spawning from cold launch.

Edits:
- Remove `LoginShell.applyToProcessEnvironment()` from
  `AllnighterMacApp.init()`.
- Replace `RootView.onAppear -> model.runDetection()` with a no-spawn cache load.
- Rename the `didInitialDoctor` state if touched; it gates detection, not Doctor.

Expected behavior:
Cold launch shows cached tool state if present. With no cache, show unknown/not
checked state and a visible setup/recheck entry point. It does not run shell,
`command -v`, `--version`, or smoke.

### Slice H1 - Split Detection Authority

Goal:
Make probe authority explicit in the type/API surface so this cannot regress.

Create separate AppModel commands:

```swift
loadCachedSetupState()
runLightSetupRefresh(userInitiated: Bool)
runFullSetupProbe(userInitiated: Bool)
```

Rules:
- `loadCachedSetupState`: no `CommandRunner`, no `Process`, no shell, no writes
  except normal in-memory state.
- `runLightSetupRefresh`: optional; only allowed after user intent unless proven
  TCC-safe. No smoke. Prefer direct cached path validation; be skeptical of shell.
- `runFullSetupProbe`: requires `userInitiated == true`; may run shell resolve,
  version, and smoke; visible progress required.

Do not keep one `runDetection()` method with flags that call sites can misuse.
The method names must make authority visible.

### Slice H2 - Align GUI With CLI Defaults

Goal:
The GUI does not become more invasive than the CLI.

Rules:
- Default GUI launch mirrors default `alln doctor`: no full smoke.
- Explicit full setup/recheck mirrors `alln doctor --full` or `alln detect`.
- If the user clicks "Check tools", say that Allnighter will launch local CLIs
  to verify readiness.

Implementation detail:
When a probe path calls `CLIDetector.probeAll`, pass `smoke: false` for light
mode and `smoke: true` only for explicit full setup/recheck.

### Slice H3 - Neutralize Probe CWD

Goal:
Any allowed child process starts from Allnighter-owned scratch, not the repo or
the app bundle location.

Edits:
- Add an owned scratch directory under `AllnighterPaths.support`, for example
  `AllnighterPaths.support/ProbeScratch`.
- Ensure `CLIDetector.runResolved`, `ModelHealthChecker`, and any Doctor/full
  probe path pass that CWD instead of `nil`.
- Keep worker runs and dispatch runs using their existing explicit working dir
  semantics; this slice is about setup/health probes.

Reason:
`workingDirectory: nil` lets child CLIs inherit an unsafe CWD. In development
that can be the repo under `~/Documents`.

### Slice H4 - Dev Launch Outside Protected Folders

Goal:
Eliminate the dev-only Documents prompt amplifier.

Edits:
- Change `scripts/dev.sh` derived data/output path from `$ROOT/.build/mac` to an
  unprotected location such as:

```text
~/Library/Developer/Allnighter/Build
```

or:

```text
/tmp/allnighter-mac-build
```

Rules:
- Keep logs easy to find.
- Do not break `allapp build`, `allapp test`, or deterministic relaunch.
- Document that TCC-sensitive launch testing must use a copied app outside
  protected folders.

### Slice H5 - Explicit Probe UX

Goal:
Make the first required probe a user-owned act.

Minimum UI:
- A visible "Check tools" or "Set up team" action where health appears.
- Progress states for checking.
- Honest outcomes: ready, not installed, needs login, installed not probed,
  probe failed.

Do not block the whole app on a silent probe. If no tool is ready and no cache is
present, show a setup-needed state with a button, not surprise dialogs.

### Slice H6 - Regression Gates

Goal:
Make "process-quiet launch" wall-reachable.

Required tests:

1. Unit/policy test:
   Inject a recording runner or launch policy seam. Exercise app/model launch
   cache path. Assert zero attempted process runs before explicit user intent.

2. Full-probe intent test:
   Exercise the explicit setup/recheck path. Assert that process runs are allowed
   only when `userInitiated == true` and that full smoke passes `smoke: true`
   only there.

3. Neutral CWD test:
   Verify setup/health probe child commands receive an Allnighter-owned scratch
   CWD, not `nil`.

4. Dev path test or script assertion:
   Verify `scripts/dev.sh` launch output is outside protected folder roots.

Proof commands to add/use:

```text
swift test --package-path Packages/AllnighterCore
xcodebuild test -scheme AllnighterMac -destination 'platform=macOS'
bash scripts/check.sh
```

Founder Works Test:

```text
tccutil reset All com.allnighter.mac
open <Allnighter.app outside Documents/Downloads/Desktop/iCloud/network volumes>
```

Pass condition:
No Documents, Downloads, Desktop, network-volume, or Full Disk Access prompt
appears before clicking setup/recheck/run.

## Implementation Impact

Mac app:
- Startup becomes cache-only.
- Health surfaces must tolerate unknown/installedNotProbed state.
- Setup/recheck buttons become the first live-probe affordance.

Core/Engine:
- `CLIDetector` remains the probe truth owner.
- Add or expose probe mode intentionally; avoid default `smoke: true` for app
  launch call sites.
- Add neutral CWD support for setup/health probes.

CLI:
- Preserve current default: `alln doctor` is quota-free/non-smoke.
- Preserve explicit full checks: `alln doctor --full` and `alln detect`.

iOS:
- No direct change. iOS must not assume Mac app launch has fresh live probe
  state. It may display cached/unknown until the Mac performs explicit setup.

Driver/protocol:
- No manifest changes required for the hotfix.
- Later manifests can add cheap status commands, but that is not required to
  stop launch TCC.

Auth/privacy/permissions:
- Strongly improved. No new permissions.
- No Full Disk Access.
- No mandatory third-party cloud.
- No user data leaves the machine as a side effect of app launch.

## Risk Register

| Risk | Response |
| --- | --- |
| Health badge looks stale | Accept; stale is better than violating launch trust. |
| First run has no ready team until user clicks setup | Accept; make setup action obvious. |
| Workers cannot run because no cached invocation exists | On explicit Run, route through setup/recheck or run with honest missing invocation failure. Do not probe silently. |
| Existing code expects `toolStatuses` to mean checked-now | Rename/annotate presentation state as cached/unknown where needed. |
| Dev script path change disrupts local loop | Preserve command shape and logs; only move derived output. |

## Done When

- Cold app launch spawns zero shells and zero worker CLIs before explicit user
  intent.
- `AllnighterMacApp.init()` no longer runs `LoginShell`.
- `RootView.onAppear` does not call full detection.
- Full smoke probes are reachable only from explicit setup/recheck/full Doctor
  actions.
- Setup/health probes use neutral Allnighter-owned CWD.
- `scripts/dev.sh` launches from outside protected user folders.
- Regression tests cover process-quiet launch, explicit full-probe authority,
  neutral CWD, and dev output location.
- Founder Works Test passes after TCC reset.
- The debugger backlog item
  `Mac app launch is process-quiet before explicit setup/recheck/run` is closed
  with a wall-reachable proof command.

## Open Questions

1. Should light refresh exist at all before the full Setup UI ships, or should
   the hotfix be strictly cache-only on launch?
2. Should explicit Run with no cached invocation trigger a setup-required sheet
   before running, or attempt a direct run and fail honestly?
3. Should `CLIDetector.probeAll` keep `smoke: true` as its default, or should the
   API remove the default to force every call site to choose?
4. Should dev launch output use `~/Library/Developer/Allnighter/Build` or `/tmp`?

## Supersedes

Until this hotfix is complete, this doc supersedes any setup-phase language that
allows background full smoke on ordinary app launch.
