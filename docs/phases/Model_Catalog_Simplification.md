# Model Catalog Unification

Status: **Ready for Implementation** — Spec Review **Ready** (2026-07-27); start **MCAT-S01a** in AgentOS  
Owner: AgentOS (`AgentOSCLI`) first → Allnighter consumer cutover  
Created: 2026-07-27  
Updated: 2026-07-27  
Process: `docs/workflows/SSOT_Founder_Input_Workflow.md` →
`docs/workflows/SSOT_Feature_Workflow.md`  
Depends on: AgentOS P1 CLI runtime (`BundledDefaults`, `Model`, `EffortLevel`,
`DriverManifest`); Allnighter `ModelCatalog.swift`, `DefaultConfig.swift`,
`team_default.json`; archived `Model_Smoke_And_Driver_Detection.md` boundary law

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
| `ModelCatalog.builtIns` | AllnighterCore | **20 models, 6 drivers** — parallel SSOT |
| `builtInCapabilities` / `strengthRank` | AllnighterCore | Seating policy mixed into catalog |
| `team_default.json` | Mac bundle | Must match `defaultFreshModels()` or CI fails |
| `DefaultConfig` manifest strings | AllnighterEngine | Third driver-manifest copy |
| `Resources/Drivers/*.json` | Mac bundle | Fourth driver-manifest copy |
| `EffortRoutingTests.swift` | Both repos | Fifth duplicate — near-identical tests in AgentOS + Allnighter |
| `MenuSelectionCopy` | AllnighterCore | Per-model-id hand copy |
| `BuiltInTeams` fallback chains | AllnighterCore | Hardcoded `model_*` ids |
| `DefaultModelSettings` tiers | AllnighterCore | Product policy (keep) |

**Dependency note:** Allnighter pins AgentOS via **local path**
(`.package(path: "../../../AgentOS")`). S01–S03 and S04–S05 can land in adjacent
commits with no version-publish ceremony. CI must check out both siblings.

**Triggering incident (2026-07-27):** Removing agy Opus/Sonnet 4.6 from defaults
required edits across `ModelCatalog.swift`, `team_default.json`, `MenuSelectionCopy`,
`BuiltInTeams`, and multiple test files — for a product decision that is one JSON
object in a unified catalog.

**What Allnighter already inherits from AgentOS (do not reimplement):**

- `Model`, `Model.resolvedLabel(at:)`, `Model.supportsEffort(manifest:)`
- `EffortLevel` in `RuntimeEnums.swift` (`low` / `med` / `high`)
- `DriverManifest.Invoke.effortFlag` + `{{effortArgs}}` substitution
- `ModelSmokeVerifier`, `CLIDetector` / probe records

**What does not exist yet (verified 2026-07-27):** no `catalog.json`, no
`CatalogLoader`, no `resources:` entry on the AgentOSCLI target in `Package.swift`.
Allnighter does not call `BundledDefaults` today — S04 is first-time integration.

**Boundary law** (archived AgentOS `Model_Smoke_And_Driver_Detection.md`):

> AgentOS = what exists and works. Apps = what we should use.

Bug: model *definitions* are duplicated in both layers instead of flowing one way.

### SSOT

**Truth owner (target):**

| Concern | Owner after cutover |
| --- | --- |
| Driver manifests + curated model wire labels + effort mapping | AgentOS `Catalog/catalog.json` + `CatalogLoader` |
| Bench default on/off, hidden ids, caliber/seating, `menuHint` | Allnighter `catalog_overlay.json` + merge at load |
| User enabled set | `Config/model_roster.json` (unchanged) |
| Substitution tiers | `default_model_settings.json` (unchanged) |

**Lie-prone layers:**

- `MenuSelectionCopy` per-model prose → overlay `menuHint` (S05)
- `BuiltInTeams` hardcoded fallback ids → tier/capability refs (S05)
- `team_default.json` mirror → delete or generate from catalog (S04)
- `DefaultConfigDriftTests` mirror agreement → transitional only until S04

**New/changed semantic rules:**

1. One runtime catalog file in AgentOS; Allnighter merges overlay — never a second full catalog in Swift.
2. Each model declares `effort`: `variants` | `driver` | `fixed` | `none` (see Effort schema).
3. Removing a built-in default = delete catalog entry or `hidden: true` in overlay — not a cross-repo sweep.
4. Shared drivers (claude, grok, cursor, kimi) defined once in AgentOS only.
5. **antigravity, codex, opencode** are real working CLIs → shared AgentOS catalog (not overlay-only).
6. Overlay holds only `defaultOn`, `hidden`, `caliber`, and `menuHint` — not duplicate model wire data.

**Duplicate truth to delete (by slice):**

- S04: `ModelCatalog.builtIns` Swift array, `team_default.json` model rows, `DefaultConfig` manifest strings
- S05: `MenuSelectionCopy` entries for built-ins; `BuiltInTeams` `model_agy_*` style ids
- S03: duplicate manifests in Allnighter bundle where AgentOS catalog owns them
- S02: de-duplicate `EffortRoutingTests` (do not "move" — both repos must stay green)

### Effort / reasoning schema (one dial, four authoring labels)

Composer exposes one **Effort** control. Catalog entry documents how it maps.

