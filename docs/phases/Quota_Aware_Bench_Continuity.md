# Quota-Aware Bench Continuity

Status: **OPEN — founder priority (2026-07-30)**
Owner: AllnighterCore (menu envelope) + AllnighterEngine (loop park-yield) +
AllnighterCLI (capacity injection, `alln loop` delivery)
Created: 2026-07-30
Revised: 2026-07-31 (code-verified pass — symbol names, layering, and the
resume-race were wrong in v2; see "Corrections against live code")
Origin: Founder dogfood — `alln capacity` + cross-vendor substitution exist at
runtime, but planners never see the meter at plan time; long `alln loop` dev
turns hit session caps and die because the loop ignores a successful vendor park
and thrash-retries as infra backoff.

Related shipped substrate (reuse, do not re-build):
archived [`Capacity_Hardening_Hotfix.md`](../archive/phases/Capacity_Hardening_Hotfix.md),
archived `Rate_Limit_Continuity.md` (`VendorBackoffPolicy`,
`VendorBackoffReconciler`, `VendorSubstitutionPolicy`),
[`Loop_Verb_Cutover.md`](../archive/phases/Loop_Verb_Cutover.md),
[`Work_Recovery_And_PM_Continuity.md`](Work_Recovery_And_PM_Continuity.md)
(composes; does not replace).

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations; code remains SSOT; archive this packet.

---

## Corrections against live code (2026-07-31)

Every claim below was checked against the tree, not remembered. These are the
deltas from the v2 draft; the slice plan already reflects them.

1. **Stale symbol names.** `RelayCoordinator` / `RelayState` /
   `RelayTurnClassifier` / `RelayCoordinatorTests` do not exist. The Loop Verb
   Cutover renamed them: `LoopCoordinator` (AllnighterEngine),
   `LoopState` (AllnighterCore), `LoopTurnClassifier`, `LoopCoordinatorTests`.
   `AGENTS.md` still routes to `RelayCoordinator` and must be fixed at closeout.
2. **S00 as drafted does not compile.** `CapacityDisplayAcquisition` lives in
   **AllnighterEngine** (`CapacityHistoryStore.swift:281`);
   `MenuCatalog` / `MenuJSON` / `Bootstrap` live in **AllnighterCore**. Core
   cannot import Engine. Capacity must be **injected downward** from
   AllnighterCLI, never acquired inside `MenuCatalog.project`.
3. **Do not embed the strip type — it is a display type.** `CapacityStripJSON`
   (`CapacityStripRenderer.swift:7,26`) is what `alln capacity --json` emits, and
   reusing it verbatim costs a measured **4,113 bytes for 6 rows**. That is 12%
   of the whole menu for six numbers, and the breakdown shows why it is the
   wrong type to embed:

   | Key | Bytes across 6 rows | Verdict for a planner |
   | --- | --- | --- |
   | `pools[]` | 958 (35%) | **Cut** — for flat sources it verbatim restates the row-level fields. Only `agy` has genuinely distinct pools, and its ceiling is already `effectiveRemainingPercent` |
   | `observedAt` | 210 | **Cut** — `observedAgeSeconds` carries the same honesty in fewer bytes, and the envelope already has `generatedAt` |
   | `displayName` | 140 | **Cut** — derivable from `source` |
   | `color` | 88 | **Cut** — TTY/GUI presentation, meaningless to a planner |
   | pretty-printing | 1,265 (31%) | Structural; shrinks with the field count |

   The menu needs a **decision** row, not a display row: `source`,
   `effectiveRemainingPercent`, `resetAt`, `scope`, `shortRemainingPercent`,
   `observedAgeSeconds`, `unknownReason`. Measured on this bench: **815 bytes
   pretty / 562 compact — 2.3% of the menu**, a 5× reduction. Project it from
   `CapacityBenchRow`, which is **already in Core** — so this stays a
   Core→Core projection with no new acquisition and no Engine dependency.

   **Rounding law:** the live strip emits `"age":818.8028600215912` and
   `74.22`. Sub-millisecond precision on a staleness number is both byte waste
   and false confidence. Percentages and ages round to `Int` in the menu row.
