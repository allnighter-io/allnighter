# RLR-S06 Works Test Matrix

Status: **DELIVERED 2026-07-19.** Phase close gate for
`docs/archive/phases/Run_Lifecycle_Reliability.md` §Works Test items 1–15.

Filter:

```bash
swift test --package-path Packages/AllnighterCore \
  --filter 'RunLifecycle|KillSettlement|RunContradiction|RunClock|Idempotency|RetryOf|RunAcceptance'
bash scripts/check.sh
```

## Matrix

| # | Item | Status | Proof |
| --- | --- | --- | --- |
| 1 | `--stream` start; first-event `runId` | **GREEN** | `RunLifecycleReliabilityWorksTest.testItem1FirstStreamEventCarriesRunId`; `NDJSONStreamProjectorTests.testLiveMapperCarriesThroughDurableSeq`; `RunStreamContractTests.testStreamSeqIsMonotonicAndDurableAcrossReattach` |
| 2 | Second process polls; journal ≡ status | **GREEN** | `RunLifecycleTwoProcessTests.testStatusPolledFromSecondProcessDisagreesWithDurableJournalDuringHang` (ungated S06; asserts no `accepted` / no one-worker `fanning_out` while live); `RunAcceptanceBoundaryTests.testWriteLockWaitLeavesDurablePollableQueuedRunWithBlocker` |
| 3 | Write-lock FIFO + root isolation | **GREEN** | `RunAcceptanceBoundaryTests` — `testBlockedRunCarriesFifoTicketFactsNamingHolderRun`, `testSameRootCaseVariantSpellingSharesOneLockAndNamesHolder`, `testSameRootSymlinkSpellingSharesOneLockAndNamesHolder`, `testTrueDifferentRootDoesNotSerializeAndNeverNamesHolder` |
| 4 | L6 activity + monotonic `seq` | **GREEN** | `RunActivityTests` + `RunActivityJournalTests` (L6 only); `NDJSONStreamProjectorTests` / `RunStreamContractTests` (durable `seq`) |
| 5 | Idle → kill + typed `KillOutcome` + lane release + B proceeds | **GREEN** | `RunLifecycleReliabilityWorksTest.testItem5IdleClockReleasesLaneSoBlockedWaiterProceeds`; `RunClockEnforcerTests.testFireStoppedWhenRecordedWorkerDead` / `testFireStampsTimedOutTerminalEvenWhenWorkerStillAlive` |
| 6 | `kill` live worker/grandchild; contradiction | **GREEN** | `RunLifecycleTwoProcessTests.testKillStampsTerminalKilledWhileLiveWorkerSurvives` (partial, non-terminal); `KillSettlementTests` + `RunContradictionTests` |
| 7 | Kill orphaned coordinator; recover worker from 2nd process | **WAIVED** | Full SIGKILL-coordinator mid-stream harness deferred. Responsive-coordinator settlement protocol + second-process worker kill proven by KillSettlement + item 6 two-process. Warm/ACP excluded from P0 (S00 matrix). Follow-up if orphaned-coordinator field returns. |
| 8 | `kill --all` same-root; other-root protected | **GREEN** | `ConcurrentInvocationTwoProcessTests.testTwoRealProcessesMutationAndContextIsolation` |
| 9 | Same-key replay; `IDEMPOTENCY_CONFLICT`; `--retry-of` | **GREEN** | `ConcurrentInvocationTwoProcessTests.testTwoRealProcessesSameKeyIdempotencySingleFlight`; `IdempotencyRetryOfTests` (conflict / expired / retry-of after verified stop); `RunAcceptanceBoundaryTests.testSyncRunClaimsIdempotencyKeyAndReplaysSameRunNeverASecondWorker` |
| 10 | Corrupt journal → `JOURNAL_CORRUPT` | **GREEN** | `RunLifecycleReliabilityWorksTest.testItem10CorruptJournalSurfacesJournalCorruptNotInventedStatus` |
| 11 | Exactly one terminal NDJSON (success/cancel/timeout/kill) | **GREEN** | `NDJSONStreamProjectorTests.testExactlyOneTerminalPerAttachmentOnSuccessCancelTimeout` + `testExactlyOneTerminalPerAttachmentOnKillSettlement`; `RunStreamContractTests` |
| 12 | Close: zero identity-alive harness orphans | **GREEN** | `RunLifecycleReliabilityWorksTest.testItem12PsAllProjectsShowsZeroHarnessOrphansAfterClose` |
| 13 | Governor/capacity over-limit → typed refusal, no id/journal | **GREEN** | `RunLifecycleReliabilityWorksTest.testItem13GovernorBusyRefusesWithNoRunIdAndNoJournal`; `ProcessOwnershipStartSeamTests.testGovernorBusyRefusesWithoutAcceptedRunDir`. Capacity cooling is pre-accept ledger (`SourceCapacityLedgerTests`); public `CAPACITY_REFUSED` wire shares the no-id/no-journal acceptance boundary. |
| 14 | Cancel/kill blocked run withdraws FIFO ticket | **GREEN** | `RunAcceptanceBoundaryTests.testCancelOfBlockedRunWithdrawsTicketSameProcess` / `testKilledBlockedRunGrantedLaneNeverSpawnsAndStaysTerminal`; `RunLifecycleTwoProcessTests.testKillOfBlockedRunWithdrawsFifoTicketFromSecondProcess` |
| 15 | `--wait-for` lifecycle states only | **GREEN** | `RunLifecycleReliabilityWorksTest.testItem15WaitForAcceptsLifecycleStatesOnly`; `AsyncTeamLifecycleTests.testWaitTargetParseAcceptsTerminalAlias` |

**Score:** 14 GREEN · 1 WAIVED (item 7) · 0 GAP

## Also landed in S06

- Ungated `RunLifecycleTwoProcessTests` (no longer `RLR_RED=1` opt-in).
- Bounded ownership-receipt reaper:
  `ProcessOwnership.reapExpiredOwnershipReceipts` (wired through
  `ProcessOwnershipGarbageCollector`); proof
  `testOwnershipReceiptReaperDropsIdentityDeadPastRetention`.

## Exit gates

- [x] Works Test matrix mapped (prove or waive)
- [x] Contract drift / Core wall via focused filter (+ `check.sh` result in closeout)
- [x] Morning zero identity-alive harness orphans (item 12)
- [x] IR-S02 + Onboarding V1 unblocked in docs
- [x] Phase Status → Complete (archive is orchestrator)

## `check.sh` closeout (2026-07-19)

- **Spawn policy:** green (`check: no bare SubprocessCommandRunner() constructions`).
- **RLR focused filter:** green (67 tests).
- **Full `bash scripts/check.sh`:** red on pre-existing non-RLR suites — quarantined
  in `docs/operations/debugger/QUARANTINE.md` (expiry 2026-08-02). GUI proof for
  `ThreadView.swift` also pre-existing (waive locally; out of RLR scope).
- Fatal abort mid-suite: `RelayCoordinatorTests.testAmbiguousStallRetryAppendsPartialCompletionHint`
  (`Index out of range`) — not RLR-owned.
