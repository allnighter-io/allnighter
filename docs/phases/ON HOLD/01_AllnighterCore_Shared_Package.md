# 01 — AllnighterCore Shared Package

Status: Draft — **next strategic target after `00`**
Milestone: A (Substrate)
Depends on: `00` (constitution)
Owner: Shared Core
Created: 2026-06-13

## Goal

Create `Packages/AllnighterCore/` — the pure-Swift contract both apps and the
relay share. It contains the Codable domain models, the lane state machine, the
API request/response types, the event envelope, and the JSON fixtures, all
proven by `swift test`. **No I/O, no networking, no git** — types and logic only.

This package is the parallel-team contract: once it exists with fixtures, the
Mac and iOS tracks can proceed independently (`00` §8).

## Non-Goals

- The Hummingbird server (Phase 08) and any networking.
- Git/worktree logic (Phase 03), drivers (Phase 04), persistence (GRDB lives in
  the Mac app, not Core).
- Full output parsers — stubs only.

## Approach (per `00`)

- Pure SPM library, `swift test` runs without Xcode.
- Model every entity in `00` §7 as `Codable`, `Sendable`, `Hashable`.
- The lane state machine is the crown jewel: encode legal transitions as data and
  expose `Lane.canTransition(to:) -> Bool` + `LaneStatus.legalNextStates`.
- The event envelope (`00` §5) with `seq`, `id`, `kind`, `payload` (type-erased
  but decodable per kind).
- API types (`00` §6) as request/response structs grouped by route.

## Ordered Slices

- [ ] P01-S01 — Create SPM package + folder layout + `scripts/check.sh` wiring `swift test`.
- [ ] P01-S02 — Implement entities: `Project`, `Task`, `Lane`, `Worker`, `Driver`, `Race`, `Council`, `Artifact`, `Landing`, `PreferenceEvent`, `WorkerScorecard`.
- [ ] P01-S03 — Implement enums: `LaneStatus`, `RiskTier`, `CapabilityLevel`, `DispatchMode`, `OutputType`, `EventKind`.
- [ ] P01-S04 — Implement the `Event` envelope + per-kind payload decoding.
- [ ] P01-S05 — Implement lane state machine: legal transition table + `canTransition(to:)` + exhaustive unit tests (every legal edge passes, illegal edges throw/return false).
- [ ] P01-S06 — Implement API request/response types for all routes in `00` §6.
- [ ] P01-S07 — Author fixtures A–G (`00` §8) and round-trip decode/encode tests.
- [ ] P01-S08 — Add `MockDriver` output schema + `MockiOSClient` message helpers (test support module).

## Works Test

```text
swift test is green and includes:
- every Lane state transition (legal + illegal) asserted;
- fixtures A–G decode and re-encode byte-stably;
- one Event of each kind decodes its payload.
```

## Exit Gates

- [ ] Works Test passes (`swift test`).
- [ ] All `00` §7 entities + §6 API types exist and match the doc.
- [ ] Fixtures A–G committed under `Fixtures/`.
- [ ] Code Audit CLEAN.

## Closeout

Archive to `docs/archive/phases/`; activate Phase 02. Promote any model changes
back into `00` §7.
