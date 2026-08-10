# `alln serve` Recovery

Status: **CODE RED — READY FOR IMPLEMENTATION**
Owner: AllnighterCLI + AllnighterEngine
Created: 2026-08-10
Finalized: 2026-08-10
Supersedes: `docs/archive/phases/Serve_Continuity.md` and its unfinished logout/login
queue. The shipped code named there is evidence, not the forward design.

Related incident evidence:

- `docs/operations/debugger/2026-08-09-serve-launchagent-lwcr-PACKET.md`
- `docs/operations/debugger/2026-08-10-mac-serve-fork-bomb-PACKET.md`
- `docs/operations/debugger/2026-08-10-first-launch-tcc-popups-PACKET.md`
- `docs/operations/debugger/DEBUGLOG.md` (2026-08-09 and 2026-08-10)

Code truth at intake:

- `ServeDaemon`, `ServeDaemonProbe`, `ServeDaemonAdmission`
- `ServeLifecycle`, `ServeLaunchAgentStatus`, `ServeStableBinary`
- `ServeAutoLaunch`, `ServeAutoLaunchCLI`
- `InstallCLI`, `scripts/get-alln.sh`, `scripts/rebuild_cli.sh`
- `CapacityResidentService`, `CapacityRefreshScheduler`,
  `ProbeRecordRefreshScheduler`

This is the final recovery packet. It contains decisions, not hypotheses or a
menu of founder forks. Each slice may begin when its sprint work order is cut;
no additional product ruling is required.

---

## 1. Founder intent

### Raw request

`alln serve` must be dependable enough to own every background scheduler for a
CLI-only user. The Dock app must not be installed, open, or involved. Opening
the app must never start, repair, replace, or recursively launch serve.

### Product value

A user installs `alln` once and gets one supervised local scheduler that
survives terminal exit, daemon crash, logout/login, and CLI update. Pending
wake, Boost seed, vendor-backoff continuation, notifications, capacity refresh,
probe refresh, and optional relay remain alive without a ritual command and
without the Dock app.

### Trusted workflow slice

```text
install or update CLI
-> product atomically installs one canonical binary
-> product registers one per-user launchd agent
-> launchd starts one alln serve daemon
-> active health proves daemon identity and scheduler progress
-> process death is restarted by launchd
-> CLI-only background obligations continue
```

### Non-goals

- No scheduler or run semantics move into launchd.
- No second daemon, watcher daemon, cron job, menu-bar keeper, or app fallback.
- No root daemon, privileged helper, Full Disk Access, or Keychain change.
- No app-bundled `SMAppService` dependency for CLI users.
- No Linux/Windows service manager in this packet.
- No smart routing, capacity estimation, or new scheduler behavior.

---

## 2. CTO ruling

### 2.1 One host, one supervisor, one binary

The supported background path is:

```text
launchd user agent
  com.allnighter.resident-coordinator
    -> ~/.local/share/allnighter/bin/alln serve
         -> ServeDaemon
              -> all background schedulers
```

There is exactly one canonical installed CLI executable:

```text
~/.local/share/allnighter/bin/alln
```

The PATH entry (`~/.local/bin/alln`, `/usr/local/bin/alln`, or an explicit
install directory) is a symlink to that canonical executable. The LaunchAgent
points to the same canonical executable. Delete the second staged copy under
`~/Library/Application Support/Allnighter/CLI/` and delete its staging owner,
`ServeStableBinary`.

The dev build is also installed through this layout. `rebuild_cli.sh` may build
under `~/Library/Developer/Allnighter/CLI`, but `install-cli` copies the result
atomically to the canonical installed path before updating the PATH symlink or
the agent.

### 2.2 CLI install enables continuity by default

`alln install-cli` and the one-paste installer install/update the canonical
binary, register the LaunchAgent, start it, and verify active health in one
transaction. This is the product default, not a later ritual.

