# Work Order Team Model

Status: Draft language contract for post-MVP specs
Owner: Founder + Shared Core + Mac
Updated: 2026-06-15

## Purpose

This doc fixes the product language for how Allnighter turns a simple work order
into an expert team without making the composer feel like a form.

It is designer-facing and implementation-facing. Use this vocabulary in new phase
docs, GUI briefs, and copy.

## Canonical Model

```text
Bench  = who the user has available
Skill  = what hat/instruction a worker wears
Seat   = one worker wearing one skill
Team   = the seat lineup for a work order
Lane   = Build / Design / Copy
Type   = subtype inside a lane
Effort = how big/deep the team runs
Preset = saved type + effort + team defaults
```

## Definitions

| Term | Meaning |
| --- | --- |
| **Bench** | The user's available workers: Claude/Opus, Grok, Sonnet, Codex, Gemini, image engines, etc. |
| **Skill** | A reusable prompt profile or hat: first-principles reviewer, minimal designer, offer strategist, proof skeptic. |
| **Seat** | One `worker + skill` assignment. A worker may fill several seats with different skills. |
| **Team** | The seat lineup for this work order. User-facing synonym: team. Internal docs may still say council/panel where existing contracts require it. |
| **Lane** | The three peer creation lanes: Build, Design, Copy. |
| **Type** | A subtype inside a lane, e.g. Copy -> Landing page, Email, Ads; Design -> Redesign, Greenfield; Build -> Feature, Bug fix. |
| **Effort** | Quick / Standard / Deep. Controls seat count, review depth, patience, and later research. Never a forecast. |
| **Preset** | A saved default: lane + type + effort + team lineup + enabled review skills. |

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

Implementation may keep type names such as `PromptProfile`, `PanelSeatSpec`, and
`StageBinding` where already specified. Product and design docs should explain
them through Skill and Seat.

## Default Lineup vs Custom Team

Both are true:

- A lane/type ships with a **default team** so prompt-only runs work instantly.
- Advanced users can customize the team: each row is `worker` wearing `skill`.

The main composer must stay simple:

```text
Lane -> Prompt -> Type when needed -> Effort -> Run
```

Team customization is one click deeper:

```text
Customize team

Skill                  Worker
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
- Built-in skills can be duplicated and edited without forking worker setup.
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
  Team: Opus + First Principles, Sonnet + Skeptic, Codex + Maintainer

Design
  Type: Redesign
  Effort: Standard
  Team: Grok Imagine + Minimal Designer, ChatGPT image + Bold Designer

Copy
  Type: Landing page
  Effort: Standard
  Team: Opus + Offer Strategist, Grok + Objection Hunter, Sonnet + Direct Response
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
- Worker availability filters the bench. Skill compatibility filters the skill
  dropdown.

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

Skill                  Worker
Offer strategist       Claude Opus
Objection hunter       Grok
Direct-response        Sonnet
Proof skeptic          Gemini

[ + Add seat ] [ Save as preset ]
```

Settings/library:

```text
Skills

Build
Design
Copy
Shared
```

