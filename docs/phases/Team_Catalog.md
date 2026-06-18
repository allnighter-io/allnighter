# Team Catalog

Status: Backend BUILT — S00–S05 shipped (2026-06-16, branch `feat/design-chain`).
Core lane-scoped `TeamPreset` + `SkillCatalog`/`ModelCatalog`/`TeamResolver`/
`TeamRequestResolver`/`BuiltInTeams` (13 teams) + Engine `CatalogRunCoordinator`
(answer→review→output staging) + CLI `--team`/`--lane`/legacy `--effort`/`--type` +
`team teams` + `TeamRunJSON` upgrades. 278 Core/Engine tests + Mac build green;
contracts regenerated. GUI composer/team-library (S05/S06) + iOS (S07) NOT built.
Owner: Founder + Shared Core + Mac + iOS
Updated: 2026-06-16

## Forward Simplification

Effort and team shape are **two independent axes**. Do not conflate them, and do
not remove either.

1. **Effort = per-worker model reasoning level (KEPT, user-facing).** The composer's
   `EFFORT Low / Med / High` sets the reasoning level of each worker's model where
   the selected source supports it. It is bound to the model (shown as
   `<model> · Med`, "higher effort = more reasoning time"), is real model
   configuration, and routes per CLI: Claude Code `--effort low|medium|high`; Codex
   `-c model_reasoning_effort="…"` (with `-m <model>`); Antigravity via a model-name
   variant; Grok has no effort axis. Effort is never removed and is never an
   Allnighter-wide knob — it is the provider/model reasoning setting per worker.

2. **Team shape = the team definition (named variants).** Worker count, review
   posture, output shape, proof bar, and research posture belong to the Team. To run
   deeper or lighter, select a different Team — `Bug Hunt Lite`, `Bug Hunt`,
   `Bug Hunt Exterminator` — not a separate generic Quick/Standard/Deep depth dial
   layered on top of the team.

New GUI/MCP surfaces select shape with:

```text
Lane -> Team -> Prompt -> Run
```

and set effort as the chosen model/worker's reasoning level where supported. They
must not introduce a separate generic team-depth/quality toggle:

```text
Lane -> Team -> <generic depth toggle> -> Prompt -> Run   # banned
```

Rules:

- Team names/definitions own worker count, review posture, output shape, proof
  bar, and research posture (axis 2).
- If team shape changes, create/select a different Team, such as `Bug Hunt Lite`,
  `Bug Hunt`, or `Bug Hunt Exterminator` — not a generic depth toggle.
- Reasoning effort (axis 1) is a worker/model setting where the selected source
  supports it. It stays. The GUI surfaces it bound to the model, and it routes to
  the real CLI flag/arg per CLI above.
- GUI presents the Core/CLI/MCP contract. It must not introduce a *client-only*
  toggle that fakes team shape; the EFFORT control is not client-only — it maps to
  the model's real reasoning-level argument.
- Built M1 substrate also used the Low/Med/High `effort` value to gate which worker
  rows activate (`minEffort`, `effortPolicy`, `synthesisPolicyByEffort`). That
  machinery is built, tested, and remains functional — it is not ripped out. The
  forward, preferred way to express a different team shape is a distinct named Team
  variant rather than an effort-gated row set; reasoning effort itself stays as
  axis 1.

## Founder Intent

Fan out should feel like sending the right unit onto the field, not configuring a
form.

When the user chooses Fan out, Allnighter must show:

```text
Build / Design / Copy
```

Then it must show a **team**, not a model or a second effort knob. Users should
be able to select from pre-built and custom teams in the composer:

```text
Fan out -> Build -> Bug Hunt
Fan out -> Design -> Premium Polish
Fan out -> Copy -> Landing Page Team
```

The hard part is not picking the team. The hard part is creating useful teams:
worker skills, model bindings, output shape, and review posture.
Allnighter should do that hard part up front with excellent built-in teams, then
let users duplicate and customize them.

Important backend law:

```text
A team does not require many connected CLIs.
```

If the user has only one ready model, Allnighter can still run a powerful team by
running that model multiple times with different skills. One Opus wearing six
different skills is not as diverse as six different models, but it is still much
better than one prompt.

## Product Value

Custom teams are the 10x upgrade to fan-out:

- The composer stays fast: pick lane, team, send.
- Users get immediate value from built-in specialist teams.
- Power users can create reusable expert units: Bug Hunt, GUI Bug Hunt,
  Security Review, Premium Polish, Conversion Studio, Architecture Pressure Test.
- Skill prompts become product value, not hidden implementation detail.
- One connected CLI still unlocks parallel perspectives through self-fusion.

The product promise becomes:

```text
Build your bench once. Send the right team every time.
```

## Trusted Workflow Slice

```text
open composer
-> choose Fan out
-> choose Build / Design / Copy
-> choose a lane-scoped team
-> run
-> result truthfully shows workers, skills, models, failures, and plan/board
```

The first implementation slice should prove:

```text
one ready CLI -> Build -> Bug Hunt -> multiple skill workers on one model
```

That slice proves the most important claim: Allnighter is valuable even before
the user connects every model source.

## Non-goals

- Do not infer Build / Design / Copy from the prompt.
- Do not configure team skills inside the main composer.
- Do not add a fourth peer lane for security, bugs, architecture, research, SEO,
  or sales. These are teams, types, or skills inside Build / Design / Copy.
- Do not require multiple unique models for a team to run.
- Do not pretend repeated runs of one model are different models.
- Do not estimate cost, runtime, quota burn, or task difficulty.
- Do not expose worktree, subprocess, branch, or scheduler plumbing.

## Current State

Existing useful substrate:

- `TeamPreset` already stores a named worker lineup plus synthesis config.
- `TeamPresetStore` already persists user-created presets.
- `WorkerSpec` already supports `modelId`, `count`, and `skillId`.
- `WorkerSpec.expandedWorkers()` already supports repeated workers for one model.
- `TeamRunCoordinator` already fans out workers in parallel.
- `SkillLibrary` already prepends per-worker skill prompt prefixes.
- The Mac app already has "Save current team as preset..." for global presets.
- Copy docs already establish type packs, skill suites, and default teams.

Current gaps:

- `TeamPreset` is not lane-scoped.
- Legacy effort is still represented in built M1 data and should be migrated to
  named team variants or model reasoning settings.
- Built-in Build and Design specialist teams are not defined as product packs.
- The main composer does not expose Fan out lane/team selection.
- Team customization is not separated cleanly into a settings/library surface.
- CLI grammar accepts `--lane`, `--type`, and legacy `--effort`, but new
  run-shaping input should be team id / deployable team id.
- Team display can still over-emphasize models where it should show teams and
  workers.

## Implementation Contract Decisions

These decisions close the mentor-review ambiguity before S00 starts.

### Canonical Fan out request

The canonical Fan out request is:

```text
lane + teamPresetId + prompt
```

`type` is not a primary Fan out selector. It survives as optional metadata and
as a Copy compatibility/router field only when a Copy phase doc explicitly owns
that mapping. New composer UI picks a Copy team such as `Landing Page Team`, not
a separate type chip.

If a request passes both `teamPresetId` and `type`, the type must match the
team's `typeTags`. A conflicting pair is rejected before running; it must not
silently choose a different team.

### Legacy effort values

M1 shipped canonical machine values:

```text
low
med
high
```

Display labels are:

```text
Low
Med
High
```

Do not introduce `medium` as a fourth spelling if touching legacy artifacts.
Forward Deploy Teams work should not expose this as a generic team-depth control.
Move worker-count/depth differences into named Team variants and reserve
reasoning effort for provider/model settings.

### Team and preset language

Product language:

```text
Team = the saved unit the user picks
TeamPreset = the Core type that stores a built-in or custom team
Preset = old public word, avoid in new UI
```

CLI may keep `--preset` as a hidden/deprecated compatibility alias while new
docs and generated help prefer `--team`.

### Legacy effort schema homes

M1 effort is not prose. In built v1 it has these enforceable homes:

- each worker row has `minEffort`;
- each team has `effortPolicy`;
- each output-capable lane can define `outputCountByEffort`;
- synthesis/review behavior is selected through `synthesisPolicyByEffort`.

Deferred from v1: independent per-effort runtime estimates, quota estimates, and
opaque "difficulty" scoring. Admission may cap or queue work, but effort never
becomes a forecast.

Forward cleanup should collapse `minEffort`, `effortPolicy`, and
`synthesisPolicyByEffort` into named Team variants unless the setting maps
strictly to provider/model reasoning effort.

### Skills are catalog assets

Built-in skill prompts live in a Core-owned `SkillCatalog`, not only in this doc
and not as ad hoc strings in SwiftUI.

Team rows reference `skillId`. Editing a built-in skill creates a custom skill;
built-in skills remain immutable except by versioned app update. Runs snapshot
resolved `skillId`, `skillName`, and `skillVersion` so history remains readable
after a skill update.

### Stages are explicit

Not every worker is a blind first-pass answer worker.

Team rows declare:

```text
purpose: answer | review
```

Answer workers run blind in parallel. Review workers run after answer workers
and may see answer outputs. The plan/output writer is a synthetic `plan` worker
resolved from the team's synthesis policy and included in the run snapshot.

This keeps critic, contrarian, prioritizer, and final-register skills meaningful
without making the base fan-out graph arbitrary.

### Output kind drives synthesis

Every team declares one `outputKind`:

```text
plan
bugPacket
securityRegister
architectureVerdict
proofPacket
designBoard
polishBoard
copyBoard
```

`outputKind` chooses the synthesis profile, result renderer, and default stage
shape. It prevents a Security Review from being forced into generic Build-plan
copy and prevents Design/Copy boards from pretending they are implementation
plans.

### Model fallback is deterministic

Fallback policies depend on Core-owned model metadata:

```text
capabilityTags
laneTags
strengthRank
```

Until user-edited ranking exists, built-in model metadata supplies deterministic
rank and capability defaults. Ties break by stable model id order.

### Self-fusion obeys admission

Multiple workers on one ready model are allowed, but they do not bypass
`docs/phases/parked/Utilization_Admission_Control.md`.

Same-source workers may run concurrently only when the driver/admission layer
allows it. Otherwise they queue visibly as workers waiting for the same model.
The UI may show active specialist badges so the user sees that High runs more
workers, but it must not estimate runtime or cost.

### Defaults are lane invariants

Exactly one default team is active per lane.

Rules:

- setting a custom team as lane default clears the previous default for that
  lane;
- deleting the current custom default falls back to the built-in lane core team;
- built-in core team ids are immutable;
- built-in team ids are public contract once used in history or reproduce
  commands.

## Truth Owner

Shared Core owns the semantic truth:

```text
WorkLane
EffortLevel
TeamPreset metadata
Skill definitions
Team resolution
TeamRunJSON projection
```

Mac, iOS, CLI, MCP, and local API render or invoke this truth. They do not invent
lane/team rules locally.

## Lie-prone Layers

| Layer | Possible lie | Required guardrail |
| --- | --- | --- |
| Prompt classifier | Infers "copy" means Copy lane | Never infer lane from prose for Fan out |
| Composer UI | Shows one model for a team run | Fan out target displays lane + team |
| Team picker | Offers illegal teams | Filter teams by selected lane |
| Team resolver | Disables team when only one model is ready | Resolve multiple skill workers onto one ready model when allowed |
| Results UI | Hides repeated model usage | Show worker rows as `Skill / Model`; model count and worker count are separate |
| JSON contract | Stores GUI-only team names | `TeamRunJSON.teamRun.teamPresetId` and worker skill/model snapshot are authoritative |
| Settings | Lets teams exist without lane | Every team must declare exactly one lane |

## Semantic Rules

### 1. Fan out requires an explicit lane

The user chooses the lane. Allnighter never guesses.

Reason:

```text
"The copy looks bad"
```

could mean:

- Copy: rewrite the words.
- Design: improve the button/menu visual hierarchy.
- Build: update the code that renders the copy.

This is user intent, not model-inferable metadata.

### 2. Lane is only for Fan out

Chat resolves to one worker. Execute resolves to one executor. Fan out resolves
to a team.

```text
Chat    -> worker/model
Fan out -> lane + team
Execute -> executor
```

Only Fan out shows Build / Design / Copy.

### 3. Composer selects teams; settings builds teams

Composer is for dispatch:

```text
Fan out
Build
Bug Hunt
Run
```

Settings is for authoring:

```text
Team name
Lane
Legacy default effort (M1 only)
Workers:
  Skill
  Model policy
  Optional preferred model
  Optional fallback policy
```

The composer may include a quiet `Customize teams...` link, but opening it leaves
the composer flow. Composer must not become a team-builder.

### 4. Teams are lane-scoped presets

Every built-in and custom team declares **exactly one and only one** lane:

```text
Build
Design
Copy
```

There are no shared teams and no multi-lane teams. If a useful lineup should
exist in two lanes, duplicate it and tune the copy for each lane. Example:

```text
Build -> Security Review
Design -> Accessibility Review
```

They may share some skills, but they are separate teams because the output,
proof, and user intent are different.

Specialties live inside the lane:

```text
Build -> Bug Hunt
Build -> GUI Bug Hunt
Build -> Security Review
Build -> Architecture Pressure Test
Design -> Premium Polish
Design -> Conversion Studio
Copy -> Landing Page Team
```

Security is not a fourth lane. It is a Build team.

### 5. Teams are made of workers, not models

A team row is:

```text
Skill + Model policy
```

Examples:

```text
Bug Reproducer      Opus preferred, any code model allowed
State Skeptic       Sonnet preferred, fallback to strongest ready
Regression Guard    Codex preferred, fallback to any code model
```

If only Opus is ready, the same team can resolve to:

```text
Bug Reproducer      Opus
State Skeptic       Opus
Regression Guard    Opus
```

Those are three workers because Opus is wearing three skills.

### 6. Worker count and model count are different facts

The UI and JSON must distinguish:

```text
6 workers
1 model
6 skills
```

from:

```text
6 workers
5 models
6 skills
```

Never imply repeated workers are unique models. The honest value is perspective,
not fake vendor diversity.

### 7. Legacy effort is Low / Med / High

M1 used industry-familiar labels:

```text
Low
Med
High
```

Do not use Quick / Standard / Deep in new composer UI.

Legacy effort is a bundle. For a team it may affect:

- number of workers activated;
- synthesis/review stage policy;
- whether a review/final pass runs;
- output count, where lane-specific;
- whether fallback workers are allowed.

In the built M1 substrate, those effects are expressed through `minEffort`,
`effortPolicy`, and `synthesisPolicyByEffort`. Do not add UI-only effort
behavior. Forward Deploy Teams should replace this user-facing selector with
named Team variants.

Effort is not an estimate of runtime, quota, cost, or complexity.

### 8. Built-in teams are product assets

Built-in teams should be treated like templates users can trust, duplicate, and
customize. The skill prompts are part of the product.

Built-ins must include:

- a concise team name;
- lane;
- default effort;
- intended use;
- worker skill rows;
- model policy;
- Low / Med / High activation behavior;
- output shape;
- anti-echo instruction;
- version.

### 9. User teams are first-class

Users can create, duplicate, edit, and delete custom teams.

Each custom team belongs to exactly one lane. Changing a team's lane is a
semantic edit, not a filter toggle; the UI should make that obvious and may
prefer "Duplicate to another lane" over direct lane mutation for built-in-based
teams.

Minimum user team fields:

```text
id
displayName
lane
description
defaultEffort
isDefaultForLane
outputKind
workerSpecs
synthesisPolicyByEffort
effortPolicy
builtIn
version
```

Future optional fields:

```text
typeTags
purposeTags
recommendedFor
disabledReason
createdAt
updatedAt
```

## Data Model Target

Preferred Core shape:

```swift
public enum WorkLane: String, Codable, Sendable, CaseIterable {
    case build
    case design
    case copy
}

public enum EffortLevel: String, Codable, Sendable, CaseIterable {
    case low
    case med
    case high
}

public enum TeamOutputKind: String, Codable, Sendable, CaseIterable {
    case plan
    case bugPacket
    case securityRegister
    case architectureVerdict
    case proofPacket
    case designBoard
    case polishBoard
    case copyBoard
}

public enum TeamWorkerPurpose: String, Codable, Sendable, CaseIterable {
    case answer
    case review
}

public struct TeamPreset: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var displayName: String
    public var lane: WorkLane
    public var description: String
    public var outputKind: TeamOutputKind
    public var defaultEffort: EffortLevel
    public var isDefaultForLane: Bool
    public var workerSpecs: [TeamWorkerSpec]
    public var effortPolicy: TeamEffortPolicy
    public var synthesisPolicyByEffort: [EffortLevel: TeamSynthesisPolicy]
    public var typeTags: [String]
    public var purposeTags: [String]
    public var builtIn: Bool
    public var version: Int
}
```

`WorkerSpec` should be replaced for team-catalog work by `TeamWorkerSpec`.
Existing ad hoc/global presets can be converted during the implementation slice;
this phase defines the final shape rather than a long-lived compatibility model.

Note two distinct purpose enums (do not merge them): the catalog
`TeamWorkerPurpose` is `{answer, review}` — the plan writer is selected separately
via `TeamSynthesisPolicy.planWriterSkillId`, not as a worker purpose. The run-output
worker purpose (`TeamRunJSON.WorkerPurpose`) is `{answer, plan, review}`, so the
writer worker is surfaced with `"purpose": "plan"` in `TeamRunJSON` even though its
catalog spec purpose is `answer`.

Target shape:

```swift
public struct TeamWorkerSpec: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var skillId: String
    public var purpose: TeamWorkerPurpose
    public var minEffort: EffortLevel
    public var preferredModelId: String?
    public var allowedModelIds: [String]
    public var requiredCapabilityTags: [ModelCapabilityTag]
    public var count: Int
    public var fallbackPolicy: ModelFallbackPolicy
    public var required: Bool
}

public enum ModelFallbackPolicy: String, Codable, Sendable, CaseIterable {
    case exactOnly
    case sameSource
    case laneCapable
    case anyReady
    case strongestReady
}

public struct TeamEffortPolicy: Codable, Sendable, Equatable {
    public var defaultEffort: EffortLevel
    public var outputCountByEffort: [EffortLevel: Int]
    public var allowPartialByEffort: [EffortLevel: Bool]
}

public enum AnalysisDepth: String, Codable, Sendable, CaseIterable {
    case combined   // analysis + plan produced in one writer pass
    case separate   // analysis and plan produced as distinct passes
}

public struct TeamSynthesisPolicy: Codable, Sendable, Equatable {
    public var outputKind: TeamOutputKind
    public var planWriterSkillId: String
    public var modelPolicy: ModelSelectionPolicy
    public var analysisDepth: AnalysisDepth
    public var dissentPolicy: DissentPolicy
}

public struct ModelSelectionPolicy: Codable, Sendable, Equatable {
    public var preferredModelId: String?
    public var requiredCapabilityTags: [ModelCapabilityTag]
    public var fallbackPolicy: ModelFallbackPolicy
}

public enum ModelCapabilityTag: String, Codable, Sendable, CaseIterable {
    case code
    case planner
    case review
    case security
    case design
    case image
    case copy
    case localContext
    case fast
}

public struct ModelCapabilities: Codable, Sendable, Equatable {
    public var laneTags: [WorkLane]
    public var capabilityTags: [ModelCapabilityTag]
    /// Higher is stronger. Ties break by stable model id.
    public var strengthRank: Int
}

public enum DissentPolicy: String, Codable, Sendable, CaseIterable {
    case preserveDissent
    case compareOptions
    case riskRegister
}
```