The user can opt out during installation with `--no-serve` (one-paste env:
`ALLN_NO_SERVE=1`) or later with `alln serve disable`. Disable persists a local
desired-state marker, so later CLI updates do not silently re-enable it.
`alln serve enable` clears the marker and converges the installation to healthy.

Install output must plainly say that Allnighter installed a per-user background
scheduler, why it exists, and how to disable it. This is the permission/startup
posture disclosure.

### 2.3 launchd owns continuity; commands never spawn a detached substitute

Delete `ServeAutoLaunch.ensureRunning`, `ServeAutoLaunchCLI`, and their call
sites. An ordinary command never starts an unsupervised `alln serve` child.
`alln run` stays runnable without serve because serve owns no run semantics.

A command that intentionally creates a future background obligation must call
one shared `ServeRequirement` preflight before writing that obligation. If the
supervised daemon is not actively healthy, it exits nonzero with the observed
state and `alln serve repair`; it does not queue work and hope a daemon appears.
The first audit covers Loop operations, Pending wake, Boost seed, vendor-backoff
continuation, notification scheduling, and cloud relay entry points.

### 2.4 The Dock app is outside the lifecycle

The Mac app must not import or call `ServeLifecycle`, `ServeAutoLaunch`,
`launchctl`, or any generic process path that starts `alln serve`. Keep the
existing early refusal for `Allnighter.app ... serve` until an architecture
check makes the impossible path permanent.

The Dock app also stops hosting periodic capacity/probe scheduling. It may:

- render durable history written by serve;
- request an explicit user refresh through the shared Engine operation; and
- show the read-only `alln serve status` projection.

It may not own a timer, wake observer, or silent vendor-CLI acquire. Remove the
periodic/wake portion of `CapacityResidentService` and the stale socket-vs-disk
truth split. `CapacityRefreshScheduler` and `ProbeRecordRefreshScheduler` run
only inside `ServeDaemon`.

### 2.5 CLI-only launchd is deliberate

Apple's current `SMAppService.agent(plistName:)` requires the LaunchAgent plist
and helper executable inside an app bundle. That is the preferred app-owned
path, but it would violate CLI-only operation. A product-owned per-user plist
under `~/Library/LaunchAgents` is therefore the deliberate CLI distribution
path.

On macOS 13+, observe user authorization with
`SMAppService.statusForLegacyPlist(at:)`. If it returns `requiresApproval`,
report that exact fact and direct the user to Login Items. Never bypass a user
who disabled the background item.

Prior art:

- [Apple: Updating helper executables from earlier versions of macOS](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)
- [Apple: Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)

---

## 3. Root cause and present evidence

This incident is not one mysterious macOS failure. It is an ownership failure
with four proven consequences.

| Proven defect | Evidence | Design correction |
| --- | --- | --- |
| Three executable identities can disagree | On 2026-08-10 the PATH symlink resolved to a Documents debug build; the staged binary had different bytes/code identity; the live daemon ran the staged copy | One canonical installed executable for PATH, launchd, update, and health |
| Supervision is opt-in after install | The pre-diagnostic host had no product LaunchAgent; `serve enable` created it manually | Install/update establishes desired state by default and verifies it |
| App demand-heal recursively launched the Dock app | SC-S03 resolved `Allnighter.app/Contents/MacOS/Allnighter`, appended `serve`, and repeated until the machine filled with Dock processes | App never owns serve lifecycle; delete detached auto-launch |
| A live PID is painted healthier than the work it hosts | `ServeDaemonProbe` treats `kill(pid, 0)` as loopback listening; LaunchAgent PATH is `/usr/bin:/bin:/usr/sbin:/sbin`; no per-scheduler receipt proves useful progress | Active loopback handshake + binary match + scheduler receipts |

Additional verified constraints:

- The original exit 78/LWCR storm occurred before Swift `main`; admission code
  could not repair it.
