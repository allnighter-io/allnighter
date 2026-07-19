# Quarantine

Tests or gates that cannot run green yet must be listed here with owner, reason,
and expiry. Expired quarantine entries should fail the green wall once CI exists.

Format:

```text
- <command or test path>: owner <name>, reason <why>, expiry YYYY-MM-DD
```

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
- `scripts/check_gui_proof.sh` / `Apps/AllnighterMac/Sources/ThreadView.swift`:
  owner GUI, reason content-hash proof stale; no GUI changes in RLR-S06.
  Local override: `ALLNIGHTER_GUI_PROOF_WAIVER=…`. expiry **2026-08-02**.

No RLR-owned suites are quarantined.
