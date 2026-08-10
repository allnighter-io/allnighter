# Allnighter — `alln serve` Hotfixes

Status: **OPEN — incident 2026-08-10**
Owner: AllnighterCLI / AllnighterEngine (`ServeDaemon`, `ServeLifecycle`,
`ServeAutoLaunch`, `ServeLaunchAgentStatus`, `CapacityRefreshScheduler`)
Created: 2026-08-10
Related:
- [`Serve_Continuity.md`](Serve_Continuity.md) — parent packet (code floor shipped; host proof incomplete)
- [`docs/operations/debugger/2026-08-09-serve-launchagent-lwcr-PACKET.md`](../operations/debugger/2026-08-09-serve-launchagent-lwcr-PACKET.md)
- [`docs/operations/debugger/2026-08-10-mac-serve-fork-bomb-PACKET.md`](../operations/debugger/2026-08-10-mac-serve-fork-bomb-PACKET.md)
- [`docs/operations/debugger/DEBUGLOG.md`](../operations/debugger/DEBUGLOG.md) — 2026-08-10 TCC / cold-launch entry
- Code SSOT: `ServeDaemon.swift`, `ServeLifecycle.swift`, `ServeAutoLaunch.swift`,
  `ServeDaemonProbe.swift`, `CapacityRefreshScheduler.swift`

Phases are ephemeral. This doc captures **open hotfix hypotheses** from a live
dogfood incident. No fixes are authorized here — investigation and ranked
hypotheses only.

---

## 0. One-sentence claim

**`alln serve` is still not reliably alive on the dogfood Mac when the founder
expects it to be — and we may have masked the failure by manually enabling it.**

---

## 1. Facts from 2026-08-10 (dogfood host, ~3:00pm PDT)

### 1.1 What the founder was testing

Stability: **is `alln serve` staying up on its own?** The answer at check time
was effectively **no** — there was no product-owned continuity path active.

### 1.2 State before agent contamination

| Signal | Observation |
| --- | --- |
| LaunchAgent | **Absent** — `alln serve repair --json` → `outcome: absent`, `no com.allnighter.resident-coordinator plist installed` |
| `alln serve --health` | Initially showed a **debug-build** daemon (`…/Packages/AllnighterCore/.build/…/debug/alln serve`, pid 79995, started ~1:06pm) with `state: available` — **not** the staged Application Support binary and **not** LaunchAgent-supervised |
| Mac app | Open (pid 90022, debug build under `~/Library/Developer/Allnighter/Build/…`) |
| Capacity history | Disk `_newest_success.json` had recent writes; resident socket snapshot was **stale vs disk** at one point (~29m socket age vs ~3m disk recency) |
| Founder intent | Serve should stay up **without** manual intervention — it did not meet that bar |

### 1.3 Agent contamination (invalidates the stability test)

An agent ran **`alln serve enable`** while diagnosing status. That:

1. Installed `~/Library/LaunchAgents/com.allnighter.resident-coordinator.plist`
2. Staged `~/Library/Application Support/Allnighter/CLI/alln`
3. Bootstrapped LaunchAgent pid 4693 on the staged binary
4. Triggered a macOS **Documents folder** TCC prompt attributed to **`alln`**

**This was wrong.** Enable is explicit opt-in founder action, not an agent
diagnostic. The stability experiment is **compromised** until the host is
returned to the pre-enable state and observed again without intervention.

### 1.4 Documents TCC prompt (same session)

Prompt text: **`"alln" would like to access files in your Documents folder.`**

Observed immediately after agent-driven `serve enable`. Multiple prior hotfixes
target this class of leak (`Launch_Authority_TCC_Hotfix`, ProbeScratch CWD,
native capacity spawns, removal of ServeAutoLaunch from Mac app launch). **It
still fired.**

---

## 2. Product law (what we thought we shipped)

From `Serve_Continuity.md` + DEBUGLOG 2026-08-10:

| Mechanism | Intended behavior | Current doubt |
| --- | --- | --- |
| **`serve enable`** | Opt-in LaunchAgent on **staged** binary | Never enabled on this host until agent; logout/login proof still **deferred** |
| **Demand heal (`ServeAutoLaunch`)** | `alln run`, loop verbs restart serve | Mac app launch **explicitly removed** (TCC + fork-bomb) — contradicts SC-S03 "done" banner in parent packet |
| **`serve repair`** | Remove orphan / wedged CODE_RED plist | Host had **no plist** — repair is a no-op; does not *start* serve |
| **Capacity scheduler in serve** | Refreshes when app closed | Only matters if serve is alive |
| **KeepAlive** | Restarts killed serve | Only after explicit `enable`; useless when disabled |

