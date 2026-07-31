# Quota-Aware Bench Continuity

Status: **OPEN — founder priority (2026-07-30)**
Owner: AllnighterCore (capacity projection) + AllnighterEngine (relay park-yield) +
AllnighterCLI (`alln loop` / menu / bootstrap delivery)
Created: 2026-07-30
Revised: 2026-07-30 (Grok doc review v2)
Origin: Founder dogfood — `alln capacity` + cross-vendor substitution exist at
runtime, but planners never see the meter at plan time; long `alln loop` dev
turns hit session caps and die because relay ignores a successful vendor park
and thrash-retries as infra backoff.

Related shipped substrate (reuse, do not re-build):
[`Capacity_Hardening_Hotfix.md`](Capacity_Hardening_Hotfix.md),
archived `Rate_Limit_Continuity.md` (`VendorBackoffPolicy`,
`VendorBackoffReconciler`, `VendorSubstitutionPolicy`),
[`Loop_Verb_Cutover.md`](../archive/phases/Loop_Verb_Cutover.md),
[`Work_Recovery_And_PM_Continuity.md`](Work_Recovery_And_PM_Continuity.md)
(composes; does not replace).

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations; code remains SSOT; archive this packet. Closeout must also amend
LVC's "five `RelayState.Status` values" law to include `capacityParked`.

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
  Opus reads `alln menu --json` → seats Grok because Codex is exhausted →
  `alln loop start "…" --dev model_grok` runs for hours → a later Claude 5h
  wall parks with wakeAfter → loop owner (or `alln serve` if owner dead)
  resumes at reset → round continues without founder paste.

Current state (verified 2026-07-30):
  `alln capacity` + `CapacityDisplayAcquisition` + `CapacityBenchProjection`
  ship honest multi-pool rows. Capacity is NOT in `MenuJSON`, `Bootstrap.JSON`,
  or `TeachingSnippet` (protocol-only).
  `RunService` parks single-worker runs on sourced account limits with
  `waitingForVendor` + `blocker.wakeAfter`; returns `.success(run)`.
  `VendorBackoffReconciler` in `ServeDaemon` resumes parked runs.
  Exact relay failure: `dispatchDevTurn` (and twin `dispatchTurn`) never
  inspects `run.phase` after `.success`. It classifies
  `run.answers.first?.result` only → capacity observation → `.infraBackoff`
  → sleep `infraBackoffGraceSeconds` (5) up to `maxInfraBackoffAttempts` (10)
  → `budgetExhausted` → escalate. Each retry mints a new runId, orphaning the
  parked journal row. Direct Claude Code sessions never started via alln have
  no journal and cannot auto-resume.

Truth owner:
  Plan-time: `MenuCatalog.project` + `CapacityDisplayAcquisition` +
  `CapacityBenchProjection` → compact `MenuJSON.capacity` (+ bootstrap echo).
  Runtime park: `RunService` + `RunStore` (`waitingForVendor`,
  `blocker.wakeAfter`).
  Wake scheduler: `VendorBackoffReconciler` / `VendorBackoffWakePlanner`
  (standalone runs + dead loop owners).
  Loop yield/resume: `RelayCoordinator` + `RelayState` (`capacityParked`).
  Product CLI: `alln loop` (`LoopCLI`); `PilotCLI`/`RelayCLI` remain code paths.
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

| Half | Question | Primary surface | v1 slice |
| --- | --- | --- | --- |
| **Plan-time quota** | Which seat has headroom before dispatch? | `alln menu --json` + bootstrap | QABC-S00 |
| **Loop continuity** | Dev turn hits a session cap mid-loop? | `alln loop` + vendor park/wake | QABC-S01 (+ S02) |

**Scope honesty:** v1 does **not** auto-resume naked vendor sessions that never
touched alln. Continuity requires `alln run` / `alln loop` ownership.

**Moat sentence (promote at closeout):** Anthropic can only see Anthropic's
meter. Cross-vendor arbitrage is impossible from inside any one vendor.
Allnighter sees the whole bench and acts on it at plan time and at the wall.

Rough cost: ~1–2 focused sprints of wiring (S00 small, S01 medium, S02 small) —
not a new subsystem.

---

## Why this exists

1. Planner seats from `menu --json` with no capacity → wrong seat (e.g. Codex at 0%).
2. Or: Claude 5h session cap → `RunService` parks with real `wakeAfter`, but relay
   ignores park phase, infra-thrashes ~50s, escalates; founder returns to a dead
   loop and orphaned parked run(s).

