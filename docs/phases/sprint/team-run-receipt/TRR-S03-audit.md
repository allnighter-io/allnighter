# TRR-S03 — Deslop + Code Audit

Scope: commit `c7388bbc` + same-pass deslop cleanup.
Date: 2026-07-25

## Deslop

```text
Deslop:
Verdict: FIXED
Touched:
  ArtifactWriter.swift — drop unreachable WriteError rethrow in writeHTML/exportHTML
  ArtifactCLI.swift — share terminalRun resolve for show + export (no behavior change)
Residual risk:
  fileManager injection still covers createDirectory only (Data.write uses default FS) —
  same residual as S01b; not introduced by export path uniquely.
  Offline open Works Test remains manual (no browser harness in package tests).
```

## Code Audit

```text
Verdict: CLEAN
Scope reviewed:
  ArtifactWriter.exportHTML + renderedHTML share with writeHTML,
  ArtifactCLI.runExport (+ terminalRun helper), AllnighterCLI artifact export dispatch,
  ContractRegistry artifact.export (4.0.4→4.0.5) + export md teaching distinction,
  HelpTopicRegistry artifact topic, ArtifactProjectorTests export cases,
  generated alln contract/help regen from c7388bbc
Proof reviewed:
  swift test --package-path Packages/AllnighterCore --filter ArtifactProjectorTests
Findings:
- [P3] fileManager injection does not wrap Data.write — residual from S01b; export copies pattern.
- [P3] FS write failures still surface as CLI_USAGE_ERROR (same as artifact show) — message
  includes underlying WriteError; no new silent path.
- No P0/P1: export regenerates via ArtifactProjector (not a second layout); non-terminal
  fails closed; body-match and notTerminal covered by tests; md `export` untouched.
Residual risk:
  TRR-S01c live paint WIP may coexist in the working tree — out of scope; not audited here.
  Manual Works Test: open exported HTML offline and compare to `artifact show --no-open`.
```

## Proof

```text
ArtifactProjectorTests — 18 passed (includes export / match-show / non-terminal)
```
