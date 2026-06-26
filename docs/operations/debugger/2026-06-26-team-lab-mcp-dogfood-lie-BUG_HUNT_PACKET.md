# Bug Hunt Packet: Team Lab MCP Dogfood Lie (fsBypass / Copied Journal Scoring)

**Date:** 2026-06-26  
**Case:** `mcp_fs_bypass_scoring_v1` (and related) · Suite: `bug_hunt_repo_regressions_v1`  
**Tier:** T3 (measurement instrument lie). P1 impact on any Team quality conclusion drawn while `fsBypass=true`.  
**Primary files:** `scripts/team_lab/run.py`, `scripts/team_lab/scoring.py`, `docs/phases/MCP_Run_Factory_Team_Lab.md`, `Packages/AllnighterCore/Sources/AllnighterCLI/MCPAsyncTeamHandlers.swift`, `TeamRunJSONMapper.swift`, `RunStore.swift`  
**Related packets:** `2026-06-24-team-lab-mcp-dogfood-lie-PACKET.md`, `2026-06-23-team-lab-mcp-dogfood-proof-gap.md`

## Executive Summary

The harness advertised "MCP-only factory" / "product dogfooding at the contract layer" / "the Mac app is not in the loop" while the scoring path could (and historically did) source worker prompts, answers, and writer content from a direct filesystem copy of `~/Library/Application Support/Allnighter/Runs/run_<id>` (and raw `workers/*.md` files) instead of exclusively from the MCP `team_result(detail=full)` payload.

The "UI" that displayed unowned truth was not SwiftUI — it was the lab's own evaluation layer (`evaluate_team_quality`, `write_lab_report`, the resulting `report.md`, and any downstream `compare`/`promote` decisions that trusted the artifacts).

## What Was the Lie?

1. `run.py:copy_run_journal()` (still present today at line 421) unconditionally does:
   ```python
   support = Path.home() / "Library/Application Support/Allnighter"
   src = support / "Runs" / f"run_{run_id}"
   ...
   shutil.copytree(src, dest)  # to .lab/<exp>/run/
   journal_copied = copy_run_journal(...)
   ```
2. `scoring.py` loaders had (and retain as fallback) journal/filesystem branches:
   - `load_logical_workers`: prefers `team-result.json`, else `run/run.json`, else `run/workers/*.answer.md` (labels `source: "journal"` / `"filesystem"`).
   - `load_writer_bundle`: prefers team-result plan, falls back to `run/bundle.md` / `master_plan.md`.
3. Before the `mcp_artifact_status` + `fsBypass` / `pure_mcp_scoring` / `teamQualityWithheld` gates landed, a run could be scored "green" and fed to judges even if `team_result` was incomplete or absent — the copied journal supplied the content.
4. The contract narrative ("retrieve ... through MCP", "MCP is the retrieval owner", "journal copy ... diff-oracle only") and the implementation were not aligned. The evaluator (scoring/report) was the liar.

A broken `team_result` projection (or missing worker prompt/status fields) could still produce an apparently successful lab record because the FS copy was always there as a rescue.

## What Is the Truth Owner?

| Truth | Owner (current) | Notes |
|-------|-----------------|-------|
| Worker prompt snapshots, `workerAnswers[]` (markdown + status), `plan` (markdown + status) for scoring | MCP `team_result(detail=full)` → `TeamRunJSON` | Produced by `MCPAsyncTeamHandlers.result` calling `AsyncTeamService.result` → `RunStore.load` → `TeamRunJSONMapper.map(..., full=...)` |
| Run identity + artifact *refs* (never the packet body) | `floor_show` via `FloorProjector` | SUB-4: `summaryMarkdown` often empty on completed runs |
| Whether the lab run is admissible for Team quality | `scripts/team_lab/scoring.py::score_run_contract` | Emits `fsBypass`, `scoringSource`, `runContractScore`, `teamQualityWithheld`, `pure_mcp_scoring` check |
| Quality judgment (no deterministic number) | `compare.py` two blind LLM judges (different families) | Only called when `!fsBypass && runContractScore >= 0.95 && completed` |
| Durable run state (single source) | `RunStore` (run.json + atomic terminal artifacts) | Lab must not read it directly; copy is kept only as diff-oracle |
| Lab experiment record | `.lab/<exp>/experiment.json` + `evaluation/*.json` | Written from MCP transcripts + evaluation gates |

**Inference ban:** "App (or local journal) can run it" ≠ "MCP surface returned the truth." The lab is forbidden from importing AllnighterCore or reading Application Support for *scored* facts.

## What Proof Now Gates Team Quality?

In `score_run_contract` (scoring.py:169+):

