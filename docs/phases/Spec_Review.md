# Spec Review — the spec-hardening loop

> **Renamed from "Pressure Test" (2026-07-16)** per `Team_Depth_Naming.md`: the team is
> named for what it does, one name everywhere — picker, docs, marketing.

**Name: Spec Review.** Named for what it does, self-explanatory, no fantasy.
The artifact it produces is a **hardened spec**.
Names considered and retired: *Pressure Test* (brand over function), *Spec Hardening*, *Red Team*. Decided once, no aliases.

**The one-liner:** Agents fail because specs are mediocre. Spec Review puts every frontier model
in a room to tear the plan apart until it holds — then any one of them can build it in one pass,
and shows you it working.

("In a room" is marketing, not mechanism. The mechanism is the opposite of a room — see §5:
workers are blind to each other, always. Delphi method, not committee.)

---

## 1. What it is

A team run that takes a rough intent or draft spec and iterates it to convergence:

```
intent/draft ──▶ [draft pass] ──▶ lens fan-out (blind) ──▶ synthesis + refutation gate ──▶ converged?
                                       ▲                        + impact ledger              │ no
                                       └───────────── revised spec ◀────────────────────────┘
                                                                                             │ yes
                                                                                             ▼
                                               hardened spec + proof plan ──▶ executor (any CLI)
```

- **Draft pass (pass 0, optional):** if the input is a rough idea rather than a spec, the plan
  writer drafts one first, grounded in the project context packet. Critique needs a concrete
  target; models critique prose badly and specs well.
- **Lens fan-out:** N workers, each assigned ONE lens (§3). Every worker gets the same spec +
  the same repo context packet — and nothing from any other worker (§5). Structured findings
  out, never walls of text.
- **Synthesis:** the plan writer emits the universal **Lead Call** envelope
  (Status Ready|Partial, the call, what changed, locked recommendations with
  lean+why, contrarian flags, next move, proof, basis, worker credit, plus a
  fenced `lead-call` JSON block for the decision card), then the Spec Review
  **craft body** (impact ledger, rejects, apply-to-doc pointers, proof plan) —
  not a full rewritten phase doc and not a founder homework checklist.
  **Closeout law:** never "not ready." **Ready** = recommended something for
  every fork; work can start without a human answering first. **Partial** =
  only true human/law/missing-fact forks remain, each with Options +
  Recommendation + Why. Lockable engineering leans left open = failed Lead.
  Workers critique; they do not edit repo files. Code SSOT:
  `SkillCatalog.leadCallEnvelope` injected for every `.planWriter` via
  `assemblePrompt`.
- **Converge:** repeat with fresh lens passes until dry (§4). Exit artifact is
  Lead Call + craft body **plus proof** — consumed by verification / the
  decision card later.

Non-mutating end to end. The loop touches no code; its hardened spec can become
the work order for a later execution run.

**Cross-vendor is a tier, not a prerequisite.** A single model running the full lens panel
over multiple passes captures a large share of the value (hardening is mostly the passes,
not the vendor spread). Single-model Spec Review = the on-ramp (works with one CLI
subscription, free-tier candidate). Cross-vendor panel = the premium claim — and it is a
claim the ledger can *measure* (§7), not assert.

### Built-in depth tiers

- **Spec Review Min:** three workers + Lead; prefers Kimi, Cursor Grok, and Grok.
- **Spec Review (default):** five workers + Lead for the everyday send.
- **Spec Review Max:** seven workers + outside scout + Lead for launch/hard cases.

Each row has an ordered cross-CLI fallback chain. All three tiers must remain
runnable when Claude and ChatGPT/Codex are unavailable; Kimi K3, Grok 4.5, and
Cursor Grok 4.5 are first-class preferred workers, not weak last resorts. The
canonical roster and fallback order live in `BuiltInTeams.swift`; naming and
routing law live in `Team_Depth_Naming.md`.

## 2. The impact ledger (the product IS this)

The visible "diff" of each pass is not spec-prose-diff; it is an attributed change summary.
Per pass, the synthesizer emits:

- **Accepted changes** — each entry: what changed in the spec, which worker(s) found it,
  severity (`blocking` / `material` / `polish`), and a one-line why.
  - **Co-attribution:** when multiple workers independently hit the same issue, credit all of
    them. Independent convergence is a strong importance signal — but only because workers
    are blind (§5), and only when the findings cite concrete spec/repo evidence. Three
    workers pointing at the same store schema line is signal; three workers vibing "this
    feels tightly coupled" is one shared prior wearing three hats. Evidence-free convergence
    gets no co-attribution boost.
- **Rejected findings** — each with the worker, the finding, and the rejection reason.
  Recorded rejections stop the same objection being re-litigated next pass, and prove the
  synthesizer isn't rubber-stamping.
- **Open questions** — genuine disagreements between workers, or judgment calls the models
  should not make. These go to the human as cheap approve/pick taps between passes. The
  synthesizer must NOT average away a sharp disagreement; homogenized synthesis is the main
  way this loop dies.
- **Spec vitals** — spec length delta, counts by severity, duplication rate across workers.
  A spec that grows every pass is a smell (hardening ≠ lengthening).

Cumulative across passes and across runs, the ledger becomes a **scoreboard of (lens, model)
pairs** — never of models alone. Every hit is credit to a prompt × model combination; a fixed
lens→model mapping would launder prompt quality as model quality. So: **rotate lens↔model
assignments across runs** (Latin-square style). With enough runs the two effects separate —
"the Cut lens carries, whoever runs it" is as actionable as "model X catches concurrency
bugs." The disentangled scoreboard feeds lens→model routing and is standalone content
("which frontier model is the best critic" writes itself — honestly).

## 3. Lens catalog (seed set)

Two categories, deliberately different jobs:

- **Critics** find flaws in the plan as given. They improve the spec you have.
- **Challengers** compete with the plan. They protect you from hardening the wrong spec —
  a panel of pure critics converges on a well-polished local maximum.

One lens per worker per pass. Lenses must stay orthogonal and concrete — when every lens
drifts into "general review," the fan-out collapses into N copies of the same generic
answer and the loop is worthless. Each lens ships with 2–3 exemplar findings in its prompt.

### Critics

| Lens | Question it asks |
|---|---|
| **Cut** | What in this spec should be deleted? What is the smaller spec that ships the same value? |
| **Greenfield** | Zero users exist. Flag every migration path, compat shim, alias, fallback, or "legacy" mention as a defect to remove. The spec should describe the end state only. |
| **Foundation** | If you were building this substrate from scratch: what shared primitive should exist here? Where does this spec duplicate something that should be one thing? What existing component should it consume instead of reinventing? |
| **Failure modes** | Where does this break? Concurrency, partial failure, bad input, empty/huge state. Each finding must name a concrete scenario, not a category. |
| **Maintainability** | What will the person changing this in six months curse? Naming, coupling, hidden state, unstated invariants. |
| **Sequencing** | Is this ordered so each slice lands green and testable? What's mis-ordered or should be deferred? |
| **Proof** | What commands or visible behaviors would prove each part works? Writes the proof plan. If a requirement can't be proven, flag the requirement. |

### Challengers

