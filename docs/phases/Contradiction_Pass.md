# Contradiction Pass — disagreement as a product, not a defect

Status: **DRAFT — NOT AUTHORIZED.** Founder sequencing (2026-07-24): Code Red
(archived complete) first; this packet needs fresh founder scoping before start.
Owner: `docs/operations/Spec_Review.md` mechanism + team-run synthesis contract
(finding schema, synthesizer/gatekeeper, defensive seats)
Updated: 2026-07-24

Extends [`docs/operations/Spec_Review.md`](../operations/Spec_Review.md) (living hero-loop SSOT). That doc is
**not reopened**: §5's blind fan-out law stays inviolable, §2's impact ledger
stays the product, and §4's refutation gate stays the truth rule. This doc adds
one thing those sections currently leave to synthesizer judgment — **mechanical
detection of disagreement** — and one bounded seat that acts on it.

> **"Laws" in this doc are working hypotheses.** They are revisable by founder
> ruling only — never by an implementing agent mid-slice.

---

## Founder intent

Max currently means *more bodies with tweaked roles*. That is a quantity
difference the user cannot see in the output. Give Max a **structural**
difference: it resolves the disagreements the panel produced, instead of only
producing more of them. And do it with **fixed rounds** — loops burn unbounded
tokens for marginal benefit.

## The problem with Max as it stands

`docs/operations/Spec_Review.md` §2 already says the right thing:

> **Open questions** — genuine disagreements between workers... The synthesizer
> must NOT average away a sharp disagreement; homogenized synthesis is the main
> way this loop dies.

But §5 also names the synthesizer as **the contamination point** — "it reads
everything and is just as persuadable." Today, whether a disagreement reaches the
human depends entirely on that persuadable component *noticing and choosing to
surface it*. There is no mechanism that makes homogenization detectable. The
documented failure mode has no gate.

Meanwhile Max adds seats. More seats produce more findings, and more findings
produce more opportunity for exactly that silent averaging.

---

## Evidence

