# Model Catalog And Bench Roster

Status: **BUILT** (MCBR-S01–S08, 2026-06-18) — `ModelCatalog.swift` + `alln models` + MCP shipped; doc is the historical requirements record
Owner: AllnighterCore + AllnighterCLI + Mac GUI
Updated: 2026-06-18

## Founder Intent

Raw request:

- The CLIs page already knows which models belong to each CLI, but it is
  read-only and seeded fresh every launch.
- Start with a Core `ModelCatalog` that lists the models for every shipped CLI.
- Add backend support for user-added models because provider rosters change
  faster than Allnighter releases.
- Keep model management inside CLIs. Do not create a separate Bench editor.
- Make `alln models` the rock-solid CLI-to-CLI contract. The Mac GUI, MCP
  tools, and future iOS surfaces consume the same Core/CLI truth.

Product value:

Allnighter should let the user curate the models they already pay for without
pretending Allnighter is a model provider. A ready CLI can expose multiple
models; the user decides which of those models are on the Bench. If Claude Code,
Codex, Grok, or Gemini/Antigravity adds or restores a model before Allnighter
ships an updated built-in catalog, the user can add it manually and use it in
teams immediately. An agent, script, or GUI can then ask `alln models --json`
for the exact same available/enabled/ready truth and act without scraping UI
state.

Trusted workflow slice:

```text
open CLIs
-> select Claude Code
-> see every known Claude Code model
-> disable Sonnet
-> restart Allnighter
-> Sonnet remains available but off the Bench
-> add a new Claude Code model with display name + model label
-> enable it
-> composer/team resolver offers only enabled models from ready CLIs
-> a team pinned to disabled Sonnet falls back honestly with a warning
```

Non-goals:

- No separate Bench sidebar item in the MLP.
- No cloud sync, account sync, marketplace, or vendor account inspection.
- No API-key based model enumeration.
- No launch-time probing or model discovery that can spawn provider CLIs.
- No requirement that disabling a model edits teams that reference it.
- No migration burden for nonexistent users.
- No cost, quota, runtime, quality, or difficulty forecast from model choice.
- No hand-edited generated artifacts. Source contracts change first, then
  generated fixtures/docs update.

## Current State

Useful substrate:

- `Model` already has `id`, `displayName`, `modelLabel`, `driverId`, `role`, and
  `enabled`.
- `driverId` already ties a model to one CLI/source.
- `AppModel.composeBench` derives the user-facing Bench from
  `models.filter(\.enabled)` plus live/cached CLI readiness.
- `TeamResolver.resolve` receives `readyModels`; disabled models naturally fall
  out of resolution and pinned teams already fall back or warn.
- `AppModel.setupCards` already groups models by CLI for the "Models on this
  CLI" detail pane.
- `alln models --json` exists, but it only prints the runtime seeded models.
- `ToolRuntime.init()` currently sets `models = DefaultConfig.models`; `doctor`,
  `detect`, `team`, `TeamService`, and `AsyncTeamService` inherit that seeded
  array.
- `doctor`/`detect` currently choose one `modelLabel` per driver by scanning the
  runtime model array, which couples source probing to the roster.
- `TeamCatalog` and `SkillCatalog` already provide the catalog pattern for
  built-in plus custom definitions.

Current gap:

- `Packages/AllnighterCore/Sources/AllnighterCore/ModelCatalog.swift` is not yet
  a full model roster catalog. It only stores capability metadata for seeded
  model IDs.
- `DefaultConfig.models` and `Apps/AllnighterMac/Resources/Drivers/team_default.json`
  still seed the runtime roster.
- Model enable/disable choices do not persist.
- Custom models do not exist.
- The CLIs detail pane is read-only.
- The CLI command surface has no enable, disable, add, update, or delete
  commands for models.
- The generated CLI contract already advertises `models_json`; changing
  `alln models --json` requires a registry update and generated artifact refresh.

Existing truth owners:

| Fact | Current owner | Problem |
| --- | --- | --- |
| Shipped runtime models | `DefaultConfig.models` + `team_default.json` | Duplicate bundle/code truth and no custom entries. |
| Model capabilities | `ModelCatalog.builtInCapabilities` | Capabilities only; no per-driver available model catalog. |
| CLI readiness | `SetupStore` / `ToolProbeRecord` | Correct owner; must stay separate from model enablement. |
| Bench membership | `Model.enabled` in runtime array | Correct field, but no persistence or catalog API. |
| Team fallback | `TeamResolver` | Already uses ready/enabled models when callers pass the right bench. |

## SSOT

Truth owner:

```text
AllnighterCore.ModelCatalog
AllnighterCore.ModelID
AllnighterCore.ModelDefinition
AllnighterCore.ModelRosterState
```

The product noun is `ModelCatalog`: every model Allnighter knows a shipped or
custom CLI can run. File IO is private plumbing, e.g. `ModelCatalogPersistence`
or `CatalogFileIO`; do not introduce public `ModelStore` vocabulary.

CLI authority:

