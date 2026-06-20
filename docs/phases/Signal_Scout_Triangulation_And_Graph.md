# Signal Scout, Triangulation, And The Signal Graph

Status: Draft backend/product spec — the next big upgrade to the Signal craft
Owner: Signal lane (Core team-run substrate + TeamResolver + a new Signal Graph store)
Updated: 2026-06-19

## Authority

Read with:

- `docs/strategy/Allnighter_Public_Signal_Wedge.md` (why Signal is the wedge; the Grok/X premise)
- `docs/phases/Team_Run_Floor.md` (owns the `SignalInsight` / `SignalReceipt` contract and the Floor projection)
- `docs/phases/Team_Delegation_Surface.md` (owns Signal as a team family)
- `docs/phases/Model_Catalog_And_Bench_Roster.md` (owns model lane tags + driver manifests)
- `docs/phases/Language_Cutover.md` (Signal is the 4th craft; `WorkLane.signal`, `TeamOutputKind.insight`)

This doc owns three things the others do not: (1) the **scout → triangulation** run
shape for Signal, (2) **role-aware, distinct-driver model assignment** so a signal
is read by *many minds*, not one, and (3) the **Signal Graph** — the durable
cross-signal memory that makes every answer better than the last without anyone
asking.

## Founder Intent

Raw request:

```text
If I paste a link to X and ask "what does this mean for my project / how does
this apply" I expect an answer. I literally want to know the fucking answer
right now. The insane unlock is that the answers should get better and better
over time without asking. Every signal run should have an internal researcher /
analyst that compares this signal to prior signals to find the true AHA given
the Signal Graph Store.

Also: a signal run should NOT just be Grok. We use Grok because it has X API
access. A much better process: Grok (the lead) first distills the info from X
WITHOUT passing judgement — just the raw info dump — then passes it to all the
CLI workers (one is Grok, the others are other CLIs) so we get triangulation.
We are missing that today and it will immediately make signal runs much more
valuable for finding unique ideas.

This could be insanely valuable — not just for developers working on projects
but for online influencers too, because we can surface better ideas. Their
"repo" might just be the content they write about and how well their posts do.
```

Product value:

```text
The intersection of 10+ signals over time is where the gems are. One X post is
a tip. Ten X posts cross-referenced against each other AND against your own
corpus is a thesis nobody else can see. Allnighter is the only place that holds
the signal stream, the corpus (code OR content), and a fleet of CLI minds — so
it is the only thing that can connect them and keep connecting them as the pile
grows.
```

Trusted workflow slice:

```text
1. User pastes an X link into a Project and asks "how does this apply to us?"
2. Grok (X-capable) distills the post + its thread/context into a NEUTRAL source
   packet — raw facts, quotes, who/when — and passes no judgement.
3. That one packet fans out to several DIFFERENT CLIs (Claude, Codex, Gemini,
   Grok) who each interpret it independently → triangulation.
4. An analyst compares this signal to prior signals in the Signal Graph and
   surfaces the cross-signal AHA.
5. A skeptic pressure-tests; the Insight Writer decides.
6. The user gets a decisive answer RIGHT NOW — plus an "in light of your last N
   signals…" section that is richer than it could have been a month ago.
7. The signal + packet + interpretations + edges are written to the Signal Graph
   so the next run is smarter.
```

Non-goals:

- Do NOT hold back the answer to the user's question waiting for a cluster to
  form. The single question is always answered now. The cross-signal AHA is
  **additive enrichment**, never a gate. (This reverses an earlier proposal.)
- No social-listening dashboard, X API proxy/reseller, scheduler, or auto-poster.
- No private/authenticated X access claims. Public sources only.
- Not a new run loop. This rides the existing `CatalogRunCoordinator` substrate.

## Current State

Useful substrate:

- `WorkLane.signal` + `TeamOutputKind.insight` are live (`TeamCatalog.swift`).
- Two built-in teams in `BuiltInTeams.swift`: `signalPostToProject`,
  `signalWhatToBuildNext`.
- Signal skills in `SkillCatalog.swift`: `signal_source_reader`,
  `signal_landscape_scanner`, `signal_project_fit`, `signal_product_ideas`,
  `signal_skeptic`, and the lead `insight_writer`.
- `model_grok` carries `laneTags: [.code, .copy, .signal]` and is web-aware
  (`ModelCatalog.swift`); its driver manifest runs `grok -p … -m … --output-format plain`.
- `SignalInsight` / `SignalReceipt` typed output + `SignalInsightParser`
  (`SignalInsight.swift`); surfaced via `FloorReturn.kind = .insight`.
- Run substrate `CatalogRunCoordinator.run()`: answer (blind parallel) → review
  (sees answers) → plan (the Lead synthesizes).

Current gaps (the whole reason for this doc):

1. **No scout → fan-out.** `signalPostToProject` runs `signal_source_reader`,
   `signal_project_fit`, `signal_product_ideas` as **blind parallel** answer
   workers. The interpreters do NOT receive the source reader's distillation —
   they each re-read the raw input in isolation. There is no neutral source
   packet that the interpreters share.
