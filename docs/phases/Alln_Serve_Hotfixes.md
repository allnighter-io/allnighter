# Allnighter — `alln serve` Hotfixes

Status: **OPEN — incident 2026-08-10 — v2 (external review)**
Owner: AllnighterCLI / AllnighterEngine (`ServeDaemon`, `ServeLifecycle`,
`ServeAutoLaunch`, `ServeLaunchAgentStatus`, `CapacityRefreshScheduler`)
Created: 2026-08-10
Revised: 2026-08-10 (v2 — DeepSeek V4 Pro review via `alln run`)
Review run: `CF00F214-CDF6-42B0-B915-1BA7B7756E93` (`model_opencode_deepseek_v4_pro`, read-only)
Related:
- [`Serve_Continuity.md`](Serve_Continuity.md) — parent packet (code floor shipped; host proof incomplete)
- [`docs/operations/debugger/2026-08-09-serve-launchagent-lwcr-PACKET.md`](../operations/debugger/2026-08-09-serve-launchagent-lwcr-PACKET.md)
- [`docs/operations/debugger/2026-08-10-mac-serve-fork-bomb-PACKET.md`](../operations/debugger/2026-08-10-mac-serve-fork-bomb-PACKET.md)
- [`docs/operations/debugger/DEBUGLOG.md`](../operations/debugger/DEBUGLOG.md) — 2026-08-10 TCC / cold-launch entry
- Code SSOT: `ServeDaemon.swift`, `ServeLifecycle.swift`, `ServeAutoLaunch.swift`,
  `ServeDaemonProbe.swift`, `CapacityRefreshScheduler.swift`

Phases are ephemeral. This doc captures **open hotfix hypotheses** from a live
dogfood incident, plus an external review with ranked fix slices. **No code
changes are authorized from this packet alone** — slices below are the build
queue input.

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

### 3.1 External review verdicts (DeepSeek V4 Pro, 2026-08-10)

| Hypothesis | Verdict | Notes |
| --- | --- | --- |
| H1 | **Agree** | Opt-in by design; founder expected "always on" without `serve enable` — teaching gap |
| H2 | **Agree** | `Serve_Continuity.md:217` is stale; code + `testMacAppLaunchDoesNotDemandHealServe` are SSOT |
| H3 | **Agree** | Operational failure mode of H1+H2 — heal only on `alln run` + loop |
| H4 | **Agree** | Two binaries, one `coordinator.json` — confusion, not primary crash |
| H5 | **Agree (risk), not active here** | This host had no plist pre-contamination; LWCR class still real |
| H6 | **Agree strongly** | Shipped hand plist violates parent packet §3.1 SMAppService intent |
| H7 | **Agree** | Honest probe exists; nothing surfaces dead keeper to founder |
| H8 | **Agree** | **Confirmed callsite:** `ServeStableBinary.swift:73` `Data(contentsOf:)` during `enable` staging from Documents-path debug binary |
| H9 | **Agree (symptom)** | Fix via H7 observability, not merging socket + disk paths |
| H10 | **Agree (caveat)** | `AgentPlist` has no `EnvironmentVariables`; launchd PATH too narrow |
| H11 | **Agree** | Needs code enforcement, not prose alone |

---

## 4. Root cause ranking (review + incident)

| Rank | What | Category | Code / doc reference |
| --- | --- | --- | --- |
| **1** | Founder expects always-on; product is opt-in with no teaching | Expectation mismatch | `ServeLifecycle.enable()` |
| **2** | SC-S03 doc claims Mac app heal; code forbids it | **Documentation drift** | `Serve_Continuity.md:217` vs `AllnighterMacApp.swift:114-118` |
| **3** | Only `alln run` + loop heal; dogfood uses app + capacity strip | **Actually broken** | `RunCLI.swift:169-174` |
| **4** | Hand LaunchAgent, not SMAppService/BTM | **Structural** | `ServeLifecycle.swift` plist write + bootstrap |
| **5** | `enable` stages via `Data(contentsOf:)` from Documents-path binary | **TCC leak** | `ServeStableBinary.swift:73` |
| **6** | Dead keeper invisible in UI | **Observability** | `ServeDaemonProbe` unused on timer |
| **7** | LaunchAgent serve missing PATH for vendor CLIs | **Silent probe failure** | `AgentPlist` no env block |
| **8** | Debug vs staged binary identity split | Operational confusion | `coordinator.json` / `ServeDaemonStore` |

---

## 5. Why this is so fucking hard (should be easy — isn't)

**It should be easy:** one background process, KeepAlive, done.

**It isn't**, because Allnighter picked the hardest macOS configuration:

1. **BTM/LWCR** — LaunchAgents pin to exact code identity. Every `rebuild_cli.sh`
   rotates the debug cdhash. macOS can refuse exec (exit 78) before `main` with
   no product-visible error except `launchctl print` string parsing.

2. **Staged-binary fix creates TCC problem** — Stable identity lives in Application
   Support, but staging *from* `~/Documents/…/.build/debug/alln` is a Documents
   read → TCC prompt. Fixing continuity triggers privacy.

3. **No supported API for "CLI login item"** — `SMAppService` wants an `.app`.
   Background coordinator is a bare CLI. Hand plist is the only path — and it's
   the path macOS is pushing away from.

4. **TCC inheritance blocks app-side heal** — Dock app spawning `Process` inherits
   app TCC identity. Mac app demand heal was removed after fork-bomb + Documents
   prompts. "App open → serve starts" has no clean seam.

