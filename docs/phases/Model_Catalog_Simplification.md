# Model Catalog Unification

Status: **Draft — Ready for Implementation** (MCAT-S01 starts in AgentOS)  
Owner: AgentOS (`AgentOSCLI`) first → Allnighter consumer cutover  
Created: 2026-07-27  
Updated: 2026-07-27  
Process: `docs/workflows/SSOT_Founder_Input_Workflow.md` →
`docs/workflows/SSOT_Feature_Workflow.md`  
Depends on: AgentOS P1 CLI runtime (`BundledDefaults`, `Model`, `EffortLevel`,
`DriverManifest`); Allnighter `ModelCatalog.swift`, `DefaultConfig.swift`,
`team_default.json`; archived `Model_Smoke_And_Driver_Detection.md` boundary law

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
  Five overlapping copies of model + driver truth (see Current State below).
  Effort routing works in AgentOS; authoring is scattered.

Truth owner:
  Runtime wire catalog → AgentOS `catalog.json` (new).
  Bench / tiers / seating → Allnighter overlay + existing persistence.

CLI surface:
  Existing `alln models list|enable|disable|add` — no new verbs required for S01–S04;
  loader reads same ids. Optional MCAT-S07: `alln catalog validate` for CI.

Help surface (topics / search terms / recovery):
  `HelpTopicRegistry` models topic; `alln models list`; menu model rows from
  live catalog — no hand-maintained per-id copy in `MenuSelectionCopy` after S05.

Proof scenario:
  Delete one catalog entry → one file change → tests green → `alln models list`
  no longer lists it; effort variants still resolve for survivors.

Blocking questions:
  None for S01–S03. S04 needs founder confirm: ship Allnighter-only drivers
  (antigravity, codex, opencode) in AgentOS catalog vs Allnighter overlay only.

Next slice:
  MCAT-S01 in AgentOS — `catalog.json` + `CatalogLoader` for grok/claude/cursor/kimi.
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
| Terraform | Single source + provider schema validation | We have drift tests but five handwritten sources |
| AgentOS `BundledDefaults` | Small curated model lists per driver in one module | Allnighter forked and expanded without consuming |
| OpenCode BYOK ruling (`a15a2a66`) | Driver stays; defaults removed; `alln models add` for long tail | Same pattern for agy Claude routes |

**Product value:** One edit to add, remove, or re-rank a default seat — including
how low/med/high maps to wire labels — without touching teams, menu copy, and
bundle mirrors.

**Trusted workflow slice:**

```text
AgentOS catalog.json (drivers + models + effort)
  + Allnighter overlay (defaultOn, caliber, hidden)
  -> ModelCatalog.load()
  -> alln models list / GUI picker / TeamResolver ready bench
  -> invoke uses resolvedLabel(at: effort) or manifest effortFlag
```

**Non-goals:**

- Dynamic live discovery from `agy --list-models` as default catalog source
- Moving substitution tiers or `BuiltInTeams` into AgentOS
- Menu marketing copy in the runtime catalog
- Replacing `model_roster.json` user persistence

### Current State

**Existing truth owners:**

| Layer | Owner today | Problem |
| --- | --- | --- |
| `Model`, `EffortLevel`, effort routing | AgentOSCLI | Correct runtime; incomplete catalog |
| `BundledDefaults` | AgentOSCLI | ~10 models, 4 drivers — partial SSOT |
| `ModelCatalog.builtIns` | AllnighterCore | ~20 models, 7 drivers — parallel SSOT |
| `builtInCapabilities` / `strengthRank` | AllnighterCore | Seating policy mixed into catalog |
| `team_default.json` | Mac bundle | Must match `defaultFreshModels()` or CI fails |
| `DefaultConfig` manifest strings | AllnighterEngine | Third driver-manifest copy |
| `Resources/Drivers/*.json` | Mac bundle | Fourth driver-manifest copy |
| `MenuSelectionCopy` | AllnighterCore | Per-model-id hand copy |
| `BuiltInTeams` fallback chains | AllnighterCore | Hardcoded `model_*` ids |
| `DefaultModelSettings` tiers | AllnighterCore | Product policy (keep) |

