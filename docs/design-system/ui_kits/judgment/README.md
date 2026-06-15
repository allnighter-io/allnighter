# Judgment Workflow — Allnighter (macOS) · the RB milestone

A high-fidelity, click-through recreation of the **Judgment Workflow / Review
Board** capability (specs `uploads/RB0–RB5`). It evolves the Council from "one
prompt → master plan" into a full control loop:

```
prompt → panel → judge analysis → draft plan → review board → final spec
       → dispatch → return review → scorecards → routing
```

`index.html` is one interactive macOS app with a **left pipeline rail** that
threads a single run (`run 7f3` · `light_review` · "Add per-user rate limiting
to the public API") through every stage. Click a rail step to open its view.

## Views in this batch (1 of N)- **① Composer + Call Plan** (`prompt`) — pick the workflow preset
  (synthesis_only / light_review / full_review), configure panel **seats** with
  per-seat **stances** (self-fusion), pick the synthesizer, and watch the live
  **Call Plan** update (fresh-call estimate, reuse badges, "cost is never
  silent"). Nothing runs until you press go.
- **④ Review Board** (`review`) — advisory lenses (security, maintainer,
  proof/QA) that attacked the draft in parallel: verdict chip (ok/concerns/
  **blocker**), top concerns, bound worker (+ fast-worker routing), per-lens
  rerun/disable, enable switch. Never overwrites `master_plan.md`.
- **⑤ Final Spec** (`final`) — the decision-grade `final_spec.md`: an
  **executability** banner (Works Test + proof commands present), required
  sections, and structured **decision chips** (adopted / partial / rejected /
  deferred) on review feedback and panel contradictions. "Implement this" hands
  off to dispatch.

The other rail stages (Panel, Judge analysis, Draft plan, Dispatch, Return
review) show an "Up next" stub — they're the next mockup batches.

## Files
- `index.html` — mounts `JudgmentApp` (rail nav + active view).
- `shell.jsx` — `JShell` (window + pipeline rail), `JHeader`, `JLive`, `JUD_STAGES`.
- `screens.jsx` — `ComposerView`, `ReviewBoardView`, `FinalSpecView`, `StubView`.
- `screens2.jsx` — `RunPipelineView`, `JudgeAnalysisView`, `DispatchView`.
- `screens3.jsx` — `ReturnReviewView`, `RoutingView`, `CompareView`.
- `screens4.jsx` — `JConfigShell` + `ScorecardsView`, `PresetEditorView`, `LensLibraryView`, `WorkersView` (reached via the title-bar settings icon).

## Notes
- Composes the design-system components via `components/_preview.jsx`
  (`Button`, `Tabs`, `Select`, `Menu`, `Switch`, `Badge`, `Card`, `Icon`, …).
- All run content is **representative sample data** for the rate-limiting prompt.
