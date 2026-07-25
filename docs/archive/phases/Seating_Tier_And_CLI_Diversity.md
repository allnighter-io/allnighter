# Seating — Tier + CLI Diversity

Status: **Complete — archived 2026-07-25.**
Spec Review sealed the law (`927B8CD4…`). S1–S3 shipped end-to-end.
Successor owner: `ModelCatalog.swift` + `TeamResolver.swift` + `RunDryRunJSON`.
Updated: 2026-07-25 (archived)
Evidence: `3B00A1A7` (max), `DCE9AE48` (min), Spec Review `927B8CD4…`
(Cursor panel: Opus / Cursor Sol / Cursor Grok + Fable lead).

Shipped: `6c3dff3d` (S1), `dd319f72` (S2), `70e045c4` (S3), deslop `569a0f13`,
reason honesty `405f586d`.

## Founder intent

When you pay for a panel, you get **different minds** — never a cheap mind on
a hard seat. Customs Allnighter has never rated sit at the floor. Within a
caliber band, prefer a family/CLI the crew does not already have. Degrade,
don't fail.

## Product value

Spec Review and every capability-only team stop seating junk Flagship and stop
stacking one family by accident. That is the product's "different minds" claim.

## Trusted workflow slice

Staffing only: catalog honesty for customs + resolver sort/filter + dry-run
seat visibility. No team redesign, no GUI, no SubstitutionTier wiring.

## Non-goals (out of this phase forever — open a new phase if needed)

- Wiring `SubstitutionTier` / `DefaultModelSettings` into the resolver (SEAT-F1).
- Renaming caliber bands or collapsing 4 → 3.
- Light-name word lists (`haiku`/`flash`/`mini`/…).
- `tier:` / `minTier:` on `TeamWorkerSpec`.
- `alln models repair` / disk migration of custom JSON.
- Capabilities-edit CLI for customs.
- Re-ranking `gemini_pro` vs Flash taste (fill Bug F entry only).

---

## Bugs this phase closes

| # | Bug | Close in |
| --- | --- | --- |
| **A** | `createCustom` persists donor flagship caps/rank (Haiku@100) | S1 |
| **B** | Family diversity under rank — dead on real benches | S2 |
| **C** | Custom `modelFamily` defaults to raw id | S2 |
| **D** | Scout resolved after rows; outside diversity | S2 |
| **E** | Triangulate `continue` skips diversity updates | S2 |
| **F** | Five built-ins missing `builtInCapabilities` (inherit donor) | S1 |

S00 (local roster disable of poisoned Haiku) already done on this machine —
does not replace S1.

**Hard dependency:** never ship S2 without S1. Diversity-alone leaves Haiku on
seat #2 (still Flagship band).

---

## Law (binding — Spec Review sealed)

Applies when `preferredModelId == nil` and `homeDriver == nil`. Preferred and
home-driver affinity unchanged.

### Sort (`strongest`)

1. caliber band — ≥95 / 85–94 / 70–84 / floor *(never crossed)*
2. preferred capability tags *(unchanged)*
3. family not yet on crew — `ModelCatalog.modelFamily`
4. driver not yet on crew — `driverId`
5. `strengthRank` descending
6. `id` ascending

Steps 3–4 never filter. Exhausted novelty → fall through to rank.
**Never block a run for diversity.**

### Band-aware exclusion filter (before `strongest`)

Today's id-exclusion can shrink the pool so only Haiku remains in Flagship.
Replace with:

```
unclaimed = (hasTags ∧ autoOK ∧ not excluded) in pool
bestBand = max caliberBand among unclaimed
           — or among all eligible if unclaimed is empty (reuse path)
filtered = pool ∖ diversityExclusionIds(claimed)
if filtered contains any (hasTags ∧ autoOK) with caliberBand == bestBand:
    pool = filtered
else:
    keep unfiltered pool   // reuse within best band; degrade, don't drop band
```

`bestBand` is taken from **unclaimed** candidates so a claimed Flagship
does not permanently lock the crew onto Flagship reuse and starve High-band
unused families (W1). When nothing unclaimed remains, fall back to absolute
best band and reuse.