**Triggering incident (2026-07-27):** Removing agy Opus/Sonnet 4.6 from defaults
required edits across `ModelCatalog.swift`, `team_default.json`, `MenuSelectionCopy`,
`BuiltInTeams`, and multiple test files — for a product decision that is one JSON
object in a unified catalog.

**What Allnighter already inherits from AgentOS (do not reimplement):**

- `Model`, `Model.resolvedLabel(at:)`, `Model.supportsEffort(manifest:)`
- `EffortLevel` (`low` / `med` / `high`)
- `DriverManifest.Invoke.effortFlag` + `{{effortArgs}}` substitution
- `ModelSmokeVerifier`, `CLIDetector` / probe records

**Boundary law** (archived AgentOS `Model_Smoke_And_Driver_Detection.md`):

> AgentOS = what exists and works. Apps = what we should use.

Bug: model *definitions* are duplicated in both layers instead of flowing one way.

### SSOT

**Truth owner (target):**

| Concern | Owner after cutover |
| --- | --- |
| Driver manifests + curated model wire labels + effort mapping | AgentOS `Catalog/catalog.json` + `CatalogLoader` |
| Bench default on/off, hidden ids, caliber/seating | Allnighter `catalog_overlay.json` + merge at load |
| User enabled set | `Config/model_roster.json` (unchanged) |
| Substitution tiers | `default_model_settings.json` (unchanged) |

**Lie-prone layers:**

- `MenuSelectionCopy` per-model prose (delete or generate from overlay `menuHint`)
- `BuiltInTeams` hardcoded fallback ids (replace with tier/capability refs)
- `team_default.json` mirror (delete or generate from catalog)

**New/changed semantic rules:**

1. One runtime catalog file in AgentOS; Allnighter merges overlay — never a second full catalog in Swift.
2. Each model declares `effort`: `variants` | `driver` | `fixed` | `none` (see Effort schema).
3. Removing a built-in default = delete catalog entry or `hidden: true` in overlay — not a cross-repo sweep.
4. Shared drivers (claude, grok, cursor, kimi) defined once in AgentOS only.

**Duplicate truth to delete (by slice):**

- S04: `ModelCatalog.builtIns` Swift array, `team_default.json` model rows, `DefaultConfig` manifest strings
- S05: `MenuSelectionCopy` entries for built-ins; `BuiltInTeams` `model_agy_*` style ids
- S03: duplicate manifests in Allnighter bundle where AgentOS catalog owns them

### Effort / reasoning schema (one dial, four mechanisms)

Composer exposes one **Effort** control. Catalog entry documents how it maps:

| `effort` value | Meaning | Example |
| --- | --- | --- |
| `driver` | Use manifest `effortFlag` | Claude `--effort high`, Codex `-c model_reasoning_effort="high"` |
| `variants` | Per-level wire labels on model | `Gemini 3.6 Flash (High)`, `cursor-grok-4.5-high` |
| `fixed` | Single label; dial hidden | `GPT-OSS 120B (Medium)` |
| `none` | No effort control | Cursor Composer, Kimi (today) |

**Example entries:**

```json
{
  "id": "model_gemini",
  "displayName": "Gemini 3.6 Flash",
  "driver": "antigravity",
  "role": "answerer",
  "defaultOn": true,
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
```

```json
{
  "id": "model_opus",
  "displayName": "Opus 5",
  "driver": "claude_code",
  "role": "both",
  "defaultOn": true,
  "effort": "driver",
  "label": { "default": "opus" }
}
```

Loader validates: `effort: "driver"` requires manifest `effortFlag`; `effort: "variants"`
requires ≥2 distinct `byEffort` values; mutual exclusion enforced in CI.

### Implementation

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

- **AgentOS:** `Catalog/catalog.json`, `CatalogLoader.swift`; thin `BundledDefaults` facade
- **Allnighter:** `ModelCatalog` loads AgentOS + overlay; shrink `ModelCatalog.swift`

**Mac app impact:** `AppConfig.loadDefaultModels()` reads merged catalog; drop `team_default.json` model list.

**iOS app impact:** None for S01–S05 (reads same Core catalog).

**Agent driver impact:** None — wire labels unchanged; only authoring moves.

**Auth/privacy/permissions impact:** None.

### Proof

**Works Test:**

