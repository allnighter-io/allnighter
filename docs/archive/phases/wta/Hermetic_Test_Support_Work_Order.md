# Work Order — make lane/run tests hermetic

Dev seat: `model_gemini` (Antigravity). PM: lead session.

## why

`ExecutionLaneRegistry` (and its `RunWriteLockRegistry` alias), `RunStore`,
`ProcessOwnership` and the relay coordinators all persist under
`AllnighterPaths.support`. Unless a test redirects that root, they write into the
user's **real** `~/Library/Application Support/Allnighter/`.

Consequence already observed: an interrupted run left a live `xctest` holding the
real `v1:test` lane, which poisoned every later run until the directory was
deleted by hand. The same commit produced 0 failures, a hang, and 6 failures
depending only on leftover state.

11 test classes already isolate. 21 do not. This work order fixes those 21.

## the base class already exists — do not write it

`Packages/AllnighterCore/Tests/AllnighterEngineTests/HermeticSupportTestCase.swift`
is written and in place. It redirects `ALLNIGHTER_SUPPORT_DIR` to a per-test temp
directory in `setUpWithError()` and restores/removes it in `tearDownWithError()`.

Your job is only to adopt it in the 21 files below.

## the one trap — read before editing

XCTest does **not** chain `setUpWithError()` for you. A subclass that overrides
it without calling `super` silently bypasses the base class: the test still
compiles, still passes green, and still writes to the user's real data.

So for any file that already overrides these methods you must add the super call.
Getting this wrong produces no visible symptom — which is exactly why it is
called out here.

## do exactly this, per file

**Step 1 — every file:** change the class declaration(s)

```swift
final class Foo: XCTestCase {        ->   final class Foo: HermeticSupportTestCase {
```

**Step 2 — only the files marked `setUp=YES` below:** add the super calls

```swift
override func setUpWithError() throws {
    try super.setUpWithError()      // ADD as the FIRST line
    …existing body unchanged…
}

override func tearDownWithError() throws {
    …existing body unchanged…
    try super.tearDownWithError()   // ADD as the LAST line
}
```

Do not otherwise modify the existing bodies. Do not reorder, tidy, or reformat.

## the exact file list — no judgement required

All paths are under `Packages/AllnighterCore/Tests/AllnighterEngineTests/`.

**Group A — has `setUpWithError` + `tearDownWithError`; needs BOTH super calls (16):**

```
PilotCoordinatorTests.swift
RelayAdoptTests.swift
ExecutionWriteLockTests.swift
SandboxHandoffTests.swift
CanonicalRepoRootInvariantTests.swift
PilotThreadProjectionTests.swift
RunProvenanceTests.swift
RunNoWaitTests.swift
RelayThreadProjectionTests.swift
RunCommitProofTests.swift
SandboxFailFastTests.swift
ResearchGitObservationTests.swift
RunRepoDeltaTests.swift
RunTerminalJournalFailureTests.swift
SingleRunOwnerInvariantTests.swift
RelayCoordinatorTests.swift        ← SPECIAL, see below
```

**Group B — no setUp/tearDown override; superclass change ONLY (5):**

```
FollowUpCoordinatorTests.swift
VendorBackoffReconcilerTests.swift
RunIdentityTests.swift
IdempotencyRetryOfTests.swift
ProcessOwnershipTurnKillTests.swift
```

**`RelayCoordinatorTests.swift` is special:** it declares **three** `XCTestCase`
classes but only **one** of them overrides setUp/tearDown. Change the superclass
on **all three**; add the super calls to **only the one** that already overrides
those methods.

## do NOT touch

- The 11 classes that already isolate — they set `ALLNIGHTER_SUPPORT_DIR`
  inline and are already correct: `ExecutionLaneTests`, `RunWriteLockTests`,
  `TwoSourceResearchTeamTests`, `RunIdleTimeoutTests`, `RunServiceTests`,
  `RunStreamContractTests`, `ExecutionProofTests`, `RunAcceptanceBoundaryTests`,
  `ProcessOwnershipStandingInvariantTests`, `ProcessOwnershipHarnessProofTests`,
  `ProcessOwnershipScopedWriteLanesTests`.
- `HermeticSupportTestCase.swift` itself.
- Any production source under `Sources/`. This is a test-only change.
- Any test assertion, body, or logic. Superclass + super calls only.

## proof required — build only

```bash
swift build --build-tests --package-path Packages/AllnighterCore
```

Must compile with zero errors. Report the result.

**Do NOT run `swift test`.** The suite takes ~2 minutes, and a seat that launches
a long command and waits for it has its turn END mid-wait, losing the work. I run
the suite, and I verify hermeticity empirically by checking whether the real
support root gains lane state — green tests do not prove this change worked.

## then commit — this is your completion signal

I detect completion by watching git, not by reading your report.

```bash
git add <the files you actually changed>
git commit -m "test: adopt HermeticSupportTestCase in lane/run tests"
```

Stage explicit paths only — never `git add -A` or `git add .`. Do not discard,
rewrite, or force-update history; commit forward only.

## stop conditions

1. If a file's class declaration does not match `: XCTestCase`, STOP and report it.
2. If a file needs a change outside the two steps above, STOP and report.
3. If anything tempts you to edit a test body or assertion, STOP and report.

## report

Final build result, commit SHA, how many files changed, and confirm you added
super calls to all 16 Group A files.
