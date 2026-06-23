# 2026-06-23 - Team Lab MCP Dogfood Proof Gap

Status: Bug Hunt packet and proof plan. No runtime fix in this slice.

## Executive Verdict

The Team Lab advertised MCP-only dogfooding while the historical harness also
copied run journals from:

```text
~/Library/Application Support/Allnighter/Runs/run_<id>
```

That copy is not itself the lie. The lie is allowing a copied journal or disk
artifact presence to stand in for MCP retrieval truth while drawing Team-quality
conclusions. The current spec and scorer now draw the right boundary:

- `team_result(detail=full)` owns packet, worker answer, worker prompt, and
  writer status truth.
- `floor_show` may prove the requested run id and artifact refs, but not the
  final packet body.
- `.lab/<experiment>/run/` is a diff/debug oracle only.
- If scoring falls back to the copied journal, `fsBypass=true` and Team quality
  is withheld.

The remaining gap is enforcement coverage. The scorer has local planted-failure
tests, but the green wall does not run them, and there is not yet an end-to-end
MCP transcript harness that proves a full lab record can be reconstructed from
MCP payloads alone.

## Debug Packet

Tier: T2 SSOT, with P1 Team-quality validity impact when `fsBypass=true`.

Symptom / repro:

- Run a Team Lab case.
- Harness records `team_result`, `floor_show`, and a copied run journal.
- Old behavior could score artifact presence or worker content from the copied
  journal while describing the run as MCP-only.
- A Team-quality report could therefore look authoritative even when MCP did not
  expose the required prompt/output/status truth.

Bug fingerprint:

```text
scripts/team_lab/run.py copy_run_journal
+ scripts/team_lab/scoring.py artifact reconstruction
+ docs/phases/MCP_Run_Factory_Team_Lab.md MCP-only law
+ Team-quality judgment not gated by fsBypass
```

Attempt count: first Bug Hunt packet for this exact Team Lab proof gap.

Seam:

```text
alln mcp serve --stdio
-> team_start/team_status/team_result/floor_show MCP payloads
-> .lab experiment record
-> scorer / judge gate
-> Team-quality report
```

Truth owner:

- MCP retrieval truth: `TeamRunJSON` returned by `team_result(detail=full)`.
- Durable run truth: `RunStore` + `TeamRun`, but only behind MCP for lab scoring.
- Inspectable artifact truth: Floor projection and future MCP artifact tools.
- Lab experiment truth: `.lab/<experiment>/experiment.json` plus
  `evaluation/run-contract-score.json`.
- Team-quality admissibility: `scripts/team_lab/scoring.py`.

Lie-prone layer:

- A copied Application Support journal can contain the right files even when MCP
  retrieval is incomplete.
- A completed run can hide missing prompt snapshots, worker statuses, or writer
  packet markdown.
- Disk artifact presence can make the experiment feel dogfooded while bypassing
  the actual agent-facing contract.

Regression considered:

- `docs/phases/MCP_Run_Factory_Team_Lab.md` now states the MCP-only law and the
  final packet retrieval rule.
- `scripts/team_lab/scoring.py` now sets `scoringSource`, `fsBypass`, and
  `teamQualityWithheld`.
- `scripts/team_lab/test_scoring.py` has planted local failures for
  `fsBypass`, hidden worker status, empty worker content, and stale writer
  claims.

Isolation harness: required for honest end-to-end proof. In-place Swift MCP
tests can prove handler payloads, and Python tests can prove scoring, but neither
alone proves the lab can reconstruct a real experiment from MCP without using
the copied journal.

Missing kill test / proof:

- Add the Python wall test:

```text
python3 scripts/team_lab/test_scoring.py
```

This already includes the named checks that would fail under the old lie:

```text
fs_bypass.detected
fs_bypass.team_quality_withheld
dropped_worker.status_check_fails
dropped_worker.contract<0.95
dropped_worker.team_quality_withheld
```

- Add a Swift MCP integration test:

```text
swift test --package-path Packages/AllnighterCore \
  --filter MCPAsyncTeamTests/testTeamResultFullContainsAllLabScoringTruth
```

Expected assertions: `team_result(detail=full)` contains non-empty
`workers[].resolvedWorkerPromptSnapshot`, `workerAnswers[].markdown`,
`workerAnswers[].status`, `plan.markdown`, and `plan.status` for a completed
mocked run. It must not inspect `RunStore` directly except as setup/cleanup.

- Add a Python run-record negative test:

```text
python3 scripts/team_lab/test_run_contract.py \
  --filter testCopiedJournalCannotMakeTeamQualityAuthoritative
```

Fixture: a lab directory with a complete `.lab/<exp>/run/` journal copy but no
valid `team-result.json`. Expected: `scoringSource == "journal"`,
`fsBypass == true`, `pure_mcp_scoring == false`, and
`teamQualityWithheld == true`.