- A fresh legacy `bootout` + `bootstrap` survived a same-session kill, but
  logout/login remains unproven.
- `serve enable` can read a debug binary from a Documents checkout through
  `Data(contentsOf:)`, producing the observed TCC seam.
- Current `repair` removes the agent and never restores service. That is cleanup,
  not repair.
- Current help still teaches silent detached auto-launch and the destructive
  meaning of repair.

Truth owner: `ServeInstallation` (new name; may replace `ServeLifecycle`) owns
desired state, canonical binary, plist, launchd registration, update, repair,
and rollback. `ServeDaemon` owns runtime/scheduler state. `ServeStatus` is the
read-only join of those owners.

Lie-prone layers: plist existence, PID liveness, stale coordinator record,
socket/disk freshness split, help prose, and any app-side timer/process hook.

---

## 4. Installation and supervisor contract

### 4.1 Canonical layout

```text
~/.local/share/allnighter/bin/alln
~/Library/LaunchAgents/com.allnighter.resident-coordinator.plist
~/Library/Application Support/Allnighter/Coordinator/coordinator.json
~/Library/Application Support/Allnighter/Coordinator/runtime.json
~/Library/Logs/Allnighter/serve.log
~/Library/Application Support/Allnighter/serve-desired-state.json
```

`serve-desired-state.json` stores only `enabled|disabled`, schema version, and
updated time. Absence migrates to `enabled` during the first post-fix install.
It contains no credentials or vendor data.

### 4.2 LaunchAgent shape

The generated plist has one code owner and these required properties:

- `Label = com.allnighter.resident-coordinator`
- `ProgramArguments = [canonicalBinaryPath, "serve"]`
- `RunAtLoad = true`
- `KeepAlive = true`
- `ThrottleInterval = 30`
- `ProcessType = Background`
- `WorkingDirectory = ~/Library/Application Support/Allnighter/ProbeScratch`
- `StandardOutPath` and `StandardErrorPath` under `~/Library/Logs/Allnighter/`
- deterministic `HOME` and `PATH`; never inherit repo/app CWD or a host shell

Vendor processes use persisted absolute `ToolInvocation` paths. The LaunchAgent
PATH is a fallback containing only the canonical install directory and standard
user/system binary directories. It never evaluates a login shell.

### 4.3 Install/update transaction

One owner performs this bounded sequence:

1. Resolve the candidate binary and refuse app-bundle re-exec or a protected
   Documents/Desktop/Downloads source in developer mode. `rebuild_cli.sh`
   already supplies a Library/Developer scratch candidate.
2. Read desired state and active obligations. If an update would stop a daemon
   with active obligations, exit `75`/`SERVE_BUSY` before modifying anything.
3. Verify candidate executable/version, then copy it to a same-filesystem temp
   beside the canonical path. Preserve the prior canonical binary as rollback.
4. Atomically rename candidate into the canonical path and atomically update the
   requested PATH symlink.
5. When desired state is enabled: write the plist atomically, boot out the old
   label once, bootstrap the new plist once, and wait at most 10 seconds for an
   active health response from the expected build.
6. On any failure after step 3, restore binary, symlink, and plist; bootstrap the
   prior known-good job when one existed; return a nonzero structured failure.
7. Delete rollback bytes only after active health matches the candidate build.

No unbounded retry, recursive self-launch, `kickstart` loop, or success-with-a-
warning. The install command's exit code covers the whole requested transaction.

The one-paste installer downloads to temp, verifies SHA/signature as it does
today, then invokes the candidate's `install-cli`; it no longer hand-maintains a
parallel install layout.

### 4.4 Crash and login behavior

launchd restarts an abnormal serve exit. Serve stays in the foreground from
launchd's perspective and never daemonizes/forks. `SIGTERM` settles runtime
receipts and exits. `serve disable` boots out before removing the plist, so
KeepAlive cannot resurrect a disabled service.