When the chosen model’s family is already in `familyUsed`, append a warning
(reuse). Same for driver reuse optional one-liner.

### Unrated-model law (S1)

- No `builtInCapabilities` entry → inherit driver **tags** only, **rank = 40**.
- `createCustom` persists `ModelCapabilities()` (empty), not `fallbackCapabilities`.
- Delete `isLighterVariant` (Gemini “mini” misfire).
- Persisted custom ranks become inert; no repair CLI.
- `models add` human line: `Added as Unrated — seats last.`

### Family for customs (S2)

| driverId | family |
| --- | --- |
| `claude_code` | `claude` |
| `codex` | `gpt` |
| `grok` | `grok` |
| `kimi` | `kimi` |
| `cursor_agent`, `antigravity`, `opencode` | `driver:<id>` |

Known built-in ids keep the existing switch. Unknown id → `hostFamily(driverId)`
above, else `driver:<driverId>`.

### Scout + triangulate (S2 — closes D/E)

1. Resolve scout **before** answer/review rows (it runs first).
2. Seed `familyUsed` + `diversityUsed` from the scout pick when present.
3. After each triangulate pick, update both sets (remove the early `continue`
   that skips updates at `TeamResolver.swift:190`).

### Snapshot

Build `[modelId: ModelCapabilities]` once per `resolve()` / `selectModel` call
tree — no `CatalogFileIO` inside the sort comparator.

### Named consequences (document in code comment; not bugs)

- Sonnet often absent on a full bench after Lead claimed `claude`.
- Max may show grok twice after every family is used.
- Mid-band novelty can seat 75 over 84.

### Vocabulary (doc only — code keeps band numbers)

| Founder word | Band |
| --- | --- |
| Premium / high | ≥95 and 85–94 |
| Mid | 70–84 |
| Low / floor | <70 |

Resolver **never** reads `DefaultModelSettings`.

---

## Truth owners

| Truth | Owner after this phase |
| --- | --- |
| Who sits where | `TeamResolver.selectModel` / `strongest` |
| Rank + band thresholds | `ModelCatalog` (`builtInCapabilities`, `caliberBand`, `unratedModelRank = 40`) |
| Family | `ModelCatalog.modelFamily` / `hostFamily(driverId:)` |
| Seat visibility | `RunDryRunJSON.seats` (S3) |
| Auto shelf | `DefaultModelSettings` — untouched |

---

## Execution slices (ship all three — then archive)

### S1 — Catalog honesty (Bug A + F)

**Touch only**

- `Packages/AllnighterCore/Sources/AllnighterCore/ModelCatalog.swift`
- `Packages/AllnighterCore/Tests/AllnighterCoreTests/ModelCatalogTests.swift`
- `Packages/AllnighterCore/Sources/AllnighterCLI/ModelsCLI.swift` (add disclosure line only if needed)

**Do**

1. `createCustom`: `capabilities: ModelCapabilities()` (empty).
2. `capabilities()`: if no `builtInCapabilities` entry → tags from
   `fallbackCapabilities(driverId:)` **tags only**, `strengthRank = 40`.
3. Delete `isLighterVariant` and
   `ModelCatalogTests.testLighterVariantRanksBelowFlagship`.
4. Add `builtInCapabilities` for every missing built-in (exact list):

| id | Rank | Caps to mirror |
| --- | --- | --- |
| `model_agy_sonnet` | 74 | like `model_agy_opus` tags, rank just below agy opus (75) |
| `model_gemini_pro` | 76 | like `model_gemini` tags + planner/review as appropriate; above Flash 75 |
| `model_agy_gptoss` | 70 | mid floor of High/Mid edge — tags from richest agy peer minus security if not warranted |
| `model_chatgpt_54_mini` | 40 | Fast/floor; tags subset of `model_chatgpt_54` |
| `model_codex_spark` | 40 | Fast/floor; tags subset of chatgpt/codex peers |

   Exact tag sets: copy the nearest sibling in `builtInCapabilities` and only
   change `strengthRank` as above. Drift gate will catch omissions.

