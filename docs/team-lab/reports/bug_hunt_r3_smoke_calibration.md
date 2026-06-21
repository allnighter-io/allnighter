# Bug Hunt R3 — automation smoke (not quality improvement)

**Status:** calibration only — do **not** count R2→R3→R4 banked roles toward Bug Hunt quality gains.

## What happened

| Round | Champion team | Candidate team | Config delta | Verdict |
| --- | --- | --- | --- | --- |
| R3 | `code_bug_hunt` + overlay | `code_bug_hunt` | **none** | Live compare valid; variance only |
| R4 auto-promote | same | same | **none** | Incorrectly promoted (no material delta) |

Case: `gen_706f8bafe3b0edf1` (writer-consistency gate ordering).

R3 proved:

- `advance.py` orchestration
- fresh scenario + same-input compare
- live judges + autopromote machinery
- MCP run contract green

R3 did **not** prove Bug Hunt prompts improved — both arms ran the same built-in team with identical skill templates (`templateChangedFromBuiltIn: false` for every role).

## Harness fix (2026-06-21)

- `championConfigHash` / `candidateConfigHash` on compare records
- Promotion **HOLD** when hashes match: `no material candidate delta`
- `advance.py` requires `--hypotheses-from` (or `--candidate-overlay`) for quality rounds
- `--calibration-smoke` for automation-only runs (skips promotion)
- MCP `teams_definition` + overlay deploy wires lab skills into team rows (fail-hard if not)
- Promotion JSON now includes `nextRoundManifest` at write time

## Next quality-learning round

```bash
export ALLN_SCENARIO_CMD="cursor-agent -p"
export ALLN_JUDGE1_CMD="claude -p --max-turns 1"
export ALLN_JUDGE2_CMD="codex exec - --full-auto"

python3 scripts/team_lab/advance.py \
  --suite bug_hunt_repo_regressions_v1 \
  --team code_bug_hunt \
  --round 4 \
  --champion-overlay docs/team-lab/champions/bug_hunt_repo_regressions_v1/code_bug_hunt.json \
  --hypotheses-from .lab/code_bug_hunt_candidate-r3_r3_20260621_152329/evaluation/compare-record.json
```

Candidate arm will apply hypothesis patches from R3 compare to banked roles — first **material** A/B.
