# Bug Hunt Packet — Team Lab advertised MCP-only dogfooding while scoring from disk

**Date:** 2026-06-24
**Case:** `mcp_fs_bypass_scoring_v1` · Suite: `bug_hunt_repo_regressions_v1`
**Tier:** T3 — repeated *measurement* lie (the instrument could certify runs it never observed through MCP). P1 when `fsBypass=true`.
**Files of record:** `scripts/team_lab/scoring.py`, `scripts/team_lab/run.py`, `docs/phases/MCP_Run_Factory_Team_Lab.md`, `Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift`

This packet is a hand-off. The primary lie is **already fixed**; the surviving work is a ranked ladder of *trust gaps* in the fix plus a list of missing negative tests. A disciplined worker should take the top surviving hypothesis, write its negative test, and narrow down.

---

## Symptom & smallest repro

**Symptom:** A Team Lab `.lab/<exp>/` report could show `runContractScore` ≈ 1.0 and proceed to team-quality conclusions while the phase doc advertised "MCP-only factory / product dogfooding at the contract layer / the Mac app is not in the loop." An operator reading the report would believe the agent-facing MCP retrieval surface was proven healthy when it may have been incomplete — the score came off a **copied filesystem journal**, not off MCP payloads.

**Smallest repro (no Mac app, no Core import, repo-local):**
1. Build a `.lab` fixture dir with a populated `run/run.json` (or `run/workers/*.answer.md`) journal subtree but **no** `team-result.json` (or one where `mcp_artifact_status().ok` is false), plus a minimal `experiment.json`.
2. Call `score_run_contract(lab_dir, status="completed", result_ok=False, journal_copied=True, expected_run_id=run_id)` then `evaluate_team_quality(lab_dir)` — exactly as `run.py` does.
3. **Pre-fix observed:** scoring reads worker content from disk via the `load_logical_workers` journal/filesystem branches, emits a high score, no `fsBypass` signal — the report reads "MCP-only" and green.
4. **Post-fix observed (current tree):** `scoring_source="journal"`, `fsBypass=true`, `pure_mcp_scoring` check fails, `runContractScore` low (~0.11), `teamQualityWithheld=true`, `judgePending=false`. Verified by `python3 scripts/team_lab/test_scoring.py` → **12 passed** (cases `fs_bypass.detected`, `fs_bypass.team_quality_withheld`, `dropped_worker.*`).

---

## The lie (decided)

**Team Lab's measurement instrument read Core's private filesystem layout while claiming to validate the MCP contract.** Concretely, three things were simultaneously true:

1. `run.py:copy_run_journal()` **unconditionally** `shutil.copytree`-d the run journal from the hardcoded `~/Library/Application Support/Allnighter/Runs/run_<id>` after the MCP calls (`scripts/team_lab/run.py:78`, called at the `journal_copied = copy_run_journal(...)` site).
2. `scoring.py` loaders (`load_logical_workers`, `load_writer_bundle`) carried `source="journal"` and `source="filesystem"` fallback branches that could populate worker answers / writer bundle from those copied files.
3. Artifact **presence** (prompts, answers, plan) could therefore be decided by on-disk copies rather than by fields returned in the MCP `team_result` envelope — making "MCP-only dogfooding" true in the transcript/flow but false for the truth that actually gated quality.

A broken `team_result` projection could still yield a "healthy" lab run if the journal copy succeeded. *That* is the contract-layer lie: the evaluator, not SwiftUI, was the liar. The Mac app was never in this proof path (Bug Reproducer / Truth Owner Mapper / Trace Mapper all concur — no UI layer involved).

---

## Truth owner (decided)

| Truth | Owner |
|---|---|
| Worker prompt snapshots, worker answers + per-worker terminal status, writer packet markdown + status | **MCP `team_result(detail=full)` → `TeamRunJSON`** (projected from `RunStore`+`TeamRun` by `AsyncTeamService`/`TeamRunJSONMapper`). The retrieval contract the factory is meant to dogfood. |
| Requested-run identity / artifact refs | **MCP `floor_show`** — runId/refs only, **never** packet body. |
| Whether the lab may score run truth at all | **`scripts/team_lab/scoring.py::score_run_contract`** — deterministic gate, emits `fsBypass`, `runContractScore`, `teamQualityWithheld`. SSOT for admissibility. |
| Whether the lab may interpret Team *quality* | **`compare.py` two-judge blind A/B** — only on a green contract lane. No deterministic quality number exists (keyword scoring was deleted as Goodhart theater). |
| Durable run journal under Application Support | **`RunStore`** — **diff-oracle only** for the lab; not a scoring owner. |

