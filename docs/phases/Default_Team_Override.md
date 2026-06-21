# Default Team Override

Status: Ready for Implementation
Owner: AllnighterCore + AllnighterCLI/MCP + Mac GUI
Updated: 2026-06-21

## Founder Intent

The user can edit or reset the Default Team without creating a duplicate visible
team.

Seed defaults are useful. Duplicate "Default" rows are not. The product should
feel like this:

```text
Open Default Team
-> change the worker/model/prompt
-> Save changes
-> the same Default Team is now changed
-> Restore returns it to the shipped seed
```

No second visible "Default Team." No "Default Team (custom)" clutter. No
duplicate required before the user can make the default their own.

## First Principles

Allnighter has two different concepts that must stay separate:

| Concept | Meaning | Example |
| --- | --- | --- |
| Default Team | The global no-preset run/chat team. `nil` team selection resolves here. | `default_chat` / Auto |
| Lane default | The default answer team when a lane is selected but no team is specified. | `code_core`, `design_core`, `copy_core` |

The bug comes from treating `default_chat` like an ordinary built-in team. For
ordinary built-ins, duplicate-to-edit is correct. For the global Default Team,
it is wrong because the user is trying to change the active default, not create a
second option.

The fix is not to mutate the shipped seed. The fix is to introduce one
effective Default Team:

```text
BuiltInTeams.defaultChat       immutable seed, bundled with the app
Catalogs/teams/default_chat    optional user override, same id, builtIn false
TeamCatalog.get("default_chat") returns override when present, else seed
```

The seed is the restore source. The override is the user's active Default Team.
Every list/show/run surface sees exactly one effective `default_chat`.

## Feature Packet

Allnighter Feature Packet

Status: Ready for Implementation

### Founder Intent

- Raw request: Let me edit or delete/reset the Default Team. Do not force me to
  have two default teams.
- Product value: The default path feels owned by the user instead of like a
  bundled sample that must be copied before it can be useful.
- Trusted workflow slice: edit Default Team -> save -> run default chat -> restore
  -> seed is active again.
- Non-goals:
  - Do not make every built-in team editable in place.
  - Do not migrate or delete existing local custom teams in this slice.
  - Do not change model/default-tier settings (`alln defaults`).
  - Do not change run execution safety, write locks, or worker driver behavior.
  - Do not include `execution_playbook` unless a separate founder decision says
    it should become shadowable too.

### Current State

- Existing truth owners:
  - `AllnighterCore.TeamCatalog`
  - `AllnighterCore.BuiltInTeams.defaultChat`
  - `TeamPreset`
  - `CatalogFileIO`
  - CLI/MCP registry in `ContractRegistry`
- Existing models/API paths:
  - `TeamCatalog.defaultRunTeam()` already checks for a custom non-built-in
    `default_chat` file.
  - `TeamCatalog.get(_:)` returns the built-in first, so an override is invisible
    to normal readers.
  - `TeamCatalog.all` / `mergeCustom` drops custom definitions whose id is
    reserved by a built-in.
  - `TeamCatalog.saveCustom` rejects built-in id collisions.
  - `TeamCatalog.deleteCustom` rejects built-in ids before checking whether an
    override file exists.
  - `TeamCatalogJSON.project` maps stored `isDefaultForLane` flags directly.
  - `TeamDraft.commit` duplicates any built-in base.
  - `TeamEditorView` labels built-in saves as "Duplicate Team."
- Existing parsers/generated outputs:
  - `docs/generated/alln/*` must be regenerated after registry/schema changes.
- Existing UI surfaces:
  - Team Studio inline editor.
  - Teams launcher edit drawer.
  - Composer model/team picker (`nil` team means Auto/Default Team).
- Existing tests/proof:
  - Catalog persistence tests cover ordinary duplicate-to-edit.
  - TeamDraft tests assert built-ins duplicate and stay untouched.
  - No kill test proves `default_chat` edits in place or lists exactly once.

### SSOT

- Truth owner: `TeamCatalog` owns seed/override/effective-team resolution.
- Lie-prone layers:
  - `TeamCatalog.get` can return the seed while `defaultRunTeam` returns the
    override.
  - Catalog list/projection can show seed plus override or multiple defaults.
  - SwiftUI can infer "built-in" means "duplicate" for the Default Team.
  - CLI/MCP can keep advertising duplicate-to-edit for a team that must edit in
    place.
