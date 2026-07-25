# Work Order Team Model

> **Doc title is legacy naming.** "Work Order" as a product ceremony (propose →
> approve → dispatch → verify, a separate Project Manager identity) was retired
> by `Unified_Run_Model.md` (code SSOT `RunService.swift`, `RunRecord`); this doc
> was swept 2026-07-24 to drop that vocabulary from its body. The Source/Bench/
> Model/Skill/Worker/Team/Lane/Type word list below is still current.

Status: Active language contract for post-MVP specs
Owner: Founder + Shared Core + Mac
Updated: 2026-07-24

## Purpose

This doc fixes the product language for how Allnighter turns a simple work order
into an expert team without making the composer feel like a form.

It is designer-facing and implementation-facing. Use this vocabulary in new phase
docs, GUI briefs, and copy.

Old public words are not grandfathered. While Allnighter has no migration burden,
new work must use this language and cleanup work must remove the old language
rather than alias it.

## Canonical Model

```text
Project = the local repo/folder floor where work happens
Chat = the default turn inside a Project — a run of the Default Team, no
        separate propose/approve identity (code SSOT `RunService.swift`)
Source = how Allnighter reaches a model (internal / setup detail)
Execution source = one source/driver that owns a mutating execution run
Bench  = the models the user has available
Model  = the AI identity users recognize: Opus, Sonnet, Grok, Gemini, etc.
Skill  = what hat/instruction a model wears
Worker = one model wearing one skill for this run
Team   = the worker lineup for a work order
Lane   = Build / Design / Copy
Type   = optional subtype metadata inside a lane; not a Fan out selector
Reasoning effort = optional provider/model reasoning-depth setting
TeamPreset = saved lane team definition
```

## Definitions

| Term | Meaning |
| --- | --- |
| **Project** | The durable local repo/folder context where work happens. Projects own the selected root, thread grouping, run/pending scope, and the default chat. |
| **Default chat** | The default turn inside a Project: a run of the Default Team (one worker + its optional preset) in the repo root. It is not a separate surface, service, or identity — colloquially "the chat that knows the repo." There is no propose/approve/verify step; the agent reads and writes as the message implies (code SSOT `RunService.swift`). |
| **Source** | How Allnighter reaches a model: Claude Code, Codex CLI, Gemini CLI, Grok, a local runtime. Mostly setup/internal language. |
| **Execution source** | The single source/driver that owns a mutating or `execute` posture run. Judgment teams may mix sources; execution teams must resolve to one execution source before any worker spawns. |
| **Bench** | The user's available models. |
| **Model** | The AI identity users already recognize: Opus 4.8, Sonnet, Grok, Gemini, ChatGPT image, etc. A model sits on the Bench. |
| **Skill** | A reusable prompt profile or hat: first-principles reviewer, minimal designer, offer strategist, proof skeptic. |
| **Worker** | One `model + skill` assignment for this run. A model can become multiple workers by wearing different skills. |
| **Team** | The worker lineup for this work order. This is the user-facing word for the lineup that runs. |
| **Lane** | The three peer creation lanes: Build, Design, Copy. |
| **Type** | Optional subtype metadata inside a lane. Type is not a primary Fan out selector. Copy may use type as compatibility/default-team routing, e.g. `landing-page` -> `copy_landing_page`, when owned by Copy docs. |
| **Reasoning effort** | Optional provider/model reasoning-depth setting. It may map to values such as low/medium/high when the selected model supports them. It must not change team lineup, output contract, review posture, scheduling, runtime promise, quota estimate, or product flavor. |
| **TeamPreset** | Core type for a saved built-in or custom team: lane, output kind, worker lineup, and synthesis/review policy. Product UI says Team. |

Shortcut:

```text
Model at rest. Model at work.
```

The product promise is not "configure a lineup." It is "turn the models you
already pay for into a working team."

## Execution Source Gate

Allnighter separates judgment from execution:

```text
Judgment can be mixed-source.
Execution is single-source.
```

Teams with non-mutating `scout`, `propose`, or `review` posture may resolve to
multiple sources. That is the point of the judgment layer: different models,
skills, sources, blind spots, and tool affordances harden the spec before the
work is made real.

Teams with `posture == execute` or `mutating == true` must resolve to exactly one
`sourceId`/driver before any worker spawns. `modelId` is not enough; the gate is
source/driver coherence: one CLI runtime boundary, permission posture, Project
readiness contract, working directory, and mutating execution owner.

Rules:

- Mixed-source judgment teams may return plans, options, review findings,
  Insights, and proof recommendations.
- Mixed-source judgment teams must not write Project files, change external
  state, or start mutating subprocess work.
