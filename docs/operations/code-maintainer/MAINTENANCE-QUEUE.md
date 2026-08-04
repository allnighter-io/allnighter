# Maintenance Queue

Structured follow-up work. Keep rows bounded and actionable.

Allowed `Status` values: `open | in-progress | done | wontfix | needs-founder`.

| Created | Target | Reason | Proof need | Risk | Status | Next action |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-08-03 | `Apps/AllnighterMac/Sources/TeamEditorView.swift` | CM-S21 structure scout done — split plan ready (~1,036 LOC monolith) | xcodebuild test AllnighterMac | low | open | CM-S22 extraction (EditSkillView) |
| 2026-08-03 | `Apps/AllnighterMac/Sources/ThreadsViewModel.swift` | **done** CM-S10–S15 — 1627→470 LOC shell + 6 extension files | AppModelTests + xcodebuild | med | done | — |
| 2026-08-03 | `Apps/AllnighterMac/Sources/RoutingComposer.swift` | **done** CM-S01–S09 — 1648→308 LOC shell + 8 focused extension files | xcodebuild test AllnighterMac | med | done | — |
| 2026-08-03 | `Apps/AllnighterMac/Sources/ThreadView.swift` | **done** CM-S08+S16 — ThreadBoardRow + ThreadMutatingRunRow extracted; 1238→793 LOC | xcodebuild test AllnighterMac | low | done | — |
| 2026-06-19 | `Apps/AllnighterMac/Sources/ThreadsViewModel.swift` | Fixture extraction landed in `ThreadsFixtureSeeder.swift`; review remaining routing/notification mix | xcodebuild test AllnighterMac | low | done | Close after hot-fix cleanup closeout |
| 2026-06-19 | `Apps/AllnighterMac/Sources/AppModel.swift` | Setup/census/catalog split started (`AppSetupModel`, `AppCensusModel`, `AppModelCatalogActions`) | AppModelTests + xcodebuild | low | done | Run lifecycle still in AppModel — next Structure batch |
| 2026-06-19 | `Apps/AllnighterMac/Sources/DesignComponents.swift` | Split into per-component files (StatusPill, buttons, dropdowns, etc.) | xcodebuild test AllnighterMac | low | done | Delete queue row after closeout commit |
| 2026-06-19 | `Apps/AllnighterMac/Sources/RootView.swift` | Title bar, workspace switcher, debug routing extracted | xcodebuild test AllnighterMac | low | done | Shell compose-only pass on next Structure batch |
| 2026-06-19 | Vocabulary residue sweep | Retired Council/fan-out/dispatch comments in active Mac source | rg active Swift sources | low | done | Duplication lens next |