5. **The monitor is the monitored** — When serve dies, nothing runs
   `ServeDaemonProbe` on a schedule. Watchers: LaunchAgent (if enabled), `alln
   run` (if invoked), loop verbs. All three were closed on 2026-08-10.

**Blunt summary (review):** macOS spent a decade making background processes
harder; we built a constantly-rebuilt adhoc-signed CLI that wants to behave like
a system daemon.

---

## 6. Fix slices (ordered — smallest shippable first)

Review recommendations. **Not implemented in this commit.**

| Slice | What | Effort | ROI |
| --- | --- | --- | --- |
| **ASH-S01** | Fix SC-S03 doc drift (`Serve_Continuity.md`, lwcr packet line 117) | Docs only | Immediate clarity |
| **ASH-S02** | Widen demand heal: `alln capacity`, `bootstrap`, `doctor` — same `ServeAutoLaunchCLI` block as `RunCLI.swift:169-174` | Small code | **Highest** — matches dogfood verbs |
| **ASH-S03** | Mac app heal **only when LaunchAgent plist exists** — spawn **staged CLI**, never `.app` (`ServeStableBinary.defaultDestinationURL()`) | Medium | Closes app-open gap without fork bomb |
| **ASH-S04** | TCC-safe enable: refuse Documents/Desktop/Downloads staging path; **require staged binary from `install-cli` first**; optional ProbeScratch intermediary copy | Small code | Stops Documents prompt on enable |
| **ASH-S05** | `AgentPlist.EnvironmentVariables` — user PATH + HOME for LaunchAgent serve | Small code | Fixes silent probe failure (H10) |
| **ASH-S06** | Dead-keeper surfacing — menu bar / capacity strip warns when `ServeDaemonProbe` ≠ `.available` >5m | Medium | Makes failure visible (H7) |
| **ASH-S07** | `.stability-watch` sentinel — refuse `enable`/`disable`/`serve`/`repair` mutations during host watches + `scripts/serve-stability-watch.sh` | Medium | Agent-proof experiments (H11) |
| **ASH-S08** | SMAppService / BTM migration (structural) — likely via Mac app login item spawning staged CLI | Large | SC-S04 logout/login; parent packet intent |

### TCC callsite (confirmed)

```
alln serve enable
  → ServeLifecycle.enable() (:215)
  → stage(currentExecutableURL)  // resolves to ~/Documents/.../.build/debug/alln
  → ServeStableBinary.stage(:73) Data(contentsOf: sourceURL)
  → macOS Documents TCC prompt on "alln"
```

**Best fix (review):** `enable` must not be the first staging call. Require
`install-cli` / SC-S02 staged binary to exist; refuse enable otherwise.

---

## 7. Stability test protocol (agent-proof)

Procedural rules failed today (agent ran `enable`). Review recommends
**declarative refusal**:

1. Sentinel: `~/Library/Application Support/Allnighter/.stability-watch`
2. When present, refuse: `serve enable`, `serve disable`, `serve repair`
   (non-absent), `alln serve` (daemon start), `refreshAfterInstall`
3. Script: `scripts/serve-stability-watch.sh` — creates sentinel, logs health +
   launchctl + capacity stamp every 5m, no mutations
4. CI: `testEnableRefusesDuringStabilityWatch`, `testRepairRefusesDuringStabilityWatch`
5. Agent rule: **never delete sentinel**; if refused, STOP and report

**Reset contaminated host before next watch:** `alln serve disable`, confirm no
pid, observe ≥1h without healing.

---

## 8. What we are **not** claiming yet

- We have **not** reproduced LWCR exit 78 on this host post-contamination.
- We have **not** proven logout/login continuity.
- TCC callsite is **hypothesis-confirmed** (`ServeStableBinary.swift:73`) but not
  host-reproduced with Instruments after sentinel reset.
- We do **not** know if pid 79995 died naturally or was never the "real"
  keeper the founder cared about.

---

## 9. Recommended next steps

1. **Reset experiment** (founder): `alln serve disable`, no manual start, watch
   ≥1h — ideally via ASH-S07 sentinel script once built.
2. **Ship ASH-S01 + ASH-S02** — doc truth + heal widening (low risk, high ROI).
3. **Founder ruling** on ASH-S03 (conditional Mac app heal) vs ASH-S02-only path.
4. **Ship ASH-S04** before anyone runs `serve enable` from Documents checkout again.
5. **SC-S04 logout/login** host proof when session can be spared.

---

## 10. Founder rulings needed

| Question | Options |
| --- | --- |
| Default continuity | Stay opt-in (`serve enable`) vs on-after-first-install |
| Mac app heal | Re-enable demand heal with TCC-safe spawn (staged CLI only, never `.app`) vs accept app-open ≠ serve-alive |
| Heal widening | Add `alln capacity` / bootstrap / doctor ensureRunning? |
| TCC on enable | Is staging from Documents-path debug binary acceptable ever? |
| Stability test protocol | Agents must **never** run `serve enable`, `serve`, or `kickstart` during watch periods |

---

## 11. Anti-patterns (do not repeat)

- Agent runs `alln serve enable` during a status check.
- Treating "a serve pid exists" as "continuity works" when it is debug/adhoc.
- Treating KeepAlive plist presence as health without `launchctl print` + live pid.
- Assuming SC-S03 doc banner matches Mac app after 2026-08-10 TCC revert.
