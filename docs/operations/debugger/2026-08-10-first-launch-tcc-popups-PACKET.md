# 2026-08-10 — First-launch TCC popups (many)

```text
Tier: T3 Critical
Symptom / repro: Opening Allnighter on a cold / first launch surfaces many
  macOS privacy dialogs (Downloads / Documents / network-volume class)
  attributed to "Allnighter" before any Setup / Refresh / Run click.
Bug fingerprint: AllnighterMac cold launch + capacity default-ON silent
  acquire + strip loadLive→refreshAll + ServeAutoLaunch under GUI TCC +
  remote relay bootstrap / Launch Authority process-quiet bypass
Attempt count: ≥4 prior TCC boundaries (H0–H6, worker CWD, relay packet,
  resident probe); this is a new authority path past those gates
Seam: AppDelegate / CapacityResidentService / CapacityStripModel /
  RemoteAccountModel / native CapacityPaneReader+Codex spawn CWD
Truth owner: Launch Authority process-quiet law; CapacityResidentService
  setEnabled re-arm; AppDelegate launch spawners; macOS TCC attribution
Lie-prone layer: Green H0–H6 / LaunchAuthorityProbeTests / AppModelTests
  cache gates — silent about capacity, ServeAutoLaunch, and remote bootstrap
Regression considered: BUG_PATTERNS + DEBUGLOG 2026-06-16 / 2026-07-20 /
  2026-08-10 serve fork-bomb
Isolation harness: waived for this slice — product-path kill tests name the
  three spawners; signed-app TCC harness remains the open deferred proof
Missing kill test / proof (now added): cold-launch re-arm no acquire;
  loadLive no refreshAll; Mac app source has no ServeAutoLaunch;
  bootstrap has no ensureRelayRunning
Fix boundary: process-quiet cold launch only. Explicit Enable / Refresh /
  Setup / Run / sign-in may still probe. Do not add FDA or broad entitlements.
Proof command / founder test:
  scripts/swift-test.sh --filter 'CapacityResidentServiceTests|CapacityStripModelTests|ServeAutoLaunchTests|AppModelTests'
  Founder: tccutil reset → open Allnighter → touch nothing → zero dialogs,
  one Dock icon
```

## RCA

Three independent launch-time spawners re-opened the Launch Authority hole
after H0–H6 closed CLIDetector-only probes:

1. **Capacity (default ON):** `AppDelegate` calls
   `CapacityResidentService.setEnabled(true)` which wired the scheduler **and**
   fired an immediate full-bench `.launch` acquire (every vendor CLI). Home
   strip `loadLive` also called `refreshAll()` when no snapshot existed.
2. **ServeAutoLaunch (SC-S03):** Dock app spawned `<running binary> serve`.
   When resolution returned the `.app` executable, children re-entered `@main`,
   demand-healed again (Dock fork-bomb), and any real CLI serve under app
   ancestry attributed capacity probes to Allnighter.
3. **Remote bootstrap:** `.task { remoteAccount.bootstrap() }` treated a
   persisted Supabase session as consent to spawn bash relay with
   `currentDirectoryURL = repoRoot` (often under Documents).

Native agy/codex capacity helpers (`CapacityPaneReader.runHeadless`,
`CodexNativeCapacityProbe.runJSONRPC`) also inherited ambient CWD — a
Documents TCC path even when PTY probes used ProbeScratch.

## Fix

| Spawner | Change |
| --- | --- |
| Capacity re-arm | Scheduler only; immediate `.launch` only on explicit OFF→ON |
| Strip `loadLive` | Placeholders + `needsLiveRefresh`; no `refreshAll()` |
| ServeAutoLaunch | Removed from `AppDelegate` (CLI/`alln run`/Loop keep demand heal) |
| Remote bootstrap | Pairing refresh only; relay on sign-in / explicit start |
| Native headless | `currentDirectoryURL = ProbeScratch` |

## What must never be allowed again

A later feature may not add a launch-time `Process` / vendor-CLI / login-shell
spawn while leaving Launch Authority gates scoped to `CLIDetector` alone.
Any new app-open side effect that can touch the filesystem under the Dock
app's TCC identity needs a wall-reachable "zero child processes on cold
launch" gate — or an explicit waiver naming the user intent that owns it.
