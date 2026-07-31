# Quota-Aware Bench Continuity

Status: **OPEN — founder priority (2026-07-30)**
Owner: AllnighterCore (capacity projection) + AllnighterEngine (relay park-yield) +
AllnighterCLI (menu/bootstrap/delivery acks)
Created: 2026-07-30
Revised: 2026-07-30
Origin: Founder dogfood — `alln capacity` exists and cross-vendor substitution
works at runtime, but planners (Opus in session) never see the meter at plan time;
long `alln loop` dev turns hit 5h/session caps and die because relay treats vendor
park like a 5-second infra hiccup instead of sleeping until reset.

Related shipped substrate (reuse, do not re-build):
[`Capacity_Hardening_Hotfix.md`](Capacity_Hardening_Hotfix.md) (strip + hydrate),
archived `Rate_Limit_Continuity.md` (`VendorBackoffPolicy`, `VendorBackoffReconciler`,
`VendorSubstitutionPolicy`), [`Loop_Verb_Cutover.md`](Loop_Verb_Cutover.md),
[`Work_Recovery_And_PM_Continuity.md`](Work_Recovery_And_PM_Continuity.md) (composes;
does not replace).

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations as needed; code remains SSOT for fields; archive this packet.

---

## Founder intake (SSOT_Founder_Input_Workflow)

```text
Founder intent:
  Put capacity facts in the selection envelope so every plan is quota-aware for
  free — Codex at 0% until Aug 5 → seat Grok; Claude weekly 46% but Fable pool
  90% → route long turns away from Fable. When a loop or run still hits a wall,
  sleep until the vendor reset and continue — not escalate after ~50 seconds.

Product value:
  Cross-vendor arbitrage no single vendor can copy (each only sees its own meter).
  This is behavior, not a dashboard: the PM routes around limits before spending
  quota on the wrong seat, and unattended loops finish across session caps.

Trusted workflow slice:
  Opus reads `alln menu --json` → seats Grok for execution because Codex is
  exhausted → `alln loop start "…" --dev model_grok` runs for hours → dev hits
  Claude 5h on a later round → run parks with wakeAfter → `alln serve` (or loop
  waiter) resumes at reset → round continues without founder paste.

Current state (verified 2026-07-30):
  `alln capacity` + `CapacityDisplayAcquisition` + `CapacityBenchProjection`
  ship honest multi-pool rows (Claude session vs weekly vs Fable). Capacity is
  NOT in `MenuJSON`, `Bootstrap.JSON`, or `TeachingSnippet` (protocol-only).
  `RunService` parks single-worker runs on sourced account limits with
  `wakeAfter`; `VendorBackoffReconciler` in `ServeDaemon` resumes them.
  `RelayCoordinator.dispatchDevTurn` classifies capacity as `.infraBackoff`,
  sleeps 5s, mints a new runId, retries up to 10×, then escalates — bypassing
  vendor park/wake. Direct Claude Code sessions (never started via alln) have no
  journal and cannot auto-resume.

Truth owner:
  Plan-time snapshot: `MenuCatalog.project` + `CapacityDisplayAcquisition` +
  `CapacityBenchProjection` → compact `MenuJSON.capacity` (and bootstrap echo).
  Runtime park: `RunService` + `RunStore` (`waitingForVendor`, `blocker.wakeAfter`).
  Wake scheduler: `VendorBackoffReconciler` / `VendorBackoffWakePlanner`.
  Substitution on long reset: `VendorSubstitutionPolicy` (unchanged law).
  Loop yield: `RelayCoordinator` + `RelayState` + `RelayTurnClassifier` behavior.
  Delivery acks: `PilotCLI` / `RelayCLI` / `LoopCLI` status projections.

Blocking questions:
  None on product posture. v1 is two slices (plan envelope + relay yield).
  Optional counsel string and Mac strip echo are follow-ons within packet.
```

---

## Product promise

```text
The PM knows what you have left — and routes around it without being asked.
When a wall is still hit, Allnighter sleeps until the meter resets and continues
the work it owns — not after a minute of useless retries.
```

Two co-equal halves — ship both for the full vision:

| Half | Question | Primary surface | v1 slice |
| --- | --- | --- | --- |
| **Plan-time quota** | Which seat has headroom *before* dispatch? | `alln menu --json` + bootstrap | QABC-S00 |
| **Loop continuity** | What happens when a dev turn hits a session cap mid-loop? | `alln loop` + vendor park/wake | QABC-S01 |

Plan-time quota prevents most wrong seats. Loop continuity finishes long work
that still hits a limit.

**Scope honesty:** v1 does **not** auto-resume naked vendor sessions that never
touched alln. The moat requires starting work through `alln run` / `alln loop`
(and `alln serve` for unattended wake on standalone runs). Say that plainly in
help and delivery acks.