Scored checks (all must contribute to >= 0.95):
- `terminal_status` (completed/failed/cancelled/interrupted)
- `team_result_retrieved`
- `mcp_worker_prompts` (>0 snapshots)
- `mcp_worker_answers` (>0)
- `mcp_worker_status`: `nonPlanWorkerCount > 0 && statusedAnswerCount == nonPlanWorkerCount && writerStatusPresent`
- `mcp_worker_nonempty`
- `mcp_plan_markdown`
- `floor_show_run_id` (or no expected id)
- `pure_mcp_scoring` (`not fs_bypass`)

Unscored (for diff/debug only):
- `journal_copied_for_diff`

Then:
```python
fs_bypass = scoring_source != "mcp"
team_quality_withheld = fs_bypass or status != "completed" or run_contract_score < 0.95
```
`evaluate_team_quality` sets `judgePending = not withheld`.

Downstream:
- `compare.py:49` early-returns `False, "fsBypass=true"`
- `genesis.py`, `macro_*`, `promote.py` also key off `fsBypass` + contract >= 0.95
- Report always prints `Scoring source: ... (fsBypass=...)`

`mcp_artifact_status` (scoring.py:39) is the pure-MCP oracle that decides `ok`.

## Places the "UI" (Evaluator / Report / Judges) Displayed Truth It Did Not Own

- `load_logical_workers` / `load_writer_bundle` returning journal or FS content while the narrative said "MCP retrieval".
- `evaluate_team_quality` packaging `workerFacts` and `writerPresent` from non-MCP sources when `fsBypass` would later (or previously did) allow `judgePending`.
- Report + any human/automation reading it treating a high `runContractScore` as proof the MCP surface was complete.
- (Broader system parallel, lower severity for this packet): `ThreadsViewModel.teamRun` + `RunDecodeCache` is a terminal-run snapshot for perf. It is read-only, invalidated, and backed by `RunStore.load`; it is not a source of *different* truth. It would become a problem only if a view used the cache without invalidation or read raw FS beside the store.

Duplicated / drifted state observed:
- Run journal (`run.json`) + derived FS artifacts (`workers/`, `bundle.md`) written by `RunStore.save` on terminal.
- Projection layers (`TeamRunJSON` via mapper for `team_result`/`show`; `FloorRun` via `FloorProjector` for `floor_show`).
- Status mappers (`AsyncTeamStatusMapper.liveStatus`) vs full result.
- `completedAt` in mapper = max worker `finishedAt` (pre-synthesis) — SUB-1.
- `stages[]` in `TeamRunJSON` omit markdown/timestamps that exist internally — SUB-2.
- `workerAnswers[].finishedAt` not serialized — SUB-3.
- `floor_show.summaryMarkdown` empty while `team_result.plan.markdown` has the body — SUB-4.

Optimistic / stale risks:
- Non-terminal runs rely on live owner.pid + orphan recovery on load (never write on read).
- Status polling sees `team_status` projection; full truth only on terminal `team_result`.
- If a resident coordinator or another process mutates the journal after an MCP stdio process has returned a snapshot, a late `team_result` could differ (the per-root write lock + single-writer journal are meant to prevent this for execution teams).

Missing persistence (projection gaps that starve the scorer):
- Without `resolvedWorkerPromptSnapshot` on full, `mcp_worker_prompts` fails.
- Without `workerAnswers[].status` for every non-plan, `mcp_worker_status` fails (hiding failures was exactly the scenario the check was added to catch).
- Without `plan.status` + `plan.markdown`, writer checks fail.

## Negative Tests Still Missing (or Incomplete)

Current `test_scoring.py` (12/12 green) covers good path, partial answers (dropped), empty content, stale writer claims, and basic fsBypass (no team-result + journal_copied).

**Still missing / thin (ranked by the prior packets):**

1. **H1 (most likely live gap):** Writer status absent while answer workers present.
   - `make_lab(..., writer_status="")` (or `None`) → `mcp_worker_status` fails, contract <0.95, withheld.
   - Good `plan.markdown` + at least one `workerAnswers[].status` missing or `"timeout"` among non-plan workers → same failure.

2. **H2:** `floor_show_run_id` mismatch asserted as failure.
   - `score_run_contract(..., expected_run_id="WRONG-ID")` with floor showing correct id → check `ok=false`.
   - `expected_run_id=None` should perhaps not silently pass the check.

3. **H3/H4 coverage:**
   - No `team-result.json` + full `run/run.json` → `load_logical_workers` yields `source="journal"` AND `judgePending == false` (via contract gate).
   - `result_ok=False, journal_copied=False` → `scoringSource="none"`, low score, withheld.
   - `team-result.json` present but missing `resolvedWorkerPromptSnapshot` or empty plan while journal is lush → still withholds (no rescue).