```text
ModelCatalog -> alln models JSON -> GUI/MCP/iOS consumers
```

The Mac GUI may call Core directly inside the app process, but it must consume
the same projection and semantics exposed by `alln models --json`. No GUI-only
model roster shape may become durable truth.

Lie-prone layers:

- SwiftUI CLIs pane rows.
- `DefaultConfig.models`.
- bundle `team_default.json`.
- `alln models` text output.
- team presets with `preferredModelId` or `allowedModelIds`.
- setup/readiness cards.
- future live model discovery adapters.

New/changed semantic rules:

- A model cannot exist without a known `DriverManifest.id`.
- The CLIs page manages CLI model rosters; Bench is the derived set of enabled
  models across ready CLIs.
- `alln models` is the public machine contract for model catalog and Bench
  membership. GUI controls are consumers of this contract, not a separate editor.
- Built-in model definitions are read-only product assets.
- Custom model definitions are user-owned local definitions.
- Enable/disable changes Bench membership only. It does not install, sign in,
  smoke-test, delete, or mutate the CLI.
- CLI readiness gates whether an enabled model can run. It does not decide
  whether the model is visible in the CLI detail pane.
- Disabling a CLI's last enabled model is allowed. That CLI contributes zero
  models to the Bench and the UI may show a soft note.
- Disabling or deleting a model referenced by a team is allowed. Resolution must
  fall back or block honestly according to the team's existing fallback policy.
- Manual custom model labels are passed only through the driver's existing argv
  substitution path. They are never concatenated into shell strings.
- Source probing (`alln detect`, `alln doctor --full`, setup re-check) uses a
  per-driver probe model label from `ModelCatalog`; it must not depend on the
  user's enabled Bench.
- Live discovery, when added, may suggest candidates but must not auto-enable
  models or run on launch.

Duplicate truth to delete:

- Runtime roster ownership in `DefaultConfig.models`.
- Bundle roster ownership in `team_default.json`.
- Any SwiftUI-local arrays of models.
- Any CLI output that treats `alln models` as "enabled only" without an explicit
  filter.

## Definitions

### Source / Driver

The CLI or runtime Allnighter uses to reach a model. Existing machine key:
`DriverManifest.id`.

Examples:

```text
claude_code
codex
grok
antigravity
```

Manual paste is a driver kind, but it is not part of the editable CLI model
catalog in this phase.

### ModelDefinition

The durable catalog definition for one model a source can run. It is available
whether or not it is on the Bench.

```swift
public typealias ModelID = String

public enum ModelOrigin: String, Codable, Sendable, CaseIterable {
    case builtIn = "built_in"
    case custom
    case discovered
}

public struct ModelDefinition: Codable, Sendable, Equatable, Identifiable {
    public var id: ModelID
    public var displayName: String
    public var modelLabel: String
    public var driverId: String
    public var role: ModelRole
    public var origin: ModelOrigin
    public var defaultEnabled: Bool
    public var capabilities: ModelCapabilities
    public var createdAt: Date?
    public var updatedAt: Date?
}
```

`Model` remains the runtime shape that existing runners, resolvers, and run
snapshots consume. `ModelCatalog` materializes `[Model]` from definitions plus
roster state:

```text
ModelDefinition + ModelRosterState -> Model(enabled: Bool)
```

### ModelRosterState

The local user overlay for Bench membership.

```swift
public struct ModelRosterState: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var enabledModelIds: [ModelID]
    public var updatedAt: Date?
}
```

Rules:

- If no roster file exists, built-ins use `defaultEnabled`.
- Once a roster file exists, `enabledModelIds` is the complete Bench membership.
- Adding a custom model enables it by default unless the caller passes disabled.
- Deleting a custom model removes it from `enabledModelIds`.
- New built-in models added by an app update default to available/off-Bench for
  existing users unless a phase explicitly says otherwise.

### Bench

The derived set:

```text
Bench = ModelCatalog.resolvedModels().filter(\.enabled)
Ready Bench = Bench filtered to source statuses where ToolProbeRecord.status.isReady
```

No UI or CLI surface should persist a separate Bench list.

### Probe Model Label

Setup and Doctor probe a source/driver, not the user's Bench. A driver can have
zero enabled models and still need to be detected, versioned, authenticated, and
smoke-tested.

`ModelCatalog` must provide this separate lookup:

```swift
public static func probeModelLabel(driverId: String) -> String?
public static func probeModelLabels(registry: DriverRegistry) -> [String: String]
```

Selection order:

1. Enabled definitions for that driver, if any.
2. Custom/discovered definitions for that driver.
3. Built-in definitions for that driver.

Within each group, choose deterministically: `role == .both`, then
`strengthRank` descending, then stable `id` order. Enabled state can bias the
choice, but the absence of an enabled model must never suppress a source probe.

If no probe label exists for a headless driver, that is a catalog coverage bug.
It should be reported as `MODEL_DRIVER_MISSING` or an equivalent Doctor/catalog
diagnostic and caught by the built-in coverage test.

### Catalog Projection

