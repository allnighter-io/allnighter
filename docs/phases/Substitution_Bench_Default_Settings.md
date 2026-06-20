# Substitution Bench - Default Settings

Status: Draft CLI/MCP-first feature packet
Owner: AllnighterCore + AllnighterCLI + MCP + Mac GUI
Updated: 2026-06-20

## Founder Intent

Raw request:

- Default Settings should let users pick the global default model.
- `Auto` should sit at the top of model dropdowns as a real default choice.
- "Allow healthy substitutions" is currently undefined and therefore
  untrustworthy.
- Healthy substitution should use buckets such as Flagship, Balanced, and Fast.
- Allnighter assigns sensible default buckets, and users can override them.
- A substitution can cross CLIs, because cross-CLI recovery is part of the
  product value.
- A substitution must never silently move to a higher bucket or lower bucket.
- If the chosen bucket has no ready model, work waits. The user can update
  settings or explicitly route the work elsewhere.
- MCP must expose the same capability first class. The GUI cannot become the
  only owner of this rule.

Product value:

Allnighter turns "use another ready model" from a vague fallback into a trusted
contract:

```text
If a model is down, use another ready model on the same substitute shelf.
Never silently upgrade. Never silently downgrade. If the shelf is empty, wait.
```

The same shelves also make global `Auto` legible:

```text
Default: Auto on Flagship
-> Allnighter uses the best ready Flagship model.
-> If one Flagship model is down, another ready Flagship model may run.
-> If no Flagship model is ready, the work waits.
```

Trusted workflow slice:

```text
open Default Settings
-> set Default to Auto
-> choose the Flagship shelf
-> verify Opus and ChatGPT are on Flagship, Sonnet is Balanced, Gemini Flash is Fast
-> move a custom Claude model from Balanced to Flagship
-> enable healthy substitutions
-> start a default chat while Opus is unavailable
-> resolver chooses a ready Flagship model from another CLI
-> start again with every Flagship model unavailable
-> work blocks/waits with an exact setting/action, not a silent downgrade
```

Non-goals:

- No cost, runtime, token, quota, or task-complexity forecasting.
- No provider-price database.
- No silent cross-shelf fallback, even from Flagship to Balanced.
- No GUI-only Settings semantics.
- No separate model roster. The substitution bench consumes `ModelCatalog` and
  Bench truth; it does not replace them.
- No automatic live model discovery in this phase.
- No team-depth or effort slider. Provider reasoning effort remains a separate
  model/worker setting.
- No migration burden for public users.

## Current State

Useful substrate:

- `ModelCatalog` owns known models, custom models, Bench membership, model
  capabilities, and deterministic `strengthRank`.
- `alln models --json` is the public model catalog and Bench state contract.
- `ModelFallbackPolicy` exists with `exactOnly`, `sameSource`, `laneCapable`,
  `anyReady`, and `strongestReady`.
- `TeamResolver.selectModel` already resolves from the ready Bench and sorts by
  `strengthRank`.
- Mac `TeamEditorView` has an "Allow healthy substitutions" toggle.
- MCP tools are registry-projected and already include model/team surfaces.

Current gap:

- "Healthy substitution" currently means broad lane-capable fallback in the Mac
  team editor.
- There is no durable substitution shelf/group owner.
- `strengthRank` is a resolver preference, not a user-governed equivalence
  contract.
- There is no global Default Settings contract for `Auto on <shelf>`.
- There are no CLI commands or MCP tools for viewing or editing default model
  settings and substitution shelves.
- A GUI could accidentally define shelves locally unless this contract lands in
  Core/CLI/MCP first.

Existing truth owners:

| Fact | Current owner | Problem |
| --- | --- | --- |
| Known models and Bench state | `ModelCatalog` | Correct owner for models, but not shelf membership. |
| Model readiness | `SetupStore` / `ToolProbeRecord` | Correct owner; must stay separate from shelf membership. |
| Resolver fallback behavior | `TeamResolver` / `ModelFallbackPolicy` | Existing fallback is too broad for "healthy". |
| Mac substitution toggle | `TeamEditorView` draft state | UI-only wording; not durable semantics. |
| MCP tool descriptors | `ContractRegistry` | Must gain parity for default/substitution tools before GUI-only promises. |