**Moat sentence (promote at closeout):** Anthropic can only see Anthropic's
meter. Cross-vendor arbitrage is impossible from inside any one vendor. Allnighter
sees the whole bench and acts on it at plan time and at the wall.

---

## Why this exists (dogfood shape)

Typical failure today:

1. Opus plans a loop, seats Claude Opus for PM and Codex for dev — never runs
   `alln capacity` because nothing in `menu --json` reminded it to.
2. Codex is at 0% until next weekly reset. First dev turn fails or substitutes
   late after quota is already spent on the wrong plan.
3. Or: dev runs on Claude for 4h, hits the 5h session cap. `RunService` parks
   with a real `wakeAfter`, but relay's dev-turn loop treats it as infra backoff,
   retries every 5s, escalates in under a minute. Founder returns to a dead loop
   and an orphaned parked run in the journal.

The infrastructure for (3)'s *happy path* already exists for `alln run` +
`alln serve`. The wiring gap is planner visibility and relay honor of vendor park.

---

## Architecture (reuse, don't reinvent)

```text
Plan time                          Run time                         Loop time
─────────                          ────────                         ─────────
menu --json                        RunService.run                   dispatchDevTurn
  └─ capacity{} (tier-1 hydrate)     └─ park on account limit          └─ SEE waitingForVendor
       no probes on menu read              wakeAfter from vendor               YIELD (not 5s thrash)
bootstrap --json                           │                              persist loop parked
  └─ same compact snapshot                 ▼                              │
VendorSubstitutionPolicy (plan hints)  VendorBackoffReconciler              ▼
  └─ optional counsel string           (alln serve)                    resume at wakeAfter
                                         resumeParkedRun                     │
                                             │                             ▼
                                             └──────────────────► round continues
```

**Do not** probe on every `menu --json` read — same law as bare `alln capacity`
(tier-1 disk + `CapacityHydration`; unknown never blocks). `--refresh` stays on
`alln capacity` only.

**Do not** stuff capacity into `TeachingSnippet.body` — live JSON is SSOT;
teaching stays protocol-only (MR-S05 / ONB-S01).

---

## Slice plan

### QABC-S00 — Capacity in the selection envelope

**Goal:** Every agent that reads `alln menu --json` before planning sees a
compact, honestly aged capacity snapshot.

**Changes:**

| Surface | Field / behavior |
| --- | --- |
| `MenuJSON` | Top-level `capacity: CapacityMenuSnapshot` — `generatedAt`, `rows[]` (source, effective remaining, short remaining when seat has one, reset hints, `observedAt`, `unknownReason`) |
| `alln menu show model:<id>` | Include capacity row(s) for that model's `driverId` / source |
| `Bootstrap.JSON` | Same compact snapshot (session boot once) |
| `MenuCatalog.project` | Call `CapacityDisplayAcquisition.windows(now:, refresh: false)` → `CapacityBenchProjection.rows` → trim to menu budget |
| Optional | One-line `capacityCounsel` string (e.g. "Codex exhausted until … — prefer Grok for execution") |

**Constraints:**

- Stay inside MenuJSON byte budget (`MenuSelectionGradeTests` 32 KiB gate). Six
  rows × compact fields should fit; if not, truncate to bench order + `truncated: true`.
- Unknown rows stay unknown — never block menu or seating.
- Contract bump + schema in `ContractSchema.swift`.

**Works Test:**

```text
swift test --filter MenuSelectionGradeTests
swift test --filter CapacityBenchProjectionTests
# Manual: alln menu --json | jq '.capacity.rows[] | {source, effectiveRemainingPercent, observedAt}'
# Assert Codex/Grok/Claude Fable facts visible without running alln capacity separately
```

**Proof waiver:** None — unit tests + one manual dogfood read.

---

### QABC-S01 — Relay yields to vendor park (loop continuity)

**Goal:** When a dev turn returns `waitingForVendor` with `blocker.wakeAfter`,
relay **yields** instead of infra-backoff thrash; loop status names the wake;
work resumes across session caps.

**Changes:**