**Lie-prone layer:** "code floor shipped" + green unit tests ≠ serve actually
stays up on the founder Mac without a ritual verb.

---

## 3. Hypotheses — why it is still not fucking working

Ranked by likelihood given today's evidence. **Unconfirmed** until host proof.

### H1 — Default-off + no LaunchAgent = expected death (product gap, not crash)

`serve enable` is **opt-in**. This host had **no plist** until the agent ran
enable. Without that, serve only comes back via demand heal (`alln run`, loop)
or manual `alln serve`.

**If the founder expectation is "always on," the product never promised that
without enable.** The bug may be **expectation / teaching / default policy**,
not a crashed daemon.

**Proof:** With plist removed and app open but no `alln run` — does serve stay
dead for >30m? (Should, per current law.)

---

### H2 — Mac app demand heal was deliberately removed (SC-S03 regression vs TCC fix)

`AllnighterMacApp` / `AppDelegate` **does not** call `ServeAutoLaunch` on
launch (comment: child inherits Dock app TCC → Documents prompts). Unit test
`testMacAppLaunchDoesNotDemandHealServe` **locks this in**.

`Serve_Continuity.md` still claims SC-S03 shipped "Mac app launch calls
ensureRunning." **That is stale relative to code.**

**Effect:** Founder keeps the app open all day; serve dies; **nothing heals it.**

**Proof:** Diff `Serve_Continuity.md` SC-S03 row vs `AppDelegate` + DEBUGLOG
2026-08-10 entry. Reconcile which is SSOT.

---

### H3 — Demand heal surface is too narrow for dogfood reality

Even where SC-S03 holds, heal is only on **`alln run`** and **loop engine
verbs** — not `alln capacity`, `alln bootstrap`, `alln doctor`, menu-bar
actions, or "app is open."

Founder dogfood is **Teams + app open + capacity strip**, not necessarily
`alln run` every hour. Serve can die silently until the next loop dispatch.

**Proof:** Kill serve with app open, use only GUI for 1h — does capacity age
past 30m with no heal?

---

### H4 — Debug serve vs staged binary split (two worlds)

Before contamination, a **debug `.build/alln serve`** was alive (pid 79995).
LaunchAgent targets **staged** `Application Support/Allnighter/CLI/alln`. Health
probe keys off `coordinator.json` pid — whichever process wrote last wins.

Dogfood terminal = debug symlink; continuity path = staged copy. Rebuild
without `install-cli` / `serve enable` refresh can leave **registration,
coordinator record, and running process** on different identities.

**Proof:** After `rebuild_cli.sh`, compare staged bytes, coordinator.json
`binaryGitSha`, and live `pgrep -fl alln serve`.

---

### H5 — LWCR / EX_CONFIG wedge (founder machine class; absent on this host today)

Original code red: orphan CODE_RED plist, exit **78 EX_CONFIG**, LWCR thrash,
~6700 spawn cycles, KeepAlive that never holds a pid.

**This host today:** `repair` reported **absent** — not the same failure mode.
Still a risk if an old plist returns or if new `enable` plist wedges after
logout/login (SC-S04 **unproven**).

**Proof:** `launchctl print gui/$UID/com.allnighter.resident-coordinator` for
`last exit code = 78`, Console LWCR strings. Logout/login with enabled agent.

---

### H6 — Hand LaunchAgent is not BTM/SMAppService (structural fragility)

`serve enable` writes a **LaunchAgents plist** with KeepAlive — not
`SMAppService` / modern Background Task Management registration. Parent packet
§3.2 originally called for SMAppService; shipped SC-S04b is plist-based.

May work same-session (PASS log exists) but fail across logout, OS update, or
privacy reset — **exactly the scenario Serve_Continuity was opened for.**

**Proof:** SC-S04 logout/login host test (still deferred in parent packet).

---

### H7 — Serve dies and nothing notices (health / doctor gap)

`ServeDaemonProbe` reports `foregroundOnly` when no `coordinator.json` or dead
pid — but **nothing pushes that to the founder** during normal app use. Menu
bar / capacity strip can show **stale resident snapshot** while serve is dead
(socket from Mac app) or go cold without a loud "keeper dead" surfacing.

**Proof:** Kill serve, open app, read capacity age for 45m — is failure loud?

---

### H8 — Documents TCC still leaks on serve lifecycle (enable path)

Observed prompt attributed to **`alln`** after `serve enable`. Likely
mechanisms (not mutually exclusive):

