# Code Maintainer Health

Deltas must be explained, not minimized.

## 2026-06-19 (Batch 2 — Duplication)

- Extracted `SetupCardBuckets`, `SetupCardState` pill mapping, and `SetupActions.handle` from duplicated setup/readiness surfaces.
- Shared `AppSetupModel.invocations(from:)` between `AppModel` and `ThreadsViewModel`.
- Open maintenance queue rows: 0
- Next regular lens: Dead weight (index 2)

## 2026-06-19 (hot-fix cleanup closeout)

- Repo stage: Swift package (`Packages/AllnighterCore`) + Mac app (`Apps/AllnighterMac`) + iOS target; green wall recovered after xcodegen regen (stale `DesignBoardView.swift` reference removed).
- Open maintenance queue rows: 0 (hot-fix cleanup slices marked done)
- Suppressions: 0
- Top Mac shell pressure after cleanup: `SetupViews.swift` (~748 LOC), `TeamEditorView.swift` (~706), `ReadinessView.swift` (~611), `HomeView.swift` (~608), `ThreadView.swift` (~601)
- Next regular lens: Duplication (index 1)

## 2026-06-12 (bootstrap)

- Repo stage: docs/process only; no Swift targets yet.
- Open maintenance queue rows: 0
- Suppressions: 0
- Next detector milestone: Phase 01 after `AllnighterCore` package lands.
