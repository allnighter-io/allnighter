# Launch TCC Popups - Mentor Packet

Date: 2026-06-16
Status: investigation only; no runtime fix applied

## Executive Read

Allnighter is triggering macOS privacy prompts on ordinary app launch:

- "Allnighter" would like to access files in your Documents folder.
- "Allnighter" would like to access files on a network volume.
- "Allnighter" would like to access files in your Downloads folder.

This is a `T3 Critical` permission regression. The app is unusable because system
permission dialogs appear before the user has asked Allnighter to run a team,
check tools, open files, or configure setup.

The strongest RCA is not one single bad CLI. It is an authority boundary bug:

1. The dev app is launched from a build product under `~/Documents`.
2. App startup runs login-shell PATH capture before the first window.
3. `RootView.onAppear` runs live CLI detection on every launch.
4. Live detection defaults to full smoke probes, so it can run `codex exec`,
   `claude -p`, `grok -p`, and `agy --print` under the GUI app's TCC identity.

The previous mitigation changed shell mode from interactive login shell (`-lic`)
to non-interactive login shell (`-lc`). That reduces `.zshrc` exposure, but it
does not remove launch-time shell/CLI execution. It also does not fix the dev
bundle living under `~/Documents`.

## Debug Packet

Tier: `T3 Critical`

Symptom / repro:
Launch the Mac app. Before useful interaction, macOS prompts for Documents,
Downloads, and network-volume access.

Bug fingerprint:
`Apps/AllnighterMac launch + TCC protected-folder prompts + startup shell/CLI probe authority leak`

Truth owner:
`AppModel` launch/setup state plus `CLIDetector` probe policy. The durable setup
truth is `SetupStore` under Application Support.

Lie-prone layer:
SwiftUI startup (`RootView.onAppear`) and startup PATH bridging present background
tool readiness as harmless UI health, but they execute child processes that can
touch protected user locations.

Regression considered:
This appears repeated. Git history shows a 2026-06-16 TCC-targeted mitigation
(`e7cc36c fix(mac): unify titlebar, fix icon/name/TCC, codex service_tier`) that
changed shell execution to `-lc`, but the launch path still performs detection
and full smoke probes.

Missing kill test / proof:
No test proves "first window open does not spawn shell/CLI processes" or "launch
does not access protected user folders." No fixture covers TCC-triggering shell
profiles, network-volume mounts, Downloads access, or app bundle location under
Documents.

Fix boundary:
Do not patch random CLI manifests or SwiftUI paint. The fix must change startup
authority:

- first window render must not run login shells or worker CLIs;
- cached setup state may render;
- explicit user action may run a bounded recheck/setup flow;
- dev launch should avoid a `.app` path under protected folders, or the limitation
  must be documented until fixed.

Proof command / founder test:
Needs a new wall-reachable unit/fixture test that injects a process runner and
asserts launch/render uses zero child processes before explicit setup/recheck.
Founder test: reset TCC for `com.allnighter.mac`, launch via `open`, observe no
Documents/Downloads/network-volume dialogs before clicking a setup/recheck/run
control.

## Evidence

### Startup invokes login shell before UI

`Apps/AllnighterMac/Sources/AllnighterMacApp.swift:26` initializes the app by
calling:

```swift
LoginShell.applyToProcessEnvironment()
```

`Apps/AllnighterMac/Sources/AppConfig.swift:115` implements this by spawning the
user shell:

```swift
process.executableURL = URL(fileURLWithPath: shellPath)
process.arguments = ["-lc", "printf %s \"$PATH\""]
```

This is less risky than `-lic`, but still executes login shell startup files as
the Allnighter app. Any login profile, version manager, path helper, mount probe,
or shell integration that reads Downloads/Documents/network volumes can raise a
TCC prompt attributed to Allnighter.

### Launch view runs detection every appearance

`Apps/AllnighterMac/Sources/RootView.swift:69`:

```swift
.onAppear {
    GlobalHotKey.enable()
    if model.isConfigurationBroken {
        showMissingDriversAlert = true
    } else if !didInitialDoctor {
        didInitialDoctor = true
        model.runDetection()
    }
}
```

This means the first app screen initiates live detection without explicit user
consent.

### Detection performs full smoke by default

`Apps/AllnighterMac/Sources/AppModel.swift:570` calls:

```swift
CLIDetector(commandRunner: SubprocessCommandRunner())
    .probeAll(registryCopy.all, models: modelLabels, now: Date())
```

`Packages/AllnighterCore/Sources/AllnighterEngine/CLIDetector.swift:95` defaults
`smoke: Bool = true`.

So ordinary launch does:

- shell resolve for all bins;
- version checks;
- smoke probes;
- cache write.

### Smoke probes invoke real agent CLIs

Driver manifests include:

- `claude -p "Reply with the single token ALLNIGHTER_READY" --model {{model}}`
- `codex exec --skip-git-repo-check --color never "Reply with the single token ALLNIGHTER_READY"`
- `grok -p "Reply with the single token ALLNIGHTER_READY" -m {{model}} --output-format plain`
- `agy --print "Reply with the single token ALLNIGHTER_READY" --model "{{model}}" --dangerously-skip-permissions`

These are not harmless metadata reads. They can load each CLI's config, auth,
project discovery, shell wrappers, caches, extensions, or provider runtimes. All
of that runs under Allnighter's process ancestry and can trigger TCC dialogs for
the app.

### Dev app path is itself under Documents

`scripts/dev.sh:15` sets:

```bash
DERIVED="$ROOT/.build/mac"
APP="$DERIVED/Build/Products/Debug/Allnighter.app"
```

For this clone, `ROOT` is:

```text
/Users/mike/Documents/GitHub/Allnighter
```

So the launched app bundle is inside `~/Documents`. Reading bundled resources,
frameworks, or metadata from its own app path may itself explain the Documents
prompt. It does not explain Downloads or network-volume prompts, which point to
shell/CLI startup behavior.

## Spec Conflict

`docs/phases/setup/01_CLI_Detection_Auth_And_Bench.md` says launch should use
cached state plus fast re-validation, while setup/re-entry forces a fresh sweep.
The current app instead performs full detection with smoke from `RootView.onAppear`.

Relevant spec intent:

- `SetupStore` persists per-tool invocation/status/version.
- On launch, populate instantly from cache.
- Full detection belongs to first-run Setup or explicit recheck.
- The app should not require Full Disk Access by default.

This bug is the practical consequence of treating "health badge freshness" as
more important than first-launch permission quietness.

## What Was The Agent Allowed To Do That Must Never Be Allowed Again?

The app was allowed to execute login shells and model-provider CLI smoke probes
from the first rendered window, without an explicit user setup/recheck/run
action, and without a regression test proving launch is process-quiet.

Proposed regression law:

```text
Mac app launch may render cached setup truth, but must not spawn shells, worker
CLIs, or smoke probes before explicit user intent.
```

## Mentor Questions

1. Should first launch show a full-window Setup screen that asks permission before
   any live probe, or should it render cached/unknown state and wait for the user
   to click "Check tools"?
2. Should `LoginShell.applyToProcessEnvironment()` be removed from app init and
   moved behind explicit setup/recheck/run, now that runs can use cached
   `ToolInvocation`?
3. Should default app launch ever perform smoke probes, or should launch do only
   zero-process cache render plus maybe non-spawning executable-path validation?
4. Should the dev script build the `.app` outside `~/Documents` to eliminate the
   self-inflicted Documents prompt during development?
5. What is the minimum proof gate: injected process-runner unit test, built-app
   smoke with TCC reset, or both?

## Candidate Fix Boundary For Later

Not implemented in this pass.

Recommended shape:

1. Split `AppModel.runDetection()` into `loadCachedSetupState()`,
   `fastNonSmokeRevalidate()`, and `runFullSetupProbe(userInitiated:)`.
2. On `RootView.onAppear`, only enable hotkey, load cached setup state, and show
   setup/unknown UI. Do not run `CLIDetector.probeAll(... smoke: true)`.
3. Move login-shell PATH capture out of `AllnighterMacApp.init()` or gate it
   behind explicit setup/recheck/run.
4. Make full smoke probes require explicit user action and visible progress.
5. Add a test runner that fails if first-window launch calls `CommandRunner.run`.
6. Move dev `DERIVED` outside `~/Documents` or document that debug builds in
   protected folders can create false-positive TCC prompts.

## Investigation Notes

I did not launch the app during this investigation to avoid generating more TCC
prompts. Evidence is from source, docs, git history, and the provided screenshots.
