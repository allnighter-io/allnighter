# Design2 - Build This (the flywheel)

Status: **Build-ready after Design1.**
Owner: Founder + Shared Core + Mac
Created: 2026-06-15
Updated: 2026-06-15
Depends on: Design1 (the board + chosen option), RB4 (direct executor dispatch)

> **Dead and not coming back:** OCR and HTML rendering (Design0 § "What is DEAD").
> The chosen design is an **image**; turning it into code is a job for a **coding
> agent that reads the image**, not a render pipeline.

## Why this is mostly RB4

The design council produces images; **code comes from the build step.** That step is
Lane 1's executor dispatch (RB4) with one twist: the brief carries the **chosen design
image** so the implementer can see what to build. Image engines designed it; now a
coding CLI **you choose** builds it. Almost everything here is reused.

## Goal

From a chosen option: write a short build brief, let the user **pick which CLI
implements it** (just like the build council), and dispatch — the coding agent reads
the chosen image and builds the real code in the user's working directory. Optionally,
an advisory **lead-designer** critique helps the user decide *before* the pick.

## Non-Goals

- No Allnighter-owned git/worktree rules (RB4's boundary holds: Allnighter invokes the
  CLI; the repo owns git).
- No automated "winner" — the human picks (Design1).
- No render/preview of the built code inside Design2 (the agent builds into the repo;
  the user runs it).

## Design

### Build this → choose the implementer (reuse RB4)

- The board's **"Build this"** on a chosen option opens RB4's executor picker: the
  user selects a **coding CLI** (Claude Code / Codex / Grok / …) and a **working
  directory** — same UI and dispatch the build council already uses.
- **Capability gate (`canReadImages`).** The chosen implementer must be able to read
  an image file headlessly (Doctor flag). Image-read-capable workers are offered
  first; if the user picks one that can't, the brief degrades to a text description of
  the design (still useful) with an honest note.

### The build brief (`build_brief.md`)

A short, RB4-shaped `ImplementationBrief` whose inputs are:

- the **chosen design image** (`option_<seatId>.png`) as the visual target the agent
  reads,
- the **original screenshot** (if any) as the "before,"
- the **user's intent** (the design prompt + persona) and, if present, the
  lead-designer tradeoff note,
- explicit **integration constraints** so the agent builds into the real codebase,
  not a toy page: *target file(s)/component, framework + styling system in the repo,
  what to reuse vs. create, and what to ignore in the mockup* (a mockup image is a
  look, not a spec — say what's binding and what's inspiration).

The brief is the only new artifact; dispatch, transcript capture, and status are RB4.

### Optional: the lead designer (advisory, speaks second)

A single advisory pass, **off by default**, that a `canReadImages` worker runs over
the board to **name the tradeoff** — never to pick: *"the minimal option reads
cleaner, but the bold one's empty-state is the only one a new user won't bounce on."*

- **Sequenced strictly after the board.** It is hidden until the user has looked
  (and may run only on request), so it can't anchor the verdict (board-first law).
- Its note is carried into `build_brief.md` so the implementer knows *why* this design
  was chosen ("the empty-state was deliberate — don't optimize it away").

### Iterate

Build is not always one shot. After a build, the user can return to the board, pick a
different option or a "more like this" variant (Design1), and build again — the run
keeps its history. The flywheel: **board → pick → build → (look) → re-pick → build.**

## Ordered Slices

- [ ] D2-S01 — `build_brief.md` model (RB4 `ImplementationBrief` carrying the chosen
  image + before + intent + integration constraints); Codable + fixtures.
- [ ] D2-S02 — Doctor `canReadImages` capability probe; offered first in the executor
  picker; text-description fallback + honest note when the chosen CLI can't read
  images.
- [ ] D2-S03 — "Build this" → RB4 executor picker (CLI + working dir) + dispatch with
  the chosen image attached; live status + transcript to the run folder.
- [ ] D2-S04 — Optional advisory lead-designer pass (off by default, board-first
  sequencing); its tradeoff note folds into the build brief.
- [ ] D2-S05 — Iterate loop: re-pick / "more like this" → re-build; run history +
  `bundle.md` include the chosen option, build brief, and build status.
- [ ] D2-S06 — Log `chosen_option.json` (+ the pick's rationale) to the local taste
  ledger for the parked `15_Preference_Ledger` phase.

## Works Test

```text
On a Design1 board, pick the minimal option. Click "Build this."
-> the executor picker opens (RB4): choose Claude Code + the project working dir.
   Claude Code is canReadImages, so it's offered first.
-> build_brief.md is written: the chosen image as the visual target, the original
   screenshot as "before," the intent, and integration constraints ("build as a React
   component using the repo's Tailwind tokens; reuse <Card>; this is the profile
   screen at src/.../Profile.tsx").
-> dispatch: the coding agent reads the image and builds the component into the repo;
   live status + transcript captured. No copy/paste.
-> turn on the advisory lead designer: AFTER you've already picked, it notes a tradeoff
   you'd missed; the note appears in build_brief.md.
-> later, return to the board, build the bold option instead into a scratch dir to
   compare. Run history holds both.
Pick a build CLI that can't read images: the brief degrades to a text description with
a visible note, and dispatch still runs.
```

## Exit Gates

- [ ] "Build this" reuses RB4's executor picker (user chooses CLI + working dir);
  Allnighter invokes the CLI, the repo owns git.
- [ ] The chosen **image** is carried to the implementer; `canReadImages` workers are
  offered first; non-capable choice degrades to a text description with an honest note.
- [ ] `build_brief.md` carries integration constraints (target/framework/reuse/ignore)
  so the agent builds into the real codebase, not a toy page.
- [ ] The lead designer is advisory, off by default, and sequenced after the board;
  it never casts the verdict.
- [ ] Iterate (re-pick / re-build) preserves run history.
- [ ] Verdicts are logged for future taste memory.
- [ ] `swift test` + app suite green.

## Closeout

The design council is a flywheel and it's small: **screenshot → board of real options
→ your pick → an agent builds it in your repo.** Image engines design, coding agents
build, you decide. The next compounding step is **taste memory** (parked
`15_Preference_Ledger`): the logged picks train a `house_style` persona that joins the
bench and pre-tunes one option to *you*.