Logout/login is a release gate, not a deferred nice-to-have.

---

## 5. CLI and JSON contract

### 5.1 Commands

| Command | Contract |
| --- | --- |
| `alln install-cli [--path <dir>] [--no-serve] [--json]` | Install/update canonical CLI; enabled serve is the default; atomic result includes serve status |
| `alln serve status [--json]` | Read-only desired state + supervisor + active daemon + scheduler health |
| `alln serve --health [--json]` | Compatibility spelling for `serve status`; same output and exit code |
| `alln serve enable [--json]` | Persist enabled, converge plist/registration, start, actively verify |
| `alln serve disable [--json]` | Persist disabled, boot out, delete plist, verify stopped |
| `alln serve restart [--json]` | Refuse while obligations are active; otherwise one bootout/bootstrap + active verify |
| `alln serve repair [--json]` | If desired state is enabled, reinstall canonical plist and registration, then active verify; never merely delete |
| `alln serve` | Foreground daemon entry used by launchd and explicit diagnostics; singleton admission remains fail-closed |

Retire from all contracts/help: `--no-auto-serve`, `ALLN_NO_AUTO_SERVE`, and
the claim that ordinary dispatch silently spawns serve.

### 5.2 `ServeStatusJSON` v2

```json
{
  "schemaVersion": 2,
  "desiredState": "enabled",
  "state": "healthy",
  "supervisor": {
    "kind": "launchAgent",
    "label": "com.allnighter.resident-coordinator",
    "loaded": true,
    "authorization": "enabled",
    "pid": 1234,
    "lastExitCode": null
  },
  "binary": {
    "path": "/Users/me/.local/share/allnighter/bin/alln",
    "expectedGitSha": "abc123",
    "runningGitSha": "abc123",
    "matches": true
  },
  "daemon": {
    "daemonId": "...",
    "pid": 1234,
    "startedAt": "...",
    "activeHealthRespondedAt": "..."
  },
  "schedulers": [
    {
      "id": "capacityRefresh",
      "state": "waiting",
      "lastAttemptAt": "...",
      "lastSuccessAt": "...",
      "lastError": null,
      "nextWakeAt": "..."
    }
  ],
  "recovery": null
}
```

Top-level state is one of:

- `healthy`: desired enabled, authorization enabled, loaded supervisor, active
  loopback response, matching binary, required schedulers registered;
- `starting`: bounded internal install/repair observation only;
- `disabled`: desired disabled and no loaded job/process;
- `requiresApproval`: macOS reports user approval/revocation;
- `degraded`: any enabled-state mismatch, stale/nonresponding daemon, binary
  mismatch, crash/wedge, or required scheduler failure.

`healthy` requires a real `GET /health` response from the recorded loopback
port whose daemon id, pid, and build identity match the durable record. A live
PID alone never sets `loopback.listening = true`.

### 5.3 Exit codes and errors

| Exit | Meaning | Stable error code examples |
| --- | --- | --- |
| `0` | Requested state reached; status is healthy or intentionally disabled | — |
| `2` | CLI usage error only | `CLI_USAGE_ERROR` |
| `69` (`EX_UNAVAILABLE`) | Enabled service is not actively healthy | `SERVE_UNAVAILABLE`, `SERVE_WEDGED`, `SERVE_BINARY_MISMATCH` |
| `75` (`EX_TEMPFAIL`) | Active obligations make update/restart unsafe | `SERVE_BUSY` |
| `77` (`EX_NOPERM`) | User/macOS approval is required | `SERVE_REQUIRES_APPROVAL` |
| `1` | Filesystem, launchctl, rollback, or verification failure | `SERVE_INSTALL_FAILED`, `SERVE_ROLLBACK_FAILED` |

JSON commands emit exactly one object on stdout. Diagnostics go to structured
fields and the serve log, not stray stdout. Human output ends with one working
recovery command.

---

