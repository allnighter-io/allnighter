# Quarantine

Tests or gates that cannot run green yet must be listed here with owner, reason,
and expiry. Expired quarantine entries should fail the green wall once CI exists.

Format:

```text
- <command or test path>: owner <name>, reason <why>, expiry YYYY-MM-DD
```

## Active — SH-S00 (2026-07-20)

Alln Sharpening entry gate (`docs/archive/phases/Alln_Sharpening.md` SH-S00). The three
SH-S00-owned failures are **fixed** (not quarantined): contract fixture /
`ContractRegistryTests` → `2.1.0`; `CodeReviewParallelSafety` maxConcurrent in
`testDisjointFindingsTouchesAreSafe`; hermetic `ALLNIGHTER_SUPPORT_DIR` for
`ExecutionLaneTests` + `RunAcceptanceBoundaryTests`.

Focused owned proof is green:
`swift test --package-path Packages/AllnighterCore --filter 'CodeReviewParallelSafety|ContractRegistryTests|ExecutionLaneTests|RunAcceptanceBoundaryTests'`.

Remaining reds below are **out of Alln Sharpening product scope**. They are
quarantined so SH-S01 can start with an attributable wall (owned green + named
quarantine for the rest). Receipt: `/tmp/alln-wall-s00-after.txt` (full package
wall) plus Relay re-runs that abort the process.

### Named remaining reds (observed)

- `CursorAgentTests.testCodeCorePrefersCursorComposer25`: owner staffing /
  ModelCatalog, reason Code-core preferred staffing drifted
  (`model_opus`/`model_chatgpt` vs expected Cursor Composer), expiry **2026-08-02**.
- `DefaultConfigDriftTests` (`testEmbeddedManifestsMatchBundledCoreFields`,
  `testEmbeddedWorkersMatchModelCatalogBuiltIns`): owner platform / config
  sync, reason missing Mac `Drivers/kimi.json` + OpenCode / label drift vs
  bundled catalog, expiry **2026-08-02**.
- `ExecutionTeamSourceGateTests.testMixedSourceJudgmentTeamPassesSourceGate`:
  owner Unified Run Model / source gate, reason mixed-source judgment team no
  longer passes the source gate assertion (pre-existing vs SH product scope),
  expiry **2026-08-20**.
- Pilot / ProcessOwnership / Relay crash bucket (same RLR-S06 class):
  - `PilotCoordinatorTests` (multiple: continue / handover / maxRounds /
    idleTimeout / stagnation)
  - `PilotThreadProjectionTests` (continue round + dev turn projection)
  - `ProcessOwnershipHarnessProofTests.testHarnessProofTimeoutStampsEndReasonAndEmptiesGroup`
  - `ProcessOwnershipStandingInvariantTests` (clean + stale delivered-turn)
  - `ProcessOwnershipTurnKillTests` (reported + stalled budget endReason)
  - `RelayAdoptTests` (adopt / adoption-prompt cases)
  owner Pilot/Relay / ProcessOwnership, reason coordinator + standing-invariant
  unwraps / crashes outside Sharpening, expiry **2026-08-02**.
- `RelayCLITests.testParseStartConfigCustomMaxRoundsAndUntil` (and remainder of
  suite after it): owner Relay CLI, reason `WORKER_NOT_AVAILABLE` for fixture
  worker id `model_pm` prints an error envelope then **aborts the test process**
  (wall truncation), expiry **2026-08-02**.
- `RelayCoordinatorTests` (at least
  `testAmbiguousStallRetryAppendsPartialCompletionHint`): owner Relay
  coordinator, reason `Fatal error: Index out of range` (signal 5) — aborts
  process; post-truncation Relay/Remote suites after this abort are
  **unobserved on the full wall** until RelayCLI/coordinator abort is fixed,
  expiry **2026-08-02**.

### Post-truncation note

Full `swift test --package-path Packages/AllnighterCore` does not finish after
`RelayCLITests` abort. Suites alphabetically after `RelayCLITests` (Relay*
remainder, Remote*, …) were not attributed on that run. Re-probe those families
only after the Relay abort is repaired; until then treat them as covered by the
Relay/Pilot crash quarantine above, not as silent green.

### Not quarantined (SH-S00 owned — now green)

- Contract fixture `team_run.json` / `ContractRegistryTests` `2.1.0`
- `CodeReviewParallelSafetyTests`
- `ExecutionLaneTests` / `RunAcceptanceBoundaryTests` (hermetic support dir)

## Active (RLR-S06 closeout, 2026-07-19)

Pre-existing **non-RLR** green-wall failures observed while closing
`Run_Lifecycle_Reliability.md` S06. RLR focused filter is green; spawn-policy
gate is green. These are quarantined so the phase can close without mixing
unrelated repair into the lifecycle gate.

- `bash scripts/check.sh` (full `swift test --package-path Packages/AllnighterCore`):
  owner platform / follow-up maintainer, reason pre-existing suite failures
  outside RLR (AgentHello/IR drift, contract/help drift, DefaultConfigDrift
  missing kimi/OpenCode resource, Pilot/Relay coordinator crashes + standing
  invariant unwraps, PanelCLI alias, CodeReviewParallelSafety, CursorAgent
  staffing). RLR proof remains:
  `swift test --package-path Packages/AllnighterCore --filter 'RunLifecycle|KillSettlement|RunContradiction|RunClock|Idempotency|RetryOf|RunAcceptance'`.
  expiry **2026-08-02**.
  **SH-S00 note (2026-07-20):** CodeReviewParallelSafety and PanelCLI are no
  longer red on the SH-S00 wall; see SH-S00 section for the attributable
  remaining list. Do not treat this blanket RLR bullet as authority over the
  SH-S00 named list.
- `scripts/check_gui_proof.sh` / `Apps/AllnighterMac/Sources/ThreadView.swift`:
  owner GUI, reason content-hash proof stale; no GUI changes in RLR-S06.
  Local override: `ALLNIGHTER_GUI_PROOF_WAIVER=…`. expiry **2026-08-02**.

No RLR-owned suites are quarantined.