4. **The byte budget is already blown, before this packet.** Live
   `alln menu --json` on the founder's bench is **35,037 bytes** — over the
   32,768 cap. `MenuSelectionGradeTests:159` only asserts against the *built-in
   fixture*, so the gate does not protect the real surface. Re-setting the
   budget is an S00 **prerequisite**, not a QABC-caused regression.
5. **`--refresh` does not exist on `alln capacity`.** The real flags are
   `--cached` / `--no-refresh`, and **refresh is the default**
   (`AllnighterCLI.swift:352-354`). The law is "menu passes `refresh: false`",
   not "`--refresh` stays on capacity".
6. **The live bug is worse than described.** Each infra retry calls
   `RunService.mintRunId()` (`LoopCoordinator.swift:1786`) and re-parks a
   **fresh mutating run**. Ten retries leave up to **ten orphaned parked
   mutating runs**, each of which `VendorBackoffReconciler` will independently
   wake at reset and replay the same dev prompt against the repo. The write lock
   serializes them; it does not prevent ten repeated executions of the same
   turn. This is a repo-safety bug, not only a continuity bug.
7. **"Alive loop owner resumes" races `alln serve`.** `resumeParkedRun` requires
   a lease (`blocker.holderId == coordinatorId`,
   `RunService.swift:592-598`), and `RunStore.claimVendorWake` refuses to claim
   before `wakeAfter` unless `force: true` (`RunStore.swift:346-354`). So the
   loop cannot pre-claim; it must claim at wake — exactly when the reconciler is
   also polling. **Two `alln serve` daemons are running on this machine right
   now.** Whoever claims first wins; if serve wins, the loop's claim returns
   `nil` and the loop escalates while the run resumes orphaned. That is the same
   bug, relocated. Fix: **claim-or-adopt** (below).
8. **`capacityParked` must not be a `LoopState.Status`.**
   `LoopStateStore.save` writes the `owner.pid` marker only for `.running` and
   clears it otherwise (`LoopStateStore.swift:66-70`), and
   `reconcileOrphan` only scans `.running`. A loop asleep for five hours has a
   **live owning process**; giving it a non-`running` status would strip its
   owner marker and drop it out of orphan reconcile and `alln ps` liveness.
   The codebase already has the right precedent: `LoopState.laneBlocked`
   (`LoopState.swift:244`) — a "why am I waiting" side-field on a still-running
   loop. Use that shape. This also means **no LVC status-law amendment is
   needed**, which deletes a closeout obligation.
9. **`parkedRunId` is redundant.** `persistDeliveredDevRun` stamps the attempt
   run id onto the open round before the worker wait
   (`LoopCoordinator.swift:1785-1788`), so `round.devRunId` already points at
   the parked run.

---

## Founder intake (SSOT_Founder_Input_Workflow)

```text
Founder intent:
  Put capacity facts in the selection envelope so every plan is quota-aware
  without a separate `alln capacity` call. When a loop/run still hits a wall,
  sleep until the vendor reset and continue — do not escalate after ~50s of
  5-second infra retries.

Product value:
  Cross-vendor arbitrage no single vendor can copy. Behavior, not a dashboard:
  PM routes around limits before wrong-seat spend; owned loops finish across
  session caps.

Trusted workflow slice:
  Opus reads `alln menu --json` → seats Grok because Codex is at 0% → `alln loop
  start "…" --dev model_grok` runs for hours → a later Claude 5h wall parks with
  wakeAfter → the loop sleeps, then claims-or-adopts the wake → round continues
  without founder paste.

Truth owner:
  Plan-time: `CapacityDisplayAcquisition` + `CapacityBenchProjection` +
  `CapacityStripRenderer.json` (all existing) → injected into
  `MenuCatalog.project` / `Bootstrap` as `MenuJSON.capacity`.
  Runtime park: `RunService` + `RunStore` (`waitingForVendor`,
  `blocker.wakeAfter`, `claimVendorWake`).
  Loop yield/resume: `LoopCoordinator` + `LoopState.capacityPark`.
  Wake fallback for dead owners + standalone runs: `VendorBackoffReconciler`.
  Substitution on long reset: `VendorSubstitutionPolicy` (unchanged).

Blocking questions: none — decisions locked below.
```

