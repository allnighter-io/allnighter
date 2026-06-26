# BUG HUNT PACKET — floor_show run selector drift (runId vs run)

**Date:** 2026-06-26  
**Source case:** `floor_show_wrong_run_v1` (bug_hunt_necessity_v1.json, bug_hunt_repo_regressions_v1.json)  
**Scope of review:** `Packages/AllnighterCore/Sources/AllnighterCLI/MCPServer.swift`, `scripts/team_lab/run.py`, direct callees (`AllnighterCLI.runRef`, `resolveRun`, `MCPAsyncTeamHandlers`, ContractRegistry, scoring, test).

---

## Symptom

When the MCP harness (or any MCP client) calls `floor_show` for a concrete run while a later run exists in the same `RunStore`, `floor-show.json` (and `.txt`) can contain the **latest** run's Floor projection instead of the requested run.

Result: `.lab/<exp>/floor-show.{json,txt}` describes a different run than `experiment.json.run.runId`. The `floor_show_run_id` scoring check fails (or is masked), `runContractScore` drops, and batch lab data is cross-contaminated.

`team_result` (the packet source) and `team_status` are unaffected.

---

## Severity

| Dimension              | Verdict |
|------------------------|---------|
| Product / GUI / CLI    | None — `alln floor show <id>`, `FactoryFloorView`, and direct `RunStore` paths were never affected. |
| Team Lab batch integrity | **High** — shared `RunStore` under `macro_advance` / A/B / sequential runs. Silent wrong artifact written per experiment. |
| Scoring / macro rollup | `floor_show_run_id=false` lowers contract score; can withhold team quality or pollute meta-analysis. |
| Result packet fidelity | Unaffected (`team_result` uses `runId` directly). |
| Cross-experiment       | Possible under one support root when ≥2 runs exist and caller uses the lifecycle key. |

**Tier:** T2 SSOT (persisted experiment identity vs derived floor artifact identity).

---

## Fingerprint (exact)

Harness: `client.call_tool("floor_show", {"runId": run_id})` (or any key other than the documented `run`).  
Server: `MCPServer.swift:280` → `let ref = AllnighterCLI.runRef(from: args)` → `resolveRun(ref)` → `FloorProjector.project(run)` → returned as structured/text.  
Pre-fix `runRef`: only read `args["run"]`, default `"latest"` → `resolveRun("latest") = RunStore().list().max(by: createdAt)`.

The MCP response surface returned a FloorRun whose `.run.id` did not match the caller's requested identity — the response displayed truth it did not own for that request.

---

## Truth Owners (per project law)

- **Persisted run identity (source of truth):** `TeamRun.id` from `team_start` response, written to `start["runId"]`, mirrored to `experiment.json["run"]["runId"]`, passed as `expected_run_id` to `score_run_contract`.
- **Selector contract (SSOT):** `ContractRegistry+Milestone1.swift:155` — `floor_show` param is named `"run"` (optional; default latest). Same for `show` and `spec_get`.
- **Lifecycle convention:** `team_status`/`team_result`/`team_cancel` require `"runId"` (MCPAsyncTeamHandlers.swift:46,59,88).
- **Resolver:** `AllnighterCLI.runRef(from:)` + `resolveRun`.
- **Floor artifact consumer:** `scoring.py:178` (`floor_show_run_id` check) and downstream (reports, macro).

No UI layer owned the mapping; the lie was in the argument adapter.

---

## Reproduction (deterministic, no agents, no quota)

### Minimal setup
- Built `alln` (debug) at `Packages/AllnighterCore/.build/debug/alln` (or `$ALLN_BIN`).
- Isolated support dir (`ALLNIGHTER_SUPPORT_DIR`).
- Two minimal persisted runs under `<support>/Runs/`:
  - `RA` (older `createdAt`)
  - `RB` (newer `createdAt` → "latest")

See `test_mcp_floor_show_run_id.py` `MINIMAL_RUN_JSON` and `write_minimal_run` for exact shape.