- New semantic rules:
  - `default_chat` is a shadowable built-in team id.
  - The bundled `default_chat` is immutable seed truth.
  - A persisted `Catalogs/teams/default_chat.json` is the active user override.
  - `TeamCatalog.get("default_chat")`, `TeamCatalog.all`,
    `TeamCatalog.list(lane:)`, `TeamCatalog.defaultRunTeam()`, CLI, MCP, and GUI
    all resolve the same effective team.
  - The effective `default_chat` appears at most once in every catalog list.
  - Editing `default_chat` saves an override with the same id and `builtIn =
    false`.
  - Restoring `default_chat` deletes the override file and reveals the seed.
  - Deleting an overridden `default_chat` is reset/restore. Deleting the seed
    when no override exists remains blocked.
  - Ordinary built-ins remain duplicate-to-edit and non-deletable.
  - Per-lane default flags are computed at projection time; do not trust stored
    `isDefaultForLane` flags when a custom default masks a seed.
- Duplicate truth to delete:
  - The ad-hoc direct-file override check inside `defaultRunTeam`; it should
    delegate to the same effective lookup as `get`.
  - UI logic that equates all `builtIn` bases with duplicate-only saves.
  - Contract copy that says every built-in team must be duplicated before edit.

### Implementation

#### CLI surface

```bash
alln teams show default_chat [--json]
alln teams edit default_chat --file <team-preset-json> [--json]
alln teams restore default_chat [--json]
alln teams delete default_chat [--json]
alln teams --lane code [--json]
```

Rules:

- `teams show default_chat` returns the effective team.
- `teams edit default_chat` accepts a full replacement `TeamPreset` whose `id` is
  `default_chat`; Core forces `builtIn = false` before saving the override.
- `teams restore default_chat` is idempotent. It returns the effective seed and
  a machine flag saying whether an override was removed.
- `teams delete default_chat` removes the override when one exists and returns a
  delete/reset acknowledgement. If no override exists, it fails with
  `TEAM_BUILTIN_IMMUTABLE`.
- `teams --lane code --json` emits exactly one `default_chat` entry.

Additive JSON fields for team show/list responses:

```json
{
  "id": "default_chat",
  "displayName": "Auto",
  "builtIn": false,
  "origin": "override",
  "seedId": "default_chat",
  "restoreAvailable": true,
  "isDefaultForRun": true,
  "isDefaultForLane": false
}
```

`origin` values:

```text
seed       bundled built-in, no override active
override   user override of a shadowable built-in id
custom     ordinary custom team
builtIn    ordinary non-shadowed built-in team
```

Restore JSON:

```json
{
  "schemaVersion": 1,
  "contractVersion": "1",
  "id": "default_chat",
  "restored": true,
  "team": { "id": "default_chat", "origin": "seed" }
}
```

Exit codes and errors:

| Code | When |
| --- | --- |
| `TEAM_NOT_FOUND` | Unknown TeamID |
| `TEAM_BUILTIN_IMMUTABLE` | Edit/delete/restore non-shadowable built-in, or delete `default_chat` when only the seed exists |
| `TEAM_RESTORE_UNSUPPORTED` | Restore requested for a team id that is not shadowable |
| `TEAM_INVALID` | Replacement definition fails validation |
| `SKILL_LANE_MISMATCH` | Replacement row references a skill from another lane |
| `CATALOG_ID_INVALID` | Replacement id fails canonical rules |

#### MCP tools

MCP mirrors CLI and uses the same schemas:

```text
teams_show
teams_save
teams_restore
teams_delete
teams_list
```

`teams_restore` args:

```json
{ "teamId": "default_chat" }
```

Returns the same restore JSON as CLI. `teams_delete` has the same reset semantics
as CLI when an override exists.

#### Core impact

- Add `TeamCatalog.shadowableBuiltInTeamIDs` with only `default_chat` in this
  slice.
