# ASR-S07 — clear the pre-existing red so `check.sh` can go green

Status: **ready**
Priority: **P1 — blocks §10's "focused proofs and `bash scripts/check.sh` pass".**
Scope note: these failures are **not** ASR's. A baseline run at `32f7aa5c`
(pre-`uninstall`) produced **88 tests, 14 failures** — byte-identical to the
current tree's 88/14 in the same filter. ASR introduced exactly one check.sh
failure (stale generated contract artifacts) and it is already fixed. The
founder has directed that these be cleared so the packet can close.

## 0. The rule that matters more than going green

**Do not loosen an assertion, bound, or budget to make a test pass.** Several of
these look like genuine product defects. For each failure, decide which is
wrong — the product or the test — and fix that one. If the only way to pass is
to relax a check, **stop and report that failure instead**; a green suite bought
by weakening a gate is worse than a red one, and this repo's laws say so
explicitly.

State per failure, in the commit message: *product was wrong* or *test was
wrong*, and why.

## 1. The seven failures

| # | Test | Message | First read |
| --- | --- | --- | --- |
| 1 | `BuiltInTeamsTests.testNoHardcodedWorkerIdentityOutsideSignalLane` | `code_ai_readiness` worker `readiness_loop_scout` hardcodes model identity `model_gpt_sol` outside the signal lane (**Law 3**) | **product** — a team definition violates a stated law. Fix the definition, do not delete the test. |
| 2 | `CapacityHistoryStoreTests.testRecordCallPerformsNoAcquisition` | `("3") is not equal to ("2")` — record must not create vendor-side artifacts outside store files | **product** — a `record` call is creating an artifact it should not. Find what the third file is. |
| 3 | `FrontDoorTests.testEmptyBenchModelsJSONIncludesCounselNotBareArray` (7 assertions) | empty bench models JSON should carry counsel, not a bare array; expects `nextAction` = `alln menu --json` | diagnose — either the front door stopped emitting counsel, or the contract moved. |
| 4 | `MenuSelectionCopyAuthoredBoundsTests.testEveryAuthoredEntryWithinBoundsAndNotBannedStub` | authored `MenuSelectionCopy` bounds/stub failures | read the full assertion output; it names the offending entries. |
| 5 | `MenuSelectionGradeTests.testPerRowBoundsAndBuiltInFixtureStillWithin25KiB` | built-in Tier-1 MenuJSON **25671** exceeds 25 KiB | see §2 — special handling. |
| 6 | `OneRunSurfaceDispatchReadinessTests.testDriversAndModelsStillReportNotInstalledAsNotReady` | `"Grok not found on PATH or known paths"` != `"Not installed"` | diagnose — a readiness string changed, or the test encodes a message that is no longer the product's. |
| 7 | `SpendingCommandTwinTests.testEverySpendingCommandHasFreeTwin` | spending commands missing `freeTwinCommand`: `["detect"]` | **product/contract** — `detect` spends and has no free twin declared. |

## 2. The size budget — do not just raise the ceiling

`MenuJSON` is 25671 bytes against a 25600 budget. **It was already over before
this packet**: the baseline measured **25603**. So the budget was breached by 3
bytes by earlier work, and `alln uninstall` added ~68 more.

Order of preference:

1. **Trim authored copy** so the fixture fits under 25600. Menu copy is the
   product's own text and is the thing the budget is protecting.
2. If it genuinely cannot fit — say so with the measurement, and **stop**.
   Raising the number is a product decision about how large the agent-facing
   menu payload may be, and it belongs to the founder, not to this slice.

Do **not** silently change `25600`.

## 3. Read only

- The seven test files named above — each states its own expectation.
- Whatever source each failure points at. Follow the failure, do not go
  exploring.
- `AGENTS.md` § Project Laws for Law 3 (failure 1).

## 4. Touch only

Whatever the diagnosis requires, subject to §0 — but **not**:

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemon.swift
Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift
Packages/AllnighterCore/Sources/AllnighterEngine/ServeStatusJSON.swift
Packages/AllnighterCore/Sources/AllnighterCore/CanonicalCLIInstall.swift
Packages/AllnighterCore/Sources/AllnighterCore/UninstallCLI.swift
scripts/works-test-serve-continuity.sh
scripts/validate_architecture_policy.py
config/architecture-policy.json
docs/**
```

The ASR surfaces are green and proven by host gates. Do not touch them.

## 5. Steps

1. **One failure at a time**, in the table's order. Re-run only that suite
   between fixes so you can attribute each change.
2. **Diagnose before editing.** For each, say in one line what is actually
   broken. A fix whose author cannot state the cause is a guess.
3. **Fix the product where the test is right** — expected for 1, 2 and 7.
4. **Fix the test only where it is provably stale**, and say what changed in the
   product that makes the old expectation wrong. "It fails" is not evidence the
   test is wrong.
5. **Failure 5 per §2.** Trim, or stop and report the measurement.
6. **Do not touch the GUI visual proof gate.** It is handled separately.

## 6. Works Test

```bash
scripts/swift-test.sh --filter 'BuiltInTeamsTests|CapacityHistoryStoreTests|FrontDoorTests|MenuSelectionCopyAuthoredBoundsTests|MenuSelectionGradeTests|OneRunSurfaceDispatchReadinessTests|SpendingCommandTwinTests'
bash scripts/rebuild_cli.sh
```

Target: **88 tests, 0 failures** in that filter. Report the real number; if any
failure is left standing under §0 or §2, say which and why rather than forcing it.

## 7. Done when

- [ ] Each of the seven is fixed, or explicitly reported as needing a founder
      decision under §0/§2.
- [ ] Every fix names *product was wrong* or *test was wrong*, with the reason.
- [ ] No assertion, bound or budget was loosened to pass.
- [ ] `rebuild_cli.sh` passes.
- [ ] ASR surfaces untouched.
- [ ] One commit.

## 8. Host-state invariant

None of these touch serve, install, or the LaunchAgent. The founder's bench is
unaffected.