`ModelCatalog.resolvedModels(registry:)` returns the full catalog projection as
`[Model]`, with each row carrying its current `enabled` value. It is not the
Bench.

`ModelCatalog.benchModels(registry:)` returns only enabled models. Callers that
need runnable models must additionally filter by ready source:

```text
catalog projection: available built-in/custom models, enabled or off-Bench
Bench:              enabled models
Ready Bench:        enabled models whose driver is ready
```

## Initial Built-In Catalog

The MLP built-in catalog covers every shipped headless CLI manifest. Adding a new
headless CLI manifest later must add at least one built-in model definition, even
if that definition is disabled by default.

| Driver ID | Model ID | Display name | Model label passed to CLI | Role | Default enabled |
| --- | --- | --- | --- | --- | --- |
| `claude_code` | `model_opus` | `Opus 4.8` | `opus` | `both` | yes |
| `claude_code` | `model_sonnet` | `Sonnet 4.6` | `sonnet` | `answerer` | yes |
| `codex` | `model_chatgpt` | `ChatGPT 5.5` | `gpt-5.5` | `answerer` | yes |
| `grok` | `model_composer` | `Composer 2.5` | `grok-composer-2.5-fast` | `answerer` | yes |
| `grok` | `model_grok` | `Grok Build` | `grok-build` | `answerer` | yes |
| `antigravity` | `model_gemini` | `Gemini (Antigravity)` | `Gemini 3.5 Flash (Medium)` | `answerer` | yes |

These six shipped built-ins are the default fresh-install Bench. Avoid informal
new product names for them in code or user-facing output.

Catalog list rule:

```text
ModelCatalog.list(driverId: "claude_code")
-> Opus 4.8, Sonnet 4.6, plus custom/discovered Claude Code models
```

Do not add guessed provider names as built-ins. If a provider restores or adds a
model before the built-in catalog is updated, the user adds it as a custom model
with the exact model label accepted by that CLI.

## Persistence

Add model catalog paths beside existing team/skill catalog paths:

```swift
AllnighterPaths.catalogModels
// ~/Library/Application Support/Allnighter/Catalogs/models/
```

Required path additions:

```swift
AllnighterPaths.catalogModels
CatalogRoots.models
CatalogRoots.overrideForTesting(teams:skills:models:)
```

`CatalogRoots` already owns test overrides for team and skill custom catalogs.
Models must participate in that same override mechanism; do not add a second
model-only test root pattern.

Custom model definitions:

```text
~/Library/Application Support/Allnighter/Catalogs/models/<model-id>.json
```

Use the existing catalog envelope pattern, extended with `CatalogKind.model`:

```json
{
  "schemaVersion": 1,
  "kind": "model",
  "definition": {
    "id": "custom_claude_code_fabel",
    "displayName": "Fabel",
    "modelLabel": "fabel",
    "driverId": "claude_code",
    "role": "answerer",
    "origin": "custom",
    "defaultEnabled": true,
    "capabilities": {
      "laneTags": ["build", "design", "copy"],
      "capabilityTags": ["code", "review"],
      "strengthRank": 0
    },
    "createdAt": "2026-06-18T00:00:00Z",
    "updatedAt": "2026-06-18T00:00:00Z"
  }
}
```

Roster state:

```text
~/Library/Application Support/Allnighter/Config/model_roster.json
```

Roster persistence is config, not catalog content. Keep it behind private
plumbing such as:

```swift
public struct ModelRosterPersistence {
    public init(fileURL: URL? = nil)
}
```

Tests inject `fileURL`; `CatalogRoots` does not own the roster file.

Example:

```json
{
  "schemaVersion": 1,
  "enabledModelIds": [
    "model_opus",
    "model_chatgpt",
    "custom_claude_code_fabel"
  ],
  "updatedAt": "2026-06-18T00:00:00Z"
}
```

Load order:

1. Load built-in definitions from `ModelCatalog.builtIns`.
2. Load custom definitions from `Catalogs/models`.
3. Drop custom definitions whose `driverId` has no manifest, and report them in
   diagnostics. Do not silently attach them to another driver.
4. Load `model_roster.json`.
5. If no roster file exists, apply each definition's `defaultEnabled`.
6. If a roster file exists, set `enabled = enabledModelIds.contains(model.id)`.
7. Materialize `[Model]` for existing callers.

Upgrade rule:

- Fresh install / no roster file: shipped built-ins default according to
  `defaultEnabled`.
- Existing install / roster file exists: `enabledModelIds` is complete. New
  built-ins delivered by app update appear available/off-Bench until the user
  enables them.
- A driver with zero enabled models remains visible in the CLIs pane. It simply
  contributes zero models to the Bench.
- `MODEL_ROSTER_STALE_ID` diagnostics are returned by the catalog/CLI JSON and
  may be surfaced by Mac as a non-blocking diagnostics row. They must not block
  the app from loading valid models.

Save rules:

- `setEnabled(modelId, true)` creates or updates `model_roster.json`.
- `setEnabled(modelId, false)` removes the ID from `enabledModelIds`.
- Save atomically.
- Preserve unknown future JSON fields only if the chosen encoder path supports
  it; otherwise schema bumps must be explicit.

