# Model Catalog Unification

Status: **Ready for Implementation** — final audit **Ready with edits incorporated** (2026-07-28); start **MCAT-S01a**
Owner: AgentOS (`AgentOSCLI`) first → Allnighter consumer cutover
Created: 2026-07-27
Updated: 2026-07-28
Process: `docs/workflows/SSOT_Founder_Input_Workflow.md` →
`docs/workflows/SSOT_Feature_Workflow.md`  
Depends on: AgentOS P1 CLI runtime (`BundledDefaults`, `Model`, `EffortLevel`,
`DriverManifest`); Allnighter `ModelCatalog.swift`, `DefaultConfig.swift`,
`team_default.json`; archived `Model_Smoke_And_Driver_Detection.md` boundary law

---

## Final audit (2026-07-28)

### Verdict

**Ready with edits incorporated** — the goal and ownership split are sound; the
audit closed ordering, schema, packaging, merge, and proof gaps that otherwise
would have stopped S01b, broken the green-between-slices rule, or changed runtime
behavior silently.

### Lead Call (implementation authority)

**Status:** **Ready**

**The call:** Implement the final v1 loader shape in MCAT-S01a, with grok as the
only production catalog row and a proof-only Allnighter Mac linkage test. Add
data driver-by-driver through S03 without deleting any Allnighter fallback;
perform the one atomic consumer cutover and legacy deletion in S04, then remove
model-id copy/fallback duplication in S05.

**Locked decisions:**

| Decision | Implementation authority |
| --- | --- |
| Ownership | AgentOS owns embedded driver manifests, model identity/wire labels, role, and effort mapping. Allnighter owns bench policy, visibility, caliber/capabilities, menu hints, user roster, and substitution tiers. |
| Catalog shape | `Sources/AgentOSCLI/Catalog/catalog.json`, schema v1, embeds `DriverManifest` objects. No manifest paths and no runtime filesystem override. |
| Overlay shape | `Packages/AllnighterCore/Sources/AllnighterCore/Resources/Catalog/catalog_overlay.json`, schema v1. Only `defaultOn`, `hidden`, `caliber`, and `menuHint` are legal per-model fields. |
| Effort types | `driver`, `variants`, `fixed`, and `none` are catalog authoring/validation labels only. Do not change `Model`, `EffortLevel`, or `DriverManifest`. |
| Effort timing | S01a implements the complete v1 decode/materialization behavior because S01b contains variant-label models. S02 hardens the validation matrix and removes duplicated routing assertions. |
| Packaging | `Bundle.module` is primary. A generated Swift data constant is allowed only if the Allnighter Mac linkage proof fails; JSON remains authored truth and a drift test must prove equality. |
| Driver scope | antigravity, codex, opencode, and `manual_paste` join the shared AgentOS catalog before S04. OpenCode is valid with zero built-in models. |
| Migration safety | S01–S03 only add AgentOS authority. They do **not** delete Allnighter `DefaultConfig`, Mac driver JSON, or `team_default.json`; all consumer deletion happens after the S04 cutover is proven. |
| Manifest reconciliation | Catalog migration is field-by-field, not a blind copy from `BundledDefaults`. Preserve Allnighter production invocation behavior at cutover (including the current 1800-second invoke budgets) and lock every intentional convergence in fixture tests. |
| App policy | `caliber` is Allnighter `ModelCapabilities` data, not AgentOS data and not substitution-tier membership. `DefaultModelSettings` stays unchanged. |
| Menu copy | `menuHint` is an authored `{useWhen, dontUseWhen}` object. Do not synthesize marketing copy from model names. |
| Compatibility | `BundledDefaults` may remain temporarily as a source-compatible facade derived from `CatalogLoader`; it may not retain literals after the corresponding catalog rows land. |
| Failure behavior | Missing bundle resource may use the generated fallback. Malformed/invalid bundled JSON is a hard load error; never mask bad authored data with the fallback. |
| Slice health | AgentOS tests, Allnighter package tests, and the Mac app test wall stay green after every slice. No hosted Allnighter CI is present today, so do not claim cross-repo CI proof; record both adjacent commit hashes and run the local two-repo wall. |

**Contrarian flags:**

| Flag | Disposition | Why |
| --- | --- | --- |
| A brand-new model that must also be on-bench by default still needs one AgentOS edit and one Allnighter overlay edit. | **Accept** | That is the intentional runtime-policy boundary. “One edit” means one authored file per concern; enabling an already-known model or hiding/removing a default is one overlay edit. |
| S01a has a proof-only Allnighter test even though production ownership is AgentOS. | **Accept** | An AgentOS unit test cannot prove a SwiftPM resource is reachable through the real Mac host. The test adds no consumer cutover. |
| AgentOS and Allnighter manifests differ today (smoke tokens and invoke timeouts). | **Accept with reconciliation gate** | Convergence necessarily changes one side. Preserve the shipped Allnighter run budget and require exact manifest parity fixtures before deleting its fallback. |
| Generated Swift fallback creates a second representation. | **Accept only if required** | It is derived packaging output, not authored truth; byte/hash parity and missing-resource-only use prevent semantic drift. |
| OpenCode has a driver but no bundled models. | **Accept** | Custom/BYOK-only drivers are valid and must not be “fixed” by inventing a default model. |

**Next move:** **MCAT-S01a**. Exit only when schema v1 and all four effort
materializations exist; the bundled grok manifest + `model_grok` load through
`Bundle.module`; malformed resource data fails closed; `BundledDefaults` grok
APIs derive from the loader; AgentOS focused/full tests pass; and an
AllnighterMac host test proves it can call the same loader from the locally
pinned package. No Allnighter production path consumes the catalog yet.

### Gaps found and resolved

