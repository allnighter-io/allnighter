# Bug Packet — `floor_show` resolved `runId` to `latest` (MCP run-selector drift)

**Writer synthesis.** Supersedes the two seat drafts in this directory
(`...-floor-show-runid-mismatch.md`, `...-floor-show-runid-drift.md`); they agree on
substance. This packet is built for elimination and reflects the **current working tree**,
which already carries the fix (verified on disk 2026-06-24).

---

## Symptom & smallest repro

**Symptom.** A Team Lab experiment for run `RA` could persist a *different* run's Floor
into its `.lab/<exp>/floor-show.json`. The scorer's `floor_show_run_id` check then goes
red and `runContractScore` drops — lab evidence is cross-contaminated even though the
real result packet is fine.

**Smallest repro (pre-fix, no agents required):**

1. Persist two runs in `RunStore`: `RA` (earlier `createdAt`), `RB` (later).
2. MCP `tools/call` → `floor_show` with `arguments: {"runId": "RA"}`.
3. Server `runRef` reads only `args["run"]` → absent → returns `"latest"`.
4. `resolveRun("latest")` → `RB` (max `createdAt`).
5. Response / `floor-show.json` describe **RB**.

- **Expected:** Floor for `RA`, or `RUN_NOT_FOUND`.
- **Observed:** Floor for `RB`, silently, with no error.

Unit-level repro of the exact lie (pre-fix): `runRef(from: ["runId": "RA"]) == "latest"`.

**Why latent.** If the target run is still the absolute latest at call time, IDs match by
accident. Divergence surfaces only under sequential/concurrent runs sharing one
`RunStore` — exactly the batch-lab regime (`macro_advance.py` runs A/B against one store).

---

## Fingerprint, truth owner, lie-prone layer

- **Fingerprint:** `run.py floor_show({"runId":…})` + `runRef` reads `run` only + silent
  `"latest"` fallback + `resolveRun("latest") = max(createdAt)` → wrong `floor-show.json`.
- **Truth owner:** the persisted `TeamRun.id` the caller intended — i.e.
  `team_start.runId`, mirrored in `experiment.json.run.runId`. The *selector contract* is
  owned by `ContractRegistry+Milestone1.swift` (declares `floor_show` param = `run`).
- **Lie-prone layer:** the MCP query-argument adapter `AllnighterCLI.runRef(from:)`. It
  silently upgrades an explicit-but-unrecognized selector into a global `latest`. The
  amplifier — not the key mismatch — is the real danger: **an explicit run id degrading
  to `latest`.** `FloorProjector`, `RunStore`, and the GUI are all honest; they project
  whatever run the adapter chose.

---

## The SEAM (and why a one-side proof is a trap)

The bug lives at **Python harness JSON args ↔ Swift MCP resolver + generated contract.**

Two adjacent truths make it deceptive:
- Lifecycle tools (`team_status`/`team_result`/`team_cancel`) *correctly* use `runId`
  (`MCPAsyncTeamHandlers`), so `runId` looks right by muscle memory.
- `alln floor show <id>` (positional) and `team_result({"runId":…})` both return the
  correct run — proximity proofs that disguise the query-tool path being broken.

**One-side-proof trap (carry this into the proof method):** a green Swift `runRef` unit
test does **not** prove the lab is fixed. The lab spawns a *separate* `alln` binary
(`Packages/AllnighterCore/.build/debug/alln`, overridable via `ALLN_BIN`) against a
`RunStore` chosen by `ALLNIGHTER_SUPPORT_DIR`. A stale binary or mismatched support dir
reproduces the identical symptom against correct source. Only an end-to-end MCP roundtrip
across the Python↔Swift seam decides "fixed."

---

## Ranked hypothesis ladder