## Core API

Add or expand `ModelCatalog` into the public Core lookup and mutation surface:

```swift
public enum ModelCatalog {
    public static var builtIns: [ModelDefinition] { get }

    public static func list(
        driverId: String? = nil,
        includeUnavailableDrivers: Bool = true
    ) -> [ModelDefinition]

    public static func get(_ id: ModelID) -> ModelDefinition?
    public static func resolvedModels(registry: DriverRegistry) -> [Model]
    public static func benchModels(registry: DriverRegistry) -> [Model]
    public static func probeModelLabel(driverId: String) -> String?
    public static func probeModelLabels(registry: DriverRegistry) -> [String: String]
    public static func diagnostics(registry: DriverRegistry) -> [ModelCatalogDiagnostic]

    public static func isEnabled(_ id: ModelID) -> Bool
    public static func setEnabled(_ id: ModelID, _ enabled: Bool) throws

    @discardableResult
    public static func createCustom(
        driverId: String,
        displayName: String,
        modelLabel: String,
        role: ModelRole,
        enabled: Bool
    ) throws -> ModelDefinition

    public static func updateCustom(_ model: ModelDefinition) throws
    public static func deleteCustom(_ id: ModelID) throws

    public static func capabilities(_ modelId: ModelID) -> ModelCapabilities
}
```

Validation:

- IDs use lowercase snake case: `^[a-z][a-z0-9_]{2,63}$`.
- Generated custom IDs include the driver:
  `custom_<driver>_<slug>`, e.g. `custom_claude_code_fabel`.
- IDs are still global. Including the driver prevents normal same-name models on
  different drivers from colliding; any remaining collision gets a suffix.
- `driverId` must exist in `DriverRegistry`.
- `displayName` must be non-empty after trimming.
- `modelLabel` must be non-empty after trimming.
- Built-in IDs cannot be saved, edited, or deleted as custom definitions.
- Custom definitions cannot collide with built-in or custom IDs.
- `updateCustom` must reject `driverId`, `id`, and `origin` changes. Moving a
  model to another driver is delete plus create, with normal ID rules.
- `role` must be one of the existing `ModelRole` cases.
- Custom model capabilities are optional in UI. If omitted, use empty
  capabilities plus same-driver fallback where available.

Diagnostics:

```swift
public struct ModelCatalogDiagnostic: Codable, Sendable, Equatable {
    public var code: String
    public var modelId: ModelID?
    public var driverId: String?
    public var message: String
}
```

Required diagnostics:

| Code | Meaning |
| --- | --- |
| `MODEL_DRIVER_MISSING` | Custom model references a driver manifest not installed in this build. |
| `MODEL_ID_COLLISION` | Custom model collides with another model. |
| `MODEL_BUILTIN_IMMUTABLE` | Caller tried to edit/delete a built-in model. |
| `MODEL_INVALID` | Required model fields are empty or malformed. |
| `MODEL_ROSTER_STALE_ID` | Roster enabled set references a model that no longer exists. |

## CLI Contract

`alln models` becomes the headless contract for the same catalog the GUI uses.
This supersedes the current read-only output.

This is an intentional public contract change from the current raw `[Model]`
JSON output to a named envelope. Allnighter has no external model-roster
migration burden yet, so prefer the correct `ModelListJSON` contract now rather
than preserving the raw array as a compatibility shape.

Registry rule:

- Update `ContractRegistry+Milestone1.swift` before runtime behavior.
- Change the `models_json` example title from "List bench models" to "List
  model catalog and Bench state."
- Add schema/docs for `ModelListJSON`.
- Regenerate `docs/generated/alln/*`.
- `alln dev export-contracts --check` is part of S04/S08 proof.
- `MODEL_UNAVAILABLE` should continue to point agents at `alln models --json`,
  but its explanation must distinguish available/off-Bench/not-ready.

Grammar:

```bash
alln models [--json] [--driver <driverId>] [--bench]
alln models enable <model-id> [--json]
alln models disable <model-id> [--json]
alln models add --driver <driverId> --name <display-name> --model-label <label> \
  [--role answerer|planWriter|both] [--id <model-id>] [--disabled] [--json]
alln models update <custom-model-id> [--name <display-name>] [--model-label <label>] \
  [--role answerer|planWriter|both] [--json]
alln models delete <custom-model-id> [--json]
```

Output JSON (`ModelListJSON`):

```json
{
  "schemaVersion": 1,
  "contractVersion": "0.1.0",
  "models": [
    {
      "id": "model_opus",
      "displayName": "Opus 4.8",
      "modelLabel": "opus",
      "driverId": "claude_code",
      "driverName": "Claude Code",
      "role": "both",
      "origin": "built_in",
      "enabled": true,
      "ready": true,
      "status": "ready",
      "state": "onBench",
      "capabilities": {
        "laneTags": ["build", "design", "copy"],
        "capabilityTags": ["code", "planner", "review", "security", "copy", "localContext"],
        "strengthRank": 100
      }
    }
  ],
  "diagnostics": []
}
```