| Severity | Gap found | Where it was wrong | Concrete resolution in this packet |
| --- | --- | --- | --- |
| **Blocking** | S03 deleted Allnighter driver truth before S04 changed the consumer. | “Duplicate truth to delete” and old S03b row | S01–S03 are additive only. S04 performs cutover, bundle/project cleanup, and fallback deletion in one green slice. |
| **High** | S01b includes Cursor effort variants but the effort schema was deferred to S02. | Old S01b/S02 ordering | S01a now implements the final four-case decode/materialization; S02 adds exhaustive invalid-shape and route-parity proof. |
| **High** | Existing shared manifests are not actually identical. AgentOS has mostly 300/600-second invoke budgets and `AGENTOS_READY`; Allnighter ships 1800 seconds and `ALLNIGHTER_READY`. | Current State implied a mechanical move | Every driver slice includes a reconciliation fixture. S04 may delete Allnighter manifests only after the AgentOS entry preserves the Allnighter production run budget and intentional token changes are asserted. |
| **High** | A scalar `menuHint` cannot replace `MenuSelectionCopy.Pair`. | Old overlay example and S05 | `menuHint` is now a two-field authored object with the existing length/empty validation. |
| **High** | The overlay had no schema version, resource location, unknown-id behavior, or fresh-roster precedence. | Old overlay example | Final schema and merge rules below define all four, including stale overlay diagnostics and hidden/default/roster precedence. |
| **High** | `manual_paste` and the union-only AgentOS/Allnighter models had no migration slice. | Old slice table | S01b migrates the union for grok/claude/cursor/kimi; S03b adds codex/opencode plus `manual_paste`. |
| **High** | The fallback could hide malformed JSON and had no generation/drift contract. | Packaging section | Fallback is missing-resource-only, generated from JSON, and parity-tested. Invalid primary data fails closed. |
| **Low** | “CI must check out both siblings” described a CI system that is not present in Allnighter. | Dependency note | The packet requires the actual local two-repo wall and adjacent commit hashes; CI wiring is not claimed or expanded here. |
| **Low** | “One edit adds a default” blurred runtime definition and app default policy. | Founder intent / Works Test | Proof now distinguishes catalog-only add, overlay-only enable/hide, and the deliberate two-file brand-new-default case. |

---

## Spec Review (2026-07-27)

**Run:** `32F60943-113E-465D-96C3-8AFD870F395C` · team `custom_mcat_spec_review`  
**Seats:** Gemini 3.6 Flash (Antigravity) · Cursor Grok 4.5 · Sonnet 5 (Claude) · **Opus 5 Lead** (Claude)  
**Lead Call:** **Ready** — approve catalog unification; shrink and split the first slice.

**The call:** Build it — the duplicate-data problem is real (verified in both repos).
MCAT-S01 is greenfield schema + loader + **first-ever AgentOS runtime resource
file**, not a simple migration. Split it before moving driver data.

**Locked recommendations (applied below):**

| Decision | Lean |
| --- | --- |
| Split first slice | **S01a** = schema + loader + **one** driver (grok, 1 model, no effort variants), proving `catalog.json` loads from a fresh checkout in tests **and** the Mac app. **S01b** = claude / cursor / kimi. |
| Packaging | Ship as a real bundled file (`Bundle.module`). If Mac app load fails in S01a, fall back to generated Swift constant with JSON still the authored source — do not stall. |
| Effort schema | Authoring/validation labels only — **no changes** to `Model`, `EffortLevel`, or `DriverManifest`. |
| Non-shared CLIs | antigravity, codex, opencode live in the **shared AgentOS catalog**, not the Allnighter overlay. |
| Split S03 | **S03a** antigravity first (founder-urgent); **S03b** codex + opencode second. |

**Rejects:** runtime telemetry loop (scope creep); floating-point effort abstraction
(speculative); filesystem override catalog (two truth sources); auto-generated menu
marketing copy.

**Next move:** MCAT-S01a in AgentOS after this packet update.

Reproduce: `alln run "Harden docs/phases/Model_Catalog_Simplification.md …" --team custom_mcat_spec_review --effort high`

---

## Founder intake (SSOT_Founder_Input_Workflow default output)

```text
Founder intent:
  Adding or removing a default model (e.g. only Gemini 3.6 Flash on Antigravity;
  no agy Opus/Sonnet 4.6 in defaults) should be one edit, not a seven-file sweep.
  Effort/reasoning (low/med/high) must stay first-class in the same catalog.
  Simplification should start in AgentOS — Allnighter should inherit, not fork.

Product value:
  Faster, safer model roster changes; fewer drift failures; one place to answer
  "what label do we pass at high effort?" for every driver.

Trusted workflow slice:
  edit catalog.json (AgentOS) or overlay (Allnighter)
  -> swift test (CatalogLoader + drift)
  -> fresh install / alln models list --bench shows correct seats
  -> composer effort dial matches invoke wire label

Current state:
  Six overlapping copies of model + driver truth (see Current State below).
  Effort routing works in AgentOS; authoring is scattered.

Truth owner:
  Runtime wire catalog → AgentOS `catalog.json` (new).
  Bench / tiers / seating → Allnighter overlay + existing persistence.

CLI surface:
  Existing `alln models list|enable|disable|add` — no new verbs required for S01–S04;
  loader reads same ids. Optional MCAT-S07: `alln catalog validate` for CI.

Help surface (topics / search terms / recovery):
  `HelpTopicRegistry` models topic; `alln models list`; menu model rows from
  live catalog — overlay `menuHint` replaces per-id `MenuSelectionCopy` after S05.

Proof scenario:
  Delete one catalog entry → one file change → tests green → `alln models list`
  no longer lists it; effort variants still resolve for survivors.

Blocking questions:
  None — Spec Review decided antigravity/codex/opencode belong in shared catalog.

Next slice:
  MCAT-S01a in AgentOS — schema + loader + grok-only round-trip + Bundle.module proof.
```

---

## Allnighter Feature Packet

### Founder Intent

**Raw request:**

```text
The only default Antigravity model should be Gemini Flash 3.6. Opus 4.6 and
Sonnet 4.6 should not be listed by default. More broadly: adding a model and
giving it a rank (Flagship / Balanced / Fast or effort level) should be 10×
easier — ideally one JSON file, with effort/reasoning supported in the same
place. Start from what we inherit from GitHub/AgentOS rather than sweeping
Allnighter Swift again.
```

