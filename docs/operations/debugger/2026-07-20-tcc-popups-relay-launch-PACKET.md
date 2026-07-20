# TCC Popups Returned — Remote Relay Launch Authority Leak

Date: 2026-07-20
Status: investigation only; no fix applied (per intake constraint)

## Debug Packet

Tier: `T3 Critical` (permission regression, repeated, second occurrence of the
same fingerprint class → Regression Law review required per Debugger.md:31)

Symptom / repro:
Founder sees macOS TCC prompts attributed to "Allnighter" (Documents / Downloads /
network-volume class), ~10 times on 2026-07-19. Previously fixed by Launch
Authority TCC Hotfix H0–H6 (2026-06-16) and worker neutral-CWD `2f57af74`.

Bug fingerprint:
`AllnighterMac first-window .task → RemoteAccountModel.bootstrap → /bin/bash relay
script with currentDirectoryURL = repoRoot under ~/Documents → swift build + resident
alln serve daemon inheriting Allnighter's TCC responsible process`

Truth owner:
`RemoteAccountModel` relay lifecycle + `RemoteMacRelayLauncher` spawn authority.
The durable truth is the persisted Supabase session at
`~/Library/Application Support/Allnighter/Config/Remote/supabase_session.json`,
which is treated as standing consent to spawn at launch.

Lie-prone layer:
The **launch-authority regression gates** (`LaunchAuthorityProbeTests`,
`AppModelTests`). They report "process-quiet launch" as PROVEN and pass green,
but they only bind the detection/probe subsystem. They are silent about the app
as a whole, so a second launch-time spawner walked straight past them.

NOT the truth owner: SwiftUI. The `.task` modifier is the trigger, not the owner.
NOT the truth owner: AgentOS, Kimi, `CLIDetector` — all disproven below.