**Runtime law (Spec Review locked):** these four values are **catalog-authoring and
loader-validation labels only**. `Model`, `EffortLevel`, and `DriverManifest` are
**unchanged**. Today there are two mechanisms: `effortVariants` and
`effortFlag`; `fixed` is already a degenerate variants map; `none` is absence of both.

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
  "effort": "driver",
  "label": { "default": "opus" }
}
```

**Overlay example** (Allnighter — not wire data):

```json
{
  "model_gemini": { "defaultOn": true },
  "model_agy_gptoss": { "defaultOn": false, "menuHint": "GPT-OSS 120B via Antigravity" }
}
```

Loader validates: `effort: "driver"` requires manifest `effortFlag`; `effort: "variants"`
requires ≥2 distinct `byEffort` values; mutual exclusion enforced in CI.

### Implementation

**Packaging (S01a must settle this):**

| Option | Decision |
| --- | --- |
| **A. Real bundled file** | **Primary** — add `resources:` to AgentOSCLI; read via `Bundle.module` |
| **B. Generated Swift constant** | **Fallback** — JSON remains authored source; drift test guards generated output |
| **C. Filesystem override** | **Rejected** — two runtime truth sources |

S01a acceptance: fresh checkout → `swift build` → runtime read of `catalog.json`
→ Mac app resolves same file at launch. If Mac target fails, switch to B and continue.

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

- **AgentOS:** `Catalog/catalog.json`, `CatalogLoader.swift`, first `resources:` on AgentOSCLI target
- **Allnighter:** `ModelCatalog` loads AgentOS + `catalog_overlay.json`; shrink `ModelCatalog.swift`

**Mac app impact:** `AppConfig.loadDefaultModels()` reads merged catalog; drop `team_default.json` model list.

**iOS app impact:** None for S01–S05 (reads same Core catalog).

**Agent driver impact:** None — wire labels unchanged; only authoring moves.

**Auth/privacy/permissions impact:** None.

### Proof

**Product Works Tests (hero claims):**

1. Fresh install (no roster): `alln models list --bench --json` shows exactly overlay `defaultOn` models.
2. Antigravity: only `model_gemini` default-on; no removed agy Claude routes in list.
3. Team effort high on `model_gemini` → invoke args contain `Gemini 3.6 Flash (High)`.
4. Append one model to `catalog.json` → appears in `alln models list` with **no hand-edited Swift array change**.

**Required new tests (name them in slice PRs):**

| Test | Slice | Claim |
| --- | --- | --- |
| `CatalogLoaderTests` | S01a–S02 | Load + reject malformed effort shapes |
| `testEffortDriverRequiresManifestFlag` | S02 | `driver` without `effortFlag` → load error |
| `testEffortVariantsRequiresDistinctByEffort` | S02 | `variants` with <2 labels → load error |
| `testOneCatalogEditAddsModelWithoutSwiftTouch` | S01a/S04 | Hero one-edit claim |
| `testOverlayHiddenSuppressesBenchDefault` | S04 | Overlay wins over catalog `defaultOn` |
| `testMergedCatalogNoSecondBuiltInsEncyclopedia` | S04 | No parallel Swift catalog SSOT |

**Transitional only (retire at S04):** `DefaultConfigDriftTests` proves mirrors agree —
that is the disease, not the cure. Replace with catalog-authoritative drift or delete.

**S01a commands:**

```bash
cd ../AgentOS && swift build && swift test --filter CatalogLoaderTests
cd - && swift build --package-path Packages/AllnighterCore
alln models list --driver antigravity --bench
```

**Missing proof / waiver:** MCAT-S06 `LiveLabels` — waived for CI; manual on founder Mac.

### Done When

- [ ] AgentOS `catalog.json` is the only runtime definition for bundled drivers + models
- [ ] Allnighter loads catalog + overlay; no `builtIns` Swift encyclopedia
- [ ] One-file add/remove for default models (including agy policy above)
- [ ] Effort schema validated in loader tests; runtime types unchanged
- [ ] `DefaultConfigDriftTests` retired or replaced by catalog-authoritative test
- [ ] Teaching surface: no `MenuSelectionCopy` keys for removed built-ins
- [ ] MCAT-S01a through S05 committed; packet archived after promotion

---

## Build slices

| Slice | Repo | Deliverable |
| --- | --- | --- |
| **MCAT-S01a** | AgentOS | Schema + `CatalogLoader` + **grok only** (1 model); `Bundle.module` proof; `CatalogLoaderTests` |
| **MCAT-S01b** | AgentOS | claude / cursor / kimi migrated from `BundledDefaults` |
| **MCAT-S02** | AgentOS | Effort authoring schema; loader → `effortVariants`; de-duplicate `EffortRoutingTests` |
| **MCAT-S03a** | AgentOS | **antigravity** driver + models (Gemini Flash effort variants; founder-urgent) |
| **MCAT-S03b** | AgentOS | codex + opencode drivers + models; drop Allnighter `DefaultConfig` manifest dupes |
| **MCAT-S04** | Allnighter | `ModelCatalog` loads AgentOS + overlay; delete `builtIns` array; retire mirror drift tests |
| **MCAT-S05** | Allnighter | `BuiltInTeams` tier/capability fallbacks; `menuHint` replaces `MenuSelectionCopy` built-ins |
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
| Drift test → SSOT | CI | Mirror agreement = catalog correct | Drift tests transitional until S04; then catalog-only | `testMergedCatalogNoSecondBuiltInsEncyclopedia` |
| Overlay vs catalog | Merge loader | Overlay duplicates wire labels | Overlay = policy fields only | `testOverlayHiddenSuppressesBenchDefault` |

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