`state` values:

| State | Meaning |
| --- | --- |
| `onBench` | Enabled by roster. May or may not be ready, depending on source status. |
| `available` | Known to the catalog but off-Bench. |

`status` values:

| Status | Meaning |
| --- | --- |
| `ready` | Source/driver is ready in cached setup state. |
| `notReady` | Source exists but is not ready. |
| `notChecked` | No cached setup state for the source. |
| `driverMissing` | Definition references a driver not present in this build. |

CLI rules:

- Default `alln models` lists available models, not only enabled Bench models.
- `--bench` filters to enabled models.
- `--driver` filters by source.
- `ready` is derived from cached setup state, never from enablement.
- Text output must show enabled/off-Bench and ready/not-ready separately.
- JSON mode prints exactly one `ModelListJSON` object to stdout.
- Human warnings and recovery guidance go to stderr in machine modes.
- Commands that mutate the catalog must emit standard error envelopes on
  validation failure.
- Mutating commands write atomically and then print the refreshed
  `ModelListJSON`. Do not vary output shape by subcommand.

## CLI Runtime Loading

`ToolRuntime` is the first consumer to fix. After MCBR-S01/S02:

```swift
let registry = DefaultConfig.registry
let models = ModelCatalog.resolvedModels(registry: registry)
```

`ToolRuntime.init()` must no longer read `DefaultConfig.models` as the public
runtime roster. `DefaultConfig.models` may remain temporarily as a compatibility
facade, but it should derive from `ModelCatalog.builtIns` and must not bypass
custom definitions or roster state in CLI commands.

CLI runtime rules:

- `runtime.models` is the full catalog projection (`Model.enabled` included),
  not only the Bench.
- `runtime.readyModels` is enabled models filtered to ready drivers.
- Team runs, async team runs, `TeamRunJSONMapper`, history/show/export, and
  `TeamService` receive the full projection so run snapshots can name disabled
  or historical preferred models when needed.
- Team resolution and dispatch candidate lists use `runtime.readyModels` or an
  explicit enabled/ready filter.
- `doctor`, `detect`, setup re-check, and census verification build their
  `[driverId: modelLabel]` maps from `ModelCatalog.probeModelLabels(registry:)`,
  not from enabled Bench membership.
- A driver with zero enabled models is still detected and can still be marked
  ready. It simply has no Bench models until the user enables one.
- A headless driver without any catalog model is a build/config failure, not a
  reason to skip the driver silently.

## Mac Backend Contract

`AppModel` remains the Mac observable facade, but it no longer owns model roster
truth directly.

`AppModel.models` becomes the full catalog projection. It is not synonymous with
the Bench. Every UI-facing derived property must choose the right projection:
available catalog, enabled Bench, or ready Bench.

Required changes:

- Initialize `models` from `ModelCatalog.resolvedModels(registry:)`.
- Reload `models` from `ModelCatalog.resolvedModels(registry:)` after every
  model mutation.
- Add `reloadModelsFromCatalog()`.
- Add `setModelEnabled(modelId:enabled:)`.
- Add `addCustomModel(driverId:displayName:modelLabel:role:)`.
- Add `deleteCustomModel(modelId:)`.
- Keep `composeBench` as enabled models plus readiness.
- Keep `setupCards` grouped by driver, but source its `workers`/model rows from
  all catalog models for that driver, not only enabled models.
- Use `ModelCatalog.probeModelLabels(registry:)` for `runFullSetupProbe` and
  census ingest model labels.
- Do not run CLI probes while toggling or adding models.

Call sites that must be audited in S05:

| AppModel surface | Required projection |
| --- | --- |
| `setupCards` | Full catalog for each driver, with enabled/off-Bench state. |
| `readyWorkerCount` | Enabled models whose driver is ready. |
| `composeBench` | Enabled models, annotated with readiness. |
| `composeExecutorIds` | Enabled headless-CLI models unless a caller explicitly asks for all available executor-capable models. |
| `planWriterModel` | Current seated workers only; disabled model seats should already have fallen out when the team was resolved. |
| `runDoctor` | Probe labels from catalog, not enabled Bench count. |
| `runFullSetupProbe` | Probe labels from catalog, not enabled Bench count. |
| `runCensusDiscovery` / ingest | Probe labels from catalog, not enabled Bench count. |
| `censusAgent` | Ready Bench model; if none, no agent-powered census. |
| `imageWorkers` / design runs | Enabled models whose manifests can generate images. |
| dispatch/review pools | Enabled and ready where they can start work; full projection only for display/snapshot lookup. |

GUI-visible states the backend must expose per model row:

| State | Backend fact |
| --- | --- |
| On Bench | `model.enabled == true` |
| Available | `model.enabled == false` and definition exists |
| Ready | `ToolProbeRecord(driverId).status.isReady == true` |
| Not ready | CLI exists but setup status is not ready |
| Custom | `ModelDefinition.origin == .custom` |
| Built-in | `ModelDefinition.origin == .builtIn` |

