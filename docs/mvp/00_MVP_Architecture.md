> **Vocabulary (2026-06-15).** Current product language lives in
> `docs/workflows/Product_Vocabulary.md`. This doc uses team/model/worker/plan
> terms only.

# 00 — MVP Architecture (read first)

Status: **Locked for the MVP.** Every MVP phase obeys this doc.
Owner: Founder
Updated: 2026-06-14

> This fixes *how* the MVP is built so no phase re-decides the stack. It defines
> the language, repo layout, data model, the driver-manifest schema, the
> parallel fan-out contract, the synthesis contract, persistence, the safety
> posture, and — critically — the **Growth Seams** that let this MVP expand into
> post-MVP phases without a rewrite. Where this doc is silent, `docs/phases/`
> phase docs govern forward work.

---

## 1. Language and Platform

| Concern | Decision | Rationale |
| --- | --- | --- |
| Language | **Swift 6** (strict concurrency) | Same language as the full roadmap; the fan-out engine maps cleanly to `async/await` + `TaskGroup` + `actor`; no rewrite for iOS or the factory. |
| Mac UI | **SwiftUI** (`MenuBarExtra` + a window), AppKit only where needed | Native menu-bar app, fast, shared idioms with future iOS. |
| Mac floor | **macOS 14 Sonoma+** | Mature `MenuBarExtra`, `Observation`. |
| Async model | **Swift Concurrency** (`async/await`, `actor`, `AsyncStream`, `TaskGroup`) | Parallel fan-out + cancellation + timeouts are first-class. |
| State | **`@Observable`** in the app | Modern, low boilerplate. |

**Why not Python / a shell script?** Faster to hack, but it dead-ends: the
roadmap's iOS app, the embedded API server, and the worktree factory are all
Swift. A Python MVP would be thrown away. Swift makes the MVP the literal seed
of the product. (Founder explicitly removed the Python suggestion.)

The Mac app is **unsandboxed** (it must spawn local developer CLIs and inherit
their auth/PATH). It is notarized and distributed as a DMG outside the App
Store, matching the constitution.

---

## 2. Repository Layout (MVP)

Aligns with the constitution's layout; only the pieces the MVP needs exist now.

```text
/  (this repo — "Allnighter")
├── Packages/
│   └── AllnighterCore/              # SPM library: models, manifest schema, run state machine, fixtures
│       ├── Sources/AllnighterCore/
│       ├── Tests/AllnighterCoreTests/
│       └── Package.swift
├── Apps/
│   └── AllnighterMac/               # macOS menu-bar app + window (the MVP)
│       └── Drivers/                 # bundled default driver manifests (*.json)
├── Fixtures/                        # shared JSON fixtures (panels, runs, plans)
├── scripts/                         # check.sh, doctor
└── docs/mvp/                        # these docs (MVP execution truth)

# Added later (Growth Seams — do not build now):
# ├── Packages/AllnighterCore/       # + `allnighter` executable target (RB6: CLI / MCP / loopback server)
# ├── Apps/AllnighteriOS/            # iOS floor manager (post-MVP)
# ├── Services/AllnighterRelay/      # remote relay (much later)
# └── (Lane Manager, Preview/Artifact, Scheduler) inside AllnighterMac
```

> **RB6** adds an `allnighter` SPM executable product (Team-as-Tool: CLI + MCP
> stdio + loopback HTTP/WS), linking `AllnighterEngine`. It runs the team
> headlessly, shares `Config/` and `Runs/` with the Mac app, and needs no GUI
> running. See `docs/mvp/RB6_Team_As_Tool.md`.

- **Project generation: XcodeGen** (`project.yml` per app), so `.xcodeproj` is
  generated and diffable. `AllnighterCore` is **pure SPM** (`swift test` runs
  without Xcode).