- Add `TeamCatalog.isShadowableBuiltIn(_:)`.
- Add `TeamCatalog.hasOverride(_:)`.
- Add `TeamCatalog.restoreBuiltInOverride(_:)`.
- Change `TeamCatalog.get(_:)` so a shadowable override wins over the seed.
- Change `TeamCatalog.all` / merge logic so a shadowable override replaces the
  seed in the list instead of being filtered out.
- Change `TeamCatalog.defaultRunTeam()` to call `get("default_chat")`.
- Change `TeamCatalog.saveCustom(_:)` to allow id collision only for shadowable
  built-in ids, with normal validation and forced `builtIn = false`.
- Change `TeamCatalog.deleteCustom(_:)` to delete an override file before
  applying the ordinary built-in immutable block.
- Normalize effective per-lane default flags before projecting or printing.
- Defensively force loaded shadow overrides to `builtIn = false`.

#### Mac app impact

- Team Studio and the Teams edit drawer treat `default_chat` as editable in
  place.
- Footer copy:
  - Seed active: `Save changes`
  - Override active: `Save changes` plus `Restore`
  - Ordinary built-in: `Duplicate Team`
  - Ordinary custom: `Save changes`
- Saving a `default_chat` seed draft writes the override id `default_chat`, not a
  `custom_code_*` duplicate.
- Restore removes the override and reloads the seed draft.
- Favorite/star treatment remains: Default Team is always featured and cannot be
  unstarred.
- The GUI never writes catalog files directly; it calls catalog APIs.

#### iOS impact

No iOS editing in this slice. Future iOS readers must receive the effective
team from the Mac/Core projection and must not render seed plus override.

#### WebSocket/protocol impact

No new WebSocket message is required for this slice unless the GUI moves catalog
editing behind a local API. If that happens, the API must expose the same
restore/edit/delete semantics as CLI/MCP.

#### Agent driver impact

None. The selected worker/model changes through `TeamPreset`; worker drivers
receive the already-resolved prompt as before.

#### Auth/privacy/permissions impact

No new permissions. The override file is local Application Support catalog data.
Do not sync or export override prompt content without a future export/privacy
spec.

## Implementation Slices

### DTO-S00 - SSOT and tests first

- Add this phase doc and route it from the phase board and catalog docs.
- Add failing Core tests for:
  - `TeamCatalog.get("default_chat")` returns the override when present.
  - `TeamCatalog.all` / `list(.code)` contains exactly one `default_chat`.
  - `defaultRunTeam()` resolves through the same effective lookup.
  - restore/delete reveals the seed.
  - ordinary built-in id collision still fails.
  - `TeamCatalogJSON.project` emits exactly one `isDefaultForLane` winner when a
    custom lane default masks a seed.

### DTO-S01 - Core effective catalog semantics

- Implement shadowable built-in lookup, save, list, delete, and restore.
- Remove the ad-hoc direct-file lookup from `defaultRunTeam`.
- Normalize effective default flags at the catalog/projection boundary.
- Focused proof:

```bash
swift test --package-path Packages/AllnighterCore --filter TeamCatalog
swift test --package-path Packages/AllnighterCore --filter CatalogPersistence
```

### DTO-S02 - CLI/MCP contract

- Add `alln teams restore`.
- Allow `alln teams edit default_chat`.
- Make `alln teams delete default_chat` reset an existing override.
- Add `teams_restore` MCP tool.
- Update `ContractRegistry`, schemas, examples, error copy, and generated
  artifacts.
- Focused proof:

```bash
swift test --package-path Packages/AllnighterCore --filter CatalogCLI
swift test --package-path Packages/AllnighterCore --filter ContractRegistry
alln dev export-contracts --check
```

### DTO-S03 - Mac Team Studio / drawer

- Replace built-in duplicate-only branching with save mode:

```text
saveShadowOverride(default_chat)
duplicateOrdinaryBuiltIn
saveCustom
createNewCustom
```

- Add Restore affordance when `TeamCatalog.hasOverride("default_chat")` is true.
- Add TeamDraft tests proving Default Team saves in place while `code_core` still
  duplicates.
- Add/refresh GUI fixture for the Default Team editor and restore state.
- Focused proof:

```bash
xcodebuild test -project Apps/AllnighterMac/AllnighterMac.xcodeproj -scheme AllnighterMac -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:AllnighterMacTests/TeamDraftTests
bash scripts/gui_proof.sh studio-default-team-editor
```

