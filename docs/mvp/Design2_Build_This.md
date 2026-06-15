> **Vocabulary (2026-06-15).** Current product language lives in
> `docs/phases/Work_Order_Team_Model.md`. This doc uses team/model/worker/plan
> terms only.

# Design2 - Build This (the flywheel)

Status: **BUILT (2026-06-15) — Core+Engine+Mac green.** Reuses RB4 dispatch; chosen image + redesign framing → coding agent (Claude Code/Codex read images).
Owner: Founder + Shared Core + Mac
Created: 2026-06-15
Updated: 2026-06-15
Depends on: Design1 (the board + chosen option), RB4 (direct executor dispatch)

> **Dead and not coming back:** OCR and HTML rendering (Design0 § "What is DEAD").
> The chosen design is an **image**; turning it into code is a job for a **coding
> agent that reads the image**, not a render pipeline.

## The framing that de-risks this whole step: it's a *redesign*

Mentors worry that handing a static image to a coding agent yields hallucinated,
unbuildable code. That fear assumes **build-from-scratch**. It isn't our case.

> **Our ICP is redesigning a screen whose code already exists.** A vibe coder who
> hands over a screenshot and says "build this from nothing" with no repo is **not
> our user.** So the build step is almost never "invent a component from a picture"
> — it's **"restyle this *existing* file to match this image."**

That changes the task from generative guessing to a constrained edit: the agent gets
the **target file's current source**, the **repo's styling system**, *and* the chosen
image, and is told to **modify the existing code to adopt the new look.** This is the
single most important thing in Design2 — it's why the handoff works.

## Why the rest is mostly RB4

The design team produces images; **code comes from this step.** It is Lane 1's
executor dispatch (RB4) with two deltas: the brief carries the **chosen image** *and*
the **existing target file + repo tokens** (double context), and the execution prompt
must get the image to the CLI. Picker, working dir, dispatch, status, transcript,
boundary law — all reused.

## Goal

From a chosen option: assemble a build brief carrying the chosen image **plus the
existing target file's source + repo styling tokens**, let the user **pick which CLI
implements it** (just like the build team), and dispatch — the coding agent reads
the image and **modifies the existing code** to match. An advisory **lead-designer**
critique is optional, off by default, and speaks **after** the pick (never before).

## Non-Goals

- No Allnighter-owned git/worktree rules (RB4's boundary: Allnighter invokes the CLI;
  the repo owns git).
- No automated "winner" — the human picks (Design1).
- No render/preview of the built code inside Design2 (the agent builds into the repo;
  the user runs it).
- **No first-class "build from a bare image with no repo" mode.** It's supported only
  as a low-fidelity edge case with an honest warning — it is not our ICP.
- **No BYOK / API image access in this version** (Design0 § Deferred).

## Design

### Build this → choose the implementer (reuse RB4)

- The board's **"Build this"** on a chosen option opens RB4's executor picker: a
  **coding CLI** (Claude Code / Codex / Grok / …) + a **working directory** — the same
  UI and dispatch the build team uses.
- **Capability gate (`canReadImages`).** The implementer must read an image headlessly
  (Doctor flag, Design1 §). `canReadImages` workers are offered first — **Claude Code
  is the default** (confirmed on-device: strong coder, reads images; it can't *generate*
  images, which is exactly why it lives on the build side, not the design workers). Two
  fallbacks,
  in order: (1) if the CLI reads files but has no image flag, the runner passes the
  image as a **base64 data URI** inside the prompt; (2) if it can't take an image at
  all, the brief **degrades to a text description** of the target look with a **visible
  warning** that this build is weaker — recommended **reveal-only**, never presented as
  equivalent to an image build.

### The build brief — double context (`design_build_brief.md`)

A `DesignImplementationBrief` — an RB4 `ImplementationBrief` **variant**
(`sourceKind: .designImage`) that **does not require `final_spec.md`**. Its inputs:

- **Visual target:** the chosen `option_<workerId>.png` (the agent reads it), and the
  **original screenshot** as the "before."
- **Structural context (the de-risker):** the **current source of the target
  file(s)/component** the user is redesigning, plus the repo's **styling system**
  (Tailwind config / theme tokens / CSS vars — the same repo scan the team can use).
- **Integration constraints (required, not prose):** target file(s), framework +
  styling system, **what to reuse vs. create**, and **what to ignore in the mockup**
  (a mockup is a *look*, not a spec). Prefilled from the repo scan + the picked target;
  user-editable. The execution prompt is shaped as **"modify these files to match the
  design image,"** not "build this."
- **Intent + (optional) lead-designer note** so the agent knows *why* this design was
  chosen ("the empty-state was deliberate — don't optimize it away").

