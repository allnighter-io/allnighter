# Seating — Tier + CLI Diversity (hardened)

Status: **Hardened — REVIEW ONLY for code slices. Not authorized to
implement S1–S3 while live panels may still be running.** S00 (disable
poisoned Haiku) is a roster-only mitigation and is allowed.
Owner: `TeamResolver.swift` + `ModelCatalog.swift` (staffing law).
Updated: 2026-07-25
Spec Review: run `927B8CD4-A99A-4B68-AE25-262BF52BB338` — Min panel pinned to
Opus / Cursor Sol / Cursor Grok + Fable lead (`custom_code_spec_review_min_cursor`).
Evidence bugs: `code_spec_review_max` `3B00A1A7`, `code_spec_review_min` `DCE9AE48`.

## Founder intent (product sentence)

When you pay for a panel, you get **different minds** — and never a cheap mind
on a hard seat. Three product words (premium / mid / low) map to the existing
caliber bands; within a band, prefer a CLI/family the crew does not already
have. Degrade, don't fail. Haiku is **floor**, not mid.

## Product value

Blind multi-model review only works if seats are different minds. A Claude×N
crew is theater. Unevaluated customs must not inherit flagship rank.

## Trusted workflow slice

Staffing only: how `TeamResolver` picks a model for a capability-only row, and
what `models add` / `capabilities()` stamp for customs. No team redesign, no
Spec Review prompt changes, no GUI.

## Non-goals

- Wiring `SubstitutionTier` / `DefaultModelSettings` into the resolver (live
  shelf has Fable Unassigned and Composer-60 in Flagship — would regress Leads).
- Renaming caliber bands to Flagship/Balanced/Fast in code.
- Light-name word lists (`haiku`/`flash`/`mini`/…).
- New `tier:` / `minTier:` on `TeamWorkerSpec`.
- Scout / triangulate diversity in the bugfix slices (deferred).
- Shipping a binary or mutating catalog JSON while panels are live (except S00).

---

## Bugs (verified)

| # | Bug | Evidence |
| --- | --- | --- |
| **A** | `createCustom` persists donor flagship capabilities/rank. Custom Haiku sits at rank **100** with Fable's tags (incl. `.security` / `.design`) — wins every capability-only first pick after Lead reserves Fable. | On-disk record; `ModelCatalog.swift:373` |
| **B** | Family diversity is priority 4 under `strengthRank` in `strongest()` — unreachable on a real bench (distinct ranks). Id-dedup claims "diverse" for Haiku+Opus+Sonnet+Fable. | `TeamResolver.swift:355-372`; tests only cover exact ties |
| **C** | `modelFamily` defaults to `modelId` for customs — custom Haiku is its own "family," not `claude`. | `ModelCatalog.swift:51-72` |
| **D** | Scout resolves after rows; neither contributes to nor consults diversity sets. | Deferred — preferred-identity scout; Spec Review unaffected |
| **E** | Triangulate rows `continue` before diversity updates — invisible to family tracking. | `TeamResolver.swift:190`; Signal teams; deferred with D |
| **F** | Five built-ins lack `builtInCapabilities` entries and inherit donor profiles (`agy_sonnet` enabled live). Same class as A. | Proof Planner, live bench |

Also: `isLighterVariant` substring `"mini"` already misfires on **"ge*mini*"** (−15 on Gemini). Delete it with the unrated-model law.

**Hard dependency:** diversity-without-rank leaves Haiku on seat #2 (still Flagship band). Rank fix **before or with** diversity fix — never diversity alone.

---

## Premise correction (Spec Review gem)

Do **not** treat `SubstitutionTier` as the seating dial. Live
`default_model_settings.json` put Composer (rank 60) in Flagship and left
`model_fable` Unassigned. Tier in *this* packet means **caliber band from
`strengthRank`**. Founder vocabulary map (doc only):

| Founder word | Band |
| --- | --- |
| Premium / high | ≥95 and 85–94 |
| Mid | 70–84 |
| Low / floor | <70 |

*The resolver never reads `DefaultModelSettings`.* Reconciling shelf↔rank is
follow-up **SEAT-F1**, not this bugfix.

---

## Seating law (working hypothesis — founder-revisable only)

Applies only when `preferredModelId == nil` and `homeDriver == nil`
(preferred / home-driver affinity unchanged).

Candidates sort by:

1. **caliber band** — ≥95 / 85–94 / 70–84 / floor *(never crossed)*
2. **preferred capability tags** *(unchanged)*
3. **family not yet on the crew** — `ModelCatalog.modelFamily`
4. **driver not yet on the crew** — `driverId` (wall-clock: some drivers
   `maxConcurrentSpawns: 1`)
5. **strengthRank** descending
6. **id** ascending

Steps 3–4 never filter. When every family is used, fall through to rank.
**Never block a run for diversity.**

**Exclusion filter (half the fix):** today's id-exclusion shrinks the pool
*before* `strongest()` with no band awareness — on a thin Flagship pool that
can leave only Haiku visible. Filter may apply only when the filtered pool
still retains a best-band candidate; otherwise keep the full best-band set.

**Degrade precedence (D7):** unused-family Balanced+ → reuse any Balanced+ →
floor with warning → never block.

**Unrated-model law:** no `builtInCapabilities` entry → inherit driver's
**tags** only, **rank 40** (floor), regardless of persisted record. Delete
`isLighterVariant`. `createCustom` persists empty capabilities (not donor
profile). Disk Haiku JSON becomes inert — no repair CLI / migration.

**Custom family:** single-vendor drivers map via `hostFamily(driverId)`
(`claude_code`→claude, `codex`→gpt, `grok`→grok, `kimi`→kimi); multi-vendor
routers use `driver:<id>`. No name-sniffing.

