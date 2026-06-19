# Maintenance Queue

Structured follow-up work. Keep rows bounded and actionable.

Allowed `Status` values: `open | in-progress | done | wontfix | needs-founder`.

| Created | Target | Reason | Proof need | Risk | Status | Next action |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-06-19 | `Apps/AllnighterMac/Sources/ThreadsViewModel.swift` | Fixture extraction landed in `ThreadsFixtureSeeder.swift`; review remaining routing/notification mix | xcodebuild test AllnighterMac | low | done | Close after hot-fix cleanup closeout |
| 2026-06-19 | `Apps/AllnighterMac/Sources/AppModel.swift` | Setup/census/catalog split started (`AppSetupModel`, `AppCensusModel`, `AppModelCatalogActions`) | AppModelTests + xcodebuild | low | done | Run lifecycle still in AppModel — next Structure batch |
| 2026-06-19 | `Apps/AllnighterMac/Sources/DesignComponents.swift` | Split into per-component files (StatusPill, buttons, dropdowns, etc.) | xcodebuild test AllnighterMac | low | done | Delete queue row after closeout commit |
| 2026-06-19 | `Apps/AllnighterMac/Sources/RootView.swift` | Title bar, workspace switcher, debug routing extracted | xcodebuild test AllnighterMac | low | done | Shell compose-only pass on next Structure batch |
| 2026-06-19 | Vocabulary residue sweep | Retired Council/fan-out/dispatch comments in active Mac source | rg active Swift sources | low | done | Duplication lens next |
