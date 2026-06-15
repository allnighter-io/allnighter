# Estimate Cleanup and Effort Dial

Status: **Complete** (2026-06-15). Archived to `docs/archive/phases/`.
Owner: Founder correction → Shared Core + Mac + CLI/MCP
Updated: 2026-06-15
Supersedes (estimate requirements): RB0, RB1, 06, RB6, Design0, 00 §9 — see § Supersedes.

## Founder Correction

> **Allnighter is a floor manager, not a billing dashboard.**

Allnighter must not estimate cost, quota burn, runtime, difficulty, or complexity
for a work order **before** it runs. That is not how the founder uses Claude,
Codex, GPT, or any agent. The question before dispatch is never "how expensive /
how long?" It is:

```text
What level of effort do I want the bench to apply right now?
```

**Effort is a user instruction. Cost/time is a guess. Keep the instruction; delete
the guess.** This phase deletes the guess — the estimator, the predicted seconds,
the quota-risk buckets, the "est. N calls" chrome, and the specs that ordered them.

One-sentence test for every line of code or copy this phase touches:

```text
Does this imply we know the future? → delete it.
```

## The Distinction That Drives Every Decision

The draft treated `CallPlan` as uniformly bad. It is not. Some pre-run facts are
**choices the user made**; only the **predictions layered on top** are fiction.
Deleting the wrong half either guts useful transparency or recreates the lie under
a new name.

| Structural truth — KEEP (it's what you chose) | Predictive fiction — DELETE (it pretends to know the future) |
| --- | --- |
| Seats selected (e.g. 6), per-worker multiplicity | Wall-clock duration / ETA |
| Combined vs separate analysis+plan | Token / credit consumption |
| Which workers, which judge | Quota-risk bucket (low/medium/high) |
| Which review lenses are enabled | "cheap / expensive / slow / worth the extra calls" |
| Design output count (e.g. 4 mockups) | Median latency mined from run history |
| Requested reasoning level (where a worker supports it) | A "calls" number presented as an estimate |

The work order the user configured **is** the preview. It needs no estimator.

## Product Law (this phase, binding)

**Banned anywhere in product code, UI, CLI/MCP, tool I/O, and live docs:**

- Pre-run cost, time, token, credit, or quota estimates.
- Quota-risk buckets or "low/medium/high cost" language.
- ETA, "est.", "~N calls", "worth the extra calls".
- Any tool behavior that **branches on a predicted** duration or call count.
- Scheduler/admission routing from guessed complexity (that's the other phase).

**Allowed:**

- **Before dispatch:** the exact selected work shape — workers × seats, judge,
  stage shape, review lenses, output count. Live; mutates as the user toggles.
- **During a run:** observed elapsed time, live per-worker status.
- **After a run:** observed facts — `invocations` actually made, per-member
  durations, outcomes, failures, rate-limit/auth signals.
- **Capacity state from real signals:** available, cooling down, auth required,
  degraded, unknown (see `Utilization_Admission_Control.md`).

## Root Cause (so it does not come back)

This code was **specified into existence**, not invented by a rogue agent. RB0's
"Cost is never silent → the composer must show the CallPlan (count + rough
quota/latency estimate) before commit" was a real instinct (don't let a heavy
preset surprise-burn a dozen calls) solved with the wrong mechanism: a labeled
**prediction**. RB1 made `estimatedCalls/estimatedSeconds/estimateNote` first-class
fields; 06 made tiered presets "surface est. wall time + quota risk"; RB6 made
`council_ask` branch sync/async on an estimate; Design0 said "the CallPlan shows
the generation count before you commit." An agent implemented all of it faithfully:
`CallPlan` + `CallPlanEstimator` (history-median latency, parallel/serial time
math, quota buckets), the composer caption, CLI/MCP listings, a `cost_latency_quota`
lens, and tests. The specs treated a **labeled estimate as honesty**; the real user
model is **"how hard should they try?"** The fix is not better estimates — it is
**delete the estimate layer** and let the chosen shape be the preview.

## Replacement: render the shape, do not model a new one

