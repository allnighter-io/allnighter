# `alln serve` Recovery

Status: **CODE RED — READY FOR IMPLEMENTATION**
Owner: AllnighterCLI + AllnighterEngine
Created: 2026-08-10
Finalized: 2026-08-10
Adversarial review: 2026-08-10 — code identity, restart contract, wake ownership,
slice ordering, and rollback terminal state were added after review. §4.5 is the
highest-risk assumption in this packet and ASR-S00 exists to settle it; §4.6
names the most likely fix if it fails.
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

The PATH entry is a symlink to that canonical executable. The LaunchAgent points
to the same canonical executable. Delete the second staged copy under
`~/Library/Application Support/Allnighter/CLI/` and delete its staging owner,
`ServeStableBinary`.

The default PATH symlink is `~/.local/bin/alln`. `/usr/local/bin/alln` is no
longer auto-preferred: it is machine-wide but would point into one user's home,
which is wrong on a multi-user Mac and needs sudo for a per-user install. It
remains available only through an explicit `--path`, and install output says
plainly that it points at this user's canonical binary.

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

The preflight guards **the write of a deferred obligation** — a wake ticket, a
park, a scheduled notification — never command entry. Attended work that runs
now and returns its own result is never gated by it: `alln run` and an attended
`alln loop` turn stay runnable with serve dead or disabled, and only refuse at
the moment they would hand work to a daemon that will not claim it. This is the
queue-honesty law in `AGENTS.md` ("prove a host will claim before queuing, and
refuse loudly"), not a health sensor vetoing an explicit request — which the
INFORM-never-BLOCK law forbids. `ServeRequirement` is the only place in the
product allowed to make that refusal.

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
- `KeepAlive = { SuccessfulExit = false }` — **not** `true`
- `ThrottleInterval = 30`
- `ProcessType = Background`
- `WorkingDirectory = ~/Library/Application Support/Allnighter/ProbeScratch`
- `StandardOutPath` and `StandardErrorPath` under `~/Library/Logs/Allnighter/`
- deterministic `HOME` and `PATH`; never inherit repo/app CWD or a host shell

The install transaction creates `ProbeScratch` and the log directory before
bootstrapping. launchd fails the spawn if the `WorkingDirectory` is missing, and
that failure looks exactly like the wedge this packet is fixing.

Vendor processes use persisted absolute `ToolInvocation` paths. The LaunchAgent
PATH is a fallback containing only the canonical install directory and standard
user/system binary directories. It never evaluates a login shell.

#### Restart contract

`KeepAlive = true` restarts the job on *every* exit, including a deliberate one.
Today `alln serve` exits `0` when admission refuses a duplicate and `1` when a
peer survives KILL (`AllnighterCLI.swift`), and the health listener exits on a
bind failure. Under `KeepAlive = true` each of those is a permanent 30-second
respawn loop — a slow-motion rerun of the fork bomb. The contract is therefore:

| Daemon exit | launchd behavior | Used for |
| --- | --- | --- |
| exit `0` | **no restart** | deliberate stand-down: admission refusal, unrecoverable configuration |
| signal death or nonzero exit | restart after `ThrottleInterval` | crash, wedge, external kill |

`SIGTERM` settles runtime receipts and then re-raises `SIGTERM` under the default
handler, so launchd observes signal death and restarts. `serve disable` boots out
before removing the plist, so stand-down never competes with KeepAlive.

A stood-down daemon is never silently absent: the job is loaded with no process,
and `serve status` reports `degraded` with `supervisor.lastExitCode = 0`, the
stand-down reason, and a recovery command.

Under launchd, the supervised daemon is authoritative. `ServeDaemonAdmission`
must supersede a foreground diagnostic daemon rather than refuse to start; the
refuse-and-exit-0 path belongs only to a human-invoked foreground `alln serve`,
which is not KeepAlive-managed. Recoverable runtime conditions — a busy health
port, a transient filesystem error — retry in process with backoff. They never
become a process exit, because a process exit is launchd's problem to loop on.

### 4.3 Install/update transaction

One owner performs this bounded sequence:

1. Resolve the candidate binary and refuse app-bundle re-exec or a protected
   Documents/Desktop/Downloads source in developer mode. `rebuild_cli.sh`
   already supplies a Library/Developer scratch candidate.
2. Read desired state and active obligations. If an update would stop a daemon
   with active obligations, exit `75`/`SERVE_BUSY` before modifying anything.
3. Verify candidate executable/version, then copy it to a same-filesystem temp
   beside the canonical path. Preserve the prior canonical binary as rollback at
   the named path `<canonical>.rollback`.
4. **Boot out the existing label before the canonical bytes change.** No
   KeepAlive job may be loaded against the canonical path while its code identity
   is being replaced (§4.5).
5. Atomically rename candidate into the canonical path and atomically update the
   requested PATH symlink.
6. When desired state is enabled: write the plist atomically, bootstrap it once,
   and wait at most 10 seconds for an active health response from the expected
   build.
7. On any failure after step 5, restore binary, symlink, and plist; bootstrap the
   prior known-good job when one existed; return a nonzero structured failure.
8. Delete rollback bytes only after active health matches the candidate build.

No unbounded retry, recursive self-launch, `kickstart` loop, or success-with-a-
warning. The install command's exit code covers the whole requested transaction.

**When rollback itself fails** (`SERVE_ROLLBACK_FAILED`, exit `1`), the rollback
bytes stay at `<canonical>.rollback` and are never deleted. The failure output
must print an absolute-path recovery that does **not** require a working `alln`
on PATH — a literal `cp` of the preserved rollback into the canonical path plus
the one-paste faucet as the second option. A user whose PATH binary is broken
cannot be told to run an `alln` subcommand to fix it.

The one-paste installer downloads to temp and verifies the published sha256 —
`scripts/get-alln.sh` performs no signature check today, and this packet does not
add one — then invokes the candidate's `install-cli`; it no longer hand-maintains
a parallel install layout.

### 4.4 Crash, login, and sleep behavior

launchd restarts an abnormal serve exit per the restart contract in §4.2. Serve
stays in the foreground from launchd's perspective and never daemonizes/forks.
`serve disable` boots out before removing the plist, so KeepAlive cannot
resurrect a disabled service.

Logout/login is a release gate, not a deferred nice-to-have.

**Sleep is an owner, not an assumption.** §2.4 removes the app's wake observer,
and every serve-side scheduler is a `Task.sleep` poll today
(`PendingWakeScheduler`, `CapacityRefreshScheduler`). A sleeping Mac does not
fire those timers, and a long interval can resume late after wake. Left
unowned, a lid close silently defers exactly the obligations serve exists for:
Pending wake and vendor-backoff continuation.

`ServeDaemon` therefore owns wake. Schedulers compare a persisted absolute
deadline against wall-clock time and are re-evaluated on system wake, not only
when a timer expires. The bound is explicit and testable: **a due obligation
fires within 2 minutes of system wake.** Whether that is an `IOKit`/
`NSWorkspace` wake source inside the daemon or a short bounded poll that
re-reads deadlines is an implementation choice for ASR-S03; the bound is not.

### 4.5 Code identity across replacement — the load-bearing assumption

> **SETTLED 2026-08-10 by ASR-S00.** The assumption below is **confirmed**, and
> the branch that would have required a signing slice did **not** fire. Measured
> record: [`docs/qa/alln-serve/ASR-S00-code-identity-matrix.md`](../qa/alln-serve/ASR-S00-code-identity-matrix.md).
> Case (a) — bootout → atomic rename → bootstrap — passed on all three signing
> tracks including ad-hoc, with an image-derived `buildTag` proving the
> replacement binary was loaded. §4.3's ordering stands as the invariant.
>
> Case (b) — atomic rename underneath a loaded KeepAlive job, no rebind — also
> passed on all three tracks: launchd re-exec'd the new bytes with no LWCR
> refusal and no `exit 78`. **Changing an ad-hoc binary's cdhash under a loaded
> agent does not, by itself, reproduce the 2026-08-09 wedge.** The incident's
> root cause is therefore still unidentified and is not what §4.5 originally
> assumed. Keep the bootout bracketing as the conservative posture — it is
> proven sufficient — but do not treat it as a fix for the original incident.
> The residual LWCR cause is tracked as a separate investigation, not a
> prerequisite for ASR-S01.

This is the seam that opened the incident and it must be named, not implied.

The 2026-08-09 failure was launchd refusing to exec before Swift `main` ran, with
a lightweight code requirement in the log. Allnighter binaries are **ad-hoc
signed** (`scripts/build-universal.sh`), so the cdhash changes on every build —
release or dev rebuild. When launchd bootstraps a job it records the code
identity at that path. Replacing the bytes underneath a loaded KeepAlive job
means the next respawn execs an executable whose identity no longer matches the
registration launchd and Background Task Management are holding.

The whole install transaction rests on one assumption:

> A bootout before the bytes change, followed by a fresh bootstrap after, is
> sufficient to keep a per-user LaunchAgent valid across an ad-hoc-signed binary
> replacement whose cdhash differs.

That assumption is **unproven on this host**. It is why §4.3 step 4 boots out
before the rename rather than after, and it is the entire reason ASR-S00 runs
first. ASR-S00 must vary code identity across the replacement — two ad-hoc
binaries with genuinely different cdhashes — and test both orders:

- replace bytes **with** bootout/bootstrap around the rename;
- replace bytes **without** rebind, letting KeepAlive respawn into new bytes.

If the second case reproduces the exit-78 class, §4.3's ordering is confirmed and
becomes an invariant: *every change to the canonical binary's bytes is bracketed
by bootout and bootstrap; launchd is never allowed to respawn across a code
identity change.* If the first case **also** fails, the CLI-only LaunchAgent
distribution path in §2.5 is not viable as ad-hoc-signed, and the fix is §4.6
rather than another product patch.

### 4.6 Signing is a candidate fix, not a later chore

Ad-hoc signing is not "unsigned." It is signed with **no stable anchor**: the
identity *is* the content hash, so every rebuild is, to launchd, a different
program. A team-signed binary is different in kind — the code requirement can be
anchored to the signing team rather than to one hash, and any later build from
the same team satisfies the same requirement.

| Track | Anchor launchd/BTM can hold | Survives a byte replacement |
| --- | --- | --- |
| ad-hoc (`codesign --sign -`, today) | the cdhash itself | no — new bytes are a new identity |
| team-signed | `cert leaf` team identifier | yes — same requirement, new build |

This is testable in dev builds **today**. Nothing about the macOS sandbox is
involved: the CLI is not sandboxed, the Mac app is unsandboxed by design, and
arm64 binaries already carry an ad-hoc signature because the platform requires
one to execute at all. The machine already carries an
`Apple Development: Michael Reining (7RU34H8XPD)` identity, which is sufficient
to run the signed arm of the experiment locally.

ASR-S00 therefore tests the signed arm too. If team-signed replacement survives
where ad-hoc does not, signing is **promoted from a distribution nicety to a
prerequisite of §2.5**, and a signing slice lands before ASR-S01 rather than
after the packet closes.

> **MEASURED 2026-08-10 by ASR-S00: signing is NOT a prerequisite.** All three
> tracks — ad-hoc, `Apple Development (7RU34H8XPD)`, and
> `Developer ID Application: Happy Moose Apps Inc. (LP5YNK7A36)` — behaved
> identically across both replacement cases. Ad-hoc did not fail where a signed
> track succeeded, so signing stays a distribution question and ASR-S01 proceeds
> on the ad-hoc track unchanged.
>
> Correction to the bullet below: the **Developer ID Application certificate is
> already present on the build host** (Happy Moose Apps Inc., LP5YNK7A36) and was
> used in the ASR-S00 matrix. The remaining distribution gap is notarization and
> the choice of publishing identity, not certificate acquisition.

Facts this packet does not overstate:

- No track is signed with a real identity today. `scripts/build-universal.sh` is
  ad-hoc on the dogfood track, and there is no separate signed release track —
  the public artifacts are built the same way.
- An `Apple Development` certificate proves the mechanism locally. Distributing
  to other users needs a **Developer ID Application** certificate (and, for the
  faucet path, notarization); that certificate is not on the build host yet.
  Obtaining it is a distribution-identity decision under the High-Risk Stops.
- Install records the candidate's code identity alongside its version, and
  `ServeStatus` reports a binary mismatch when the running daemon's identity is
  not the recorded one. Version string equality is not identity.
- The curl faucet does not apply `com.apple.quarantine` (curl does not set it),
  and `get-alln.sh` already execs the downloaded binary before install, which
  would fail loudly if that ever changed. No Gatekeeper workaround is added.
- Nothing in this packet weakens, strips, or works around a signature.

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
    "expectedCodeIdentity": "cdhash:...",
    "runningCodeIdentity": "cdhash:...",
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
  mismatch, crash/wedge, deliberate stand-down (§4.2), or required scheduler
  failure.

`healthy` requires a real `GET /health` response from the recorded loopback
port whose daemon id, pid, and build identity match the durable record. A live
PID alone never sets `loopback.listening = true`. `binary.matches` is false when
either the build sha or the recorded code identity differs; two builds sharing a
version string are not the same executable.

### 5.3 Exit codes and errors

| Exit | Meaning | Stable error code examples |
| --- | --- | --- |
| `0` | Requested state reached; status is healthy or intentionally disabled | — |
| `2` | CLI usage error only | `CLI_USAGE_ERROR` |
| `69` (`EX_UNAVAILABLE`) | Enabled service is not actively healthy | `SERVE_UNAVAILABLE`, `SERVE_WEDGED`, `SERVE_BINARY_MISMATCH` |
| `75` (`EX_TEMPFAIL`) | Active obligations make update/restart unsafe | `SERVE_BUSY` |
| `77` (`EX_NOPERM`) | User/macOS approval is required | `SERVE_REQUIRES_APPROVAL` |
| `1` | Filesystem, launchctl, rollback, or verification failure | `SERVE_INSTALL_FAILED`, `SERVE_ROLLBACK_FAILED` |

`SERVE_BUSY` must never become an un-updatable CLI. "Active obligations" means
non-terminal runs as `ServeDaemonProbe` already computes them, minus
vendor-backoff parks. A wedged run that `RunClockEnforcer` fails to settle would
otherwise block every future update with no way out, so exit `75` must name the
blocking run ids and print the exact existing command that settles or kills
them. This packet adds **no** `--force` update path: forcing would kill live runs
silently, which is a destructive session kill under the High-Risk Stops. The
escape is explicit run settlement by the owner, not a flag.

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
| app -> freshness | `ServeDaemon` | app-open timer can substitute for serve | Periodic scheduling exists only in ServeDaemon | Seeded violation through `scripts/validate_architecture_policy.py` fails the gate |
| version -> identity | `ServeInstallation` | same version string means same executable | Recorded code identity, not version equality, decides `binary.matches` | Fixture: equal version, different cdhash => degraded |
| exit -> restart | launchd plist | KeepAlive can always restart safely | Exit `0` means stand-down; only signal/nonzero restarts | Fixture: persistent refusal produces one stand-down, not a respawn loop |
| timer -> wake | `ServeDaemon` | an in-process sleep survives system sleep | Deadlines are wall-clock and re-evaluated on wake | Host gate: due obligation after lid close fires within 2 min of wake |
| user disable -> repair | desired state + ServiceManagement | missing process means re-enable it | Updates preserve explicit disabled; revoked approval is never bypassed | Disabled/requiresApproval fixtures perform no bootstrap |
| PATH -> vendor availability | persisted `ToolInvocation` | launchd's PATH can answer which vendor CLI to run | Scheduler spawns use resolved absolute invocations; PATH is fallback only | Minimal-PATH scheduler fixture invokes absolute binary |

---

## 8. Ordered implementation slices

One slice = one work order = one commit. Do not combine slices.

**Per-slice invariant:** committing any single slice must leave the founder's
live host no worse than before it. A slice that can only be safe in combination
with a later slice is mis-cut. Each work order states, in one line, what the host
looks like with that slice committed and the rest unbuilt.

### ASR-S00 — native launchd isolation harness

Goal: prove the CLI-only primitive, and specifically the §4.5 code-identity
assumption, before another product patch.

- Add `tools/ServeLaunchdHarness/` with a tiny executable/fixture that writes a
  heartbeat from a neutral Library CWD.
- Use a unique non-product label and scratch home; never mutate
  `com.allnighter.resident-coordinator`.
- Prove bootstrap, active check, TERM/KILL restart, disable cleanup, minimal
  PATH, and no repo/app dependency.
- **Code identity is the headline experiment.** Build two harness binaries with
  genuinely different cdhashes (verify with `codesign -dvvv`) and replace the
  bootstrapped executable both ways:
  (a) bootout -> rename -> bootstrap, and (b) rename underneath a loaded
  KeepAlive job with no rebind. Record what launchd does in each case, including
  exit status and any pre-`main` refusal.
- **Run that matrix on both signing tracks** (§4.6): ad-hoc (`codesign --sign -`,
  today's shipping reality) and team-signed with the local
  `Apple Development (7RU34H8XPD)` identity. Four cells total. The comparison is
  the point — if the signed track survives a case the ad-hoc track fails, the
  answer is a signing slice, not more lifecycle code.
- Prove the restart contract from §4.2 on the real primitive: `KeepAlive =
  { SuccessfulExit = false }` with a deliberate exit `0` produces **no** respawn,
  and a signal death does produce one.
- Capture the working plist/API sequence and product delta under `docs/qa/`.

Proof: `bash tools/ServeLaunchdHarness/run.sh same-session`

Stop conditions — report the platform result and edit no product lifecycle code:

- the minimal agent cannot survive kill or rebind;
- case (a) fails on **both** signing tracks, which invalidates the §4.3
  transaction and the §2.5 CLI-only LaunchAgent path outright;
- the restart contract does not behave as §4.2 assumes.

Branch conditions:

- case (a) fails ad-hoc but passes team-signed -> §4.6 wins: cut a signing slice
  before ASR-S01 and make a stable signing anchor a prerequisite of §2.5;
- case (b) succeeds where the incident failed -> say so plainly; the LWCR wedge
  had another cause and §4.5 must be re-derived before ASR-S01.

### ASR-S01 — one canonical CLI installation

Goal: make `InstallCLI` and the one-paste installer converge on one binary.

Touch: `InstallCLI`, `AllnighterCLI.runInstallCLI`, `scripts/get-alln.sh`,
`scripts/rebuild_cli.sh`, install tests. Delete `ServeStableBinary` and its tests
only after all references move.

Ordering guard: the founder's live host currently runs a LaunchAgent whose
`ProgramArguments` point at the staged copy under Application Support
(`ServeLifecycle`). This slice writes the canonical binary and repoints PATH, but
it **must not delete the staged bytes** — deleting them while that agent is still
loaded gives launchd a missing executable to thrash on. Staged bytes stay until
ASR-S02 rebinds the live agent to the canonical path. With only this slice
committed, the host has a stale-but-running agent and a correct PATH binary.

Proof:

```text
scripts/swift-test.sh --filter 'InstallCLITests|ServeInstallRefreshTests'
bash scripts/test-get-alln.sh
```

Required kill tests: same-file candidate; protected dev source refusal; atomic
rollback; PATH and LaunchAgent target resolve to the same inode/path; bootout is
observed **before** the canonical bytes change (§4.3 step 4); install records the
candidate's code identity, not only its version string; a failed rollback leaves
`<canonical>.rollback` in place and emits a recovery that does not invoke `alln`.

### ASR-S02 — convergent supervisor lifecycle

Goal: make enable/disable/restart/repair and default install activation one
transactional owner.

Touch: `ServeLifecycle` (or rename to `ServeInstallation`),
`ServeLaunchAgentStatus`, desired-state store, CLI routing, lifecycle tests.
Links `ServiceManagement` into the CLI target for `statusForLegacyPlist(at:)`,
which the codebase does not use today.

This slice owns the live-host rebind: converging an enabled installation boots
out any agent still pointing at the Application Support staged path, writes the
canonical plist, bootstraps it, and only then removes the staged bytes. That
migration belongs here, not in ASR-S05, so no commit leaves two executable
identities on a real host.

**Inherited from ASR-S01b (`91cad2de`):** `runInstallCLI` no longer calls
`ServeLifecycle().refreshAfterInstall()`, so that method now has **no production
caller** — only `ServeInstallRefreshTests`. This was the right removal (it was
the path that re-staged a Documents debug build into the agent's executable
path, the §3 TCC/identity seam), but it leaves a real intermediate state: between
S01b and this slice, `install-cli` updates the canonical binary and PATH while
the live daemon keeps running whatever bytes are already staged, so the daemon's
build goes stale and no longer tracks installs. ASR-S02 must close that gap —
converge the agent onto the canonical path — and either delete
`refreshAfterInstall` with its tests or fold it into the new owner. Do not
reintroduce staging.

`CanonicalCLIInstall` exposes an injected `beforeBytesChange` hook, called after
the rollback is preserved and immediately before the canonical rename. That is
the designated seam for §4.3 step 4's bootout; this slice plugs launchd into it
rather than adding a second ordering mechanism.

Proof:

```text
scripts/swift-test.sh --filter 'ServeLifecycleTests|ServeLifecycleEnableTests|ServeLaunchAgentStatusTests|ServeInstallRefreshTests'
```

Required kill tests: first install defaults enabled; `--no-serve`; disable
persists across update; repair restores enabled agent; requiresApproval does not
bootstrap; busy update is byte-for-byte nonmutating and names the blocking run
ids; bootstrap failure restores prior healthy bytes/plist; the generated plist
emits `KeepAlive` as a dictionary with `SuccessfulExit = false`, never the bare
boolean; convergence rebinds an agent still pointing at the staged path and
removes the staged bytes only after the canonical agent answers health;
`WorkingDirectory` and the log directory exist before bootstrap.

### ASR-S03 — active health and scheduler receipts

Goal: make status answer “is useful scheduling alive?” rather than “does a pid
exist?”

Touch: `ServeDaemon`, `ServeDaemonProbe`, `ServeDaemonAdmission`, loopback health
client/server, `CoordinatorHealth` -> `ServeStatusJSON` mapping, runtime receipt,
bounded log, focused scheduler wrappers/tests. Also owns the §4.4 wake bound and
the §4.2 in-daemon exit contract (supersede under launchd; retry recoverable
runtime conditions in process instead of exiting into a KeepAlive loop).

Proof:

```text
scripts/swift-test.sh --filter 'CoordinatorTests|ServeLaunchAgentStatusTests|ServeDaemonAdmissionTests|ServeStatusTests|ServeRuntimeStatusTests'
```

Required kill tests: recycled PID; dead port; wrong daemon id; wrong build;
missing required scheduler; failed scheduler with readable last error; daemon-
dead status still returns one recovery object; a deadline that came due during a
simulated sleep gap is re-evaluated on wake rather than waiting out the original
interval; a stood-down daemon (loaded job, exit `0`, no process) reports
`degraded` with the stand-down reason instead of reading as absent; a busy health
port retries in process and does not exit.

### ASR-S04 — delete alternate lifecycle and app scheduler ownership

Goal: make the forbidden architecture unrepresentable.

Delete `ServeAutoLaunch`, `ServeAutoLaunchCLI`, run/loop call sites,
`--no-auto-serve`, `ALLN_NO_AUTO_SERVE`, app demand-heal remnants, and app-owned
periodic/wake capacity acquisition. Retain explicit UI refresh through the
shared Engine operation and durable history rendering.

This slice also **builds** `ServeRequirement`, which does not exist yet. It is
mandated by §2.3 and belongs here because it replaces the very call sites this
slice deletes: `ensureRunning` is invoked from `LoopEngineCLI` today. Touch:
new `ServeRequirement` plus the §2.3 audit list — Loop obligations, Pending
wake, Boost seed, vendor-backoff continuation, notification scheduling, cloud
relay. Each converted call site is listed in the work order with a verdict of
"gated" or "attended, not gated" per §2.3's scope rule; a call site that runs
now and returns its own result is not gated.

Add a deterministic architecture gate to
`scripts/check_architecture_policy.sh`: app source may not call/import serve
lifecycle or host `CapacityRefreshScheduler`/`ProbeRecordRefreshScheduler`;
non-lifecycle CLI code may not spawn `alln serve`.

A name-based gate that has never failed is not a gate. Every rule added here
must be proven by a seeded violation through `scripts/validate_architecture_policy.py`,
which already exists for exactly this. A gate that cannot be made to fail on
demand does not count as the negative proof in §7.

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
- The staged-binary and plist migration itself lands in ASR-S02, not here. This
  slice sweeps what the migration leaves behind: stale teaching, retired
  vocabulary, and any residual on-disk artifact that no owner claims.
- Retire in-code teaching strings, not only help topics. The refuse path today
  prints "Stop it with `kill <pid>` if you want a fresh one"
  (`AllnighterCLI.swift:678`), which contradicts the supervised lifecycle and
  must be replaced with the supported command.
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
9. **Founder dev loop, three consecutive cycles in one session:**
   `rebuild_cli.sh` -> `install-cli` -> healthy serve, repeated three times with
   a changing ad-hoc cdhash under the same registration. No LWCR/exit-78 wedge,
   no TCC prompt, exactly one daemon and one agent after each cycle. This is the
   loop the founder actually runs; a clean-install-only proof does not cover it.
10. **Sleep gate:** schedule an obligation due during sleep, close the lid past
    its deadline, wake, and prove the receipt advances within 2 minutes (§4.4).
11. **No restart loop:** induce a persistent stand-down (exit `0`) and confirm
    launchd does not respawn and `serve status` reports `degraded` with the
    reason. Then induce a crash and confirm it does respawn.

Faucet status as of 2026-08-10, measured not assumed. The public host is
`https://allnighter.ikiro.io` (Ikiro is ours; it moves to `allnighter.io`
shortly, and `get.allnighter.io` currently returns HTTP 525). The site root
answers `200`, but the two artifacts the installer actually fetches —
`/latest.json` and `/get-alln.sh` — both return `404`. A live marketing host is
not a live faucet.

So the accepted gate form stays base-pinned:
`ALLN_INSTALL_BASE_URL=<base> sh scripts/get-alln.sh`. The published one-liner
becomes the gate the day `/latest.json` and `/get-alln.sh` return `200` and the
sha256 in the manifest matches the published binary. Quoting the one-liner as a
passing proof before then is a false receipt.

Publishing the artifacts does not make them signed. Both tracks are ad-hoc
(§4.6), so the host proofs must state which signing track the tested binary
came from.

Gates 7, 8, 9, and 10 require a human at the machine. The founder is the signer.
Each run is recorded under `docs/qa/alln-serve/` as one file per attempt with:
date, build identity, the gate number, the raw `serve status --json` before and
after, and pass/fail. An unrecorded gate is an unrun gate.

Closeout proof: focused tests from all slices, then `bash scripts/check.sh`, then
the approved host script and the founder-signed records under
`docs/qa/alln-serve/`.

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

# host is live (allnighter.ikiro.io) but /latest.json and /get-alln.sh are 404
# as of 2026-08-10 — pin the base until the publish pipeline serves them
ALLN_INSTALL_BASE_URL="$BASE" sh scripts/get-alln.sh
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

- [x] ASR-S00 settled the §4.5 code-identity assumption on a real host across
  both signing tracks, and the bootout-before-replacement invariant is either
  confirmed or replaced by the §4.6 signing slice. — **done 2026-08-10**
  (`e775d586`); confirmed on three tracks, no signing slice required; residual
  LWCR root cause remains open as a separate investigation.
- [ ] CLI-only install enables and actively verifies one supervised serve by
  default, with a disclosed opt-out.
- [ ] PATH, launchd, health, and update name one canonical installed binary, and
  identity — not version string — decides `binary.matches`. — **install side done
  2026-08-10** (ASR-S01a–d: `d60efa8a`, `91cad2de`, `fa8dc145`, `1f3e1add`);
  launchd and health still name the staged path until ASR-S02.
- [ ] No exit path produces a KeepAlive respawn loop; stand-down is visible in
  status rather than silent.
- [x] A due obligation survives system sleep and fires within 2 minutes of wake.
  — **done 2026-08-11**, gate 10 founder-signed; measured +54 s and +87 s after a
  real wake, with `nextWakeAt` rescheduled forward (§10.1 R2).
- [ ] Kill, update, rollback, disable, logout/login, sleep, and the founder's
  three-cycle rebuild loop host proofs pass and are signed under
  `docs/qa/alln-serve/`. — **logout/login, disable and sleep signed 2026-08-11**
  (gates 7, 8, 10); three-cycle rebuild countersigned but PM-executed (gate 9);
  **kill, update and rollback still unrun** (§8 host matrix 3, 4).
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
- [ ] Every risk in §10.1 is resolved or re-homed to a named owner, and the
  archive note states plainly that the LWCR root cause was never identified
  (R1). Archiving without this is a false receipt.

## 10.1 Known open risks — carry these to closeout

These are **not** blockers and none of them stops a slice. They are named here so
closeout cannot quietly imply they were solved. Archiving this packet without
resolving or re-homing each one is a false receipt.

### R1 — the 2026-08-09 LWCR root cause is unidentified

ASR-S00 refuted this packet's own theory. Replacing an ad-hoc binary's bytes
under a loaded KeepAlive agent — the mechanism §4.5 assumed — did **not**
reproduce the exit-78/LWCR wedge, on any of three signing tracks. The install
ordering in §4.3 is still correct and proven sufficient, but it is not a
confirmed fix for the incident, because the incident's cause is unknown.

Consequence: the wedge can recur after this packet closes and nothing here would
have predicted it. **ASR-S06 gate 9** (three consecutive `rebuild_cli.sh` →
`install-cli` cycles with a changing cdhash under one registration) is the
closest thing to a detector, because it is the exact motion that wedged. Do not
waive it, and record its result either way. If it wedges, that is a reproduction
with the new receipts and bounded logs in place — a better starting point than
any investigation available today.

**Closeout requirement:** this packet is archived stating the root cause was
never identified. It must not be archived implying the incident is fixed.

**Gate 9 measured 2026-08-11 — 3/3 clean, R1 still open.** Three consecutive
`rebuild_cli.sh` → `install-cli` cycles produced four distinct ad-hoc cdhashes
under one registration with zero LWCR/exit-78 entries, one agent and one daemon
each time. Record:
[`docs/qa/alln-serve/2026-08-11-gate9-three-cycle-rebuild.md`](../qa/alln-serve/2026-08-11-gate9-three-cycle-rebuild.md)
— **PM-executed at founder direction, not founder-signed.** This is absence
evidence for an unidentified fault, not a confirmed fix. A **second** unexplained
launchd event occurred the same day (job unloaded, orphaned daemon at PPID 1);
there are now two unexplained events, not one.

### R2 — sleep/wake is the least-designed obligation in the packet — **ANSWERED 2026-08-11, founder-signed**

**Gate 10 passed on a real sleep.** `capacityRefresh` (due 16:04:44Z) and
`probeRecordRefresh` (due 16:04:36Z) both fell strictly inside a genuine system
sleep (`pmset`: slept 16:02:00Z, woke 16:12:27Z) and fired **+54 s** and **+87 s**
after wake — inside the §4.4 two-minute bound — with `nextWakeAt` rescheduled
forward rather than left at the stale pre-sleep deadline. The daemon pid was
identical either side of the sleep, so catch-up was measured rather than
disguised by a restart. Record:
[`docs/qa/alln-serve/2026-08-11-gate10-deadline-due-while-asleep.md`](../qa/alln-serve/2026-08-11-gate10-deadline-due-while-asleep.md).

This is the proof R2 said was the only one that counts, on the real primitive,
founder-signed. What remains unproven is the tail: long sleeps, repeated cycles,
and dark/maintenance wake. R2 is answered for the designed bound, not retired as
a topic.



§4.4 states a bound — a due obligation fires within 2 minutes of system wake —
but deliberately leaves the mechanism to ASR-S03, and every scheduler today is a
`Task.sleep` poll (`PendingWakeScheduler`, `CapacityRefreshScheduler`). This is
the easiest place in the packet to write a proof that cannot fail: a test that
advances a fake clock proves the arithmetic, not that a sleeping Mac wakes and
fires. ASR-S03 must carry the 2-minute bound as its own failing-first test, and
**ASR-S06 gate 10** (real lid close past a deadline) is the only proof that
counts. Cut the wake work as its own sub-slice so it cannot ride along inside a
larger status slice.

### R3 — the release gates that matter need a human — **3 of 4 signed 2026-08-11**

Gates 7, 8, 9, and 10 (logout/login, disable-survives-login, the three-cycle
rebuild loop, and sleep) cannot be closed by any agent or same-session unit
test. They are the gates that actually prove §9's user-visible claim. Until they
are recorded and signed under `docs/qa/alln-serve/`, the claim is unproven no
matter how green the suite is. An unrecorded gate is an unrun gate.

| Gate | Result | Record | Signature |
| --- | --- | --- | --- |
| 7 — logout/login | **PASS** | [`2026-08-11-gate7-logout-login.md`](../qa/alln-serve/2026-08-11-gate7-logout-login.md) | **founder-signed** |
| 8 — disable survives login | **PASS** | [`2026-08-11-gate8-disable-survives-login.md`](../qa/alln-serve/2026-08-11-gate8-disable-survives-login.md) | **founder-signed** |
| 9 — three-cycle rebuild | **PASS** | [`2026-08-11-gate9-three-cycle-rebuild.md`](../qa/alln-serve/2026-08-11-gate9-three-cycle-rebuild.md) | countersigned; PM-executed |
| 10 — sleep | **PASS** | [`2026-08-11-gate10-deadline-due-while-asleep.md`](../qa/alln-serve/2026-08-11-gate10-deadline-due-while-asleep.md) | **founder-signed** |

All four were run on the second Mac (Mac mini, macOS 15.6/24G84) against build
`ef928f6e` / contract 9.19.0 / ad-hoc cdhash `e8bf976f`, on a host with no
`Allnighter.app`. Gates 7, 8 and 10 carry no PM-executed caveat: the founder
performed every logout, login and sleep.

**R3 is not closed.** The human gates named in this risk are done, but §8's host
matrix items 1–6 and 11 remain unrun, and gate 9 is still the weaker
PM-executed record. Three signed gates do not make §9's claim proven.

### R4 — intermediate state: the live daemon is frozen — **CLOSED 2026-08-11**

Closed by the first real `rebuild_cli.sh` → `install-cli` run on the founder's
host. The S02d migration rebound the agent from the Application Support staged
path to the canonical binary, cleaned the staged bytes, and left exactly one
supervised daemon whose pid matches the agent. Record:
[`docs/qa/alln-serve/2026-08-11-live-host-migration.md`](../qa/alln-serve/2026-08-11-live-host-migration.md).

That run also found — and repaired — an **unsupervised** host: the launchd job
was not loaded and an orphaned daemon (PPID 1) was running a Library/Developer
debug build. The cause of the bootout was not identified and is recorded as
unknown, not guessed.


Between ASR-S01b (`91cad2de`) and ASR-S02c, `install-cli` updates the canonical
binary and PATH while the loaded agent keeps running its already-staged bytes,
so the daemon's build no longer tracks installs. This is deliberate — it is the
§8 ASR-S01 ordering guard — but it is a real degradation while it lasts, and
ASR-S02c closes it. Do not let it survive past that slice.

## 11. Blocking questions

None for the founder. Native host proofs are execution gates, not unanswered
product decisions.

One open **platform** question remains, and it is deliberately assigned to
ASR-S00 rather than answered here: whether a per-user LaunchAgent survives
replacement of an ad-hoc-signed binary whose cdhash changes (§4.5). ASR-S00
answers it by experiment on both signing tracks, so the likely outcomes are
already routed:

- ad-hoc survives with bootout bracketing -> proceed to ASR-S01 unchanged;
- only team-signed survives -> §4.6 signing slice lands first; this is an
  execution consequence, not a new product decision;
- neither survives -> §2.5's CLI-only LaunchAgent path fails and the packet
  returns for a distribution ruling (app-bundle-hosted agent) before any product
  code moves.

The one thing that would need a founder ruling is obtaining a **Developer ID
Application** certificate for distribution to other users — a distribution
identity decision under the High-Risk Stops. It is not needed to run ASR-S00 or
to fix the founder's own host.
