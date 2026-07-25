# Seating — Tier + CLI Diversity (simplify)

Status: **Draft — REVIEW ONLY. Not authorized to implement.** Live runs
must not be disrupted; this packet is for founder read-before-build.
Owner: `TeamResolver.swift` + `ModelCatalog.swift` (staffing law), not teams.
Updated: 2026-07-25
Evidence runs: `code_spec_review_max` `3B00A1A7` (Haiku on First Principles);
`code_spec_review_min` `DCE9AE48` (3× Claude among 4 seats).

## Founder intent

Haiku must never take a hard judgment seat. Spec Review crews must not stack
one CLI/family. The existing "diversity" machinery looks present and is
mostly inert. Prefer a rule that works ~90% of the time over a clever sort.

## Product value

Blind multi-model review only works if seats are different minds. A crew of
Claude×N + one token outsider is theater. Cheap models belong on easy work.

## Trusted workflow slice

Staffing only: how `TeamResolver` picks a model for a capability-only row
(and what `models add` stamps onto a custom record). No team redesign, no
Spec Review prompt changes, no GUI.

## Non-goals

- Re-ranking every built-in by taste in this packet (except Haiku placement).
- Hard "never two Claudes" blocks that fail a run when the bench is thin.
- New schemas, menus, or agent-facing contract bumps unless a slice needs them.
- Touching binaries or catalog JSON while runs are in flight.

---

## What broke (verified in code — do not re-litigate)

### Bug A — custom Haiku inherited Fable's rank 100

`ModelCatalog.createCustom` persists `fallbackCapabilities(driverId:)`, which
is the richest built-in on that driver. For `claude_code` that is Fable
(`strengthRank: 100`). The on-disk custom Haiku record therefore sits in the
Flagship band (≥95) and wins every capability-only first pick after Fable is
reserved for Lead.

`isLighterVariant` only knows `mini` / `spark`, and only on the tag-less read
path — never at write time, and never for `haiku`.

### Bug B — "family diversity" never fires on a real bench

`strongest()` order today:

1. caliber band (≥95 / 85–94 / 70–84 / floor)
2. preferred capability tags
3. **strengthRank**
4. family not-yet-used ← dead on production data
5. id alphabetical

Built-in ranks are distinct integers, so step 3 always decides and step 4
never runs. What *does* run is `diversityUsed` (distinct **model ids** only):
Haiku + Opus + Sonnet + Fable = "diverse." Tests only cover exact rank ties.

### Bug C — custom models have no family

