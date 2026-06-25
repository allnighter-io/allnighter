# Bug Hunt Packet: floor_show (and show/spec_get) ignore runId, drift to latest

**Date:** 2026-06-24  
**Files reviewed:** `Packages/AllnighterCore/Sources/AllnighterCLI/MCPServer.swift`, `Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift`, `scripts/team_lab/run.py`  
**Related:** `MCPAsyncTeamTests.swift`, `RunStore.swift`, `FloorRun.swift`, `scoring.py`

## Severity

**P1 (batch integrity) / P2 (single-run observability).**

- When the Team Lab harness (or any MCP client) runs multiple experiments concurrently or in quick succession against the same support root, `floor_show` (and `show`/`spec_get`) can return the Floor / packet for a *different* run than the one whose `runId` was supplied.
- The returned structured payload carries the *wrong* `run.id`. Lab artifacts (`floor-show.json`) are cross-contaminated.
- The scorer's `floor_show_run_id` check fails (or is bypassed when `expected_run_id` is not passed), lowering `runContractScore` and potentially withholding Team quality for otherwise valid runs.
- Single sequential labs are mostly unaffected except the rubric item is noisy and any human/LLM inspecting the `.lab` dir sees a drifted snapshot.
- Root cause class per prompt: **drifted snapshot** (global `RunStore().list().max(createdAt)`) + **parameter convention drift** between tool families. The MCP handler returns a projection whose identity the caller did not request — classic "UI displays truth it does not own."

## Symptom

Harness:
```python
# run.py:413
floor = client.call_tool("floor_show", {"runId": run_id})
```

Server path (MCPServer.swift:280):
```swift
case "floor_show":
    let ref = AllnighterCLI.runRef(from: args)   # !!!
    guard let run = AllnighterCLI.resolveRun(ref) else { ... }
    ...
```

`runRef` (AllnighterCLI.swift:1092):
```swift
static func runRef(from args: [String: Any]) -> String {
    if let run = args["run"] as? String { ... }
    return "latest"
}
```

`resolveRun("latest")` (AllnighterCLI.swift:1087):
```swift
if ref == "latest" { return RunStore().list().max(by: { $0.createdAt < $1.createdAt }) }
```

`team_status`/`team_result` correctly read `args["runId"]` directly in `MCPAsyncTeamHandlers`. Only the query/inspect family went through the `run`-only helper.

## Reproduction

1. Build `alln`, start two lab experiments near each other (or one finishes while the second is still polling).
2. First experiment receives `runId = R1` from `team_start`.
3. Second experiment's terminal save makes R2 the newest on disk.
4. Harness for R1 does `floor_show({"runId": "R1"})`.
5. `runRef` sees no `"run"`, returns `"latest"`.
6. `resolveRun("latest")` returns R2.
7. `floor-show.json` and the structured floor contain R2's worker lanes, artifacts, and timeline.
8. Scorer records `floor_show_run_id: false`; contract score drops; cross-run data pollutes the `.lab/<exp>` record.

Deterministic local repro exists via the planted case `floor_show_wrong_run_v1` in `bug_hunt_necessity_v1.json` and `bug_hunt_repo_regressions_v1.json`.

## Truth / Lie / Ownership

- **Truth owner for a specific run's floor:** the persisted `run_<id>/run.json` + derived artifacts under `RunStore`, projected by `FloorProjector`.
- **Requested identity:** the `runId` returned by `team_start` and passed to `team_status`/`team_result`.
- **Lie-prone layer:** `runRef(from:)` + `resolveRun("latest")` in the inspect-tool path silently substitutes a global max. No enforcement that returned `run.id == requested`.
- **Drift vector:** `RunStore.list()` is a fresh FS scan sorted by `createdAt`; no caller-owned pin, no session, no per-MCP-client view.
- **UI displays truth it does not own:** the MCP client (harness) receives a `FloorRun` (or `TeamRunJSON` for show) whose `run.id` is unrelated to the experiment it is recording. The scorer and report then operate on that foreign snapshot.

No optimistic UI, no in-memory cache duplication, and no GUI `@Observable` state is involved — this is a pure server-side ref-resolution + convention mismatch.

## Fix Boundary (minimal)

**Server (defensive):**
- `runRef(from:)` now accepts `runId` as alias when `run` is absent (or whitespace). `run` still takes precedence.
- Location: `AllnighterCLI.swift:1092`

**Harness (correctness):**
- `run.py:413` changed to pass documented key: `{"run": run_id}` instead of `{"runId": run_id}`.
- (Note: `resume_writer.py` already sidestepped via CLI `alln floor show <id>` and has its own mismatch guard.)

**Contract:**
- Remains unchanged: `floor_show` / `show` / `spec_get` document `run` (optional). Accepting `runId` is tolerance, not new API.

**Not in scope for minimal fix:**
- Changing the contract schema to make `runId` the canonical for inspect tools.
- Adding a required `runId` to the inspect tools (would be a breaking surface change).
- Adding server-side "echo the requested ref" wrapper (the payload already contains the true `run.id`; caller must compare).

## Regression Test

**Unit (committed, passes):**
`Packages/AllnighterCore/Tests/AllnighterEngineTests/MCPAsyncTeamTests.swift`:
```swift
func testRunRefAcceptsRunOrRunId() {
    XCTAssertEqual(AllnighterCLI.runRef(from: ["runId": "AAA", "run": "BBB"]), "BBB")
    XCTAssertEqual(AllnighterCLI.runRef(from: ["runId": "AAA"]), "AAA")
    XCTAssertEqual(AllnighterCLI.runRef(from: ["run": "BBB"]), "BBB")
    XCTAssertEqual(AllnighterCLI.runRef(from: [:]), "latest")
}
```

**Contract-level negative (recommended addition):**
Add an MCP-level test that:
1. Starts a run via `MCPAsyncTeamHandlers.start` (or directly saves a `TeamRun` with known id into an isolated `RunStore`).
2. Invokes the `floor_show` path (or calls `AllnighterCLI` surface) with `["runId": thatId]`.
3. Asserts the returned `FloorRun` (or decoded structured) has `run.id == requested`.

A Python-side contract test can assert that after `floor_show({"run": R})` the written `floor-show.json` satisfies `floor_run_id == expected_run_id` and the scorer marks the check green.

**End-to-end gate already exists:**
`scripts/team_lab/scoring.py:209`:
```python
checks.append({"name": "floor_show_run_id", "ok": floor_ok or not expected_run_id})
```
When `expected_run_id` is supplied (as it is from `run.py`), a drifted floor makes the check false and `runContractScore` drop below the 0.95 gate (withholding quality).

## Commits / Handoff

- `AllnighterCLI.swift`: tolerate runId in runRef for inspect tools
- `MCPAsyncTeamTests.swift`: update + rename runRef test to document tolerance
- `run.py`: call floor_show with canonical "run" key
- This packet: `docs/operations/debugger/2026-06-24-floor-show-runid-drift.md`

## Proof Commands

```bash
swift test --package-path Packages/AllnighterCore --filter MCPAsyncTeamTests/testRunRefAcceptsRunOrRunId
python3 -c '
from scripts.team_lab.scoring import score_run_contract
# (existing planted negative fixtures exercise floor_show_run_id)
'
```

Founder-readable: "MCP query tools for runs now honor the id you actually pass (whether you call it `run` or `runId`). Labs no longer see another experiment's floor by accident."