Default semantics:

- `minEffort` gates worker activation. `low` activates `low` rows, `med`
  activates `low + med`, and `high` activates all rows.
- `allowedModelIds == []` means any ready model matching required capability and
  lane tags.
- `count > 1` creates multiple workers with the same skill and distinct
  `instanceIndex`; this is allowed but not exposed in the first composer.
- `required == false` rows may be disabled without failing the whole run.
- `required == true` rows must resolve or the team is disabled for that effort.
- Built-in IDs and skill IDs are immutable after public release.

## Team Resolution

Team resolution converts a lane team preset plus current bench state into a
concrete run snapshot.

Inputs:

```text
teamPresetId
lane
effort
ready models
driver readiness
skill compatibility
fallback policy
admission snapshot
```

Outputs:

```text
resolved workers
warnings
disabled rows
plan writer worker
outputKind
TeamRunJSON worker snapshot
```

Resolution rules:

1. Validate `team.lane == request.lane`; otherwise reject before running.
2. Choose `request.effort ?? team.defaultEffort`.
3. Activate rows whose `minEffort <= effort`.
4. Split active rows into `answer` and `review` rows.
5. For each row, try `preferredModelId`, then apply `fallbackPolicy`.
6. Apply model capability and lane tags before rank fallback.
7. If no allowed model is ready for a required row, the team is disabled for
   that effort.
8. If no allowed model is ready for an optional row, mark that row disabled and
   include it in warnings.
9. Resolve the synthetic plan/output writer from `synthesisPolicyByEffort`.
10. A team can run if at least one answer worker resolves and the synthetic
    plan/output writer resolves.
11. Answer workers run in the answer fan-out stage with pristine context; they
    do not see each other's outputs.
12. Review workers run after answer workers and may see answer outputs.
13. The synthetic plan/output writer runs after answer/review stages and must
    preserve dissent according to `dissentPolicy`.
14. If only one model is ready, multiple rows may resolve to that model with
    different `skillId`s.
15. Expanded worker ids must remain distinct with `instanceIndex`.
16. Same-source workers obey admission/concurrency caps. They may be queued
    behind each other; queued workers still render honestly.
17. Results must show each worker as `Skill / Model`.

One-model example:

```json
{
  "teamPresetId": "build_bug_hunt",
  "lane": "build",
  "effort": "high",
  "readyModels": ["model_opus"],
  "workers": [
    {"id": "model_opus#0", "skillId": "bug_reproducer", "modelId": "model_opus"},
    {"id": "model_opus#1", "skillId": "truth_owner_mapper", "modelId": "model_opus"},
    {"id": "model_opus#2", "skillId": "correct_fix_planner", "modelId": "model_opus"},
    {"id": "model_opus#3", "skillId": "regression_guard", "modelId": "model_opus"},
    {"id": "model_opus#4", "skillId": "trace_mapper", "modelId": "model_opus"},
    {"id": "model_opus#5", "skillId": "state_skeptic", "modelId": "model_opus"},
    {"id": "model_opus#6", "skillId": "change_impact_reviewer", "modelId": "model_opus"},
    {"id": "model_opus#7", "skillId": "user_impact_narrator", "modelId": "model_opus"},
    {"id": "model_opus#8", "skillId": "contrarian_root_cause", "modelId": "model_opus"},
    {"id": "model_opus#9", "skillId": "bug_packet_writer", "modelId": "model_opus", "purpose": "plan"}
  ],
  "warnings": [
    "Only one ready model. Running multiple skills on Opus.",
    "Opus admission may queue workers for the same source."
  ]
}
```

`reproduceCommand` replays intent:

```text
alln team --lane build --team build_bug_hunt "..."
```

The run snapshot is the exact historical record of the models/skills that
actually ran. If the bench changes later, replaying the command may resolve a
different concrete model set while preserving the same lane/team intent.

## Composer Contract

Collapsed composer mode:

```text
[ Chat v ] [ Opus 4.8 v ] [ Send ]
[ Fan out v ] [ Build ] [ Bug Hunt v ] [ Run team ]
[ Execute v ] [ Codex v ] [ Execute ]
```

Fan out surface:

```text
Fan out

Lane:
[ Build ] [ Design ] [ Copy ]

Team:
[ Bug Hunt v ]

Prompt:
[ ... ]

[ Run team ]
```

Team picker popover:

```text
Build teams

* Build Core          Default
  Bug Hunt
  Bug Hunt Exterminator
  GUI Bug Hunt
  Security Review
  Architecture Test
  Release Proof

Customize teams...
```

Rules:

- Lane buttons are visible at rest when Fan out is selected.
- Changing lane selects that lane's default team.
- The target chip shows team, not model.
- The popover can change lane and team.
- The popover does not edit worker rows.
- Team selection may show active specialist badges, e.g. `Reproducer`, `Trace`,
  `Regression`, to communicate shape without estimating time or cost.
- If the selected lane has no team, show a clear empty state and a
  `Create team...` action.
- If only one model is ready, do not block the team; show a compact warning.
- The send button verb reflects the armed mode: Send, Run team, Execute.
- Enter sends chat. It must not run Fan out or Execute unless the user has
  explicitly changed the mode and the UI visibly shows that mode.

## Settings / Team Library Contract

Settings owns team authoring.

Team library sections:

```text
Build
Design
Copy
```

Each lane lists:

```text
Default team
Built-in teams
Custom teams
```

Team editor:

```text
Name
Lane
Description
Make default for lane

Workers
Skill                  Stage    Legacy min effort   Preferred model       Fallback
Bug Reproducer         Answer   Low          Opus                  Strongest ready
Trace Mapper           Answer   Med          Sonnet                Any ready
Regression Guard       Answer   Low          Codex                 Lane capable
Contrarian Root Cause  Review   High         Opus                  Any ready

[ Add worker ] [ Duplicate team ] [ Save ]
```

Guardrails:

- Built-in teams cannot be overwritten; duplicate to customize.
- A custom team cannot save without a lane.
- A team cannot save without at least one worker row.
- A worker row cannot save without a skill.
- A worker row must declare `stage` and `minEffort`.
- Model fallback must be visible; users should understand whether a row can
  resolve to another model.
- If a custom team references a missing model, keep the team and show a row-level
  warning; do not delete the row.
- Deleted teams remain referenced by past runs through run snapshots; history
  must still render.
- Setting a team as default for a lane clears the previous custom default.
- Deleting a custom default falls back to the built-in core team for that lane.
- Built-ins are duplicate-to-edit; changing a built-in's lane is not allowed.

## Built-in Team Manifest Index

The prose below explains why each team exists. The manifest index pins the
machine-readable shape implementers must encode.

Legend:

```text
A = answer stage
R = review stage
P = synthetic plan/output writer
L/M/H = minEffort
```

### Build manifests

```text
build_core
lane: build
outputKind: plan
defaultEffort: med
writer: plan_writer_build (P, strongest planner, all efforts)
rows:
  product_architect (A, L)
  proof_planner (A, L)
  first_principles_builder (A, M)
  code_maintainer (A, M)
  scope_steward (R, M)
  security_privacy_reviewer (R, H)
  contrarian_reviewer (R, H)

build_bug_hunt
lane: build
outputKind: bugPacket
defaultEffort: high
writer: bug_packet_writer (P, strongest planner, all efforts)
rows:
  bug_reproducer (A, L)
  truth_owner_mapper (A, L)
  correct_fix_planner (A, L)
  regression_guard (A, L)
  trace_mapper (A, M)
  state_skeptic (A, M)
  change_impact_reviewer (A, M)
  user_impact_narrator (R, H)
  contrarian_root_cause (R, H)

build_gui_bug_hunt
lane: build
outputKind: bugPacket
defaultEffort: high
writer: gui_bug_packet_writer (P, strongest planner, all efforts)
rows:
  gui_bug_reproducer (A, L)
  gui_proof_guard (A, L)
  correct_fix_planner (A, L)
  regression_guard (A, L)
  truth_owner_mapper (A, M)
  state_skeptic (A, M)
  change_impact_reviewer (A, M)
  gui_layout_reviewer (R, H)
  contrarian_root_cause (R, H)

build_security_review
lane: build
outputKind: securityRegister
defaultEffort: high
writer: security_register_writer (P, strongest planner, all efforts)
rows:
  boundary_mapper (A, L)
  secrets_reviewer (A, L)
  permission_reviewer (A, L)
  data_flow_reviewer (A, M)
  abuse_case_reviewer (A, M)
  dependency_injection_reviewer (R, H)
  security_fix_prioritizer (R, H)

build_architecture_pressure_test
lane: build
outputKind: architectureVerdict
defaultEffort: med
writer: architecture_verdict_writer (P, strongest planner, all efforts)
rows:
  truth_owner (A, L)
  boundary_mapper (A, L)
  complexity_cutter (A, L)
  failure_concurrency (A, M)
  migration_steward (A, M)
  contrarian_architect (R, H)

build_release_proof
lane: build
outputKind: proofPacket
defaultEffort: high
writer: proof_packet_writer (P, strongest planner, all efforts)
rows:
  acceptance_auditor (A, L)
  test_runner_planner (A, L)
  risk_register (R, L)
  edge_case_hunter (A, M)
  contract_drift_checker (A, M)
  demo_narrator (R, H)
```