**Do not add a `WorkOrderShape` type.** That is rename theater. The work-order
shape is **already modeled** by `PanelPreset` (seats + `SynthesisConfig` + judge)
and `WorkflowPreset` (+ stages + lenses). The selection state
(`currentSeats`, `currentSynthesis`, active lens ids, design output count) **is** the
work order. The only thing missing is an honest way to **render** it.

Add one pure, prediction-free renderer in `AllnighterCore`:

```text
WorkOrder.summary(seats, synthesis, lensIds, outputCount?) -> String
  e.g. "6 seats · Opus judge · separate analysis + plan · 3 lenses"
       "Design Board · 4 mockups · Grok, Gemini, ChatGPT"
```

- It returns **structural facts only**: counts and names. No seconds, no quota, no
  calls-as-estimate, no "est.".
- The Mac composer, CLI `presets`, and MCP `council_presets` all call it — one
  source of truth, no per-surface drift.
- If a value type reads cleaner than a string for CLI `--json`, a tiny
  `WorkOrderSummary { seatCount, judgeWorkerId?, stageShape, lensCount, outputCount? }`
  is allowed — but it must contain **no** time/quota/calls fields and **never** the
  word `estimate`.

## Effort Dial = presets + direct shape controls

There is no abstract "effort" enum to build. Effort is expressed by the **shape the
user selects**, exactly like choosing "generate 4 variations" in a design tool. The
controls, in priority order:

1. **Preset picker is the effort dial.** `Fast` / `Quality` / `Deep` / `Custom`
   load common shapes in one tap. (Today these are the tiered `PanelPreset`s — keep
   them; this is the dial.)
2. **Direct, countable knobs** the vibe coder understands:
   - panel seats / per-worker multiplicity (the fan-out count),
   - analysis depth: combined (faster) vs separate (deeper),
   - review board: none / light (3 lenses) / full,
   - **design output count** ("# of mockups": 2 / 4 / 6).
3. **Custom** = edit the seats/stages/lenses directly (progressive disclosure).

Rules:

- **One control surface, not two.** The preset *is* the effort selection; Custom
  opens the shape editor. Do **not** add a parallel `effort: low|medium|high` field
  next to `presetId`.
- An optional **display-only** `effortTag` (Quick/Standard/Deep) on a preset is
  allowed purely as a label. It must **never** drive prediction, admission, or
  routing. If it tempts anyone toward a forecast, drop it.
- **No cost framing on any control.** "Quick" means *shallower bench*, never
  *cheaper*. "Deep" means *more judgment surface*, never *expensive/slow*.

### Out of this slice (named, not built)

- **`requestedReasoning`.** No worker/driver manifest exposes a reasoning level
  today; adding the field now is dead code — the exact sin we are removing. When a
  manifest gains a reasoning flag, add it then, mapped to that real field. Not now.

## Rip-Out Map (delete — do not deprecate)

Zero users, no migration: **delete**, never alias or shim. Verified against the repo
on 2026-06-15.

### Delete entirely

| Target | Why |
| --- | --- |
| `Packages/AllnighterCore/Sources/AllnighterEngine/CallPlan.swift` (whole file: `CallPlan` + `CallPlanEstimator`) | The estimator + `estimatedCalls/estimatedSeconds/estimateNote/quotaRisk` + history-median time math. Pure prediction. |
| `AppModel.callPlan` + `AppModel.latencyByWorker()` (`Apps/AllnighterMac/Sources/AppModel.swift`) | `latencyByWorker` mines history only to feed the estimator. |
| `cost_latency_quota` lens (`BuiltInLenses.swift`) + its use in `AppModel.fullReviewLenses` | The lens whose charter was "challenge quota burn" while the previewer manufactured the numbers. Replace with `scope_discipline`. |
| Estimate tests: `testCallPlanCountsSeatsPlusSynthesis` (`AppModelTests.swift`), `testCallPlanEstimatesPanelPlusSynthesis` (`PresetAndDoctorTests.swift`), `testPresetSummariesIncludeCallPlan` + the `estimateNote.contains(...)` assertion (`CouncilServiceTests.swift`) | Assert fake numbers. Replace with shape assertions. |

