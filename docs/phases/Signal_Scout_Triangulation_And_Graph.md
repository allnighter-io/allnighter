# Signal Scout, Triangulation, And The Signal Graph

Status: Draft backend/product spec — the next big upgrade to the Signal craft
Owner: Signal lane (Core team-run substrate + TeamResolver + a new Signal Graph store + source adapters)
Updated: 2026-07-24 (banned-term sweep: dead `Project_Spine_And_Project_Manager.md`
  reference and stale propose/approve/dispatch/verify "Current State" claims removed)

## Authority

Read with:

- `docs/strategy/Allnighter_Public_Signal_Wedge.md` (why Signal is the wedge; the Grok/X premise)
- Code SSOT `RunService.swift` (Signal is a preset/tag/output shape over the ONE run primitive, not a separate mode)
- `docs/phases/Team_Run_Floor.md` (owns the `SignalInsight` / `SignalReceipt` contract and the Floor projection)
- `docs/phases/Team_Delegation_Surface.md` (owns Signal as a team family)
- `docs/phases/Model_Catalog_And_Bench_Roster.md` (owns model lane tags + driver manifests)
- Code SSOT `RunService.swift` / `RunRecord` owns the run+receipt trail the provenance reuses (there is no propose→approve→dispatch→verify spine — that ceremony's deletion manifest is in archived `Unified_Run_Model.md`)
- `docs/phases/Language_Cutover.md` (Signal is the 4th craft; `WorkLane.signal`, `TeamOutputKind.insight`)

This doc owns: (1) a **source-agnostic** Scout → triangulation run shape, (2)
**role-aware, distinct-driver** model assignment so a signal is read by *many
minds and many source types*, (3) the **Signal Graph** — durable cross-signal
memory, and (4) the two laws that keep this honest instead of becoming another
second-brain graveyard: the **doubly-grounded gate** and **observation, not
attribution**.

## The two laws (read these first — everything else serves them)

A "compounding intelligence graph" on its own is the second-brain promise, and
that graveyard is large. Two laws keep this grounded. They are the spine, not
footnotes.

### Law 1 — Doubly-grounded gate (intersection-or-nothing)

Every Insight must stand on **two feet**:

```text
one foot on an OUTSIDE source span   (a verbatim quote, a transcript timestamp)
one foot on PRIVATE TRUTH            (a file:line, a doc, a prior run/decision, a past post)
```

- One foot on outside-only → that is just *news*. Reject.
- One foot on private-only → that is just *code search*. Reject.
- The wedge IS the intersection: ideas and suggestions **grounded in your own
  private repo/content**, sourced to a real outside artifact. An LLM can
  summarize a podcast or summarize X; it cannot say "this point at 34:12 lines up
  with the same complaint in three threads you saved AND maps to the feature in
  `OnboardingView.swift:212` you almost cut last week." That sentence is only
  possible because Allnighter sits on both corpora at once.

The **private leg is mostly self-generated.** Allnighter is the execution
environment, so the private corpus accretes as exhaust of normal use — runs,
threads, worker answers, docs, past content. It is not a curation chore the user
must maintain; it fills because you worked here. That is the durable, hard-to-
copy asset (your operational history exists nowhere else), and it is why the
intersections get richer the longer you use the tool.

This is a **validity gate**, enforced on the Insight Writer's output and tested
— not a tagline. "No move today" is always a valid, complete Insight.

### Law 2 — Observation, not attribution (no causation claims)

Correlation is not causation. A move made after a signal does not mean the signal
caused it; an outcome after a move does not mean the move caused it. The open
loop cannot prove either link — there is no control group — so the product must
never claim it does.

```text
OBSERVATION and PROVENANCE survive without a control.   -> we do this.
ATTRIBUTION and SCORING require a control.               -> we do NOT, except via A/B (see seam).
```

Banned by policy (each needs causation we do not have):

- calibration / "your X angle underperforms by N%";
- per-user scoring of workers/models ("Codex is better for you");
- "track record / keeps score" positioning;
- "this signal worked / paid off."

Kept (pure observation/provenance — true regardless of cause):

- **Provenance / recall:** "here is what you were looking at when you decided."
- **Addressed-vs-open:** "this cluster already produced a move — stop surfacing
  it as fresh." A true statement about *your actions*, not about cause.
- **Outcomes as raw facts:** "this post got 2.1k saves." Display it; attribute
  nothing.
- **Counts:** "this topic recurred 5 times; you have not acted." A count, not a
  verdict — the human decides if it is an opportunity or correctly-ignored noise.

So a receipt records **that a move was made and its observed context/outcome**,
for provenance and dedup — never to score the signal. The unfair advantage stays
real but narrower: Allnighter **already owns a durable run record** (`RunRecord`
— message, worker(s), result, timestamps; no propose/approve/dispatch/verify
ceremony), so capturing that provenance is free.

**The seam where the loop genuinely closes:** a controlled experiment. Where a
move targets an A/B-testable surface (Ikiro / websitemd.studio), randomized
assignment closes the **move → outcome** link causally — real calibration lives
*there*, in that product, not in this one. Even then it does **not** close
**signal → move** (A/B proves "B beat A," not "the post is why B existed"), so we
never re-import the fallacy through the A/B door. This is a marked future seam,
not a build target for this phase.

## Founder Intent

Raw request (distilled from the brainstorm):

```text
If I paste a link and ask "what does this mean for my project?" I want the
answer RIGHT NOW. The insane unlock is the answers get better over time without
asking. A signal run should NOT just be Grok: Grok distills the source WITHOUT
judgement (raw info dump), then fans it out to several DIFFERENT CLIs so we get
triangulation. Every run has an internal analyst that compares this signal to
prior signals in a Signal Graph to find the true AHA.

X is not "Signal" — X is one signal SOURCE. VVX transcripts are another. The
real primitive is: outside artifact -> neutral source packet -> multi-agent
interpretation -> project/content fit -> durable Signal Graph -> move/receipt.
X = velocity (WHEN it's moving). Long-form video/podcast = depth (WHY it
matters). The repo = feasibility (WHETHER we can act). VVX is ours and open
source; we consume it almost like another CLI — something Allnighter leverages
when a user wants to extract/evaluate a signal.

This is for developers AND online creators, whose "repo" is the content they
write and how their posts perform.
```

Product value:

```text
One artifact is a tip. Ten artifacts cross-referenced against each other AND
against your own corpus produces ideas and suggestions grounded in YOUR private
repo/content — not generic AI summary. Allnighter is the only place that holds
the signal stream, the corpus (code OR content), AND a fleet of CLI minds across
velocity + depth sources, so it can keep generating grounded moves as the pile
grows. It does not claim those moves "work" — it makes them easy to generate,
well-grounded, and easy to recall later. Validation of whether a move actually
worked is a separate, controlled problem (see the A/B seam); this product is
honest about not solving it here.
```

Trusted workflow slice:

```text
1. User drops a source (X link, YouTube/podcast URL, article) into a Project and
   asks "how does this apply to us?"
2. The right SOURCE ADAPTER turns it into a neutral SignalSourcePacket:
   - X            -> read natively by an X-capable scout (Grok today)
   - video/podcast-> VVX extracts timestamped transcript blocks + chapters,
                     then the scout distills them. NO judgement either way.
3. That one packet fans out to several DIFFERENT CLIs (Claude, Codex, Gemini,
   Grok) who each interpret independently -> triangulation across minds.
4. The Analyst compares this signal to prior signals in the Signal Graph and
   surfaces the cross-signal AHA.
5. The Skeptic stress-tests; the Insight Writer DECIDES.
6. The user gets a decisive, DOUBLY-GROUNDED answer right now — plus an "in
   light of your prior signals…" section richer than a month ago.
7. The signal + packet + topic tags + edges are written back to the graph; if a
   move ships, its receipt is recorded as PROVENANCE (what was done, in what
   context) — not as proof the signal worked.
```

Non-goals:

- Do NOT hold back the answer waiting for a cluster to form. The single question
  is always answered now; the cross-signal AHA is **additive enrichment**.
- No social-listening dashboard, X API proxy/reseller, scheduler, auto-poster.
- **Do not build a video app inside Allnighter.** VVX stays an external
  extractor we consume; Allnighter turns packets into Project-aware moves.
- No private/authenticated source access claims. Public sources only.
- Not a new run loop. Rides `CatalogRunCoordinator` and the existing dispatch
  spine.
- No standalone "clustering" subsystem (edges ARE the clusters — see below).
- **No causation claims** (Law 2): no calibration, no scoring of signals/
  workers, no "this worked." Receipts are provenance + dedup only.

## Current State

Useful substrate:

- `WorkLane.signal` + `TeamOutputKind.insight` are live (`TeamCatalog.swift`).
- Built-in teams `signalPostToProject`, `signalWhatToBuildNext` (`BuiltInTeams.swift`).
- Signal skills (`SkillCatalog.swift`): `signal_source_reader`,
  `signal_landscape_scanner`, `signal_project_fit`, `signal_product_ideas`,
  `signal_skeptic`, lead `insight_writer`.
- `model_grok`: `laneTags: [.code, .copy, .signal]`, web-aware; driver runs
  `grok -p … -m … --output-format plain` (`ModelCatalog.swift`).
- `SignalInsight` / `SignalReceipt` typed output + parser (`SignalInsight.swift`);
  surfaced via `FloorReturn.kind = .insight`.
- Run substrate `CatalogRunCoordinator.run()`: answer (blind parallel) → review
  → plan (Lead synthesizes).
- The durable run record exists (`RunRecord`/`RunService.swift`) — Law 2 reuses
  it for provenance. `ProjectDispatchService` and `WorkReturnStore` were the old
  propose/approve ceremony types; both are deleted, not a substrate to reuse.

Current gaps (the reason for this doc):

1. **No scout → fan-out.** The three interpreters run *blind parallel* and never
   receive the source reader's distillation — no shared neutral packet.
2. **One mind, not many.** `fallbackPolicy: .strongestReady` tends to pick one
   model (usually Grok) for the whole team. Triangulation does not exist.
3. **One source type.** Only pasted text / X is contemplated. No depth source
   (video/podcast) and no source-agnostic packet.
4. **No memory.** Each run is one-shot. No Signal Graph, no analyst, nothing
   persists to learn from — so answers can't compound.
5. **No gate, no provenance.** Nothing enforces double-grounding; nothing records
   what a move was grounded in for later recall.
6. **Corpus is code-shaped.** A creator's content corpus has no home.

## Decision — the upgraded Signal run shape (source-agnostic)

Five ordered stages on the existing substrate. Stage 0 (Scout, fed by a source
adapter) and the distinct-driver fan-out at Stage 1 are the core change.

```text
Stage 0  ADAPTER + SCOUT  (distill, NO judgement)
         A source adapter turns the URL/text into source spans; an X-capable
         scout (Grok today) distills them into a neutral SignalSourcePacket.
         X: scout reads natively. Video/podcast: VVX extracts timestamped
         transcript first, then the scout distills. Facts/quotes/timestamps
         only — zero fit, zero ideas.

Stage 1  TRIANGULATE  (N interpreters, DISTINCT drivers)
         The same packet fans out to several different CLIs. Each runs
         project-fit + product-ideas independently. Diversity of minds — and,
         when several sources are in play, diversity of SOURCE TYPES — is the
         product.

Stage 1b ANALYST  (cross-signal AHA)
         Query the Signal Graph for prior related signals; surface the
         intersection and propose typed edges. Additive — never blocks.

Stage 2  SKEPTIC  (review)
         Fresh / stale / saturated / not-a-fit. Now also sees the triangulation
         spread and the analyst's links. "No move today" is first-class.

Stage 3  INSIGHT WRITER  (the Lead, DECIDES)
         Enforce the doubly-grounded gate. Answer the question NOW; append the
         triangulation spread and the cross-signal AHA. Tag the topic (free —
         it's already deciding what this is about). Write signal + packet +
         tags + edges back to the graph. If a move dispatches, its receipt is
         recorded as provenance (Law 2) — never scored.
```

Substrate mapping: the Scout is a new pre-answer dependency stage whose packet is
injected into every interpreter's context (interpreters stay parallel; their
input is the packet, not the raw paste). Analyst is an answer worker with read
access to the graph. Skeptic stays review; Insight Writer stays the Lead
(`planWriter`) and gains the gate + write-back.

