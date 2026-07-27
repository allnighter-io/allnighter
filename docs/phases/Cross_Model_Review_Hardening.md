# Cross-Model Review Hardening — Directional Role Assignment & Low-Hanging Quality Guardrails

Status: **OPEN PHASE PACKET — Low-Hanging Fruit Optimization**
Owner: `Packages/AllnighterCore` (`RunService.swift`, `BuiltInTeams.swift`, `RelayCoordinator.swift`, `ArtifactProjector.swift`)
Updated: 2026-07-27

---

## 1. Context & empirical evidence

A July 2026 study (*[Cross-Model LLM Code Review: Should you use Claude to review Codex or vice versa?](https://arxiv.org/abs/2607.21656)*, Zuodong Xiang, Yike Zhang, YueMing Zhang, Hailu Xu; arXiv:2607.21656v1 [cs.SE], 22 Jul 2026) conducted controlled experiments across 116 hard and medium LiveCodeBench tasks evaluating static (pre-execution) code review between frontier models (**Claude Opus 4.7** and **Codex GPT-5.5**).

### Primary Source & Citation
- **Paper:** *Cross-Model LLM Code Review: Should you use Claude to review Codex or vice versa?*
- **Authors:** Zuodong Xiang (UC Davis), Yike Zhang (JHU), YueMing Zhang (CSULB), Hailu Xu (CSULB).
- **Publication / arXiv:** [arXiv:2607.21656 [cs.SE]](https://arxiv.org/abs/2607.21656) (July 2026).

### Key Empirical Findings

| Condition | Writer (Draft) | Reviewer (Static Pass) | Pass Rate | Delta vs. Solo Baseline | Significance |
| :--- | :--- | :--- | :---: | :---: | :---: |
| **Solo Claude Baseline** | Claude Opus 4.7 | *None* | **91.4%** | — | — |
| **Solo Codex Baseline** | Codex GPT-5.5 | *None* | **71.6%** | — | — |
| **Codex Self-Review** | Codex GPT-5.5 | Codex GPT-5.5 | **84.5%** | +12.9% | $p_{BH} = .022$ |
| **Claude Self-Review** | Claude Opus 4.7 | Claude Opus 4.7 | **91.4%** | 0.0% (No gain) | Unchanged |
| **Optimal Cross-Model** | Codex GPT-5.5 | **Claude Opus 4.7** | **89.7%** | **+18.1% gain** | $p_{BH} = .001$ |
| **Inverted Cross-Model** | Claude Opus 4.7 | **Codex GPT-5.5** | **82.8%** | **-8.6% regression** | $p_{BH} = .046$ |

### Direct Lessons for Agent Control Loops

1. **Role Pairing Is Strongly Asymmetric:** The direction of writer vs. reviewer assignment matters immensely. Assigning a higher-reasoning model (**Claude Opus 4.7**) to review a faster/cheaper worker's draft (**Codex GPT-5.5**) elevates accuracy from **71.6% to 89.7%**—approaching top-tier solo performance at a fraction of the flagship generation cost.
2. **Weaker Reviewers Actively Degrade Strong Drafts:** Having a weaker reviewer (**Codex GPT-5.5**) review a stronger writer's draft (**Claude Opus 4.7**) causes an **8.6% pass rate drop** (91.4% → 82.8%). The weaker reviewer introduces false-positive bug reports, breaks correct logic, and over-simplifies complex implementations.
3. **Top-Tier Self-Review Yields Zero Gain:** Having a flagship model review its own unexecuted code draft produces **0.0% improvement**, consuming budget and latency without benefit.
4. **Static Review Relies on Reviewer Caliber:** In static (pre-execution) review where test runners are not executed, reviewer reasoning capability is the primary bottleneck.

---

## 2. Allnighter baseline state ("We already have most of this")

Allnighter's core architecture already aligns with these principles:

- **Pilot / Relay Loop:** Uses a strong Lead (e.g. Claude Opus) to steer and review, while fast execution seats (e.g. Grok, Composer, Codex) execute mutating work in the repo root ([AGENTS.md](file:///Users/mike/Documents/GitHub/Allnighter/AGENTS.md)).
- **Built-in Team Presets:** `BuiltInTeams.swift` sets `leadFlagship` (Fable / Opus / Codex Sol) as the synthesis lead over worker seats ([BuiltInTeams.swift](file:///Users/mike/Documents/GitHub/Allnighter/Packages/AllnighterCore/Sources/AllnighterCore/BuiltInTeams.swift)).
- **Spec Review Hero Loop:** Uses blind fan-out for critics and anchors final judgment to a flagship Synthesizer and Refutation Gate ([Spec_Review.md](file:///Users/mike/Documents/GitHub/Allnighter/docs/operations/Spec_Review.md)).

### What is Missing (The Low-Hanging Fruits)

While the default structures are sound, Allnighter currently lacks explicit guardrails against inverted relay configurations, advisory warnings for wasteful self-reviews, and pair-directionality telemetry in team run receipts.

---

## 3. Work Slices (Low-Hanging Implementation Plan)

### Slice 1: Inverted Pilot / Relay Quality Warning (`CMR-S01`)
- **Goal:** Warn users when a Relay or Pilot run is configured with an inverted role assignment (`Reviewer Caliber < Execution Seat Caliber`).
- **Mechanism:**
  - In `RelayCoordinator` / `PilotCLI` / CLI option validation, compare model caliber ranks of the designated Lead vs. the execution worker.
  - If `lead.caliber < worker.caliber`:
    Emit a non-blocking advisory warning to stdout and CLI run logs:
    ```text
    [alln warning] Inverted Pilot/Relay role assignment detected!
    Reviewer (<LeadModel>) has lower reasoning caliber than Execution Seat (<WorkerModel>).
    Empirical evidence shows reverse code review degrades code quality by up to 8.6% (arXiv:2607.21656).
    Recommended: Set Lead to a higher-caliber model than the execution worker.
    ```

### Slice 2: Flagship Self-Review Waste Advisory (`CMR-S02`)
- **Goal:** Prevent wasteful token spend when users configure a top-tier model for 2-pass self-review without execution/test runner feedback.
- **Mechanism:**
  - In `TeamRequestResolver` / `RunService.swift`, detect when a static code review run uses identical flagship models for both Writer and Reviewer seats (`Writer == Reviewer == Tier-1`).
  - Output an advisory guidance note:
    ```text
    [alln tip] Flagship self-review yields 0% pass rate gain in static review (arXiv:2607.21656).
    Consider pairing a fast worker (Codex/Composer) as Writer with <FlagshipModel> as Reviewer to achieve ~90% accuracy at reduced cost.
    ```

### Slice 3: Built-In Team Staffing Invariant Audit (`CMR-S03`)
- **Goal:** Ensure no shipped built-in team preset in `BuiltInTeams.swift` defaults to a lower-caliber Lead than any of its constituent worker seats.
- **Invariant:** For all presets in `BuiltInTeams.all`:
  $$\text{CaliberRank}(\text{Lead}) \ge \max_{w \in \text{Workers}} \text{CaliberRank}(w)$$
- **Execution:** Add unit test `BuiltInTeamsTests.testLeadCaliberDominatesWorkers()` to validate that no built-in team violates this invariant.

### Slice 4: Refuter & Synthesizer Lead Seat Locking (`CMR-S04`)
- **Goal:** Prevent the Spec Review Refutation Gate and Synthesis stage from degrading to low-tier models during fallback.
- **Mechanism:**
  - In `Spec_Review.md` contracts and `SkillCatalog.leadCallEnvelope`, explicitly lock the Refuter seat (`purpose: .review`) and Synthesizer (`purpose: .planWriter`) fallback policy to `.strongestReady` within Tier-1 / Tier-2 flagship models.
  - Require that refutation of `blocking` or `material` findings must never be performed by a lower-caliber model than the finding's author.

### Slice 5: Telemetry Pair-Directionality in Team Receipts (`CMR-S05`)
- **Goal:** Track empirical `(Writer -> Reviewer)` directional pass rates in Allnighter's local receipts.
- **Mechanism:**
  - Update `TeamRunJSON` and `ArtifactProjector.swift` to record `writer_model_id` and `reviewer_model_id` in run metadata.
  - Expose pair telemetry in `alln artifact` and team run receipts so users can inspect local pass rates for model pairings across their repository history.

---

## 4. Proof & Verification Plan

- `swift test --filter BuiltInTeamsTests`: Verify all built-in team presets pass the Lead caliber dominance invariant (`CMR-S03`).
- `swift test --filter RelayCoordinatorTests`: Verify CLI warning is correctly emitted when inverted model pairs are configured (`CMR-S01`).
- `swift test --filter ContractSchemaTests`: Verify `TeamRunJSON` includes `writer_model_id` and `reviewer_model_id` metadata (`CMR-S05`).