### Rewrite (strip estimate, keep observed truth)

| Target | Change |
| --- | --- |
| Composer caption (`RootView.swift` ~L115) | Replace `est. N calls (quotaRisk)` with `WorkOrder.summary(...)` — seats · judge · stage shape. |
| `DesignBoardView.callPlanText` (~L80) | Drop `· uses your provider quota`; show `N mockups · <engines>` only. |
| `CouncilService.presetSummaries()` | Return `(id, name, shape: String)` via `WorkOrder.summary`, not `CallPlan`. |
| `CouncilService` result build (`estimateNote: "...calls are best-effort counts."`) | Delete that note. `callsSpent` (observed) → rename `invocations`. |
| `CouncilTool.CouncilToolResult` | `estimateNote` → `note` (it carries refusal/status reasons, not estimates); `callsSpent` → `invocations`. Delete the "`callsSpent` makes cost honest every time" comment. |
| `CouncilRequest.waitSeconds` | Keep as a **pure client timeout**: `council_ask` blocks up to `waitSeconds`, then returns the `runId` to poll — **no** estimate-vs-budget branch, **no** `estimatedSeconds` returned. Update the comment. |
| CLI (`AllnighterCLI.swift`) | `presets` plain + `--json`: emit shape (`id`, `name`, `shape`), not `estimatedCalls`/`quotaRisk`. Fix the `presets` help text ("list presets + CallPlan"). Run output uses `invocations`. |
| MCP (`MCPServer.swift`) | `council_presets` lists `id: name (shape)`; remove `~N calls (quotaRisk)`. Result text uses `invocations`, not `estimateNote`. |
| `DefaultConfig.preset_budget` "Budget / Diverse" | Rename to shape-honest **"Diverse Panel"** (it excludes the judge from panel seats for diversity). Scrub the "Budget" comment. Audit all preset names for cost words. |

## Supersedes (rewrite these live docs, or estimates return via spec)

These authoritative docs **ordered** the deleted behavior. Rewriting them is **in
scope** — leaving them makes the next agent rebuild the estimator. When this phase
closes, their pre-run-estimate requirements are void; "no surprise burn" means the
user sees exactly the shape they configured, never a forecast.

- `docs/mvp/RB0_Judgment_Workflow_Overview.md` — "Cost is never silent" + "composer
  must show the CallPlan (count + rough quota/latency estimate) before the run
  commits" → show work shape; no forecast.
- `docs/mvp/RB1_Workflow_Presets_And_Stage_Primitives.md` — remove `CallPlan` with
  `estimatedCalls/estimatedSeconds/estimateNote` as first-class fields.
- `docs/mvp/06_Fusion_Grade_Synthesis_And_Evals.md` — presets "surface est. wall
  time + quota risk" → shape only; fix the "Budget / cheap seats / low quota burn"
  table row and preset name.
- `docs/mvp/RB6_Council_As_Tool.md` — remove `council_presets` estimate exposure and
  the `council_ask` estimate-vs-`waitSeconds` sync; replace with pure client-timeout
  polling.
- `docs/mvp/Design0_Design_Council_Overview.md` — "Cost is never silent — including
  quota" + "the CallPlan shows the generation count before you commit" → show the
  requested **output count** (honest); drop quota-risk framing.
- `docs/mvp/Design1_Image_Council.md`, `RB2`, `RB3` — scrub incidental
  "CallPlan shows / quota" references.
- `docs/mvp/00_MVP_Architecture.md` §9 — narrow "quota honesty" to **observed**
  signals only ("near limit / reset soon" from real responses), never pre-run
  forecasts.

Ignore (frozen, non-authoritative): `docs/archive/`, `docs/strategy/` history, and
`docs/design-system/uploads/` snapshots. The grep proof targets live SSOT only.

## Same law applies to the design lane

The design council is honest about its **count** ("4 mockups requested"), not its
**consumption**. Show `N mockups · <engines>`. Do not add "uses your provider
quota", "quota risk", or "est. generations" — counting requested outputs is allowed;
predicting consumption is not.

## Do Not Build (guardrail for the next agent)