- **Dependencies: keep them boring.** MVP needs almost none. `swift-log` for
  logging. Persistence starts file-based (§7); **GRDB** is the chosen upgrade
  path when history/query needs grow (same as the constitution) — Core models
  are `Codable`, so the move is mechanical.

---

## 3. System Architecture (MVP)

```text
                 +-------------------------------------+
                 |          Allnighter Mac             |
                 |  menu bar + window (SwiftUI)        |
                 +------------------+------------------+
                                    |
                 +------------------v------------------+
                 |  TeamRunCoordinator (actor)      |  owns one run's lifecycle
                 |  - builds member prompts            |
                 |  - fan-out via TaskGroup            |
                 |  - collects answers + status        |
                 |  - triggers synthesis               |
                 +------------------+------------------+
                                    |
        +-----------------+---------+---------+-----------------+
        |  WorkerRunner   |  WorkerRunner     |  WorkerRunner   |  (one per member, parallel)
        |  (subprocess)   |  (subprocess)     |  (manual paste) |
        +--------+--------+---------+---------+--------+--------+
                 |                  |                  |
        claude -p (Opus)   gemini/grok/codex     (user pastes)     ... etc.
                 |                  |                  |
        +--------v------------------v------------------v--------+
        |        AllnighterCore (pure types, no I/O)            |
        |  Model · DriverManifest · TeamRun · WorkerAnswer |
        |  · Synthesis · RunStatus · RunEvent envelope · fixtures |
        +-------------------------------------------------------+
```

Ownership rules (carried from the constitution, scoped to MVP):

- **`AllnighterCore` owns semantic models + the manifest schema + run state
  machine.** Pure types, no I/O, fully `swift test`-able.
- **The Mac app owns execution** (spawning CLIs, capturing output, persistence,
  UI). All run state lives on the Mac.
- **Workers are described by data (manifests), not hardcoded.** Adding/removing
  a model is editing a manifest, not changing code. This is the churn defense
  and the extensibility story.

---

## 4. Data Model (owned by AllnighterCore)

All `Codable`. JSON shapes are the fixtures (§8). Names are chosen to stay
forward-compatible with post-MVP phases (`Worker`, `Team`, `Driver`).

```text
Worker          : a configured model endpoint = { id, displayName, modelLabel, driverId, role, enabled }
DriverManifest  : how to invoke + read a CLI (see §5)
WorkerSpec   : a preset's worker request = { workerId, count=1, stance? }   (expands to Workers at run start; Phase 06)
Worker       : one independent team slot = { id, workerId, instanceIndex, stance?, label? }   (Phase 06)
TeamRun      : { id, prompt, status, origin, originAgent?, presetId?, team:[Worker], workerAnswers:[WorkerAnswer], stages:[StageOutput], createdAt }
WorkerPrompt    : the exact prompt sent to one worker = { workerId, workerId, text }   (text varies per worker once stance/context land — §10 seam)
WorkerAnswer  : { workerId, workerId, status, output, errorKind?, errorReason?, startedAt, finishedAt, durationMs, exitCode? }
                  Identifiable via `id { workerId }` (computed; not encoded). workerId is the stored identity; workerId is provenance.
PlanAnalysis   : structured plan writer truth = { consensus, contradictions, partialCoverage, uniqueInsights, blindSpots, failedWorkers, confidenceNote? }   (Phase 06)
StageOutput     : one post-team stage = { id, purpose, producedByWorkerId?, producedByWorkerId?, promptProfileId?, customInstruction?,
                  status, payload?, reuseKey?, errorReason?, startedAt, finishedAt }   (Phase 06)
StagePayload    : typed structured truth, one case per purpose (see §4.1)   (Phase 06)
RunOrigin       : how a run was started = gui | cli | mcp | http   (default gui; Phase 06)
RunEvent        : append-only event envelope (id, seq, ts, kind, payload) — see §6
```

