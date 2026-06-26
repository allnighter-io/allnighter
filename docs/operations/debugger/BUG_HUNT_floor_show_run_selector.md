# BUG HUNT PACKET: floor_show run selector (run vs runId)

**Prompt (from bug_hunt_necessity_v1 / bug_hunt_repo_regressions_v1):**  
"The MCP harness called floor_show with runId but the server only read run, defaulting to latest. This could cross-contaminate batch lab data. Review Packages/AllnighterCore/Sources/AllnighterCLI/MCPServer.swift and scripts/team_lab/run.py. Produce a Bug Hunt packet: severity, reproduction, fix boundary, and regression test."

Review scope (per prompt): MCPServer.swift and run.py (plus direct callees required for the seam).

## Severity

**High for lab evidence integrity in batch regime.**

- **Blast radius:** `.lab/<exp>/floor-show.{json,txt}` for one experiment can contain another experiment's Floor projection when multiple runs share one RunStore (the normal case for sequential or parallel A/B lab runs via macro_advance / daemon).
- **Does NOT affect:** actual run data, team_result (the packet body source), team_status, team_cancel, journal copy.
- **Does affect:** `floor_show_run_id` scoring check → lowers `runContractScore`; can flip `teamQualityWithheld`; pollutes any downstream consumer of the floor artifact (reports, macro rollups, genesis records that consume floor).
- **Trigger condition:** (1) explicit run id supplied under `runId` key to floor_show, (2) a later-created run exists in the same support dir at call time.

**Observation (current tree):** the described call-site mismatch is mitigated; see Reproduction.

## Smallest Reproducible Scenario

**Concrete inputs (no agents, no network, deterministic):**

1. Isolated support dir (ALLNIGHTER_SUPPORT_DIR) containing exactly two persisted runs under `Runs/`:
   - RA: id = "RA-001", createdAt = "2026-06-20T00:00:00Z"
   - RB: id = "RB-002", createdAt = "2026-06-24T00:00:00Z"  (strictly later → is "latest")
2. Launch the real binary: `alln mcp serve --stdio` with that support dir in env.
3. Complete initialize + notifications/initialized.
4. Call (via tools/call):
   - `floor_show` with arguments: `{"runId": "RA-001"}`

**Expected (per contract + caller intent):**
- Returned floor's `run.id` (FloorRun.run.id) == "RA-001"
- Or a tool error (RUN_NOT_FOUND / CLI_USAGE_ERROR)

**Observed (when the bug was live — harness passed runId, server runRef read only "run"):**
- `runRef(from: ["runId": "RA-001"])` returned "latest" (no "run" key present).
- `resolveRun("latest")` = `RunStore().list().max(by: createdAt)` → RB-002.
- floor_show response + floor-show.json describe RB-002's Floor.
- RA's lab dir now contains RB's floor artifact.

**Unit-level lie (pre-alias):**  
`AllnighterCLI.runRef(from: ["runId": "RA-001"])` == `"latest"`

**Why only under batch/sequential runs:** If RA was still the absolute latest at the moment floor_show was called, the wrong-run symptom is invisible by accident.

## Root Cause (seam)

**Call chain (MCP path):**
- run.py (or any client) → `client.call_tool("floor_show", {"runId": run_id})`
- mcp_client → JSON-RPC `tools/call {name:"floor_show", arguments:{...}}`
- MCPServer.swift:280: `case "floor_show": let ref = AllnighterCLI.runRef(from: args)`
- AllnighterCLI.swift:1093 (pre-fix): only inspected `args["run"]`; absent → "latest"
- resolveRun("latest") → max-by-createdAt (AllnighterCLI:1085)
- FloorProjector.project on the chosen run → written as floor-show.json

**Contract truth:**
- ContractRegistry+Milestone1.swift:156: `floor_show` param declared as `"run"` (optional, "Run id or `latest` (default latest)").
- Lifecycle tools declare `"runId"` (required for team_status/team_result/etc.).
- Muscle-memory mismatch between the two families.

