# DL-S02 — Host HTML→WebKit capture writes the board

Status: **done**
SSOT: `docs/phases/Design_Lane.md` §§Trusted workflow A, Truth owners, Simplicity law

## Goal

For `outputKind == designBoard` team runs, after answer seats finish, the host
captures each seat’s captureable HTML/SVG into `options[].imagePath` and
appends a `.board` stage. Product default camera = WebKit.

## Copy-paste prompt

```text
You are implementing DL-S02 ONLY (Design Lane WebKit board writer).

Read:
- docs/phases/sprint/design-lane/DL-S02-webkit-board.md
- docs/phases/Design_Lane.md
- CatalogRunCoordinator.swift + DesignRun.swift BoardPayload
- docs/operations/Execution-Playbook.md §Commits

Implement:
1. Thin host capture: given a local HTML (or SVG) file path → PNG via WebKit (WKWebView offscreen or existing host util). Sandbox: no network. Fail closed on missing file / render error.
2. Wire into CatalogRunCoordinator (or a small DesignBoardCapture helper it calls) when preset.outputKind == .designBoard:
   - After answer seats: for each seat, locate captureable artifact (convention: runDir/option_<workerId>.html or path declared by seat).
   - Capture → option_<id>.png; build BoardPayload; append StageOutput(purpose: .board).
   - Seat with no captureable file or failed capture → DesignOption status failed; never call imageGen.
3. Unit/integration tests with fixture HTML → PNG bytes exist; board stage maps through TeamRunJSONMapper.mapDesignBoard.
4. No DesignCoordinator rebirth. No Mac UI changes beyond what board JSON already feeds.
5. Commit when Works Test green. Explicit paths. Grok 4.5 / Composer only.

Out of scope: native GUI proof camera, catalog retag (S01), pick surface, live dogfood spend.

Proof:
swift test --package-path Packages/AllnighterCore --filter 'DesignBoard|WebKit|BoardCapture|DesignLane'

Done when: fixture design path writes board.options[].imagePath without imageGen; committed.
```

## Touch allowlist

- New: `Packages/AllnighterCore/Sources/AllnighterEngine/DesignBoardCapture.swift` (or similar thin name)
- `Packages/AllnighterCore/Sources/AllnighterEngine/CatalogRunCoordinator.swift`
- Tests under `Packages/AllnighterCore/Tests/**` for capture + board stage
- This sprint doc status → `done`

## Do not touch

- Deleted DesignCoordinator / DesignImageRunner (stay deleted)
- Chat imageGen spine
- Mac SwiftUI design studio

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter 'DesignBoard|BoardCapture|DesignLane'
```

## Done when

- [x] WebKit capture helper exists and is tested
- [x] designBoard runs append `.board` with PNGs (fixture path)
- [x] Failed capture ≠ silent diffusion
- [x] Committed