Phase 05 makes the draft plan writer and synthesis instruction explicit in
presets (Opus 4.8 is the built-in default by configuration, not a hardcoded
semantic rule). **Phase 06 lays the correct final run model:** the team is a list
of `Worker`s (so one worker can fill several workers — *self-fusion*), the
plan writer's analysis is the structured `PlanAnalysis` (Markdown is derived),
and everything after the team is a `StageOutput` in `TeamRun.stages` (the
Phase 04/05 `Synthesis` struct is **removed**, replaced by `analysis` + `plan`
stage outputs). **Phase 05's `TeamRun.workersPresetId` is deleted and replaced by
`presetId`.** Since there are no users yet, Phase 06 corrects these shapes
directly — fixtures and call sites are rewritten and the dev `Runs/` folder is
wiped at the 06 cutover; **no compatibility shims, no alias, no decode-old-runs.**

A reduce stage (analysis, plan, review, final spec, return review) is produced by
a **worker invocation that is not a worker**, so `StageOutput` records
`producedByWorkerId`; `producedByWorkerId` is set only on the rare stage produced by
a worker. A stage uses a named profile (`promptProfileId`) **or** one-off
custom text (`customInstruction`) — exactly one is set, which is the honest record
of what ran (the Phase 05 `SynthesisInstructionChoice` honesty, generalized).

### 4.1 StagePayload (one typed case per stage purpose)

`StageOutput.payload` is a single discriminated union — every milestone adds a
**case**, never a parallel struct or loose optional fields. It encodes with a
`kind` discriminator equal to the stage `purpose`:

```text
StagePayload =
  | analysis(PlanAnalysis)                 // purpose: analysis        (06)
  | plan(markdown: String)                  // purpose: plan            (06)
  | review(ReviewResult)                    // purpose: review          (RB2)
  | finalSpec(FinalSpecPayload)             // purpose: final_spec      (RB3) markdown + structured decisions + flags
  | dispatch(ExecutionReturn)               // purpose: dispatch        (RB4/RB5)
  | returnReview(ReturnReviewPayload)       // purpose: return_review   (RB5)
  | outcomeScore(EvalScore)                 // purpose: outcome_score   (RB5)
```

Human Markdown views (`analysis.md`, `master_plan.md`, `review_*.md`,
`final_spec.md`, …) are **derived** from the payload by `RunMarkdown`; the payload
is the only truth. `StagePurpose` is a **closed enum** on purpose: a `switch` over
it is exhaustive, so adding a purpose is a deliberate, compiler-guided
cross-cutting change (do not add an `unknown` case — silent mishandling is worse
than a compile error). Keep purpose-specific logic centralized (a renderer/handler
keyed by purpose) so new cases touch few sites.

Enums:

```text
ModelRole   : member | plan writer | both
RunStatus    : draft -> fanning_out -> answers_in -> planning -> complete | partial
               (review presets) answers_in -> reviewing -> finalizing -> complete | partial
               any active -> cancelled (user stop) ; any -> failed (unrecoverable)
WorkerAnswerStatus : queued -> running -> done | failed | timed_out | cancelled | skipped
                                          (skipped = manual worker not yet pasted)
StagePurpose : analysis | plan          (RB extends: review | final_spec | dispatch | return_review | outcome_score)
StageStatus  : queued -> running -> done | failed | timed_out | skipped | reused
RunOrigin    : gui | cli | mcp | http          (default gui; how the run was started — Phase 06)
DriverKind   : headless_cli | manual_paste     (Growth: protocol, ide_handoff, local_model — see §10)
```

**`RunStatus` is the *review* lifecycle only.** `planning` spans **both** the
analysis and plan reduces (Phase 06): a run enters `planning` at analysis
start and leaves it when the plan stage settles. If analysis succeeds but the plan
reduce fails, the run is `partial` (the `PlanAnalysis` is still usable). **Dispatch
(RB4) and return review (RB5) are post-review `StageOutput`s on a `complete`
run** — they have their own `StageStatus`; they do **not** add `RunStatus` values.
This keeps the run state machine small and stable as later milestones land. Every
legal/illegal edge (incl. mid-review and mid-synthesis stops) gets an exhaustive
`canTransition` test.

