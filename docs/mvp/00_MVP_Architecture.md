# 00 — MVP Architecture (read first)

Status: **Locked for the MVP.** Every MVP phase obeys this doc.
Owner: Founder
Updated: 2026-06-14

> This fixes *how* the MVP is built so no phase re-decides the stack. It defines
> the language, repo layout, data model, the driver-manifest schema, the
> parallel fan-out contract, the synthesis contract, persistence, the safety
> posture, and — critically — the **Growth Seams** that let this MVP expand into
> the full Allnighter without a rewrite. It is a deliberate **subset** of
> `docs/phases/ON HOLD/00_Architecture_And_Tech_Stack.md` (the full
> constitution); where this doc is silent, the constitution governs.

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
├── Fixtures/                        # shared JSON fixtures (panels, runs, master plans)
├── scripts/                         # check.sh, doctor
└── docs/mvp/                        # these docs (MVP execution truth)

# Added later (Growth Seams — do not build now):
# ├── Apps/AllnighteriOS/            # iOS floor manager (post-MVP)
# ├── Services/AllnighterRelay/      # remote relay (much later)
# └── (Lane Manager, Preview/Artifact, Scheduler) inside AllnighterMac
```

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
                 |  CouncilRunCoordinator (actor)      |  owns one run's lifecycle
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
        |  Worker · DriverManifest · CouncilRun · MemberResponse |
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

All `Codable`. JSON shapes are the fixtures (§8). Names are chosen to be
forward-compatible with `ON HOLD/00` (`Worker`, `Council`, `Driver`).

```text
Worker          : a configured model endpoint = { id, displayName, modelLabel, driverId, role, enabled }
DriverManifest  : how to invoke + read a CLI (see §5)
CouncilRun      : one prompt fanned out + synthesized
MemberPrompt    : the exact prompt sent to one worker (MVP: identical text for all)
MemberResponse  : { workerId, status, output, errorReason?, startedAt, finishedAt, durationMs, exitCode? }
Synthesis       : { synthesizerWorkerId, instructions, masterPlanMarkdown, status, startedAt, finishedAt }
RunEvent        : append-only event envelope (id, seq, ts, kind, payload) — see §6
```

Phase 05 makes the draft synthesizer and synthesis instruction explicit in
presets. Opus 4.8 remains the built-in default, not a hardcoded semantic rule.

Enums:

```text
WorkerRole   : member | synthesizer        (a worker may be both)
RunStatus    : draft -> fanning_out -> answers_in -> synthesizing -> complete
               terminal failure: failed | cancelled | partial   (partial = some members failed but run usable)
MemberStatus : queued -> running -> done | failed | timed_out | cancelled | skipped
                                          (skipped = manual worker not yet pasted)
DriverKind   : headless_cli | manual_paste     (Growth: protocol, ide_handoff, local_model — see §10)
```

Canonical examples (full shapes live in `Fixtures/`):

```json
// Worker
{
  "id": "worker_opus",
  "displayName": "Opus 4.8",
  "modelLabel": "claude-opus-4.8",
  "driverId": "claude_code",
  "role": "synthesizer",
  "enabled": true
}
```

```json
// CouncilRun (completed)
{
  "id": "run_01J...",
  "prompt": "Should we add team accounts before billing analytics?",
  "status": "complete",
  "panel": ["worker_chatgpt","worker_opus","worker_sonnet","worker_composer","worker_gemini","worker_grok"],
  "members": [
    { "workerId": "worker_opus", "status": "done", "output": "...", "durationMs": 21450, "exitCode": 0 },
    { "workerId": "worker_grok", "status": "timed_out", "errorReason": "no output for 120s" }
  ],
  "synthesis": {
    "synthesizerWorkerId": "worker_opus",
    "instructions": "default_master_plan_v1",
    "masterPlanMarkdown": "# Master Plan\n...",
    "status": "complete"
  },
  "createdAt": "2026-06-14T20:01:00Z"
}
```

### Run state machine (single source of truth; tested in Phase 01)

```text
draft -> fanning_out -> answers_in -> synthesizing -> complete
                                    -> (synthesis fails) -> partial
fanning_out/answers_in/synthesizing -> cancelled        (user stop)
any -> failed                                          (unrecoverable)
```

`CouncilRun.canTransition(to:)` is validated in Core with unit tests for every
legal and illegal edge. `partial` exists so one dead worker never blocks a
master plan.

---

## 5. Driver Manifest Schema (the extensibility + churn-defense core)

A worker's CLI is described by a thin, versioned JSON manifest + a tiny Swift
adapter. This is a scoped subset of the constitution's manifest (`ON HOLD/00`
§9.8), so MVP manifests stay valid as the factory grows.

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
stays `skipped` until the user pastes the answer. This keeps the panel
*complete* on day one and lets each CLI graduate to `headless_cli` later by
editing its manifest only.

**Bundled default manifests (best-effort, all editable in Settings):**

| Worker | Likely driver | Notes |
| --- | --- | --- |
| Opus 4.8 | `claude_code` (`claude -p --model`) | Synthesizer by default. |
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
matches the constitution (`ON HOLD/00` §5) so the same events can later be
served over WebSocket to iOS **without changing the event shapes**.

```json
{ "id": "evt_...", "seq": 42, "ts": "2026-06-14T20:01:21Z",
  "kind": "member.status_changed",
  "payload": { "runId": "run_01J...", "workerId": "worker_grok", "from": "running", "to": "timed_out" } }