The execution prompt passes the image by **absolute path** (or base64 fallback) and
reads the existing files **in place** — it does **not** copy run artifacts into the
working dir (RB4 context-exclusion law holds).

### Optional: the lead designer (advisory, speaks second)

A single advisory pass, **off by default**, that a `canReadImages` worker runs over
the board to **name the tradeoff** — never to pick: *"the minimal option reads
cleaner, but the bold one's empty-state is the only one a new user won't bounce on."*

- **Sequenced strictly after the pick.** Hidden until the user has looked and chosen
  (or run only on request) so it can't anchor the verdict (board-first law).
- Its note folds into the build brief.

### Iterate

Build is not one shot. After a build, the user returns to the board, picks another
option (or a "more like this" variant, Design1), and builds again — run history is
preserved. A design run may hold **multiple `dispatch` stages and no `final_spec.md`
at all**; `TeamRun` can complete with `design_fanout` + `board` + `dispatch` only.
The flywheel: **board → pick → build → (look in repo) → re-pick → build.**

## Ordered Slices

- [ ] D2-S01 — `DesignImplementationBrief` model: RB4 `ImplementationBrief` variant
  (`sourceKind: .designImage`, no `final_spec.md` requirement) carrying chosen image +
  before + **existing target source + repo tokens** + integration constraints. Codable
  + fixtures.
- [ ] D2-S02 — Repo styling scan (Tailwind config / theme / CSS vars) + target-file
  picker → prefilled integration constraints (user-editable, required fields).
- [ ] D2-S03 — Doctor `canReadImages` probe; offered first in the picker; **base64
  data-URI** path for file-but-no-image CLIs; text-description + visible warning
  (reveal-only) when no image input is possible.
- [ ] D2-S04 — "Build this" → RB4 executor picker (CLI + working dir) + dispatch: the
  execution prompt passes the image (absolute path / base64) and reads existing files
  in place; live status + transcript to the run folder.
- [ ] D2-S05 — Optional advisory lead-designer pass (off by default, after the pick);
  its note folds into the brief.
- [ ] D2-S06 — Iterate loop: re-pick / "more like this" → re-build; multiple `dispatch`
  stages per run; `bundle.md` includes chosen option, brief, and build status.
- [ ] D2-S07 — Append `chosen_option.json` (+ rationale) to the local taste ledger for
  the parked `15_Preference_Ledger` phase (Design1 writes the artifact; Design2 logs).

## Works Test

```text
On a Design1 board, pick the minimal option. Click "Build this."
-> the executor picker opens (RB4): choose Claude Code + the project working dir.
   Claude Code is canReadImages, so it's offered first.
-> Allnighter scans the repo (Tailwind tokens) and you point it at the existing file:
   src/.../Profile.tsx. The brief is assembled: chosen image as the visual target,
   original screenshot as "before," THE CURRENT Profile.tsx SOURCE + tokens, and
   integration constraints ("modify Profile.tsx to match this look; reuse <Card>;
   keep the data wiring; ignore the decorative hero in the mock").
-> dispatch: the agent reads the image and EDITS the existing component to the new
   style; live status + transcript captured. No copy/paste.
-> turn on the advisory lead designer: AFTER you picked, it names a tradeoff you'd
   missed; the note appears in the brief.
-> later, return to the board, build the bold option into a scratch branch to compare.
   Run history holds both dispatches; neither run produced a final_spec.md.
Pick a build CLI that can't read images: the brief degrades to a text description with
a visible "weaker build — reveal only" warning, and dispatch still runs.
```

## Exit Gates

- [ ] "Build this" reuses RB4's executor picker (user chooses CLI + working dir);
  Allnighter invokes the CLI, the repo owns git.
- [ ] The brief carries the chosen **image** *and* the **existing target source + repo
  tokens**; the execution prompt is "modify these files to match," not "build from
  scratch."
- [ ] Image reaches the CLI by absolute path or base64; `canReadImages` workers are
  offered first; no-image choice degrades to text with a visible reveal-only warning.
- [ ] Integration constraints are required fields, prefilled from the repo scan.
- [ ] The lead designer is advisory, off by default, and sequenced **after the pick**;
  it never casts the verdict.
- [ ] A design run can complete with `design_fanout` + `board` + `dispatch` and **no
  `final_spec.md`**; iterate preserves run history.
- [ ] Picks are logged for future taste memory.
- [ ] `swift test` + app suite green.

## Closeout

The design team is a flywheel and it's small: **screenshot → board of real options
→ your pick → an agent restyles your existing code to match.** Image engines design,
coding agents build, you decide. The next compounding step is **taste memory** (parked
`15_Preference_Ledger`): the logged picks train a `house_style` persona that joins the
bench and pre-tunes one option to *you*.