Inside the CLIs detail pane:

```text
Models on this CLI
  Opus 4.8       On Bench    Ready
  Sonnet 4.6     Available   Ready
  + Add model
```

The visual implementation is outside this backend-first packet, but the data
must be shaped so SwiftUI only renders Core truth.

## Team Resolution Impact

Existing team resolution should stay mostly intact:

```text
ModelCatalog.resolvedModels
-> enabled Bench
-> ready Bench
-> TeamResolver.resolve(...)
```

Required behavior:

- A disabled preferred model is treated the same as an unavailable preferred
  model.
- A disabled allowed-only model can block an exact-only required row; that block
  is honest and local to the team.
- Fallback warnings should name the preferred model display name when known,
  even if it is disabled.
- If every built-in model on a ready driver is disabled but a custom model on
  that driver is enabled, the custom model is a normal ready Bench candidate.
- Run snapshots must keep enough model display data for history to stay readable
  after a custom model is renamed or deleted.

No team definition is rewritten by model toggles.

## Live Discovery Seam

This phase builds the catalog so live discovery can land without replacing it.
Manual custom add is required in the MLP. Live discovery is a later adapter behind
the same catalog API unless a driver already supports a cheap, deterministic list
command.

Discovery protocol:

```swift
public protocol ModelDiscoveryProvider: Sendable {
    var driverId: String { get }
    func discover(invocation: ToolInvocation?) async -> ModelDiscoveryResult
}

public struct ModelDiscoveryResult: Codable, Sendable, Equatable {
    public var driverId: String
    public var candidates: [ModelDefinition]
    public var diagnostics: [ModelCatalogDiagnostic]
    public var discoveredAt: Date
}
```

Discovery rules:

- Discovery only runs from explicit user intent, e.g. "Find models" or an
  explicit CLI command. It never runs on app launch.
- Discovery candidates are available/off-Bench until the user enables them.
- Discovery must use the same resolved invocation that passed setup when
  possible.
- Discovery adapters must be per-driver. Do not invent one generic parser for
  unrelated CLI outputs.
- A discovery result cannot delete custom models.
- If a discovered candidate matches an existing built-in/custom `modelLabel` on
  the same driver, merge metadata but preserve the user's enabled state.

Possible future grammar:

```bash
alln models discover --driver <driverId> [--json]
```

This command is intentionally not required for the first backend proof if no
current shipped driver exposes a stable list-models command.

## Driver/Protocol Impact

Driver manifests continue to own how to invoke a CLI. ModelCatalog owns which
model labels are available for that driver.

Driver manifest changes:

- No required v1 manifest schema change.
- Optional future field: `modelsDiscoveryCommand`.
- Optional future field: `modelLabelValidationPattern`.

Protocol changes:

- `TeamRunJSON.models[]` remains run-snapshot data.
- `DoctorResult.models[]` should include enabled plus available model state only
  if the contract registry is updated. Otherwise keep Doctor focused on ready
  Bench models and link to `alln models --json`.
- MCP/agent surfaces must call the same CLI/Core catalog APIs. No parallel model
  JSON.

Auth/privacy/permissions impact:

- Enable/disable and manual add are local file writes only.
- Manual add does not contact vendors.
- Live discovery can spawn provider CLIs and may touch provider session state, so
  it must be explicit user intent and follow setup probe authority rules.
- No credentials, Keychain values, or API keys are read for this feature.

## Implementation Slices

### MCBR-S00 - Phase Doc And Routing

Status: This document.

Done when:

- Phase doc exists.
- `docs/phases/README.md` routes model catalog/Bench roster work here.

### MCBR-S01 - Core Built-In ModelCatalog

Backend:

- Expand `ModelCatalog` from capability metadata to built-in model definitions.
- Preserve `ModelCatalog.capabilities(_:)` for existing resolver callers.
- Add `ModelID`, `ModelOrigin`, `ModelDefinition`, and model catalog errors.
- Move the six shipped built-in definitions into `ModelCatalog.builtIns`.
- Make `DefaultConfig.models` a temporary compatibility facade derived from
  `ModelCatalog.builtIns`.
- Add `probeModelLabel(driverId:)` with deterministic label selection.

Tests:

- Every shipped headless CLI manifest has at least one built-in model.
- Every built-in model's `driverId` resolves in `DefaultConfig.registry`.
- `probeModelLabel(driverId:)` returns a label for every shipped headless driver.
- Existing capability fallback tests still pass.
- Built-in IDs are unique and valid.

### MCBR-S02 - Paths, Roster Persistence, And CLI Runtime Loading

Backend:

- Add `AllnighterPaths.catalogModels`.
- Add `CatalogRoots.models` and extend `overrideForTesting`.
- Add `ModelRosterState`.
- Add atomic load/save persistence under `Config/model_roster.json`.
- Add `setEnabled`.
- Add stale-ID diagnostics.
- Add `ModelRosterPersistence(fileURL:)` for test injection.
- Switch `ToolRuntime.init()` from `DefaultConfig.models` to
  `ModelCatalog.resolvedModels(registry:)`.