```

Event kinds (extensible): `run.*`, `member.*`, `synthesis.*`. Clients dedupe by
`id` and apply idempotently (upsert) — so a future reconnecting iOS client never
double-counts. Post-MVP workflow stages add generic `stage.*` events instead of
one-off `review.*` / `finalize.*` event families.

---

## 7. Persistence (MVP)

Start simple, stay migratable:

- Runs are persisted as a folder per run under
  `~/Library/Application Support/Allnighter/Runs/run_<id>/`:

```text
run_<id>/
  run.json                  # CouncilRun (truth)
  member_<workerId>.md      # each member's raw answer
  master_plan.md            # the synthesized plan
  bundle.md                 # export: prompt + all members + master plan, one file
```

- Workers + manifests + presets live under
  `~/Library/Application Support/Allnighter/Config/`.
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
panel_six.json            # the founder's six workers
run_inflight.json         # a run mid fan-out (some running, some done)
run_complete.json         # a finished run with master plan
run_partial.json          # one worker timed out; master plan still produced
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
- **Quota honesty.** Any "near limit / reset soon" hints (post-MVP) are labeled
  estimates, never stated as exact.

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
| **Review Board + Final Spec** (`RB0`-`RB3`) | `CouncilRunCoordinator` + `RunStore` + prompt builders | After `master_plan.md`, run optional advisory review fanout, then a first-principles final reduce stage. Reuse fanout/reduce primitives; do not build a generic DAG. |
| **Generic Council critique** (`ON HOLD/13`) | RB stage primitives | If revived, it becomes a workflow preset over `WorkflowStage`, not a separate cross-critique engine. The post-draft review board supersedes generic model-vs-model critique for implementation specs. |
| **Execution lanes** (worktree factory, `ON HOLD/03–05`) | `DriverManifest.invoke.workingDir` (already nullable) + new `Lane` model + `DriverKind.protocol` | A worker run gets a real worktree cwd; member output becomes a built branch instead of text. Core invariant (no writes to active repo) turns on here. |
| **Direct executor dispatch** (`RB4`) | The master plan / final spec + selected worker + configured working directory | Creates `implementation_brief.md` and `execution_prompt_<workerId>.md`, then invokes the selected healthy CLI. Allnighter does not create worktrees, branches, commits, landing, or revert rules. |
| **Managed "Implement This" / picker-as-prompt** (`ON HOLD/12`) | `ImplementationBrief` + lane substrate | A managed "send this to execution" action creates a Task -> Lane; reuses the same work-order shape after lane safety exists. |
| **Races** (`ON HOLD/11`) | The fan-out engine | A race is a fan-out where members are lanes on one pinned base commit instead of text members. |
| **iOS floor manager** (`ON HOLD/08–09`) | The `RunEvent` stream + a Hummingbird server in the Mac app | Wrap the existing in-process event stream in a WebSocket; iOS subscribes with `?since=<seq>`. Event shapes already match. |
| **Project/repo context** | `MemberPrompt` | Prompt builder gains optional repo/file context; member prompt stops being identical-text-only. |
| **Scheduling / quota harvest** (`ON HOLD/17`) | `WorkerRunner` dispatch | A scheduler/governor sits in front of `TaskGroup` spawn; adds concurrency caps + reset-window logic. |
| **Scorecards / routing** (`ON HOLD/16`) | `MemberResponse` (already has timing/outcome) | Aggregate response outcomes per worker over runs; drive routing. |
| **Preference ledger / taste** (`ON HOLD/15`) | A new `PreferenceEvent` on "I liked plan X / picked dissent Y" | Logged from the master-plan view; structured for future market-outcome extension. |
| **Persistence at scale** | Run index | Flat files → GRDB; `run.json` stays the artifact. |

Rule: if a phase wants a shortcut that would *remove* one of these seams (e.g.
hardcoding the panel, shell-concatenating prompts, mutating UI truth instead of
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
| 2026-06-14 | MVP scoped first to the Council slice (text judgment + configurable synthesis); full managed factory parked. | Cheapest, safest, proven-daily wedge; reuses constitution substrate. Direct executor dispatch is the next MVP layer without Allnighter-owned git rules. |
| 2026-06-14 | Swift 6 / SwiftUI for the MVP (Python rejected per founder). | Seed of the full product; no rewrite for iOS or factory. |
| 2026-06-14 | Workers described by editable driver manifests; `manual_paste` fallback for un-scriptable CLIs. | Churn defense + complete panel on day one. |
| 2026-06-14 | In-process `RunEvent` stream with constitution-matching envelope. | iOS attaches later via WebSocket with no event-shape change. |
| 2026-06-14 | Post-MVP review board uses a fixed fanout/reduce stage chain, not a general workflow engine. | Phase 05 ships first; review feedback is advisory and final spec synthesis decides from first principles. |

> Append a row whenever a phase changes a locked decision. Do not change the
> stack silently inside a phase.