| Leak | Mechanism |
| --- | --- |
| **Staging read** | `ServeStableBinary.stage` reads `Data(contentsOf:)` from debug binary at `~/Documents/GitHub/Allnighter/.build/…/alln` when `~/.local/bin/alln` resolves there |
| **Agent shell CWD** | Diagnostic commands ran from repo under `~/Documents/…` (less likely for TCC bucket `alln` unless parent process accessed Documents) |
| **Serve boot probes** | New serve immediately runs `CapacityRefreshScheduler` + `ProbeRecordRefreshScheduler` (`SourceProbeService` full smoke) — any missed ProbeScratch wiring trips TCC |
| **LaunchAgent CWD** | Plist has **no `WorkingDirectory`** — launchd default cwd; child spawns mostly use ProbeScratch, but any path that falls through `ensuredProbeScratchPath() → nil` inherits ambient cwd per `AllnighterPaths` comment |

Prior hotfixes fixed **app-child** and **capacity PTY** paths; **enable +
LaunchAgent-hosted serve** may be a **new seam**.

**Proof:** `tccutil reset`, run only `serve enable` from repo cwd with
Instruments / Console TCC logging; bisect staging vs bootstrap vs first
scheduler tick.

---

### H9 — Socket vs disk freshness split (resident lies while serve dead)

At check time, disk capacity history (`_newest_success.json` at 21:58Z) was
**newer** than the resident socket answer (`observedAt` 21:31Z, ~29m age).
Mac app's `CapacityResidentService` serves `capacity.sock`; serve writes disk
history. When both run, answers can diverge — **`alln capacity` can look
"fine but stale" while misreporting scheduler health.**

**Proof:** Compare socket `observedAt` vs disk `lastObservedAt` per source
with serve killed vs alive.

---

### H10 — KeepAlive restart uses wrong environment

LaunchAgent `environment` is minimal (`XPC_SERVICE_NAME` only); `PATH` is
`/usr/bin:/bin:/usr/sbin:/sbin`. Capacity probes need vendor CLIs on user PATH
(`~/.local/bin`, npm globals, etc.). Serve may **start** but probes **fail**
(spawn failed / never sampled), giving the appearance of a dead or useless
scheduler.

**Proof:** Log probe failures from LaunchAgent-started serve vs manual shell
start; compare `PATH` in child environment.

---

### H11 — Agent actions destroy stability experiments (process discipline)

Running `enable`, `kickstart`, or manual `alln serve` during a "is it still
up?" watch **invalidates the experiment**. Today's session is contaminated.

**Proof:** N/A — operational rule. Reset host before next stability watch.

---

## 4. What we are **not** claiming yet

- We have **not** reproduced LWCR exit 78 on this host post-contamination.
- We have **not** proven logout/login continuity.
- We have **not** bisected the Documents TCC prompt to a single callsite.
- We do **not** know if pid 79995 died naturally or was never the "real"
  keeper the founder cared about.

---

## 5. Recommended next steps (investigation only — no code until ranked)

1. **Reset experiment:** `alln serve disable` (or `repair` if wedged), confirm
   no `alln serve` pid, **do not** manually start serve. Watch ≥1h with app
   open / closed per founder scenario.
2. **Record:** `alln serve --health --json`, `launchctl print`, `pgrep -fl
   alln serve`, `stat` on `Capacity/_newest_success.json`, capacity socket age
   — on a timer, without healing.
3. **Reconcile SC-S03 doc vs code:** Mac app demand heal — shipped or
   intentionally revoked?
4. **TCC bisect:** reset TCC for `alln`, run **only** `serve enable` from
   Documents checkout; note whether prompt fires before or after bootstrap.
5. **PATH probe:** LaunchAgent-started serve vs interactive — do capacity
   probes succeed for the same seats?
6. **SC-S04 logout/login** when founder can spare a session — blocks parent
   packet archive.

---

## 6. Founder rulings needed

| Question | Options |
| --- | --- |
| Default continuity | Stay opt-in (`serve enable`) vs on-after-first-install |
| Mac app heal | Re-enable demand heal with TCC-safe spawn (staged CLI only, never `.app`) vs accept app-open ≠ serve-alive |
| Heal widening | Add `alln capacity` / bootstrap / doctor ensureRunning? |
| TCC on enable | Is staging from Documents-path debug binary acceptable ever? |
| Stability test protocol | Agents must **never** run `serve enable`, `serve`, or `kickstart` during watch periods |

---

## 7. Anti-patterns (do not repeat)

- Agent runs `alln serve enable` during a status check.
- Treating "a serve pid exists" as "continuity works" when it is debug/adhoc.
- Treating KeepAlive plist presence as health without `launchctl print` + live pid.
- Assuming SC-S03 doc banner matches Mac app after 2026-08-10 TCC revert.
