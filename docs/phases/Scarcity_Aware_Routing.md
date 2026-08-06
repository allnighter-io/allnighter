# Scarcity-Aware Routing

Status: **Brainstorm — NOT ready for implementation. No slice authorized.**
Owner: unassigned (AllnighterCore `MenuCatalog` + `ModelCatalog` if it proceeds)
Created: 2026-08-05
Origin: Founder dogfood — OpenCode ships many cheap Economy/Balanced seats. If
the PM lead could pick economy vs balanced automatically, and prefer an
abundant seat when one is available, ALLN would stretch the paid bench further.
Competitor framing: "Standard compute offers auto smart routing. Even Claude
and Cursor do."

Companion packet under active build: [`OpenCode_Go_Capacity.md`](OpenCode_Go_Capacity.md).
This doc exists so routing can keep being reviewed and argued while that spike
ships — the two are coupled (routing wants Go capacity as an input; Go capacity
is not yet trustworthy enough to be one).

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations; code remains SSOT; archive this packet.

---

## 1. The reframe: cost is the wrong objective

Standard, Cursor, and Claude all ship auto-routing, so parity reasoning is
tempting. It imports the wrong objective function.

Those routers minimize **the vendor's** inference cost, inside **their own**
model family, with full eval access to those models, and the vendor eats the
loss when the router picks wrong. Every one of those conditions is false here:

| | Vendor router | ALLN |
| --- | --- | --- |
| Who pays | Vendor, per token | Founder, flat, **already spent** |
| Scope | One family they trained | Six-plus benches they do not control |
| Eval access | Full, offline, continuous | None shared across vendors |
| Cost of a wrong pick | Vendor's margin | Founder's wall-clock and scarce hours |

Money is not the lever. The subscriptions are bought whether ALLN routes or
not. What is genuinely scarce is **Opus/Claude hours behind a hard 5h wall**;
OpenCode economy seats are effectively unlimited by comparison.

> **Working hypothesis (revisable by founder ruling only):** the objective is
> not "spend less." It is **do not burn the scarce seat on work the abundant
> seat could have done** — and, symmetrically, never strand real work on a weak
> seat to protect a quota nobody is competing for.

This reframe kills the hardest sub-problem. Cost-minimizing routers must
predict token spend. Scarcity-aware routing does not: it needs observed
headroom (already acquired) and a strength ordinal (already authored). Neither
is a projection, which matters — see the no-estimates law in §3.

## 2. What already exists

More of this is built than the idea assumes. Naming it prevents rebuilding it.

| Capability | Where | State |
| --- | --- | --- |
| Strength ordinal per model | `catalog_overlay.json` → `caliber.strengthRank` | **Authored.** OpenCode seats span 55–92 |
| Capability tags | `caliber.capabilityTags` (`code`, `planner`, `review`, `fast`) | Authored |
| Substitution tiers / diversity families | `catalog_overlay.json` | Authored |
| Provenance-gated substitution | `VendorSubstitutionPolicy` | Shipped — swaps authorized by **selection provenance only** |
| Live per-seat headroom | `CapacityAcquisition`, `alln capacity` | Shipped (six PTY seats) |
| Runtime one-off seating | `TeamExplicitSeats`, `alln run --seat` | Shipped |
| Auto routing around a down CLI | SBDS default-model resolver | Shipped |

Observed strength ranks as authored today:

```text
model_opencode_qwen_38_max       92   code planner review
model_opencode_deepseek_v4_pro   90   code planner review
model_opencode_glm_5_2           88   code planner review
model_opencode_qwen_37_max       82   code planner review
model_opencode_minimax_m3        78   code planner review
model_opencode_qwen_37_plus      65   code fast
model_opencode_deepseek_v4_flash 55   code fast
```

**The actual gap is narrow:** `strengthRank` is consumed by `TeamAssembler` and
`TeamResolver` but never reaches `MenuCatalog`. A lead asked to "pick economy vs
balanced" can already *act* (`--seat`, `--model`) but cannot *see* strength or
headroom at the front door. It is a disclosure gap, not a mechanism gap.

Note also that ALLN has **no economy/balanced vocabulary**. `strengthRank` is an
ordinal with no tier boundaries, and the only occurrence of the word "economy"
in the catalog surface is one line of `MenuSelectionCopy` prose about Codex. Any
tier language is something this packet would have to introduce and defend.

## 3. Previously rejected — do not relitigate without a founder ruling

This is the "be careful" section. Each entry below was decided, with cause, and
a routing feature is exactly the shape of thing that quietly reintroduces them.

1. **Intent router is DEAD** (founder, 2026-07-20). ALLN discloses, resolves,
   and verifies; the **caller LLM chooses**. `Menu_Not_Router.md` is the ruling.
   A hidden in-CLI router that picks a model for you is the rejected design
   wearing a new hat.
2. **No standing routing rules** (founder, 2026-07-21). The old Claude-only
   rule was revoked precisely because carrying routing policy between tasks was
   wrong. **"Always prefer OpenCode when available" is that same rule with the
   vendor swapped** and would rot the same way.