| Component | Behavior |
| --- | --- |
| `RelayCoordinator.dispatchDevTurn` | If `run.phase == .waitingForVendor` && `blocker.resource == .vendorBackoff` → return `.capacityParked(run, wakeAfter)` instead of classifying as `.infraBackoff` |
| `RelayState` / `RelayJSON` | New status or sub-status for capacity-parked loop (e.g. `capacityParked` with `wakeAfter`, `parkedRunId`, `parkedSource`) — exact enum TBD in implementation; must not collide with `awaitingPM` / `escalated` |
| `VendorBackoffReconciler` | Unchanged for run resume; relay must not mint competing runIds while park is active |
| `LoopCLI` / `RelayCLI` status | Project `wakeAfter`, `autoResumeRequiresServe: true`, exact `loop wait` command |
| `loop wait` | Wake-aware sleep when `--wait-for parked` and blocker is vendorBackoff (sleep until `wakeAfter`, not fixed poll) |
| After wake | On dev run terminal success → existing round continuation (`awaitingPM` or next step) |
| `VendorSubstitutionPolicy` | Unchanged — explicit `--dev` pin parks same seat; auto origin may substitute on long reset before park |
| Session handoff | Expect `RunService` fresh-session handoff after 5h reset; relay retry prompt must carry repo state |

**Explicit non-goals in S01:**

- PM-seat capacity park mid-round (dev-only v1; PM park composes with WRC).
- Auto-resume direct Claude Code sessions with no alln journal.
- Replacing `alln serve` — unattended wake still requires serve for standalone
  `alln run`; loop foreground waiter is alternative when caller lives.

**Works Test:**

```text
swift test --filter RelayCoordinatorTests
swift test --filter VendorBackoffReconcilerTests
# Hermetic: dev turn returns parked run with wakeAfter in near future → relay
# status capacityParked, not escalated; after reconciler resume → round continues
```

**Proof waiver:** Hermetic relay + reconciler tests required; one on-host loop
dogfood with `--refresh` capacity + forced park (or stubbed observation) before
archive.

---

### QABC-S02 — Delivery acks and serve visibility (small, ships with S01)

**Goal:** Agents and founders see *when* auto-resume happens and what to do if
serve is not running.

**Changes:**

- Detached ack / `loop start --no-wait`: include `capacityAtDispatch` snapshot.
- Parked loop/run status: `wakeAfter`, `resumePolicy: serve|manual|foregroundWait`.
- Help topic + error explain: parked until X; start `alln serve` for unattended wake.

**Works Test:** extend `CompletionDeliveryWorksTests` / `PilotCLITests` for ack strings.

---

### QABC-S03 — Optional counsel string (defer if S00 byte-tight)

**Goal:** One human/agent-readable routing sentence derived from strip rows
("seat Grok, not Codex until …").

**Owner:** `CapacityStripRenderer` or small `CapacityCounsel` pure function.
**Non-goal:** LLM-generated prose; deterministic only.

---

## Impact estimate (founder-facing, not a KPI contract)

| Audience | Lift |
| --- | --- |
| Power user (daily loops, multi-vendor, capacity-bound) | **Large** — wrong-seat plans mostly eliminated; long loops can complete across session caps |
| `alln run` + `alln serve` user | **Moderate** — fewer parks; clearer wake copy (behavior mostly exists) |
| Casual user (rarely hits limits) | **Small** — polish |
| Naked vendor session | **None** until work is routed through alln |

Rough dev cost: **~1–2 focused sprints** (S00 small, S01 medium, S02 small).
Architecturally wiring, not a new subsystem.

---

## Relationship to other packets

| Packet | Relationship |
| --- | --- |
| [`Work_Recovery_And_PM_Continuity.md`](Work_Recovery_And_PM_Continuity.md) | Composes — WRC finds work after seat death; QABC prevents/thrives through capacity walls |
| [`Loop_Verb_Cutover.md`](Loop_Verb_Cutover.md) | QABC extends loop status/wait semantics; does not change loop grammar |
| [`Capacity_Hardening_Hotfix.md`](Capacity_Hardening_Hotfix.md) | Prerequisite shipped — QABC consumes its projection path |
| [`CLI_Park.md`](CLI_Park.md) | Orthogonal — parks a driver from probes; QABC parks *runs* on quota |

---

## Done when

- [ ] `alln menu --json` includes tier-1 capacity snapshot; bootstrap echoes it.
- [ ] Planner dogfood: Opus seats from menu without separate `alln capacity` call.
- [ ] Relay dev turn honors `waitingForVendor`; loop does not escalate after ~50s on session cap.
- [ ] Status/ack names `wakeAfter` and serve requirement.
- [ ] Tests green; deslop + code audit at closeout.
- [ ] Promote moat sentence + plan-time capacity law to `Product_Vocabulary.md` or
      help; archive this packet.

## Open questions

1. **Loop status enum:** new `capacityParked` vs overload `escalated` with typed
   `note` — prefer explicit status for notifications (URN) and `loop wait`.
2. **Menu byte budget:** if six full rows exceed 32 KiB, ship top-4 bench + counsel
   first; detail stays on `menu show model:*`.
3. **PM seat park:** defer to WRC + QABC-S04 or handle in S01 if trivial.