## Contract — SignalSourcePacket (source-agnostic)

Neutral output of Stage 0. Facts only; inference is the interpreters' job.

```text
SignalSourcePacket
  id
  sourceKind        xPost | xThread | videoTranscript | podcastTranscript |
                    article | releaseNote | repo | other
  provenance        { url, author/uploader, publishedAt, capturedAt }   (uncertain allowed, never invented)
  adapter           { name, version }      e.g. {grok-native}, {vvx, 1.x}
  spans[]           the atomic receipts — verbatim, each carries an anchor:
                      xPost            -> quote + postId
                      videoTranscript  -> transcript block + timestamp + chapter
                      article          -> quote + section
  relatedPublic[]   neighbors the scout surfaced { url, author, oneLineGist }
  observedFacts[]   literal, attributable
  unverifiable[]    what could NOT be confirmed (timestamps, claims)
  scoutModelId      which model distilled this (provenance)
```

Hard rules:

- The Scout passes **no judgement** — no "why it matters," no fit, no ideas. If
  it editorializes, the triangulation is contaminated.
- Every span is a **timestamped/anchored receipt**, not a summary. (This is why
  VVX matters — it yields timestamped transcript blocks, so a video Insight can
  cite "at 34:12 the speaker says X" instead of a mushy gist.)