5. Test: `builtIns.map(\.id)` ⊆ `builtInCapabilities.keys`.
6. `models add` prints Unrated disclosure.

**Proof:** `swift test --package-path Packages/AllnighterCore --filter ModelCatalogTests`

**Commit:** `catalog(SEAT-S1): unrated customs rank 40; fill missing built-in caps`

---

### S2 — Resolver law (Bug B + C + D + E)

**Touch only**

- `Packages/AllnighterCore/Sources/AllnighterCore/ModelCatalog.swift`
  (`caliberBand`, `hostFamily`, `modelFamily`, `unratedModelRank`)
- `Packages/AllnighterCore/Sources/AllnighterCore/TeamResolver.swift`
- `Packages/AllnighterCore/Tests/AllnighterCoreTests/TeamResolverTests.swift`
- `Packages/AllnighterCore/Tests/AllnighterCoreTests/ModelCatalogTests.swift` (family)

**Do**

1. Move `caliberBand` into `ModelCatalog` (single owner next to ranks).
2. Reorder `strongest` keys per Law §Sort; pass `avoidFamilies` + used drivers.
3. Implement band-aware exclusion filter per Law §Filter.
4. Fix `modelFamily` / `hostFamily` per Law §Family.
5. Scout before rows; seed diversity sets; triangulate updates sets.
6. Snapshot capabilities map once per resolve.
7. Warning on family reuse.
8. Replace exact-tie-only diversity tests with FULL-bench golden tests (W1–W3, W5–W6).

**Fixture:** register the real poisoned Haiku shape as a test fixture
(rank 100, full Fable tag set, `origin: custom`, `driverId: claude_code`) —
do not rely on the developer’s disk.

**Proof:** `swift test --package-path Packages/AllnighterCore --filter 'TeamResolverTests|ModelCatalogTests'`

**Commit:** `resolve(SEAT-S2): family+driver above rank; band-aware exclude; scout/triangle diversity`

---

### S3 — Seat visibility + contract

**Touch only**

- `Packages/AllnighterCore/Sources/AllnighterCore/RunDryRunJSON.swift`
- Dry-run projection site in Engine/CLI that builds `RunDryRunJSON`
- `Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift`
  (`contractVersion` **4.0.1 → 4.0.2**)
- Tests for dry-run seats
- Regenerate: `alln dev export-contracts`

**Do**

1. Additive optional `seats: [Seat]?` on `RunDryRunJSON`:

```text
Seat { modelId, family, driverId, skillId, stage, reason }
```

   `reason` examples: `preferred`, `band+unusedFamily`, `band+unusedDriver`,
   `band+rank`, `reuseFamily`, `unratedFloor`, `reserveSkipped`.

2. Populate on `alln run --dry-run` for team runs (capability-only + lead + scout).
3. Persist the resolved-against ready model id list on the run snapshot
   (field name: `resolvedBenchModelIds: [String]` on the journal run record —
   additive; if the journal schema makes this painful, store under existing
   warnings/audit extension the Engine already uses — prefer a real field).
4. Bump contract 4.0.2; export-contracts; fixture `team_run.json` if locked to
   `contractVersion`.

**Proof:**
`swift test --package-path Packages/AllnighterCore --filter 'RunDryRun|TeamResolver|ContractRegistry'`
`alln dev export-contracts --check`
Live: `alln run --dry-run --json --team code_spec_review_min "x" | jq .seats`

**Commit:** `cli(SEAT-S3): dry-run seats[] + contract 4.0.2`

---

## Works Test (phase exit — all must pass)

Bench **FULL** = `ModelCatalog.defaultFreshModels()` **enabled** built-ins that
`allowsAutomaticSubstitution`, plus fixture custom Haiku (rank-100 record).
Cursor Sol stays on the bench but is never auto-picked (`neverAutomaticSubstituteIds`).

