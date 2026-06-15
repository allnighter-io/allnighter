# 00 - Copy MVP

Status: Draft
Owner: Founder + Shared Core + Mac
Updated: 2026-06-15

## Founder Intent

Add the Copy lane without making work-order creation heavier than Claude or
Cursor. The required input remains one prompt. Copy type and effort are fast
routing controls, not a form.

## Product Value

The first Copy slice proves the new lane with one revenue-near job:

> **A prompt in. Several landing-page directions out. Pick the one that should
> ship.**

Landing page optimization is the right first slice because it is common, valuable,
and structurally different from generic writing: it needs positioning, objections,
proof, CTA hierarchy, and conversion clarity.

The user-facing claim is **not** "this will convert." Allnighter cannot prove that
before the market responds. The claim is: landing-page options are expert-shaped,
objection-aware, proof-checked, and ready for a founder to judge.

## Trusted Workflow Slice

```text
New work order -> Copy
or
/copy landing

Prompt:
"Rewrite my pricing page so solo founders actually convert."

Effort:
Standard

Run copy board
-> several landing-page versions appear side by side
-> user picks one
-> copy pack is saved/exported
```

## Non-Goals

- No long intake form.
- No required customer/avatar/proof fields before the run.
- No generic "write anything" lane as the quality bar.
- No auto-publish or external email/ad account integration.
- No unsupported copy types pretending to be expert packs.
- No predicted runtime, cost, quota burn, or difficulty.
- No public web research in C0.
- No hidden repo scan or hidden use of private product context.
- No Allnighter-owned code edits or AST/localization injection.

## Current State

- `docs/mvp/` owns the built team-run and design-board substrate: legacy worker
  calls, stage outputs, board-style option selection, and run artifacts.
- `docs/phases/Work_Order_Team_Model.md` owns the product vocabulary for bench,
  model, skill, worker, team, lane, type, effort, and preset.
- `docs/phases/Utilization_Admission_Control.md` already defines Effort as a user
  instruction, not an estimate.
- `Packages/AllnighterCore/Sources/AllnighterCore/WorkOrder.swift` already has a
  prediction-free work-order summary helper for team-run and design shapes.
- `ThreadTurnKind` has `design_board`, but not yet `copy_board`.

## Truth Owner

`AllnighterCore` owns durable semantics:

- work kind: build, design, copy;
- effort: quick, standard, deep;
- copy type: auto, landing_page, later channel types;
- copy skill suite and default team lineup;
- copy board payload and chosen copy;
- generated artifact paths.

Prompt prose may shape copy quality. It must not be the only owner of the lane's
semantics.

## New Semantic Rules

### 1. Work kind is explicit

The composer exposes:

```text
Build | Design | Copy
```

The app may infer a kind from slash commands or the prompt, but there is no silent
mode switch. The selected chip is visible before run.

### 2. Prompt is the only required input

Copy MVP must run from:

```text
/copy landing
Rewrite my pricing page so solo founders actually convert.
```

Optional context may improve the output, but missing context cannot block the
first run.

Optional context appears as chips or attachments:

```text
Draft | Customer | Proof | Brand voice
```

`URL` is a future source chip unless the implemented slice includes explicit
public-page fetching. C0 must not imply live-page research if it does not actually
fetch and source-save the page.

### 3. Copy type routes the team

MVP quality-gates:

```text
Auto
Landing page
```

`Auto` may pick `Landing page` when the prompt clearly names a page, pricing page,
homepage, website copy, waitlist page, or product page. If the app is unsure, it
keeps `Auto` and uses the landing-page pack only after the user confirms.

Do not show future types as active choices until their packs exist. If future
chips are shown for product direction, they must be disabled or marked not ready.

`Copy type` is not a sub-lane. It selects the Copy skill suite, output shape, and
default team lineup.

### 4. Effort changes work shape

UI labels:

```text
Quick | Standard | Deep
```

Copy MVP mapping:

| Effort | Work shape |
| --- | --- |
| Quick | 2 versions, no review pass by default |
| Standard | 4 versions, light objection/proof pressure-test |
| Deep | 6 versions, objection/proof review, no public web research in C0 |

Effort never predicts time, cost, quota, or difficulty.

### 5. The board comes first

Like Design, the first truth surface is a board of options. No AI winner appears
before the user sees the copy.

Each option should show:

- angle name;
- hero headline and subhead;
- CTA;
- first-section rewrite;
- why this direction exists, in one short line.
- objection or proof focus.

Four versions of the same strategy with different wording is a failed board. The
MVP generation skills must create distinct positioning bets.

### 6. Pick creates the copy pack

After the user picks a version, Allnighter renders a copy pack deterministically
from the picked option's structured fields:

```text
chosen copy
alternate headlines
CTA variants
objection coverage
claims and proof table
notes for implementation
```

The copy pack is an artifact, not a required pre-run object.

### 7. Pick/reject is logged locally

`chosen_copy.json` records the picked option and optional user note. This is only
a local run artifact in C0. It seeds later copy memory, but C0 does not silently
steer future runs from memory.

### 8. Research is deferred

Web research can be high value for copy, but it is not part of the C0 MVP. Deep
effort means more versions and stronger objection/proof review, not public web
research.

When research ships later, the UI shows plain concrete text:

```text
4 versions - landing page experts - web research
```

Future research rules:

- Public web research is allowed only when the selected effort/type enables it or
  the user turns it on.
- Sources are saved with the run.
- Private files, repo contents, credentials, customer data, and unpublished
  product context are not sent to research surfaces unless the user attached or
  selected them for the run.

## Artifact Contract

`run.json` remains truth. Markdown files are derived.