---

## Product promise

```text
The PM knows what you have left — and routes around it without being asked.
When a wall is still hit, Allnighter sleeps until the meter resets and continues
the work it owns — not after a minute of useless retries.
```

| Half | Question | Primary surface | Slice |
| --- | --- | --- | --- |
| **Plan-time quota** | Which seat has headroom before dispatch? | `alln menu --json` + bootstrap | QABC-S00 |
| **Loop continuity** | Turn hits a session cap mid-loop? | `alln loop` + vendor park/wake | QABC-S01 |

**Scope honesty:** this does **not** auto-resume naked vendor sessions that never
touched alln. Continuity requires `alln run` / `alln loop` ownership.

**Moat sentence (promote at closeout):** Anthropic can only see Anthropic's
meter. Cross-vendor arbitrage is impossible from inside any one vendor.
Allnighter sees the whole bench and acts on it at plan time and at the wall.

Rough cost: **S00 small** (one optional field, one parameter, three call sites —
no new projection code). **S01 medium** (one helper, one side-field, one wait
loop). Not a new subsystem.

---

## Why this exists

1. A planner seats from `menu --json` with no capacity → wrong seat (Codex is at
   0% on this bench right now).
2. A Claude 5h cap parks the dev turn with a real `wakeAfter`, but the loop
   classifies the parked run's answer as `.infraBackoff`
   (`LoopTurnClassifier.swift:88-91` — the structured `capacityObservation`
   fires), sleeps 5s × 10, mints a new run each time, then escalates. The
   founder returns to a dead loop and up to ten orphaned parked mutating runs
   queued to replay the same turn.

Standalone `alln run` + `alln serve` continuity already works. The gaps are
planner visibility and the loop's refusal to recognise a park.

---

## Architecture (reuse)

```text
Plan time                          Turn time                      Loop time
─────────                          ─────────                      ─────────
AllnighterCLI                      RunService.run                 dispatchTurn /
  └─ CapacityDisplayAcquisition      └─ park: queued +             dispatchDevTurn
       .windows(refresh: false)           waitingForVendor           └─ vendorPark(run)?
  └─ CapacityBenchProjection.rows       + blocker.wakeAfter              │  (BEFORE classify)
  └─ MenuJSON.Capacity(rows:now:)       → .success(run)                  ▼
       │  (815 B, 6 rows)                                         sleep→ claim-or-adopt
       ▼ injected                                                        │
  MenuCatalog.project(capacity:)   VendorBackoffReconciler                ▼
  Bootstrap(capacity:)              (dead owners + standalone)    same run settles →
       └─ MenuJSON.capacity                                       re-enter classify
```

**Laws:**

- Capacity is **injected** into Core, never acquired there. Core must not gain an
  Engine dependency.
- `menu --json` passes `refresh: false` — it spawns no probes. Refresh stays the
  default only on `alln capacity` itself.
- Capacity never goes in `TeachingSnippet.body`; live JSON is SSOT.
- **A parked run is not a turn outcome — it is a turn still in progress.** The
  park check runs before `LoopTurnClassifier`, and the loop re-enters the same
  classification switch once the run settles.
- While parked, **never mint a competing runId**.
- A parked loop stays `status == .running`. Park facts live in a side-field.

---

## Locked decisions

1. Park visibility is `LoopState.capacityPark` (a `laneBlocked`-shaped
   side-field), **not** a new `LoopState.Status` case. No LVC law amendment.
2. Both `dispatchTurn` (PM) and `dispatchDevTurn` get the check, via one shared
   helper. Deferring the PM twin costs more than doing it: the same orphaned
   parked-run problem applies and the fix is the same three lines.