Regression considered:
Yes — **new path, not a regression of the old fix**. The H0–H6 fix is intact and
still enforced. `c92d7006` (2026-06-26, "feat(mac): optional iPhone remote
control in Settings") landed 10 days after the hotfix and re-opened the same
authority hole through a subsystem the hotfix never covered.

Missing kill test / proof:
There is no test asserting **"app launch spawns zero child processes."** The
regression law was written as a universal claim and encoded as four
subsystem-local assertions. Also missing: TCC log correlation (see Unknowns).

Fix boundary:
Do not patch SwiftUI, the detection path, the Kimi manifest, or AgentOS.
The fix must change **relay launch authority**:
- a persisted session is not consent to spawn *this* launch;
- relay start belongs behind explicit user intent (or a real LaunchAgent that
  owns its own TCC identity, not a GUI-app child);
- no Allnighter-spawned process may take a CWD under a protected folder —
  `RemoteMacRelayLauncher` must not pass `repoRoot`;
- `serve_remote.sh` must not run `swift build` under app ancestry.

Proof command / founder test:
```
# 1. Kill the resident daemon and clear relay state
kill $(cat ~/Library/Developer/Allnighter/ios-live-serve.pid) 2>/dev/null
rm -f ~/Library/Developer/Allnighter/ios-live-serve.{pid,log}

# 2. Reset TCC for the app, then cold launch and touch nothing
tccutil reset All com.allnighter.mac
open -a Allnighter

# 3. RED today: this file is recreated and grows a new serve line
cat ~/Library/Developer/Allnighter/ios-live-serve.log

# 4. RED today: a bash/serve child exists under the GUI app
pgrep -lf 'ios_live_mac_agent|serve_remote|alln serve'
```
GREEN condition: no log file, no child process, no dialog before the founder
clicks a relay/setup control.

---

## Evidence

### The path is live on this machine, and it fired yesterday

```
~/Library/Application Support/Allnighter/Config/Remote/supabase_session.json   # exists → isSignedIn == true
~/Library/Developer/Allnighter/ios-live-serve.log    Jul 19 08:36   # 6 serve starts logged
~/Library/Developer/Allnighter/ios-live-serve.pid    Jul 19 08:36
```
```
$ ps -p 88044 -o pid,lstart,command
88044 Sun Jul 19 08:36:50 2026 /Users/mike/Documents/GitHub/Allnighter/Packages/AllnighterCore/.build/arm64-apple-macosx/debug/alln serve
```
A resident daemon, started the day of the popups, **executing from a binary under
`~/Documents`**, spawned as a descendant of the GUI app.

### The launch chain

`Apps/AllnighterMac/Sources/AllnighterMacApp.swift:117-119` — on the main window:
```swift
.task { await remoteAccount.bootstrap() }
```
`Apps/AllnighterMac/Sources/RemoteAccountModel.swift:27-32`:
```swift
func bootstrap() async {
    refreshSignedInState()
    guard isSignedIn else { return }
    await refreshPendingPairingRequests()
    await ensureRelayRunning()
}
```
The gate is `isSignedIn = (try? sessionStore.load()) != nil`
(`RemoteAccountModel.swift:94-97`) — *prior* intent, persisted, not intent at this
launch. `ensureRelayRunning()` runs unconditionally for a signed-in Mac.

`Apps/AllnighterMac/Sources/RemoteMacRelayLauncher.swift:21-24`:
```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/bash")
process.arguments = [script.path, "ensure"]
process.currentDirectoryURL = repoRoot        // ← ~/Documents/GitHub/Allnighter
```
This is the exact condition `WorkerInvocationCWD.swift:10-13` warns against, in a
file that never routes through the chokepoint that enforces it.

`scripts/ios_live_mac_agent.sh:37` → `nohup bash scripts/serve_remote.sh &`
`scripts/serve_remote.sh:19-25`:
```bash
ALLN_BIN="${ALLN_BIN:-$(swift build --package-path "$ROOT/Packages/AllnighterCore" --disable-sandbox --product alln --show-bin-path 2>/dev/null)/alln}"
if [[ ! -x "$ALLN_BIN" ]]; then
  echo "Building alln..."
  ALLN_BIN="$(swift build ... --show-bin-path)/alln"
fi
exec "$ALLN_BIN" serve "$@"
```
So one cold launch can produce: `bash` → `bash` → `swift build` (full package
traversal under `~/Documents`, sandbox disabled) → a long-lived `alln serve`.

### Why ~10 prompts, not one

Three multipliers, all under one responsible process:
1. `bootstrap()` runs per main-window `.task`, so every cold launch re-spawns the
   bash chain — even when `serve_running()` short-circuits, the shell still runs
   with `cwd = repoRoot`.
2. `swift build` runs on every serve start that can't resolve a bin path.
3. `alln serve` is **resident** and is the process that executes remote runs; its
   own CWD is the inherited `repoRoot`, and every worker CLI it spawns inherits
   the same responsible process.

### TCC attribution — why the dialog says "Allnighter"

A child spawned via `posix_spawn`/`fork` inherits its parent's **responsible
process** unless the parent calls `responsibility_spawnattrs_setdisclaim()`.
Allnighter does not. So `Allnighter.app → bash → swift build / alln serve → worker
CLI` all carry RP = `Allnighter.app`, and any access to `~/Documents`,
`~/Downloads`, or a network volume prompts as "Allnighter". **This is independent
of the child's code signature** — signing only lets a process become its own TCC
subject, which requires LaunchServices-launched bundles, not spawned CLIs.

### Why the gates stayed green

`ed78786e` (H6) states its own scope:
> Engine gates (LaunchAuthorityProbeTests, recording CommandRunner): every probe
> child (resolve/version/smoke) launches from the neutral scratch CWD…
> AppModel gates: `loadCachedSetupState()` never starts detection…

Verified by running them: `LaunchAuthorityProbeTests` 5/5 pass,
`WorkerRunnerCWDTests` 7/7 pass. They assert probe **hygiene**, never launch
**silence**. `c92d7006` added a spawner in `Apps/AllnighterMac` that no gate observes.

---

## Ruled Out

**Kimi (`bb2ea097`) — REFUTED as the cause.** Its commit message claims K3 became
the flagship-tier default so "Auto resolves to Kimi K3." The diff (+5/+1) never
touches `DefaultModelSettings.swift`. At that commit `model_kimi_k3` is in **zero
tiers**; at HEAD it is index 3 of `balanced` while `defaultTier == .flagship`, and
`SubstitutionResolver` never crosses tiers. Auto cannot reach Kimi. `codesign`
shows `~/.kimi-code/bin/kimi` is Developer ID (Beijing Moonshot, 2J9472RW75) with
hardened runtime — the same posture as claude/codex/grok/agy, and *better* than
`agent`/`cursor-agent`/`opencode`, which are shell scripts. The popup mechanism
also predates Kimi by a month.

**AgentOS (`e617a97d` / `bcadb313`) — NOT the cause, but structurally weakened.**
The neutral-CWD rule was re-homed, not dropped: `WorkerInvocationCWD.swift:23`
resolves `override ?? defaultWorkingDirectory ?? ensuredProbeScratchPath()`, and
`WorkerInvokerFactory.swift:64` wraps it as the **outermost** decorator, so all 16
worker call sites are covered. `rg 'workingDirectory: nil'` over Sources returns
zero hits. `AllnighterSpawnEnvironmentPolicy` is environment-only (team-depth
increment + tool-token scrub) and has never had a CWD notion.

**Ordinary run / chat — NOT the trigger.** Covered by the factory chokepoint.

**Cold detection / setup probe — NOT the trigger.** `AllnighterMacApp` has no
`LoginShell` call; the sole call site is `AppModel.swift:704` behind
`guard userInitiated`. `RootView.swift:371-384` calls only `loadCachedSetupState()`.

**Trigger path answer:** cold launch — but *not* the setup/detection lane. It is
the remote-relay lane, and only for a Mac with a persisted sign-in.

---

## Secondary Findings (independent of this bug, worth their own slices)

1. **`OpenCodeServeCoordinator.swift:210`** (AgentOS) spawns `opencode serve` with
   no `currentDirectoryURL` → inherits app CWD. Pre-existing since `31a6704b`, not
   a migration regression, but it is a live second instance of this class.
2. **`ProcessACPTransport.swift:39-41`** builds env from
   `ProcessInfo.processInfo.environment + extraEnv` and never applies
   `AllnighterSpawnEnvironmentPolicy` → no team-depth increment, no tool-token
   scrub on the warm/ACP path. `scripts/check_spawn_policy.sh` cannot see it
   because it greps only for `SubprocessCommandRunner()`.
3. **Kimi manifest has no `maxConcurrentSpawns`** (antigravity/cursor_agent/
   opencode all pin `1`) with `timeoutSeconds: 1800`. Unbounded concurrent spawns.
4. **Kimi downloads an adhoc-signed `fd`** to `~/.kimi-code/bin/fd`
   (`flags=0x20002(adhoc,linker-signed)`, no Team ID) and uses it to walk the
   workspace. Only such binary in the fleet.
5. **AgentOS is a path dependency with no `Package.resolved` pin**
   (`Packages/AllnighterCore/Package.swift:19` → `../../../AgentOS`), so
   AgentOS-side spawn changes land with zero Allnighter test signal.

---

## What Was The Agent Allowed To Do That Must Never Be Allowed Again?

A feature slice was allowed to add a launch-time shell spawn — with a CWD under a
protected folder, a `swift build`, and a resident daemon — into an app carrying a
standing "process-quiet launch" regression law, because the law was enforced only
inside the one subsystem that originally broke it.

Proposed regression law (supersedes the 2026-06-16 wording):

```text
No Allnighter-spawned process may take a working directory under a TCC-protected
folder, and app launch must spawn zero child processes before explicit user intent
in THIS session. A persisted credential is not consent to spawn. Enforcement must
be app-wide (a launch-time spawn counter over the real app), not per-subsystem.
```

## Unknowns / Missing Observations

- `TCC.db` is unreadable without Full Disk Access, and
  `log show --predicate 'subsystem == "com.apple.TCC"' --last 2d` returned no
  Allnighter rows — so the prompts are **not** timestamp-correlated to this chain.
  The correlation is circumstantial (same-day log writes, live daemon under
  `~/Documents`, signed-in state), not proven.
- The founder did not record **which** folder each of the ~10 prompts named.
  Documents vs Downloads vs network-volume would discriminate `swift build` from
  `alln serve` from a login-shell profile.
- Whether the founder cold-launched the app ~10 times on 2026-07-19, or saw
  repeats from the resident daemon, is unestablished. The log shows 6 serve
  starts total, not necessarily all on 07-19.