### Design manifests

```text
design_core
lane: design
outputKind: designBoard
defaultEffort: med
writer: design_board_writer (P, strongest design/planner, all efforts)
rows:
  information_architect (A, L)
  interaction_designer (A, L)
  visual_system_designer (A, L)
  accessibility_reviewer (R, M)
  brand_fit_reviewer (R, M)
  outlier_direction (A, H)
  design_critic (R, H)

design_premium_polish
lane: design
outputKind: polishBoard
defaultEffort: high
writer: polish_board_writer (P, strongest design/planner, all efforts)
rows:
  hierarchy_sculptor (A, L)
  type_spacing_auditor (A, L)
  color_token_keeper (A, L)
  component_stylist (A, M)
  state_designer (A, M)
  polish_critic (R, H)

design_conversion_studio
lane: design
outputKind: designBoard
defaultEffort: high
writer: conversion_board_writer (P, strongest design/planner, all efforts)
rows:
  offer_clarity (A, L)
  cta_path (A, L)
  friction_hunter (A, M)
  trust_builder (A, M)
  mobile_scanner (A, M)
  objection_finder (R, H)

design_radical_directions
lane: design
outputKind: designBoard
defaultEffort: med
writer: direction_board_writer (P, strongest design/planner, all efforts)
rows:
  minimal_direction (A, L)
  bold_direction (A, L)
  operational_direction (A, M)
  editorial_direction (A, M)
  native_app_direction (A, H)
  direction_critic (R, H)

design_usability_triage
lane: design
outputKind: polishBoard
defaultEffort: med
writer: usability_triage_writer (P, strongest design/planner, all efforts)
rows:
  journey_mapper (A, L)
  control_ergonomics (A, L)
  navigation_reviewer (A, M)
  accessibility_reviewer (R, M)
  cognitive_load_cutter (R, H)
  state_feedback_reviewer (R, H)
```

### Copy parity manifests

Copy team copy and output schemas remain owned by `docs/phases/copy/`, but Fan
out must not show an empty Copy peer lane once this catalog ships.

Minimum ids for parity:

```text
copy_core
copy_landing_page
```

`copy_landing_page` is the team materialization of the old Landing page copy
type. If Copy still accepts a `landing-page` type in CLI or slash-command form,
that type resolves to `copy_landing_page` unless the user explicitly picks a
different Copy team.

## Built-in Build Teams

### Build Core

Default Build team.

Purpose:

```text
Turn a rough product/build prompt into an implementable plan with scope,
architecture, risks, and proof.
```

Default effort: Med.

Output:

```text
plan or work-order-ready spec
```

Low activates:

- Product Architect
- Proof Planner

Med activates:

- Product Architect
- First Principles Builder
- Code Maintainer
- Proof Planner
- Scope Steward

High activates:

- all Med workers;
- Security & Privacy Reviewer;
- Contrarian Reviewer;
- final plan synthesis with explicit accepted/rejected tradeoffs.

Workers:

| Skill | Prompt job | Preferred model policy |
| --- | --- | --- |
| Product Architect | Translate the prompt into product behavior, state ownership, user-visible acceptance criteria, and non-goals. Name the smallest coherent slice. | strongest ready planner |
| First Principles Builder | Ignore local habit at first. Derive the simplest architecture from the product claim, then reconcile with existing code patterns. | strongest ready planner |
| Code Maintainer | Preserve repo style. Identify files likely touched, coupling risk, migration risk, and cleanup that must not be mixed into the slice. | code-capable model |
| Proof Planner | Define the Works Test, unit checks, fixtures, and negative tests. Reject proof by screenshots where behavior/state is the claim. | code-capable model |
| Scope Steward | Cut the plan to the smallest valuable slice. Flag anything that is a separate feature, separate risk class, or broad cleanup. | any ready |
| Security & Privacy Reviewer | Check credentials, local data, permissions, network boundaries, user consent, and destructive operations. | security-capable or strongest ready |
| Contrarian Reviewer | Argue the best reason this plan is wrong. Preserve useful dissent instead of echoing consensus. | any ready |

Skill prompt templates:

```text
Product Architect:
You are the product architect for this Build fan-out. Convert the prompt into
specific behavior, state ownership, and acceptance criteria. Name the truth owner
and the smallest coherent slice. Do not write implementation code. Do not expand
scope beyond what the user asked.

First Principles Builder:
Reason from first principles before touching existing patterns. What shape would
the feature have if built cleanly today? Then reconcile that with the existing
repo and name the compromise. Prefer simple, local changes over clever systems.

Code Maintainer:
Read the request as a maintainer. Identify likely files, coupling risk,
migration risk, and behavior that must not regress. Preserve existing style.
Reject broad cleanup unless it is required for the requested behavior.

Proof Planner:
Design proof. Name the Works Test, deterministic checks, fixtures, and negative
tests. Say exactly what would convince a skeptical maintainer that the behavior
works. Do not accept screenshots as proof for state or dispatch semantics.

Scope Steward:
Cut. Separate must-have from nice-to-have, feature from cleanup, and current
slice from later phase. If the plan is too large, propose the smallest valuable
slice that still honors the prompt.

Security & Privacy Reviewer:
Review privacy, credentials, local files, permissions, network calls, destructive
actions, and user consent. Name any high-risk stop before implementation. Prefer
local, auditable behavior.

Contrarian Reviewer:
Disagree usefully. Find the strongest reason the emerging plan may fail. Look
for hidden assumptions, missing owner truth, and user-trust risks. Preserve
dissent even if the final plan chooses another path.
```

### Bug Hunt

Specialist Build team.

Purpose:

```text
Find the real cause of broken behavior, map the blast radius, and plan the
smallest correct fix.
```

Default effort: High.

Best for:

- "This is broken."
- CLI, persistence, contract, worker, lifecycle, or state bugs;
- state not persisting;
- wrong worker/team shown;
- results disappearing;
- regression after a phase slice.

Output:

```text
bug packet: symptom, repro, truth owner, lie-prone layer, blast radius, smallest
correct fix, regression proof
```

Low activates:

- Bug Reproducer
- Truth Owner Mapper
- Correct Fix Planner
- Regression Guard

Med activates:

- Bug Reproducer
- Truth Owner Mapper
- Correct Fix Planner
- Regression Guard
- Trace Mapper
- State Skeptic
- Change Impact Reviewer

High activates:

- all Med workers;
- User Impact Narrator;
- Contrarian Root Cause;
- stronger negative tests.

Workers:

| Skill | Prompt job | Preferred model policy |
| --- | --- | --- |
| Bug Reproducer | Turn the report into the shortest reproducible scenario. Separate observed facts from guesses. | any ready |
| Truth Owner Mapper | Name the semantic owner and lie-prone layer before any fix proposal. | strongest ready planner |
| Trace Mapper | Map the likely path through UI, model, store, coordinator, and persisted data. Name where truth should live. | code-capable model |
| State Skeptic | Look for duplicated state, stale snapshots, optimistic UI lies, missing reloads, and persistence gaps. | strongest ready planner |
| Change Impact Reviewer | Name shared components, state owners, contracts, fixtures, and nearby workflows that the fix could affect. | code-capable model |
| Correct Fix Planner | Plan the smallest correct fix, not the smallest visible patch. | code-capable model |
| Regression Guard | Define the deterministic test that would have caught the bug. Include a negative test when possible. | code-capable model |
| User Impact Narrator | Explain what the user experienced and what trust was damaged. Keep the fix oriented around that claim. | any ready |
| Contrarian Root Cause | Challenge the obvious root cause. Name the second most plausible cause and how to rule it out cheaply. | any ready |

Skill prompt templates:

```text
Bug Reproducer:
Reduce the bug to the smallest reproducible scenario. Use concrete steps,
inputs, expected behavior, and observed behavior. Do not invent facts. If a
detail is unknown, name the missing observation.

Truth Owner Mapper:
Name the truth owner before proposing a fix. Separate the observed symptom from
the semantic owner, the layer that appears to be lying, and the proof that would
disprove that theory. Do not let a visible UI symptom make SwiftUI the assumed
owner.

Trace Mapper:
Map the bug through the likely layers: UI, presenter/model, engine, store,
contract, persisted file, external CLI. Name the truth owner and the first layer
likely to be lying.

State Skeptic:
Assume the bug is caused by duplicated state, stale state, optimistic UI, missing
persistence, or a drifted snapshot. Look for places the UI can display truth it
does not own.

Change Impact Reviewer:
Zoom out before the fix. Name the shared components, state owners, presenters,
persisted files, contracts, fixtures, and nearby workflows that the proposed fix
could affect. The goal is not broad cleanup; it is avoiding a local patch that
leaves wreckage elsewhere.

Correct Fix Planner:
Plan the smallest correct fix, not the smallest visible patch. Do not patch the
visible layer until the truth owner and blast radius are named. If the cause is
duplicated state, SSOT drift, presenter mismatch, or shared component behavior,
the correct fix may be deeper than the failing view.

Regression Guard:
Write the proof plan. Name the exact unit/integration/fixture test that would
fail before the fix and pass after. Include a negative test for the old lie when
possible. For GUI-visible bugs, name the fixture/render/watcher proof in addition
to semantic tests.

User Impact Narrator:
Describe the trust break in user terms. What did the user believe Allnighter
would do, what happened instead, and what must be visibly true after the fix?

Contrarian Root Cause:
Argue against the leading theory. Provide an alternate root cause and the
cheapest observation or test that rules it in or out.
```

