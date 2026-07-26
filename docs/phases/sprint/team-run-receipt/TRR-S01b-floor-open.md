# TRR-S01b — Mac Floor “Open artifact”

Status: **done**
SSOT: `docs/archive/phases/Team_Run_Receipt.md` §TRR-S01b

## Goal

From Factory Floor on a terminal run, open the same regenerable HTML artifact
as `alln artifact show` (shared `ArtifactProjector` — no second layout).

## Copy-paste prompt

```text
Implement TRR-S01b ONLY.

Read:
- docs/phases/sprint/team-run-receipt/TRR-S01b-floor-open.md
- docs/archive/phases/Team_Run_Receipt.md §TRR-S01b
- Apps/AllnighterMac/Sources/FactoryFloorView.swift
- Packages/AllnighterCore/Sources/AllnighterCore/ArtifactProjector.swift
- Packages/AllnighterCore/Sources/AllnighterCLI/ArtifactCLI.swift

Touch:
- FactoryFloorView (or thin helper in Mac Sources) — “Open artifact” control for terminal runs
- Optionally teaching cross-link in floor CLI help only if tiny
- Tests if Mac test target can cover regenerating path without GUI flakiness; else unit-test Core write path already covered and document Mac gesture Works Test
- Mark sprint done + Team_Run_Receipt S01b Done
- Commit

Behavior:
1. Only when run is terminal.
2. Regenerate artifact/index.html via ArtifactProjector under RunStore runDirectory (same as CLI).
3. Open with NSWorkspace.shared.open(fileURL) — browser, not in-app WebKit.
4. Do NOT re-implement HTML field mapping in Mac.

Proof: regenerate path parity with CLI logic (shared Core API). Prefer extracting a small Core/CLI-shared writer if CLI duplicated write logic — keep one owner.

Out of scope: S01c live paint, S03 export UI, iOS.
```

## Works Test

Mac: terminal Floor run → Open artifact → browser opens HTML for that run id.
Core: any shared writer unit test still green.

## Done when

- [x] Floor control ships
- [x] Same projector as CLI
- [x] committed