- How deep the scout digs is governed by **reasoning level + team size** — the
  two existing axes. There is no separate "neighbor budget" knob.

## Contract — the Signal Graph

Durable cross-signal memory; the substrate that makes grounding richer over time
and the home of provenance (Law 2).

```text
SignalGraph (per Project / per corpus)
  signals[]    Signal { id, capturedAt, packetRef, topicTags[], insightRef }
  edges[]      SignalEdge { fromSignalId, toSignalId, kind, rationale, byModelId }
               kind ∈ reinforces | contradicts | supersedes | recurs | appliesTo
  receipts[]   SignalReceiptLink { signalId, moveRef, workReturnRef, status }
               status ∈ shipped | reverted | abandoned | pending
               (PROVENANCE: what was done in what context — NOT a score of the signal)
  corpusRefs[] what a signal touched
               code repo     -> file:line / commit
               content corpus-> postId / asset id
```

- **Append-only at run time.** The Insight Writer writes the new signal + topic
  tags + the Analyst's edges after each run.
- **Clusters need no algorithm.** A cluster is a *connected component* of the
  edge graph. Topic tags (written free at synthesis) are the cheap coarse index
  for "which priors might be relevant"; the analyst's edges are the reasoned
  truth; components fall out of the topology. There is no separate clustering
  pass to build or keep consistent.