**Prior art:**

| Tool / system | Convention | Our deviation |
| --- | --- | --- |
| `kubectl` / Helm | One values/manifest file; apps consume | We mirror the same models in Swift + JSON + bundle |
| Terraform | Single source + provider schema validation | We have drift tests but six handwritten sources |
| AgentOS `BundledDefaults` | Small curated model lists per driver in one module | Allnighter forked and expanded without consuming |
| OpenCode BYOK ruling (`a15a2a66`) | Driver stays; defaults removed; `alln models add` for long tail | Same pattern for agy Claude routes |

**Product value:** One edit to add, remove, or re-rank a default seat — including
how low/med/high maps to wire labels — without touching teams, menu copy, and
bundle mirrors.

**Trusted workflow slice:**

```text
AgentOS catalog.json (drivers + models + effort)
  + Allnighter overlay (defaultOn, hidden, caliber, menuHint)
  -> ModelCatalog.load()
  -> alln models list / GUI picker / TeamResolver ready bench
  -> invoke uses resolvedLabel(at: effort) or manifest effortFlag
```

**Non-goals:**

- Dynamic live discovery from `agy --list-models` as default catalog source
- Moving substitution tiers or `BuiltInTeams` into AgentOS
- Menu marketing copy in the runtime catalog (overlay `menuHint` only)
- Replacing `model_roster.json` user persistence
- Runtime execution-health telemetry loop (deferred; MCAT-S06 live smoke only)

### Current State

**Existing truth owners:**

| Layer | Owner today | Problem |
| --- | --- | --- |
| `Model`, `EffortLevel`, effort routing | AgentOSCLI | Correct runtime; incomplete catalog |
| `BundledDefaults` | AgentOSCLI | **11 models, 4 drivers** — partial SSOT; Swift literals + embedded JSON strings |
| `ModelCatalog.builtIns` | AllnighterCore | **20 models, 6 drivers** in the audited working tree (**22 at attached commit `100c7019` before the agy Claude removal**) — parallel SSOT |
| `builtInCapabilities` / `strengthRank` | AllnighterCore | Seating policy mixed into catalog |
| `team_default.json` | Mac bundle | Must match `defaultFreshModels()` or `DefaultConfigDriftTests` fails |
| `DefaultConfig` manifest strings | AllnighterEngine | Third driver-manifest copy |
| `Resources/Drivers/*.json` | Mac bundle | Fourth driver-manifest copy |
| `EffortRoutingTests.swift` | Both repos | Fifth duplicate — near-identical tests in AgentOS + Allnighter |
| `MenuSelectionCopy` | AllnighterCore | Per-model-id hand copy |
| `BuiltInTeams` fallback chains | AllnighterCore | Hardcoded `model_*` ids |
| `DefaultModelSettings` tiers | AllnighterCore | Product policy (keep) |

**Dependency note:** Allnighter pins AgentOS via **local path**
(`.package(path: "../../../AgentOS")`). S01–S03 and S04–S05 can land in adjacent
commits with no version-publish ceremony. There is no hosted Allnighter workflow
in the audited repo; the required integration proof is the local two-repo green
wall with both adjacent commit hashes recorded. Any future hosted workflow must
check out the sibling at the exact path before it can claim this proof.

**Triggering incident (2026-07-27):** Removing agy Opus/Sonnet 4.6 from defaults
required edits across `ModelCatalog.swift`, `team_default.json`, `MenuSelectionCopy`,
`BuiltInTeams`, and multiple test files — for a product decision that is one JSON
object in a unified catalog.

**What Allnighter already inherits from AgentOS (do not reimplement):**

- `Model`, `Model.resolvedLabel(at:)`, `Model.supportsEffort(manifest:)`
- `EffortLevel` in `RuntimeEnums.swift` (`low` / `med` / `high`)
- `DriverManifest.Invoke.effortFlag` + `{{effortArgs}}` substitution
- `ModelSmokeVerifier`, `CLIDetector` / probe records

**What does not exist yet (verified 2026-07-28):** no `catalog.json`, no
`CatalogLoader`, no `resources:` entry on the AgentOSCLI target in `Package.swift`.
Allnighter does not call `BundledDefaults` today — S04 is first-time production
integration. AgentOS and Allnighter both have `EffortRoutingTests`; they overlap
at the runtime seam but are not byte-identical. AgentOS owns generic routing
after S02; Allnighter retains only merged-catalog/invocation integration proof.

**Boundary law** (archived AgentOS `Model_Smoke_And_Driver_Detection.md`):

> AgentOS = what exists and works. Apps = what we should use.

Bug: model *definitions* are duplicated in both layers instead of flowing one way.

### SSOT

**Truth owner (target):**

| Concern | Owner after cutover |
| --- | --- |
| Driver manifests + curated model wire labels + effort mapping | AgentOS `Sources/AgentOSCLI/Catalog/catalog.json` + `CatalogLoader` |
| Bench default on/off, hidden ids, caliber/capabilities, `menuHint` | AllnighterCore bundled `Resources/Catalog/catalog_overlay.json` + merge at load |
| User enabled set | `Config/model_roster.json` (unchanged) |
| Substitution tiers | `default_model_settings.json` (unchanged) |

**Lie-prone layers:**

- `MenuSelectionCopy` per-model prose → overlay `menuHint` (S05)
- `BuiltInTeams` incidental/default-membership fallback ids → existing
  tier/capability policies (S05); intentional recognizable-model/source pins may
  remain only when documented and covered by the model-reference authority test
- `team_default.json` mirror → delete after catalog cutover (S04)
- `DefaultConfigDriftTests` mirror agreement → transitional only until S04

**New/changed semantic rules:**

1. One runtime catalog file in AgentOS; Allnighter merges overlay — never a second full catalog in Swift.
2. Each model declares `effort`: `variants` | `driver` | `fixed` | `none` (see Effort schema).
3. Removing a model from fresh defaults = `defaultOn: false`; hiding an
   otherwise shared model = `hidden: true`; removing runtime existence = delete
   the AgentOS catalog row. Each is a one-file edit in its owning concern.