3. Wake is **claim-or-adopt**, never claim-or-escalate. Serve winning the race is
   a normal outcome, not a failure.
4. The menu carries a lean **decision** row (~815 B), not the `CapacityStripJSON`
   **display** row (~4,113 B). Percentages and ages round to `Int`.
5. Menu byte budget is re-set and the gate is extended to a realistic catalog
   **before** capacity is added (prerequisite, S00).
6. S02 (acks/help) folds into S01. S03 (counsel string) is **cut** — see below.

---

## Slice plan

### QABC-S00 — Capacity in the selection envelope

**Goal:** Every agent reading `alln menu --json` before planning sees a compact,
honestly aged capacity snapshot, with no probe spawned.

**S00a — prerequisite: fix the byte gate.** Live menu is 35,037 B against a
32,768 B documented cap that only the built-in fixture is tested against. Extend
`MenuSelectionGradeTests` to project a realistic large catalog and set the
budget to a number the real surface meets. Shipping S00 on top of an
untested-and-already-exceeded budget would make the gate a lie.

Note the sizes: `models` 11,664 B, `teams` 10,433 B, `commands` 8,447 B. Capacity
at 815 B is 2.3% and is **not** what broke the budget. Do not let this packet
absorb blame for a gate that was already failing — but do not stack onto it
either. If the re-set proves contentious, the fallback is to trim `commands`
(the least-read section), not to drop capacity.

| Surface | Change |
| --- | --- |
| `MenuJSON.Capacity` | New lean Core type: `generatedAt` + `rows[]` of `{source, effectiveRemainingPercent: Int?, resetAt, scope, shortRemainingPercent: Int?, observedAgeSeconds: Int, unknownReason}`. ~15 lines. **Not** `CapacityStripJSON` (correction 3) |
| `MenuJSON` | `public var capacity: Capacity?` — one optional field |
| `MenuCatalog.project` | New `capacity: Capacity? = nil` parameter, passed straight through. No acquisition, no Engine import |
| `Bootstrap` | Same optional parameter, same passthrough |
| `MenuJSON.Capacity.init(strip: CapacityStripJSON)` | A **narrowing** projection of the row `alln capacity` already computes — drops `pools`/`color`/`displayName`/`observedAt`, rounds to `Int`. Deriving from `CapacityStripJSONRow` rather than re-deriving from `CapacityBenchRow` keeps **one** derivation path, so `menu` and `alln capacity` can never report different remaining values |
| `MenuCLI` / `HelpCLI` / bootstrap CLI | Acquire and inject: `CapacityDisplayAcquisition.windows(now:, refresh: false)` → `CapacityBenchProjection.rows` → `CapacityStripRenderer.json` → `MenuJSON.Capacity(strip:)` |
| `alln menu show model:<id>` | Filter injected rows to that model's source |

**Measured budget:** 815 B pretty (2.3% of the live 35,037 B menu), against
4,113 B (11.7%) if the strip type were embedded. `alln capacity --json` keeps
emitting the full strip — disclosure lives there, decisions live in the menu.

**Constraints:**

- Nil capacity is always legal — unknown never blocks menu or seating. Every
  non-CLI caller (`ModelListProjector`, `CatalogJSON`, `TypedRef`, tests) keeps
  compiling untouched because the parameter defaults to `nil`.
- Rows already carry `observedAt` + `observedAgeSeconds` + `unknownReason`. Never
  render them in a way that implies a fresh probe.
- **Gate:** bump `contractVersion` (currently 7.0.0); extend `ContractSchema`'s
  MenuJSON schema with the optional `capacity` object.

**Works Test:**

```text
scripts/swift-test.sh --filter MenuSelectionGradeTests
scripts/swift-test.sh --filter CapacityBenchProjectionTests
scripts/swift-test.sh --filter ContractSchema
# New: menu projection with injected capacity spawns zero probes (inject a
# counting CapacityProbeExecuting and assert count == 0).
# Manual: alln menu --json | jq '.capacity.rows[] | {source, effectiveRemainingPercent, observedAgeSeconds}'
```

