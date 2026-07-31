# TRR-S01c — Deslop + Code Audit

Scope: commit `218ea4fc` + same-pass deslop/audit fixes.
Skimmed `224a2318` (TRR-S03) for accidental overlap — CLI/ArtifactWriter only; no Mac live-paint bleed.
Date: 2026-07-25

## CLI gate

```text
alln artifact show/export on non-terminal → RUN_NOT_TERMINAL (unchanged).
S01c did not touch ArtifactCLI; 224a2318 shared terminalRun helper and kept the gate.
Proof: ArtifactProjectorTests testNonTerminalRunCannotProject +
       testArtifactWriterRejectsNonTerminal + testArtifactWriterExportRejectsNonTerminal.
```

## Deslop

```text
Deslop:
Verdict: FIXED
Touched:
  ArtifactFloorOpener.swift — restore ModelCatalog.list() when models omitted (Floor open)
  LiveArtifactProjector.swift — drop unused apply(context:) parameter
  ThreadsViewModel.swift / LiveArtifactProjectorTests.swift — match apply signature
Residual risk:
  regenerateArtifact still best-effort swallows write errors (Open artifact retries loud).
  ThreadView body-eval seed fallback is display-only until ViewModel seats populate.
  Mac live gesture remains a manual Works Test (host-bound).
```

## Code Audit

```text
Verdict: CLEAN
Scope reviewed:
  LiveArtifactProjector (+ tests), LiveArtifactPreviewView,
  ArtifactFloorOpener extraction from FactoryFloorView,
  ThreadsViewModel liveArtifactByRunId apply/seed/clear + terminal regenerate,
  ThreadView live preview + Open artifact,
  ArtifactCLI terminal gate (confirm only; owned by S01/S03)
Proof reviewed:
  swift test --package-path Packages/AllnighterCore --filter 'LiveArtifactProjectorTests|ArtifactProjectorTests'
Findings:
- [P1 FIXED] ArtifactFloorOpener.openArtifact defaulted models to [] after extraction;
  Factory Floor Open artifact lost ModelCatalog.list() seat labels/glyphs. Restored via
  resolveModels fallback (S01b posture).
- [P3] regenerateArtifact silent catch — intentional best-effort; Open path remains fail-loud.
- [P3] firstLine/capped helpers duplicate ArtifactProjector — no new abstraction this pass.
- No P0: live path consumes only worker.status_changed / worker.answer_delta; seats from
  TeamRunSeatSet seed; settled HTML still ArtifactProjector; CLI non-terminal fail-closed.
Residual risk:
  Events before run.json seats exist are dropped until seed; next delta/status recovers.
  Manual Works Test: start multi-seat Mac run → live seats/status → terminal Open artifact.
```

## Proof

```text
LiveArtifactProjectorTests — 4 passed
ArtifactProjectorTests — 18 passed (includes non-terminal writer + canProject)
```
