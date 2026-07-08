# Pressure Test — the spec-hardening loop

**Working name: Pressure Test.** Verb-able ("pressure-test this spec"), self-explanatory, no fantasy.
The artifact it produces is a **hardened spec**. Rename is a one-shot find/replace now (zero users);
alternates considered: *Spec Hardening* (outcome-named), *Red Team* (instant dev recognition,
security-scented). Decide once, no aliases.

**The one-liner:** Agents fail because specs are mediocre. Pressure Test puts every frontier model
in a room to tear the plan apart until it holds — then any one of them can build it in one pass,
and shows you it working.

---

## 1. What it is

A team run that takes a rough intent or draft spec and iterates it to convergence:

```
intent/draft ──▶ [draft pass] ──▶ lens fan-out ──▶ synthesis + impact ledger ──▶ converged?
                                       ▲                                           │ no
                                       └───────────── revised spec ◀──────────────┘
                                                                                   │ yes
                                                                                   ▼
                                                     hardened spec + proof plan ──▶ executor (any CLI)
```

- **Draft pass (pass 0, optional):** if the input is a rough idea rather than a spec, the plan
  writer drafts one first, grounded in the project context packet. Critique needs a concrete
  target; models critique prose badly and specs well.
- **Lens fan-out:** N workers, cross-vendor, each assigned ONE lens (§3). Every worker gets the
  same spec + the same repo context packet. Structured findings out, never walls of text.
- **Synthesis:** the plan writer merges findings into a revised spec and emits the impact
  ledger (§2). It is a gatekeeper, not a stenographer — it accepts, rejects, or escalates.
- **Converge:** repeat with fresh lens passes until dry (§4). Exit artifact is the hardened
  spec **plus a proof plan** (the proof commands / visible behaviors that will verify the
  build) — the spec's last section, written during hardening, consumed by verification later.

Non-mutating end to end. The loop touches no code; it exits into the existing
propose → approve → dispatch → verify path.

## 2. The impact ledger (the product IS this)

The visible "diff" of each pass is not spec-prose-diff; it is an attributed change summary.
Per pass, the synthesizer emits:

- **Accepted changes** — each entry: what changed in the spec, which worker(s) found it,
  severity (`blocking` / `material` / `polish`), and a one-line why.
  - **Co-attribution:** when multiple workers independently hit the same issue, credit all of
    them. Independent convergence is the strongest importance signal in the system — surface
    it ("3 of 5 workers flagged the store schema").
- **Rejected findings** — each with the worker, the finding, and the rejection reason.
  Recorded rejections stop the same objection being re-litigated next pass, and prove the
  synthesizer isn't rubber-stamping.
- **Open questions** — genuine disagreements between workers, or judgment calls the models
  should not make. These go to the human as cheap approve/pick taps between passes. The
  synthesizer must NOT average away a sharp disagreement; homogenized synthesis is the main
  way this loop dies.
- **Spec vitals** — spec length delta, counts by severity, duplication rate across workers.
  A spec that grows every pass is a smell (hardening ≠ lengthening).

Cumulative across passes and across runs, the ledger becomes a **per-model scoreboard**:
which model catches what class of issue, hit rate per lens. Feeds lens→model assignment
(§3) and is standalone content ("which frontier model is the best critic" writes itself).

## 3. Lens catalog (seed set)

One lens per worker per pass. Lenses must stay orthogonal and concrete — when every lens
drifts into "general review," the fan-out collapses into six copies of the same generic
answer and the loop is worthless. Each lens ships with 2–3 exemplar findings in its prompt.

| Lens | Question it asks |
|---|---|
| **Cut** | What in this spec should be deleted? What is the smaller spec that ships the same value? |
| **Greenfield** | Zero users exist. Flag every migration path, compat shim, alias, fallback, or "legacy" mention as a defect to remove. The spec should describe the end state only. |
| **Foundation** | If you were building this substrate from scratch: what shared primitive should exist here? Where does this spec duplicate something that should be one thing? What existing component should it consume instead of reinventing? |
| **Failure modes** | Where does this break? Concurrency, partial failure, bad input, empty/huge state. Each finding must name a concrete scenario, not a category. |
| **Maintainability** | What will the person changing this in six months curse? Naming, coupling, hidden state, unstated invariants. |
| **Sequencing** | Is this ordered so each slice lands green and testable? What's mis-ordered or should be deferred? |
| **Proof** | What commands or visible behaviors would prove each part works? Writes the proof plan. If a requirement can't be proven, flag the requirement. |