## 6. Runtime receipts and logs

`ServeDaemon` writes `runtime.json` atomically. It records daemon identity and
one row for every registered scheduler:

- `pendingWake`
- `pmTurnWake`
- `boostSeed`
- `vendorBackoff`
- `notifications`
- `capacityRefresh`
- `probeRecordRefresh`
- `cloudRelay` only when configured

Each row records registered/running/waiting/failed, last attempt, last success,
last observed error, and next wake when known. Absence of a configured optional
scheduler is omitted, never painted failed. Absence of a required scheduler is
degraded.

The serve log is bounded: rotate at 5 MiB, keep three files. Lifecycle actions
and daemon start/stop/crash write timestamp, build identity, pid, launchd label,
and observed result. Never log prompts, source, credentials, environment dumps,
or vendor output.

`alln serve status` remains useful if the daemon is dead because it can join the
desired-state file, plist, launchctl observation, coordinator record, runtime
receipt, and last bounded log error.

---

## 7. Inference bans

| Junction | Owner | Possible bad inference | Ban | Negative proof |
| --- | --- | --- | --- | --- |
| plist -> supervision | `ServeInstallation` | plist exists, therefore serve is supervised | Healthy requires authorization + loaded launchd job + active daemon response | Fixture: plist present, job absent => degraded |
| pid -> daemon | `ServeStatus` | `kill(pid, 0)` means health endpoint is listening | Active loopback handshake and matching daemon identity are mandatory | Fixture: recycled live pid => degraded |
| daemon -> scheduler | `ServeRuntimeStatus` | process answers, therefore schedulers work | Required scheduler registration and current receipt are part of health | Fixture: missing capacity row => degraded |
| install -> enabled | install transaction | binary copied, therefore install succeeded | Exit 0 only after requested desired state is actively verified | Bootstrap failure rolls back and exits 1 |
| update -> safe restart | active obligations | update command may kill serve at any time | Refuse before mutation when obligations are active | Busy fixture leaves binary/plist bytes unchanged |
| CLI -> app | architecture gate | any executable named Allnighter can run `serve` | App bundle paths are never lifecycle candidates; Mac app has no lifecycle calls | Static gate + app argv kill test |
| app -> freshness | `ServeDaemon` | app-open timer can substitute for serve | Periodic scheduling exists only in ServeDaemon | Static gate rejects app timer/wake ownership |
| user disable -> repair | desired state + ServiceManagement | missing process means re-enable it | Updates preserve explicit disabled; revoked approval is never bypassed | Disabled/requiresApproval fixtures perform no bootstrap |
| PATH -> vendor availability | persisted `ToolInvocation` | launchd's PATH can answer which vendor CLI to run | Scheduler spawns use resolved absolute invocations; PATH is fallback only | Minimal-PATH scheduler fixture invokes absolute binary |

---

## 8. Ordered implementation slices

One slice = one work order = one commit. Do not combine slices.

### ASR-S00 — native launchd isolation harness

Goal: prove the CLI-only primitive before another product patch.

- Add `tools/ServeLaunchdHarness/` with a tiny executable/fixture that writes a
  heartbeat from a neutral Library CWD.
- Use a unique non-product label and scratch home; never mutate
  `com.allnighter.resident-coordinator`.
- Prove bootstrap, active check, TERM/KILL restart, atomic binary replacement +
  rebind, disable cleanup, minimal PATH, and no repo/app dependency.
- Capture the working plist/API sequence and product delta under `docs/qa/`.

Proof: `bash tools/ServeLaunchdHarness/run.sh same-session`
Stop: if the minimal agent cannot survive kill/rebind, do not edit product
lifecycle code; report the platform failure.

### ASR-S01 — one canonical CLI installation

Goal: make `InstallCLI` and the one-paste installer converge on one binary.

