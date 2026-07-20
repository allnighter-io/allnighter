# MR-S01 — Build the real menu

Status: **complete**
SSOT: `docs/archive/phases/Menu_Not_Router.md` §Implementation slices MR-S01 + §The end-state interface

## Goal

Ship Core-owned `MenuCatalog` plus `alln menu --json` / `alln menu show <ref> --json`
as the compact, complete, gated agent front door — without deleting router-era
commands yet (that is MR-S02).

## Slice packet

```text
Slice: MR-S01
Goal: One live MenuCatalog projection + menu / menu show CLI + gates
Out of scope: router deletion, bootstrap rewrite, display-name dispatch, cold-agent matrix
Truth owner: MenuCatalog (projection) + ContractRegistry (command rows/visibility/effects)
Lie-prone layer: hand-authored menu beside registry; truncated/paginated menu; actions as second taxonomy
Works Test: see below
Proof command: swift test --package-path Packages/AllnighterCore --filter MenuCatalog
Missing proof / waiver: full Works Test matrix waits for MR-S02+; this slice proves menu completeness gates
Done when: menu --json encodes ≤32 KiB built-in fixture; unique refs; completeness booleans; menu show hydrates typed refs
```

## Read first

- `docs/archive/phases/Menu_Not_Router.md` (MR-S01 + end-state interface + compact field table)
- `Packages/AllnighterCore/Sources/AllnighterCore/CommandsManifestJSON.swift` (projection pattern)
- `Packages/AllnighterCore/Sources/AllnighterCore/CatalogJSON.swift` (team active/blocked)
- `Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry.swift` (CommandSpec)

## Touch allowlist (implementer may add new files under these trees)

- `Packages/AllnighterCore/Sources/AllnighterCore/MenuCatalog.swift` (new)
- `Packages/AllnighterCore/Sources/AllnighterCore/MenuJSON.swift` (new — or colocated)
- `Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/ContractSchema.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/ContractExport.swift`
- `Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift` (menu dispatch only)
- `Packages/AllnighterCore/Sources/AllnighterCLI/MenuCLI.swift` (new, preferred)
- `Packages/AllnighterCore/Tests/AllnighterCoreTests/MenuCatalogTests.swift` (new)
- `scripts/verify_menu_contract.py` (new)
- `docs/generated/alln/*` (via `alln dev export-contracts` only)
- this sprint doc status

## Do not

- Delete `AgentIntentRouter`, `team hello`, `route`, `resolve`, or `commands`
- Rewrite bootstrap / TeachingSnippet
- Change run dispatch / display-name matching (MR-S04)
- Broad cleanup outside allowlist
- Commit `BuildInfo.swift` if dirty and unrelated

## Steps

1. Extend `CommandSpec` with registry-owned `visibility` (`public|developer|internal`, default public for existing M1), optional `menuAction: Bool` (or tag) for fast-path `actions`, and structured `effects` (`EffectProfile` with `never|always|dependsOnFlags|dependsOnSelection` for workerStart/quotaSpend/repoWrite/destructive/humanInteraction). Add `OutputSchema.menuJSON` / `menuShowJSON`.
2. Implement `MenuCatalog.project(...)` returning Tier-1 `MenuJSON`: actions, commands, teams, models, recipes, effectProfiles, defaults, completeness, `truncated: false`, `contractVersion`, `contractHash`, `catalogRevision`. Compact rows per phase field table. One top-level `detailTemplate`. Target-bound `runTemplate` / `validateTemplate` on team/model rows.
3. Implement `MenuCatalog.show(ref:)` for typed refs (`command:`, `team:`, `model:`, `recipe:`). Unknown ref → structured same-kind suggestions (error path).
4. Wire `alln menu` / `alln menu show` in CLI; register CommandSpecs; bump `contractVersion` (minor additive, e.g. 1.7.0); regenerate contracts.
5. Add XCTest gates: completeness, unique refs, deterministic ordering, ≤32 KiB built-in fixture encode, every public command row present, every effective team/model/recipe present, actions ⊆ tagged public commands 1:1.
6. Add `scripts/verify_menu_contract.py` matching phase Works Test flags.

## Works Test

```bash
swift build -c release --package-path Packages/AllnighterCore --product alln
B=Packages/AllnighterCore/.build/release/alln
$B menu --json > /tmp/alln-menu.json
/usr/bin/python3 scripts/verify_menu_contract.py /tmp/alln-menu.json \
  --max-built-in-bytes 32768 --require-complete --require-unique-refs
$B menu show command:run --json >/dev/null
$B menu show team:code_growth --json >/dev/null
$B menu show model:model_sonnet --json >/dev/null
swift test --package-path Packages/AllnighterCore --filter MenuCatalog
$B dev export-contracts --check
```

## Done when

- [x] `alln menu --json` returns complete untruncated MenuJSON
- [x] `alln menu show <typed-ref> --json` hydrates all four kinds
- [x] Built-in fixture ≤32 KiB; unique refs; completeness booleans true
- [x] Every parser-accepted public command has visibility; unregistered branches unchanged this slice but public M1 rows are visibility-tagged
- [x] `actions` generated only from tagged command specs
- [x] Contract lock regenerated after version bump
- [ ] Committed as one slice commit

## SSOT

`docs/archive/phases/Menu_Not_Router.md` — MR-S01
