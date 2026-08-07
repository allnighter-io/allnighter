# HY-S13 — CapacityAcquisition hygiene (dead code, duplication, dashboard tier)

Status: done
Owner: hygiene / capacity acquisition
Updated: 2026-08-07
Implemented by: DeepSeek V4 Pro (`alln run` 6578D6FF)

## Goal

Remove dead code and duplication in `CapacityAcquisition.swift`, and stop
labelling dashboard-scrape seats as `.tuiProbe` on synthesized `neverSampled`
rows.

## Read only

- `Packages/AllnighterCore/Sources/AllnighterCore/CapacityAcquisition.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/CapacityWindow.swift` (for
  `CapacityAcquisitionTier` cases only)
- `Packages/AllnighterCore/Tests/AllnighterCoreTests/CapacityAcquisitionTests.swift`

## Touch only

- `Packages/AllnighterCore/Sources/AllnighterCore/CapacityAcquisition.swift`

## Do not touch

- `CapacityHydration.swift` — it has the same `.tuiProbe` fallback at line ~91,
  but that is a separate slice. Leave it alone.
- `CapacityProbe.swift`, `CapacityStripRenderer.swift`, `CapacityFetch.swift`.
- `docs/phases/OpenCode_Go_Capacity.md` — it names `tier3ProbeableSources` as a
  historical record of a past change. That reference stays stale on purpose.
- Any test file. No test edits should be needed; if one is, stop and report.

## Copy-paste prompt

```text
Implement HY-S13 only.

Touch ONLY: Packages/AllnighterCore/Sources/AllnighterCore/CapacityAcquisition.swift

Seven changes, no others. Preserve behavior except where item 5 says otherwise.

1. Fix the stale file header doc comment (lines 3-17). It claims "PTY only, all
   six bench seats" and that refresh "run PTY adapters for all seats". Untrue
   now: the bench is 6 PTY seats + 2 dashboard-scrape seats (opencode_go,
   bailian_token_plan), and dashboard refresh happens outside this type. Rewrite
   the header to say that. Keep the "Fail closed" paragraph.

2. Delete the dead line `_ = dogfood` (line 83) in validateRefreshSourceId, and
   its trailing comment. `dogfood` is already used on line 80, so the discard is
   leftover from the OCG-S08 promotion.

3. Collapse the bare-call early return. When `sourcesToProbe.isEmpty` (lines
   123-143) the code hand-builds a full dictionary of `neverSampled` windows,
   but `orderedBenchWindows` already backfills every missing or empty source
   with exactly that window. Replace the whole block body with:
       return orderedBenchWindows([:], now: now)

4. Deduplicate the per-seat timeout resolution. The same branch appears twice —
   once in the `effectiveTimeouts` map (lines 162-167) and again as `seatTimeout`
   inside the dispatch loop (lines 174-176). Add one private static helper:
       private static func resolveProbeTimeout(
           for source: String,
           override: TimeInterval
       ) -> TimeInterval
   returning `override == CapacityProbe.defaultTimeout
   ? CapacityProbe.timeout(for: source) : override`. Call it from both places.

5. Stop labelling dashboard seats as `.tuiProbe`. Add one private static helper:
       private static func sourceTier(for source: String) -> CapacityAcquisitionTier
   returning `.dashboardScrape` when `dashboardSourceOrder.contains(source)`,
   otherwise `.tuiProbe`. Use it for EVERY `CapacityWindow.unknown(...)`
   `sourceTier:` argument constructed in this file (the neverSampled paths).
   Do NOT change `CapacityProbe.unknown(...)` call sites — those are PTY probe
   results and are correctly `.tuiProbe`.

6. Delete two unused public symbols: `tier3DisklessSources` (line 64) and
   `tier3ProbeableSources` (line 67). They have zero Swift call sites in the
   repo. KEEP `diskOnlySources` (used by CapacityHydration) and KEEP
   `ptyOnlySources` (used by tests).

7. Move the `final class ProbeResults` declaration (lines 149-159) out of the
   body of `windows(...)` to a private file-scope type at the bottom of the
   file. Same implementation, same locking. Rename nothing else.

Proof: scripts/swift-test.sh --filter Capacity

Expect green with NO test edits. If a test fails, report which one and stop —
do not adjust the test to match.

Then set `Status: done` in docs/phases/sprint/hygiene/HY-S13-capacity-acquisition-hygiene.md

Commit ONLY these explicit paths — the repo has unrelated dirty files, do not
stage them, do not use `git add -A`:
  Packages/AllnighterCore/Sources/AllnighterCore/CapacityAcquisition.swift
  docs/phases/sprint/hygiene/HY-S13-capacity-acquisition-hygiene.md
  docs/phases/sprint/README.md

Message: refactor(core): capacity acquisition hygiene (HY-S13)
```

## Steps

1. Header truth (item 1).
2. Dead-code deletions (items 2, 6).
3. Duplication collapse (items 3, 4, 7).
4. Dashboard tier correctness (item 5).
5. Run the Works Test.
6. Flip `Status: done`, commit the three explicit paths.

## Works Test

```text
scripts/swift-test.sh --filter Capacity
```

Result: 339 tests, 1 failure — `CapacityClassifierTests`
`testNoEstimateCarriesNoInventedNumbers`. **Pre-existing and unrelated**:
reproduced with `CapacityAcquisition.swift` reverted to HEAD, and
`CapacityClassifier` lives in the AgentOS dependency (`AgentOSCLI`), which
AllnighterCore's acquisition boundary cannot affect. It is the open
Vendor Signal Isolation defect — generic `rate limited — try again later`
prose classified as `accountRateLimit` instead of `unknownCapacity`.
No test was edited. Every capacity acquisition test passed.

## Done when

- [x] Header no longer claims a PTY-only six-seat bench.
- [x] `_ = dogfood`, `tier3DisklessSources`, `tier3ProbeableSources` gone.
- [x] Bare-call path is `orderedBenchWindows([:], now: now)`.
- [x] One timeout resolver, one tier resolver, both private.
- [x] `opencode_go` / `bailian_token_plan` neverSampled rows report
      `.dashboardScrape`.
- [x] `scripts/swift-test.sh --filter Capacity` green apart from the
      pre-existing unrelated classifier failure; no test edits.
- [x] One commit, three explicit paths.

## SSOT link

Bench roster and PTY/dashboard split: `docs/phases/OpenCode_Go_Capacity.md`
§ Promotion. Acquisition-tier meaning: `CapacityAcquisitionTier` in
`CapacityWindow.swift`.
