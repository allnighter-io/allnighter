# 2026-08-10 — Mac app demand-heal Dock fork bomb

```text
Tier: T3 Critical
Symptom / repro: Opening Allnighter.app floods the Dock with identical running
  icons; process table is mostly
  `…/Allnighter.app/Contents/MacOS/Allnighter serve`.
Bug fingerprint: Mac app launch + ServeAutoLaunch.ensureRunning +
  re-exec of .app/Contents/MacOS binary as `serve` + no CLI argv circuit
  breaker → infinite Dock instances
Attempt count: 1
Seam: ServeAutoLaunch executable resolution → Process spawn → Mac @main
  (ignores `serve`, paints Dock, demand-heals again)
Truth owner: ServeAutoLaunch.resolveServeExecutablePath /
  ServeAutoLaunch.ensureRunning (must launch a CLI `alln`, never the Dock
  app binary)
Lie-prone layer: “same running binary” self-relaunch (correct for `alln`,
  catastrophic for Allnighter.app); Dock dots look like many apps while
  argv is `serve`
Regression considered: BUG_PATTERNS
  `serve-autolaunch-must-not-reexec-mac-app-bundle`
Isolation harness: not required — kill test is unit-level path refusal +
  Mac argv circuit breaker; host proof is “open app → one Dock icon”
Missing kill test / proof: ServeAutoLaunchTests refuse .app path;
  Mac circuit breaker before demand heal
Fix boundary: ServeAutoLaunch (+ Mac AppDelegate circuit breaker). Do not
  teach the Dock app to run ServeDaemon.
Proof command / founder test:
  scripts/swift-test.sh --filter ServeAutoLaunchTests
  Founder: open Allnighter once → exactly one Dock icon; no `Allnighter serve`
  children that are themselves Dock apps.
```

## RCA

SC-S03 wired `ServeAutoLaunch.ensureRunning(optedOut: false)` into
`AppDelegate.applicationDidFinishLaunching`. Resolution used
`ProcessOwnership.resolveRunningExecutablePath`, which returns the Dock app
executable. `defaultLaunch` then spawns `<that> serve`.

`Allnighter.app`’s `@main` is SwiftUI GUI — it does not dispatch CLI `serve`.
Each child therefore:

1. activates as another Dock app,
2. demand-heals again,
3. spawns another child,

until the machine is saturated. `ServeDaemonProbe` never reports `.available`
because none of the children are the CLI serve daemon.

## What must never be allowed again

`ServeAutoLaunch` must never exec a path under `.app/Contents/MacOS/`. Mac app
launch with argv `serve` must exit without activating or demand-healing.