- Mutating/`execute` teams are rejected before spawn when resolved workers cross
  sources.
- Allnighter must not silently pick the first ready source, flip the team to
  non-mutating, create hidden isolated workspaces, or start multiple CLIs and
  call that one execution team.
- Built-in execution teams are source-scoped variants; custom execution teams
  cannot save when worker rows resolve across multiple sources.
- Mutating runs name one execution owner (`targetSourceId`, `targetAgent`,
  `targetWorkerId`, and/or `executionTeamId` as applicable).
- The shared blocker is `EXECUTION_TEAM_MIXED_SOURCES`.

The historical implementation phase and proof are archived at
`docs/archive/phases/Execution_Team_Source_Gate.md`; this section is the active
product/model authority.

## Multiple Workers Per Model

One model may appear more than once in a team. That is not a special public
concept; it is just multiple workers.

Preferred cases:

```text
Opus as First Principles
Opus as Skeptic
Opus as Maintainer
```

Rare case:

```text
Opus as Skeptic
Opus as Skeptic
```

When the same model runs the same skill more than once, use an internal
`instanceIndex` and a display suffix such as `Opus / Skeptic A` and
`Opus / Skeptic B`. Do not introduce another product noun for this. The row is
still a worker.

## Plan Writer

For v1, the plan writer is a designated worker in the team snapshot:

```text
Model: Opus 4.8
Skill: Plan Writer
Worker: Opus 4.8 as Plan Writer
```

The plan stage may run after the parallel answers, but the product still shows a
worker doing the job. JSON uses `planWriterWorkerId`; UI copy may say "Plan
written by Opus 4.8." Do not expose `plan writer` or `plan writer` as product nouns.

For lane-scoped team catalog runs, Core may resolve this as a synthetic
plan/output worker from the team's synthesis policy. It is still included in the
run snapshot and still follows the rule: models sit on the Bench, workers do
jobs.

This keeps the rule simple:

```text
Models sit on the Bench. Workers do jobs.
```

## One-Worker Chat

Thread chat uses the same vocabulary. A chat turn resolves to one **worker**:
the chosen model wearing the default Chat skill or a lane/preset skill.

```text
Claude Opus on the Bench
-> Opus as Chat Partner for this turn
```

It is not a full team run, but it is also not a bare model invocation in product
language. The chip can display `Opus / Chat` or a friendlier equivalent. The
implementation may keep legacy `WorkerChatCoordinator` until the rename slice,
but the durable product truth is still model + skill -> worker.

## Send

There is one send primitive: a run is a message + optional preset + worker
selection, executed in the repo root (code SSOT `RunService.run`; see
`RunRecord`/`TeamRunJSON`). There is no separate "Chat mode" or "Execute mode",
and no propose/approve/dispatch/verify ceremony between the message and the
run — read vs write is the agent's call, not a user toggle.

Rules:

- Enter sends the message to the resolved worker. Enter never builds a
  separate confirmation step.
- A mutating (execute) team resolves to one worker and runs; it is never
  silently converted to research/dry-run output, and it is never gated behind
  a second confirmation ceremony.
- Reveal-only is another send shape: write/show the exact handoff without
  invoking the worker.
- Safety belongs in prerequisites and honest labels: trusted device/client,
  working directory, Doctor/admission state, permission posture, and visible
  boundary copy.
- Separate approvals are reserved for separate risks: pairing a new device,
  enabling a new MCP/local API client, changing privacy/permission posture,
  killing sessions, or destructive cleanup.

## One Primitive, Many Old Names

Old docs used several words for the same underlying idea:

```text
stance
persona
lens
role
hat
prompt profile
```

The product word is **Skill**.

Examples:

| Old wording | New product framing |
| --- | --- |
| Build skillId: `skeptic` | Build skill: Skeptic |
| Review lens: `security_privacy` | Build/review skill: Security & Privacy Reviewer |
| Design persona: `minimal` | Design skill: Minimal Designer |
| Copy role: `objection hunter` | Copy skill: Objection Hunter |

Product and design docs should explain implementation shapes through Skill,
Model, Model, and Team. Implementation names that expose old product language
should be renamed before the next public surface depends on them. Temporary
internal names are acceptable only inside a bounded cleanup slice; they are not a
compatibility promise.

## Default Lineup vs Custom Team

Both are true:

- Each lane ships with a **default team** so prompt-only runs work instantly.
  Copy type compatibility may route to a type-specific Copy team.
- Advanced users can customize the team: each row is one worker, shown as
  `skill + model`.
- Every built-in and custom team belongs to exactly one lane. There are no shared
  teams or multi-lane teams.