- Switch CLI doctor/detect probe label maps to
  `ModelCatalog.probeModelLabels(registry:)`.

Tests:

- With no roster file, the six shipped built-ins default to enabled.
- Disabling `model_sonnet` persists across reload.
- Re-enabling restores it to the Bench.
- Stale enabled IDs are ignored and diagnosed.
- Disabling the last model for a driver is allowed.
- `alln doctor --json` / detector model-label selection still has a probe label
  for a driver whose models are all disabled.
- `ToolRuntime.readyModels` filters enabled plus ready; `runtime.models` remains
  the full projection.

### MCBR-S03 - Custom Model CRUD

Backend:

- Add `CatalogKind.model`.
- Add custom model save/load/delete under `Catalogs/models`.
- Add `createCustom`, `updateCustom`, and `deleteCustom`.
- Generate deterministic custom IDs with collision fallback.
- Validate driver existence, ID shape, display name, label, role, and built-in
  immutability.
- Reject `id`, `driverId`, and `origin` changes during custom update.

Tests:

- Add `custom_claude_code_fabel` with label `fabel`; it persists and is enabled.
- Add with `--disabled`; it persists but is not on the Bench.
- Update custom display name and label.
- Delete custom model; enabled roster removes it.
- Unknown driver fails with `MODEL_DRIVER_MISSING`.
- Built-in edit/delete fails with `MODEL_BUILTIN_IMMUTABLE`.

### MCBR-S04 - CLI Model Commands

Backend/CLI:

- Update `alln models` grammar.
- Add `ModelListJSON` envelope for available/off-Bench/ready state.
- Add enable/disable/add/update/delete commands.
- All mutating commands return refreshed `ModelListJSON`.
- Update `ContractRegistry+Milestone1.swift`, generated schema/docs/examples,
  and `MODEL_UNAVAILABLE` explanation.
- Run `alln dev export-contracts --check`.

Tests:

- `alln models --json` includes available and enabled state.
- `alln models --json` prints exactly one `ModelListJSON` object, not raw
  `[Model]`.
- `alln models --driver claude_code --json` filters to Claude Code.
- `alln models --bench --json` filters to enabled models.
- `alln models disable model_sonnet` changes subsequent JSON.
- `alln models add --driver claude_code --name Fabel --model-label fabel --json`
  creates a custom enabled model.
- `alln models update <custom-id> --driver grok` is rejected because driver
  changes are not updates.
- Error envelopes are stable for invalid ID, unknown driver, and built-in delete.
- `alln dev export-contracts --check` passes.

### MCBR-S05 - Mac AppModel Backend Glue

Backend/Mac:

- Initialize `AppModel.models` through `ModelCatalog`.
- Add mutation methods for GUI actions.
- Make `setupCards` expose all models for a CLI, not only enabled models.
- Keep `composeBench` enabled plus ready.
- Ensure `readyWorkerCount` counts enabled plus ready only.
- Audit every AppModel call site listed in "Mac Backend Contract."

Tests:

- `AppModel.setModelEnabled` updates `composeBench`.
- After reload, disabled model stays disabled.
- Setup card for Claude Code still shows disabled Sonnet as available.
- Composer target lists do not show disabled Sonnet.

### MCBR-S06 - Team Resolver Proof

Backend:

- Add focused tests around disabled preferred models and custom models.
- Ensure warnings are readable when preferred disabled model falls back.
- Ensure exact-only required rows block honestly when their only allowed model is
  disabled.

Tests:

- Team preferred `model_sonnet`; Sonnet disabled; ready Opus available ->
  runnable with warning.
- Team exact-only allowed `model_sonnet`; Sonnet disabled -> blocked with reason.
- Custom model enabled and ready driver -> resolver can choose it.
- Built-in Claude models disabled, custom Claude model enabled, Claude driver
  ready -> resolver can choose the custom Claude model.

### MCBR-S07 - Discovery Seam

Backend:

- Add `ModelDiscoveryProvider` protocol and result types.
- Add no-op registry for drivers with no supported discovery.
- Add optional `alln models discover --driver` only when at least one provider is
  implemented, or keep the protocol internal until then.

Tests:

- Discovery candidates do not auto-enable.
- Discovery merge preserves enabled state.
- Discovery never runs from `ModelCatalog.resolvedModels`.

### MCBR-S08 - Duplicate Truth Cleanup

Backend:

- Delete or generate `team_default.json` as an owner of model truth.
- Keep fixtures in sync from `ModelCatalog` through a deterministic export.
- Update `DefaultConfigDriftTests` so drift points at `ModelCatalog`, not a
  hand-maintained duplicate.
- Refresh generated CLI docs after duplicate truth cleanup.

Tests:

- Drift test fails if bundle/runtime model definitions diverge.
- `alln dev export-contracts --check` passes.
- `swift test` passes.