## SSOT

Truth owner:

```text
AllnighterCore.DefaultModelSettings
AllnighterCore.SubstitutionBenchState
AllnighterCore.SubstitutionShelf
AllnighterCore.SubstitutionResolver
```

Model definitions stay in `ModelCatalog`. Bench membership stays in
`ModelRosterState`. Substitute shelf membership is a separate user settings
overlay:

```text
ModelCatalog + ModelRosterState + SetupStore readiness + SubstitutionBenchState
-> resolver candidates
```

The shelf is not a property of the model definition and not a property of the
CLI/source. It is a user-governed substitute group. A model can be moved between
groups without changing its model label, driver, custom definition, capability
tags, or Bench membership.

CLI/MCP authority:

```text
Core state -> alln defaults/substitutions JSON -> MCP tools -> GUI/iOS renderers
```

The Mac GUI may call Core directly inside the app process, but it must consume
the same projections and semantics exposed by CLI/MCP. No SwiftUI-local
substitution shelf shape may become durable truth.

Lie-prone layers:

- SwiftUI Settings rows and dropdowns.
- The existing "Allow healthy substitutions" toggle text.
- `ModelCapabilities.strengthRank`.
- Team presets with `fallbackPolicy == .laneCapable`.
- MCP clients that only see `models_list` and guess fallback safety.
- Generated help/examples if not refreshed from the registry.

New/changed semantic rules:

- `Auto` is a first-class default model selection, not a concrete hidden model.
- Global `Auto` always names a substitution shelf, e.g. `Auto on Flagship`.
- Built-in shelves are `flagship`, `balanced`, and `fast`.
- Allnighter ships default shelf membership for built-in models.
- Users can override a model's shelf membership.
- A model may belong to at most one built-in substitution shelf in v1.
- Off-Bench models may have shelf membership, but only ready Bench models are
  runnable candidates.
- Healthy substitution means same shelf only.
- Healthy substitution may cross CLIs/sources when the shelf matches.
- Healthy substitution never crosses shelves silently.
- If no ready Bench model exists in the required shelf, the run blocks or waits.
- Work that must wait reports a typed blocker and exact next actions.
- `strengthRank` can order candidates inside a shelf, but it cannot assign shelf
  membership and cannot authorize cross-shelf fallback.
- Existing `laneCapable` fallback is not the public meaning of healthy
  substitution after this phase.

Duplicate truth to delete:

- UI-local "healthy means lane-capable" copy.
- Any Settings-only shelf arrays.
- Any MCP-only model/default JSON parallel to the CLI/Core contract.
- Any docs/help examples that imply `Auto` means strongest ready model across the
  whole Bench.

## Definitions

### Default Model Selection

The global setting used by default chat and other surfaces that say "Default":

```swift
public enum DefaultModelSelection: Codable, Sendable, Equatable {
    case auto(shelfId: SubstitutionShelfID)
    case pinned(modelId: ModelID)
}
```

Rules:

- Fresh install default: `auto(shelfId: "flagship")`.
- A pinned default model must be a known model and should be on the Bench.
- If a pinned default model is down and healthy substitutions are allowed, the
  resolver uses the pinned model's shelf.
- If a pinned model has no shelf assignment, substitutions are blocked until the
  user assigns it or chooses a different default.

### Substitution Shelf

The product-facing shelves are:

| ID | Display label | Meaning |
| --- | --- | --- |
| `flagship` | Flagship | Best models for important/high-judgment work. |
| `balanced` | Balanced | Strong everyday models. |
| `fast` | Fast | Quick/light models and intentionally lower-caliber variants. |

Labels are user-facing, but the substitution rule is not based on price or
forecasting. The rule is group equality:

```text
preferred model shelf == candidate model shelf
```

No silent shelf crossing exists in v1.

### SubstitutionBenchState

Local user settings overlay:

```swift
public typealias SubstitutionShelfID = String

public struct SubstitutionBenchState: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var assignments: [SubstitutionShelfID: [ModelID]]
    public var updatedAt: Date?
}
```

Rules:

- If no state file exists, built-in default assignments apply.
- Once a state file exists, it is the complete shelf membership overlay.
- A model ID can appear in at most one shelf.
- Unknown model IDs are ignored for resolution and diagnosed.
- New built-in/custom models get Allnighter's default assignment only when no
  state file exists; after the user customizes shelves, new models appear
  unassigned until Allnighter explicitly adds an upgrade rule.
- Deleting a custom model removes it from shelf assignments.
- Disabling a model removes it from runnable candidates but does not erase shelf
  membership.

Suggested fresh-install default assignments:

| Shelf | Built-ins |
| --- | --- |
| Flagship | `model_opus`, `model_chatgpt`, `model_agy_opus` |
| Balanced | `model_sonnet`, `model_cursor_auto`, `model_cursor_composer_25`, `model_grok`, `model_gemini_pro`, `model_agy_sonnet`, `model_agy_gptoss` |
| Fast | `model_gemini`, `model_composer`, `model_cursor_composer_25_fast`, `model_chatgpt_54_mini`, `model_codex_spark` |

`model_chatgpt_54`, `model_fable`, and other default-off recognized models need
a product/default decision during implementation. Until then, they can be
unassigned or assigned by the model-catalog slice that introduces them.

### DefaultModelSettings

```swift
public struct DefaultModelSettings: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var defaultSelection: DefaultModelSelection
    public var allowHealthySubstitutions: Bool
    public var updatedAt: Date?
}
```

Fresh install:

```json
{
  "schemaVersion": 1,
  "defaultSelection": { "kind": "auto", "shelfId": "flagship" },
  "allowHealthySubstitutions": true
}
```

Storage:

```text
~/Library/Application Support/Allnighter/Config/default_model_settings.json
~/Library/Application Support/Allnighter/Config/substitution_bench.json
```

Keep IO behind private persistence helpers. Do not introduce public `Store`
vocabulary.

## Resolver Contract

Resolution inputs:

```text
default settings
substitution shelf assignments
full model catalog projection
ready Bench
team/worker requested model or Auto
team fallback policy
```

Candidate construction:

1. Determine the required shelf.
   - `Auto`: selected shelf from `DefaultModelSelection.auto`.
   - Pinned model: shelf containing that model.
   - Team row with preferred model: shelf containing the preferred model when
     the row's fallback policy allows healthy substitution.
2. Filter candidates to ready Bench models in that shelf.
3. Filter by lane/capability tags required by the team row.
4. Pick deterministically by `strengthRank` descending, then stable model ID.
5. If no candidate remains, block/wait. Do not cross shelves.

Required resolver outcomes:

| Case | Outcome |
| --- | --- |
| Auto on Flagship; Opus down; ChatGPT ready | Run ChatGPT. |
| Auto on Flagship; no Flagship ready | Block/wait with `SUBSTITUTION_SHELF_EMPTY`. |
| Pinned Opus; substitutions on; ChatGPT in Flagship ready | Run ChatGPT with warning/provenance. |
| Pinned Opus; substitutions off | Block if Opus is not ready. |
| Pinned Opus; only Balanced ready | Block/wait, no silent downgrade. |
| Pinned model unassigned | Block with `SUBSTITUTION_MODEL_UNASSIGNED`. |
| Gemini Flash in Fast down; another Fast model ready | May substitute within Fast. |

Run provenance:

Every substituted run must record both requested and resolved model facts:

```json
{
  "requestedModelId": "model_opus",
  "resolvedModelId": "model_chatgpt",
  "substitution": {
    "applied": true,
    "shelfId": "flagship",
    "reason": "requested model not ready",
    "crossSource": true
  }
}
```

This may land as an additive field on worker/run JSON once the contract registry
is updated. Until then, warnings must include the same facts in structured form
where available.

## CLI Contract

`alln defaults` and `alln substitutions` are the headless contract for Default
Settings. They must land in the command registry before GUI promises the feature.

Grammar:

```bash
alln defaults show [--json]
alln defaults set --model auto [--shelf flagship|balanced|fast] [--json]
alln defaults set --model <model-id> [--json]
alln defaults substitutions --allow true|false [--json]

alln substitutions list [--json]
alln substitutions assign <model-id> --shelf flagship|balanced|fast [--json]
alln substitutions remove <model-id> [--json]
alln substitutions reset [--json]
```

Rules:

- JSON mode prints exactly one `DefaultSettingsJSON` object to stdout.
- Human warnings and recovery guidance go to stderr in machine modes.
- Mutating commands write atomically and then print the refreshed
  `DefaultSettingsJSON`.
- `alln defaults set --model auto` requires a shelf when no previous Auto shelf
  exists; otherwise it preserves the current Auto shelf.
- `alln defaults set --model <model-id>` rejects unknown models.
- `substitutions assign` accepts known models whether enabled or off-Bench.
- Resolution only uses ready Bench models.
- `substitutions reset` restores built-in defaults and clears user overrides.

Output JSON (`DefaultSettingsJSON`):

```json
{
  "schemaVersion": 1,
  "contractVersion": "0.1.0",
  "default": {
    "selectionKind": "auto",
    "modelId": null,
    "shelfId": "flagship",
    "allowHealthySubstitutions": true
  },
  "shelves": [
    {
      "id": "flagship",
      "displayName": "Flagship",
      "modelIds": ["model_opus", "model_chatgpt"],
      "onBenchModelIds": ["model_opus", "model_chatgpt"],
      "readyModelIds": ["model_chatgpt"]
    }
  ],
  "models": [
    {
      "id": "model_opus",
      "displayName": "Opus 4.8",
      "driverId": "claude_code",
      "enabled": true,
      "ready": false,
      "shelfId": "flagship",
      "state": "onBench"
    }
  ],
  "diagnostics": []
}
```

Exit codes:

| Exit | Meaning |
| --- | --- |
| `0` | Success; JSON payload emitted under `--json`. |
| `2` | Usage/validation error, such as missing shelf or unknown flag. |
| `3` | Operational setup/catalog error, such as unreadable settings file. |
| `4` | Contract/runtime error envelope for known model/shelf blockers. |

Error codes:

| Code | Meaning | Agent action |
| --- | --- | --- |
| `DEFAULT_MODEL_UNKNOWN` | Requested default model ID does not exist. | Call `models_list`, then retry with a known model. |
| `DEFAULT_MODEL_OFF_BENCH` | Requested default model is known but not enabled. | Enable the model or choose Auto/a Bench model. |
| `SUBSTITUTION_SHELF_UNKNOWN` | Shelf ID is not one of the built-in shelves. | Use `substitutions list`. |
| `SUBSTITUTION_MODEL_UNKNOWN` | Assignment target model does not exist. | Call `models_list`, then retry. |
| `SUBSTITUTION_MODEL_UNASSIGNED` | A pinned model needs substitution but has no shelf. | Assign the model to a shelf or disable substitutions. |
| `SUBSTITUTION_SHELF_EMPTY` | No ready Bench model exists in the required shelf. | Wait, enable/add a model in the shelf, or explicitly choose another shelf/model for this run. |
| `SUBSTITUTION_STATE_INVALID` | Settings file has duplicate/invalid assignments. | Run reset or repair through the offered command. |

## MCP Contract

MCP is first class for this feature. The following tools must be generated from
the same registry as the CLI commands:

```text
defaults_get
defaults_set
defaults_set_substitutions
substitutions_list
substitutions_assign
substitutions_remove
substitutions_reset
```

Tool behavior:

- All tools return the same `DefaultSettingsJSON` shape or the standard error
  envelope.
- `defaults_get` is read-only and cheap.
- `substitutions_list` is read-only and cheap.
- Mutating tools are local file writes only and must be idempotent where
  possible.
- MCP clients can configure default Auto/shelf behavior without opening the Mac
  GUI.
- `mcp_hello` should eventually advertise whether defaults/substitution tools
  are available and whether descriptors match the binary contract version.