### Steps (from run.py pattern)
1. Spawn: `alln mcp serve --stdio` (env with `ALLNIGHTER_SUPPORT_DIR`).
2. `initialize` + `notifications/initialized` + `tools/list`.
3. `tools/call` name=`floor_show`, arguments=`{"runId": "RA-..."}` (the value the harness actually held from `team_start`).
4. Server resolves via `runRef` → `"latest"` (pre-fix) → RB.
5. Client receives floor whose `run.id == "RB-..."`.
6. If `floor_show` was in tools, harness writes `floor-show.json` for the RA experiment.
7. `score_run_contract(..., expected_run_id="RA-...")` → `floor_show_run_id=false`.

**Observed (buggy):** floor describes RB.  
**Expected:** floor describes RA (or `RUN_NOT_FOUND`).

Same for `show` and `spec_get` (they also use `runRef`).

### Why latent
If the requested run is still the latest at call time, keys differ but outcome matches by accident. Divergence appears exactly in the batch-lab regime (multiple runs, shared store).

---

## Root Cause Analysis (line-precise)

**Primary seam:** Python harness convention (`runId` muscle memory from `team_*`) vs documented query-tool contract (`run`) vs server adapter.

```swift
// MCPServer.swift:280
case "floor_show":
    let ref = AllnighterCLI.runRef(from: args)   // !!!
    guard let run = AllnighterCLI.resolveRun(ref) else { ... }
    ... AllnighterCLI.floorRunJSONString(run)
```

```swift
// AllnighterCLI.swift:1093 (pre-alias)
static func runRef(from args: [String: Any]) -> String {
    let ref = (args["run"] as? String) ?? (args["runId"] as? String)  // defensive alias added later
    ...
    return ref?.trimming... ?? "latest"
}
```

```python
# scripts/team_lab/run.py:412 (historical)
floor = client.call_tool("floor_show", {"runId": run_id})   # now fixed to {"run": run_id}
```

Lifecycle tools are correct:
```swift
// MCPAsyncTeamHandlers.swift:46
guard let runId = args["runId"] as? String, !runId.isEmpty else { ... }
```

Contract declares `run`:
```swift
// ContractRegistry+Milestone1.swift:155
MCPToolSpec("floor_show", ..., params: [.init("run", summary: "Run id or `latest` (default latest).")], ...)
```

**Classification per user framing:**
- Drifted snapshot: resolver returned a Floor projection of a different persisted entity.
- Displayed truth it did not own: MCP response claimed to describe the requested run.
- Not duplicated state (RunStore is single source), not optimistic UI (no client write), not missing persistence (both runs were durably stored), not stale in-memory cache (RunStore is FS-only, `list()` rescans).

---

## Ranked Hypotheses

| # | Claim | Evidence | Status |
|---|-------|----------|--------|
| H1 | Harness passed `runId`; `runRef` read only `run` → fell to `latest`. | `run.py` call site, pre-alias `runRef`, `resolveRun("latest")` impl. | CONFIRMED (historical root). |
| H2 | Silent `latest` fallback is the amplifier (explicit id → wrong entity with no error). | `resolveRun` + max-by-createdAt; no warning path. | CONFIRMED. |
| H3 | Contract advertised `runId`. | ContractRegistry declares `run`. | RULED OUT. |
| H4 | Per-process cached state in ToolRuntime or MCPServer cross-contaminated. | ToolRuntime is per-process; each lab experiment spawns fresh `alln mcp`; only shared is disk RunStore. | RULED OUT for this symptom. |
| H5 | On-disk `run.json` was mutated after write or reader saw partial write. | RunStore uses `.atomic` writes + owner.pid ordering. `FloorProjector` is pure projection from `TeamRun`. | RULED OUT. |

---

## Fix Boundary (minimal, exact)

**Two coordinated changes (both present in current tree):**

1. **Harness (caller) — canonical key:**
   - `scripts/team_lab/run.py:413`
   - `floor = client.call_tool("floor_show", {"run": run_id})`
   - (Also `show` / `spec_get` if called from harness would use `run`.)

2. **Server (defense in depth) — tolerant alias in resolver:**
   - `AllnighterCLI.swift:1093`
   - `let ref = (args["run"] as? String) ?? (args["runId"] as? String)`
   - Whitespace/empty/ absent → `"latest"`.
   - `run` wins if both present (documented contract wins).
   - Covers `floor_show`, `show`, `spec_get` uniformly.