Doc SSOT for the boundary: `MCP_Run_Factory_Team_Lab.md` "MCP-Only Law", "Truth owners", "Final packet retrieval rule", "Inference Bans", and the diff-oracle pin ("The harness reads the packet from `team_result`, never from `floor_show` text or the copied journal").

---

## The seam (why a one-side proof is a trap)

The bug crosses **MCP payloads (`alln mcp serve --stdio`) ↔ Python `.lab` reconstruction/scoring**. The adjacent-truth trap: *the copied journal can be perfectly correct while MCP retrieval is incomplete.* A test that asserts "the worker answers are all present in the `.lab` dir" passes from the journal copy and proves nothing about the MCP surface. A passing single-layer (disk) check while the MCP contract is broken is **not** proof. Any proof must assert the content arrived **through MCP frames with no Application Support read** — hence the isolation harness named below.

---

## What proof now gates team quality (current, verified)

`score_run_contract` runs nine scored checks (one unscored). Team quality is interpretable only when **all** hold:

- `fsBypass == false` ⟺ `pure_mcp_scoring` ok ⟺ `mcp_artifact_status(team-result.json).ok` true (`scoring.py:176,210`). This is the anti-lie gate.
- `runContractScore >= 0.95` (9 scored checks; `journal_copied_for_diff` is `scored:false`, zero weight — `scoring.py:211`).
- `status == "completed"`.
- `mcp_worker_prompts` (≥1 `resolvedWorkerPromptSnapshot`), `mcp_worker_answers` (≥1 answer), `mcp_plan_markdown` (writer bundle non-empty).
- `mcp_worker_status`: `nonPlanWorkerCount > 0 ∧ statusedAnswerCount == nonPlanWorkerCount ∧ writerStatusPresent` — a hidden/dropped answer worker fails this.
- `mcp_worker_nonempty`: every non-plan answer non-empty.
- `floor_show_run_id`: `floor-show.json` runId matches expected (`scoring.py:209`).

Then `team_quality_withheld = fsBypass or status != "completed" or runContractScore < 0.95` (`scoring.py:218`), and `evaluate_team_quality` sets `judgePending = not teamQualityWithheld` (`scoring.py:325`). Downstream, `compare.py` refuses to judge on `fsBypass` or low contract; `promote.py` requires `evidenceValid=true`, `judgeMode=live`, unanimous per-worker banks.

---

## Ranked hypothesis ladder (surviving trust gaps, most-likely first)

The primary lie is fixed. These are the surviving ways the fix could still mislead, ranked by likelihood × impact. Each row carries forward what is **already ruled out** so the next round never re-litigates it.

### H1 — `mcp_worker_status` / writer-status corner cases are under-tested (most likely live gap)
The check is real but the test matrix is thin: a run with workers present but **writer status absent** isn't independently exercised; nor is "strong `plan.markdown` masking a `status=timeout` worker."
- **Cheapest experiment:** `make_lab(non_plan_workers=2, writer_status="")` → assert `mcp_worker_status` check `ok=false`, contract `<0.95`, `teamQualityWithheld=true`. Separately `make_lab(... one workerAnswers[].status="timeout")` → assert nonempty/status fails.
- **Rules out:** "completed run ⇒ complete artifacts" inference-ban regressions; the "strong writer hides a dead worker" failure mode.

### H2 — `floor_show_run_id` mismatch is never asserted as a *failing* negative
`runRef(from:)` was hardened to accept both `run` and `runId` (`AllnighterCLI.swift:1093-1094`), and `run.py` calls `floor_show({"run": run_id})` — so the **defeat-via-key-mismatch** path is **RULED OUT in-tree** (refutes CFP H1, see Contradictions). Residual: `test_scoring.py` always passes `expected_run_id` equal to the planted runId, so no test proves the check *can* fail; and `scoring.py:209` masks via `or not expected_run_id` when a caller passes `None`.
- **Cheapest experiment:** `score_run_contract(..., expected_run_id="DIFFERENT-RUN")` with `floor-show.json` runId `"TEST-RUN"` → assert check `ok=false`. Plus a Swift unit test `testRunRefAcceptsRunOrRunIdAlias` to pin the resolver against regression. Decide whether `expected_run_id=None` should fail rather than silently pass.
- **Rules out:** cross-run contamination passing by accident; silent "latest" drift if a future caller mixes key conventions.

