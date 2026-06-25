# 2026-06-24 — floor_show MCP parameter mismatch (runId vs run)

Status: Bug Hunt packet — root cause isolated to one call site + shared resolver. No execution required for diagnosis.

## Summary

The MCP harness in `scripts/team_lab/run.py:413` calls `floor_show` with `{"runId": run_id}`.  
The server at `MCPServer.swift:280` routes to `AllnighterCLI.runRef(from: args)` which only inspects `args["run"]` (AllnighterCLI.swift:1092). Absent `run`, it returns `"latest"`. `resolveRun("latest")` returns the max-by-`createdAt` run.

This violates the documented contract (`ContractRegistry+Milestone1.swift:156`: `floor_show` param is `"run"`). Same path affects `show` and `spec_get`. Lifecycle tools correctly use `runId`.

Risk: in batch/concurrent lab runs against the same `~/Library/Application Support/Allnighter/Runs`, one experiment's `floor-show.json` can contain another run's Floor projection. The `floor_show_run_id` scoring check will flag it, but the persisted artifact for that `.lab` dir is wrong.

## Severity

- Impact: Lab batch data integrity for `floor_show` artifact (cross-experiment contamination possible). Does not affect `team_result` (the packet source), `team_status`, or `team_cancel`.
- User-visible: No. Only team-lab harness and scoring.
- Scoring: `floor_show_run_id` check becomes `false` when `expected_run_id` is supplied and IDs diverge → lowers `runContractScore`.
- Known partial mitigation: `resume_writer.py:156` already avoids MCP `floor_show` ("MCP floor_show can return a stale run id") and shells out to `alln floor show <id> --json`.
- Latent until: second run exists with later `createdAt` at the moment of a `floor_show` call for an earlier id.

## Smallest Reproducible Scenario

### Concrete inputs (no agents, no network)

1. Build produces `alln` with current `MCPServer`.
2. A support dir (`RunStore` root) that already contains at least one persisted `TeamRun`.
3. Python harness executes (simplified):

```python
# after team_start that returned run_id = "run_TARGET"
floor = client.call_tool("floor_show", {"runId": "run_TARGET"})
# also writes:
# (lab_dir / "floor-show.json").write_text(...)
```

Equivalent direct Swift observation (from existing test shape):

```swift
XCTAssertEqual(AllnighterCLI.runRef(from: ["runId": "run_TARGET"]), "latest")
let latest = RunStore().list().max(by: { $0.createdAt < $1.createdAt })
let resolved = AllnighterCLI.resolveRun("latest")
XCTAssertEqual(resolved?.id, latest?.id)  // not "run_TARGET" if a newer run exists
```

### Steps (minimal)

1. Persist run RA (earlier `createdAt`).
2. Persist run RB (later `createdAt`).
3. From a fresh MCP stdio client (or the lab harness path), invoke:
   - `tools/call` → `name: "floor_show"`, `arguments: {"runId": "RA"}`
4. Server executes `MCPServer.handleCall` → case `"floor_show"` → `runRef(from: ["runId": "RA"])` → `"latest"` → `resolveRun("latest")` → RB.
5. Response contains `FloorRun` whose `run.id == "RB"`.
6. Harness writes `floor-show.json` containing RB's data into the lab dir that was tracking RA.

### Expected behavior (per contract + caller intent)

- `floor_show` with a concrete run reference must return that run's Floor (or `RUN_NOT_FOUND`).
- Contract (`ContractRegistry+Milestone1.swift:155`):
  ```json
  {"name": "floor_show", "params": [{"name": "run", "summary": "Run id or `latest` (default latest)."}]}
  ```
- `runRef` comment (AllnighterCLI.swift:1091): "Query-style MCP tools accept `run` only; team lifecycle tools use `runId`."
- `team_result`, `team_status` etc. that use direct `args["runId"]` must continue to work.

### Observed behavior

- `runRef` ignores `runId` entirely.
- Returns `"latest"`.
- `resolveRun("latest")` can return a different run.
- `floor-show.json` + `floor-show.txt` in the `.lab/...` dir are for the wrong run.
- `scoring.score_run_contract(..., expected_run_id=RA)` sets `floor_ok = (RB == RA)` → false.
- Check `"floor_show_run_id"` fails for that experiment.

### Unknown / missing observation

- Timestamp of any historical `.lab` run where `floor-show.json` `run.id` actually differed from the experiment's `run.runId` (would be visible in existing lab dirs under `.lab/*/floor-show.json`).
- Whether concurrent `macro_advance` or parallel variant runs have produced observable contamination in real artifacts.

## Root Cause (seam)