- Do not build `CallPlanEstimator`, latency medians for preview, quota-risk buckets,
  or ETA logic — not even "labeled estimates."
- Do not add CLI/MCP fields that smell like billing (`quotaRisk`, `estimatedCalls`).
- Do not implement RB6 features that depend on a predicted duration.
- SwiftUI/CLI/MCP render shape from Core types; Core types do **not** compute
  forecasts. (Add this line to `WORKING_RULES.md` as a permanent guard.)

## Phase Contract

- **Trusted workflow slice:** composer preset/effort selection → live work-shape
  summary → commit → live status with elapsed time → post-run observed facts.
- **Truth owner:** `AllnighterCore` owns shape rendering (`WorkOrder.summary`);
  Mac/CLI/MCP are views.
- **Lie-prone layers:** SwiftUI composer copy, CLI/MCP preset output, MCP tool
  descriptions, the RB/Design/06 docs that still mandate CallPlan estimates.
- **Non-goals:** admission control / capacity probes / queue scheduling (see
  `Utilization_Admission_Control.md` — this cleanup simply deletes the predicted
  fields it would otherwise be tempted to use); provider quota accounting; token
  counting; `requestedReasoning`.
- **Open questions (resolved here, recorded for the implementer):**
  - Show a pre-run "calls" number at all? **No** — the GUI shows shape, not a count.
    Observed `invocations` appears only post-run.
  - New `WorkOrderShape` type? **No** — render from existing presets/selection.
  - `requestedReasoning` in scope? **No** — deferred until a manifest supports it.

## Works Test

**Setup:** launch the Mac app with built-in presets; have the CLI + MCP available.

**Gesture:** open the composer, switch presets / toggle seats + analysis depth;
list presets in CLI (`allnighter presets` + `--json`) and MCP (`council_presets`);
run a short council; open a design board.

**Assert (positive):**

- Composer shows `{N} seats · {judge} · {stage shape}` (and `{N} mockups · {engines}`
  for design), updating live as the shape changes.
- CLI/MCP preset listings show **shape** strings only.
- A running worker shows live elapsed time; a completed run reports observed
  `invocations` + per-member duration.

**Assert (negative):**

- No "est.", "~N calls", "quota risk", ETA, or cost language anywhere in composer,
  CLI, MCP, or tool output.
- No built-in preset display name contains "Budget", "cheap", or quota wording.
- `cost_latency_quota` is absent; `scope_discipline` is present and its prompt
  challenges work-shape bloat, not cost/time.
- `council_ask` with a small `waitSeconds` returns a `runId` to poll — it does **not**
  return a predicted duration and does **not** decide sync/async from an estimate.

**Static proof (must return zero hits in live paths):**

```text
rg "CallPlan|CallPlanEstimator|estimatedCalls|estimatedSeconds|estimateNote|quotaRisk|latencyByWorker|cost_latency_quota|est\\. .*calls|quota risk|~[0-9]+ calls|uses your provider quota|worth the extra calls" \
  Apps Packages docs/mvp docs/phases docs/gui
```

Allowed sole exceptions: this file (`docs/archive/phases/Estimate_Cleanup_And_Effort_Dial.md`) and
`docs/archive/`. **No migration carve-out, no deprecated aliases, no "removed in v2"
comments.** Zero users — the only acceptable result is gone.

### New lens (replaces `cost_latency_quota`)

```text
scope_discipline · "Scope discipline"
Challenge unnecessary stages, duplicated review, vague work orders, and runaway
workflow shape. Do not estimate provider cost, quota, or runtime.
```

## Done When

- The product asks for **effort (shape)**, never an estimate.
- The user sees the **exact work order** they chose, not fake accounting.
- `CallPlan`/`CallPlanEstimator` and every predicted field are **deleted** (not
  renamed); `invocations`/elapsed remain as observed facts.
- `cost_latency_quota` is gone; presets carry no cost-framed names.
- RB0/RB1/06/RB6/Design0/00 §9 no longer require pre-run estimates.
- The static proof returns zero hits in live paths.
- `swift test` + Mac app build green.
