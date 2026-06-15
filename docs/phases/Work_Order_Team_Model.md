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
Model at rest. Worker at work.
```

The product promise is not "configure a lineup." It is "turn the models you
already pay for into a working team."

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
| Build stance: `skeptic` | Build skill: Skeptic |
| Review lens: `security_privacy` | Build/review skill: Security & Privacy Reviewer |
| Design persona: `minimal` | Design skill: Minimal Designer |
| Copy role: `objection hunter` | Copy skill: Objection Hunter |

Product and design docs should explain implementation shapes through Skill,
Model, Worker, and Team. Implementation names that expose old product language
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
- Worker count and output count are different facts. A Copy team may have six
  workers and produce four versions because some workers review instead of
  generate.

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