- **Edges are model-attributed** (`byModelId`) so a spurious link is traceable
  and prunable.
- **Receipts are provenance, not feedback** (Law 2): when a Signal-derived move
  dispatches, a `SignalReceiptLink` records *that it was done and in what
  context*. It marks the cluster as **addressed** (stop surfacing it as fresh) —
  a true statement about your actions. It does **not** weight, score, or grade
  the signal; causal feedback only exists at the A/B seam.
- **Corpus-agnostic:** `corpusRefs` anchors to `file:line` for code and
  `postId`/asset for content — same graph, different anchor.

The lifecycle, in computable terms (counts and states, not verdicts):

```text
Insight      = one signal, doubly-grounded                       (Law 1)
Recurring    = a cluster that appears across >= N signals AND touches private
               truth AND has no recorded move yet. A COUNT surfaced for the
               human to judge — not a claim that you should act.
Addressed    = a cluster that already produced a move (has a receipt).
               Stop surfacing it as fresh. Provenance only — no claim it worked.
```

## Contract — distinct-driver triangulation policy

New resolver policy on the Signal team preset, honored by `TeamResolver`:

```text
TeamPreset.signalPolicy
  scoutModelTag      = .signal + web-aware     (pins Stage 0 to an X-capable model; capability-selected, not hardcoded)
  interpreters       = N
  triangulate        = distinctDrivers         (spread interpreters across distinct driverIds before doubling up)
  degradeWhenSingle  = answerAnyway + LOG      (never silently collapse to one mind)
```

- Scout pins to an X-capable model by *capability* (Grok today; a future
  X-capable model qualifies automatically).
- Interpreters maximize distinct `driverId`s (Claude / Codex / Gemini / Grok)
  before doubling on any driver.
- If only one driver is ready, the run still answers — but `log()`s that
  triangulation degraded to a single mind (no-silent-caps rule). Never pretend a
  one-mind read was triangulated.
- When several sources are present, triangulation also spans **source types**
  (velocity × depth), which is a second, orthogonal axis of diversity.

## Source adapters — sources behave like CLIs

A `SourceAdapter` turns a URL/text into a `SignalSourcePacket`. Two shapes:

```text
native-read   the X-capable scout model reads the source directly
              -> X / public web (Grok)
external      an external extractor produces anchored spans, then the scout
              distills them
              -> video/podcast (VVX)
```

**VVX is ours and open source; we consume it almost like another CLI.** Just as
`model_grok` is a bench driver with a manifest, a video/podcast `SourceAdapter`
is a driver-like entry Allnighter invokes on a URL to get timestamped transcript
blocks + chapters. Keep VVX excellent at extraction, external, and unabsorbed;
Allnighter's job starts at the packet.

Adapter discipline (avoid the adapter zoo): make the **packet contract**
source-agnostic on day one (foundation-first), but ship exactly **two** adapters
— X (velocity) and VVX/transcript (depth). They differ enough (snippet vs.
timestamped block) to *prove the abstraction is right*. Reddit / blog /
changelog wait.

## Implementation Slices

### SIG-S00 — Source-agnostic packet + Scout split (run shape)

- [ ] Add `SignalSourcePacket` (source-agnostic, anchored `spans[]`) + parser
      (fenced ```signal-packet``` block), mirroring `SignalInsight`.
- [ ] Promote `signal_source_reader` to the dedicated **Scout** skill: distill +
      named related public sources, explicitly no judgement.
- [ ] `CatalogRunCoordinator`: run the Scout first; inject its packet into every
      interpreter's context. Interpreters read the packet, not the raw paste.
- [ ] Durable packet via `RunStore` alongside the insight.

Tests: a `signalPostToProject` run produces exactly one packet; interpreter
prompts contain packet text; packet carries no fit/ideas content; spans carry
anchors.

### SIG-S01 — Signal Graph store (memory + receipts)

- [ ] New `SignalGraphStore` (per Project / corpus): `signals`, `edges`,
      `receipts`, `corpusRefs`. Append + read APIs; JSON envelopes;
      `SIGNAL_GRAPH_*` error catalog.
- [ ] Clusters as connected components (no clustering pass); topic-tag index.
- [ ] `alln signal graph show|signals|edges|clusters` CLI + MCP
      `signal_graph_*` parity.

Tests: append a signal; read it back; add an edge; clusters derive from edges;
envelopes schema-validate.

### SIG-S02 — Distinct-driver (+ cross-source) triangulation

- [ ] Add `signalPolicy` to `TeamPreset`; `TeamResolver` pins the Scout to an
      X-capable model and spreads interpreters across distinct `driverId`s.
- [ ] `degradeWhenSingle`: answer anyway, emit degraded-triangulation log + a
      flag on the `TeamRun`.

Tests: ≥2 drivers ready → interpreters resolve to distinct `driverId`s; 1 ready
→ run completes with degraded flag set.

### SIG-S03 — The Analyst (cross-signal AHA)

- [ ] New `signal_analyst` answer skill with read access to the Signal Graph.
- [ ] Surfaces prior related signals + proposes typed edges (reinforces /
      contradicts / supersedes / recurs); separates "from prior signals" vs new.
- [ ] Wire into `signalPostToProject` and `signalWhatToBuildNext`.

Tests: seeded graph → analyst references priors + proposes typed edges; empty
graph → degrades to "first signal — no priors yet."

### SIG-S04 — Doubly-grounded gate + Insight Writer upgrade (Law 1)

- [ ] `insight_writer` consumes packet + triangulated reads + skeptic + analyst.
- [ ] **Gate:** every Insight must cite ≥1 outside source span AND ≥1 project
      corpusRef, or it is "no move today." Enforced + tested.
- [ ] Output answers the question first; appends `triangulation` (who
      agreed/diverged) and `crossSignal` (AHA + edges) sections.
- [ ] Writer tags the topic at write time (free byproduct of synthesis) and
      writes signal + tags + edges back to the graph.
- [ ] `SignalInsight` += `groundedSpans[]`, `groundedCorpusRefs[]`,
      `triangulation`, `crossSignal`.

Tests: an insight with only outside grounding is rejected as "no move today";
with both feet it ships; with priors, `crossSignal` is populated + edges
persisted.

### SIG-S05 — Receipt provenance (Law 2 — observation only)

- [ ] When a Signal-derived move dispatches via the existing
      `ProjectDispatchService`, record a `SignalReceiptLink`
      (status: shipped/reverted/abandoned/pending) as **provenance** — what was
      done, in what context.