| Finding | Source | Bearing |
| --- | --- | --- |
| Repeated sampling scales *coverage* log-linearly over four orders of magnitude, but selection is the bottleneck: majority voting and reward models "plateau after a few hundred samples." Gains convert to accuracy only where a verifier exists. | [Large Language Monkeys](https://arxiv.org/abs/2407.21787) | **The core argument.** Max buys coverage today and ships no selector. Adding seats without a selection mechanism is the configuration the literature says underperforms its spend. |
| Intrinsic self-correction — a model revising its own answer with **no external feedback** — often fails and "at times, performance even degrades." | [Huang et al., ICLR 2024](https://arxiv.org/abs/2310.01798) | Hard design constraint: the resolution seat must never be "think again." It must receive external input — the opposing claim and its evidence. Adjudication, not introspection. |
| Across 5 multi-agent-debate methods × 9 benchmarks × 4 models, **no** method beat chain-of-thought in more than 20% of 36 configurations, while consuming far more tokens; self-consistency beat both. **But model heterogeneity consistently improved MAD.** | [Stop Overvaluing Multi-Agent Debate](https://arxiv.org/abs/2502.08788) | Two conclusions. (1) External support for `docs/operations/Spec_Review.md` §5's ban on discussion rounds — debate rounds are the losing lever. (2) Cross-vendor spread is the empirically supported lever, which is what `alln` already sells. |
| Self-consistency gains plateau early while token cost scales nearly linearly with sample count; at high counts accuracy can decline. | [Self-Consistency Is Losing Its Edge](https://arxiv.org/abs/2511.00751) | Direct support for the founder's fixed-rounds ruling over an adaptive loop. |
| Annotator disagreement is not noise to be adjudicated away — in interpretative tasks it reflects genuine ambiguity, underspecified guidelines, or alternative valid readings. | [Human label variation / perspectivist NLP](https://arxiv.org/html/2601.09065v2) | **The most transferable idea here.** When blind reviewers disagree about a spec, the leading hypothesis is that *the spec is ambiguous* — a defect in the artifact, not an error by a model. |
| GPT-4 "exhibits a significant degree of self-preference bias"; the cause appears to be familiarity — LLMs rate low-perplexity text far above human evaluators whether or not they generated it. Position bias is separately documented and is mitigable by rearranging option order. | [Self-Preference Bias in LLM-as-a-Judge](https://arxiv.org/abs/2410.21819) (abstract read 2026-07-24) | The resolver must not have authored either claim, and claim order must be randomised. Backs the existing source-blind synthesis rule. ⚠️ The widely quoted "−38% to +90% on ArenaHard" range is from a *different* paper (arXiv:2604.22891) — do not attribute it here. |
| Heterogeneous ensembles contribute more than clones — but Self-MoA (one strong model) beat mixed MoA by 6.6% on AlpacaEval 2.0. | [Rethinking Mixture-of-Agents](https://arxiv.org/abs/2502.00674) | Honest caveat: cross-vendor spread is not a free lunch. This is precisely what `docs/operations/Spec_Review.md` §7 "measure the moat" exists to settle with our own telemetry. |

**What the evidence does not say:** none of this tested spec review, structured
findings, or blind panels over a real repo. It supports the *shape* — fixed
rounds, external evidence, heterogeneous sources, an explicit selector — not the
specific numbers. Calibration is CP-S01's job.

---

## The mechanism

### Step 1 — Anchors make agreement and conflict computable (all tiers, zero model cost)

Every finding already ships schema-backed (`docs/operations/Spec_Review.md` §6). Add two fields:

- **`anchor`** — what the claim is *about*, in a comparable form: spec section
  id, `file:line`, requirement id. Not prose.
- **`stance`** — the direction of the claim (`assert` / `deny`) plus the existing
  severity.

Then group by anchor. This is a join, not an inference — **no worker, no
tokens**:

- same anchor, same direction → **agreement**. This is `docs/operations/Spec_Review.md` §2
  co-attribution, computed instead of judged.
- same anchor, opposing direction → **contradiction**.

### Step 2 — Classify (all tiers)

| Class | What it means | Where it goes |
| --- | --- | --- |
| **False conflict** | Different scope or assumptions; both claims true as stated. | **A finding in its own right: the spec is ambiguous at this anchor.** New product output — the artifact defect that caused the disagreement. |
| **Factual conflict** | One side is checkable against the repo, the test, or the spec text. | Resolvable by evidence. |
| **Judgment conflict** | Genuinely differing priorities; no fact settles it. | **Open question to the human, both cases stated.** Never forced to a winner. Already `docs/operations/Spec_Review.md` §2. |

### Step 3 — Resolution seat (Max)

A synthesis-stage seat — the same architectural class as Refuter and Steelman,
which `docs/operations/Spec_Review.md` §3 already places "inside synthesis, not the fan-out."
**This is why it does not violate the blind fan-out law**: fan-out workers still
never see each other. The resolver is not a worker; it is a gatekeeper input.

- Receives both claims and their cited evidence — external input, per Huang et al.
- Authored neither claim; different vendor where available.
- Claim order randomised (position bias).
- Prompted to classify and adjudicate, **not** to find a middle position.
- Runs **only** where both sides already survived the existing refutation gate
  (§4). A claim killed by a Refuter is not a contradiction; it is a rejected
  finding. This ordering is what bounds the work.

### Step 4 — One round. Never two.

If the resolution seat does not settle a conflict, it escalates to the human as
an open question. There is no third pass, no re-resolution, no adaptive loop.

---

## Founder's two questions, answered

### "Max-only, or default when the contradiction is big?"

**Split by cost, not by importance.** Detection is free; only the resolution
round spends.

| Capability | Min | Default | Max |
| --- | :---: | :---: | :---: |
| Anchored findings | ✅ | ✅ | ✅ |
| Mechanical agreement / contradiction detection | ✅ | ✅ | ✅ |
| Contradictions surfaced in the ledger + synthesizer reasoning | ✅ | ✅ | ✅ |
| False-conflict → "spec is ambiguous here" finding | ✅ | ✅ | ✅ |
| **Resolution seat (spends a worker call)** | ✗ | ✗ (escalates) | ✅ |

**The founder's own point is the default tier, and it is right:** a contradiction
detected in round 1 can be reasoned about and summarised by the synthesizer
without any second round. What changes at Default is not that contradictions get
handled — it is that the synthesizer can no longer *quietly not notice one*. The
join happens whether or not the synthesizer is paying attention.

**A big contradiction at Default does not silently buy a resolution round.**
`docs/workflows/Product_Vocabulary.md` §Routing law: escalation may *recommend* Max but never
silently switches teams. So a `blocking`-severity contradiction that survives the
refutation gate on both sides emits `escalationRecommended` — copy writes itself
from the existing vocabulary:

> *"Two reviewers blocking-disagree on §4 and both survived refutation. Rerun as
> Spec Review Max to resolve?"*

That is the honest version of "Max earns its name": the user is told exactly what
Max would do and why, at the moment it would matter.

### "Fixed rounds?"

Yes — ruled, and the literature agrees. Exactly one resolution round, capped at
**K conflicts per run** (K set in CP-S01 from observed data, not guessed). Cap
hit → remaining conflicts listed as open questions, never silently dropped. The
`hardened: partial` mechanism in §4 already covers this shape.

---

## Laws (working hypotheses — founder-revisable only)

1. **Detection is mechanical and unconditional.** Agreement and contradiction are
   computed from anchors on every tier. No model decides whether a disagreement
   exists.
2. **The blind fan-out law is untouched.** Resolution is a synthesis-stage seat.
   No worker ever sees another worker's finding. A "discussion round" remains
   forbidden — `docs/operations/Spec_Review.md` §5, now with external support.
3. **The resolver adjudicates; it never averages.** A synthesised middle position
   that neither worker proposed is a failed resolution, recorded as such.
4. **Judgment conflicts go to the human unresolved.** Forcing a winner on a
   priority call is the homogenized-synthesis failure mode wearing a gate.
5. **The resolver authored neither claim, and order is randomised.**
6. **One round. Never a third pass.** Unsettled → open question.
7. **No cost projections.** Per the standing no-estimates law, this feature emits
   *observed* counts (conflicts detected, resolved, escalated, extra worker calls
   made) and never an estimate of what a run will cost.
8. **`alln` never rates itself.** The resolution seat judges findings, never the
   quality of the run or of Allnighter.

---

## Slices

| Slice | Deliverable |
| --- | --- |
| **CP-S00 — Anchors and stance in the finding schema** | Add `anchor` + `stance` to the structured finding contract; make every built-in lens prompt emit them. No behaviour change, no extra calls. Gate: a finding without a resolvable anchor fails validation. |
| **CP-S01 — Measure, then calibrate (kill gate)** | Run the anchored schema over real dogfood runs. Publish: what share of findings pair on an anchor at all; what share of pairs are contradictions; the false/factual/judgment split. **Kill criteria — any one of these archives the doc:** pairing rate so low the join is empty; contradiction rate so high the anchor is too coarse to be meaningful; or the split showing essentially no judgment/false conflicts, i.e. nothing a human needed. Set K here from observed counts. |
| **CP-S02 — Ledger surfacing (all tiers)** | Contradictions and computed co-attribution become first-class impact-ledger sections. False conflicts become spec-ambiguity findings. Vitals gain a disagreement rate alongside the existing duplication rate. Still zero extra worker calls. |
| **CP-S03 — Resolution seat (Max) + Default escalation** | The synthesis-stage resolver, gated behind both-sides-survived-refutation, capped at K, order-randomised, resolver-authored-neither. Default tier emits `escalationRecommended` instead of spending. |
| **CP-S04 — Generalise beyond Spec Review** | Bug Hunt and other panel families adopt anchors (`file:line`) and inherit detection. Only if CP-S01/S03 proved value on Spec Review first. |

## Works Test

```bash
# CP-S00/S02 — mechanical, no provider spend
swift test --package-path Packages/AllnighterCore --filter FindingAnchorTests
swift test --package-path Packages/AllnighterCore --filter ContradictionJoinTests
#   fixtures: opposing stances on one anchor -> contradiction
#             identical stances on one anchor -> co-attribution
#             unanchored finding             -> validation failure
#             resolver assigned a claim it authored -> assignment failure
#             K exceeded -> remaining conflicts listed, none dropped

# CP-S03 — Max resolves, Default escalates and does NOT spend
$B run "<spec>" --team code_spec_review_max --json   # resolution entries present
$B run "<spec>" --team code_spec_review --json       # escalationRecommended; zero resolver calls

scripts/check.sh
```

**Proof note:** CP-S01 cannot be satisfied mechanically. It requires real
multi-model runs over real specs — dogfood on Allnighter's own phase docs, as
`docs/operations/Spec_Review.md` §8 already prescribes. A fixture-only pass proves the join
works, not that disagreement is worth surfacing.

## Done when

- Every finding carries a machine-comparable anchor; unanchored findings fail.
- Contradiction and co-attribution are computed, not judged, on every tier.
- The observed contradiction split from real runs is published in this doc —
  including a null result that kills the resolution seat.
- Max resolves within one bounded round; Default escalates without spending.
- No judgment conflict is ever auto-resolved.

## Open questions

1. **Anchor granularity — the whole thing hinges on this.** Too coarse and every
   finding "conflicts"; too fine and nothing pairs. Recommendation: start at spec
   section / `file:line`, measure the pairing rate in CP-S01, and treat a bad
   rate as a calibration result rather than a reason to hand-tune upward.
2. **Does the resolver replace or precede the Refuter?** Recommendation: precede
   nothing — Refuter runs first as today, resolution runs only on survivors. That
   ordering is what makes the cost bounded and reuses a shipped mechanism.
3. **Is "false conflict → the spec is ambiguous" a finding the synthesizer
   accepts on its own authority, or does it face the refutation gate like any
   other material finding?** Recommendation: gate it. It is a material claim
   about the artifact and should survive attack like the rest.
4. **Does the Default-tier escalation prompt count as a recommendation `alln`
   is allowed to make?** It names a team, which brushes against the no-router
   posture. Recommendation: allowed — it is the existing `escalationRecommended`
   mechanism from `docs/workflows/Product_Vocabulary.md`, triggered by a *mechanical* condition
   rather than by inferring intent from prose. Founder ruling wanted.
5. **Relationship to the parked Buzz / judgment layer.** Judgment conflicts are
   adjacent to that exploration. Flagged, deliberately not merged — nothing here
   depends on Buzz being built.

## Routing

| Work | Read first |
| --- | --- |
| Hero-loop positioning, lenses, impact ledger, blind fan-out law, refutation gate | `docs/operations/Spec_Review.md` |
| Depth tiers, escalation law, what Min/Default/Max mean | `docs/workflows/Product_Vocabulary.md` |
| Seat economics, roster ablation, necessity suites | Team Lab is SHUT DOWN (founder, 2026-07-24); archived `Team_Lab_Composition_And_Seat_Economics.md` has the historical spec |
| Menu disclosure of tiers and families | `Menu_Relations.md` |
