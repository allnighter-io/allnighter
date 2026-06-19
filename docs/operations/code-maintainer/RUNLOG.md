# Code Maintainer Runlog

```text
## 2026-06-19 - Batch 2

Scope: Duplication lens (index 1)
Class: Bounded dedup — setup roster grouping, status pills, action handlers, invocation map
Lens: Duplication (index 1)
Files touched: Apps/AllnighterMac/Sources/{SetupViews,ReadinessView,AppSetupModel,AppModel,ThreadsViewModel}.swift; docs/operations/code-maintainer/{RUNLOG,HEALTH}.md
Behavior guarantee: No UI restyle; same setup roster groups, pill labels, and repair actions
Proof: swift test --package-path Packages/AllnighterCore (639 tests, 0 failures); xcodebuild test -scheme AllnighterMac (84 tests, 0 failures); bash scripts/check.sh
Before/after signal: Extracted SetupCardBuckets, SetupCardState roster/repair pills, SetupActions.handle; AppSetupModel.invocations shared by AppModel + ThreadsViewModel
Next lens: Dead weight (index 2)
```

```text
## 2026-06-19 - Batch 1

Scope: Hot-fix cleanup health-check scout (Structure lens)
Class: Scout + bounded queue seed from HOT_FIX_CLEANUP.md
Lens: Structure (index 0)
Files touched: docs/operations/code-maintainer/{RUNLOG,MAINTENANCE-QUEUE,HEALTH}.md
Behavior guarantee: Readonly scout; no product behavior changes in this batch
Proof: swift test --disable-sandbox --package-path Packages/AllnighterCore (639 tests, 0 failures); xcodebuild test -scheme AllnighterMac (84 tests, 0 failures)
Before/after signal: Identified ThreadsViewModel (986 LOC), AppModel (791), DesignComponents (904), RootView (517) as top Mac shell pressure; compile hot fix already landed on mutatingRun cutover
Next lens: Duplication (index 1)
```
