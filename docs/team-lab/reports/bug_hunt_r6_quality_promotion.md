# Bug Hunt R6 — quality promotion closeout

**Status:** accepted · first **quality** promotion after harness fixes (2026-06-22).

## Green run dirs (local `.lab/`, gitignored)

| Arm | Dir |
| --- | --- |
| Champion | `.lab/code_bug_hunt_champion-r6_r6_20260622_175524` |
| Candidate | `.lab/code_bug_hunt_candidate-r6_r6_20260622_181258` |
| Case | `gen_5dc28030c4fb97d7` |

Contract: **1.0** both arms · worker failures: **zero** both arms.

## Live compare gates (verified)

| Gate | Value |
| --- | --- |
| `judgeMode` | `live` |
| `evidenceValid` | `true` |
| `sameInput` | `true` |
| `materialCandidateDelta` | `true` |
| `unmatchedRoles` | `[]` |
| `interactionWarning` | `false` |
| `deliverableOutcome` | `candidate` |

Judges: `claude -p --max-turns 1` + `codex exec - --full-auto` (non-AGY).

**Banked roles (both judges agree):** `correct_fix_planner#0`, `state_skeptic#0`, `contrarian_root_cause#0`.

Full per-role verdicts: `.lab/code_bug_hunt_candidate-r6_r6_20260622_181258/evaluation/compare.md`.

## Champion outcome

Overlay advanced to **R7** (`promotionClass: quality`, `degradedWin: false`, `confirmRequiredNextRound: false`).

Durable SSOT: `docs/team-lab/champions/bug_hunt_repo_regressions_v1/code_bug_hunt.json`.

Promotion manifest (local only): `.lab/promotions/next_round_r7_code_bug_hunt.json`.

## R7 direction

Use R6 `compare.md` idea-engine hypotheses on **incumbent** roles that lost (reproducer, trace mapper, regression guard, truth owner mapper). Keep R6 banked roles unchanged. See `docs/team-lab/candidates/bug_hunt_repo_regressions_v1/code_bug_hunt_r7.json`.