Canonical examples (full shapes live in `Fixtures/`):

```json
// Model
{
  "id": "model_opus",
  "displayName": "Opus 4.8",
  "modelLabel": "claude-opus-4.8",
  "driverId": "claude_code",
  "role": "plan writer",
  "enabled": true
}
```

```json
// TeamRun (completed, Phase 06 shape)
{
  "id": "run_01J...",
  "prompt": "Should we add team accounts before billing analytics?",
  "status": "complete",
  "presetId": "preset_six_default",
  "workers": [
    { "id": "model_opus#0", "workerId": "model_opus", "instanceIndex": 0 },
    { "id": "model_grok#0", "workerId": "model_grok", "instanceIndex": 0 }
  ],
  "members": [
    { "workerId": "model_opus#0", "workerId": "model_opus", "status": "done", "output": "...", "durationMs": 21450, "exitCode": 0 },
    { "workerId": "model_grok#0", "workerId": "model_grok", "status": "timed_out", "errorReason": "no output for 120s" }
  ],
  "stages": [
    {
      "id": "stage_analysis", "purpose": "analysis", "producedByWorkerId": "model_opus#0",
      "promptProfileId": "default_master_plan_v1", "status": "done",
      "analysis": { "consensus": [], "contradictions": [], "blindSpots": [], "failedWorkers": [{ "workerId": "model_grok#0", "reason": "no output for 120s" }] }
    },
    {
      "id": "stage_plan", "purpose": "plan", "producedByWorkerId": "model_opus#0",
      "promptProfileId": "default_master_plan_v1", "status": "done",
      "markdown": "# Plan\n..."
    }
  ],
  "createdAt": "2026-06-14T20:01:00Z"
}
```

### Run state machine (single source of truth; tested in Phase 01)

```text
draft -> fanning_out -> answers_in -> planning -> complete
                                    -> (synthesis fails) -> partial
fanning_out/answers_in/planning -> cancelled        (user stop)
any -> failed                                          (unrecoverable)
```

`TeamRun.canTransition(to:)` is validated in Core with unit tests for every
legal and illegal edge. `partial` exists so one dead worker never blocks a
plan.

---

## 5. Driver Manifest Schema (the extensibility + churn-defense core)

A worker's CLI is described by a thin, versioned JSON manifest + a tiny Swift
adapter. MVP manifests should remain valid as post-MVP phases grow the worker
system.

```json
{
  "id": "claude_code",
  "manifestVersion": 1,
  "displayName": "Claude Code",
  "kind": "headless_cli",
  "detectCommand": "claude --version",
  "smokeTestCommand": "claude -p \"Reply with the single token ALLNIGHTER_READY\" --model {{model}}",
  "smokeTestExpect": "ALLNIGHTER_READY",
  "invoke": {
    "command": "claude",
    "args": ["-p", "{{prompt}}", "--model", "{{model}}"],
    "promptVia": "arg",                 // arg | stdin
    "env": {},                          // extra env; inherits the user's login shell env by default
    "workingDir": null,                 // MVP: null (no repo). Growth seam: lane worktree path.
    "timeoutSeconds": 240
  },
  "output": {
    "capture": "stdout",                // stdout | file
    "stripAnsi": true,
    "doneSignal": "exit_code",          // exit_code | sentinel | idle_timeout
    "sentinel": null
  }
}
```

Template tokens: `{{prompt}}`, `{{model}}` (from the `Worker.modelLabel`),
`{{workingDir}}`. Substitution is literal-safe: prompts are passed as a single
`argv` element (never shell-interpolated) or via stdin — **no shell string
concatenation**, so prompt content cannot inject commands.