4. **Isolation harness (the seam trap):** `scripts/team_lab/harness_mcp_reconstruct.py` + committed transcript fixtures (pure JSON-RPC frames for hello/preflight/start/status/result/floor). Rebuilds `.lab` with `copy_run_journal` *never called* and zero reads of Application Support / real RunStore. Asserts `fsBypass=false`, `scoringSource="mcp"`, `runContractScore>=0.95`, report says quality judge-pending, success readable by non-coder. (This does not exist yet.)

5. **Contract parity (Swift):**
   - Unit test that `TeamRunJSON` (full) always contains the scorer fields when a completed run has them internally: `workers[].resolvedWorkerPromptSnapshot`, `workerAnswers[].status` + `.markdown`, `plan.status` + `.markdown`.
   - Negative: a completed run with one answer worker lacking status must produce a `team_result` that makes `mcp_worker_status` false.

6. **Pipeline / promotion gates:**
   - `compare.py` / `advance.py` / `promote.py` refuse (or mark `evidenceValid=false`) on `fsBypass` or contract <0.95 even when judge records or overlays are supplied.
   - Green-wall / CI target runs `python3 scripts/team_lab/test_scoring.py` (and future harness) on every slice.

7. **Stale / drifted snapshot negatives (broader):**
   - A seeded case where synthesis finishes after the last worker answer (proves SUB-1 `completedAt` drift visible over MCP).
   - `floor_show` vs `team_result` divergence on the same run id (packet body lives only in one).

8. **Static hygiene (inference ban):**
   - Lint or test that `scripts/team_lab/*.py` never `import AllnighterCore` or resolve a RunStore path for facts used in scoring.

## Current State of the Fix (verified)

- Primary lie fixed: `fsBypass` / `pure_mcp_scoring` gate + withholding landed; `journal_copied_for_diff` has `scored: false`.
- `test_scoring.py` kills the old happy path that used disk.
- `copy_run_journal` and the fallback loaders are intentionally retained as diff-oracle / debug surface (do not delete without new MCP artifact tools).
- `mcp_worker_status` check exists to prevent "failed workers hidden because writer succeeded."
- `run.py` still copies (for diff), writes `team-result.json` from MCP first, then scores.
- `report.py` surfaces the source and bypass flag.

## Remaining Work (ranked)

1. Add the H1/H2/H3/H4 negative cases to `test_scoring.py` (cheap, high value).
2. Author the isolation `harness_mcp_reconstruct.py` + fixtures (the only thing that proves "MCP alone is sufficient").
3. Wire scoring tests + the harness into an automated target (green wall or `scripts/check.sh` team-lab slice).
4. Add the Swift mapper parity test (so a projection regression cannot starve the scorer silently).
5. Decide + test the `expected_run_id=None` behavior for the floor check.
6. Close SUB-1/2/3 projection gaps so the lab can verify completion ordering and per-worker finishedAt over MCP (blocked on mapper work).
7. Seed the meta regression cases (`mcp_fs_bypass_scoring_v1`) as actual Bug Hunt runs that must stay green-contract.

## Proof Commands

```bash
python3 scripts/team_lab/test_scoring.py
# (after new cases) expect 16+/N or whatever the expanded matrix yields

python3 scripts/team_lab/test_mcp_floor_show_run_id.py   # already exercises selector parity

# When harness exists:
python3 scripts/team_lab/harness_mcp_reconstruct.py --fixture scripts/team_lab/fixtures/mcp_complete_run.jsonl
# Must emit report.md with fsBypass=false, scoringSource=mcp, contract>=0.95, quality not withheld.

# Remove team-result.json from a good lab dir and re-evaluate:
python3 scripts/team_lab/evaluate.py /path/to/lab --rescore-contract
# Must flip to fsBypass=true and withhold even though .lab/run/ is intact.
```

## Dissent / Notes Preserved

- The journal copy **should stay** for diff-oracle work (comparing MCP projection vs RunStore ground truth surfaces SUB-1..4).
- No deterministic quality score is correct (Goodhart on template language).
- A green contract proves the *run system told the truth to the caller*; it does not prove the diagnosis in the packet is correct. Verifiable seeded cases remain necessary.
- The Mac app / SwiftUI was never the liar for this path (MCP-only law).

## Danger Flags

None blocking for adding tests. `copy_run_journal` only touches the `.lab/<exp>/run` subtree (rmtree + copytree on a lab-owned path). Adding cases or a pure-MCP harness script does not touch credentials, production paths, or distribution.

---

**End of packet.** The lie was "our measurement said MCP dogfood while the instrument could pass from disk." The current gate makes the claim enforceable; the missing negatives and isolation harness are what make the enforcement *proven* rather than asserted.
