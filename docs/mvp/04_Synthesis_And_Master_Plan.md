# 04 — Synthesis + Master Plan

Status: **Built (automated gates green)** — live one-click loop with real CLIs is
a founder-run manual step. **This completes the MVP "lovable demo" (01–04).**
Depends on: 01, 02, 03
Owner: Mac (engine + UI)
Created: 2026-06-14
Built: 2026-06-14

## Goal

Close the loop the founder runs every day: after the panel answers, hand the
original prompt + all labeled answers to the **synthesizer** (Opus 4.8 by
default) with a strong master-plan instruction, and produce a single, decisive
**master plan**. Render it, and export the whole bundle (prompt + every member
answer + master plan) as one Markdown file and to the clipboard. This is the
moment the product replaces ~12 manual copy/paste actions with one click.

## Non-Goals

- Cross-critique / red-team round (full Council, Growth Seam `00` §10 — easy add
  later). "Implement This" / execution lanes. Custom judge ML.

## Approach (per `00`)

- **Synthesis input assembly**: build one prompt containing the original prompt
  and each member's answer **clearly labeled by worker** (only `done` members;
  failed/timed-out members are noted as "no answer" so the synthesizer knows the
  panel was incomplete).
- **Synthesizer invocation**: reuse the Phase 02 `WorkerRunner` with the worker
  whose `role` is `synthesizer` (default Opus 4.8 via `claude_code`). The
  synthesis instruction is a stored, **editable** template (preset
  `default_master_plan_v1`). If the synthesizer worker is `manual_paste`, show
  the assembled synthesis prompt for the user to run and paste back.
- **Master plan structure** (default sections, user-editable):

```text
# Master Plan

## Consensus            — what most/all sources agree on
## Conflicts            — where they disagree, and the recommended resolution
## Unique insights      — standout points only one source raised (attributed)
## Blind spots & gaps   — what none addressed but matters
## Risks & unknowns     — what could go wrong; what we still need to learn
## The Plan             — decisive, ordered, actionable steps
## Open questions       — what the founder should decide next
```

- **State**: `synthesizing -> complete`; if synthesis fails, run resolves
  `partial` (members are still readable). Emits `synthesis.*` `RunEvent`s.
- **Export**: write `master_plan.md` and `bundle.md` to the run folder (`00`
  §7) and copy `bundle.md` to the clipboard; a "Save as…" is offered.

## Ordered Slices

- [x] P04-S01 — Synthesis-input assembly (`SynthesisPromptBuilder`: labeled
  answers + explicit incomplete-panel note).
- [x] P04-S02 — Synthesis instruction template + 7-section default structure
  (`SynthesisInstructions`; editable via `AppModel.synthesisInstructions`).
- [x] P04-S03 — Synthesizer invocation via the engine (`Synthesizer` reuses
  `WorkerRunner`); `answersIn -> synthesizing -> complete`/`partial`.
- [x] P04-S04 — Master-plan card (Markdown, selectable) + Copy plan.
- [x] P04-S05 — Manual-paste synthesizer path (assembled prompt shown + paste box
  → `setManualSynthesis`).
- [x] P04-S06 — Export: `run.json` + `master_plan.md` + `bundle.md` to the run
  folder (`RunStore`) + "Copy full bundle" to clipboard.
- [~] P04-S07 — Run-store wiring done. `synthesis.*` events deferred: in-app the
  observable `run` drives the master-plan card directly; the dedicated synthesis
  events are only needed for the iOS WebSocket seam (added with iOS).

## Works Test

```text
The full daily loop, one click: type one real prompt, run the six-worker panel,
let it fan out in parallel; when answers are in, the synthesizer (Opus 4.8)
produces a master plan in the seven default sections. If a worker failed, the
master plan still appears and notes the missing source (run = `partial`/
`complete`). Click export and get one Markdown bundle containing the prompt,
every member answer, and the master plan — on the clipboard and on disk. Zero
copy/paste actions were performed by the founder.
```

## Exit Gates

- [ ] **Founder manual:** end-to-end one-click loop with the real six workers.
- [x] Master plan prompt grounds sections in member answers (labeled per worker;
  proven in `SynthesisTests`).
- [x] A failed member never blocks synthesis; incompleteness is disclosed in the
  synthesis prompt and the run resolves `complete` (or `partial` if synthesis
  itself fails).
- [x] Synthesis instruction is editable (`synthesisInstructions`); persisting it
  as a named preset is Phase 05.
- [x] Export bundle is complete, well-formed Markdown (`RunMarkdown.bundle`,
  tested) and written to disk + clipboard.
- [x] `swift test` (56) + `xcodebuild test AllnighterMac` (7) green via
  `scripts/check.sh`.

## Closeout

**MVP lovable demo built (01–04); one founder-run live test remains.** The
one-command "fan out to my six CLIs → Opus master plan → export" loop exists
end-to-end in code, proven deterministically. Before trusting real output, run
the app once with live CLIs and correct any driver flags (Phase 02 deferred
probe). Activate **Phase 05** (History, Presets, Doctor, notarized DMG) to make
it the daily driver. iOS planning begins only after 05.