- Add an MCP transcript isolation harness:

```text
python3 scripts/team_lab/harness_mcp_reconstruct.py \
  --fixture scripts/team_lab/fixtures/mcp_complete_run.jsonl
```

The harness replays or serves a tiny MCP stdio transcript containing only
`mcp_hello`, `team_preflight`, `team_start`, `team_status`, `team_result`, and
`floor_show`. It writes a `.lab` record with no copied journal. Success
criterion: a non-coder can open `report.md` and see `fsBypass=false`,
`Scoring source: mcp`, `runContractScore >= 0.95`, and Team quality not withheld.

Fix boundary:

- Keep `copy_run_journal` only for diff/debug evidence, or remove it once MCP
  artifact tools are complete.
- Never let `journal_copied_for_diff` count toward `runContractScore`.
- Do not add direct `RunStore` imports to `scripts/team_lab`.
- Do not compare or promote Teams unless `fsBypass=false` and
  `runContractScore >= 0.95`.
- Wire `python3 scripts/team_lab/test_scoring.py` into the green wall or an
  equivalent team-lab check target.

Proof command / founder test:

```bash
python3 scripts/team_lab/test_scoring.py
swift test --package-path Packages/AllnighterCore --filter MCPAsyncTeamTests
python3 scripts/team_lab/harness_mcp_reconstruct.py --fixture scripts/team_lab/fixtures/mcp_complete_run.jsonl
```

Founder-readable success criterion:

```text
Open .lab/<experiment>/report.md.
It must say scoring source is mcp, fsBypass=false, run contract >= 0.95,
and quality is not withheld. Remove team-result.json and rerun evaluation:
the report must flip to fsBypass=true and withhold quality even if .lab/run/
still contains a complete copied journal.
```

## Proof Feasibility

Honest end-to-end proof can be written in this codebase only with a small
isolation harness.

Reason: a live end-to-end lab run depends on installed CLIs, auth/session state,
quota, support-root permissions, and long-running MCP process ownership. That
path is valuable as a Works Test, but it is not a reliable wall test. The
existing Swift MCP tests cover the handler/runtime seam with mocked workers, and
the Python scorer tests cover the scoring gate. The missing proof is the seam
between an MCP transcript and the `.lab` record.

Minimal isolation harness:

```text
scripts/team_lab/harness_mcp_reconstruct.py
scripts/team_lab/fixtures/mcp_complete_run.jsonl
scripts/team_lab/fixtures/mcp_missing_team_result_with_journal/
```

The harness uses the same MCP JSON-RPC frame shape and the same Python
`score_run_contract` / `evaluate_team_quality` path as the real lab. It does not
import `AllnighterCore`, call `RunStore`, or read Application Support. Green
means the lab can reconstruct Team-quality-admissible evidence from MCP alone.
Red means Team quality is withheld.

## What Was The Lie?

The lab was allowed to advertise MCP-only dogfooding while using local run
journals or disk artifact presence as scoring evidence. That made the harness
capable of passing while the agent-facing MCP contract was still incomplete.

## What Is The Truth Owner?

`team_result(detail=full)` is the scoring truth owner for worker prompts,
worker outputs, terminal worker status, and final writer packet markdown.
Floor/artifact MCP tools own inspectable artifact references. The copied journal
is not a scoring owner.

## What Proof Now Gates Team Quality?

Team quality is admissible only when all are true:

```text
terminal status == completed
team_result(detail=full) was retrieved
pure_mcp_scoring == true
fsBypass == false
runContractScore >= 0.95
worker prompt snapshots are present
worker answers are present and non-empty
worker answer statuses are present for all non-plan workers
plan.markdown and plan.status are present
floor_show returns the requested run id
```

The current deterministic gate lives in `scripts/team_lab/scoring.py`, especially
`score_run_contract`, and is covered locally by `scripts/team_lab/test_scoring.py`.

## Negative Tests Still Missing

- A committed fixture where `.lab/run/` is complete but `team-result.json` is
  missing; evaluation must withhold quality.
- A committed fixture where `team-result.json` has prompt snapshots and answers
  but one non-plan worker lacks `status`; evaluation must withhold quality.
- A committed fixture where `floor_show` returns the wrong run id; run contract
  must fall below the quality gate.
- A transcript harness that proves `.lab` reconstruction from MCP frames alone.
- A green-wall entry that runs the Python team-lab truth tests.
- A schema/contract test that fails if `team_result(detail=full)` stops exposing
  any field required by the scorer.
- A report-level negative test that prevents compare/promotion when
  `fsBypass=true`, even if judge records exist.

## GUI Proof

No GUI fixture, render, or layout-watcher proof applies. This bug lives in the
headless MCP Team Lab path, and the phase doc explicitly excludes the Mac app
from the lab workflow. The equivalent visible proof is the generated lab report
and MCP transcript, not a SwiftUI render.