| Lens | Question it asks |
|---|---|
| **Clean-room rival** | Never sees the spec. Gets the problem statement + context packet and designs from first principles. The synthesizer diffs the rival against the spec: agreement from a worker who never saw the spec is real validation (it can't be anchoring); divergence is the most valuable finding a run can produce. |
| **Wrong premise** | Which load-bearing assumption in this spec is most likely false? Show what collapses if it is. |
| **Wildcard** | What would the unconventional solution look like? Low expected hit rate, huge value per hit — the ledger decides whether it keeps its seat. |

### Defensive seats (run inside synthesis, not the fan-out — see §4/§5)

| Seat | Job |
|---|---|
| **Steelman** | Defends the current spec against the pass's findings. Accepted findings should have survived someone whose incentive was to reject them. |
| **Refuter** | Fresh worker, different vendor, shown ONE finding with no attribution: "try to kill this claim." Gate for `blocking`/`material` acceptance. |

Lens rules:
- **"No material findings" is a first-class, rewarded answer.** Forced findings are how noise
  gets in. Never quota findings.
- Pass 1 runs the full panel (incl. one challenger). Later passes run a targeted subset
  (lenses whose territory the revision touched) plus one full-panel sweep before declaring
  convergence. Clean-room rival runs once per run (pass 1) — it critiques the problem, not
  the revision.
- **Rotate lens↔model assignments across runs** (§2). Prefer maximum vendor spread per pass
  when cross-vendor; same-family critics share blind spots.

## 4. Convergence and stop rules

Two different things, never blurred:

- **Convergence is the STOP rule.** "Everyone stopped finding new material things" tells you
  when to exit the loop. It never tells you a finding was right.
- **Refutation-survival is the TRUTH rule.** A finding earns acceptance by surviving attack,
  not by being popular.

Mechanics:
- **The bar is outcome-relevance:** a finding is accepted only if it would change what gets
  built or whether it survives. Models can nitpick forever; "would this change execution?" is
  the synthesizer's acceptance test. Polish-severity findings never block convergence.
- **Refutation gate:** every `blocking`/`material` finding goes to a Refuter (§3) before
  acceptance — a fresh worker, different vendor where available, no attribution, prompted
  only to kill the claim. Refuted → rejected (ledger records the kill). Same pattern as the
  try-fix "danger, not doubt" gate.
- **Pushover test (cheap variant):** before accepting a big finding, push back on the finder
  with a counterargument. A finder that instantly caves was pattern-matching, not reasoning —
  downgrade the finding.
- **Dry = one full-panel pass with zero accepted `blocking`/`material` changes.** Then stop.
- **Hard caps:** max passes (default 3–4) and a budget cap. Hitting a cap exits with the spec
  marked `hardened: partial` and the remaining open items listed — never silently truncate.
- Rising duplication rate across workers (everyone finding the same last few things) is the
  natural approach-to-convergence signal; show it in the vitals.

## 5. Independence law + failure modes

**Blind fan-out is INVIOLABLE.** Workers never see other workers' findings — not in the same
pass, not in later passes. They see the revised spec, never the deliberation that produced
it. Independence is the entire epistemic value of the fan-out: convergence between workers
who've read each other is worthless (models are sycophantic, persuadable pleasers and buy into
each other's garbage); convergence between blind workers is signal. A "discussion round"
feature would destroy the product's core mechanism — never build one.

The **synthesizer is the contamination point** — it reads everything and is just as
persuadable. Counters: it judges findings **source-blind** (attribution stripped while
judging, re-attached for the ledger), and it cannot accept big findings alone (refutation
gate, §4).

| Failure | Counter |
|---|---|
| Groupthink / mutual persuasion | Blind fan-out (inviolable) + source-blind synthesis + refutation gate + steelman seat. |
| Shared-prior convergence (blind workers independently land on the same *fashionable* answer — "add an abstraction layer") | Co-attribution only for evidence-grounded findings (§2); clean-room rival converges on designs rather than critiques, which shared fashion fakes less easily. |
| Sycophancy (praise instead of findings) | Adversarial lens framing + "no findings" as a valid answer + findings must cite the spec line they attack. |
| Persuadable finders (cave on pushback) | Pushover test before accepting big findings (§4). |
| Generic advice ungrounded in the repo | Every worker gets the project context packet; findings that don't reference actual repo state get rejected by the synthesizer (and logged — it trains the ledger). |
| Homogenized synthesis | Disagreements become open questions, never averaged. Synthesizer must quote the losing position when rejecting. |
| Local-maximum polishing (great spec, wrong design) | Challenger lenses, clean-room rival especially. |
| Prompt quality laundered as model quality | Scoreboard on (lens, model) pairs + rotation (§2). |
| Spec bloat | Cut lens in every full panel + length vitals + "hardening ≠ lengthening" as an explicit synthesizer instruction. |
| Re-litigation loops | Rejected-findings ledger travels with the spec into every later pass. |
| Six walls of text (manual fan-out with nicer chrome) | Structured finding schema everywhere; the human reads the ledger, never raw worker output (raw available one click deeper). |

## 6. Substrate fit (build notes, not a new system)

- **One team-run substrate.** Spec Review is a team run with a non-mutating posture and an
  insight-class output — a preset + synthesis contract, NOT a second fan-out system. If it
  can't be expressed as a team run, fix the substrate, don't fork it.
- Workers = lens critics/challengers; plan writer = synthesizer/gatekeeper; refuter/steelman
  are ordinary workers invoked by the synthesis stage. Existing roles, sharper contracts.
- Findings, ledger entries, and the hardened spec are schema-backed structured outputs
  end-to-end (agent-first: no text-blob returns anywhere in the loop).
- Grounding comes from the existing project context packet; the exit artifact feeds the
  existing proposal → work order path, with the proof plan flowing into verification.
- Spec revisions are versioned per pass (spec@pass-N + ledger-N); the run is replayable.
- Works degraded-but-real with ONE healthy CLI (single-model mode, §1): same loop, same
  ledger, vendor spread absent. Refutation gate falls back to same-vendor fresh instance.

## 7. Metrics and the flywheel

**North star: one-pass execution success rate** — the share of Lead Calls an
executor can act on in a single pass with proof green and no clarifying
questions. This is the entire point of the feature; everything else is
diagnostic. Exiting "Not ready" with a founder checklist is a failed Lead run
against this north star — banned by the Lead Call closeout law (§1 /
`SkillCatalog.leadCallEnvelope`).

Diagnostics: passes-to-convergence, accepted findings per pass by severity, (lens, model)
hit rates under rotation, refutation-gate kill rate, spec length trajectory, human
open-question load per run.

**Measure the moat:** run the same specs through single-model and cross-vendor panels and
compare accepted blocking/material findings. The cross-vendor premium ("N× more blocking
findings caught") becomes a number the product generates about itself — pricing-tier
evidence, not a marketing assertion. If the delta is small, better to learn it from our own
telemetry than from churn.

**Flywheel:** every execution failure or executor clarifying question downstream is, by
definition, a lens gap — something the panel should have caught. Capture them, mine them
periodically, and turn recurring gaps into new lenses or sharper exemplars. The lens catalog
is a living asset that compounds; it (plus the rotated scoreboard) is the part of this
feature nobody can copy by reading the marketing page.

## 8. Iteration roadmap

- **v0 — the loop, CLI-first, single-model OK:** draft pass + full-panel fan-out + synthesis +
  impact ledger + dry-stop. Fixed seed lenses (critics + clean-room rival). Ledger as
  structured JSON + rendered markdown. Prove it on Allnighter's own specs (dogfood: every
  phase doc goes through it).
- **v1 — convergence quality:** refutation gate + pushover test, rejected-findings memory
  across passes, open-question surfacing to the human, spec vitals, targeted re-review
  passes, budget caps.
- **v2 — the flywheel:** (lens, model) scoreboard with rotation, lens→model routing,
  single-vs-cross-vendor delta measurement, execution-failure capture feeding the lens
  catalog, proof-plan handoff into verify.
- **v3 — surfaces:** GUI ledger view (the pass-over-pass story is the demo), phone
  open-question taps, then the marketing surface (scoreboard content).

Ship v0 before designing v2. The fastest way to learn what the synthesizer contract should
be is ten real runs on our own specs.

## 9. Open questions

- Executor clarifying-question capture: what's the cheapest reliable hook for harvesting
  "the executor had to ask" events per CLI?
- Does the draft pass use the strongest available planner always, or the scoreboard leader?
- Refutation gate cost: gate every blocking/material finding, or sample below a threshold?
  (Start: gate everything; measure kill rate; sample only if kill rate is negligible.)
- Ledger schema versioning: lock v0 schema after dogfood run #10, not before.
