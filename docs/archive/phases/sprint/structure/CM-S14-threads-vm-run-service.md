# CM-S14 — Extract ThreadsViewModel run service

Status: done (`ba1665ac`, Gemini via `alln run`)
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Move run execution, caching, live artifact, and vendor park/resume out of
`ThreadsViewModel.swift` into `ThreadsViewModel+RunService.swift`. **Move only.**

## Copy-paste prompt

```text
Implement CM-S14 only. Read docs/operations/code-maintainer/plans/ThreadsViewModel-split.md.

Touch ONLY:
- Apps/AllnighterMac/Sources/ThreadsViewModel.swift (remove moved code)
- Apps/AllnighterMac/Sources/ThreadsViewModel+RunService.swift (NEW extension)

Move these members from the routing composer area:
- makeRunService, runViaRunService
- applyLiveArtifactEvent, ensureLiveArtifactSeed, applyTerminalSettlement
- readyModels, effectiveModelId
- runCache, liveArtifact(forRunId:), teamRun(forRunId:), invalidateRunCache
- resumeParkedVendorRun, vendorSubstitutionCandidates, substituteParkedVendorRun,
  cancelParkedVendorRun, prefetchTerminalRuns
- appendFailedRun
- turnStatus(for:), settledStatus(forSuccessfulRun:) static methods

Use `extension ThreadsViewModel { }`. Widen `private` → `internal` as needed.
runCache and liveArtifactByRunId stay owned on ThreadsViewModel.

Proof:
cd Apps/AllnighterMac && xcodegen generate && xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'

Commit only the two Swift files above.
Message: refactor(mac): extract ThreadsViewModel run service (CM-S14)
```

## Works Test

```text
xcodebuild build -scheme AllnighterMac -destination 'platform=macOS'
```