`modelFamily` is a hardcoded id switch; `default: return modelId`. Custom
Haiku's "family" is its own id, not `claude`, even with `driverId:
claude_code`.

### Bug D — scout sits outside diversity

Scout resolves after worker rows and neither contributes to nor consults
`familyUsed` / `diversityUsed`.

---

## Zoom out — delete complexity, keep two dials

We already have the two concepts the product needs:

| Dial | Existing owner | Meaning |
| --- | --- | --- |
| **Tier** | `SubstitutionTier`: Flagship / Balanced / Fast (founder: premium / mid / low) | How hard is this mind? |
| **CLI / family** | `driverId` + `modelFamily` | Whose mind is this? |

Today seating mostly ignores both dials as policy and races a 0–100
`strengthRank` integer instead. That is the overcomplication.

### Proposed law (simple — aim 90%)

For every **capability-only** seat (no `preferredModelId`):

1. **Stay in the right tier.** Need hard judgment → Flagship/High first;
   easy work → Fast/low is eligible and preferred for that class of work.
2. **Prefer a CLI the crew does not already have.** Same tier, unused CLI
   beats same-CLI stronger rank.
3. **Then** pick the strongest remaining match (tags + readiness).
4. **Degrade, don't fail.** If every ready CLI is already on the crew, reuse
   is allowed (warning ok). Never block a run for diversity alone.

That is one reorder inside `strongest()` (CLI/family **above** raw rank
*within* a tier/band) plus honest catalog data. Not a second resolver.

Lead / exact preferred rows stay untouched. Triangulate rows already spread
by driver — leave them.

### Haiku placement (founder ruling for this packet)

Haiku is **not** mid. Trust order: Gemini 3.6 Flash and Compose 2.5 ≫ Haiku.
Haiku is **floor / Fast** — the weakest auto-eligible mind we staff, below
Flash (~75) and Compose 2.5 (~80), and below Compose Fast (~50) if we keep
that seat. Exact number is an implementation detail; the band is floor.

Custom add must never stamp Flagship/High onto a light name
(`haiku`, `flash`, `mini`, `spark`, `lite`, `nano`, `small`).

### What we stop doing

- Treating family diversity as an exact-rank tiebreak.
- Letting `models add` copy a donor flagship's rank/tags wholesale.
- Claiming id-dedup is "diversity."
- Designing a multi-pass "roster economics" system for this bug.

---

## Truth owner / lie-prone layer

| Truth | Owner |
| --- | --- |
| Who sits where on a run | `TeamResolver` (+ `TeamAssembler` for lead) |
| How strong / what family a model is | `ModelCatalog` (`strengthRank`, `modelFamily`, custom create) |
| User shelf labels (Flagship/Balanced/Fast) | `DefaultModelSettings` / `SubstitutionTier` — already exist; seating should stop fighting them |

Lie-prone: custom model JSON on disk; any doc that says "we diversify by
family" while sort priority still puts rank first; tests that only green on
synthetic ties.

## Duplicate truth to delete (when implementing)

- Dead comment at `ModelCatalog.modelFamily` ("tiebreak only") once family is
  a real within-tier preference.
- Dual stories: "caliber bands for preference" vs "family only on exact tie."

---

## Impact (when authorized — not now)

| Surface | Impact |
| --- | --- |
| Mac / iOS GUI | None required |
| CLI contract | None unless help copy mentions staffing |
| In-flight runs | **Do not ship while panels are live.** Resolver + catalog are on the hot path of `alln` / `alln serve`. |
| Drivers | None |

## Works Test (when authorized)

1. Custom Haiku on bench → Spec Review Min First Principles is **not** Haiku;
   Haiku only appears on easy/Fast-class fills if at all.
2. Spec Review Min with Fable lead + ready Kimi/Grok/Gemini/Compose → among
   the three answer seats, **≥2 distinct families/CLIs** (not Claude×3).
3. Spec Review Max → no single family holds a majority of answer+review seats
   when ≥4 families are ready.
4. Thin bench (only Claude ready) → run still staffs; warning ok.

Proof sketch: extend `TeamResolverTests` / `ModelCatalogTests` with a real
rank-spread fixture (not an exact tie). Live: one Min + one Max dry seating
dump before any mutating run.

## Done when

- [ ] Founder ratifies or rejects the simple law above (tier + prefer other CLI).
- [ ] Founder confirms Haiku = floor (not weakest-mid).
- [ ] Implementation authorized **after** in-flight Spec Review / work panels finish.
- [ ] Bugs A–D closed or explicitly waived in one small slice.
- [ ] Works Test green; no contract churn unless help needs a sentence.

## Open questions for founder

1. **Diversity unit:** CLI (`driverId`) or reasoning family (`claude` /
   `gpt` / `grok` / …)? Cursor-hosted Grok vs xAI Grok — same family or two
   CLIs? (Simple default: **family**, with `driverId` fallback for customs.)
2. **Scout:** fold into the same prefer-other-CLI rule, or leave preferred
   Grok scouts alone?
3. **Repair existing custom Haiku JSON** as part of the slice, or a one-shot
   `alln models` repair after binary land?
4. Authorize implementation only when live panels are done — confirm.

## Rejection ledger (keep out)

| # | Rejected | Why |
| --- | --- | --- |
| R1 | Fixing catalog JSON or shipping a binary while panels run | Founder: no disruption guarantee |
| R2 | Hard fail when diversity can't be met | Degrade > block |
| R3 | New multi-objective seat optimizer / lab economics | Overcomplicates; 90% rule above |
| R4 | Calling id-dedup "diversity" in product copy | Lie |
| R5 | Putting Haiku in Mid | Founder: Flash/Compose trusted far more; Haiku = floor |