Touch: `InstallCLI`, `AllnighterCLI.runInstallCLI`, `scripts/get-alln.sh`,
`scripts/rebuild_cli.sh`, install tests. Delete `ServeStableBinary` and its tests
only after all references move.

Proof:

```text
scripts/swift-test.sh --filter 'InstallCLITests|ServeInstallRefreshTests'
bash scripts/test-get-alln.sh
```

Required kill tests: same-file candidate; protected dev source refusal; atomic
rollback; PATH and LaunchAgent target resolve to the same inode/path.

### ASR-S02 — convergent supervisor lifecycle

Goal: make enable/disable/restart/repair and default install activation one
transactional owner.

Touch: `ServeLifecycle` (or rename to `ServeInstallation`),
`ServeLaunchAgentStatus`, desired-state store, CLI routing, lifecycle tests.

Proof:

```text
scripts/swift-test.sh --filter 'ServeLifecycleTests|ServeLifecycleEnableTests|ServeLaunchAgentStatusTests|ServeInstallRefreshTests'
```

Required kill tests: first install defaults enabled; `--no-serve`; disable
persists across update; repair restores enabled agent; requiresApproval does not
bootstrap; busy update is byte-for-byte nonmutating; bootstrap failure restores
prior healthy bytes/plist.

### ASR-S03 — active health and scheduler receipts

Goal: make status answer “is useful scheduling alive?” rather than “does a pid
exist?”

Touch: `ServeDaemon`, `ServeDaemonProbe`, loopback health client/server,
`CoordinatorHealth` -> `ServeStatusJSON` mapping, runtime receipt, bounded log,
focused scheduler wrappers/tests.

Proof:

```text
scripts/swift-test.sh --filter 'CoordinatorTests|ServeLaunchAgentStatusTests|ServeDaemonAdmissionTests|ServeStatusTests|ServeRuntimeStatusTests'
```

Required kill tests: recycled PID; dead port; wrong daemon id; wrong build;
missing required scheduler; failed scheduler with readable last error; daemon-
dead status still returns one recovery object.

### ASR-S04 — delete alternate lifecycle and app scheduler ownership

Goal: make the forbidden architecture unrepresentable.

Delete `ServeAutoLaunch`, `ServeAutoLaunchCLI`, run/loop call sites,
`--no-auto-serve`, `ALLN_NO_AUTO_SERVE`, app demand-heal remnants, and app-owned
periodic/wake capacity acquisition. Retain explicit UI refresh through the
shared Engine operation and durable history rendering.

Add a deterministic architecture gate to
`scripts/check_architecture_policy.sh`: app source may not call/import serve
lifecycle or host `CapacityRefreshScheduler`/`ProbeRecordRefreshScheduler`;
non-lifecycle CLI code may not spawn `alln serve`.

Proof:

```text
scripts/swift-test.sh --filter 'ServeRequirementTests|ServeAutoLaunchTests|CapacityResidentServiceTests|CapacityStripModelTests'
bash scripts/check_architecture_policy.sh
```

Replace obsolete tests rather than preserving tests for deleted behavior.
Founder app check: open Allnighter once -> one Dock process; serve pid/build is
unchanged by app launch; no silent vendor process starts.

### ASR-S05 — contract, teaching, migration, uninstall

Goal: make every entry point teach and preserve the same lifecycle.

- Update `ContractRegistry`, `HelpTopicRegistry`, `RetiredVocabulary`, bootstrap
  snippets, `alln doctor`, and generated contract artifacts.
- Search terms: `serve`, `scheduler`, `background`, `login`, `launchagent`,
  `capacity stale`, `pending stuck`, `notification`, `repair`.
- Migrate the old Application Support staged binary and old plist only after the
  new agent is healthy. Remove the obsolete staged binary; never leave two jobs.
- Uninstall disables/boots out first, then removes canonical CLI, plist, desired
  state, runtime receipt, and logs according to the uninstall disclosure.