Example MCP flow:

```text
agent calls defaults_get
-> sees Auto on Flagship
-> calls substitutions_list
-> sees no ready Flagship models
-> presents "Flagship is empty; wait or explicitly switch this run"
-> does not call a lower shelf automatically
```

MCP parity proof:

```bash
alln defaults show --json
alln substitutions list --json
alln mcp serve --stdio
# MCP defaults_get returns the same default/shelf/model projection
# MCP substitutions_assign mirrors CLI substitutions assign
alln dev export-contracts --check
```

## Model/Package Impact

Core:

- Add `DefaultModelSelection`.
- Add `DefaultModelSettings`.
- Add `SubstitutionShelfID`.
- Add `SubstitutionShelf`.
- Add `SubstitutionBenchState`.
- Add persistence helpers under `Config/`.
- Add `SubstitutionResolver` or extend `TeamResolver` behind a clear seam.
- Add diagnostics and error-envelope mapping.

`ModelCatalog`:

- Keep model definitions and Bench membership ownership unchanged.
- Expose enough projection for shelf JSON: known models, enabled state, ready
  state, display name, driver ID, and model state.
- Do not store shelf membership in `ModelDefinition`.

`TeamResolver`:

- Keep existing fallback policies for internal/legacy behavior during migration.
- Add a healthy-substitution resolution path that filters by shelf before rank.
- Replace Mac team's "allow substitutions -> laneCapable" save behavior with the
  shelf-aware policy once Core support exists.

`TeamRunJSON`:

- Add substitution provenance once registry/schema is updated, or attach
  structured warning objects if that lands sooner.

## Mac App Impact

Default Settings screen:

- Default control:
  - model picker with `Auto` pinned at the top;
  - when `Auto` is selected, show shelf picker: Flagship / Balanced / Fast;
  - when a concrete model is selected, show its assigned shelf.
- Substitutions control:
  - switch: `Allow healthy substitutions`;
  - helper copy: "If a model is down, use another ready model on the same shelf.
    Never upgrades or downgrades silently.";
  - compact shelf legend showing models by Flagship, Balanced, Fast;
  - action to move models between shelves.
- Empty shelf state:
  - show the shelf as empty/not ready;
  - explain that work waits unless the user changes settings or explicitly
    routes this run elsewhere.

Team editor cleanup:

- Existing "Allow healthy substitutions" must use the same Core resolver
  semantics.
- Copy must no longer say "another ready model in this lane" once shelf-aware
  substitution exists.
- Team-level toggles may remain, but they are policy consumers, not owners.

The GUI must not persist shelf state in SwiftUI-only storage. It calls Core or
CLI-equivalent services and renders `DefaultSettingsJSON`-equivalent facts.

## iOS App Impact

iOS is deferred, but the contract must be ready:

- iOS may show Default Settings read-only or editable after pairing policy allows
  remote settings changes.
- iOS must call the same local Mac API/CLI/MCP-backed contract.
- iOS must not invent a second shelf model.

## Driver/Protocol Impact

Driver manifests do not need a schema change.

Driver/source readiness continues to come from setup/Doctor state. A model's
source being ready does not make the model enabled, and neither source readiness
nor model enablement assigns a shelf.

Cross-CLI substitution is allowed when the shelf matches and the candidate model
is on the ready Bench. Mutating/execute teams still obey the execution source
gate from `Work_Order_Team_Model.md`; substitution cannot turn a single-source
execution requirement into mixed-source execution.

## Auth/Privacy/Permissions Impact

- Settings mutations are local file writes under Application Support.
- No credentials, Keychain values, or API keys are read.
- No vendor CLI is spawned by viewing or editing substitution shelves.
- No network access is required.
- MCP callers can mutate local settings; if client approval/provenance gates are
  enabled, these tools must obey the same gate as other MCP write tools.

## Implementation Slices

### SBDS-S00 - Phase Doc And Routing

Status: This document.

Done when:

- Phase doc exists.
- `docs/phases/README.md` routes Default Settings / healthy substitutions here.

### SBDS-S01 - Core State And Persistence

Backend:

- Add Core types for default selection, settings, shelves, and assignments.
- Add default fresh-install shelf assignment.
- Add load/save/reset persistence.
- Add diagnostics for duplicate/unknown assignments.
- Keep assignments outside `ModelDefinition`.

Tests:

- Fresh install defaults to Auto on Flagship with substitutions allowed.
- Built-in assignments load deterministically.
- A model cannot appear in two shelves.
- Unknown model IDs are diagnosed and ignored for resolution.
- Reset restores default assignments.

### SBDS-S02 - CLI And MCP Registry

Backend/CLI/MCP:

- Add command specs for `alln defaults` and `alln substitutions`.
- Add MCP descriptors for the matching tools.
- Add `DefaultSettingsJSON` schema/example.
- Mutating commands and tools print/return the refreshed envelope.
- Regenerate generated contract artifacts.

Tests:

- `alln defaults show --json` emits one `DefaultSettingsJSON`.
- `alln defaults set --model auto --shelf balanced --json` persists.
- `alln defaults substitutions --allow false --json` persists.
- `alln substitutions assign model_sonnet --shelf flagship --json` persists.
- MCP `defaults_get` matches CLI projection.
- MCP `substitutions_assign` matches CLI mutation result.
- `alln dev export-contracts --check` passes.

### SBDS-S03 - Shelf-Aware Resolver

Backend:

- Add a resolver path for Auto and healthy substitution.
- Filter candidate models to ready Bench plus required shelf.
- Keep lane/capability filtering inside the shelf.
- Add structured substitution provenance.
- Ensure no silent cross-shelf fallback exists.

Tests:

- Auto on Flagship chooses a ready Flagship model.
- Auto on Flagship blocks when only Balanced/Fast models are ready.
- Pinned Opus can substitute to ChatGPT when both are Flagship.
- Pinned Opus cannot substitute to Sonnet when Sonnet is Balanced.
- Substitution can cross CLIs inside the same shelf.
- Pinned unassigned model blocks with a typed error.

### SBDS-S04 - Team Fallback Policy Integration

Backend/Mac:

- Replace GUI "healthy -> laneCapable" save semantics with shelf-aware healthy
  fallback.
- Decide whether `ModelFallbackPolicy` gains a `sameShelf` case or whether
  existing policies call `SubstitutionResolver` through separate settings.
- Preserve exact-only behavior when substitutions are off.
- Ensure mutating execution teams still satisfy the single-source execution gate.

Tests:

- Custom team with substitutions on uses same-shelf fallback.
- Custom team with substitutions off uses exact-only fallback.
- Existing built-in teams do not silently broaden to lane-capable substitution.
- Mutating team does not cross source through substitution unless the team
  resolves to one execution source.

### SBDS-S05 - Mac Default Settings Surface

Mac:

- Add/edit Default Settings surface.
- Pin `Auto` above concrete models.
- Add shelf picker for Auto.
- Add healthy substitution toggle.
- Add shelf legend and reassignment controls.
- Render empty shelf/wait state.

Proof:

- GUI visual proof required.
- User-visible Works Test required before claiming this slice done.

### SBDS-S06 - Duplicate Truth Cleanup

Backend/docs:

- Remove UI-local healthy-substitution copy that says lane-only.
- Refresh generated CLI/MCP help.
- Update docs that describe `Auto` as strongest ready across the whole Bench.
- Add contract drift checks where feasible.

Tests:

- Search/docs check finds no user-facing "healthy substitutions" definition that
  conflicts with same-shelf semantics.
- `swift test` passes.
- `alln dev export-contracts --check` passes.