4. Shared drivers (claude, grok, cursor, kimi) defined once in AgentOS only.
5. **antigravity, codex, opencode** are real working CLIs → shared AgentOS catalog (not overlay-only).
6. Overlay holds only `defaultOn`, `hidden`, `caliber`, and `menuHint` — not duplicate model wire data.

**Duplicate truth to delete (by slice):**

- S04: `ModelCatalog.builtIns` Swift array, `builtInCapabilities` Swift map
  (policy moves into overlay `caliber`), `team_default.json`, `DefaultConfig`
  manifest strings, Mac `Resources/Drivers/*.json`, and the corresponding
  `project.yml` resource entry
- S05: `MenuSelectionCopy` entries for built-ins; `BuiltInTeams` `model_agy_*` style ids
- S01b: literals for migrated AgentOS `BundledDefaults` rows; keep only derived
  compatibility accessors while callers still need them
- S03a/S03b: **no Allnighter deletion**; these slices only complete AgentOS data
- S02: de-duplicate `EffortRoutingTests` (do not "move" — both repos must stay green)

### Final `catalog.json` schema

Composer exposes one **Effort** control. The catalog label describes how the
unchanged runtime types are populated; it is not a new runtime enum.

```ts
type CatalogDocument = {
  schemaVersion: 1;
  // Full DriverManifest JSON objects, embedded. DriverManifest.id is the key.
  // Path references are deliberately unsupported.
  drivers: DriverManifest[];
  models: CatalogModel[];
};

type CatalogModel = {
  id: `model_${string}`;
  displayName: string;
  driver: string; // references DriverManifest.id
  role: "answerer" | "planWriter" | "both";
  effort: "driver" | "variants" | "fixed" | "none";
  label: {
    default: string;
    // Present only for variants; exact keys low/med/high.
    byEffort?: { low: string; med: string; high: string };
  };
};

type CatalogOverlay = {
  schemaVersion: 1;
  models: Record<string, {
    defaultOn?: boolean; // omitted = false
    hidden?: boolean;    // omitted = false
    caliber?: {
      laneTags: WorkLane[];
      capabilityTags: ModelCapabilityTag[];
      strengthRank: number; // integer 0...100
    };
    menuHint?: {
      useWhen: string;     // existing MenuSelectionCopy bound applies
      dontUseWhen: string; // existing MenuSelectionCopy bound applies
    };
  }>;
};
```

`CatalogLoader` returns manifests plus catalog model records; it does not choose
`Model.enabled`. Materializing `[Model]` requires an explicit
`(modelID) -> Bool` policy. Allnighter supplies that from overlay + roster;
AgentOS-only call sites that merely enumerate what exists pass `true`.
`BundledDefaults` may keep unmigrated rows until their slice, but every migrated
manifest/model accessor must derive from the loader. Its old per-row
`enabled: false` choices are retired as misplaced app policy when that row
migrates.

`caliber` is the JSON representation of Allnighter `ModelCapabilities`. Moving
that table from Swift to an Allnighter resource does **not** move it to AgentOS.
It does not assign Flagship/Balanced/Fast membership; that remains
`DefaultModelSettings`.

#### Effort materialization

| `effort` | Required authored shape | Loader output using unchanged runtime types |
| --- | --- | --- |
| `driver` | `label.default`; referenced manifest has a non-empty `effortFlag` with exact `low`/`med`/`high` keys; no `byEffort` | `Model.modelLabel = default`, `effortVariants = nil`; driver flag carries effort |
| `variants` | No manifest `effortFlag`; `byEffort` has exact `low`/`med`/`high`, all non-empty, at least two distinct values | `modelLabel = default`, `effortVariants = byEffort` |
| `fixed` | No manifest `effortFlag`; no `byEffort` | `modelLabel = default`, `effortVariants = [.low: default, .med: default, .high: default]`; existing distinctness check hides dial |
| `none` | No manifest `effortFlag`; no `byEffort` | `modelLabel = default`, `effortVariants = nil`; dial hidden |

This mutual exclusion is required because a model with variants plus a manifest
flag would send two effort mechanisms, while `none` under a flag-based driver
would still expose effort through the unchanged `Model.supportsEffort`.

#### Validation rules

`CatalogLoader.decode(_:)` and `CatalogLoader.bundled()` return typed errors;
they never drop bad rows.

1. `schemaVersion` must equal `1`; arrays and ids are unique and deterministically
   returned in authored order.
2. Driver ids match `^[a-z][a-z0-9_]*$`; model ids match
   `^model_[a-z0-9_]+$`; every model references an existing driver.
3. Every embedded manifest passes `DriverManifest.validate()`. A headless driver
   may have zero models (OpenCode); `manual_paste` must have zero.
4. Display names and all used wire labels are non-empty after trimming.
5. The effort matrix above is exact. Variant keys are exactly
   `low`/`med`/`high`; aliases such as `medium` are rejected. `variants` needs
   at least two distinct values. `driver` needs all three manifest level keys.
6. Unknown catalog/overlay wrapper fields, invalid role/effort values, invalid
   overlay tags, out-of-range/non-integral `strengthRank`, and
   `hidden: true` with `defaultOn: true` are errors.
7. A missing bundled resource may use the generated fallback. A present but
   unreadable, undecodable, wrong-version, or invalid resource is an error and
   must not fall back.
8. If the generated fallback exists, a test compares its bytes or SHA-256 to
   the authored JSON. The generator is the only writer of the Swift file.

#### Overlay merge rules

1. Decode and validate the AgentOS catalog first, then decode the Allnighter
   overlay. Custom/user models merge through existing `CatalogFileIO` afterward
   and may not shadow a built-in id.
2. An overlay row may change only `defaultOn`, `hidden`, `caliber`, and
   `menuHint`; it cannot change driver, label, display name, role, or effort.