1. Fresh install (no roster file): `alln models list --bench --json` shows exactly overlay `defaultOn` models.
2. Antigravity: only `model_gemini` default-on; no `model_agy_opus` / `model_agy_sonnet` in list.
3. Set team effort high on `model_gemini`; invoke args contain `Gemini 3.6 Flash (High)` (existing `EffortRoutingTests` class).
4. Add one line to `catalog.json`; `swift test --filter CatalogLoaderTests` passes without editing Swift arrays.

**User gesture:** CLI setup → Antigravity card → Models on this CLI shows only shipped defaults.

**Exact command:**

```bash
alln models list --driver antigravity --bench
swift test --filter CatalogLoaderTests
swift test --filter DefaultConfigDriftTests
```

**Missing proof / waiver:** MCAT-S06 `LiveLabels` opt-in local smoke — waiver for CI; manual on founder Mac.

### Done When

- [ ] AgentOS `catalog.json` is the only runtime definition for bundled drivers + models
- [ ] Allnighter loads catalog + overlay; no `builtIns` Swift encyclopedia
- [ ] One-file add/remove for default models (including agy policy above)
- [ ] Effort schema validated in loader tests
- [ ] `DefaultConfigDriftTests` retired or replaced by catalog drift test
- [ ] Teaching surface: no `MenuSelectionCopy` keys for removed built-ins
- [ ] MCAT-S01–S05 slices committed; packet archived after promotion

---

## Build slices

| Slice | Repo | Deliverable |
| --- | --- | --- |
| **MCAT-S01** | AgentOS | `catalog.json` + `CatalogLoader` + tests; migrate grok/claude/cursor/kimi from `BundledDefaults` |
| **MCAT-S02** | AgentOS | Effort schema (`variants`/`driver`/`fixed`/`none`); loader → `effortVariants`; move `EffortRoutingTests` |
| **MCAT-S03** | AgentOS | antigravity, codex, opencode drivers + models in catalog; drop Allnighter `DefaultConfig` manifest dupes |
| **MCAT-S04** | Allnighter | `ModelCatalog` loads AgentOS + overlay; delete `builtIns` array; fix `team_default.json` drift |
| **MCAT-S05** | Allnighter | `BuiltInTeams` tier/capability fallbacks; trim `MenuSelectionCopy`; agy Opus/Sonnet not in defaults |
| **MCAT-S06** | AgentOS | Opt-in `LiveLabels` — smoke every curated label on installed CLIs |
| **MCAT-S07** (optional) | Allnighter | `alln catalog validate` for CI / pre-commit |

Each slice keeps Allnighter green. No big-bang.

---

## Inference bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Catalog → roster | `ModelCatalog` | "Listed in catalog" ⇒ enabled on bench | Bench = roster ∩ catalog; `defaultOn` only on fresh install | `testBuiltInsDefaultEnabledOnFreshInstall` |
| Effort dial → wire | `Model` + manifest | Show dial when only one label exists | `supportsEffort` requires >1 variant OR manifest flag | `testAntigravityEffortVariantsGateEffortDial` |
| Tier → model id | `DefaultModelSettings` | Tier membership auto-updates when catalog entry removed | Stale id diagnosed (`MODEL_ROSTER_STALE_ID`); tiers manual | `testStaleRosterIDIsDiagnosed` |
| Team fallback → catalog | `BuiltInTeams` | Removed model still in fallback chain | Fallbacks reference tier/capability after S05 | `testNoBuiltInSeedPrefersRemovedAgyClaudeRoutes` |

---

## Immediate closeout (pre-MCAT)

Founder ruling applied **before** catalog unification ships:

- **Antigravity defaults:** only `model_gemini` (Gemini 3.6 Flash) on-bench by default.
- **Removed from built-in catalog:** `model_agy_opus`, `model_agy_sonnet` (code change on branch; tests green).

Long-term fix is MCAT-S01+ so the next removal is one JSON edit.

---

## Related docs

- AgentOS: `docs/phases/00_AgentOS_Architecture_And_Roadmap.md` (P1)
- AgentOS: `docs/archive/phases/Model_Smoke_And_Driver_Detection.md`
- AgentOS: `docs/archive/phases/CLI_Detector_Promotion.md` (do not promote Bench to AgentOS)
- Allnighter: `docs/archive/phases/Substitution_Bench_Default_Settings.md`
- Allnighter: commit `a15a2a66` (opencode default removal pattern)
