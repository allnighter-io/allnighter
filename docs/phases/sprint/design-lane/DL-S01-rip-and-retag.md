# DL-S01 — Rip diffusion Design default + retag mockup seats

Status: **ready**
SSOT: `docs/phases/Design_Lane.md` (WebKit-first; rip DesignCoordinator/DesignImageRunner)

## Goal

Delete the orphaned imageGen Design path and retag mockup seats off `.image`
so Design staffs builders. Zero customers — no migration.

## Copy-paste prompt

```text
You are implementing DL-S01 ONLY (Design Lane rip + catalog retag).

Read:
- docs/phases/sprint/design-lane/DL-S01-rip-and-retag.md
- docs/phases/Design_Lane.md
- docs/operations/Execution-Playbook.md §Commits

Implement:
1. DELETE Packages/AllnighterCore/Sources/AllnighterEngine/DesignCoordinator.swift
2. DELETE Packages/AllnighterCore/Sources/AllnighterEngine/DesignImageRunner.swift
3. DELETE Packages/AllnighterCore/Tests/AllnighterEngineTests/DesignCoordinatorTests.swift
4. DELETE Packages/AllnighterCore/Tests/AllnighterEngineTests/DesignImageRunnerTests.swift
5. ProveCLI/main.swift: remove --design / proveDesign() only; keep text proof path.
6. TeamRunAttachmentMapper: remove mapForDesign() / designSeatPrompt() if present; fix/remove their tests in ThreadSendCoordinatorAttachmentTests.
7. BuiltInTeams.swift: retag visual_system_designer, minimal_direction, bold_direction, editorial_direction from [.image] → [.design]. Rewrite comments to screenshot-receipt law (not imageGen mockups).
8. Update TeamResolverTests that assert .image staffing for those seats.
9. KEEP: DesignRun.swift board schema, WorkerImageCapture/Invoker, chat imageGen, Artifact/Floor board readers, driver imageGen JSON.
10. Commit when Works Test green. Explicit paths only. Allowed models for this sprint: Cursor Grok 4.5 and Composer only.

Out of scope: WebKit capture, board writer in CatalogRunCoordinator, native GUI proof, pick surface, Mac UI.

Proof:
swift test --package-path Packages/AllnighterCore --filter 'Design|TeamResolver|SkillCatalog|Attachment|Prove'

Done when: deleted files gone, catalog retagged, tests green, committed.
```

## Read only

- `docs/phases/Design_Lane.md`
- This work order

## Touch allowlist

- `Packages/AllnighterCore/Sources/AllnighterEngine/DesignCoordinator.swift` (delete)
- `Packages/AllnighterCore/Sources/AllnighterEngine/DesignImageRunner.swift` (delete)
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/DesignCoordinatorTests.swift` (delete)
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/DesignImageRunnerTests.swift` (delete)
- `Packages/AllnighterCore/Sources/ProveCLI/main.swift`
- `Packages/AllnighterCore/Sources/AllnighterEngine/TeamRunAttachmentMapper.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/BuiltInTeams.swift`
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/ThreadSendCoordinatorAttachmentTests.swift`
- `Packages/AllnighterCore/Tests/AllnighterCoreTests/TeamResolverTests.swift`
- This sprint doc status → `done` on closeout

## Do not touch

- `DesignRun.swift` board schema
- `WorkerImageCapture.swift` / `WorkerImageInvoker.swift` / chat imageGen
- `CatalogRunCoordinator` / `RunService` board wiring (DL-S02)
- Mac app UI

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter 'Design|TeamResolver|Attachment'
```

## Done when

- [ ] Orphaned DesignCoordinator / DesignImageRunner + their tests deleted
- [ ] ProveCLI `--design` gone
- [ ] Mockup seats tagged `.design`
- [ ] Tests green; committed
