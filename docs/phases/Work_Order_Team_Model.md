# Work Order Team Model

Status: Active language contract for post-MVP specs
Owner: Founder + Shared Core + Mac
Updated: 2026-06-15

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
Source = how Allnighter reaches a model (internal / setup detail)
Bench  = the models the user has available
Model  = the AI identity users recognize: Opus, Sonnet, Grok, Gemini, etc.
Skill  = what hat/instruction a model wears
Worker = one model wearing one skill for this run
Team   = the worker lineup for a work order
Lane   = Build / Design / Copy
Type   = subtype inside a lane
Effort = how big/deep the team runs
Preset = saved type + effort + team defaults
```

## Definitions

| Term | Meaning |
| --- | --- |
| **Source** | How Allnighter reaches a model: Claude Code, Codex CLI, Gemini CLI, Grok, a local runtime. Mostly setup/internal language. |
| **Bench** | The user's available models. |
| **Model** | The AI identity users already recognize: Opus 4.8, Sonnet, Grok, Gemini, ChatGPT image, etc. A model sits on the Bench. |
| **Skill** | A reusable prompt profile or hat: first-principles reviewer, minimal designer, offer strategist, proof skeptic. |
| **Worker** | One `model + skill` assignment for this run. A model can become multiple workers by wearing different skills. |
| **Team** | The worker lineup for this work order. This is the user-facing word for the lineup that runs. |
| **Lane** | The three peer creation lanes: Build, Design, Copy. |
| **Type** | A subtype inside a lane, e.g. Copy -> Landing page, Email, Ads; Design -> Redesign, Greenfield; Build -> Feature, Bug fix. |
| **Effort** | Quick / Standard / Deep. Controls worker count, review depth, patience, and later research. Never a forecast. |
| **Preset** | A saved default: lane + type + effort + team lineup + enabled review skills. |

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

- A lane/type ships with a **default team** so prompt-only runs work instantly.
- Advanced users can customize the team: each row is one worker, shown as
  `skill + model`.

The main composer must stay simple:

```text
Lane -> Prompt -> Type when needed -> Effort -> Run
```

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

Milestone 1 does not need standalone skill-library CRUD. Built-in and preset
embedded skills are enough if `team show`, `team --json`, and the GUI snapshot
resolve every worker row to `Skill | Model`.

## Lane / Type Examples

```text
Build
  Type: Feature
  Effort: Deep
  Team: First Principles on Opus, Skeptic on Sonnet, Maintainer on Codex

Design
  Type: Redesign
  Effort: Standard
  Team: Minimal Designer on Grok Imagine, Bold Designer on ChatGPT image

Copy
  Type: Landing page
  Effort: Standard
  Team: Offer Strategist on Opus, Objection Hunter on Grok, Direct Response on Sonnet
```

Copy does **not** have multiple lanes. It has multiple types/playbooks inside the
Copy lane.

## UX Laws

- Default lineup first. Custom lineup second. Skill library in settings.
- Work-order creation stays prompt-first.
- Effort changes range, rigor, review, and later research. It does not create a
  new lane.
- A fourth peer lane requires a new substrate or output class. Otherwise it is a
  type, skill, preset, or thread turn inside Build / Design / Copy.
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

Prompt
[ Rewrite my pricing page so solo founders actually convert. ]

Copy type
[ Auto ] [ Landing page ]

Effort
[ Quick ] [ Standard ] [ Deep ]

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