### H3 — journal/filesystem fallback branches are live but untested dead code
`load_logical_workers` (`scoring.py:114-149`) and `load_writer_bundle` (`scoring.py:160-162`) still contain `source="journal"`/`"filesystem"` branches.
- **Already ruled out:** these branches **cannot** make a run judgeable — `evaluate_team_quality` gates `judgePending` on `contract.teamQualityWithheld`, which is true whenever `fsBypass=true` (`scoring.py:325`). So CFP H2's "judgePending could be True despite fsBypass" is **REFUTED**.
- **Residual risk:** untested code rots; a future refactor could wire a fallback source into a *scored* path without a test catching it.
- **Cheapest experiment:** fixture with no `team-result.json` + populated `run/run.json` → assert `load_logical_workers` returns `source="journal"` **and** `evaluate_team_quality.judgePending == false`. Add the symmetric `run/workers/*.answer.md` `source="filesystem"` case. (Lowest priority: harmless today, guards tomorrow.)

### H4 — `scoring_source="none"` path (result_ok false, journal not copied) untested
No test exercises the path where `team_result` parse fails **and** no journal exists.
- **Cheapest experiment:** `score_run_contract(..., result_ok=False, journal_copied=False)` → assert `scoringSource="none"`, `runContractScore<0.95`, `teamQualityWithheld=true`. Cheap; closes a coverage hole.

---

## Smallest correct fix for the top surviving hypothesis (H1)

**Boundary: add tests only.** Do **not** touch `score_run_contract` logic — the gate is correct. In `scripts/team_lab/test_scoring.py`, extend `make_lab` to parameterize `writer_status` and per-worker `status`, and add the two H1 cases. No production code change, no journal-copy removal (keep it as diff-oracle), no Core import into the lab scripts. If H1 tests reveal the check is actually wrong (not expected), *then* and only then patch `mcp_artifact_status`/`score_run_contract`.

---

## Proof method (what decides "fixed")

- **Existing regression proof (passes now):** `python3 scripts/team_lab/test_scoring.py` → 12/12, including `fs_bypass.detected`, `fs_bypass.team_quality_withheld`, `dropped_worker.*`.
- **Per-hypothesis proof:** each ladder rung's "cheapest experiment" is a new `test_scoring.py` case (H1, H2-python, H3, H4) plus one Swift unit test (H2-swift).
- **The proof that cannot be written in the current harness** (a passing disk check is not proof of MCP truth — the seam trap): a **minimal isolation harness** must be authored —
  **`scripts/team_lab/harness_mcp_reconstruct.py`** + committed MCP transcript fixtures (JSON-RPC frames: `mcp_hello`, `team_preflight/start/status/result`, `floor_show`). It rebuilds a `.lab` record **from MCP frames only**, with `copy_run_journal` never invoked and zero Application Support reads, then runs score/evaluate/report and asserts `fsBypass=false`, `scoringSource="mcp"`, `runContractScore>=0.95`, quality not withheld. Success must be readable in the generated `report.md`. This is the only artifact that proves reconstruction is *exclusively* MCP even when a perfect journal copy is present.
- **GUI proof: N/A** — headless MCP/run-contract bug; the phase doc excludes the Mac app. Visible proof = the lab report + MCP transcript, not a SwiftUI fixture.

---

## Negative tests still missing (deduped union, by owner)

**`test_scoring.py`:**
1. Writer status absent with answer workers present → `mcp_worker_status` fails. *(H1)*
2. Good `plan.markdown` + one `workerAnswers[].status="timeout"`/missing → `mcp_worker_status`/`mcp_worker_nonempty` fails. *(H1)*
3. `floor_show_run_id` mismatch — `expected_run_id="DIFFERENT-RUN"` → check fails. *(H2)*
4. Partial MCP: `team-result.json` present but missing `resolvedWorkerPromptSnapshot` or empty `plan.markdown` while journal is complete → must withhold, no journal rescue. *(H1/H3)*
5. Journal-only and filesystem-only fallback → `source="journal"`/`"filesystem"` **and** `judgePending==false`. *(H3)*
6. `scoring_source="none"` (`result_ok=False`, `journal_copied=False`) → low contract, withheld. *(H4)*
7. Writer text claims `fsBypass=false` while contract recorded `fsBypass=true` → `check_writer_consistency` flags it (no dedicated case today).

**Swift / MCP contract:**
8. `testRunRefAcceptsRunOrRunIdAlias` — pin `runRef` against silent "latest" drift. *(H2)*
9. Schema/parity test that fails the build if `team_result(detail=full)` stops emitting any scorer-required field (`resolvedWorkerPromptSnapshot`, `workerAnswers[].status`+`.markdown`, `plan.status`+`.markdown`).
10. End-to-end negative against a live MCP server: one `workerAnswers[].status=""` among complete workers → `mcp_worker_status` fails.