### GUI Bug Hunt

Specialist Build team.

Purpose:

```text
Fix visible native-app breakage with rendered proof, layout-watcher review, and
the right truth owner.
```

Default effort: High.

Best for:

- missing, clipped, collapsed, overlapping, detached, or off-screen UI;
- broken popovers, sheets, scrims, z-order, or responsive layout;
- GUI bugs where build success or code inspection is not visual proof;
- visible wrong state where Core/content truth and layout truth must be separated.

Output:

```text
GUI bug packet: visible symptom, rendered repro, truth owner, layout proof,
smallest correct fix, regression proof
```

Low activates:

- GUI Bug Reproducer
- GUI Proof Guard
- Correct Fix Planner
- Regression Guard

Med activates:

- all Low workers;
- Truth Owner Mapper
- State Skeptic
- Change Impact Reviewer

High activates:

- all Med workers;
- GUI Layout Reviewer;
- Contrarian Root Cause.

Workers:

| Skill | Prompt job | Preferred model policy |
| --- | --- | --- |
| GUI Bug Reproducer | Reduce the visible failure to a rendered fixture/state and separate layout from data truth. | any ready |
| GUI Proof Guard | Name the required GUIFixture render, layout-watcher pass, affected states, and proof blockers. | code-capable model |
| Correct Fix Planner | Plan the smallest correct fix, not the smallest visible patch. | code-capable model |
| Regression Guard | Define semantic proof plus rendered proof when the surface is visible. | code-capable model |
| Truth Owner Mapper | Name the owner before SwiftUI is treated as the cause. | strongest ready planner |
| State Skeptic | Check SSOT drift, duplicated state, stale snapshots, and presenter mismatch. | strongest ready planner |
| Change Impact Reviewer | Name shared components and nearby workflows the visual fix can break. | code-capable model |
| GUI Layout Reviewer | Block closeout on clipped, missing, collapsed, overlapping, off-screen, detached, or z-order breakage. | any ready |
| Contrarian Root Cause | Challenge the leading visual-root-cause theory and name the cheapest ruling observation. | any ready |

Skill prompt templates:

```text
GUI Bug Reproducer:
Reduce the visible GUI bug to the smallest rendered state that proves it:
surface, fixture, window state, interaction, expected pixels, and observed
pixels. Separate layout breakage from content/data truth.

GUI Proof Guard:
Apply the GUI proof law. A visible GUI bug is not fixed from build success, code
confidence, or the builder's own screenshot. Name the required GUIFixture render,
layout-watcher pass, affected states, and any blocked proof harness.

GUI Layout Reviewer:
Review the rendered surface for clipped, collapsed, missing, overlapping,
off-screen, detached, or z-order/scrim breakage. Treat layout proof as separate
from Core/content truth, and block closeout when pixels are still broken.
```

### Security Review

Specialist Build team.

Purpose:

```text
Evaluate code, architecture, or a planned feature for privacy, credentials,
permission posture, local network exposure, and destructive operations.
Calibrate mitigations for a small team shipping quickly.
```

Default effort: High.

Best for:

- local API / MCP surfaces;
- iOS pairing;
- Tailscale/Supabase/R2 control and media paths;
- Keychain or credentials;
- running external CLIs;
- session kill, file deletion, worktree cleanup, or dispatch.

Output:

```text
small-team security review: boundaries, risks, severity, required stops, cheap
hardening, accepted risks, proof requirements
```

Low activates:

- Boundary Mapper
- Secrets Reviewer
- Permission Reviewer

Med activates:

- Boundary Mapper
- Secrets Reviewer
- Permission Reviewer
- Data Flow Reviewer
- Abuse Case Reviewer

High activates:

- all Med workers;
- Dependency/Injection Reviewer;
- Security Fix Prioritizer;
- final risk register.

Workers:

| Skill | Prompt job | Preferred model policy |
| --- | --- | --- |
| Boundary Mapper | Identify trust boundaries, local/remote hops, client/server ownership, and what data crosses each boundary. | strongest ready planner |
| Secrets Reviewer | Look for API keys, tokens, Keychain use, env vars, logs, config files, and accidental persistence. | security-capable or code model |
| Permission Reviewer | Check Full Disk Access, local network, file writes, process control, pairing, and consent posture. | security-capable or strongest ready |
| Data Flow Reviewer | Trace sensitive data lifecycle: source, transform, storage, transmission, deletion, and audit trail. | code-capable model |
| Abuse Case Reviewer | Think like a malicious local client, paired device, compromised cloud row, or confused agent. | any ready |
| Dependency/Injection Reviewer | Check shell invocation, argument escaping, prompt/file injection, dependency trust, and output handling. | code-capable model |
| Security Fix Prioritizer | Convert findings into required stops, must-fix before ship, cheap hardening, later-when-scale-warrants, accepted risk, and enterprise-only rejections. | strongest ready planner |

Skill prompt templates:

```text
Boundary Mapper:
Map every trust boundary. Name local process, app, CLI, network, cloud, paired
device, and file-system boundaries. For each crossing, name the data, authority,
and owner. Calibrate mitigations for a small team moving fast.

Secrets Reviewer:
Hunt for secrets and credential exposure. Check env vars, config files, Keychain,
logs, generated artifacts, prompts, run journals, and error messages. Assume logs
outlive the session. Prefer cheap, durable hygiene over enterprise process.

Permission Reviewer:
Review macOS/iOS permission posture. Name every permission request or destructive
capability, why it is needed, how the user consents, and how the app minimizes
the surface. Avoid permission rituals that slow traction without reducing real risk.

Data Flow Reviewer:
Trace sensitive data from source to deletion. Include local files, prompts,
attachments, worker output, run journals, cloud metadata, encrypted blobs, and
notifications. Prefer simple ownership and deletion rules a tiny team can maintain.

Abuse Case Reviewer:
Invent realistic misuse cases: confused user, malicious local client,
compromised paired device, compromised cloud metadata, prompt injection, and
agent overreach. Tie each to the smallest practical mitigation, not a generic
enterprise control.

Dependency/Injection Reviewer:
Check command construction, argument escaping, shell usage, dependency trust,
file paths, prompt injection, output parsing, and generated artifacts. Prefer
structured APIs over string parsing where possible, and prefer local code changes
over heavyweight governance.

Security Fix Prioritizer:
Convert findings into small-team action. Label required stop, must-fix before
ship, cheap hardening, later when scale warrants, accepted risk, or
enterprise-only suggestion rejected. Every required stop needs a proof condition.
```

### Architecture Pressure Test

Specialist Build team.

Purpose:

```text
Pressure-test a proposed architecture before implementation hardens the wrong
truth owner.
```

Default effort: Med.

Best for:

- new Core models;
- cross-surface contracts;
- run lifecycle;
- persistence;
- local API / WebSocket / MCP boundaries;
- iOS/Mac shared state.

Output:

```text
architecture verdict: truth owner, boundary map, rejected alternatives,
implementation slices, proof wall
```

Workers:

| Skill | Prompt job | Preferred model policy |
| --- | --- | --- |
| Truth Owner | Name the semantic owner for every durable fact. Reject UI-only truth. | strongest ready planner |
| Boundary Mapper | Draw package/surface/protocol boundaries and data flow. | code-capable model |
| Complexity Cutter | Remove abstractions that do not pay rent. Keep the shape local until duplication is real. | any ready |
| Failure & Concurrency | Look for races, partial writes, interruptions, retries, orphaned state, and cancellation. | code-capable model |
| Migration Steward | Identify compatibility, fixture, generated artifact, and old-data migration needs. | code-capable model |
| Contrarian Architect | Defend the strongest alternative architecture and explain why it loses or wins. | strongest ready planner |

Skill prompt templates:

```text
Truth Owner:
Name the semantic owner for every durable fact. Separate product truth from UI
rendering, generated artifacts, prompt prose, and cache state. Reject any design
where SwiftUI or an agent prompt becomes the only owner of durable meaning.

Boundary Mapper:
Map package, process, storage, protocol, and UI boundaries. For every boundary,
name what data crosses it, who owns it, and which tests or schemas keep it from
drifting.

Complexity Cutter:
Remove abstractions that do not pay rent. Prefer the smallest local shape that
preserves the future path. Call out cleverness, generic frameworks, and config
surfaces that are not needed for the current slice.

Failure & Concurrency:
Look for races, partial writes, cancelled tasks, orphaned runs, interrupted
processes, retries, and stale snapshots. Name what happens if the app closes
mid-run or two attempts touch the same owner.

Migration Steward:
Identify fixtures, generated artifacts, persisted files, CLI contracts, and docs
that must move together. Because the product is pre-user, prefer clean cutovers
over long-lived compatibility shims.

Contrarian Architect:
Defend the strongest alternative architecture. Say what it would make simpler,
what it would make worse, and what evidence would change the decision.
```