## Inference Bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| CLI detail row -> Bench | `ModelCatalog` | Visible model row means enabled. | UI must render available/off-Bench separately from enabled. | Disabled Sonnet still appears under Claude Code but not in composer Bench. |
| CLI ready -> model enabled | `ModelRosterState` | Ready CLI auto-enables every model on it. | Readiness never mutates `enabledModelIds`. | Re-check setup does not re-enable disabled Sonnet. |
| Bench -> source probe labels | `ModelCatalog` | Disabled models make a driver unprobeable. | Probe labels come from all known definitions, not only Bench. | Disable every Claude model; detector/Doctor fixture still receives a Claude probe label. |
| Team preferred model -> roster | `TeamResolver` | A team pin forces a disabled model back on. | Team resolution cannot mutate catalog/roster. | Running a team pinned to disabled Sonnet leaves Sonnet disabled. |
| Driver manifest -> model list | `ModelCatalog` | A driver manifest implies available models. | Every headless driver needs explicit catalog definitions. | New test manifest without model definition fails catalog coverage. |
| CLI JSON -> GUI model state | `alln models` / `ModelCatalog` | GUI invents a local model row shape. | GUI consumes the same catalog projection and states as `ModelListJSON`. | Toggle via `alln models disable`; GUI reload shows the same off-Bench state. |
| Discovery candidate -> Bench | `ModelCatalog` | Discovered means enabled. | Discovery suggestions are off-Bench until user enables them. | Mock discovery returns Fabel; `composeBench` unchanged until enable. |
| Custom model label -> shell command | `DriverManifest.invoke` | Label can be concatenated into shell text. | Model labels flow only through existing argv templating. | Custom label with shell metacharacters is passed as one argument or rejected by validation. |

## Works Test

Backend proof wall:

```bash
swift test
alln models --json
alln models --driver claude_code --json
alln models disable model_sonnet
alln models --bench --json
alln models add --driver claude_code --name Fabel --model-label fabel --json
alln models --driver claude_code --json
alln doctor --json
alln dev export-contracts --check
```

Automated proof should run against injected temporary catalog/roster roots, not
the founder's real Application Support roster. Manual smoke may back up and
restore `Config/model_roster.json` if needed.

CLI-to-CLI focused proof:

```bash
alln models disable model_opus --json
alln models disable model_sonnet --json
alln doctor --json
alln models add --driver claude_code --name Fabel --model-label fabel --json
alln models --driver claude_code --json
```

Expected assertions:

- `alln models --json` returns one `ModelListJSON` object.
- Disabled Claude models remain listed as `available`.
- `alln models --bench --json` excludes disabled models.
- `alln doctor --json` can still build a Claude Code probe label after every
  Claude built-in is disabled.
- After adding Fabel, `alln models --driver claude_code --json` lists Fabel with
  `enabled: true` and `state: "onBench"`.
- `alln dev export-contracts --check` is clean after contract regeneration.

Owner-visible claim:

```text
In CLIs -> Claude Code, Sonnet can be removed from the Bench, the choice survives
restart, and a manually added Fabel model appears under Claude Code and can join
the Bench without editing a JSON file.
```

Missing proof / waiver:

- GUI visual proof is waived for backend slices MCBR-S01 through MCBR-S04.
- GUI proof is required once S05 adds editable controls to the CLIs pane.
- Live discovery proof is waived until a driver-specific discovery provider is
  implemented.

## Done When

- `ModelCatalog` is the only Core owner for built-in, custom, and discovered
  model definitions.
- `model_roster.json` persists enabled Bench membership.
- The six shipped built-ins are present as built-ins and default on for fresh
  installs.
- Every shipped headless CLI has at least one built-in catalog model.
- Every shipped headless CLI has a catalog-derived probe model label even if the
  user disables every model on that CLI.
- `ToolRuntime` loads through `ModelCatalog.resolvedModels(registry:)`, not
  directly from `DefaultConfig.models`.
- `alln models --json` emits `ModelListJSON`; generated CLI contracts, schemas,
  examples, and docs match it.
- Users can enable/disable models through Core and CLI APIs.
- Users can add, update, and delete custom models through Core and CLI APIs.
- `AppModel.composeBench`, `setupCards`, and team resolution consume the same
  resolved catalog.
- Team fallback behavior remains honest when a pinned model is disabled or
  deleted.
- Duplicate roster truth in `DefaultConfig.models` / `team_default.json` is
  removed or generated from the catalog.
- `swift test` and the `alln models` Works Test pass, or missing GUI/discovery
  proof is explicitly waived in the closeout.

## Decisions

- `alln models --json` moves to `ModelListJSON`; no raw `[Model]` compatibility
  shape is preserved.
- Model management stays inside CLIs. Bench remains derived.
- Existing users do not get new built-in models auto-enabled after app update.
- CLI `models add` supports `--role`; default role is `answerer`.
- The first GUI add-model sheet may hide role and create `answerer` models. Role
  editing can live in CLI or an advanced GUI pass.
- Custom model capability tags are not editable in GUI v1. Custom models use
  empty capabilities plus normal same-driver/ready fallback unless a later
  advanced model-editing slice adds capability editing.
