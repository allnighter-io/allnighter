# RLC-S01 — Contract convergence

Status: **done**
SSOT: `docs/archive/phases/Rate_Limit_Continuity.md` §Slices RLC-S01
Updated: 2026-07-19

## Goal

Promote existing `CapacityObservation` into unified-run truth: `vendorBackoff`
blocker + `waitingForVendor` phase + durable `attempts[]` on `TeamRun`, with
park-eligibility helpers and classifier fixtures (incl. negatives). No park/wake
runtime yet (that is RLC-S02).

## Slice packet

```text
Slice: RLC-S01
Goal: Freeze RLC lifecycle/blocker/attempt wire shapes on existing capacity truth
Out of scope: coordinator wake, session resume, substitution, Mac notifications
Truth owner: TeamRun.blocker / TeamRun.attempts / CapacityObservation (AgentOS)
Lie-prone layer: inventing a parallel rateLimited type; Pending dual-truth drift
Works Test: focused Core tests below + contract regen --check
Proof command: see Done when
Missing proof / waiver: no end-to-end park/wake (S02)
Done when: checkboxes below
```

## Read only

- `docs/archive/phases/Rate_Limit_Continuity.md` (Law + Lifecycle + Park rules + S01 row)
- `docs/phases/Run_Lifecycle_Reliability.md` §RLR-L4 (typed blockers; vendorBackoff deferred → promote)
- Existing: `CapacityObservation` / `CapacityClassifier` in AgentOS sibling

## Touch only

Allnighter:

- `Packages/AllnighterCore/Sources/AllnighterCore/RunLifecycle.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/TeamRun.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/RunAttempt.swift` (new)
- `Packages/AllnighterCore/Sources/AllnighterCore/VendorBackoffPolicy.swift` (new)
- `Packages/AllnighterCore/Sources/AllnighterCore/TeamRunJSON.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/TeamRunJSONMapper.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/ContractSchema.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/SourceCapacityLedger.swift` (park gate comment + weekly retention note / lookback fix if cheap)
- `Packages/AllnighterCore/Sources/AllnighterCore/BenchReadiness.swift` (lookback must not drop live weekly cooldowns)
- `Packages/AllnighterCore/Sources/AllnighterEngine/UtilizationCapacityReader.swift` (same)
- Tests under `AllnighterCoreTests` / `AllnighterEngineTests` for the above
- `docs/generated/alln/*` via `alln dev export-contracts` only
- `docs/archive/phases/Rate_Limit_Continuity.md` status note for S01 delivered (brief)
- `docs/archive/phases/rlc/S01_Notes.md` (new — what retires from Pending path)

AgentOS sibling (`/Users/mike/Documents/GitHub/AgentOS`) — only if needed for fixtures:

- `Sources/AgentOSCLI/CapacityClassifier.swift` — parse Claude session-limit prose with timezone; negative fixture for model *discussing* rate limits
- Matching AgentOS tests if present; mirror coverage in Allnighter `CapacityClassifierTests`

## Do not touch

- ResidentCoordinator wake loop (S02)
- SeatReseat hop policy (S04)
- Mac GUI / notifications (S03)
- Unrelated dirty/RLR files
- Inventing `rateLimited(vendor, resumesAt)` types

## Steps

1. Add `RunPhase.waitingForVendor` (lifecycle `.queued`).
2. Add `RunBlocker.Resource.vendorBackoff` + quota-scope fields:
   - `quotaScope` (String? — source/account/profile key)
   - `wakeAfter` (Date?)
   - `capacityObservation` (CapacityObservation? — the only capacity truth)
   - keep existing write-lock fields optional/nil for vendor parks
3. Add `RunAttempt` + `TeamRun.attempts: [RunAttempt]` (append-only; default `[]` for legacy decode). Fields: attemptNumber, requestedSourceId/modelId, resolvedSourceId/modelId, startedAt/endedAt, capacityObservation?, vendorSessionId?, selectionOrigin?, substitutionOfAttempt?, terminalStatus/reason?, diagnosticSnippet? (redacted).
4. `VendorBackoffPolicy`:
   - `shouldPark(_ observation) -> Bool` — high confidence only (`accountRateLimit` + `.structured`, or `.messageFallback` **with** sourced `observedResetAt` / Retry-After). Never park on `unknownCapacity` / vibes/`busy`.
   - `computeWakeAfter(from:now:jitter:)` — `observedResetAt + ≥2min pad + 1–5min jitter`; unknown → nil (unknown-reset path).
   - Document clock rules: UTC instant; malformed/past/absurd → unknown path.
5. Project new blocker fields + attempts onto `TeamRunJSON` / `ContractSchema`; regen contracts.
6. Classifier fixtures: Claude `"You've hit your session limit · resets 4:20pm (Europe/Madrid)"` → parkable observation; negative: model prose discussing rate limits → no park / nil or non-parkable.
7. Fix 12h lookback so cooldowns with `coolingUntil > now` survive even when the originating run is older than 12h (weekly/monthly). Prefer retaining observations whose wake/reset is still in the future.
8. Write `docs/archive/phases/rlc/S01_Notes.md`: Pending path keeps `PendingResume.capacityObservation` for Pending items; unified-run parks do **not** mint Pending items; no second classifier; `SeatReseat` text cues stay for reseat eligibility until S04 precedence — do not invent parallel truth.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter 'VendorBackoff|RunAttempt|CapacityClassifier|SourceCapacityLedger|TeamRunJSON|ContractExport|BenchReadiness'
swift run --package-path Packages/AllnighterCore alln dev export-contracts --check
```

## Done when

- [ ] `vendorBackoff` + `waitingForVendor` compile; legacy `run.json` still decodes
- [ ] `attempts[]` on TeamRun decodes empty for legacy
- [ ] Park eligibility + wakeAfter helpers tested
- [ ] Session-limit fixture parks; discussion-negative does not
- [ ] Weekly cooldown survives lookback while `coolingUntil > now`
- [ ] Contracts regenerated / `--check` green
- [ ] S01_Notes names Pending vs unified-run ownership
- [ ] Committed as `feat(rlc): S01 — vendorBackoff contract + attempts + park policy`