**Snapshot:** capabilities once per `resolve()` — no disk I/O inside the sort
comparator.

### Named consequences (not regressions)

- Sonnet 5 often never seats on a full bench once Lead claimed `claude`.
- Max can show grok twice + grok scout once every family is used.
- Balanced-band novelty can seat rank-75 over rank-84.

---

## Truth owners

| Truth | Owner |
| --- | --- |
| Who sits where | `TeamResolver.selectModel` / `strongest()` |
| Strength / band | `ModelCatalog.builtInCapabilities.strengthRank` + `caliberBand` (**move** thresholds from `TeamResolver.swift:352` into `ModelCatalog`) |
| Family | `ModelCatalog.modelFamily` (+ driver fallback) |
| User Auto shelf | `DefaultModelSettings` — **not read by seating** |

---

## Slice plan

| Slice | What | When |
| --- | --- | --- |
| **S00** | `alln models disable custom_claude_code_claude_haiku_45` — roster only, reversible | **Now** (zero code) |
| **S1** | Catalog honesty: empty caps on `createCustom`; unrated law rank 40; delete `isLighterVariant`; fill Bug F built-in entries + drift gate `builtIns ⊆ builtInCapabilities.keys`; `models add` discloses Unrated | After panels drain |
| **S2** | Resolver law: family+driver above rank within band; band-aware exclusion filter; degrade warnings; `modelFamily` fallback; snapshot caps; move `caliberBand` | After S1 (never alone) |
| **S3** | Observability: optional `seats[]` `{modelId, family, driverId, skillId, stage, reason}` on `RunDryRunJSON`; persist resolved-against bench on the run snapshot | After bugfix |
| **Follow-ups** | SEAT-F1 shelf reconcile; scout+triangulate diversity (D/E); `gemini_pro` vs Flash rank; capabilities-edit CLI for customs | Separate |

## Works Test (golden — fuzzy predicates rejected)

Fixture `FULL` = fresh built-ins + real custom-Haiku JSON (rank 100, 7 tags)
registered as a test fixture. Hand-traced expected tuples — any mismatch at
implementation is a **finding**, not a typo to paper over.

| # | Case | Expect |
| --- | --- | --- |
| W1 | Min / FULL after fix | Lead `model_fable`; answers exactly `[model_chatgpt, model_cursor_grok_45, model_kimi_k3]`; custom Haiku **absent** |
| W2 | Same fixture through **pre-fix** comparator | `[fable, custom_haiku, chatgpt, opus]` (reproduction of `DCE9AE48` class) — keep as comment |
| W3 | Max / FULL | No family majority of answer+review; Haiku absent; scout `model_grok` (preferred) |
| W4 | `createCustom(claude_code, …)` | Persisted tags empty; `capabilities(id).strengthRank == 40` |
| W5 | Thin bench `[model_fable]` only | Runnable; warning ok; no block |
| W6 | Row with `preferredModelId` on a used family | Still gets preferred — diversity does not override |
| W7 | Drift gate: `BuiltInTeams` × `defaultFreshModels()` | Distinct-family floor per team; fails if production ranks make family dead again |

Until S3, live observation = post-start `team status` workerIds (no dry-run
seat list today).

## Decided (was open questions)

| Q | Ruling |
| --- | --- |
| Diversity unit | Family primary, driver secondary |
| Scout | Deferred with Bug E |
| Poisoned Haiku JSON | Read-path unrated law (inert); S00 disable now; no repair CLI |
| Timing | S00 now; S1–S3 after panels drain |

## Rejection ledger

| # | Rejected | Why |
| --- | --- | --- |
| R1 | Fix binary/catalog mid-flight | Founder: no disruption |
| R2 | Hard-fail when diversity unmet | Degrade > block |
| R3 | Seat optimizer / lab economics | Overcomplicates |
| R4 | Calling id-dedup "diversity" | Lie |
| R5 | Haiku as Mid | Founder: Flash/Compose ≫ Haiku; Haiku = floor |
| R6 | Wire `SubstitutionTier` into resolver | Live shelf would regress Leads / seat junk Flagship |
| R7 | Light-name word list | Fails open/closed wrongly; Gemini mini misfire |
| R8 | Collapse/rename 4 bands → 3 Flagship/Balanced/Fast in code | Rename theater |
| R9 | `tier:` on `TeamWorkerSpec` | Schema churn |
| R10 | `alln models repair` / disk migration | Read-path makes record inert |
| R11 | Scout diversity this packet | Deferred |
| R12 | Diversity slice without rank fix | Haiku still takes seat #2 |
| R13 | Fuzzy Works Tests ("≥2 families") | Pass on Bug A alone — don't prove B |
| R14 | `seats[]` inside S1/S2 | Right feature, wrong slice → S3 |
| R15 | Non-light customs default rank 80 | Re-creates Bug A class |

## Impact (when S1–S3 authorized)

| Surface | Impact |
| --- | --- |
| Mac / iOS | None required |
| CLI contract | None for S1/S2; S3 additive `seats[]` |
| In-flight runs | S1–S3 wait for panels; S00 roster-only |

## Done when

- [x] Spec Review Min (Cursor panel) completed — `927B8CD4…`
- [x] Doc hardened from synthesis (this revision)
- [x] S00 Haiku disabled on this machine (`custom_claude_code_claude_haiku_45` enabled=false)
- [ ] Founder OK on law + rejects (esp. R6 / unrated-40 / S1→S2 order)
- [ ] S1–S3 authorized after panels drain
- [ ] W1–W7 green; contract bump only if S3 ships
