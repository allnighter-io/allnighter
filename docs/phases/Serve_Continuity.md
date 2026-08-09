# Serve Continuity (Background Keeper)

Status: **OPEN — v1 proposal (2026-08-09); Bug Hunt Max `AC9D2295` in flight —
synthesis section reserved for landing update**
Owner: AllnighterCLI / AllnighterEngine (`ServeDaemon`, `ServeAutoLaunch`,
admission, doctor) + Mac app (enablement / launch heal) — **not** a second
capacity scheduler
Created: 2026-08-09
Origin: Dogfood code red — with the Mac app closed, capacity / Pending wake /
Boost / vendor-backoff / OS notifications depend on `alln serve`. Serve can
die; on this host the orphan LaunchAgent did **not** bring it back (exit 78 /
LWCR wedge, ~6700 thrash cycles). Weekly reboot is not a recovery plan.

Related:
- Debugger packet: `docs/operations/debugger/2026-08-09-serve-launchagent-lwcr-PACKET.md`
- Bug Hunt Max: `AC9D2295-329F-4417-A5EC-FA65D010EB1C`
- CODE_RED note: orphan `com.allnighter.resident-coordinator` outlived deleted
  `alln serve install`
- `Probe_Freshness.md` finding 2 — nothing in-repo keeps serve across logout
- Archived intent: `Mac_Standalone_App_And_Background_Coordinator.md` (`alln serve`
  as coordinator; LaunchAgent when start-at-login enabled)
- Shipped substrate to **reuse**: `ServeDaemon`, `ServeDaemonAdmission`,
  `ServeDaemonProbe`, `ServeAutoLaunch`, `CapacityRefreshScheduler`

Phases are ephemeral. At closeout: promote product law into help / doctor /
AGENTS routing; code remains SSOT; archive this packet.

---

## 0. Code-red claim (one sentence)

**Serve may die; failing to notice and failing to bring it back is not allowed.**

Dying is normal. Silent death with a fake supervisor and no heal path is the bug.

---

## 1. First principles (build from scratch)

Ignore the current orphan plist. Ask: how do reliable background Mac products
actually work (sync clients, password managers, container engines, music helpers)?

They share four properties — not cleverness:

| Property | Meaning |
| --- | --- |
| **Stable identity** | One install path, one signing identity, refreshed on update. Not a debug symlink whose cdhash changes every rebuild. |
| **OS-registered supervisor** | Continuity across logout/reboot is owned by Apple’s background-item APIs (`SMAppService` / Login Item / managed agent) — registered, inspected, and removed by the product. Hand-dropped KeepAlive plists are not a product. |
| **Demand heal** | Any ordinary use that implies a live bench re-checks liveness and starts the keeper if missing. Users should not need a ritual verb. |
| **Fail-closed health** | “Registered but not running” and “wedged / throttled / LWCR-dead” are **unhealthy**, never painted as supervised/OK. |

Allnighter already chose the process model: **`alln serve` is the one background
coordinator** (capacity refresh, Pending wake, Boost seed, vendor-backoff
continuation, notifications, cloud relay). Do not invent a second scheduler.
Do not put capacity refresh back in the Dock app as the only automatic path
(Probe_Freshness §0.2).

What we lack is **lifecycle ownership** around that one process.

```text
                    ┌─────────────────────────────┐
   login / reboot   │  OS supervisor (SMAppService │  optional, founder-gated
                    │  registered agent)           │  "start at login"
                    └──────────────┬──────────────┘
                                   │ starts / restarts
                                   ▼
                           ┌───────────────┐
                           │  alln serve   │  ← sole scheduler host
                           └───────┬───────┘
                                   ▲
   app open / alln run / loop /    │ ensureRunning (demand heal)
   capacity / bootstrap            │
                                   │
                    ┌──────────────┴──────────────┐
                    │  ServeLifecycle (product)   │
                    │  enable · disable · status  │
                    │  repair · health (honest)   │
                    └─────────────────────────────┘
```

---

## 2. What broke on the dogfood host (facts, not theory)

Verified 2026-08-09 before this packet:

1. Capacity history advanced on a ~30m cadence with the app closed until
   ~10:45am PDT, then stopped — so serve-hosted refresh **worked**, then the
   keeper was gone.
2. `~/Library/LaunchAgents/com.allnighter.resident-coordinator.plist` exists
   with KeepAlive / RunAtLoad, points at `~/.local/bin/alln serve`, but
   launchd reported `spawn scheduled`, exit **78 EX_CONFIG**, runs ≈ 6700+.
3. Console: `Unable to get updated LWCR … error 0x3` / `Unable to update LWCR
   with smd: 3` on a ~10s cadence — pre-exec refuse while thrashing.
4. Manual `alln serve` starts; `ServeDaemonAdmission` exit paths are 0/1 only;
   product code does not emit exit 78.
5. `ServeAutoLaunch.ensureRunning` is wired to **Loop engine verbs only** — not
   `alln run`, not Mac app launch. This Bug Hunt team run itself ran minutes
   without spawning serve.
6. `alln serve install` was deleted; help tests forbid resurrecting it; CODE_RED
   left the orphan agent “on purpose.” The machine **looks** supervised and is not.

**Lie:** plist + KeepAlive + “spawn scheduled” ⇒ recovery exists.  
**Truth:** no product-owned lifecycle; OS registration is stale/wedged; demand
heal is too narrow; health does not fail closed on the wedge.

---

## 3. Proposed solution (simple, no hacks)

One new product concept: **`ServeLifecycle`** — the sole owner of how `alln
serve` is enabled, registered, inspected, repaired, and demand-started.

Everything below is that idea broken into slices. No parallel capacity poller.
No “just kickstart harder.” No “reboot and hope.”

### 3.1 Stable binary for any OS-managed agent

If start-at-login is on, the supervisor must target a **stable, product-owned
executable**:

- Prefer: `Allnighter.app` embedded CLI / Developer ID (or notarized) install
  path managed by `install-cli` / app updates.
- Forbid as the KeepAlive target: adhoc-signed SwiftPM debug symlink that
  changes cdhash every `rebuild_cli.sh` (this host’s `~/.local/bin/alln` →
  debug). Dogfood can still run debug **foreground**; OS-managed continuity
  requires a stable identity or an explicit refresh of registration on every
  rebuild (see 3.2).

### 3.2 Supported enablement (replace the orphan)

Ship lifecycle verbs (names illustrative — contract owns final grammar):

| Verb | Job |
| --- | --- |
| `alln serve status` | Honest: daemon live? OS agent registered? wedged? identity match? |
| `alln serve enable` | Register via **SMAppService** (or equivalent supported API), not a hand-copied plist. Idempotent. |
| `alln serve disable` | Unregister + stop. Leaves no orphan. |
| `alln serve repair` | Detect wedge (EX_CONFIG / LWCR / throttle / stale registration) → supported re-bind or disable+enable → verify `serve --health` available. |

`enable` is opt-in (founder ruling on default). Disabling is first-class.
The CODE_RED orphan is **migrated away** in the same change that ships enable
(bootout + delete, or adopt-then-replace — never leave two labels).

### 3.3 Demand heal on real fronts

Reuse `ServeAutoLaunch.ensureRunning` (probe → detached start, existing
opt-outs). Widen call sites to fronts weekly-reboot users actually hit:

**Must (v1 continuity):**

- Mac app launch (in addition to in-process `CapacityResidentService` — app
  open should also ensure the coordinator, then history-recency arbiter
  prevents double-probe storms).
- `alln run` / team dispatch (opt-out `--no-auto-serve` / `ALLN_NO_AUTO_SERVE`).

**Already have:**

- `alln loop` engine verbs (`step` / `start` / `resume` / `pm` / adopt paths).

**Nice:**

- `alln capacity`, `alln bootstrap` — cheap ensure before work that assumes a
  live bench.

Demand heal does **not** replace login continuity; it means **one ordinary
action after death is enough**. Loop-only heal is why an all-day Teams dogfood
with the app closed went dark.

### 3.4 Fail-closed health / doctor

`alln serve --health` and `alln doctor` must report unhealthy when:

- OS agent registered but no live daemon, or
- launchd state is wedged (`spawn scheduled` + EX_CONFIG / LWCR errors), or
- recorded pid is live but is **not** an `alln serve` of the expected build
  (see 3.5).

Never imply “KeepAlive = OK.” Recovery text points at `serve repair` or
`serve enable`, not reboot.

### 3.5 Admission must identify *serve*, not a recycled PID

`ServeDaemonAdmission` already lists real `alln serve` PIDs from the process
table. Health and refuse paths must not treat `kill(pid, 0)` alone as “our
daemon is up” when the coordinator record’s pid has been recycled by an
unrelated process. Refuse / already-running only when the live process is
verified as `alln serve` (args + preferably matching git sha). Stale records
clear; they do not exit(0) in a KeepAlive death loop.

### 3.6 What we explicitly will not do

- Second `CapacityRefreshScheduler` in the app “just in case.”
- Hand-maintained LaunchAgent as the supported path.
- Silent fallback that invents capacity while serve is down.
- Requiring weekly reboot as recovery.
- Resurrecting deleted `serve install` help text without a real SMAppService
  owner and doctor path.

---

## 4. Slice sketch (implementation order)

| Slice | Outcome | Proof |
| --- | --- | --- |
| **SC-S00** | Doctor / `--health` fail-closed on orphan or wedged LA; teaching text. No behavior change to start yet. | Fixture or host: wedged label ⇒ unhealthy + repair hint. |
| **SC-S01** | `ServeLifecycle` status/repair; migrate/remove CODE_RED orphan; stop 10s thrash. | After repair or remove: no LWCR thrash; health honest. |
| **SC-S02** | Demand heal: app launch + `alln run` call `ensureRunning` (opt-out preserved). | Kill serve → `alln run` or open app → health `available` without reboot. |
| **SC-S03** | `enable` / `disable` via SMAppService against stable binary; rebuild refreshes registration when enablement is on. | Reboot/login Works Test (founder host): serve comes back; capacity stamp advances app-closed. |
| **SC-S04** | Admission PID identity harden (if still open after S01). | Recycled-pid fixture cannot `refuse` forever. |

S00–S02 are the **code-red floor** (notice + heal without reboot). S03 is
login continuity (founder opt-in). S04 closes a lie class if Bug Hunt’s
admission hypothesis survives.

---

## 5. Works Test (product claim)

> With the Dock app quit: if `alln serve` is killed, the next ordinary bench
> action (`alln run` or opening the app) brings serve back within seconds;
> capacity history advances again without a reboot. If start-at-login is
> enabled, serve also returns after logout/login. Doctor never reports a
> wedged LaunchAgent as healthy.

---

## 6. Founder rulings needed

1. **Default enablement:** start-at-login off until explicit `serve enable`
   (recommended), vs on after first successful install.
2. **Stable binary for OS agent:** require app-bundled / notarized CLI for
   enablement, vs allow debug with mandatory re-register on every rebuild
   (dogfood-hostile but possible).
3. **`alln run` auto-serve:** yes (recommended for hero all-day Teams) vs
   loop-only (status quo — proven insufficient).

---

## 7. Bug Hunt synthesis (placeholder — update on land)

Bug Hunt Max `AC9D2295` still running as of v1 commit. Early seat agreement:

- Orphan KeepAlive is a lie-prone layer; demand heal is too narrow; do not add
  a second scheduler.
- Host evidence for LWCR / EX_CONFIG thrash is real.

Early dissent (to reconcile on land — do not pick winners in v1):

- Whether LWCR “never hands off” vs launchd throttle after rapid exits (one
  seat claimed `bootout`+`bootstrap` cleared the wedge on this host).
- Whether `ServeDaemonAdmission` recycled-PID refuse is a contributing death
  loop (needs a kill-test, not assertion alone).

**This section will be replaced** when the team artifact / lead answer lands,
with an explicit **v1 → Bug Hunt delta** list.

---

## 8. Routing

While open: this packet.  
After ship: code SSOT `ServeLifecycle` (name TBD) + `ServeDaemon*` +
`ServeAutoLaunch`; help topics; doctor; AGENTS row for “serve dead / capacity
stale with app closed.”
