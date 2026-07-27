# Cross-Model Review Hardening

Directional role assignment and low-hanging quality guardrails for
writer/reviewer model pairing.

- Status: **FINALIZED — ready for slice execution**
- Owner: `Packages/AllnighterCore` (`RunService.swift`, `BuiltInTeams.swift`,
  `RelayCoordinator.swift`, `ArtifactProjector.swift`)
- Updated: 2026-07-27

---

## 1. Evidence

Source: *[Cross-Model LLM Code Review: Should you use Claude to review Codex
or vice versa?](https://arxiv.org/abs/2607.21656)* — Zuodong Xiang (UC Davis),
Yike Zhang (JHU), YueMing Zhang (CSULB), Hailu Xu (CSULB).
arXiv:2607.21656 [cs.SE], July 2026.

Controlled experiments across 116 hard/medium LiveCodeBench tasks evaluated
static (pre-execution, no test runner) code review between Claude Opus 4.7 and
Codex GPT-5.5:

| Condition | Writer | Reviewer | Pass rate | Δ vs solo | Significance |
| :--- | :--- | :--- | :---: | :---: | :---: |
| Solo Claude baseline | Claude Opus 4.7 | — | 91.4% | — | — |
| Solo Codex baseline | Codex GPT-5.5 | — | 71.6% | — | — |
| Codex self-review | Codex GPT-5.5 | Codex GPT-5.5 | 84.5% | +12.9% | p = .022 |
| Claude self-review | Claude Opus 4.7 | Claude Opus 4.7 | 91.4% | 0.0% | none |
| **Optimal cross-model** | Codex GPT-5.5 | **Claude Opus 4.7** | **89.7%** | **+18.1%** | p = .001 |
| Inverted cross-model | Claude Opus 4.7 | Codex GPT-5.5 | 82.8% | **−8.6%** | p = .046 |

### Lessons for Allnighter

1. **Pairing is asymmetric.** A strong reviewer over a fast worker's draft
   (Codex → Claude) lifts 71.6% to 89.7% — near-flagship quality at worker
   generation cost. The reverse direction is not equivalent.
2. **Weak reviewers damage strong drafts.** Claude → Codex drops 91.4% to
   82.8%: false-positive bug reports, broken correct logic, over-simplified
   implementations.
3. **Flagship self-review buys nothing.** 0.0% gain at double the latency and
   budget.
4. **Static review is reviewer-bound.** Without test execution, reviewer
   caliber is the bottleneck.

---

## 2. Baseline: what Allnighter already does right

- **Pilot / relay loop** — a strong lead (e.g. Opus) steers and reviews while
  execution seats (Grok, Composer, Codex) mutate the repo root
  (`RunService.swift`, `RelayCoordinator.swift`).
- **Built-in team presets** — `BuiltInTeams.swift` staffs a flagship synthesis
  lead over worker seats.
- **Spec Review** — blind critic fan-out anchored to a flagship Synthesizer and
  Refutation Gate (`docs/operations/Spec_Review.md`).

Missing: explicit guardrails against inverted relay configs, advisories for
wasteful flagship self-review, and pair-directionality telemetry in receipts.
That gap is the entire scope of this packet.

---

## 3. Work slices (low-hanging)

### CMR-S01 — Inverted pilot/relay warning

Warn when a relay or pilot run assigns a reviewer of lower caliber than the
execution seat.

- Where pilot/relay resolves the final Lead + worker pair (near
  `PilotSeatResolver` / `RelayCoordinator` — exact call site TBD at
  implementation), compare caliber ranks of Lead vs worker. If
  `lead.caliber < worker.caliber`, emit a non-blocking advisory to stdout and
  the run log. The warning cites the study directionally; it must NOT restate
  the paper's percentage as a general fact, since that number is from one
  model pair (Claude Opus 4.7 / Codex GPT-5.5), not the pair actually running:

  ```text
  [alln warning] Inverted pilot/relay role assignment.
  Reviewer (<LeadModel>) has lower reasoning caliber than execution seat (<WorkerModel>).
  A weaker reviewer over a stronger worker's draft tends to erode correct work
  rather than improve it (arXiv:2607.21656, one model pair — directional, not
  a guaranteed result for this pairing).
  Recommended: set Lead to a higher-caliber model than the worker.
  ```

### CMR-S02 — Flagship self-review waste advisory

Warn when a static review run uses the same flagship model as both writer and
reviewer.

- In `TeamRequestResolver` / `RunService.swift`, detect
  `Writer == Reviewer == Tier-1` and emit. As in CMR-S01, keep the citation
  directional and do not present the paper's single-pair figure as a general
  rate:

  ```text
  [alln tip] Flagship self-review bought no measurable pass-rate gain in the
  cited static-review study (arXiv:2607.21656, one model pair) despite double
  the latency and budget.
  Consider pairing a fast worker (Codex/Composer) as writer with <FlagshipModel>
  as reviewer instead.
  ```

### CMR-S03 — Built-in team staffing invariant

No shipped preset may default to a lead of lower caliber than any of its
workers.

- Invariant over all presets in `BuiltInTeams.all`:
  `caliberRank(lead) >= max(caliberRank(worker))` for every worker seat.
- Proof: unit test `BuiltInTeamsTests.testLeadCaliberDominatesWorkers()`.

### CMR-S04 — Refuter and Synthesizer seat locking

The Spec Review Refutation Gate and Synthesis stage must never fall back to a
low-tier model.

- In `TeamCatalog` / `TeamResolver` (the actual fallback-policy + caliber-band
  resolver — **not** `SkillCatalog.leadCallEnvelope`, which is Lead Call prompt
  copy and has no model-selection role), lock the Refuter (`purpose: .review`)
  and Synthesizer (`purpose: .planWriter`) fallback policy to `.strongestReady`
  within Tier-1/Tier-2 flagships.
- `docs/operations/Spec_Review.md` defines the Refuter as "a fresh worker,
  different vendor" — decorrelation is the point, not caliber alone. This
  slice adds a caliber floor on top of that vendor-diversity requirement; it
  must not narrow the refuter pool to fewer vendors than today. If a caliber
  floor and vendor diversity ever conflict for a given finding, vendor
  diversity wins and the floor is best-effort.
- Refutation of a `blocking` or `material` finding must never be performed by a
  model of lower caliber than the finding's author, subject to the vendor-diversity
  constraint above.

### CMR-S05 — Pair-directionality telemetry

Track empirical `(writer → reviewer)` outcomes in local receipts.

- Record `writer_model_id` and `reviewer_model_id` in `TeamRunJSON` /
  `ArtifactProjector.swift` run metadata.
- Expose the pairing in `alln artifact` receipts so users can inspect local
  pass rates per model pair across repo history.

---

## 4. Proof plan

| Slice | Check |
| :--- | :--- |
| CMR-S01 | `swift test --filter RelayCoordinatorTests` — warning emitted for inverted pairs |
| CMR-S03 | `swift test --filter BuiltInTeamsTests` — lead-caliber dominance invariant holds |
| CMR-S05 | `swift test --filter ContractSchemaTests` — `TeamRunJSON` carries both model IDs |

CMR-S02 and CMR-S04 ship with the same advisory/contract test coverage as
their host modules.