```text
run_<id>/
  copy_request.json       # prompt, copy type, effort, optional context refs
  copy_option_<workerId>.md # one generated direction per generator worker
  copy_board.json         # ordered board: workerId, angle, model, skill, status
  chosen_copy.json        # human pick + optional note
  copy_pack.md            # deterministic render of chosen version + variants/tables
  bundle.md               # prompt + options + chosen copy pack
```

## MVP Landing-Page Skill Suite

The `Landing page` copy type ships with a default team so prompt-only runs work
instantly. Advanced team customization uses the shared model:

```text
Worker = model + skill
```

The main C0 composer does not require team configuration.

Generation skills:

- Offer strategist
- Objection hunter
- Direct-response writer
- Clarity editor
- Proof/claims skeptic
- Contrarian angle finder

Review skills:

- Unsupported claims
- Weak CTA hierarchy
- Generic AI phrasing
- Sounds like every AI landing page
- Wrong awareness stage
- Missing objection coverage

The default worker assignments are starting-lineup decisions. The UI says what
the user gets in the main path (`4 versions - landing page experts`). A future
`Customize team` control may expose rows as `Skill | Model`, but that control
stays one level below the primary composer.

## Implementation Impact

Core:

- Add `WorkKind.copy` if the work-kind model exists, or introduce one.
- Add `Effort` values with UI labels Quick / Standard / Deep.
- Add `CopyType` with `auto` and `landing_page`.
- Add/route Copy skills as lane-tagged prompt profiles.
- Add `ThreadTurnKind.copyBoard` or equivalent thread family mapping.
- Add copy payloads: request, option, board, chosen copy.
- Add prediction-free copy summary helper, e.g. `4 versions - landing page`.
- Keep `copyBoard` in the existing heavy-run family for MVP thread filters. Copy
  is a routed team turn, not a separate thread system.

Engine:

- Reuse text worker fan-out.
- Reuse stage output/run artifact storage.
- Add copy skills as prompt profiles for landing-page generation and review.
- Render the copy pack deterministically from structured option fields. Do not add
  a second reduce stage in C0.

Mac:

- New work order shows Build / Design / Copy.
- Slash commands route `/copy` and `/copy landing`.
- Hotkeys: B, D, C for work kind; 1, 2, 3 for effort.
- Copy composer shows prompt, copy type chips, effort, optional context chips,
  and a concrete run summary.
- Team customization, if included in C0 UI, is an advanced drawer: each row is
  `Skill | Model`. It must not be in the required path.
- Copy board shows versions, pick action, copy/export.

iOS:

- No MVP requirement beyond rendering/starting an existing copy work order once
  remote floor manager supports generic work kinds.

Driver/protocol:

- No new driver capability required for MVP. Copy workers emit text.
- If a model/source cannot browse, it can still participate in non-research
  workers.

Auth/privacy/permissions:

- No new macOS permissions.
- No public web research in C0.
- No hidden repo-wide scan.
- No private context is sent outside the worker prompts unless user-selected.

## Ordered Slices

- [ ] C0-S01 - Core route model: work kind, copy type, effort, copy board turn kind,
  Codable fixtures, state-machine coverage.
- [ ] C0-S02 - Composer routing: Build / Design / Copy chips, `/copy` commands,
  hotkeys, prompt-only run path.
- [ ] C0-S03 - Landing-page skill suite: generation skills, review skills, default
  team lineup, effort map, fixtures.
- [ ] C0-S04 - Copy fan-out: reuse text worker runner, produce copy options and
  copy board payload.
- [ ] C0-S05 - Copy board UI: versions side by side, pick, copy/export, failed
  worker tiles.
- [ ] C0-S06 - Deterministic copy pack artifact after pick: chosen copy, alternate
  headlines, CTA variants, objections, claims/proof table.
- [ ] C0-S07 - Quality gate: founder dogfoods one real landing-page prompt and
  confirms the board is better than a single strong prompt chain before the lane
  is enabled by default.

## Works Test

```text
Press Cmd+N, then C.
Type:
  Rewrite my pricing page so solo founders actually convert.
Choose Landing page and Standard effort.
Press Enter.

Allnighter shows a concrete summary:
  4 versions - landing page experts

The run produces a copy board with four distinct landing-page directions. One
worker is forced to fail; its failed option stays visible with the reason while
the other options remain usable.

Pick one option. Allnighter writes copy_pack.md with the chosen copy, alternate
headlines, CTA variants, objection coverage, and a claims/proof table. The full
bundle exports without requiring any field beyond the original prompt.
```

Quality assertion:

```text
The four options must be different strategies, not synonym swaps. The founder
must be able to name at least one option they would seriously consider shipping,
and the copy pack must flag unsupported claims as "needs proof" rather than
inventing evidence.
```

## Proof Command

```text
swift test
```

App proof follows `docs/operations/TechStack.md` once Mac UI code exists.

## Done When

- The user can start Copy from a prompt, `/copy`, or hotkey path.
- `Prompt` is the only required field.
- `Copy type` and `Effort` are visible and simple.
- Landing page has a default team so the user does not need to configure workers.
- Standard landing-page effort produces a usable copy board.
- Picking a version creates a copy pack artifact.
- The copy pack is rendered deterministically from structured option fields.
- The landing-page board passes the quality gate before default enablement.
- No UI uses abstract run-planning language for this lane.
- `swift test` and the app proof wall pass, or missing app proof is explicitly
  waived before implementation.

## Open Questions

- Which exact structured fields are required for `copy_option_<workerId>.md` so the
  deterministic copy pack is complete without a reduce stage?
- Should the first dogfood prompt use Allnighter's own pricing/home page or a
  founder-provided external product?
- Is team customization in C0 or the first follow-up? Either way, the language and
  data model must be `worker = model + skill`.