| # | Case | Exact expect |
| --- | --- | --- |
| **W1** | Spec Review Min × FULL after S1+S2 | Lead `model_fable`. Answers **exactly** `[model_chatgpt, model_cursor_grok_45, model_kimi_k3]`. Custom Haiku **absent**. Families `{gpt,grok,kimi}` + lead `claude`. |
| **W2** | Same FULL through **pre-fix** comparator (test helper) | `[fable, custom_haiku, chatgpt, opus]` — comment cites `DCE9AE48`. |
| **W3** | Spec Review Max × FULL after S1+S2 | Custom Haiku absent. Scout = `model_grok` (preferred). Among answer+review+lead: no single family holds a strict majority; ≥4 distinct families. |
| **W4** | `createCustom(driverId: "claude_code", …)` | Persisted `capabilityTags` empty; `capabilities(id).strengthRank == 40`; family `claude`. |
| **W5** | Bench = `[model_fable]` only | `isRunnable`; no hard block; warning ok. |
| **W6** | Capability-only row with `preferredModelId` on an already-used family | Resolves to preferred — diversity does not override. |
| **W7** | Drift: every `builtIns.id` ∈ `builtInCapabilities` | Hard fail if missing. |
| **W8** | `alln run --dry-run --team code_spec_review_min --json` | `seats` present, length = seatCount, each row has `modelId`+`family`+`reason`; Haiku absent when fixture Haiku is enabled on a test roster. |

If W1 mismatches the exact tuple at implementation time: **stop and investigate**
(do not “fix the test”). Re-derive from Law; amend this doc in the same PR
only if the law was wrong — not to paper over a bug.

---

## Rejection ledger (do not reopen)

| # | Rejected | Why |
| --- | --- | --- |
| R1 | Mid-flight binary swap while panels live | Cleared 2026-07-25; still don't disrupt live identityAlive runs |
| R2 | Hard-fail on diversity | Degrade > block |
| R3 | Seat optimizer / lab economics | Overcomplicates |
| R4 | Id-dedup as “diversity” | Lie |
| R5 | Haiku as Mid | Floor only |
| R6 | Wire SubstitutionTier into resolver | Live shelf regresses Leads |
| R7 | Light-name word list | Unrated law; Gemini mini misfire |
| R8 | Rename/collapse bands | Churn |
| R9 | `tier:` on TeamWorkerSpec | Schema churn |
| R10 | models repair CLI | Read-path inert |
| R11 | S2 without S1 | Haiku still Flagship seat #2 |
| R12 | Fuzzy Works Tests | Pass on Bug A alone |
| R13 | Customs default rank 80 | Re-creates A |
| R14 | Half-shipping this phase | Founder rule: end-to-end or don't start |

---

## Impact

| Surface | Change |
| --- | --- |
| Mac / iOS GUI | None |
| CLI | Dry-run gains `seats[]`; contract 4.0.2 |
| Catalog | Custom add + capabilities(); five built-in cap rows |
| Resolver | Sort, filter, scout order, triangle diversity |
| In-flight | Check `alln ps` for `identityAlive` before installing a new `alln`; wait if any |

## Implementation order (one agent / one chain)

```text
S1 commit → S2 commit → S3 commit + export-contracts
→ W1–W8 green → bash scripts/check.sh (or Core wall + export check)
→ archive this doc → board/routing update → phase Complete
```

Do not leave S1 landed without S2/S3 in the same execution chain.
Deslop + Code Audit at phase closeout per Execution Playbook.

## Done when (archive criteria)

- [x] Spec Review sealed law (`927B8CD4…`)
- [x] S00 local Haiku disabled
- [x] S1 shipped + committed (`6c3dff3d`)
- [x] S2 shipped + committed (`dd319f72`)
- [x] S3 shipped + committed; contract 4.0.2; export-contracts `--check` green (`70e045c4`)
- [x] W1–W8 green
- [x] Deslop FIXED (`569a0f13`); Code Audit CLEAN
- [x] Doc moved to `docs/archive/phases/`; board + routing updated; successor owner = code SSOT above

## Proof commands (phase wall)

```text
swift test --package-path Packages/AllnighterCore --filter 'ModelCatalogTests|TeamResolverTests|RunDryRun|ContractRegistry'
swift run --package-path Packages/AllnighterCore alln dev export-contracts --check
alln run --dry-run --json --team code_spec_review_min "seat check"   # seats[] present
```