### Release Proof

Specialist Build team.

Purpose:

```text
Before a slice closes, prove that the owner-visible claim is actually true.
```

Default effort: High.

Best for:

- sprint closeout;
- mentor demo prep;
- before committing a risky slice;
- after broad docs/model/schema changes.

Output:

```text
proof packet: Works Test, commands run, missing proof, residual risks,
closeout verdict
```

Workers:

| Skill | Prompt job | Preferred model policy |
| --- | --- | --- |
| Acceptance Auditor | Compare the user-visible claim to implemented behavior. | any ready |
| Test Runner Planner | Identify exact commands and fixtures. | code-capable model |
| Edge Case Hunter | Probe empty, error, partial, interrupted, and one-model states. | any ready |
| Contract Drift Checker | Check generated docs, schemas, fixtures, CLI help, and JSON names. | code-capable model |
| Demo Narrator | State what the user can now do in one crisp walkthrough. | any ready |
| Risk Register | Name residual risk and proof gaps honestly. | strongest ready planner |

Skill prompt templates:

```text
Acceptance Auditor:
Compare the claimed user-visible behavior to the actual slice. Name what is
done, what is not done, and what would make the claim misleading.

Test Runner Planner:
Choose the exact proof commands, fixtures, and focused tests. Prefer
deterministic checks over agent judgment. Include the smallest command set that
protects the behavior.

Edge Case Hunter:
Probe empty, error, partial, interrupted, one-model, missing-model, and stale
history states. Look for where the happy path can lie.

Contract Drift Checker:
Check CLI help, generated schemas, fixtures, JSON field names, docs, and
reproduce commands for drift. Generated artifacts must come from the registry,
not hand edits.

Demo Narrator:
Write the shortest credible demo walkthrough. It should say what the user can do
now, what they will see, and why the result proves the slice.

Risk Register:
Name residual risks and proof gaps honestly. Separate blockers from acceptable
follow-ups and assign an owner to each open item.
```

## Built-in Design Teams

Design teams use the existing Design board substrate. This catalog does not
replace image-first design runs; it names reusable Design teams that can resolve
to text, image, or hybrid workers depending on model capabilities and attached
inputs.

Rules:

- Design output is a board, not a generic Build plan.
- Image-capable workers may produce visual tiles.
- Text-only workers may produce critique, direction, hierarchy, or interaction
  notes.
- The board renderer shows artifact type honestly.
- The picker still shows one Design team, not separate "text design" and "image
  design" lanes.

### Design Core

Default Design team.

Purpose:

```text
Turn a product/design prompt into several credible interface directions, then
make the tradeoffs visible.
```

Default effort: Med.

Output:

```text
design board: options, rationale, tradeoffs, selected direction if requested
```

Low activates:

- Information Architect
- Interaction Designer
- Visual System Designer

Med activates:

- Information Architect
- Interaction Designer
- Visual System Designer
- Accessibility Reviewer
- Brand Fit Reviewer

High activates:

- all Med workers;
- Outlier Direction;
- Design Critic;
- stronger comparison board.

Workers:

| Skill | Prompt job | Preferred model policy |
| --- | --- | --- |
| Information Architect | Organize the screen around user decisions, scan order, hierarchy, and object relationships. | design-capable or strongest ready |
| Interaction Designer | Focus on controls, states, flows, and ergonomic repeated use. | design-capable or strongest ready |
| Visual System Designer | Apply tokens, spacing, type, color restraint, and component consistency. | design-capable model |
| Accessibility Reviewer | Check contrast, keyboard, hit targets, motion, labels, and cognitive load. | any ready |
| Brand Fit Reviewer | Keep the surface in Allnighter's amber phosphor on midnight system and calm voice. | design-capable or any ready |
| Outlier Direction | Produce one deliberately different but plausible direction. | image/design model preferred |
| Design Critic | Compare options. Name what each option sacrifices. Reject pretty but unusable output. | strongest ready planner |

Skill prompt templates:

```text
Information Architect:
Design the information structure. What must be seen first, what can be
secondary, and what object relationships must be clear? Optimize for scanning
and repeated use, not marketing flourish.

Interaction Designer:
Design behavior. Choose controls, states, affordances, and flow. Make the common
path fast and the dangerous path explicit. Include empty, loading, error,
running, and done states where relevant.

Visual System Designer:
Apply the design system. Use dark-mode midnight surfaces, one warm amber signal,
restrained status hues, stable dimensions, and existing component patterns.
Avoid decorative clutter and one-note palettes.

Accessibility Reviewer:
Review contrast, focus, keyboard use, screen-reader labels, hit targets, motion,
and cognitive load. Point out where the design would fail under stress or on a
small screen.

Brand Fit Reviewer:
Protect Allnighter's voice and visual posture: calm, capable, local, technical,
and plain-spoken. Reject hype, noisy cards, and UI text that explains itself
instead of doing the job.

Outlier Direction:
Create one plausible direction that breaks the default assumptions while still
respecting product truth and the design system. The goal is useful contrast, not
novelty for its own sake.

Design Critic:
Evaluate the options. Name the job each option does best, where it fails, and
which tradeoff matters most. Prefer usable hierarchy over surface decoration.
```

### Premium Polish

Specialist Design team.

Purpose:

```text
Make an existing surface feel expensive, intentional, and native without
changing its product semantics.
```

Default effort: High.

Best for:

- a working view that feels rough;
- spacing/type/color pass;
- final mentor/demo polish;
- UI with correct behavior but weak hierarchy.

Output:

```text
polish board: concrete visual/interaction improvements, before/after priorities,
token/component changes
```

Workers:

| Skill | Prompt job | Preferred model policy |
| --- | --- | --- |
| Hierarchy Sculptor | Improve scan order, grouping, rhythm, and primary action clarity. | design-capable model |
| Type & Spacing Auditor | Fix text scale, density, alignment, spacing, and overflow risk. | design-capable or any ready |
| Color & Token Keeper | Keep one amber signal, muted status colors, and dark-mode system consistency. | design-capable model |
| Component Stylist | Use the correct controls: icons, segmented controls, menus, sliders, tabs, toggles. | design-capable or strongest ready |
| State Designer | Design loading, empty, running, failed, partial, and done states. | any ready |
| Polish Critic | Reject changes that only decorate. Preserve the product job and native feel. | strongest ready planner |

Skill prompt templates:

```text
Hierarchy Sculptor:
Improve visual hierarchy and scan order. Make the user's next action obvious
without oversized hero treatment. Group related controls and reduce visual noise.

Type & Spacing Auditor:
Audit type scale, line length, truncation, spacing rhythm, alignment, and
responsive fit. Text must not overlap, overflow, or look oversized inside compact
surfaces.

Color & Token Keeper:
Use the existing design tokens. Preserve dark mode, one warm amber signal, muted
status colors, and restrained surfaces. Do not introduce decorative gradients or
new accent families.

Component Stylist:
Choose familiar controls for each job: icons for tools, segmented controls for
modes, toggles for binary settings, menus for option sets, tabs for views, and
buttons for commands.

State Designer:
Design every state the surface can enter: loading, empty, running, partial,
failed, done, disabled, and manual attention. A failed worker is shown failed.

Polish Critic:
Cut decoration. Keep only changes that improve clarity, trust, speed, or fit
with the design system. Preserve product semantics.
```

### Conversion Studio

Specialist Design team.

Purpose:

```text
Improve a product/marketing surface so users understand the offer, trust it, and
know what to do next.
```

Default effort: High.

Best for:

- landing pages;
- pricing/product pages;
- onboarding;
- upgrade prompts;
- call-to-action flows.

Output:

```text
conversion board: hierarchy, offer clarity, trust/proof, CTA path, friction cuts
```

Workers:

| Skill | Prompt job | Preferred model policy |
| --- | --- | --- |
| Offer Clarity | Make the literal offer legible in the first viewport. | any ready |
| CTA Path | Inspect primary/secondary actions, button copy, placement, and follow-through. | design-capable model |
| Friction Hunter | Find hesitation, ambiguity, missing context, and form/control drag. | any ready |
| Trust Builder | Place proof, safety, local/privacy claims, testimonials, or evidence without clutter. | any ready |
| Mobile Scanner | Optimize for small-screen scan order and thumb flow. | design-capable model |
| Objection Finder | Name objections the screen must answer before the user acts. | strongest ready planner |

Use this team when the task is about hierarchy, trust, CTA placement, or
friction. If the task is words-first, route to a Copy team instead.

Skill prompt templates:

```text
Offer Clarity:
Make the literal offer legible. The first viewport should answer what this is,
who it is for, and why the user should care. Put value props in supporting copy,
not vague headlines.

CTA Path:
Inspect the primary and secondary action path: button copy, placement, visual
priority, follow-through, and dead ends. The user should know what happens next.

Friction Hunter:
Find hesitation points: missing context, overlong forms, unclear commitments,
buried proof, confusing labels, and choices that arrive too early.

Trust Builder:
Place evidence where it reduces risk: proof, safety copy, local/privacy claims,
testimonials, screenshots, or concrete examples. Do not add trust badges as
decoration.

Mobile Scanner:
Optimize for small-screen scan order and thumb flow. Ensure the product or offer
is visible early, text does not crowd controls, and the next section is hinted.

Objection Finder:
Name the objections the screen must answer before action: price, effort, risk,
credibility, setup, switching cost, privacy, and "why now."
```

