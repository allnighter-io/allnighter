# 04 — Synthesis + Master Plan

Status: Draft — **MVP "done": the full one-click daily loop**
Depends on: 01, 02, 03
Owner: Mac (engine + UI)
Created: 2026-06-14

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

- [ ] P04-S01 — Synthesis-input assembly (labeled answers + incomplete-panel note).
- [ ] P04-S02 — Editable synthesis instruction template + default structure.
- [ ] P04-S03 — Synthesizer invocation via the engine; `synthesizing -> complete`/`partial`.
- [ ] P04-S04 — Master-plan viewer (Markdown) + copy.
- [ ] P04-S05 — Manual-paste synthesizer path (show assembled prompt, accept pasted plan).
- [ ] P04-S06 — Export: `master_plan.md` + `bundle.md` to run folder + clipboard + Save as.
- [ ] P04-S07 — `synthesis.*` events + run-store wiring.

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

- [ ] Works Test passes end to end with the founder's real six workers.
- [ ] Master plan grounds its sections in the member answers (attribution present).
- [ ] A failed member never blocks synthesis; incompleteness is disclosed.
- [ ] Synthesis instruction is editable and persisted as a preset.
- [ ] Export bundle is complete and well-formed Markdown.
- [ ] `xcodebuild test -scheme AllnighterMac` + `swift test` green.

## Closeout

**MVP lovable demo complete.** Activate Phase 05 (History, Presets, Doctor,
Distribution) to make it the daily driver. iOS planning begins only after 05.
