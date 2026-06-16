# Copy Lane - Work Orders That Sell

Status: Draft post-MVP phase; Fan out team picker updates routed through
`docs/phases/Fanout_Team_Catalog.md`
Owner: Founder + Shared Core + Mac
Updated: 2026-06-16

## Founder Intent

Allnighter already routes build and design work to teams of agents. Copy is the
third high-value lane:

```text
Build  |  Design  |  Copy
```

The product should stay as simple as Claude or Cursor:

```text
New work order
[ Build ] [ Design ] [ Copy ]

Prompt
"Rewrite my pricing page so solo founders actually convert."

Team
[ Landing Page Team ]

Effort
[ Low ] [ Med ] [ High ]

Run copy board
```

Slash commands and hotkeys are first-class:

```text
/build
/design
/copy
/copy landing
```

Keyboard path:

```text
Cmd+N -> C -> L -> type prompt -> 2 -> Enter
```

## Product Value

Generic writing is a commodity. Copy work is not generic writing. Landing pages,
email funnels, ads, lead magnets, UGC scripts, newsletters, and app store pages
each need a different expert setup.

Allnighter's value is not that it asks the user to fill out a marketing form. The
value is that one prompt can route to the right copy team, generate distinct
directions, pressure-test objections, and hand back copy the user can pick from.

Copy also completes the launch loop:

```text
Build  -> makes it real
Design -> makes it desirable
Copy   -> makes someone act
```

The MVP proves this with landing pages. Later slices close the loop by handing the
picked copy to Build so the user's site changes without copy/paste.

Copy uses the shared work-order team model:

```text
Bench  = the models the user has
Model  = Opus, Sonnet, Grok, Gemini, etc.
Skill  = what hat a model wears
Worker = model + skill for this run
Team   = the worker lineup for this work order
Lane   = Copy
Type   = Landing page, Email, Ads, UGC, ...
Effort = Low / Med / High
```

Read `docs/phases/Work_Order_Team_Model.md` before designing Copy team controls.

## UX Laws

- **One prompt is the only required input.**
- **The user chooses the kind of work and the amount of effort. Allnighter chooses
  the default team.**
- **Default team first; custom team second.** Prompt-only runs use the lane/type's
  default lineup. Advanced users can customize workers one level deeper as
  `Skill | Model` rows.
- **Copy type is routing metadata, not paperwork.** In the Fan out composer,
  Copy type packs materialize as Copy teams. CLI/slash compatibility may still
  accept type and resolve it to the default team for that type.
- **Effort is an instruction, not a forecast.** It may change how many versions,
  review passes, or research steps run. It must not imply predicted runtime, cost,
  quota burn, or difficulty.
- **No intake-form tax.** Optional context appears as lightweight chips or
  attachments. MVP chips are draft, customer, proof, and brand voice; URL/source
  chips wait until source capture exists.
- **No abstract run-preview label in the UI.** Show concrete value like
  `4 versions - landing page experts`.
- **Do not call the user's prompt a brief.** The UI word is `Prompt`.
- **A failed worker is shown failed, never hidden.**
- **Three peer lanes is the ceiling.** Build, Design, and Copy are the top-level
  product surface. New domains become a copy type, design type, build preset, or
  thread turn, not a fourth composer lane.
- **Copy boards must show strategies, not synonym swaps.** Different wording with
  the same angle is a failed board.
- **Copy has types, not sub-lanes.** Landing page, email, ads, UGC, and newsletter
  are Copy types/playbooks inside the Copy lane.

## Decision Summary

MVP (`00`):

- `/copy landing`;
- prompt-only required input;
- Low / Med / High effort;
- default landing-page team, with later customization through shared team controls;
- copy board with distinct landing-page strategies;
- deterministic copy pack after pick;
- local pick/reject logging;
- founder quality gate before default enablement;
- no public web research.

Fast follow (`02`):

- picked copy -> Apply to site -> Build edits selected files;
- user chooses target files and Build worker;
- no direct Allnighter code edits.

Later (`01`):

- more copy types;
- source capture and source browser;
- house voice, banned claims, and copy memory;
- campaign runs across Build, Design, and Copy.

Avoid:

- fourth peer lane;
- intake forms;
- half-built copy type chips;
- auto-publish integrations;
- hidden repo scans;
- direct AST/localization edits by Allnighter;
- new paid API/BYOK default path.

## Docs

- **[00_Copy_MVP.md](00_Copy_MVP.md)** - thin first slice: `/copy landing`, prompt
  first, effort, copy board, pick, copy pack.
- **[02_Copy_Apply_To_Site.md](02_Copy_Apply_To_Site.md)** - fast-follow loop
  closer: picked copy -> Build edits selected site files.
- **[01_Copy_Roadmap.md](01_Copy_Roadmap.md)** - the full copy lane: more copy
  types, research, house voice, and campaign runs.

## MVP vs Later

| Layer | MVP | Later |
| --- | --- | --- |
| Entry | `Build / Design / Copy`, `/copy`, hotkeys | iOS remote start, saved defaults, recent copy types |
| Required input | Prompt only | Prompt only |
| Copy team/type | `Landing Page Team` quality-gated first; `landing-page` type may route to it in CLI/slash paths | Email funnel, ads, UGC, lead magnet, newsletter, app store, SEO/blog, sales page teams |
| Effort | Low / Med / High | Per-team effort maps, saved user defaults |
| Output | Copy board + deterministic picked copy pack | Apply-to-site handoff, channel exports, campaign pack |
| Research | No public-web research in C0 | Source browser, competitor sets, customer-language library |
| Memory | Log pick/rejection in the run | House voice, banned claims, audience memory, copy scorecards |

## Trusted Workflow Slice

```text
/copy landing
-> prompt
-> effort
-> copy board with several distinct versions
-> user picks one
-> Allnighter writes a copy pack
```

## Routing

Read in order:

1. `docs/phases/copy/README.md`
2. `docs/phases/copy/00_Copy_MVP.md`
3. `docs/phases/Work_Order_Team_Model.md` - model/skill/worker/team vocabulary
4. `docs/phases/Utilization_Admission_Control.md` - Effort and admission rules
5. `docs/mvp/README.md` - built team-run/design-board substrate
6. `docs/phases/copy/02_Copy_Apply_To_Site.md` for the fast-follow handoff
7. `docs/phases/copy/01_Copy_Roadmap.md` for anything beyond the first slice