3. `hidden: true` removes the built-in from catalog/menu/bench materialization
   even if an old roster contains it. A diagnostic names the stale roster id.
4. With no persisted roster, bench membership is every visible catalog model
   whose overlay says `defaultOn: true`. With a persisted roster, the roster
   wins over `defaultOn`, intersected with the visible catalog.
5. An overlay id absent from AgentOS is ignored with a deterministic warning,
   not a load failure. This makes a one-file AgentOS removal safe; it must be
   covered by `testUnknownOverlayModelIsDiagnosedAndIgnored`.
6. Omitted `caliber` yields existing unrated policy (rank 40, no inferred
   capability tags). Omitted `menuHint` uses neutral operational fallback copy
   for an unreviewed shared model; it does not generate marketing claims.
7. Overlay `caliber` only supplies `ModelCapabilities`. It never edits
   `DefaultModelSettings.fresh`, persisted tier membership, aliases, or
   `neverAutomaticSubstituteIds`.

#### Full S01a grok example

This is a schema-complete minimal fixture. The production row must also carry
the current streaming/session/setup/image blocks during reconciliation; those
are unchanged `DriverManifest` fields, not parallel catalog schema.

```json
{
  "schemaVersion": 1,
  "drivers": [
    {
      "id": "grok",
      "manifestVersion": 1,
      "displayName": "Grok Build CLI",
      "kind": "headless_cli",
      "detectCommand": "grok --version",
      "smokeTestCommand": "grok -p \"Reply with the single token ALLNIGHTER_READY\" -m {{model}} --output-format plain",
      "smokeTestExpect": "ALLNIGHTER_READY",
      "invoke": {
        "command": "grok",
        "args": [
          "-p", "{{prompt}}", "-m", "{{model}}", "{{effortArgs}}",
          "--output-format", "streaming-json", "--always-approve",
          "--no-wait-for-background", "--no-subagents",
          "--disable-web-search", "--cwd", "{{workingDir}}"
        ],
        "promptVia": "arg",
        "env": {},
        "workingDir": null,
        "timeoutSeconds": 1800,
        "effortFlag": {
          "flag": "--reasoning-effort",
          "levels": { "low": "low", "med": "medium", "high": "high" }
        }
      },
      "output": {
        "capture": "stdout",
        "stripAnsi": true,
        "doneSignal": "exit_code",
        "sentinel": null
      }
    }
  ],
  "models": [
    {
      "id": "model_grok",
      "displayName": "Grok 4.5",
      "driver": "grok",
      "role": "answerer",
      "effort": "driver",
      "label": { "default": "grok-4.5" }
    }
  ]
}
```

#### Full S03a Gemini Flash variants example

```json
{
  "schemaVersion": 1,
  "drivers": [
    {
      "id": "antigravity",
      "manifestVersion": 1,
      "displayName": "Antigravity",
      "kind": "headless_cli",
      "maxConcurrentSpawns": 1,
      "detectCommand": "agy --version",
      "smokeTestCommand": "agy --print \"Reply with the single token ALLNIGHTER_READY\" --model \"{{model}}\" --dangerously-skip-permissions",
      "smokeTestExpect": "ALLNIGHTER_READY",
      "invoke": {
        "command": "agy",
        "args": [
          "--print", "{{prompt}}", "--model", "{{model}}",
          "--dangerously-skip-permissions"
        ],
        "promptVia": "arg",
        "env": {},
        "workingDir": null,
        "timeoutSeconds": 1800
      },
      "output": {
        "capture": "stdout",
        "stripAnsi": true,
        "doneSignal": "exit_code",
        "sentinel": null
      }
    }
  ],
  "models": [
    {
      "id": "model_gemini",
      "displayName": "Gemini 3.6 Flash",
      "driver": "antigravity",
      "role": "answerer",
      "effort": "variants",
      "label": {
        "default": "Gemini 3.6 Flash (Medium)",
        "byEffort": {
          "low": "Gemini 3.6 Flash (Low)",
          "med": "Gemini 3.6 Flash (Medium)",
          "high": "Gemini 3.6 Flash (High)"
        }
      }
    }
  ]
}
```

#### Full overlay example

```json
{
  "schemaVersion": 1,
  "models": {
    "model_gemini": {
      "defaultOn": true,
      "caliber": {
        "laneTags": ["design", "code", "copy", "signal"],
        "capabilityTags": ["code", "design", "image", "copy", "fast"],
        "strengthRank": 75
      },
      "menuHint": {
        "useWhen": "Gemini 3.6 Flash, Antigravity",
        "dontUseWhen": "Not Pro; model_gemini_pro"
      }
    },
    "model_gemini_pro": { "defaultOn": false },
    "model_agy_gptoss": { "defaultOn": false }
  }
}
```

### Implementation

**Packaging (S01a must settle this):**

| Option | Decision |
| --- | --- |
| **A. Real bundled file** | **Primary** — add `.copy("Catalog/catalog.json")` to AgentOSCLI; `CatalogLoader.bundled()` reads it via `Bundle.module` |
| **B. Generated Swift data constant** | **Conditional fallback** — add only if the real AllnighterMac host linkage test cannot read A. Generate from JSON; fallback only when the resource URL is absent; parity test guards output |
| **C. Filesystem override** | **Rejected** — two runtime truth sources |

S01a acceptance: fresh checkout → `swift build` → runtime read of `catalog.json`
→ an AllnighterMac host test calls `CatalogLoader.bundled()` successfully. If
that host cannot resolve the package resource, add B and continue. A malformed
primary resource fails closed; it never triggers B.

**CLI surface** (existing — no parallel JSON):

- `alln models list [--bench] [--json]` — reads merged catalog
- `alln models enable|disable <id>`
- `alln models add --driver … --name … --model-label …`
- Optional S07: `alln catalog validate` — schema + effort consistency (exit 1 on drift)

**Teaching surface:**

- Topics: `models`, `defaults`, setup CLI cards
- Search: driver names (`antigravity`, `gemini`), `models list`, `models add`
- Retirement: remove `MenuSelectionCopy` keys when catalog entry removed (S05)
- Recovery: `alln models list` when agent asks "what models are on the bench"