Happy path for standalone `alln run` + `alln serve` already exists. Gaps:
planner visibility + relay honor of vendor park.

---

## Architecture (reuse)

```text
Plan time                         Run time                      Loop time
─────────                         ────────                      ─────────
menu --json                       RunService.run                dispatchDevTurn
  └─ capacity{} (tier-1 hydrate)    └─ park + wakeAfter           └─ IF phase waitingForVendor
       no probes on menu read             │                            YIELD capacityParked
bootstrap --json                          ▼                            persist parkedRunId
  └─ same compact snapshot          VendorBackoffReconciler            │
                                      (serve / dead owner)             ▼
                                      resumeParkedRun            owner alive: sleep→resume
                                                                 round continues
```

**Laws:**

- Do not probe on `menu --json` (`refresh: false` only). `--refresh` stays on
  `alln capacity`.
- Do not stuff capacity into `TeachingSnippet.body` — live JSON is SSOT.
- Phase/blocker check **before** `RelayTurnClassifier`. Parked success is not
  infra backoff.
- While `capacityParked`, do not mint competing runIds.

---

## Locked decisions

1. New loop status: **`capacityParked`** (not overloaded `escalated`).
2. Dev-turn only in v1; PM `dispatchTurn` twin deferred.
3. Alive loop owner resumes via `resumeParkedRun`; serve covers standalone runs
   and dead owners. Project `resumePolicy`.
4. Menu oversize → truncate + `truncated: true`; counsel deferred to S03.
5. S02 ships with S01 (thin acks/help). S03 optional.
6. LVC five-status law amended at closeout for `capacityParked`.

---

## Slice plan

### QABC-S00 — Capacity in the selection envelope (mandatory)

**Goal:** Every agent that reads `alln menu --json` before planning sees a compact,
honestly aged capacity snapshot.

| Surface | Field / behavior |
| --- | --- |
| `MenuJSON` | Top-level `capacity` — `generatedAt`, `rows[]` (source, effective remaining, short remaining when present, reset hints, `observedAt`, `unknownReason`), optional `truncated` |
| `alln menu show model:<id>` | Capacity row(s) for that model's driver/source |
| `Bootstrap.JSON` | Same compact snapshot (boot once) |
| `MenuCatalog.project` | `CapacityDisplayAcquisition.windows(now:, refresh: false)` → `CapacityBenchProjection.rows` → trim to menu budget |

**Constraints:**

- MenuJSON ≤ 32 KiB (`MenuSelectionGradeTests`). Truncate to bench order +
  `truncated: true` if needed.
- Unknown never blocks menu or seating.
- **Gate:** bump `contractVersion`; extend `ContractSchema` MenuJSON schema.

**Works Test:**

```text
swift test --filter MenuSelectionGradeTests
swift test --filter CapacityBenchProjectionTests
# Manual: alln menu --json | jq '.capacity.rows[] | {source, effectiveRemainingPercent, observedAt}'
```

**Proof waiver:** None.

---

### QABC-S01 — Relay yields to vendor park (mandatory)

**Goal:** When a dev turn returns a parked run, relay yields `capacityParked`
instead of infra thrash; loop status names the wake; work resumes across
session caps.

| Component | Behavior |
| --- | --- |
| `RelayCoordinator.dispatchDevTurn` | After `.success(run)`: if `phase == .waitingForVendor` && `blocker.resource == .vendorBackoff` → return capacity-parked outcome with `wakeAfter` / `parkedRunId`. **Do not** classify via `RelayTurnClassifier`. **Do not** mint another runId. |
| `RelayState.Status` | Add `capacityParked` with `wakeAfter`, `parkedRunId`, `parkedSource`, `resumePolicy`. Must not collide with `awaitingPM` / `escalated`. |
| Alive loop owner | Sleep until `wakeAfter` (deadline-clamped) → `resumeParkedRun` → continue round on terminal success. |
| Dead owner / standalone run | `VendorBackoffReconciler` unchanged; loop may need `loop resume` / reattach after run completes. |
| `alln loop status` | Project wake + resumePolicy + exact next command. Wake-aware `--wait-for` on status (not `loop wait` — wait uses `PilotCLI.runWatch` with different flags). |
| `VendorSubstitutionPolicy` | Unchanged. |

