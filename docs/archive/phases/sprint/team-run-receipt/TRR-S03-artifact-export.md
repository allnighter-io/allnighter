# TRR-S03 — `alln artifact export`

Status: **done** (2026-07-25)
SSOT: `docs/archive/phases/Team_Run_Receipt.md` §TRR-S03

## Goal

Export the same ArtifactProjector HTML to a user-chosen path for offline reading.

## Copy-paste prompt

```text
Implement TRR-S03 ONLY.

Read:
- docs/phases/sprint/team-run-receipt/TRR-S03-artifact-export.md
- docs/archive/phases/Team_Run_Receipt.md §TRR-S03
- Packages/AllnighterCore/Sources/AllnighterCLI/ArtifactCLI.swift
- ArtifactProjector

Ship:
`alln artifact export <run-id|latest> --out <path>`
- terminal-only (RUN_NOT_TERMINAL otherwise)
- writes self-contained HTML (inline CSS ok) readable offline
- body matches show regenerator for same run
- does NOT change `alln export --format md`
- ContractRegistry `artifact.export`; bump contractVersion (4.0.4 → 4.0.5); regen generated docs
- Help distinguishes artifact export vs export md
- Tests for export + non-terminal
- Optional Mac save panel ONLY if trivial; prefer CLI-first this slice
- Commit; mark sprint + phase S03 Done

Proof:
swift test --package-path Packages/AllnighterCore --filter Artifact
alln dev export-contracts --check
```

## Done when

- [x] command + teaching + tests + committed