### DTO-S04 - Works Test and closeout

- Run the owner-visible CLI scenario below.
- Run the green wall.
- Add DEBUGLOG entry because this is a founder-found T2 SSOT bug.

## Works Test

Setup:

- Use a temp catalog root or a safe local backup of
  `~/Library/Application Support/Allnighter/Catalogs`.
- Prepare a fixture `fixtures/teams/default_chat_codex_override.json` with
  `id: "default_chat"`, `builtIn: false`, one worker, and a changed display name.

Command scenario:

```bash
alln teams show default_chat --json | jq -e '.origin == "seed" and .id == "default_chat"'
alln teams edit default_chat --file fixtures/teams/default_chat_codex_override.json --json \
  | jq -e '.id == "default_chat" and .origin == "override" and .restoreAvailable == true'
alln teams --lane code --json \
  | jq -e '[.teams[] | select(.id == "default_chat")] | length == 1'
alln teams show default_chat --json \
  | jq -e '.displayName == "Auto Codex" and .builtIn == false'
alln teams restore default_chat --json \
  | jq -e '.restored == true and .team.id == "default_chat"'
alln teams show default_chat --json \
  | jq -e '.origin == "seed" and .restoreAvailable == false'
```

Founder test:

```text
Open Team Studio -> Default Team.
Change the model or prompt.
Click Save changes.
The roster still shows one Default Team.
Reopen it and see the change.
Click Restore.
The same row returns to the shipped Auto seed.
```

## Inference Bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Built-in id -> edit behavior | `TeamCatalog` | Every built-in id must duplicate before edit | Only non-shadowable built-ins duplicate; `default_chat` saves an override | `teams edit default_chat` succeeds; `teams edit code_core` still fails or duplicates through GUI |
| Catalog file -> visible entry | `TeamCatalog.all` | A custom file with a built-in id should be hidden as collision noise | Shadowable ids replace the seed; non-shadowable collisions remain hidden/rejected | `list(.code)` has exactly one `default_chat` |
| Detail lookup -> seed | `TeamCatalog.get` | Built-ins always win over files | Shadow override wins for `default_chat` only | `get("default_chat")` returns override display name after save |
| Delete -> destructive removal | `TeamCatalog.deleteCustom` | Delete of Default Team removes the product seed | Delete removes only the override; seed remains available | Delete override, then `get("default_chat")` returns seed |
| Default flags -> JSON | `TeamCatalogJSON.project` | Stored `isDefaultForLane` flags are already effective | Projection computes the effective single default per lane | Custom lane default plus built-in seed emits one default |
| GUI builtIn -> duplicate button | `TeamEditorView` | `builtIn` means "Duplicate Team" | `default_chat` seed means "Save changes" with restore semantics | TeamDraft saves Default Team in place; ordinary built-in still duplicates |
| MCP -> separate schema | `ContractRegistry` | MCP can return a smaller restore shape | MCP returns the same schema as CLI | CLI/MCP restore JSON parity test |

## Done When

- `TeamCatalog.get`, `all`, `list`, `defaultRunTeam`, CLI, MCP, and Mac GUI all
  agree on the same effective Default Team.
- `default_chat` appears once in every catalog list.
- Editing `default_chat` creates or updates one override at the same id.
- Restore/delete removes only the override and reveals the seed.
- Ordinary built-ins still cannot be edited or deleted in place.
- CLI/MCP contract and generated docs include restore semantics.
- Mac Team Studio says `Save changes` for Default Team, not `Duplicate Team`.
- Focused tests and the Works Test pass.
- GUI fixture receives layout-watcher PASS.
- DEBUGLOG records the T2 SSOT fix and proof command.

## Open Questions

1. Should `execution_playbook` become shadowable in a later slice? This packet
   intentionally says no for now to avoid accidentally making all built-ins
   editable in place.
2. Should `teams restore default_chat` be the only reset command, or should
   `teams delete default_chat` also reset when an override exists? This packet
   recommends both: restore is explicit; delete on an existing override is a
   reset because the visible thing is user-owned.
3. Should team detail JSON expose prompt/template snapshots by default, or keep
   them behind a future `--full` flag? This packet does not change current
   template exposure rules.