**Do NOT change (outside boundary):**
- `team_status`/`team_result`/`team_cancel` — they correctly require `runId`.
- `ContractRegistry` param names (keep `"run"` for query tools).
- `resolveRun`, `FloorProjector`, `RunStore`, resume_writer CLI bypass.
- No new top-level `runId` param on the contract surface.

**resume_writer.py** retains its CLI bypass (`alln floor show <id> --json`) with the comment "MCP floor_show can return a stale run id." — acceptable belt-and-suspenders; do not remove without broader contract hardening.

---

## Regression Test (the decider)

**Unit (necessary, not sufficient):**
```swift
// AllnighterEngineTests/MCPAsyncTeamTests.swift
func testRunRefAcceptsRunOrRunId() {
    XCTAssertEqual(AllnighterCLI.runRef(from: ["runId": "AAA", "run": "BBB"]), "BBB")
    XCTAssertEqual(AllnighterCLI.runRef(from: ["runId": "AAA"]), "AAA")
    XCTAssertEqual(AllnighterCLI.runRef(from: ["run": "BBB"]), "BBB")
    XCTAssertEqual(AllnighterCLI.runRef(from: [:]), "latest")
    XCTAssertEqual(AllnighterCLI.runRef(from: ["runId": "   "]), "latest")
}
```
Run: `swift test --package-path Packages/AllnighterCore --filter MCPAsyncTeamTests/testRunRefAcceptsRunOrRunId`

**End-to-end seam (decides fixed / closes H5):**
`scripts/team_lab/test_mcp_floor_show_run_id.py`

- Uses `ALLNIGHTER_SUPPORT_DIR` isolation (temp dir).
- Seeds RA (older) + RB (latest) via direct minimal `run.json` writes.
- Spawns the **real deployed** `alln mcp serve --stdio` binary.
- Calls:
  - `floor_show({"run": RA})` → asserts returned `run.id == RA`
  - `floor_show({"runId": RA})` → asserts returned `run.id == RA` (alias exercised)
  - `floor_show({})` → asserts returned `run.id == RB` (latest fallback)
- PASS means both documented and lifecycle keys work against the actual binary the lab will run.

Run:
```bash
python3 scripts/team_lab/test_mcp_floor_show_run_id.py
```

**Artifact gate (existing):**
- `scoring.py:209`: `floor_show_run_id` check is `floor_ok or not expected_run_id`
- `score_run_contract(..., expected_run_id=RA)` must yield `true` for that check when floor is present.
- Suite case `floor_show_wrong_run_v1` must complete with `floor_show_run_id: true` and no artificial score penalty.

**Regression law (one line):**
> Query MCP tools (`show`, `spec_get`, `floor_show`) must never resolve `"latest"` when the caller supplied a concrete run id under either `run` or `runId`.

---

## Proof Wall (how we know it is fixed)

- Code inspection of reviewed files + `runRef` + call sites.
- Unit test passes.
- E2E test (`test_mcp_floor_show_run_id.py`) passes against the built binary.
- A clean execution of `floor_show_wrong_run_v1` (or necessity suite) produces `floor_show_run_id: true` and `fsBypass=false`.
- No other `call_tool("floor_show", ...)` or `floor_show` arg dicts in `scripts/team_lab/*.py` use `runId` except the defensive test.

---

## Remaining Surface / Hygiene

- `resume_writer.py:156` comment + CLI bypass: leave in place as documented skepticism until contract is versioned or query tools are unified under one key.
- Audit hook (optional): on macro closeout, assert no `.lab/*/` has `floor-show.json` run id differing from sibling `experiment.json`.
- Future hardening (minority position recorded): server could `CLI_USAGE_ERROR` on unknown selector keys instead of aliasing; current alias prioritizes "never silently latest."

---

## One-line summary for closeout

**floor_show (and show/spec_get) accepted only the documented `run` key; lifecycle callers passed `runId`; resolver defaulted to `latest`; MCP response surface returned a drifted Floor snapshot. Fixed by canonical key in harness + defensive alias in `runRef`. Regression: `test_mcp_floor_show_run_id.py` + `floor_show_run_id` scoring gate.**