**`manual_paste` kind** (no `invoke`): for any model whose CLI cannot yet be
driven headlessly (e.g. an IDE-bound Composer, or a tool behind an interactive
login). The app shows the prompt with a copy button and a paste box; the member
stays `skipped` until the user pastes the answer. This keeps the team
*complete* on day one and lets each CLI graduate to `headless_cli` later by
editing its manifest only.

**Bundled default manifests (best-effort, all editable in Settings):**

| Model | Likely driver | Notes |
| --- | --- | --- |
| Opus 4.8 | `claude_code` (`claude -p --model`) | PlanWriter by default. |
| Sonnet 4.6 | `claude_code` (`claude -p --model`) | Same CLI, different `modelLabel`. |
| ChatGPT 5.5 | `codex` / OpenAI CLI headless (`-p`-style) | Confirm flags during Phase 02; `manual_paste` fallback. |
| Gemini Flash | Antigravity / Gemini CLI headless prompt | Confirm flags; `manual_paste` fallback. |
| Grok Build | `grok` CLI headless (`--model "Grok Build"`) | Confirm flags; `manual_paste` fallback. |
| Composer 2.5 | **`grok` CLI, model = "Grok Composer 2.5 Fast"** | Composer 2.5 ships **inside Grok Build CLI** (free); same `grok` driver, different `modelLabel`. See <https://x.ai/news/grok-build-cli>. |

> Phase 02 verifies real invocation flags per CLI on the founder's machine. The
> manifest design means a wrong guess is a config edit, not a code change.
>
> **Composer 2.5 note:** Composer 2.5 is not reached via Cursor; it is bundled
> inside the **Grok Build CLI** (`grok`) and chosen via its `/model` picker
> ("Grok Composer 2.5 Fast"). So two workers — **Grok Build** and **Composer
> 2.5** — share one `grok` driver manifest and differ only by `modelLabel`,
> exactly like Opus/Sonnet share the `claude_code` driver. The grok headless
> invocation flag (e.g. `--model`) is verified in Phase 02; until then it falls
> back to `manual_paste`.

---

## 6. Event / Streaming Contract (MVP, forward-compatible)

The UI updates from an **append-only run-event stream**, not by mutating truth
directly. In the MVP this is an in-process `AsyncStream<RunEvent>`; the envelope
is shaped so the same events can later be served over WebSocket to iOS **without
changing the event shapes**.

```json
{ "id": "evt_...", "seq": 42, "ts": "2026-06-14T20:01:21Z",
  "kind": "member.status_changed",
  "payload": { "runId": "run_01J...", "workerId": "model_grok#0", "workerId": "model_grok", "from": "running", "to": "timed_out" } }
```

Member events key on **`workerId`** (Phase 06; `workerId` included for convenience),
so self-fusion workers never collide. Event kinds (extensible): `run.*`, `member.*`,
and the generic **`stage.*`** family (`stage.started`, `stage.output`,
`stage.completed`, `stage.failed`, `stage.reused`) carrying `stageId` + `purpose` —
RB adds no per-stage-kind event families. Clients dedupe by `id` and apply
idempotently (upsert) — so a future reconnecting iOS client never double-counts.

---

## 7. Persistence (MVP)

Start simple, stay migratable:

- Runs are persisted as a folder per run under
  `~/Library/Application Support/Allnighter/Runs/run_<id>/`:

```text
run_<id>/
  run.json                  # TeamRun (truth)
  member_<workerId>.md        # each worker's raw answer (workerId, so self-fusion workers don't collide)
  analysis.md               # derived view of the PlanAnalysis (Phase 06)
  master_plan.md            # the plan stage output (purpose: plan)
  bundle.md                 # export: prompt + all members + analysis + plan, one file
  # RB adds (derived from run.json stages): review_<lensId>.md, final_spec.md,
  # implementation_brief.md, execution_prompt_<workerId>.md, return_review.md
```

