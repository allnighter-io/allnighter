# Bug Hunt — baseline r1

Team: `code_bug_hunt` · Suite: `bug_hunt_repo_regressions_v1` · Case: `composer_paste_dead_v1`

**Experiment:** `.lab/code_bug_hunt_baseline_r1_20260621_060907`
**Run:** `766A934D-443C-4602-BD8E-AA04B5F072BE` · ~11.9 min · 8 answer/review workers + writer

## Scorecard

| Metric | Value |
| --- | --- |
| Run contract | **1.0** (`fsBypass=false`, all 9 checks ok incl. `mcp_worker_status`) |
| Scoring source | `mcp` (journal diff-oracle only) |
| Team quality | **judge-pending** — the heuristic (0.725) was deleted as theater; quality now decided by the two-judge blind A/B (`compare.py`). See § Judge Loop. |
| Writer consistency | 0 issues |

## Packet verdict (human)

Strong and fix-useful: T3 classification, truth owner (`RoutingComposer.text` binding),
lie-prone layer (pasteboard read), hypothesis ladder, kill tests requiring real
clipboard sources, proof boundary, and an explicit "do not patch yet." The writer
**preserved dissent and demoted the 7-worker binding-clobber majority** in favor of
the contrarian's stronger falsifier (typing uses the same insert path). That judgment
chain is exactly what Bug Hunt exists to do.

## Lab hardening landed from this baseline (no team mutation)

The baseline exposed lab defects, not just team behavior. Fixed in `scripts/team_lab/`:

1. **Evaluator ordering bug** — `evaluate_team_quality` ran before `experiment.json`
   was written, so the writer stale-claim check was silently disabled. `run.py` now
   writes `experiment.json` before evaluation.
2. **Worker-status guard** — new `mcp_worker_status` run-contract check asserts every
   non-plan worker has a `workerAnswers[].status` and writer status is present; a
   dropped/hidden worker now fails the contract and **withholds** team quality.
3. **Team-quality gate** — withheld when `runContractScore < 0.95` (was only on
   `fsBypass` / not-completed), matching the spec's stated gate.
4. **Label clarity** — reports now say answer/review workers are judged by
   `compare.py`; evaluation only records truth facts.
5. **Evaluator kill tests** — `scripts/team_lab/test_scoring.py` proves the truth
   evaluator fails a hidden-worker run, an empty answer, a stale-claim writer, and an
   `fsBypass` run. Run before trusting any evaluator change.

## Confirmed substrate bugs (filed for the substrate dev)

See `docs/phases/Team_Lab_Run_Factory.md` § Confirmed Substrate Bugs: SUB-1
`completedAt` predates synthesis (`TeamRunJSONMapper.swift:74-86`); SUB-2 stage
markdown/timestamps + `plan.status` not projected; SUB-3 `workerAnswers[].finishedAt`
not serialized; SUB-4 `floor_show.summaryMarkdown` empty. None hide a worker or
corrupt a run id (P2/P3), so the baseline remains interpretable — but completion
ordering can't be MCP-verified until SUB-1/2/3 land.

## Next (for the dev running it)

1. Finish the two substrate cases `mcp_fs_bypass_scoring_v1`, `floor_show_wrong_run_v1`.
2. Keep Bug Hunt baseline immutable until 2–3 cases × N≥3 show repeatability.
3. Do **not** mutate `TeamCatalog` from any deterministic quality score; quality has
   no score and must go through live blind A/B.
4. Treat any future run that fails `mcp_worker_status` as a substrate stop, not a team result.