## Inference Bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| `strengthRank` -> shelf | `SubstitutionBenchState` | High rank means Flagship, low rank means Fast. | Rank orders candidates inside a shelf only; it never assigns membership. | Move Sonnet to Flagship; resolver treats it as Flagship despite rank. |
| Ready CLI -> shelf candidate | `ModelCatalog` + `SubstitutionResolver` | Any ready model in a ready CLI can substitute. | Candidate must be ready, on Bench, and in the required shelf. | Opus down, Gemini ready in Fast, Auto on Flagship -> blocked. |
| Bench enabled -> assigned | `SubstitutionBenchState` | Enabling a model puts it in a shelf. | Enablement never mutates shelf assignment. | Enable a custom model; it remains unassigned until assigned. |
| GUI toggle -> durable rule | Core settings | SwiftUI defines what healthy means. | GUI renders Core/CLI/MCP settings only. | CLI disables substitutions; GUI reload shows disabled. |
| MCP tools -> alternate settings JSON | `ContractRegistry` | MCP returns its own shelf shape. | MCP tools use the same `DefaultSettingsJSON` schema. | CLI and MCP projections compare equal for the same temp config root. |
| Empty shelf -> downgrade | `SubstitutionResolver` | If Flagship is empty, try Balanced. | Empty shelf blocks/waits with exact next actions. | Flagship empty, Balanced ready -> no run unless user explicitly changes route. |
| Pinned model -> source lock | `Work_Order_Team_Model` + resolver | Same-shelf substitution can violate execute single-source. | Mutating teams still resolve to one execution source. | Mutating team pinned Claude, same shelf has Codex only -> source gate blocks unless policy explicitly routes to Codex execution source. |

## Works Test

Backend/CLI/MCP proof:

```bash
swift test
alln defaults show --json
alln defaults set --model auto --shelf flagship --json
alln substitutions list --json
alln substitutions assign model_sonnet --shelf flagship --json
alln defaults substitutions --allow true --json
alln dev export-contracts --check
```

MCP parity proof:

```text
Start alln mcp serve --stdio against a temporary config root.
Call defaults_get.
Call substitutions_assign for model_sonnet -> flagship.
Call defaults_get again.
Assert the result matches alln defaults show --json for the same config root.
```

Resolver proof:

```text
Fixture: Opus unavailable, ChatGPT ready, Sonnet ready.
Settings: Auto on Flagship; Opus and ChatGPT on Flagship; Sonnet on Balanced.
Assertion: Auto resolves to ChatGPT, not Sonnet.

Fixture: Opus unavailable, ChatGPT unavailable, Sonnet ready.
Settings: Auto on Flagship.
Assertion: run blocks/waits with SUBSTITUTION_SHELF_EMPTY.
```

Owner-visible claim:

```text
In Default Settings, Auto can be set to Flagship, models can be moved among
Flagship/Balanced/Fast shelves, and "Allow healthy substitutions" only ever
substitutes within the selected shelf. If that shelf has no ready model, work
waits instead of silently getting cheaper or dumber.
```

Missing proof / waiver:

- GUI visual proof is waived until SBDS-S05.
- iOS proof is waived until the paired iOS settings surface exists.
- Live model discovery proof is not applicable in this phase.

## Done When

- Core owns default model settings and substitution shelf assignments.
- The GUI, CLI, MCP, and future iOS surfaces consume the same contract.
- `Auto` is represented as `Auto on <shelf>`, not as a hidden concrete model.
- Flagship, Balanced, and Fast default assignments ship for built-in models.
- Users can override shelf assignments through CLI and MCP.
- The Mac Default Settings surface renders and mutates the same state.
- Healthy substitutions are same-shelf only.
- Cross-CLI substitution works inside the same shelf.
- Empty/down shelves block or wait with exact next actions.
- No silent upgrade/downgrade exists.
- Substitution provenance is visible in run output/warnings.
- `swift test`, CLI Works Test, MCP parity proof, and generated contract checks
  pass for backend slices, with GUI proof added for the GUI slice.

## Open Questions

- Should `model_chatgpt_54` and `model_fable` receive default shelves now, or
  stay unassigned until their model-catalog defaults are finalized?
- Should v1 allow custom shelf creation, or keep exactly three built-in shelves
  until dogfood proves the need?
- Should a concrete pinned default model be allowed while off-Bench, or should
  `alln defaults set --model <id>` reject off-Bench models every time?
- Does `ModelFallbackPolicy` need a public `sameShelf` case, or should healthy
  substitution stay a higher-level setting applied before existing fallback
  policies?