- Workers + manifests + presets live under
  `~/Library/Application Support/Allnighter/Config/`. Eval runs live under a
  **separate `Evals/`** tree (never `Runs/`), so history and `team_recall` (RB6)
  never surface them.
- **`run.json` is the only truth; every `.md` is derived.** All Markdown artifacts
  (`analysis.md`, `master_plan.md`, `review_*.md`, `final_spec.md`, `bundle.md`, …)
  are **regenerated from `run.json` on each stage completion** — idempotent and
  cheap. A file-watching UI should read `run.json`, not race the derived files;
  treat the `.md`s as exports.
- **Growth seam:** when history/search/observation needs exceed flat files,
  migrate the run index to **GRDB/SQLite** (constitution's choice). `run.json`
  stays the per-run artifact; Core models already `Codable`.

Nothing is ever uploaded. There is no network egress in the MVP except the CLIs'
own (which the user already authorized via their subscriptions).

---

## 8. Fixtures and Tests

`AllnighterCore` ships JSON fixtures so the app and tests build against the same
data:

```text
models_six.json            # the Founder's Six workers
run_inflight.json         # a run mid fan-out (some running, some done)
run_complete.json         # a finished run with plan
run_partial.json          # one worker timed out; plan still produced
manifest_claude.json      # a headless_cli manifest
manifest_manual.json      # a manual_paste manifest
```

Each fixture has a round-trip decode/encode test. The app renders runs from
fixtures before any real CLI is wired, so UI and engine progress in parallel.

---

## 9. Safety and Honesty Posture (MVP-scoped)

The big-product safety model is mostly about git/landing, which the MVP does not
do. The MVP's obligations:

- **No marginal cost / no keys.** The MVP never asks for or stores model API
  keys. It only invokes CLIs the user already authenticated. If a CLI needs
  login, Doctor surfaces it; the app does not capture credentials.
- **No shell injection.** Prompts are passed as single `argv` elements or via
  stdin, never concatenated into a shell command string.
- **Bounded subprocesses.** Every worker run has a timeout and is spawned in its
  own process group so it can be killed cleanly; a global **Stop** cancels the
  whole run and terminates all child process groups.
- **Honest status.** A worker that errored/timed out is shown as `failed`/
  `timed_out` with a reason — never silently dropped or faked. The run can still
  complete as `partial`.
- **Local only.** No upload, no relay in the MVP. (Relay is a far-future seam.)
- **Quota honesty (observed only).** Post-MVP capacity hints ("near limit", "reset
  soon") may appear only when sourced from **observed** provider responses — never
  as pre-run forecasts of cost, time, or token burn. See
  `docs/archive/phases/Estimate_Cleanup_And_Effort_Dial.md`.

Carried forward from the constitution but **not yet relevant** (because the MVP
writes no code and touches no repo): the worktree core invariant, protected
paths, risk tiers, landing/revert. They activate when execution lanes land
(§10).

---

## 10. Growth Seams (how the MVP becomes the full Allnighter — no rewrite)

This is the "don't build us into a box" contract. Each deferred roadmap
capability has a named attach point in the MVP design:

| Deferred capability | Attaches at | What changes (additive only) |
| --- | --- | --- |
| **Fusion-grade synthesis + evals** (`06`) | `TeamRun` model + `PlanWriter` + `RunStore` | The correct team foundation: `Worker` (self-fusion), structured `PlanAnalysis`, `StageOutput` sequence, two-stage analysis→plan, tiered presets, and an offline eval harness. **Built before RB** so RB never restructures the run model. |
| **Review Board + Final Spec** (`RB0`-`RB4`) | `StageOutput` (from `06`) + `TeamRunCoordinator` + prompt builders | After the plan stage, append optional advisory review `StageOutput`s, then a first-principles final-spec reduce. New `StagePurpose` cases only — reuse fanout/reduce; no generic DAG. |
| **Return review + scorecards + routing** (`RB5`) | `StageOutput` + `WorkerAnswer` outcomes + the `06` eval harness | After dispatch, capture the executor return, score it against the final spec, aggregate worker scorecards from local history, and recommend rerun/remix/pick. Closes the control loop; still no managed git. |
| **Team-as-Tool** (local CLI / MCP / HTTP) — **specced (`RB6`)** | `TeamService` over the existing engine + the `RunEvent` stream + a loopback server (same seam as iOS) | Expose the team→analysis→plan team as a tool any local terminal agent (Claude Code, Codex, Grok, Cursor) invokes mid-task — **local Fusion at zero marginal cost.** Recursion-guarded, governed, localhost-only, review-only (no git/execution). The strategic moat; needs only `06`. |
| **Generic Team critique** | RB stage primitives | If revived, it becomes a workflow preset over `WorkflowStage`, not a separate cross-critique engine. The post-draft review board supersedes generic model-vs-model critique for implementation specs. |
| **Managed execution lanes** | `DriverManifest.invoke.workingDir` (already nullable) + new execution owner model + `DriverKind.protocol` | A worker run gets a real isolated cwd; member output becomes built work instead of text. Isolation rules belong in the owning post-MVP phase doc. |
| **Direct executor dispatch** (`RB4`) | The plan / final spec + selected worker + configured working directory | Creates `implementation_brief.md` and `execution_prompt_<workerId>.md`, then invokes the selected healthy CLI. Allnighter does not create worktrees, branches, commits, landing, or revert rules. |
| **Managed "Implement This" / picker-as-prompt** | `ImplementationBrief` + execution substrate | A managed "send this to execution" action creates a task from the chosen plan; reuses the same work-order shape after execution safety exists. |
| **Races** | The fan-out engine | A race is a fan-out where members produce competing implementations or directions instead of text-only answers. RB5's multi-executor compare is the text-level precursor. |
| **iOS floor manager** | The `RunEvent` stream + a Hummingbird server in the Mac app | Wrap the existing in-process event stream in a WebSocket; iOS subscribes with `?since=<seq>`. Event shapes already match. |
| **Project/repo context** | `WorkerPrompt` | Prompt builder gains optional repo/file context; member prompt stops being identical-text-only. |
| **Utilization / admission control** | `WorkerRunner` dispatch | A scheduler/governor sits in front of `TaskGroup` spawn; adds concurrency caps and observed worker-availability logic. No cost/time estimates. |
| **Scorecards / routing** | `WorkerAnswer` (already has timing/outcome) | Aggregate response outcomes per worker over runs; drive routing. Implemented by `RB5`. |
| **Preference ledger / taste** | A new `PreferenceEvent` on "I liked plan X / picked dissent Y" | Logged from the master-plan view; structured for future market-outcome extension. |
| **Persistence at scale** | Run index | Flat files → GRDB; `run.json` stays the artifact. |

Rule: if a phase wants a shortcut that would *remove* one of these seams (e.g.
hardcoding the team, shell-concatenating prompts, mutating UI truth instead of
emitting events), stop and take the forward-compatible path.

---

## 11. Testing and Quality Gates (MVP)

- **`AllnighterCore`:** `swift test` — model round-trips, every run + member
  state transition (legal + illegal), manifest decode, fixture decode.
- **Mock driver:** a `MockDriver` (scripted stdout + exit code + delay) lets the
  fan-out engine and UI be tested without real CLIs.
- **Works Test per phase:** each phase doc states a concrete, runnable Works
  Test; the phase is not done until it passes.
- **Green wall** (`scripts/check.sh`): `swift test` + `xcodebuild test` for each
  app scheme that exists. Closeout names any missing proof.

---

## 12. Architecture Decision Log

| Date | Decision | Note |
| --- | --- | --- |
| 2026-06-14 | MVP scoped first to the Team slice (text review + configurable synthesis); full managed factory parked. | Cheapest, safest, proven-daily wedge; reuses constitution substrate. Direct executor dispatch is the next MVP layer without Allnighter-owned git rules. |
| 2026-06-14 | Swift 6 / SwiftUI for the MVP (Python rejected per founder). | Seed of the full product; no rewrite for iOS or factory. |
| 2026-06-14 | Workers described by editable driver manifests; `manual_paste` fallback for un-scriptable CLIs. | Churn defense + complete team on day one. |
| 2026-06-14 | In-process `RunEvent` stream with constitution-matching envelope. | iOS attaches later via WebSocket with no event-shape change. |
| 2026-06-14 | Post-MVP review board uses a fixed fanout/reduce stage chain, not a general workflow engine. | Phase 05 ships first; review feedback is advisory and final spec synthesis decides from first principles. |
| 2026-06-14 | OpenRouter's **Fusion** result is validation, not a pivot — Allnighter is the local, zero-marginal-cost version. No OpenRouter/API/keys; the fixed chain stays. | Fusion's lesson (structured plan writer analysis + self-fusion + budget-team quality) is captured locally in Phase 06. |
| 2026-06-14 | **Phase 06 lays the correct final team-run model before RB:** `Worker` (self-fusion), structured `PlanAnalysis`, `StageOutput` sequence; the `Synthesis` struct is removed. | Founder directive: build the right foundation now (no users → no migration). Fixtures + call sites rewritten; no compatibility shims. RB adds `StagePurpose` cases only. |
| 2026-06-14 | Synthesis is two stages (analysis → plan); `PlanAnalysis` is always structured truth. "combined vs separate" is a per-preset **call-count** choice, never a data-shape shortcut. | Daily speed comes from preset choice (fewer workers, fast plan writer), not from skipping the analysis. |
| 2026-06-14 | An offline **eval harness** (hidden weighted + negative rubrics) is the discipline gate for review changes; **RB5** closes the control loop (return review → scorecards → routing). | A synthesis/profile change ships as default only if it does not regress the corpus. |
| 2026-06-14 | **Team-as-Tool** (`RB6`): expose the team as a local tool (CLI / MCP / loopback HTTP) any terminal agent can call — local Fusion at zero marginal cost. Recursion-guarded, governed, review-only (no git/execution). Needs only `06`, so sequenceable early. | The moat. Founder confirmed it is in scope; the deferred "no git complexity" caveat refers to worktree/landing machinery, which RB6 explicitly excludes. |
| 2026-06-14 | **Hardening pass (post-review).** `StageOutput` carries a typed `StagePayload` union (one case per purpose) + `producedByWorkerId` (not worker-only); `StagePurpose` is a closed enum (exhaustive switches are a feature). | Two independent doc reviews; close contract gaps before code. Reduces are produced by workers, not workers. |
| 2026-06-14 | **`AllnighterEngine` imports no UI** (no SwiftUI/AppKit/`@Observable`); UI state lives only in the Mac app (`AppModel`). The `allnighter` RB6 binary links Engine and must build headlessly. | Enforced by a test/lint. Prevents the RB6 CLI from needing a display server. |
| 2026-06-14 | **HTTP recursion guard fails closed:** the loopback server requires a mandatory depth header; all Allnighter clients forward `ALLNIGHTER_TEAM_DEPTH`; the session token is scrubbed from worker subprocess env. Cross-process concurrency uses `flock(2)` (auto-released on death). | Env-var alone can't protect an already-running server. Fail-closed + governor backstop; residual adversarial self-recursion is bounded by the governor + quota and documented. |
| 2026-06-14 | **RB5 proof commands default to manual/reveal;** auto-execution is opt-in behind a user allowlist + per-command approval, timeout, in the execution dir, logged. Multi-executor compare is **sequential** by default; parallel only with distinct working dirs (never one shared CWD). | Running model-authored commands is high-risk; concurrent agents in one repo corrupt each other. |

> Append a row whenever a phase changes a locked decision. Do not change the
> stack silently inside a phase.