3. **Sensors inform, never block** (founder, 2026-08-01). Readiness, capacity,
   health, and derived history inform selection but never veto an explicit
   request, and ALLN must **never silently reseat to another vendor** on sensor
   disagreement. Owner instruction wins; failure is reported, not prevented.
4. **No-estimates law.** Cost Advisor was moved out of RLC on this basis:
   observed facts only, never projections. Any router that scores candidates by
   predicted cost or predicted difficulty violates it. Affiliate/commercial
   signal never touches rankings.
5. **Team Lab is shut down** (founder, 2026-07-24). No roster ablation, seat
   economics studies, or necessity suites to "tune" routing weights.
6. **No API keys / BYOK.** Routing may only select among seats the founder
   already pays for.

Item 3 is the sharpest constraint and deserves restating: **delegation is not
the same as a sensor veto.** When the founder says "you are the PM, you pick,"
that is the owner authorizing the lead — permitted. A capacity reading silently
overriding a seat the founder named is the rejected behavior. The line is
*who authorized the choice*, not *how good the reading was*.

## 4. Live blocker: the abundance signal is not trustworthy yet

"Prefer OpenCode when available" needs an availability reading. The OpenCode Go
`/go` scrape is **0 of 14 days** into its qualification gate, and during review
on 2026-08-05 it was found emitting a partial sample with invented `0%` values
for two of three windows (fixed in `d5c23bdb`), plus asserting `authRequired`
from a substring a real dashboard inlines (fixed in `75a24e20`).

Routing on an unqualified sensor is the precise failure that gate exists to
prevent. **Availability-based preference is blocked behind
`OpenCode_Go_Capacity.md` promotion**, or must key off a signal other than the
scrape.

## 5. Candidate design — three layers, strictly ordered

Each layer is independently useful and independently killable. Do not build
layer N+1 before layer N has earned it.

### Layer 1 — Disclosure (small, consistent with every ruling above)

Surface `strengthRank`, `capabilityTags`, and live headroom in the menu
envelope so the caller LLM can choose well. No router, no policy, no new
semantics. "Smart routing" becomes an emergent property of a better-informed
lead who states its reasoning in the open.

This is the only layer that is obviously correct today. It re-uses the
front-door architecture rather than fighting it.

**Open:** does the menu envelope carry live capacity, or a staleness-stamped
snapshot? Capacity is per-invocation and costs PTY spawns; the menu must stay
fast. Leaning: last-observed with an explicit age, never a blocking probe.

### Layer 2 — Route down, verify, escalate (the genuinely new mechanism)

Send the slice to the balanced/economy seat, **gate the result** (filtered
tests, review, or the existing Auto-Fix gate), and re-run on the strong seat
when the gate fails.

This is the only proposal here that produces evidence instead of estimates. It
converts an unobservable prior — "is this task easy enough for the cheap seat?"
— into an observed posterior — "did the cheap seat actually do it?" It satisfies
the no-estimates law by construction, and the escalation path is what makes
routing *down* safe enough to be aggressive about.

Prior art in-repo: `alln run --try-fix` already runs a gated child fix chain.

**Open:** what counts as the gate when a slice has no filtered test? An
ungated route-down is just a silent downgrade. Candidate answer: no gate, no
route-down — fall back to the named seat.

**Open:** escalation must not double-charge the wall. If the economy seat burns
10 minutes and fails, the strong seat still has to do the work. Route-down pays
off only when the economy hit rate is high enough — that number is unknown and
Layer 2 must measure it before it is trusted.

### Layer 3 — Automatic selection (not proposed; recorded for completeness)

An in-CLI router that picks without a caller decision. Collides head-on with
rulings 1, 2, and 3. Recorded here only so a future reader can see it was
considered and why it is not the plan. Would require an explicit founder ruling
reversing `Menu_Not_Router.md`.

## 5a. First observed evidence — 2026-08-05

Three OpenCode seats were given real slices of `OpenCode_Go_Capacity.md` on the
same afternoon, each verified by the lead running the filtered suite itself
rather than trusting the seat's report. This is the only measured data this
packet has; it is three data points, not a benchmark.

| Seat | Rank | Slice | Wall | Outcome |
| --- | --- | --- | --- | --- |
| GLM-5.2 | 88 | Bound the URLSession transport | 138s | **Correct.** Stayed in scope, and added unprompted hardening that was right — dropped shared cookie storage and cache for a cookie-bearing request |
| DeepSeek V4 Pro | 90 | Enrich `ScrapeDiagnostics` for the promotion gate | 225s | **Subtly wrong.** Followed the repo's CryptoKit convention correctly, but shipped a whole-body content hash where the stated purpose needed a structural fingerprint. Passed its own green suite |
| Qwen 3.7 Plus | 65 | Replace that content hash with a structural fingerprint | 114s | **Correct.** Proved both required properties, and added a `<script nonce>` to the fixture unprompted to show nonces don't perturb it |

