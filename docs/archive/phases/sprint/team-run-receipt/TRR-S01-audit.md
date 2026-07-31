# TRR-S01 — Deslop + Code Audit

Scope: commit `546f2c5f` + same-pass deslop/audit fixes.
Date: 2026-07-25

## Deslop

```text
Deslop:
Verdict: FIXED
Touched:
  ArtifactProjector.swift — indent, G13 count, Must-specify call fallback, unused manifests param
  FloorProjector.swift — remove unused seatWorkers pass-through (half extraction)
  ArtifactProjectorTests.swift — Partial G13, call fallback, real Law-2 hoist, seat-set proof
Residual risk:
  Dual-viewport layout-watcher still waived (WAIVERS.manifest trr-s01-artifact-html).
  Projector still embeds token CSS inline (work order allowed; design-system WorkerChip compact deferred).
```

## Code Audit

```text
Verdict: CLEAN
Scope reviewed:
  ArtifactProjector, LeadCallParser, TeamRunSeatSet, ArtifactCLI,
  FloorProjector seat-set touch, ContractRegistry artifact.show, HelpTopicRegistry artifact,
  ArtifactProjectorTests, ContractRegistryTests (filter)
Proof reviewed:
  swift test --package-path Packages/AllnighterCore --filter ArtifactProjectorTests
  swift test --package-path Packages/AllnighterCore --filter ContractRegistry
Findings:
- [P1 FIXED] ArtifactProjector.g13Violations — Partial lockup counted as two amber events
  (`verdict-partial` + `accent-event` on one element); gate now counts `accent-event` only.
- [P1 FIXED] Must-specify team-call third branch missing — now emits
  `(no synthesized output — status <run.status>)` when lead-call and body fallbacks are absent.
- [P1 FIXED] FloorProjector.seatWorkers was a dead half-extraction; anti-drift test compared
  floors lanes incorrectly. Seat-set law lives in TeamRunSeatSet; card order proof updated.
- [P2 FIXED] Law-2 hoist test did not empty the worker row; now proves chip reads hoisted answer.
- [P3] Inline projector CSS vs design-system WorkerChip compact — allowed by work-order allowlist /
  waiver path; residual until a later design-system land.
- [P3] Missing worker answer still labels status `queued` (matches RunStore prior art).
Residual risk:
  Visual dual-viewport proof remains waived until an HTML fixture harness exists.
  Floor deep-reader lanes may still include scout; artifact seat-set correctly excludes them
  via TeamRunSeatSet (shared law, not Floor lane filter).
```

## Proof

```text
ArtifactProjectorTests — 13 passed
ContractRegistryTests (+ CLIHelpDrift) — green
```