**Pipeline / CI:**
11. `compare.py` / `advance.py` refuse on `fsBypass=true` **or** `runContractScore<0.95` (only same-input refusal is covered today); independently test `materialCandidateDelta=false` early-return.
12. Static lint: `scripts/team_lab/` never imports `AllnighterCore` / calls `TeamService` (inference ban: app-ready ≠ MCP-ready).
13. Green-wall entry runs `test_scoring.py` (+ new fixtures) on every slice — currently manual.
14. Seeded regression E2E: execute meta cases `mcp_fs_bypass_scoring_v1` and `floor_show_wrong_run_v1` as real runs (doc still lists "no Bug Hunt regression benchmark with seeded known failures yet").

**Substrate (blocked on projection work — SUB-1/2/3):**
15. MCP-verifiable completion ordering (`completedAt` before synthesis; stage timestamps) — needs `TeamRunJSONMapper` to project stage payload first.
16. Live two-judge path (`ALLN_JUDGE1_CMD`/`ALLN_JUDGE2_CMD` on real provider CLIs) — mock judges prove orchestration only (`evidenceValid=false`).

---

## Contradictions resolved (do not average)

- **Correct Fix Planner H1 — "`floor_show_run_id` is structurally defeatable; `runRef` accepts only `run` → ref always `latest`": REFUTED.** Verified `AllnighterCLI.swift:1093-1094` accepts both `run` and `runId` (with a comment explicitly guarding "silent latest drift when callers mix conventions"), and `run.py` calls `floor_show({"run": run_id})`. The three untracked `2026-06-24-floor-show-runid-*` debugger docs indicate this was a live bug **already fixed today**. Surviving residual (the missing *failing* negative test + the `or not expected_run_id` mask) is retained as **H2**, not the original defeat claim.
- **Correct Fix Planner H2 — "fallback could set `judgePending=True` despite `fsBypass=True`": REFUTED.** `scoring.py:325` gates `judgeable` on `contract.teamQualityWithheld`, which is true under `fsBypass`. Demoted to **H3** (untested dead code, harmless today).
- **Consensus upheld:** the `fsBypass`/`pure_mcp_scoring` gate has landed and `test_scoring.py` passes 12/12 (independently re-run). All seats agree the truth owner is `team_result(detail=full)` and the missing piece is committed negative fixtures + an MCP-only isolation harness.

## Dissent preserved (minority positions kept)