### Radical Directions

Specialist Design team.

Purpose:

```text
Generate genuinely different design directions before the team converges too
early.
```

Default effort: Med.

Best for:

- greenfield surfaces;
- brand exploration;
- "show me options";
- escaping local maxima.

Output:

```text
option board: distinct directions, what each optimizes for, when to choose it
```

Workers:

| Skill | Prompt job | Preferred model policy |
| --- | --- | --- |
| Minimal Direction | The quietest functional version. Fewest elements, clearest path. | design-capable model |
| Bold Direction | Stronger contrast, larger gestures, clearer opinion, still usable. | design-capable model |
| Editorial Direction | Narrative hierarchy and explanatory flow for complex value props. | design-capable model |
| Operational Direction | Dense, utilitarian, repeat-use interface for power users. | design-capable or any ready |
| Native App Direction | macOS/iOS-native control feel, not web marketing composition. | design-capable model |
| Direction Critic | Keep options distinct. Reject synonym swaps and shallow style changes. | strongest ready planner |

Skill prompt templates:

```text
Minimal Direction:
Create the quietest functional direction. Fewer elements, clearer hierarchy,
less copy, and the shortest path to the user's decision.

Bold Direction:
Create a stronger, more opinionated direction with clearer contrast and larger
gestures while staying usable and inside the design system.

Editorial Direction:
Create a narrative direction for complex value props. Use sequencing,
explanation, examples, and proof to make the idea easier to understand.

Operational Direction:
Create a dense repeat-use direction for power users. Prioritize scanning,
comparison, predictable controls, and fast repeated action over decorative
composition.

Native App Direction:
Create the most macOS/iOS-native version. Use familiar controls, restrained
surfaces, stable layout, and local-app posture instead of web landing-page
patterns.

Direction Critic:
Keep the directions truly different. Reject shallow style swaps, name what each
direction optimizes for, and say when each should win.
```

### Usability Triage

Specialist Design team.

Purpose:

```text
Find why a surface feels confusing, slow, risky, or hard to repeat.
```

Default effort: Med.

Best for:

- dense app screens;
- settings/configuration;
- composer flow;
- run state surfaces;
- iOS remote control.

Output:

```text
usability triage: top friction points, severity, fix order, state/control changes
```

Workers:

| Skill | Prompt job | Preferred model policy |
| --- | --- | --- |
| Journey Mapper | Walk the user path step by step and name every decision point. | any ready |
| Control Ergonomics | Check whether each control matches the user's mental model. | design-capable model |
| Navigation Reviewer | Review wayfinding, backtracking, mode switching, and context loss. | any ready |
| Accessibility Reviewer | Check keyboard, focus, labels, contrast, target size, and reduced motion. | any ready |
| Cognitive Load Cutter | Remove choices, labels, or steps that do not earn their place. | strongest ready planner |
| State Feedback Reviewer | Make queued/running/done/failed/attention states obvious and honest. | any ready |

Skill prompt templates:

```text
Journey Mapper:
Walk the user's path step by step. Name every decision point, every place context
can be lost, and every place the user has to remember something.

Control Ergonomics:
Check whether each control matches the user's mental model. Use menus,
segmented controls, toggles, sliders, tabs, and buttons for the jobs they are
best at.

Navigation Reviewer:
Review wayfinding, mode switching, backtracking, selection state, and whether
the user can recover from the wrong turn without losing work.

Accessibility Reviewer:
Check keyboard access, focus order, screen-reader labels, contrast, target size,
motion, and cognitive load. Accessibility issues are product issues.

Cognitive Load Cutter:
Remove choices, labels, or steps that do not earn their place. Prefer visible
state and concrete verbs over explanatory text.

State Feedback Reviewer:
Make queued, running, partial, done, failed, timed out, disabled, and
needs-attention states obvious and honest. A failed worker is shown failed.
```

## Copy Team Interaction

Copy remains owned by `docs/phases/copy/README.md` and routed copy phase docs.
This doc does not replace copy type packs.

Shared rule:

```text
Copy teams use the same TeamPreset, Skill, Worker, Lane, and Effort model.
```

Copy examples:

```text
Copy -> Landing Page Team
Copy -> Launch Email Team
Copy -> Ads Team
Copy -> Objection Handling Team
```

Fan out composer rule:

```text
Copy -> team
```

Copy type is no longer a separate composer control in the Fan out picker. A copy
type pack materializes as one or more Copy teams. For CLI/slash compatibility,
`--lane copy --type landing-page` may resolve to `--team copy_landing_page` when
no explicit team is provided.

Minimum Copy teams before this phase is user-visible:

```text
copy_core
copy_landing_page
```

If those are not ready, the Copy lane must be disabled or clearly marked
"coming soon"; do not ship a peer lane that opens to an empty team list.

## CLI / MCP / API Impact

`TeamRequest` should carry:

```swift
question
lane
teamPresetId
type
context
waitSeconds
```

CLI:

```bash
alln team --lane build --team build_bug_hunt "Find why run history disappears."
alln team --lane design --team design_premium_polish --file prompt.md
alln team --lane copy --team copy_landing_page "Rewrite this hero."
alln team --lane copy --type landing-page "Rewrite this hero."  # sugar for copy_landing_page
alln team teams --lane build --json
```

Naming note:

- Keep `--preset` as a hidden/deprecated compatibility alias if needed.
- Prefer `--team` in new docs/help because the user is selecting a team.
- `team show` should accept `--lane` and `--team` later.
- `--team` and `--type` together are valid only when `type` matches the team's
  `typeTags`; otherwise reject before running.

MCP/local API must expose the same fields. No surface gets private team
selection semantics.

`alln team teams --lane build --json` should return a catalog summary, not full
prompt templates by default:

```json
{
  "schemaVersion": 1,
  "lane": "build",
  "teams": [
    {
      "id": "build_bug_hunt",
      "displayName": "Bug Hunt",
      "lane": "build",
      "outputKind": "bugPacket",
      "defaultEffort": "high",
      "builtIn": true,
      "isDefaultForLane": false,
      "workerCountByEffort": {"low": 4, "med": 7, "high": 9},
      "disabledReason": null
    }
  ]
}
```

Full team export/import and share links are out of scope for this phase. They
touch trust, provenance, and prompt-distribution concerns and need their own
small spec before shipping.

## TeamRunJSON Impact

`TeamRunJSON.teamRun` should include:

```text
lane
type
effort
teamPresetId
teamDisplayName
outputKind
```

Workers already include:

```text
skillId
skillName
modelId
modelName
instanceIndex
```

Required additions or validations:

- `skillName` must resolve to a user-facing name, not raw id only.
- `skillVersion` should be included or derivable from the run audit snapshot.
- Repeated model workers must keep distinct worker ids.
- `warnings` should include one-model self-fusion when relevant.
- `reproduceCommand` should include `--lane` and `--team`.
- Legacy `effort` may appear in old run records, but forward schemas should not
  use it as a team-shape control.
- `type` is null for Build/Design Fan out unless a future owning doc defines a
  type tag. Copy compatibility may populate it when type selected the team.
- `reproduceCommand` replays intent. The worker snapshot is the historical truth.

## Mac App Impact

Composer:

- Collapse Chat / Fan out / Execute into one visible mode control.
- When Fan out is selected, show lane controls.
- Fan out target chip shows team.
- Team picker filters by lane.
- Team picker shows worker/skill badges for the selected team.
- Enter sends chat unless the visible mode says otherwise and the user has
  explicitly armed that mode.

Settings:

- Add Team Library.
- Show Build / Design / Copy sections.
- Built-in teams are duplicate-to-edit.
- Custom teams can be created, edited, deleted, and made default.
- Team editor shows worker rows as `Skill | Model policy`.

Results:

- Show team name in the run header.
- Prefer `Build · Bug Hunt` in headers where space allows.
- Show worker rows as `Skill / Model`.
- Show one-model warning honestly when all workers resolved to one model.
- Show queued same-source workers honestly if admission serializes them.

## iOS Impact

iOS should use the same model:

```text
Chat -> worker
Fan out -> lane + team
Execute -> executor
```

The phone composer can remain compact:

```text
Fan out
Build / Bug Hunt
```

Tap target opens the same conceptual picker:

```text
Lane
Team
Effort
```

No team editing is required in the first iOS slice. iOS can link to "Edit on Mac"
or show read-only team details.

The Mac remains the team catalog owner. iOS receives team catalog snapshots
through the iOS transport/control-plane spine; it must not invent teams locally.
Read-only details should show worker skill names, model policies, effort
activation, and disabled reasons, not raw ids only.

## Auth / Privacy / Permission Impact

No new credentials or permissions are required for team selection itself.

Risk appears when a team targets:

- credentials;
- local network;
- Keychain;
- Full Disk Access;
- destructive session/process operations;
- dispatch/execute;
- cloud pairing/control paths.

Those risks stay governed by the owning feature docs and high-risk stops.
Security Review is a planning/review team; it does not grant permissions.

