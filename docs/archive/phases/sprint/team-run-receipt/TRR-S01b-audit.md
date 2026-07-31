# TRR-S01b — Deslop + Code Audit

Scope: commit `14dc69a4` + same-pass deslop/audit fixes.
Date: 2026-07-25

## Deslop

```text
Deslop:
Verdict: FIXED
Touched:
  FactoryFloorView.swift — ArtifactFloorOpener no longer swallows write/open failures
  ArtifactWriter.swift — WriteError.writeFailed preserves underlying reason + description
Residual risk:
  Mac Floor gesture remains a manual Works Test (no Mac UI test harness for browser open).
  Floor projector context uses ModelCatalog.list() (not live AppModel.models); seat labels
  for non-catalog models may fall back to raw ids until a later wiring pass.
```

## Code Audit

```text
Verdict: CLEAN
Scope reviewed:
  ArtifactWriter, TeamRunReplayCommand, ArtifactCLI (show → writer),
  AllnighterCLI.reproduceCommand shim, FactoryFloorView ArtifactFloorOpener,
  ContractRegistry floor-show teaching cross-link, ArtifactProjectorTests writer cases
Proof reviewed:
  swift test --package-path Packages/AllnighterCore --filter ArtifactProjectorTests
Findings:
- [P1 FIXED] ArtifactFloorOpener used try?/silent return on runDirectory + writeHTML —
  user click did nothing on failure. Now fail-loud via NSAlert; browser open Bool checked.
- [P1 FIXED] ArtifactWriter.WriteError.writeFailed discarded the underlying filesystem
  error (CLI/Floor could only say "writeFailed"). Now writeFailed(String) + CustomStringConvertible.
- [P3] fileManager injection covers createDirectory only (Data.write still default FS) —
  residual; no behavior change needed for S01b.
- [P3] AllnighterCLI.reproduceCommand is a one-line shim to TeamRunReplayCommand —
  intentional Core owner extraction, not a half-extraction (CLI callers retained).
Residual risk:
  Visual dual-viewport proof remains waived (S01 waiver). S01c live paint / S03 export
  not in scope.
```

## Proof

```text
ArtifactProjectorTests — 15 passed
```