Lens rules:
- **"No material findings" is a first-class, rewarded answer.** Forced findings are how noise
  gets in. Never quota findings.
- Pass 1 runs the full panel. Later passes run a targeted subset (lenses whose territory the
  revision touched) plus one full-panel sweep before declaring convergence.
- Cross-vendor assignment is the point: same-family critics share blind spots. Prefer maximum
  vendor spread per pass; use the scoreboard (§2) to route lenses to the models that
  historically catch that class.

## 4. Convergence and stop rules

- **The bar is outcome-relevance:** a finding is accepted only if it would change what gets
  built or whether it survives. Models can nitpick forever; "would this change execution?" is
  the synthesizer's acceptance test. Polish-severity findings never block convergence.
- **Dry = one full-panel pass with zero accepted `blocking`/`material` changes.** Then stop.
- **Hard caps:** max passes (default 3–4) and a budget cap. Hitting a cap exits with the spec
  marked `hardened: partial` and the remaining open items listed — never silently truncate.
- Rising duplication rate across workers (everyone finding the same last few things) is the
  natural approach-to-convergence signal; show it in the vitals.

## 5. Failure modes of the loop itself, and counters

| Failure | Counter |
|---|---|
| Sycophancy (praise instead of findings) | Adversarial lens framing + "no findings" as a valid answer + findings must cite the spec line they attack. |
| Generic advice ungrounded in the repo | Every worker gets the project context packet; findings that don't reference actual repo state get rejected by the synthesizer (and logged — it trains the ledger). |
| Homogenized synthesis | Disagreements become open questions, never averaged. Synthesizer must quote the losing position when rejecting. |
| Spec bloat | Cut lens in every full panel + length vitals + "hardening ≠ lengthening" as an explicit synthesizer instruction. |
| Re-litigation loops | Rejected-findings ledger travels with the spec into every later pass. |
| Six walls of text (manual fan-out with nicer chrome) | Structured finding schema everywhere; the human reads the ledger, never raw worker output (raw available one click deeper). |

## 6. Substrate fit (build notes, not a new system)

- **One team-run substrate.** Pressure Test is a team run with a non-mutating posture and an
  insight-class output — a preset + synthesis contract, NOT a second fan-out system. If it
  can't be expressed as a team run, fix the substrate, don't fork it.
- Workers = lens critics; plan writer = synthesizer/gatekeeper. Existing roles, sharper contracts.
- Findings, ledger entries, and the hardened spec are schema-backed structured outputs
  end-to-end (agent-first: no text-blob returns anywhere in the loop).
- Grounding comes from the existing project context packet; the exit artifact feeds the
  existing proposal → work order path, with the proof plan flowing into verification.
- Spec revisions are versioned per pass (spec@pass-N + ledger-N); the run is replayable.

## 7. Metrics and the flywheel

**North star: one-pass execution success rate** — the share of hardened specs an executor
completes in a single pass with proof green and no clarifying questions. This is the entire
point of the feature; everything else is diagnostic.

Diagnostics: passes-to-convergence, accepted findings per pass by severity, per-model/per-lens
hit rates, spec length trajectory, human open-question load per run.

**Flywheel:** every execution failure or executor clarifying question downstream is, by
definition, a lens gap — something the panel should have caught. Capture them, mine them
periodically, and turn recurring gaps into new lenses or sharper exemplars. The lens catalog
is a living asset that compounds; it (plus the scoreboard) is the part of this feature
nobody can copy by reading the marketing page.

## 8. Iteration roadmap

- **v0 — the loop, CLI-first:** draft pass + full-panel fan-out + synthesis + impact ledger +
  dry-stop. Fixed seed lenses. Ledger as structured JSON + rendered markdown. Prove it on
  Allnighter's own specs (dogfood: every phase doc goes through it).
- **v1 — convergence quality:** rejected-findings memory across passes, open-question
  surfacing to the human, spec vitals, targeted re-review passes, budget caps.
- **v2 — the flywheel:** per-model scoreboard, lens→model routing, execution-failure capture
  feeding the lens catalog, proof-plan handoff into verify.
- **v3 — surfaces:** GUI ledger view (the pass-over-pass story is the demo), phone
  open-question taps, then the marketing surface (scoreboard content).

Ship v0 before designing v2. The fastest way to learn what the synthesizer contract should
be is ten real runs on our own specs.

## 9. Open questions

- Executor clarifying-question capture: what's the cheapest reliable hook for harvesting
  "the executor had to ask" events per CLI?
- Does the draft pass use the strongest available planner always, or the scoreboard leader?
- Ledger schema versioning: lock v0 schema after dogfood run #10, not before.