**Proof waiver:** None.

---

### QABC-S01 — The loop yields to a vendor park

**Goal:** A parked turn suspends the loop until the meter resets, then continues
the same round — instead of thrashing, escalating, and stranding mutating runs.

**1. One shared park probe** (pure, testable, in `LoopCoordinator` or beside
`LoopTurnClassifier`):

```text
vendorPark(run) -> (runId, wakeAfter, source)?
  run.status == .queued && run.phase == .waitingForVendor
    && run.blocker?.resource == .vendorBackoff
```

Called in **both** `dispatchTurn` and `dispatchDevTurn`, immediately after
`guard case .success(let run)` and **before** `LoopTurnClassifier.classify`.
On a hit the dispatch loop does not retry, does not kill the turn group, and
does not mint a new runId.

**2. Claim-or-adopt wake** (this is the whole race fix):

```text
persist LoopState.capacityPark { runId, wakeAfter, source, since }
sleep until wakeAfter, clamped to the loop deadline (existing
  sleepClampedToDeadline; re-check isPastDeadline on wake)
try runStore.claimVendorWake(runId:coordinatorId: <loopId>, now:)
  claimed  → runService.resumeParkedRun(runId:coordinatorId:) → settled run
  nil      → another coordinator (alln serve) owns this wake.
             DO NOT escalate. Poll the journal until the run leaves
             .waitingForVendor, then load the settled run.
clear capacityPark; re-enter the SAME classification switch with the settled run
```

Deadline expiry while parked is the one honest escalation: the loop's `--until`
ceiling fired, and it says so with the wake time it was waiting for.

**3. Visibility:**

| Component | Behavior |
| --- | --- |
| `LoopState.capacityPark` | Optional struct: `runId`, `wakeAfter`, `source`, `since`. `laneBlocked`-shaped; lenient decode like every other post-hoc field |
| `LoopState.status` | Stays `.running` — the owning process is alive (see correction 8) |
| `alln loop status` | Surfaces `capacityPark` with the wake clock and the exact next command; `--wait-for` becomes wake-aware. `loop wait` is untouched (`PilotCLI.runWatch`, different flags) |
| Detached ack / notification | Names `wakeAfter` + source, so URN can fire a "parked until X" banner instead of silence |
| `VendorBackoffReconciler` | **Unchanged.** It remains the fallback for standalone runs and dead owners, and is now a legitimate winner of the claim race |
| `VendorSubstitutionPolicy` | Unchanged — a long reset still prefers substitution inside `RunService`, before any park is written |

**Non-goals:** naked-vendor auto-resume; replacing serve; changing substitution
law; forcing a pre-`wakeAfter` lease claim (`force: true` is not used — it would
let a loop starve serve).

**Works Test:**

```text
scripts/swift-test.sh --filter LoopCoordinatorTests
scripts/swift-test.sh --filter VendorBackoffReconcilerTests
```

Named hermetic cases (all with an injected `RunService` seam, no real workers):

- `testParkedDevTurnDoesNotClassifyAsInfraBackoff` — parked run in, exactly one
  runId minted, zero 5s infra sleeps.
- `testParkedTurnMintsNoCompetingRunIds` — the ten-orphans regression, asserted
  by run count.
- `testParkedLoopStaysRunningWithCapacityPark` — status `.running`, owner marker
  still written, `capacityPark.wakeAfter` set.
- `testWakeClaimLostToServeAdoptsInsteadOfEscalating` — `claimVendorWake`
  returns `nil`, journal later settles, round continues.
- `testParkPastDeadlineStopsWithWakeInReason` — the one legal escalation.
- `testPMTurnParkYieldsToo` — the `dispatchTurn` twin.

**Proof waiver:** hermetics are required; one on-host loop dogfood across a real
vendor wall before archive.

---

### QABC-S02 — cut (folded into S01)

The acks, help text, and status strings were never separable from the state that
produces them. They ship in S01's visibility table.

### QABC-S03 — cut