**Model/package impact:**

- **AgentOS:** `Sources/AgentOSCLI/Catalog/catalog.json`,
  `CatalogTypes.swift`, `CatalogLoader.swift`, first `resources:` on AgentOSCLI
  target; optional generated fallback only if the host proof requires it
- **Allnighter:** `ModelCatalog` loads AgentOS + Core-bundled
  `Resources/Catalog/catalog_overlay.json`; shrink `ModelCatalog.swift`

**Mac app impact:** S01a adds a resource-linkage test only. S04 makes
`AppConfig.loadConfiguration()` use the merged catalog/AgentOS registry and
drops `team_default.json` plus `Resources/Drivers/*.json`.

**iOS app impact:** No new UI or contract. The resource is bundled in
AllnighterCore, so iOS compiles the same merged catalog path.

**Agent driver impact:** None — wire labels unchanged; only authoring moves.

**Auth/privacy/permissions impact:** None.

### Proof

#### Product Works Tests

1. With an injected missing roster, the existing models-list CLI projection with
   `benchOnly: true` returns exactly visible overlay `defaultOn` ids.
2. Fresh policy has only `model_gemini` default-on for Antigravity;
   `model_gemini_pro` and `model_agy_gptoss` remain available/off-bench, and
   removed `model_agy_opus` / `model_agy_sonnet` do not exist.
3. A merged `model_gemini` at `.high` resolves
   `Gemini 3.6 Flash (High)` into Antigravity invoke args.
4. Loading a fixture that differs only by one added catalog model makes that id
   appear in the catalog/CLI projection with no Swift registration. It remains
   off-bench until the overlay enables it.
5. The built Mac host and the `alln` package resolve identical shared driver and
   built-in model id sets; neither ships/reads `team_default.json` or standalone
   driver JSON after S04.

#### Final proof matrix

| Proof | Status today | Final owner / action | Slice |
| --- | --- | --- | --- |
| AgentOS `EffortRoutingTests` | **Exists** | Keep generic `Model` + `DriverManifest` route behavior here; switch fixtures from literals to catalog-derived values | S01a–S02 |
| Allnighter `EffortRoutingTests` | **Exists; overlapping, not identical** | Keep only merged-catalog → invocation integration (Codex/Grok/Antigravity and dial visibility); remove generic duplicates | S02/S04 |
| AgentOS `CatalogLoaderTests.testBundledCatalogLoadsFromBundleModule` | **Must be written** | Primary package-resource proof | S01a |
| AgentOS `CatalogLoaderTests.testAllEffortKindsMaterializeWithoutRuntimeTypeChanges` | **Must be written** | `driver`/`variants`/`fixed`/`none` mapping | S01a |
| AgentOS `testCatalogMaterializationRequiresEnablementPolicy` | **Must be written** | Prevent AgentOS runtime existence from becoming bench policy | S01a |
| AgentOS malformed-schema tests (`testEffortDriverRequiresManifestFlag`, `testEffortVariantsRequiresDistinctByEffort`, `testEffortMechanismsAreMutuallyExclusive`, `testFixedAndNoneRejectDriverFlag`, `testUnknownSchemaVersionFails`) | **Must be written** | Fail-closed schema gate | S01a/S02 |
| AgentOS `testEveryCatalogManifestValidates` + per-driver reconciliation fixtures | **Must be written** | Protect invoke args, concurrency, timeout, setup, streaming, image, and session blocks while data moves | S01a–S03b |
| AgentOS `testOpenCodeDriverMayHaveZeroBuiltInModels` | **Must be written** | Preserve BYOK/custom-only ruling | S03b |
| AllnighterMac `CatalogResourceLinkageTests.testHostCanLoadAgentOSBundledCatalog` | **Must be written** | Real host boundary proof; not a production cutover | S01a |
| Allnighter `CatalogOverlayTests` (policy-only decode, hidden precedence, roster precedence, unknown-id diagnostic, invalid hidden+default) | **Must be written** | Merge law | S04 |
| Allnighter `testOneCatalogEditAddsModelWithoutSwiftRegistration` | **Must be written** | Fixture-based one-file runtime add | S04 |
| Allnighter `testOnlyGeminiIsFreshAntigravityDefault` | **Partially exists** in `ModelCatalogTests` | Rebase on overlay and assert removed ids absent | S04 |
| Allnighter `ModelCatalogCLITests` | **Exists** | Add fresh-roster exact bench set and one-extra-model projection | S04 |
| Mac `BuiltBundleConfigTests` | **Exists; asserts old resources** | Replace with shared-catalog source/id parity and assert `team_default`/driver JSON are absent | S04 |
| `DefaultConfigDriftTests` | **Exists; transitional mirror test** | **Delete at S04.** Replace with `CatalogAuthorityTests`: `testAllBuiltInsOriginateInAgentOSCatalog`, `testOverlayAcceptsPolicyFieldsOnly`, `testLegacyCatalogResourcesAreNotShipped`, and retain concurrency/manifest assertions in AgentOS reconciliation tests | S04 |
| `testMergedCatalogNoSecondBuiltInsEncyclopedia` | **Must be written** | Structural assertion/lint that production `ModelCatalog` has no literal built-in definition array | S04 |
| `MenuSelectionGradeTests` | **Exists** | Rebase built-in model rows on overlay `menuHint`; preserve bounds and banned-stub gates | S05 |
| `testBuiltInTeamExplicitModelReferencesExistOrAreDocumentedIdentityPins` | **Must be written** | Prevent stale fallback ids without banning intentional recognizable-model pins | S05 |
| Live installed-CLI label smoke (`LiveLabels`) | **Deferred/waived for CI** | MCAT-S06 opt-in manual proof on founder Mac; not a gate for S01–S05 | S06 |

#### Slice wall

Focused tests run while iterating; each slice closes with both repositories:

```bash
(cd ../AgentOS && swift test)
swift test --package-path Packages/AllnighterCore
xcodebuild test \
  -project Apps/AllnighterMac/AllnighterMac.xcodeproj \
  -scheme AllnighterMac \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

`bash scripts/check.sh` may replace the last two Allnighter commands after
`xcodegen generate` and includes the contract/architecture walls. Record the
AgentOS and Allnighter commit hashes in each slice closeout.

**Missing proof / waiver:** live vendor label availability is MCAT-S06 and
manual on the founder Mac. It does not waive catalog decoding, route resolution,
Mac resource linkage, or CLI projection tests.

### Done When

- [ ] AgentOS `catalog.json` is the only runtime definition for bundled drivers + models
- [ ] Allnighter loads catalog + overlay; no `builtIns` / `builtInCapabilities` Swift encyclopedia
- [ ] No Allnighter `team_default.json`, bundled per-driver JSON, or embedded manifest strings remain
- [ ] One-file runtime add/remove in AgentOS and one-file default enable/hide in the overlay are proven; a brand-new default intentionally edits both owners
- [ ] Effort schema validated in loader tests; runtime types unchanged
- [ ] `DefaultConfigDriftTests` is deleted and its useful assertions live in catalog-authoritative tests
- [ ] Teaching surface: built-in model copy comes from overlay `menuHint`; removed ids have no `MenuSelectionCopy` keys
- [ ] AgentOS + Allnighter adjacent commit hashes and both green walls are recorded for every slice
- [ ] MCAT-S01a through S05 committed; packet archived after promotion

---

## Build slices

Best-guess paths are authoritative enough to start; implementers may rename a
new test file but may not change the ownership, exit claim, or deletion timing.

| Slice | Repo | Files touched (best guess) | Exit tests / commands | Rollback if red |
| --- | --- | --- | --- | --- |
| **MCAT-S01a** | AgentOS + Allnighter proof-only | AgentOS `Package.swift`; new `Sources/AgentOSCLI/Catalog/catalog.json`, `CatalogTypes.swift`, `CatalogLoader.swift`; derived `BundledDefaults.swift` grok accessors; new `Tests/AgentOSCLITests/CatalogLoaderTests.swift`; optional generated fallback + generator only if needed. Allnighter new `Apps/AllnighterMac/Tests/CatalogResourceLinkageTests.swift` | AgentOS `swift test --filter CatalogLoaderTests` then full `swift test`; Allnighter `swift test --package-path Packages/AllnighterCore`; generated Mac project + `xcodebuild test ... -only-testing:AllnighterMacTests/CatalogResourceLinkageTests`; exact S01a exit criteria in Lead Call | Keep `BundledDefaults` production behavior on its old literals until catalog parity is green. If Mac resource lookup alone fails, add the generated fallback; do not weaken invalid-data errors or cut over Allnighter. |
| **MCAT-S01b** | AgentOS | `catalog.json`; `BundledDefaults.swift`; catalog/parity tests. Migrate the **union** of current AgentOS + Allnighter rows for remaining grok, claude, cursor, and kimi models (including Cursor Auto/Fast and Kimi HighSpeed), without changing Allnighter defaults. | AgentOS `swift test --filter 'CatalogLoaderTests|EffortRoutingTests'` + full `swift test`; both Allnighter walls | Do not delete a driver/model literal until its catalog-derived compatibility accessor passes exact id/label/role/effort/manifest parity. Revert only that row group, leaving S01a intact. |
| **MCAT-S02** | AgentOS + Allnighter tests | AgentOS `CatalogLoader.swift`, `CatalogLoaderTests.swift`, `EffortRoutingTests.swift`; Allnighter `Tests/AllnighterEngineTests/EffortRoutingTests.swift` | Named invalid-shape tests in proof matrix; AgentOS full tests; Allnighter package + Mac wall | Retain an Allnighter integration assertion if ownership is ambiguous, but remove no AgentOS runtime coverage and do not relax the four-case validation matrix. |
| **MCAT-S03a** | AgentOS | `catalog.json`; catalog reconciliation/effort tests for antigravity, Gemini Flash, Gemini Pro, GPT-OSS fixed | AgentOS catalog/effort tests + full suite; Allnighter package + Mac wall still use old local data and must remain unchanged | Remove only the new antigravity rows from AgentOS. Do **not** delete or redirect Allnighter manifests/models in this slice. |
| **MCAT-S03b** | AgentOS | `catalog.json`; tests for codex, opencode, and `manual_paste`; reconciliation fixtures. OpenCode has zero models. | AgentOS `testEveryCatalogManifestValidates`, `testOpenCodeDriverMayHaveZeroBuiltInModels`, routing tests + full suite; Allnighter package + Mac wall | Remove only the newly added driver/model rows. Allnighter remains on its old data until S04; no half-cutover is allowed. |
| **MCAT-S04** | Allnighter | `Packages/AllnighterCore/Package.swift`; new Core `Resources/Catalog/catalog_overlay.json`; `ModelCatalog.swift`, `ModelCatalogTypes.swift`, `DefaultConfig.swift`, `AppConfig.swift`; `Apps/AllnighterMac/project.yml`; delete Mac `Resources/Drivers/*.json` + `team_default.json`; replace `DefaultConfigDriftTests.swift`; update `ModelCatalogTests.swift`, `ModelCatalogCLITests.swift`, `BuiltBundleConfigTests.swift`, relevant manifest/session tests | All overlay/authority/CLI hero tests; `rg` confirms no production built-in model array, capability encyclopedia, embedded manifest JSON, `team_default`, or Mac driver resource refs; AgentOS full tests; `bash scripts/check.sh` | Treat cutover + legacy deletion as one atomic slice. If red, restore the complete pre-S04 consumer path in the working slice; never ship both paths with precedence/fallback ambiguity. S01–S03 AgentOS catalog remains valid. |
| **MCAT-S05** | Allnighter | `catalog_overlay.json`; `BuiltInTeams.swift`; `MenuSelectionCopy.swift`; `MenuCatalog.swift`; `MenuSelectionGradeTests.swift`, `BuiltInTeamsTests.swift`, model-reference authority tests, help/menu projections if snapshots change | `MenuSelectionGradeTests`; `BuiltInTeamsTests`; `testBuiltInTeamExplicitModelReferencesExistOrAreDocumentedIdentityPins`; help/contract export check; full `bash scripts/check.sh`; AgentOS full tests | Restore only the affected intentional team identity pin or menu hint. Do not restore removed catalog literals; an absent model must resolve through existing capability/tier policy or fail with its existing honest diagnostic. |

**MCAT-S06** remains an opt-in AgentOS `LiveLabels` manual smoke packet.
**MCAT-S07** remains optional (`alln catalog validate`) and is not required to
make S01–S05 implementable. Neither may be pulled forward to block S01a.

### Per-slice reconciliation checklist

For every migrated driver/model group:

1. Diff AgentOS `BundledDefaults`, Allnighter `DefaultConfig`, Mac driver JSON,
   `ModelCatalog.builtIns`, and relevant fixtures.
2. Choose the canonical field value under the ownership table; preserve
   Allnighter production invoke/session/setup/streaming/image behavior unless
   the slice explicitly names and tests an intentional correction.
3. Assert manifest validation, exact args (including resume), timeouts,
   concurrency, wire label, role, and effort mapping before deleting a literal.
4. Keep the compatibility facade derived from the catalog until all call sites
   are cut over; do not keep embedded JSON/string/array data behind it.
5. Close with both repo commit hashes and the two-repo wall.

---

## Inference bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Catalog → roster | `ModelCatalog` | "Listed in catalog" ⇒ enabled on bench | Bench = roster ∩ catalog; `defaultOn` only on fresh install | `testBuiltInsDefaultEnabledOnFreshInstall` |
| AgentOS record → `Model.enabled` | `CatalogLoader` caller | Runtime existence chooses bench state | Materialization requires an explicit enablement closure; AgentOS owns no bench default | `testCatalogMaterializationRequiresEnablementPolicy` |
| Effort dial → wire | `Model` + manifest | Show dial when only one label exists | `supportsEffort` requires >1 variant OR manifest flag | `testAntigravityEffortVariantsGateEffortDial` |
| Tier → model id | `DefaultModelSettings` | Tier membership auto-updates when catalog entry removed | Stale id diagnosed (`MODEL_ROSTER_STALE_ID`); tiers manual | `testStaleRosterIDIsDiagnosed` |
| Team fallback → catalog | `BuiltInTeams` | Removed model still in fallback chain | Fallbacks reference tier/capability after S05 | `testNoBuiltInSeedPrefersRemovedAgyClaudeRoutes` |
| Drift test → SSOT | CI | Mirror agreement = catalog correct | Drift tests transitional until S04; then catalog-only | `testMergedCatalogNoSecondBuiltInsEncyclopedia` |
| Overlay vs catalog | Merge loader | Overlay duplicates wire labels | Overlay = policy fields only; wire fields fail decode | `testOverlayAcceptsPolicyFieldsOnly` |
| Bundle read → fallback | `CatalogLoader` | Any decode/validation failure means “resource missing” | Generated fallback is legal only when the resource URL is absent; invalid primary data fails | `testMalformedBundledCatalogDoesNotUseFallback` |
| Catalog add → fresh bench | Allnighter overlay | A new AgentOS row is automatically default-on | New rows are visible/off-bench until overlay `defaultOn`; runtime existence is not app policy | `testCatalogOnlyAddRemainsOffFreshBench` |
| Overlay caliber → substitution tier | `ModelCatalog` / `DefaultModelSettings` | Strength/capability metadata assigns Flagship/Balanced/Fast | `caliber` materializes `ModelCapabilities` only; tier membership remains explicit settings | `testOverlayCaliberDoesNotMutateTierMembership` |
| Driver → model requirement | `CatalogLoader` | Every headless CLI must ship a default model | A valid driver may have zero built-ins; OpenCode is the standing example | `testOpenCodeDriverMayHaveZeroBuiltInModels` |
| Hidden model → persisted roster | Merge loader | User roster re-enables a product-hidden built-in | Hidden wins; stale roster id is diagnosed and excluded | `testHiddenModelSuppressesPersistedRosterEntry` |
| Compatibility facade → second truth | `BundledDefaults` | Keeping the public API permits keeping old literals | Compatibility accessors derive only from `CatalogLoader`; no embedded manifest/model data remains | `testBundledDefaultsFacadeMatchesCatalog` |
| Model id/name → menu copy | `MenuCatalog` | Missing hint can be promoted into generated marketing prose | Existing built-ins use authored `{useWhen,dontUseWhen}`; fallback is neutral operational copy only | `testBuiltInMenuHintsRemainAuthoredAndBounded` |
| Manifest convergence → timeout | Driver migration slice | Copying shorter AgentOS defaults is behavior-preserving for Allnighter | Preserve the shipped 1800-second Allnighter invoke budget unless a separately named/tested runtime change authorizes otherwise | `testCatalogInvokeBudgetsMatchAllnighterProduction` |

---

## Immediate closeout (pre-MCAT)

Founder ruling applied **before** catalog unification ships:

- **Antigravity defaults:** only `model_gemini` (Gemini 3.6 Flash) on-bench by default.
- **Removed from built-in catalog:** `model_agy_opus`, `model_agy_sonnet` (code change on branch; tests green).

Long-term fix is MCAT-S01a+ so the next removal is one JSON edit.

---

## Related docs

- AgentOS: `docs/phases/00_AgentOS_Architecture_And_Roadmap.md` (P1)
- AgentOS: `docs/archive/phases/Model_Smoke_And_Driver_Detection.md`
- AgentOS: `docs/archive/phases/CLI_Detector_Promotion.md` (do not promote Bench to AgentOS)
- Allnighter: `docs/archive/phases/Substitution_Bench_Default_Settings.md`
- Allnighter: `docs/operations/Spec_Review.md`
- Allnighter: commit `a15a2a66` (opencode default removal pattern)