- Update `Product_Vocabulary.md` with the shipped background-scheduler law at
  closeout; archive this packet (the superseded Serve Continuity history is
  already archived).

Proof:

```text
scripts/swift-test.sh --filter 'ContractRegistryTests|HelpTopicRegistryTests|InstallCLITests|ServeMigrationTests'
bash scripts/rebuild_cli.sh
alln dev export-contracts
```

### ASR-S06 — real host release gates

Goal: prove the claim outside mocks with the Dock app quit.

Add `scripts/works-test-serve-continuity.sh` with inspect-only default and
explicit `--mutate-product-agent` mode. The mutating mode kills/rebinds the real
serve and therefore requires founder approval under the High-Risk Stops.

Required host matrix:

1. CLI-only cold install in a clean user home; no Allnighter.app present.
2. `serve status --json` healthy with canonical binary/agent/daemon identity
   equal and every required scheduler registered.
3. TERM then KILL: launchd supplies a new pid and active health within 15s; no
   extra daemon and no Dock process.
4. vA -> vB update: one agent, one daemon, new build identity, no orphan/staged
   copy, rollback proven with an injected bootstrap failure.
5. Capacity and probe receipts advance from serve with the app absent; a
   persisted absolute vendor invocation works under launchd's minimal PATH.
6. TCC reset + CLI install/serve from the supported canonical layout produces no
   Documents/Desktop/Downloads prompt.
7. Logout/login: serve returns without terminal or app launch and active health
   passes. This gate cannot be waived by a same-session unit test.
8. Disable -> logout/login: serve stays absent. Reinstall/update preserves
   disabled until explicit enable.

Closeout proof: focused tests from all slices, then `bash scripts/check.sh`, then
the approved host script and logout/login record under `docs/qa/alln-serve/`.

---

## 9. Works Test

### User-visible claim

> Install the CLI and close every terminal and the Dock app. `alln serve`
> remains supervised. If its process dies, launchd restarts the same installed
> build. `alln serve status --json` proves the daemon and each scheduler, and
> logout/login brings it back. The app is never required and never launches it.

### Exact final scenario

```text
Precondition: clean user; Allnighter.app absent; no old agent/plist/process.

curl -fsSL https://get.allnighter.io | sh
alln serve status --json
# assert state=healthy; binary.matches=true; authorization=enabled;
# assert required scheduler ids present; record pid/build.

# approved Works Test kills pid
scripts/works-test-serve-continuity.sh --mutate-product-agent crash-restart
# assert new pid, same expected build, active health <=15s, one daemon.

# logout/login, launch Terminal only
alln serve status --json
# assert healthy before any app or scheduler-triggering CLI command.
```

The Works Test fails if it needs `alln serve enable`, manual `alln serve`, the
Dock app, reboot, `kickstart`, or agent intervention.

---

## 10. Done when

- [ ] CLI-only install enables and actively verifies one supervised serve by
  default, with a disclosed opt-out.
- [ ] PATH, launchd, health, and update name one canonical installed binary.
- [ ] Kill, update, rollback, disable, and logout/login host proofs pass.
- [ ] Status fails closed on authorization, launchd, daemon, binary, or required
  scheduler mismatch and returns a working recovery command.
- [ ] Scheduler-dependent commands never leave new background obligations when
  supervised serve is unavailable.
- [ ] The app contains no serve lifecycle and no periodic capacity/probe host.
- [ ] Detached auto-launch and its opt-out grammar are deleted and deny-listed.
- [ ] Install, doctor, help search, bootstrap teaching, and uninstall agree.
- [ ] TCC proof shows no protected-folder prompt on the supported install/start
  path.
- [ ] Focused proofs and `bash scripts/check.sh` pass.
- [ ] Durable law is promoted to code/contracts/vocabulary; this packet and the
  superseded sprint orders are archived.

## 11. Blocking questions

None. Native host proofs are execution gates, not unanswered product decisions.