```text
run.py:413
    client.call_tool("floor_show", {"runId": run_id})
    # (also writes floor-show.* unconditionally when tool is advertised)

MCPServer.swift:280
    case "floor_show":
        let ref = AllnighterCLI.runRef(from: args)   # !!!
        guard let run = AllnighterCLI.resolveRun(ref) ...

AllnighterCLI.swift:1092
    static func runRef(from args: [String: Any]) -> String {
        if let run = args["run"] as? String { ... }
        return "latest"   # !!!
    }
```

`show` (line 249) and `spec_get` (line 274) share the identical `runRef` call.

Contract tool schema generation (`toolDefinitions`) advertises only the declared params (`run`), so schema-aware clients would be correct; the harness hardcodes the wrong key copied from lifecycle muscle memory.

## Fix Boundary

Minimal surface:

1. **Caller fix (required)** — [scripts/team_lab/run.py](/scripts/team_lab/run.py) line 413:
   ```diff
   - floor = client.call_tool("floor_show", {"runId": run_id})
   + floor = client.call_tool("floor_show", {"run": run_id})
   ```
   (Only call site in the tree that passes the wrong key for a query tool.)

2. **Optional hardening (recommended for defense-in-depth)** — `AllnighterCLI.runRef`:
   - Accept `run` (preferred per contract) or `runId` (alias for convenience).
   - Update comment and `testRunRefUsesCanonicalRunArgumentOnly` to document the accepted alias.
   - Keeps the "run wins when both present" behavior.
   - Prevents future copy-paste from lifecycle tools from producing silent "latest".

3. **Not in scope**:
   - Changing `team_status` / `team_result` (they already use `runId` directly in the handlers).
   - Altering `resolveRun` or `FloorProjector`.
   - Adding `runId` to the ContractRegistry param list for these tools (would be a contract change; alias in resolver is cheaper).

Do not relax the "query vs lifecycle" distinction in docs without updating the registry and generated schemas.

## Regression Test

### A. Unit (Swift) — lock contract behavior

In `MCPAsyncTeamTests.swift` (or a dedicated `MCPQueryRefTests.swift`):

```swift
func testQueryToolsAcceptRunAndAliasRunId() {
    // Canonical
    XCTAssertEqual(AllnighterCLI.runRef(from: ["run": "run_ABC"]), "run_ABC")
    // Alias tolerated (prevents copy-paste footgun)
    XCTAssertEqual(AllnighterCLI.runRef(from: ["runId": "run_ABC"]), "run_ABC")
    // Both → run wins (existing)
    XCTAssertEqual(AllnighterCLI.runRef(from: ["runId": "run_XXX", "run": "run_ABC"]), "run_ABC")
    // Empty → latest (existing)
    XCTAssertEqual(AllnighterCLI.runRef(from: [:]), "latest")
    XCTAssertEqual(AllnighterCLI.runRef(from: ["run": "   "]), "latest")
}
```

Keep the existing `testRunRefUsesCanonicalRunArgumentOnly` or merge.

### B. Harness call-site discipline (Python)

- `test_scoring.py` or a new `test_run_harness_contract.py` can assert the argument keys for known query tools by static inspection or by running a tiny MCP roundtrip with a stub that records the exact `arguments` dict passed to `floor_show`, `show`, `spec_get`.
- Or simply: after a run_experiment under a temp support dir with controlled runs, assert `floor-show.json["run"]["id"] == expected_run_id`.

### C. End-to-end contract (existing path)

The case `floor_show_wrong_run_v1` in `bug_hunt_necessity_v1.json` (and `bug_hunt_repo_regressions_v1.json`) already exists precisely to gate this. Once the call site is fixed, a clean run of that case must have:
- `floor_show_run_id: true` in the scoring checks
- `runContractScore` not penalized by this check

### D. Optional: make the server reject unknown keys for query tools?

Out of scope for minimal fix. A future strict mode could log/warn on `runId` for query tools while still servicing the request.

## Proof (post-fix)

- `swift test` (specifically the `runRef` test and any Floor/MCP tests).
- `python3 -m pytest scripts/team_lab/test_*.py -q` (or the scoring tests).
- One clean execution of `floor_show_wrong_run_v1` (or the necessity suite) with `floor_show_run_id` green and no fsBypass.
- `resume_writer.py` path continues to work (it already bypasses the MCP call).

## Related

- `docs/phases/MCP_Run_Factory_Team_Lab.md` (floor_show contract expectations)
- `scripts/team_lab/scoring.py:178` (`floor_ok`, `floor_show_run_id` check)
- `scripts/team_lab/resume_writer.py:156` (workaround comment)
- `ContractRegistry+Milestone1.swift:137` (show), `155` (floor_show), `150` (spec_get) — all declare `run`
- `AllnighterCLI.swift:1091` (the comment that was violated by the caller)
- Suite case that literally contains this prompt: `docs/team-lab/suites/bug_hunt_necessity_v1.json:67`

No facts invented. All lines cited from current tree.
