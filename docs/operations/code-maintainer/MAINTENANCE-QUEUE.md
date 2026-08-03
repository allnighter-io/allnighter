# Maintenance Queue

Structured follow-up work. Keep rows bounded and actionable.

Allowed `Status` values: `open | in-progress | done | wontfix | needs-founder`.

| Created | Target | Reason | Proof need | Risk | Status | Next action |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-08-03 | `Apps/AllnighterMac/Sources/ThreadsViewModel.swift` | 1,627 LOC orchestration pressure (run lifecycle + composer + notifications) | AppModelTests + xcodebuild | med | in-progress | scout done (see ThreadsViewModel-split.md) |
| 2026-08-03 | `Apps/AllnighterMac/Sources/RoutingComposer.swift` | **done** CM-S01–S06 — 1648→390 LOC shell + 7 focused extension files | xcodebuild test AllnighterMac | med | done | Optional: attachment capture extract |
| 2026-08-03 | `Apps/AllnighterMac/Sources/ThreadView.swift` | **done** CM-S08 — ThreadBoardRow extracted (`ThreadBoardRow.swift`); 1238→978 LOC | xcodebuild test AllnighterMac | low | in-progress | Extract ThreadMutatingRunRow next |
| 2026-06-19 | `Apps/AllnighterMac/Sources/ThreadsViewModel.swift` | Fixture extraction landed in `ThreadsFixtureSeeder.swift`; review remaining routing/notification mix | xcodebuild test AllnighterMac | low | done | Close after hot-fix cleanup closeout |
| 2026-06-19 | `Apps/AllnighterMac/Sources/AppModel.swift` | Setup/census/catalog split started (`AppSetupModel`, `AppCensusModel`, `AppModelCatalogActions`) | AppModelTests + xcodebuild | low | done | Run lifecycle still in AppModel — next Structure batch |
| 2026-06-19 | `Apps/AllnighterMac/Sources/DesignComponents.swift` | Split into per-component files (StatusPill, buttons, dropdowns, etc.) | xcodebuild test AllnighterMac | low | done | Delete queue row after closeout commit |
| 2026-06-19 | `Apps/AllnighterMac/Sources/RootView.swift` | Title bar, workspace switcher, debug routing extracted | xcodebuild test AllnighterMac | low | done | Shell compose-only pass on next Structure batch |
| 2026-06-19 | Vocabulary residue sweep | Retired Council/fan-out/dispatch comments in active Mac source | rg active Swift sources | low | done | Duplication lens next |
