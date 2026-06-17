# Work Order Team Model

Status: Active language contract for post-MVP specs
Owner: Founder + Shared Core + Mac
Updated: 2026-06-16

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
Project Manager = the default chat/proposal/verification agent inside a Project
Source = how Allnighter reaches a model (internal / setup detail)
Bench  = the models the user has available
Model  = the AI identity users recognize: Opus, Sonnet, Grok, Gemini, etc.
Skill  = what hat/instruction a model wears
Worker = one model wearing one skill for this run
Team   = the worker lineup for a work order
Lane   = Build / Design / Copy
Type   = optional subtype metadata inside a lane; not a Fan out selector
Effort = Low / Med / High bundle for how big/deep the team runs
TeamPreset = saved lane team definition with effort defaults
```

## Definitions

| Term | Meaning |
| --- | --- |
| **Project** | The durable local repo/folder context where work happens. Projects own the selected root, thread grouping, run/pending/proposal scope, and default Project Manager chat. |
| **Project Manager** | The default chat identity inside a Project. It can answer, propose, verify, and route approved work, but it is not a separate lane and it does not auto-execute unapproved work. |
| **Source** | How Allnighter reaches a model: Claude Code, Codex CLI, Gemini CLI, Grok, a local runtime. Mostly setup/internal language. |
| **Bench** | The user's available models. |
| **Model** | The AI identity users already recognize: Opus 4.8, Sonnet, Grok, Gemini, ChatGPT image, etc. A model sits on the Bench. |
| **Skill** | A reusable prompt profile or hat: first-principles reviewer, minimal designer, offer strategist, proof skeptic. |
| **Worker** | One `model + skill` assignment for this run. A model can become multiple workers by wearing different skills. |
| **Team** | The worker lineup for this work order. This is the user-facing word for the lineup that runs. |
| **Lane** | The three peer creation lanes: Build, Design, Copy. |
| **Type** | Optional subtype metadata inside a lane. Type is not a primary Fan out selector. Copy may use type as compatibility/default-team routing, e.g. `landing-page` -> `copy_landing_page`, when owned by Copy docs. |
| **Effort** | Low / Med / High. Controls worker count, review depth, patience, and later research. Never a forecast. |
| **TeamPreset** | Core type for a saved built-in or custom team: lane, output kind, default effort, worker lineup, and synthesis/review policy. Product UI says Team. |

Shortcut:

```text
Model at rest. Model at work.
```

The product promise is not "configure a lineup." It is "turn the models you
already pay for into a working team."

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

## Send Modes

The product primitive is send. Chat, Ask Team, Work Order, Dispatch, and Execute
are send modes with different payloads and workers.

Rules:

- Enter sends chat to the resolved worker. Enter never builds.
- Dispatch/Execute is explicit because the user chooses that send mode from an
  editable work order. Do not add a second confirmation ceremony.
- Reveal-only is another send mode: write/show the exact handoff without
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
Fan out -> Lane -> Team -> Effort -> Prompt -> Run
```

Do not add a separate Type picker to Fan out. Copy type packs materialize as Copy
teams. CLI or slash-command compatibility may still accept type and resolve it to
a team when no explicit team was selected.

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

`docs/phases/Fanout_Team_Catalog.md` owns the forward phase for lane-scoped
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
  Effort: High
  Team: First Principles on Opus, Skeptic on Sonnet, Maintainer on Codex

Design
  Type metadata: Redesign
  Effort: Med
  Team: Minimal Designer on Grok Imagine, Bold Designer on ChatGPT image

Copy
  Type metadata: Landing page
  Effort: Med
  Team: Offer Strategist on Opus, Objection Hunter on Grok, Direct Response on Sonnet
```

Copy does **not** have multiple lanes. It has multiple types/playbooks inside the
Copy lane.

## UX Laws

- Default lineup first. Custom lineup second. Skill library in settings.
- Work-order creation stays prompt-first.
- Effort changes range, rigor, review, and later research. It does not create a
  new lane.
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
- Work-order CLI commands (`alln work`, later `alln work from latest`) create or
  link thread turns. They must not introduce a parallel work-order store.

## Designer Handoff

Main composer:

```text
New work order

[ Build ] [ Design ] [ Copy ]

Team
[ Landing Page Team ]

Effort
[ Low ] [ Med ] [ High ]

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