## Inference Bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Prompt -> lane | Composer/Core request | "copy" means Copy lane | Never infer lane for Fan out | Prompt says "button copy is bad"; app requires explicit Build/Design/Copy |
| Lane -> team | Team catalog | Every Build prompt uses Build Core | Use lane default only until user selects another team | Select Bug Hunt, run, assert `teamPresetId == build_bug_hunt` |
| Team -> models | Resolver | Team needs unique model per worker | Allow one ready model to fill many skill rows | One ready model resolves Bug Hunt High to multiple workers |
| Team -> skills | Composer | User edits skill rows in composer | Skill editing is settings-only | Composer picker has no worker-row editor |
| Effort -> estimate | UI/API | High means longer/costlier prediction | Effort is instruction bundle only | No runtime/cost estimate appears in labels/JSON |
| Same-source workers -> concurrency | Engine/admission | Five Opus workers start concurrently even when driver cannot support it | Admission caps or queues same-source workers | Five workers, cap two, assert three workers visibly queued |
| Type -> team | CLI/Core | `--type landing-page` and `--team build_bug_hunt` silently conflict | `--team` wins only when type tag matches; otherwise reject | Conflicting copy type/build team exits before run |

## Implementation Slices

### S00 - Core enums and preset metadata (legacy M1)

- Add `WorkLane`.
- Add `EffortLevel` with `low`, `med`, `high` (legacy M1; forward cleanup should
  replace user-facing team effort with named Team variants).
- Add `TeamOutputKind`, `TeamWorkerPurpose`, `TeamEffortPolicy`,
  `TeamSynthesisPolicy`, and `ModelSelectionPolicy`.
- Replace/extend team-catalog presets with lane, output kind, default effort,
  default-for-lane, type tags, purpose tags, effort policy, and synthesis policy.
- Add `minEffort`, `purpose`, `requiredCapabilityTags`, and `required` to team
  worker rows.
- Add default-per-lane integrity checks.
- Make `low|med|high` the generated CLI/JSON contract and update fixtures.
- Update Codable tests and fixtures.

### S01 - Skill catalog and model capabilities

- Add Core-owned `SkillCatalog` seeded with built-in skill definitions.
- Add skill metadata: id, display name, lane tags, purpose, template, built-in,
  version.
- Add model capability tags, lane tags, and strength rank metadata.
- Add deterministic fallback sorting.
- Snapshot skill id/name/version into runs.

### S02 - Team resolver with self-fusion

- Resolve preferred models against ready bench.
- Support capability-filtered fallback policies.
- Allow multiple workers on one ready model with different skills.
- Split answer/review/plan stages.
- Emit warnings for one-model self-fusion.
- Respect utilization/admission caps for same-source workers.
- Validate synthetic plan/output writer resolution.
- Unit-test Bug Hunt High with one ready model.

### S03 - Built-in team catalog

- Add built-in Build teams from this doc.
- Add built-in Design teams from this doc.
- Add minimum Copy parity ids or keep Copy disabled until copy teams exist.
- Add duplicate-to-custom path in the store or app model.
- Add deterministic IDs:

```text
build_core
build_bug_hunt
build_gui_bug_hunt
build_security_review
build_architecture_pressure_test
build_release_proof
design_core
design_premium_polish
design_conversion_studio
design_radical_directions
design_usability_triage
copy_core
copy_landing_page
```

### S04 - CLI request shape

- Add `lane`, `team`, and `effort` to `TeamRequest`.
- Wire CLI flags to team resolution, not only JSON projection.
- Add `alln team teams --lane <lane> --json` or equivalent generated registry
  command when contract-ready.
- Define `--type` as Copy-only sugar/default-team routing when no explicit team
  is provided.
- Update `TeamRunJSON` reproduce command.

### S05 - Mac composer fan-out picker (forward simplified)

- Collapse send mode control.
- Fan out shows Build / Design / Copy.
- Fan out target chip shows team.
- Team picker filters by lane.
- Team picker shows worker/skill badges by team.
- Run header shows selected team.

### S06 - Team library settings

- Add Team Library surface.
- Duplicate built-ins.
- Create/edit/delete custom teams.
- Set default team per lane.
- Validate lane, output kind, worker stage, min effort, skill, fallback, and
  default-lane invariants.

### S07 - iOS read-only picker

- Show Fan out lane/team selector.
- Use Mac-owned team catalog.
- No mobile team editing in first slice.

## Works Tests

### Works Test A - one CLI still runs a team

Setup:

```text
Only Opus is ready.
Build lane has built-in Bug Hunt team.
```

Gesture:

```text
Composer -> Fan out -> Build -> Bug Hunt -> High -> Run
```

Assertions:

- Run starts.
- `teamPresetId == build_bug_hunt`.
- `effort == high`.
- Exactly nine answer/review workers resolve:
  `bug_reproducer`, `truth_owner_mapper`, `correct_fix_planner`,
  `regression_guard`, `trace_mapper`, `state_skeptic`,
  `change_impact_reviewer`, `user_impact_narrator`,
  `contrarian_root_cause`.
- One synthetic plan/output worker resolves with `skillId == bug_packet_writer`.
- All workers may have `modelId == model_opus`.
- Workers have distinct `skillId`s.
- Worker ids have distinct `instanceIndex`.
- UI says multiple workers / one model truthfully.
- No error says "not enough models."
- Warning says same-source workers may queue under admission.

### Works Test B - lane is explicit

Setup:

```text
Prompt: "The copy in this signup button feels wrong."
```

Gesture:

```text
Select Fan out.
```

Assertions:

- UI does not auto-select Copy because of the word "copy."
- User must choose Build / Design / Copy or accept a visible default.
- Changing lane changes the visible team list.

### Works Test C - composer selects, settings configures

Gesture:

```text
Composer -> Fan out -> Build team picker
```

Assertions:

- Picker can choose team and effort.
- Picker cannot edit worker skill rows.
- `Customize teams...` opens the Team Library.

### Works Test D - built-in duplicate customization

Gesture:

```text
Settings -> Team Library -> Build -> Bug Hunt -> Duplicate
Rename to "Mike's Bug Hunt"
Change one worker fallback
Save
Composer -> Fan out -> Build
```

Assertions:

- Custom team appears under Build.
- Built-in Bug Hunt remains unchanged.
- Custom team can become default for Build.

### Works Test E - fallback policy is deterministic

Setup:

```text
Bug Hunt prefers Codex for Regression Guard.
Codex is unavailable.
Opus is ready and matches fallback policy.
```

Assertions:

- Regression Guard resolves to Opus.
- Warning names the fallback.
- The run snapshot records actual `modelId == model_opus`.

### Works Test F - optional rows disable without lying

Setup:

```text
High effort team has one optional image/design row with no capable ready model.
Required rows can resolve.
```

Assertions:

- Run starts.
- Disabled row appears with reason.
- Output does not pretend the disabled worker contributed.

### Works Test G - plan writer failure blocks run

Setup:

```text
Answer workers can resolve.
Synthetic plan/output writer cannot resolve.
```

Assertions:

- Run does not start.
- Error says plan/output writer cannot resolve.
- No partial answer run is represented as successful.

### Works Test H - Copy type routes to team

Gesture:

```text
alln team --lane copy --type landing-page "Rewrite this hero."
```

Assertions:

- Request resolves to `teamPresetId == copy_landing_page`.
- `teamRun.type == "landing-page"`.
- Reproduce command includes `--team copy_landing_page`.

### Works Test I - built-in immutability

Gesture:

```text
Duplicate Bug Hunt, edit one worker row, save.
```

Assertions:

- Built-in `build_bug_hunt` is unchanged.
- Custom team receives a new id.
- Built-in id remains stable in generated docs and history.

### Works Test J - admission caps same-source workers

Setup:

```text
Bug Hunt High resolves ten workers to Opus including synthetic writer.
Admission allows two concurrent Opus attempts.
```

Assertions:

- Two Opus workers run.
- Remaining Opus workers are queued or pending with a sourced admission reason.
- UI and NDJSON never imply all workers are running concurrently.

## Proof Commands

Core/package proof:

```bash
swift test
```

App proof, once Xcode targets cover the new surfaces:

```bash
xcodebuild test -scheme AllnighterMac
xcodebuild test -scheme AllnighteriOS
```

Missing proof until implementation:

- no TeamCatalog fixtures yet;
- no one-model self-fusion resolver test yet;
- no Mac composer inspection/snapshot test yet;
- no generated CLI registry for `--team` yet.

## Done When

- Fan out never shows a bare model target.
- Fan out visibly requires Build / Design / Copy.
- Team picker lists lane-scoped built-in and custom teams.
- Users can create custom teams outside the composer.
- Effort activation is machine-readable for every shipped team.
- Built-in skill prompts live in the Core skill catalog with versions.
- Model fallback uses deterministic capability tags and strength rank.
- Team output kind drives synthesis/rendering.
- Answer, review, and synthetic plan/output stages are explicit in run snapshots.
- Build ships with Build Core, Bug Hunt, GUI Bug Hunt, Security Review,
  Architecture Pressure Test, and Release Proof.
- Design ships with Design Core, Premium Polish, Conversion Studio, Radical
  Directions, and Usability Triage.
- Copy is either backed by at least `copy_core` and `copy_landing_page` or is not
  shown as an enabled peer lane.
- One connected CLI can run a multi-worker team through different skills.
- Same-source workers obey admission caps and show queued/running truthfully.
- Results show worker truth: skill, model, failure state, and repeated model
  usage.
- JSON and CLI may still emit legacy `low|med|high` for M1 runs, but forward
  Deploy Teams should not expose it as a team-shape control.
- `--team` is the public Fan out selector; `--type` is Copy-only sugar or
  metadata, never a competing selector.
- CLI/GUI/iOS/MCP share the same lane/team contract.