| # | Hypothesis | Cheapest experiment | Rules out | Status |
|---|------------|---------------------|-----------|--------|
| **H1** | Caller passed `runId`; server read `run` only and fell back to `latest`. | Read `run.py:413` + `runRef`; `runRef(["runId":"X"])`. | H3 (schema), H4 (race). | **CONFIRMED root cause** — fixed in tree. |
| **H2** | Silent `"latest"` fallback *amplifies* any unrecognized selector into wrong-run data (the actual harm). | `resolveRun("latest")` returns `max(createdAt)` with no warning/error. | "harmless typo" framing. | **CONFIRMED amplifier.** |
| **H3** | Schema/tool-definition drift — contract advertises `runId`. | `ContractRegistry+Milestone1.swift:155` declares param `run`. | — | **RULED OUT** — contract says `run`; harness was wrong. |
| **H4** | Async/timing race on a single run. | Fallback is deterministic once key absent. | — | **RULED OUT** — not racy; deterministic. |
| **H5 (minority)** | Symptom persists in current tree despite correct source → lab runs a **stale `alln` binary** or mismatched `ALLNIGHTER_SUPPORT_DIR`. | Inspect a failing `.lab` dir for `allnBinary`/`supportRoot` vs source; rerun H2-proof against the *deployed* binary. | "source is wrong." | **OPEN / preserved** (Contrarian Root Cause). Only relevant if red after rebuild+redeploy. |

**Already ruled out — do not re-test:** schema drift (H3), single-run timing race (H4),
`FloorProjector`/`RunStore`/GUI correctness (honest, downstream of the selector),
`team_result` path (uses `runId` directly, never affected).

---

## Smallest correct fix (TOP hypothesis = H1+H2) and fix boundary

Two-part minimal fix, **both already applied in the working tree**:

1. **Caller (required):** `scripts/team_lab/run.py:413` calls
   `floor_show({"run": run_id})` — the documented canonical key.
2. **Server defense (recommended, applied):** `runRef(from:)` accepts `runId` as an alias
   when `run` is absent; `run` wins when both present; empty/whitespace → `"latest"`.

**Fix boundary — apply ONLY here. No opportunistic refactor:**
- ✅ `scripts/team_lab/run.py` (one call site).
- ✅ `AllnighterCLI.runRef(from:)` (single function).
- ✅ `MCPAsyncTeamTests.testRunRefAcceptsRunOrRunId` (test).
- ❌ Do **not** touch `team_status`/`team_result`/`team_cancel` (`runId` is correct there).
- ❌ Do **not** touch `resolveRun`, `FloorProjector`, `RunStore`, or GUI paths.
- ❌ Do **not** add `runId` to `ContractRegistry`/`mcp-tools.json` — the resolver alias is
  enough; contract churn is out of scope.
- ❌ Do **not** remove the `resume_writer.py` CLI bypass (belt-and-suspenders).

**Recorded minority dissent on the fix shape (preserved, not adopted):** *Correct Fix
Planner* and *Trace Mapper* argue the server should **error (`CLI_USAGE_ERROR`/
`RUN_NOT_FOUND`) rather than alias** an `runId`-only call, on the grounds that a tolerant
alias normalizes the very convention drift that caused this and weakens the contract. The
writer adopts the tolerant alias because the dominant safety invariant is "explicit id
never silently becomes `latest`," which the alias satisfies while keeping lifecycle muscle
memory from re-breaking query tools — but the stricter "fail loud" stance is the better
long-term contract hardening and is logged as a follow-up worth revisiting if any *third*
caller convention appears.

---

## Proof method (what decides "fixed")

A passing single-layer test is **not** proof here (see seam trap). Tiered:

1. **Unit (necessary, not sufficient):**
   `swift test --package-path Packages/AllnighterCore --filter MCPAsyncTeamTests/testRunRefAcceptsRunOrRunId`
   — asserts `["runId":"AAA"]→"AAA"`, `["run":"BBB"]→"BBB"`, both→`run` wins, `[:]`/blank→`"latest"`.

2. **End-to-end seam kill test (DECIDES it) — to add:**
   `scripts/team_lab/test_mcp_floor_show_run_id.py`. Under an isolated
   `ALLNIGHTER_SUPPORT_DIR`, seed `RA` (older) + `RB` (latest), launch the **deployed**
   `alln mcp` stdio server, call `floor_show({"run":"RA"})` *and* `floor_show({"runId":"RA"})`;
   assert both structured `run.id == "RA"`. This is the only proof that closes H5 because it
   exercises the real binary across the Python↔Swift boundary. Repo already has
   `mcp_client.py` + `ALLNIGHTER_SUPPORT_DIR` isolation, so **no new isolation harness is
   required** — the harness is the existing stdio MCP client.

3. **Artifact gate (existing):** `score_run_contract(..., expected_run_id=RA)` —
   `floor_show_run_id` check at `scoring.py:178` is red on the bug, green on the fix.
   Suite case `floor_show_wrong_run_v1` (in `bug_hunt_necessity_v1` /
   `bug_hunt_repo_regressions_v1`) is the standing gate.