- **Deleting the ~0.725 keyword evaluator was correct** (Truth Owner Mapper): it rewarded template words the prompts already mandate — Goodhart theater. Quality rightly moved to blind judges. Recorded so a future round does not "restore the score."
- **The journal copy should stay** (Truth Owner Mapper, Bug Reproducer): valuable as a diff-oracle to compare MCP projection vs `RunStore` ground truth and surface substrate bugs (SUB-1..4). Do not delete it; only forbid it from any *scored* path.
- **A green run contract does NOT prove Bug Hunt diagnosis is correct** (Truth Owner Mapper): judges evaluate artifacts, not outcomes. Verifiable seeded cases (test #14) remain required to confirm "judges' better" tracks reality.

## Dropped (specialist carry law)

- **Correct Fix Planner's CWD/ProbeScratch spawn table** (`WorkerRunner.swift:166`, `WorkerImageInvoker.swift:85`, `UtilizationSeedExecutor.swift:73`, `CLIDetector.swift:33,117`, `ModelHealthChecker.swift:32`, `DirectModeExposureProvider.swift:300,412`): single-seat, and tangential to the MCP-dogfood scoring lie (worker process CWD ≠ lab scoring truth). Dropped as out-of-boundary for this packet; revisit only if a worker is found writing into a user repo from the lab path.

---

## Danger flags

**None blocking.** No credentials, no deletion outside boundary, no deploy, no billing. The recommended fix is test-only additions + one new isolation-harness script. `copy_run_journal` performs `shutil.rmtree(dest)` on the **`.lab/<exp>/run`** sub-path only (not Application Support) — safe, but any edit there must preserve that boundary. An auto-attempt of the H1 fix (adding tests) is **safe to dispatch**.

```fix-packet
seam: "alln mcp serve --stdio (team_result/floor_show payloads) <-> scripts/team_lab .lab reconstruction & scoring"
truthOwner:
  retrieval: "MCP team_result(detail=full) -> TeamRunJSON (AsyncTeamService/TeamRunJSONMapper); floor_show owns runId/refs only"
  runTruthGate: "scripts/team_lab/scoring.py::score_run_contract (fsBypass / runContractScore)"
  quality: "compare.py two-judge blind A/B on green contract only; no deterministic quality score"
  journal: "RunStore under ~/Library/Application Support/Allnighter — diff-oracle only, never a scoring owner"
theLie: "Team Lab could score artifact presence from a copied Application Support journal (run.py copy_run_journal + scoring.py journal/filesystem fallback loaders) while advertising MCP-only dogfooding; the evaluator was the liar, not the UI."
status: "PRIMARY LIE FIXED — fsBypass/pure_mcp_scoring gate landed (scoring.py:176,210,218); test_scoring.py 12/12 green."
rankedHypotheses:
  - id: H1
    claim: "mcp_worker_status / writer-status corner cases under-tested (writer-status-absent-with-workers; strong-writer-masks-timeout-worker)"
    experiment: "test_scoring.py: make_lab(writer_status='') + make_lab(one workerAnswers[].status='timeout') -> assert mcp_worker_status/nonempty fail, contract<0.95, withheld"
    fix: "add parameterized negative cases to test_scoring.py only"
    fixBoundary: "scripts/team_lab/test_scoring.py (and make_lab helper). No production logic change unless a test proves the check itself wrong."
    rulesOut: "completed!=complete inference-ban regressions; strong-writer-hides-dead-worker"
  - id: H2
    claim: "floor_show_run_id mismatch never asserted as a failing negative; expected_run_id=None silently passes (scoring.py:209)"
    experiment: "score_run_contract(expected_run_id='DIFFERENT-RUN') -> check ok=false; + Swift testRunRefAcceptsRunOrRunIdAlias"
    fix: "add negative test; decide whether expected_run_id=None should fail"
    fixBoundary: "test_scoring.py + a Swift unit test pinning AllnighterCLI runRef. Resolver itself already correct (accepts run+runId)."
    rulesOut: "cross-run contamination by accident; silent latest-drift on mixed key conventions"
  - id: H3
    claim: "journal/filesystem fallback branches in load_logical_workers/load_writer_bundle are live but untested dead code"
    experiment: "fixture: no team-result.json + run/run.json -> source=='journal' AND evaluate_team_quality.judgePending==false"
    fix: "add fixture asserting fallback never reaches a scored path / never sets judgePending under fsBypass"
    fixBoundary: "test_scoring.py only. Do NOT delete the fallback (kept harmless) unless a refactor wires it into scoring."
    rulesOut: "future refactor silently scoring from a fallback source"
  - id: H4
    claim: "scoring_source='none' path (result_ok=False, journal_copied=False) untested"
    experiment: "score_run_contract(result_ok=False, journal_copied=False) -> scoringSource='none', contract<0.95, withheld"
    fix: "add coverage case"
    fixBoundary: "test_scoring.py only"
    rulesOut: "silent green contract when both MCP and journal absent"
proofMethod:
  existing: "python3 scripts/team_lab/test_scoring.py (12/12; fs_bypass.* + dropped_worker.* are the failing-before/passing-after kill tests)"
  required_isolation_harness: "scripts/team_lab/harness_mcp_reconstruct.py + committed MCP transcript fixtures — rebuild .lab from MCP frames only, copy_run_journal never invoked, zero Application Support reads; assert fsBypass=false, scoringSource='mcp', runContractScore>=0.95, quality not withheld; success readable in report.md"
  note: "A passing disk-only check is NOT proof of MCP truth (seam trap)."
ruledOut:
  - "CFP H1 (runRef accepts only 'run' -> floor_show defeatable): REFUTED — AllnighterCLI.swift:1093-1094 accepts run+runId; run.py passes {'run':run_id}; fixed today (2026-06-24-floor-show-runid-* docs)."
  - "CFP H2 (judgePending could be True despite fsBypass): REFUTED — scoring.py:325 gates judgeable on contract.teamQualityWithheld which is true under fsBypass."
  - "Primary disk-scoring lie: FIXED — fsBypass/pure_mcp_scoring gate landed; 12/12 green."
  - "UI/SwiftUI as liar: REFUTED — Mac app not in lab proof path (MCP-Only Law)."
dangerFlags: []
autoAttemptSafe: true
dropped:
  - "CFP CWD/ProbeScratch spawn table (WorkerRunner.swift:166 et al): single-seat, tangential to scoring lie — out of boundary."
```