**Lie-prone layer:** `AllnighterCLI.runRef(from:)` — the single shared adapter for show/spec_get/floor_show. It performed silent fallback instead of preserving an explicit selector or erroring.

**Amplifier:** `resolveRun("latest")` has no caller context; it always returns the global newest run in the store.

## Current Observations (do not invent)

- scripts/team_lab/run.py:413 (as of this review):
  ```python
  floor = client.call_tool("floor_show", {"run": run_id})
  ```
  Uses the contract key for query tools.
- AllnighterCLI.swift:1093 (current):
  ```swift
  let ref = (args["run"] as? String) ?? (args["runId"] as? String)
  if let ref, !ref.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ... }
  return "latest"
  ```
  Defensive alias present; "run" takes precedence when both supplied. Comment explicitly cites "silent latest drift".
- scripts/team_lab/resume_writer.py:156 still bypasses MCP floor_show entirely and shells out to `alln floor show <id> --json` with a post-check that the returned id matches (historical mitigation comment: "MCP floor_show can return a stale run id").
- scoring.py:209: `floor_show_run_id` check is `"ok": floor_ok or not expected_run_id` (mask remains).
- Dedicated seam test: scripts/team_lab/test_mcp_floor_show_run_id.py seeds RA+RB under isolated dir, asserts run/runId both resolve correctly and absence resolves to latest. (Passes on current binary.)

The exact symptom described ("harness called with runId but server only read run") no longer reproduces on the reviewed sources because both sites have been adjusted.

## Fix Boundary (minimal)

Apply changes only at the seam:

**Required (caller hygiene):**
- scripts/team_lab/run.py: use `{"run": run_id}` for floor_show (and for show/spec_get if ever added).

**Defensive server (recommended):**
- AllnighterCLI.runRef(from:): accept `runId` as alias when `run` absent; document precedence; empty → "latest". (Already present.)

**Out of scope for this fix:**
- Do not change lifecycle tools (they correctly use runId).
- Do not alter ContractRegistry param names for floor_show (keep "run").
- Do not touch resolveRun, FloorProjector, RunStore.
- Do not remove resume_writer CLI bypass.

**Regression law (one line):** Query MCP tools (`show`, `spec_get`, `floor_show`) must never resolve `"latest"` when the caller supplied a concrete run id under either `run` or `runId`.

## Regression Test

**Primary:** `python3 scripts/team_lab/test_mcp_floor_show_run_id.py`

- Uses real binary + real MCP stdio transport.
- Isolated ALLNIGHTER_SUPPORT_DIR (no cross-test pollution).
- Seeds two runs with known createdAt ordering (RA older, RB latest).
- Exercises the three cases: `{"run": RA}`, `{"runId": RA}`, `{}` (latest).
- Fails on selector returning wrong id.

**Gate via lab case:**
- `floor_show_wrong_run_v1` in bug_hunt_necessity_v1.json and bug_hunt_repo_regressions_v1.json.
- A clean execution must produce `floor_show_run_id: true` in scoring checks (when expected_run_id supplied) and runContractScore not penalized by this check.

**Unit anchor (already present):**
- Packages/AllnighterCore/Tests/AllnighterEngineTests/MCPAsyncTeamTests.swift: `testRunRefAcceptsRunOrRunId`

## Proof Notes

- Single-layer unit test on runRef is necessary but not sufficient (the seam includes the deployed binary and chosen support dir).
- End-to-end via the Python test + a successful floor_show_wrong_run_v1 execution is the decisive evidence.
- If a future `.lab` record shows floor_show_run_id:false with a correct `run.runId` in experiment.json and a later run present in the recorded supportRoot, that is the reappearance signature.

---

**Status:** The described defect class is understood and guarded at the two reviewed sites. The regression harness exists and passes. The scoring mask (`or not expected_run_id`) and resume_writer bypass remain as additional defense-in-depth.