4. **One-time audit (H5 hygiene):** scan historical `.lab/*/` for
   `floor-show.json.run.id != experiment.json.run.runId`; quantify past contamination.

**Regression law (one line):** *Query MCP tools (`show`, `spec_get`, `floor_show`) must
never resolve `"latest"` when the caller supplied a concrete run id under either `run` or
`runId`.*

---

## Confidence as ordering (not a gate)

- **H1+H2 confirmed by code inspection** (run.py, runRef, resolveRun, contract all read
  directly). Expect **0 further rounds** for the primary fix — it's in tree and unit-green.
- **Remaining uncertainty is operational, not logical (H5).** Expect **1 round**: rebuild
  + redeploy the lab `alln`, run the end-to-end kill test (proof #2). If red there with
  correct source, pivot to H5 (stale binary / support-dir mismatch) — do not re-touch
  `runRef`.
- Severity ranking (writer decision, resolving the seat split): **High for Team Lab batch
  integrity; effectively zero for shipped product.** `team_result` (the real packet
  source) and the Mac/CLI Floor paths were never affected. *Bug Reproducer*'s "Medium"
  applies to single-run cases; the High tier is the batch/macro regime. Recorded both.

---

## Severity

| Dimension | Verdict |
|---|---|
| Product / user-visible | **None** — GUI `FactoryFloorView` and `alln floor show` use unaffected paths. |
| Team Lab / batch integrity | **High** — wrong-run `floor-show.json` under shared `RunStore`. |
| Scoring | `floor_show_run_id` false → lower `runContractScore`; can mask substrate health in macro rollups. |
| Result packet | **Unaffected** — sourced from `team_result` (`runId`, correct). |
| Tier | **T2 SSOT** (cross-layer persisted drift: experiment `runId` vs `floor-show.json`). |

---

```fix-packet
seam: python-team-lab MCP args  <->  swift MCPServer/runRef + generated contract
truthOwner: persisted TeamRun.id intended by caller (team_start.runId == experiment.json.run.runId); selector contract owned by ContractRegistry (floor_show param = "run")
liePropneLayer: AllnighterCLI.runRef(from:) — silent fallback of an explicit selector to "latest"
severity: High (Team Lab batch integrity) / None (product); tier T2 SSOT
status: FIXED IN WORKING TREE (verified 2026-06-24) — uncommitted

rankedHypotheses:
  - id: H1
    claim: caller passed runId; runRef read "run" only -> fell back to "latest"
    experiment: read run.py:413 + runRef; runRef(["runId":"X"])
    rulesOut: H3, H4
    fix: run.py -> floor_show({"run": run_id})  (DONE)
    fixBoundary: scripts/team_lab/run.py:413 only
    status: CONFIRMED root cause
  - id: H2
    claim: silent "latest" fallback amplifies any unrecognized selector into wrong-run data
    experiment: resolveRun("latest") == RunStore.list().max(createdAt), no warning
    rulesOut: "harmless typo" framing
    fix: runRef accepts runId alias when run absent; run wins if both; blank->latest  (DONE)
    fixBoundary: AllnighterCLI.runRef(from:) single function
    status: CONFIRMED amplifier
  - id: H3
    claim: schema advertises runId
    experiment: ContractRegistry+Milestone1.swift:155 -> param "run"
    status: RULED OUT
  - id: H4
    claim: async/timing race on single run
    experiment: fallback deterministic once key absent
    status: RULED OUT
  - id: H5
    claim: (minority) symptom persists despite correct source -> stale alln binary or mismatched ALLNIGHTER_SUPPORT_DIR
    experiment: inspect failing .lab dir allnBinary/supportRoot; rerun e2e proof vs deployed binary
    fix: rebuild+redeploy lab alln / fix ALLN_BIN / fix support dir — NOT a runRef change
    status: OPEN (preserved; only if red after rebuild)

ruledOut:
  - schema drift (contract declares "run")
  - single-run timing race (deterministic fallback)
  - FloorProjector / RunStore / GUI correctness (honest, downstream of selector)
  - team_result path (uses runId directly, never affected)

proofMethod:
  necessary: swift test --package-path Packages/AllnighterCore --filter MCPAsyncTeamTests/testRunRefAcceptsRunOrRunId
  decisive: scripts/team_lab/test_mcp_floor_show_run_id.py (implemented) — isolated ALLNIGHTER_SUPPORT_DIR, seed RA(old)+RB(latest), launch DEPLOYED alln mcp stdio, assert floor_show({"run":RA}) AND floor_show({"runId":RA}) both return run.id==RA (closes H5; exercises real binary across seam). Verified PASS on 2026-06-24.
  gate: score_run_contract(expected_run_id=RA) floor_show_run_id @ scoring.py:178; suite case floor_show_wrong_run_v1
  audit: scan historical .lab/*/ for floor-show.json.run.id != experiment.json.run.runId
  isolationHarness: NOT required — existing mcp_client.py + ALLNIGHTER_SUPPORT_DIR suffice
  trap: passing runRef unit test alone is NOT proof (lab spawns separate alln binary / support dir)

regressionLaw: query MCP tools (show, spec_get, floor_show) must never resolve "latest" when caller supplied a concrete run id under either run or runId

dangerFlags: NONE (no credentials, no deletion, no deploy, no billing). Auto-attempt safe — bounded to one resolver fn + one python call site + one test.

minorityPositions:
  - fixShape: Correct Fix Planner + Trace Mapper prefer server ERROR (CLI_USAGE_ERROR/RUN_NOT_FOUND) over tolerant alias; writer adopted alias for the "never silently latest" invariant; strict-fail logged as follow-up.
  - severity: Bug Reproducer rates Medium (single-run); writer rates High for batch/macro regime. Both recorded.
  - openCause: Contrarian Root Cause H5 (stale binary/support dir) preserved as the only path if e2e proof is red post-rebuild.
```

---

## Specialist Evidence Disposition

Every seat's unique, line-cited evidence — carried / rejected / suppressed. No silent drops.

- **Bug Reproducer** — `resume_writer.py:156` documents the live workaround ("MCP floor_show can return a stale run id"); `scoring.py:178` guard; the observation that *on-disk* `run.py:413` already uses `{"run": run_id}`. → **Carried forward** (workaround → "don't remove the CLI bypass"; on-disk state confirmed by writer).
- **Truth Owner Mapper** — `runRef` source 1091–1098; note that `docs/team-lab/reports/spec_upgrade_calibration_r1-r4.md` *claimed* the alias landed while code disagreed. → **Carried forward** (the claim-vs-code gap is now closed in tree; cited as the reason H5 audit matters).
- **Correct Fix Planner** — worker-process / cwd inventory (`ProjectVerificationService` at project root, `CatalogRunCoordinator` warm-process cwd) and that `run.py`'s MCP server subprocess is **not** ProbeScratch-guarded. → **Rejected for the fix boundary** (cwd/ProbeScratch is not on the run-selector seam) but the *strict-fail* stance is **carried forward** as recorded minority dissent.
- **Regression Guard** — concrete test names + the facts that `mcp_client.py` and `ALLNIGHTER_SUPPORT_DIR` isolation already exist (so no new harness needed). → **Carried forward** into Proof Method #2.
- **Trace Mapper** — full layer map; contract-vocabulary inconsistency (`run` for query vs `runId` for lifecycle) as the structural cause. → **Carried forward** (seam framing + minority strict-fail position).
- **State Skeptic** — `RunStore.list()` is a fresh FS scan with no caller-owned pin; `testRunRefUsesCanonicalRunArgumentOnly` previously *codified the drift*. → **Carried forward** (explains why fallback is FS-global; test now replaced by `testRunRefAcceptsRunOrRunId`).
- **Change Impact Reviewer** — blast-radius table; **`macro_advance.py` parallel A/B share one `RunStore` → latent contamination** (the concrete batch trigger); suite cases `floor_show_wrong_run_v1`. → **Carried forward** (justifies the High batch severity and the macro regime in Repro/Confidence).
- **Contrarian Root Cause** — `run.py` defaults to `.build/debug/alln`, `ALLN_BIN` override; stale-binary / mismatched-support-dir alternate cause. → **Carried forward** as H5 (preserved minority/open cause and the e2e proof requirement).
- **User Impact Narrator** — trust framing ("a specific run request must never return some other latest run"); reported tests **could not run** in its sandbox (`sandbox-exec` denied; `pytest` absent). → **Carried forward** (regression-law phrasing; the non-execution is noted so no false "verified" is implied — writer ran the on-disk verification instead).

**suppressed:** *(empty — every seat's unique evidence is dispositioned above.)*