2. **One mind, not many.** Every worker resolves through `fallbackPolicy:
   .strongestReady`, which tends to pick **one** model for the whole team
   (usually Grok). There is no policy that says "interpret this with *distinct*
   drivers." Triangulation is the headline value and it does not exist yet.
3. **No memory.** Each run is one-shot against the raw input. There is no
   durable store of prior signals and no analyst that mines the intersection.
   Answers cannot get better over time because nothing persists to learn from.
4. **Corpus is code-shaped.** Grounding assumes a Project that is a code repo.
   A creator's "repo" (their content + post performance) has no first-class home.

Existing truth owners that change:

| Concern | Owner today | Change |
| Run staging | `CatalogRunCoordinator` | add a scout pre-stage feeding interpreters |
| Worker→model assignment | `TeamResolver` (`.strongestReady`) | add scout-pin + distinct-driver triangulation policy |
| Signal output | `SignalInsight` / `insight_writer` | += cross-signal section + triangulation spread |
| Durable signal memory | *(none)* | new **Signal Graph** store |

## Decision — the upgraded Signal run shape

A Signal run becomes four ordered stages on the existing substrate. The new
stage 0 (Scout) and the distinct-driver fan-out at stage 1 are the core change.

```text
Stage 0  SCOUT (one X-capable model — Grok today)
         Distill the source. NO judgement. Output = neutral SignalSourcePacket
         (what was said, by whom, when; exact quotes; thread/context; named
         related public posts). A durable artifact.

Stage 1  TRIANGULATE (N interpreters, DISTINCT drivers)
         The same packet fans out to several different CLIs. Each runs
         project-fit + product-ideas independently. Diversity of minds is the
         product. Includes the Analyst (stage 1b) which reads the Signal Graph.

Stage 1b ANALYST (cross-signal AHA)
         Query the Signal Graph for prior related signals; surface the
         intersection ("this is the 4th signal this month pointing at X").
         Additive — never blocks the answer.

Stage 2  SKEPTIC (review)
         Fresh / stale / saturated / not-a-fit. Unchanged role, now also sees
         the triangulation spread and the analyst's links.

Stage 3  INSIGHT WRITER (the Lead, decides)
         Answer the user's question NOW. Append: triangulation spread (who
         agreed / who diverged) and "in light of your prior signals…".
         Writes the signal + packet + edges back to the Signal Graph.
```

Mapping to substrate: Scout is a new pre-answer dependency stage whose artifact
is injected into every interpreter's context (interpreters stay parallel, but
their input now includes the packet instead of the raw paste). Analyst is an
answer worker with read access to the Signal Graph. Skeptic stays a review
worker. Insight Writer stays the Lead (`planWriter`) and gains a write-back.

## Contract — SignalSourcePacket

The neutral output of the Scout. Facts only; inference is the interpreters' job.

```text
SignalSourcePacket
  id
  capturedAt                 (ISO-8601; uncertain allowed, never invented)
  sourceKind                 (xPost | xThread | article | releaseNote | repo | other)
  primary { url, author, postedAt, verbatimQuotes[], mediaDescribed[] }
  threadContext[]            (surrounding posts, replies, quote-posts — verbatim)
  relatedPublicPosts[]       (Grok-found neighbors: url, author, oneLineGist)
  observedFacts[]            (literal, attributable)
  unverifiable[]             (what could NOT be confirmed — timestamps, claims)
  scoutModelId               (which model distilled this — provenance)
```

Hard rule: the Scout passes **no judgement** — no "why it matters," no project
fit, no ideas. If it editorializes, the triangulation is contaminated.

## Contract — the Signal Graph

Durable cross-signal memory. The substrate that makes answers compound.

```text
SignalGraph (per Project / per corpus)
  signals[]      Signal { id, capturedAt, packetRef, topicTags[], insightRef }
  edges[]        SignalEdge { fromSignalId, toSignalId, kind, rationale, byModelId }
                 kind ∈ reinforces | contradicts | supersedes | recurs | appliesTo
  corpusRefs[]   what a signal touched (file:line for code; postId/asset for content)
```

- Append-only at run time; the Insight Writer writes the new signal + the
  Analyst's edges back after each run.
- The Analyst reads it at stage 1b. Edges are model-attributed (`byModelId`) so
  a spurious link can be traced and pruned.
- Corpus-agnostic: `corpusRefs` is `file:line` for a code repo and
  `postId`/asset id for a content repo — same graph, different anchor.

## Contract — distinct-driver triangulation policy

New resolver policy on the Signal team preset, honored by `TeamResolver`:

```text
TeamPreset.signalPolicy
  scoutModelTag      = .signal + web-aware   (pins Stage 0 to an X-capable model)
  interpreters       = N
  triangulate        = distinctDrivers       (spread interpreters across distinct driverIds)
  degradeWhenSingle  = answerAnyway + LOG    (never silently collapse to one mind)
```

- Scout pins to an X-capable model (Grok today; not hardcoded — selected by
  capability so a future X-capable model qualifies).
- Interpreters maximize **distinct `driverId`s** (Claude / Codex / Gemini /
  Grok) before doubling up on any one driver.