- Users can create multiple custom teams per lane. A Security Review or Bug Hunt
  team is a Build team, not a new lane.
- A team may run with one ready model by assigning that model to multiple workers
  with different skills. Show it truthfully as multiple workers on one model.

The main composer must stay simple:

```text
Fan out -> Lane -> Team -> Prompt -> Run
```

Do not add a separate Type picker to Fan out. Copy type packs materialize as Copy
teams. CLI or slash-command compatibility may still accept type and resolve it to
a team when no explicit team was selected.

Do not use a generic Low/Med/High team-depth toggle as a second hidden team
picker. If depth changes worker count, review policy, research posture, output
shape, or proof bar, make it a different Team:

```text
Bug Hunt Lite
Bug Hunt
Bug Hunt Exterminator
```

Reasoning effort belongs at the model/worker layer only when the provider exposes
that control. GUI may present it inside advanced model/worker configuration; it
must not be the primary Deploy Team or Fan out control.

Team customization is one click deeper:

```text
Customize team

Skill                  Model
Offer strategist       Claude Opus
Objection hunter       Grok
Direct-response        Sonnet
Proof skeptic          Gemini
```

Do not put team customization in the primary path.

`docs/archive/phases/Team_Catalog.md` owns the forward phase for lane-scoped
custom teams, built-in Build/Design team packs, and the composer picker.

## Skill Library

The skill library is global and lane-tagged, not physically siloed.

Why:

- Some skills cross lanes: Contrarian, Proof Skeptic, Clarity Editor, Brand Voice.
- Built-in skills can be duplicated and edited without forking model setup.
- A saved preset can reuse the same skill across lanes.

Skill metadata:

```text
id
displayName
laneTags: [Build | Design | Copy]
typeTags: optional subtype tags
template
builtIn
version
```

The Fan out team catalog requires a Core-owned skill catalog so built-in team
prompts have one source of truth. Full standalone skill-library CRUD can stage
later, but built-in skills, custom skill copies, and run snapshots must resolve
every worker row to `Skill | Model` plus skill version.

## Lane / Type Examples

```text
Build
  Type metadata: Feature
  Team: Bug Hunt Exterminator
  Workers: First Principles on Opus, Skeptic on Sonnet, Maintainer on Codex

Design
  Type metadata: Redesign
  Team: Premium Polish
  Workers: Minimal Designer on Grok Imagine, Bold Designer on ChatGPT image

Copy
  Type metadata: Landing page
  Team: Landing Page Team
  Workers: Offer Strategist on Opus, Objection Hunter on Grok, Direct Response on Sonnet
```

Copy does **not** have multiple lanes. It has multiple types/playbooks inside the
Copy lane.

## UX Laws

- Default lineup first. Custom lineup second. Skill library in settings.
- Work-order creation stays prompt-first.
- Team selection changes range, rigor, review, and later research. Do not hide
  those differences behind a generic effort toggle.
- Reasoning effort is optional model/provider configuration, not a product-level
  team-depth control.
- Fan out never infers Build / Design / Copy from prompt prose. The lane is an
  explicit user choice.
- Fan out shows a team target, not a model target.
- Fan out uses Team as the routing unit. Type is metadata or compatibility sugar,
  not a competing selector.
- A fourth peer lane requires a new substrate or output class. Otherwise it is a
  type metadata, skill, team, or thread turn inside Build / Design / Copy.
- Model availability filters the bench. Skill compatibility filters the model
  dropdown.
- Never call a model on the Bench a worker. Never call a team row a model. The
  row is the worker; its visible attributes are Skill and Model.
- Model count and output count are different facts. A Copy team may have six
  workers and produce four versions because some workers review instead of
  generate.
- Public JSON and CLI output must follow the same model. Use `models`, `workers`,
  `teamRun`, `workerAnswers`, `stages`, and `plan`; do not leak legacy run words
  into new machine-readable contracts.
- The CLI has one run entrypoint, `alln run` (message + optional preset +
  worker, against a project root). There is no parallel work-order store or
  ceremony verb set.

## Designer Handoff

Main composer:

```text
New work order

[ Build ] [ Design ] [ Copy ]

Team
[ Landing Page Team ]

Prompt
[ Rewrite my pricing page so solo founders actually convert. ]

4 versions - landing page experts

[ Run copy board ]
```

Advanced drawer:

```text
Team

Skill                  Model
Offer strategist       Claude Opus
Objection hunter       Grok
Direct-response        Sonnet
Proof skeptic          Gemini

[ + Add worker ] [ Save as preset ]
```

Settings/library:

```text
Skills

Build
Design
Copy
Shared
```
