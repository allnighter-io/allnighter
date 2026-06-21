# Spec Upgrade — Round 1 (baseline)

**Experiment:** `.lab/code_spec_upgrade_baseline_r1_20260621_045307`  
**Run:** `14C29DD9-99F0-473B-8350-B8F453BA01F7`  
**Duration:** ~9.4 min  
**Run contract score:** 0.714 (harness path bugs; not team quality)

## Verdict

**Team quality: strong (≈8/10 for this case).** The packet correctly identified P1 MCP substrate gaps and gave actionable spec recommendations. Multi-model diversity worked — workers cited real repo paths (`MCPAsyncTeamHandlers`, `run.py`, `FloorProjector`).

## What helped

| Worker | Model | Contribution |
|--------|-------|----------------|
| First Principles (Opus) | claude | Truth-owner inversion (FS vs MCP), smallest slice |
| Contract Auditor | Gemini | `detail:"full"` ignored, `localOnly` refs |
| Proof Planner | Composer | Proof commands vs aspirational `alln dev team-lab` |
| Contrarian | Gemini | Holdout discipline, scalar hype |
| Writer (Opus) | claude | Synthesized PRE-S0 blocking slice, preserved dissent |

## Substrate bugs found (fixed in round 2 prep)

1. **P1:** `team_result` ignored `detail:"full"` — MCP could not return prompt snapshots.
2. **P2:** `team_status` lacked `workersDone`/`workersTotal` (docs promised them).
3. **P2:** Lab harness used NDJSON not Content-Length framing (hung prior runs).
4. **P2:** Harness looked for `worker_answers/` but journal uses `workers/*.answer.md`.

## Round 2 variables

- MCP `team_result(detail=full)` fix
- Worker evidence contract in Spec Upgrade skills
- Harness contract scoring for FS bypass vs MCP prompts