Three further slices were then routed the same way, with briefs deliberately
written to state the required **property** rather than the field to add:

| Seat | Rank | Slice | Wall | Outcome |
| --- | --- | --- | --- | --- |
| DeepSeek V4 Flash | 55 | Four drift gates proving the Go seat can never enter the PTY path | 50s | **Correct.** Gates verified by mutation — adding the seat to `benchSourceOrder` turns 4 red |
| Qwen 3.7 Max | 82 | Close the feature-OFF gate bypass | 212s | **Correct.** Put the decision in an Engine seam with no default parameter, forcing every call site to state it |
| MiniMax M3 | 78 | Move parser HTML into fixtures with honest provenance | 219s | **Correct.** Held the honesty constraint exactly — labelled the fixtures synthetic rather than dressing them as captures |

Six OpenCode slices, five correct on first pass, one subtly wrong. The single
failure was the one brief that named a field instead of a property.

**The uncomfortable finding: the economy seat succeeded where the strongest
seat failed.** Rank did not predict outcome on any of these six slices. The
cheapest seat on the bench (rank 55) produced the drift gates that now protect
the promotion boundary, in 50 seconds.

What separated them was **specification quality, not seat strength**. DeepSeek's
brief named the field to add and let it choose the mechanism; the wrong
mechanism satisfied every word of the brief and every assertion of its test.
Qwen's brief stated the required *property* — stable across value changes,
sensitive to shape changes — so there was no wrong answer that passed.

Provisional read, on far too little data to be a law:

> Route-down risk tracks how much **design judgment** the slice leaves to the
> seat, not how strong the seat is. A tightly-specified, property-gated slice is
> cheap to route down. A slice where the seat must *choose the mechanism* is
> where a strong seat earns its scarcity — and where a green suite is worth
> least.

This sharpens Layer 2 (§5) and directly answers open question 2 in a direction
nobody expected: the gate is not a safety net bolted onto route-down, it is the
thing that makes route-down work at all. Both defects caught today — the
partial-sample P0 and this content hash — passed green suites written by the
seat that introduced them.

Caveat this hard: n=6, one slice each, all in one subsystem, all specified by
the same lead, all reviewed by that same lead. Every "correct" verdict is the
lead's own judgement of a brief the lead wrote — a real confound, and the exact
reason SAR-S03 must measure hit rate against an independent gate rather than
against the router's author. It is enough to justify measuring. It is not
enough to route on.

## 6. Inference bans (draft)

| Junction | Possible bad inference | Ban |
| --- | --- | --- |
| high `strengthRank` → good at this task | Ordinal becomes a general competence claim | Rank orders seats within a craft; it is not a task-fit prediction |
| headroom → permission to reseat | Sensor silently overrides a named seat | Owner-named seat is never reseated by a reading (ruling 3) |
| abundant vendor → default vendor | Standing routing rule returns | No "always X" rule survives past one task (ruling 2) |
| economy seat succeeded once → economy is fine here | Anecdote becomes policy | Route-down needs a per-slice gate, every time |
| unqualified Go scrape → availability | Routes on a sensor known to have lied | Blocked behind Go qualification (§4) |
| cheaper seat → better outcome | Cost framing re-enters | Objective is scarcity preservation, not spend (§1) |

## 7. What would make this real

Not authorized — this is the shape a packet would take if the founder green-lit
it.

- **SAR-S01** — menu discloses `strengthRank` + capability tags. Fixture test
  that the menu envelope carries what the lead needs to choose.
- **SAR-S02** — menu discloses last-observed headroom with an explicit age
  stamp; never a blocking probe.
- **SAR-S03** — route-down-verify-escalate behind an explicit flag, gated,
  with a ledger recording economy-seat hit rate. Measurement before trust.
- **SAR-S04** — tier vocabulary (economy / balanced / strong), only if S01–S03
  prove the ordinal alone is insufficient. Naming a tier is a product claim.

## 8. Open questions for the founder

1. **Is Layer 1 enough?** If disclosure lets a lead route well, Layers 2–3 may
   never need to exist. Cheapest possible test of the whole idea.
2. **Is route-down worth an escalation tax?** Layer 2 only pays if the economy
   hit rate is high. Nobody knows that number yet — S03 measures it, and the
   honest answer may be "no."
3. **Does tier vocabulary earn its keep,** or is `strengthRank` + capability
   tags sufficient? Introducing "Economy/Balanced" is a durable product claim
   about models ALLN does not control and cannot evaluate.

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| Smart routing, economy vs balanced, auto model pick | This packet + rejected list §3 |
| Front door / who chooses a model | `Menu_Not_Router.md` — caller LLM chooses; router is dead |
| Capacity as a routing input | `OpenCode_Go_Capacity.md` (unqualified) + `Quota_Aware_Bench_Continuity.md` |
| Substitution when a seat is parked | Code SSOT `VendorSubstitutionPolicy.swift` |