- [ ] A recorded move marks the cluster **addressed** (stop surfacing it as
      fresh). No scoring, no weighting, no "it worked."
- [ ] Causation explicitly out of scope here — calibration lives only at the A/B
      seam (Ikiro / websitemd.studio), tracked in that product, not this one.

Tests: dispatch a move tied to a signal → a `SignalReceiptLink` lands; the
cluster flips recurring → addressed; no scoring fields exist on the receipt.

### SIG-S06 — Source adapters: X + VVX

- [ ] `SourceAdapter` contract (native-read | external) → `SignalSourcePacket`.
- [ ] X adapter (native-read via the Grok scout).
- [ ] VVX adapter (external extractor consumed like a bench driver: URL →
      timestamped transcript blocks + chapters → scout distills). VVX stays
      external/unabsorbed.

Tests: an X URL and a YouTube URL each produce a valid packet; video spans carry
timestamps/chapters; VVX invoked as an external adapter, not vendored UI.

### SIG-S07 — Generalize the grounding corpus (creators)

- [ ] Corpus abstraction: grounding may be a code repo OR a content corpus
      (posts + performance). `corpusRefs` anchors accordingly.
- [ ] Signal teams + analyst stay corpus-agnostic; no code-only prompt
      assumptions.

Tests: a content-corpus Project runs end-to-end and anchors a corpusRef to a
postId, not a file:line.

### SIG-S08 — Surface (GUI, last)

- [ ] Insight card: the answer now + double-grounding receipts (outside span ↔
      private ref) + triangulation spread (agree/diverge by mind) + tappable
      cross-signal links + cluster state (recurring vs. addressed). No scores.
- [ ] GUIFixture seal.

## Works Test

Setup:

```text
1. Seed a Project's Signal Graph with 3 prior signals on a shared topic.
2. alln signal run --team signal_post_to_project --project P \
     --prompt "how does this apply to us?" --source <public X url>
3. alln signal run --team signal_post_to_project --project P \
     --prompt "and this talk?" --source <youtube url>      # depth source via VVX
```

Assertions:

- Each run yields exactly one `SignalSourcePacket`; no fit/ideas judgement; the
  YouTube packet's spans carry timestamps/chapters.
- Interpreters resolved to ≥2 distinct `driverId`s (or a degraded log).
- The Insight answers the question in its first section and passes the
  doubly-grounded gate (cites ≥1 outside span AND ≥1 project corpusRef) — or is a
  clean "no move today."
- `crossSignal` references ≥1 of the 3 seeded priors; ≥1 typed edge written back.
- Re-running with the new signals present yields a richer `crossSignal` (the
  compounding property: more grounding, not "better scores").
- Dispatching a move tied to a signal records a `SignalReceiptLink` (provenance)
  and flips its cluster recurring → addressed. The receipt carries no score.

Proof command:

```bash
swift test --package-path Packages/AllnighterCore
alln signal graph show --project P
alln signal graph clusters --project P
```

## Done When

- Signals distill once (Scout, source-agnostic) and interpret many (distinct
  drivers, velocity × depth) — never one blind mind re-reading raw input.
- Every Insight is **doubly-grounded** or a clean "no move today" (Law 1).
- Moves write **receipts** back as provenance only — no scoring, no causation
  claims anywhere in the product (Law 2).
- The graph compounds run over run (richer grounding) with no extra asking and no
  curation chore.
- X + VVX both feed the same packet; VVX consumed externally like a CLI.
- Same machinery serves a code repo and a content corpus.
- CLI + MCP parity; no aliases, no shims; check.sh green.

## Open Questions

- **Edge pruning:** does a periodic analyst sweep retire stale `contradicts`
  edges, or only a superseding signal?
- **Receipt linking (provenance, not attribution):** a dispatched move links to
  the signal(s) that were on screen as context — single link or a cluster link.
  This is recall plumbing, NOT a causal claim that the signal drove the move.
- **Cold-start honesty:** value ramps with corpus depth (a fresh project gets
  generic reads until it has enough private corpus to ground against). The
  self-generated corpus (Law 1) softens this — it fills as you use the tool — but
  do not promise day-1 magic.
- **Second depth adapter:** after VVX proves the external-adapter shape, which
  source earns adapter #3 (Reddit thread? competitor changelog?) — gate on
  demand, not on enthusiasm.