- If only one driver is ready, the run still answers — but `log()`s that
  triangulation degraded to a single mind (per the no-silent-caps rule). Never
  pretend a one-mind read was triangulated.

## Implementation Slices

### SIG-S00 — Scout/interpret split (run shape)

- [ ] Add `SignalSourcePacket` type + parser (fenced ```signal-packet``` block),
      mirroring `SignalInsight`.
- [ ] Promote `signal_source_reader` to the dedicated **Scout** skill: distill
      + named related public posts, explicitly no judgement.
- [ ] `CatalogRunCoordinator`: run the Scout first; inject its packet into every
      interpreter's `writerInput`/answer context. Interpreters read the packet,
      not the raw paste.
- [ ] Durable artifact: packet saved via `RunStore` alongside the insight.

Tests: a `signalPostToProject` run produces exactly one packet; interpreters'
prompts contain the packet text; packet has no fit/ideas content.

### SIG-S01 — Distinct-driver triangulation

- [ ] Add `signalPolicy` to `TeamPreset`; `TeamResolver` pins the Scout to an
      X-capable model and spreads interpreters across distinct `driverId`s.
- [ ] `degradeWhenSingle` path: answer anyway, emit a degraded-triangulation log
      + a flag on the `TeamRun`.

Tests: with ≥2 drivers ready, interpreter workers resolve to distinct
`driverId`s; with 1 ready, run completes and the degraded flag is set.

### SIG-S02 — Signal Graph store

- [ ] New `SignalGraphStore` (per Project / corpus): signals, edges, corpusRefs.
- [ ] Append API + read API; JSON envelopes; `SIGNAL_GRAPH_*` error catalog.
- [ ] `alln signal graph show|edges|signals` CLI + MCP `signal_graph_*` parity.

Tests: append a signal, read it back; add an edge; envelopes schema-validate.

### SIG-S03 — The Analyst (cross-signal AHA)

- [ ] New `signal_analyst` answer skill with read access to the Signal Graph.
- [ ] Surfaces prior related signals + proposes edges (reinforces / contradicts /
      supersedes / recurs); output clearly separates "from prior signals" vs new.
- [ ] Wire into `signalPostToProject` and `signalWhatToBuildNext`.

Tests: with a seeded graph, the analyst references prior signals and proposes
typed edges; with an empty graph it degrades to "first signal — no priors yet."

### SIG-S04 — Insight Writer upgrade + answer-now contract

- [ ] `insight_writer` consumes packet + triangulated reads + skeptic + analyst.
- [ ] Output ALWAYS answers the user's question first; appends `triangulation`
      (who agreed/diverged) and `crossSignal` (the AHA + edges) sections.
- [ ] `SignalInsight` += `triangulation` + `crossSignal`; writer writes the new
      signal + analyst edges back to the Signal Graph.

Tests: insight answers the prompt even with an empty graph; with priors, the
crossSignal section is populated and edges are persisted.

### SIG-S05 — Generalize the grounding corpus (creators)

- [ ] Corpus abstraction: a Project's grounding may be a code repo OR a content
      corpus (posts + performance). `corpusRefs` anchors accordingly.
- [ ] Signal teams + analyst stay corpus-agnostic; no code-only assumptions in
      prompts.

Tests: a content-corpus Project runs a signal end-to-end and anchors a corpusRef
to a postId, not a file:line.

### SIG-S06 — Surface (GUI, last)

- [ ] Insight card shows the answer now + triangulation spread (agree/diverge by
      mind) + tappable cross-signal links to prior signals.
- [ ] GUIFixture seal.

## Works Test

Setup:

```text
1. Seed a Project's Signal Graph with 3 prior signals on a shared topic.
2. alln signal run --team signal_post_to_project --project P \
     --prompt "how does this apply to us?" --source <public X url>
```

Assertions:

- Exactly one `SignalSourcePacket`; it contains no fit/ideas judgement.
- Interpreter workers resolved to ≥2 distinct `driverId`s (or a degraded log if
  only one driver was ready).
- The insight answers the question in its first section.
- A `crossSignal` section references at least one of the 3 seeded priors and ≥1
  typed edge was written back to the Signal Graph.
- Re-running with the new signal present yields a richer crossSignal section
  (the compounding property).

Proof command:

```bash
swift test --package-path Packages/AllnighterCore
alln signal graph show --project P
```

## Done When

- Signal runs distill once (Scout) and interpret many (distinct drivers) — never
  one blind mind re-reading raw input.
- Every run answers the user's question immediately AND writes to the Signal
  Graph; the cross-signal AHA grows run over run with no extra asking.
- The same machinery serves a code repo and a content corpus.
- CLI + MCP parity; no aliases, no shims; check.sh green.

## Open Questions

- Edge pruning: who/what removes a stale or wrong `contradicts` edge over time —
  a periodic analyst sweep, or only when a superseding signal lands?
- Topic clustering: do we tag topics with a model at write time, or compute
  clusters lazily at analyst read time? (Lazy is cheaper; write-time is faster
  to query.)
- Scout neighbor budget: how many `relatedPublicPosts[]` should Grok pull before
  cost outweighs triangulation value? Start small, log, tune.