A deterministic counsel string ("seat Grok, not Codex until …") is a second
opinion derived from data the caller now has in the same JSON envelope. It can
disagree with the rows it was derived from, it needs its own staleness rules,
and the calling LLM is strictly better at the judgment than a one-liner. Cutting
it also removes the byte-budget pressure that made it conditional in the first
place. Re-open only if dogfood shows planners reading `capacity.rows` and still
seating wrong.

---

## Non-goals

- Auto-resume of naked vendor CLI sessions with no alln journal.
- Probing / refreshing capacity on a `menu --json` read.
- Capacity inside `TeachingSnippet.body`.
- An Engine dependency in AllnighterCore.
- A new `LoopState.Status` case.
- Replacing or bypassing `VendorBackoffReconciler`.
- New dashboard / GUI capacity surface (CLI envelope + status only).
- Changing `VendorSubstitutionPolicy` law.
- `alln capacity --refresh` (that flag does not exist; refresh is the default).

---

## Lie-prone layers

- **`RunService.run` `.success` looking like "turn finished."** Parked runs are
  success-with-phase. Treating them as worker outcomes is the live bug.
- **`LoopTurnClassifier.infraBackoff` as capacity truth.** The classifier reads
  the worker outcome, which genuinely carries a `capacityObservation` — so it is
  confidently wrong. Phase + blocker is the park SSOT and must be read first.
- **Retry loops that mint ids.** Any retry path that calls `mintRunId` on a
  parked turn silently multiplies pending mutating work.
- **Status enums implying ownership.** In `LoopState`, non-`running` means
  unowned. A status that lies about that removes orphan reconcile.
- **A lease claim treated as a right.** `claimVendorWake` returning `nil` is
  normal concurrency, not an error.
- **Stale menu capacity.** Tier-1 hydrate can be aged; `observedAt` /
  `observedAgeSeconds` / `unknownReason` must stay visible.
- **A byte gate that tests a fixture, not the surface.** 32 KiB "held" while the
  real envelope was 35,037 B.
- **Product verb drift.** Docs/acks saying `pilot` / `relay` when the user-facing
  verb is `alln loop` — and code comments still saying `RelayCoordinator`.

---

## Relationship to other packets

| Packet | Relationship |
| --- | --- |
| [`Work_Recovery_And_PM_Continuity.md`](Work_Recovery_And_PM_Continuity.md) | Composes — WRC recovers after seat death; QABC prevents/survives capacity walls |
| [`Loop_Verb_Cutover.md`](../archive/phases/Loop_Verb_Cutover.md) | Status set **unchanged** (correction 8); product surface stays `alln loop` |
| [`Capacity_Hardening_Hotfix.md`](../archive/phases/Capacity_Hardening_Hotfix.md) | Prerequisite (archived, shipped) — QABC consumes the projection path unmodified |
| [`CLI_Park.md`](CLI_Park.md) | Orthogonal — parks a driver from probes; QABC parks runs on quota |

---

## Done when

- [ ] Menu byte gate covers a realistic catalog and the documented budget is one
      the live surface meets.
- [ ] `alln menu --json` and bootstrap carry `capacity` (injected, `refresh:
      false`, zero probes asserted); `contractVersion` bumped; `ContractSchema`
      extended; AllnighterCore still has no Engine dependency.
- [ ] Planner dogfood: seats from menu without a separate `alln capacity` call.
- [ ] `vendorPark` is checked before classify in **both** turn dispatchers; no
      competing runIds; no 50s infra escalate on a park.
- [ ] Claim-or-adopt proven against a lost claim; `alln serve` winning is not an
      escalation.
- [ ] Parked loop reports `.running` + `capacityPark{wakeAfter, source}` in
      `loop status`, ack, and notification.
- [ ] All six named hermetics green; one on-host wall-crossing dogfood.
- [ ] `AGENTS.md` routing rows updated (`RelayCoordinator` → `LoopCoordinator`).
- [ ] Deslop + code audit; promote the moat sentence and the plan-time capacity
      law; archive this packet.