**Explicit S01 non-goals:** PM-seat park; naked vendor auto-resume; replacing serve
for standalone runs.

**Works Test:**

```text
swift test --filter RelayCoordinatorTests/testDevTurnYieldsCapacityParkedNotInfraThrash
swift test --filter VendorBackoffReconcilerTests
# Hermetic scenario: RunService returns success with waitingForVendor + wakeAfter
# near future → loop status capacityParked (not escalated); no extra runIds minted;
# after resume → round continues
```

**Proof waiver:** Named hermetic required; one on-host loop dogfood before archive.

---

### QABC-S02 — Delivery acks + serve visibility (ships with S01)

**Goal:** Agents/founders see when auto-resume happens and what to do if the
owner/serve path is missing.

- Parked loop/run status + detached ack: `wakeAfter`, `resumePolicy`,
  `parkedRunId`.
- Help / error explain: parked until X; if owner dead, start `alln serve` (or
  `loop resume` after run wake).
- Extend delivery/status tests via `LoopCLI` surfaces (code may still live in
  `PilotCLI`/`RelayCLI`).

**Works Test:** extend existing completion/status Works Tests for ack strings.

---

### QABC-S03 — Optional counsel string (defer)

Deterministic one-liner from strip rows ("seat Grok, not Codex until …").
Owner: pure `CapacityCounsel` (or thin `CapacityStripRenderer` helper).
**Non-goal:** LLM prose. Ship only if S00 stays under byte budget.

---

## Non-goals

- Auto-resume of naked vendor CLI sessions with no alln journal.
- Probing / refreshing capacity on every `menu --json` read.
- Capacity inside `TeachingSnippet.body`.
- Replacing or bypassing `VendorBackoffReconciler` for standalone `alln run`.
- PM-seat capacity park mid-round (v1).
- New dashboard / GUI capacity surface (CLI envelope + status only).
- Changing `VendorSubstitutionPolicy` law.
- Inventing `loop wait --wait-for` flags that do not exist on the wait path.
- Mac strip echo / counsel as mandatory v1 (S03 only).

---

## Lie-prone layers

- **`RunService.run` `.success` looking like "turn finished."** Parked runs are
  success-with-phase; treating them as failed worker outcomes is the live bug.
- **`RelayTurnClassifier.infraBackoff` as capacity truth.** Classifier sees
  worker outcome text/facts, not journal park. Phase/blocker is the park SSOT.
- **Stale menu capacity.** Tier-1 hydrate can be aged; `observedAt` /
  `unknownReason` must stay visible — never imply a fresh probe.
- **`escalated` used as soft park.** Hides wake clock from URN / `loop status` /
  agents.
- **Serve implied always required.** Alive loop owners resume themselves;
  serve is for dead owners + standalone runs.
- **Product verb drift.** Docs/acks saying `pilot`/`relay` when the user-facing
  verb is `alln loop`.

---

## Relationship to other packets

| Packet | Relationship |
| --- | --- |
| [`Work_Recovery_And_PM_Continuity.md`](Work_Recovery_And_PM_Continuity.md) | Composes — WRC recovers after seat death; QABC prevents/survives capacity walls |
| [`Loop_Verb_Cutover.md`](Loop_Verb_Cutover.md) | Extends status set with `capacityParked`; product surface stays `alln loop` |
| [`Capacity_Hardening_Hotfix.md`](Capacity_Hardening_Hotfix.md) | Prerequisite — QABC consumes projection path |
| [`CLI_Park.md`](CLI_Park.md) | Orthogonal — parks a driver from probes; QABC parks runs on quota |

---

## Done when

- [ ] `alln menu --json` includes tier-1 capacity; bootstrap echoes it; contract
      version bumped; MenuJSON ≤ 32 KiB.
- [ ] Planner dogfood: seats from menu without a separate `alln capacity` call.
- [ ] `dispatchDevTurn` honors `waitingForVendor` before classify; loop status
      `capacityParked`; no infra escalate after ~50s; no competing runIds while parked.
- [ ] Status/ack names `wakeAfter` + `resumePolicy` (S02 with S01).
- [ ] Hermetic `testDevTurnYieldsCapacityParkedNotInfraThrash` green; deslop +
      code audit at closeout.
- [ ] Promote moat sentence + plan-time capacity law; amend LVC status inventory;
      archive this packet.
