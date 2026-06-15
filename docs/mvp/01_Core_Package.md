> **Vocabulary (2026-06-15).** Current product language lives in
> `docs/phases/Work_Order_Team_Model.md`. This doc uses team/model/worker/plan
> terms only.

# 01 — AllnighterCore (MVP subset)

Status: **Complete** — foundation built and proven (`swift test`: 24 passing)
Depends on: 00 (architecture)
Owner: Shared Core
Created: 2026-06-14
Completed: 2026-06-14

## Goal

Stand up the `AllnighterCore` Swift package with the pure, I/O-free types the
whole MVP depends on: the worker/run models, the driver-manifest schema, the run
+ member state machines, the `RunEvent` envelope, and JSON fixtures — all proven
by `swift test`. This is the single source of semantic truth; the engine
(Phase 02) and the app (Phase 03+) consume it.

## Non-Goals

- No subprocess execution, no UI, no persistence I/O (those are Phase 02/03).
- No critique round, no lanes, no scorecards (Growth Seams, `00` §10).

## Approach (per `00`)

- Pure SPM package, no dependencies beyond the standard library (+ `swift-log`
  only if needed). `swift test` runs without Xcode.
- Define `Codable` models exactly as `00` §4: `Worker`, `DriverManifest`,
  `TeamRun`, `WorkerPrompt`, `WorkerAnswer`, `Synthesis`, `RunEvent`, and
  the enums `ModelRole`, `RunStatus`, `WorkerAnswerStatus`, `DriverKind`.
- Implement `TeamRun.canTransition(to:)` and `WorkerAnswer` status
  transitions as the validated state machines (`00` §4).
- Ship fixtures (`00` §8) and round-trip tests so the app can render before any
  CLI is wired.

## Ordered Slices

- [x] P01-S01 — Models: `Worker`, `DriverManifest`, `TeamRun`, `WorkerPrompt`,
  `WorkerAnswer`, `Synthesis` + enums; `Codable` with stable coding keys.
- [x] P01-S02 — Manifest schema decode (template tokens, `invoke`, `output`,
  `manual_paste` kind with no `invoke`).
- [x] P01-S03 — Run state machine (`RunStatus`) + member state machine
  (`WorkerAnswerStatus`) with `canTransition(to:)`.
- [x] P01-S04 — `RunEvent` envelope (id, seq, ts, kind, payload) matching
  `00` §6; encode/decode (`JSONValue` payload).
- [x] P01-S05 — Fixtures (`models_six`, `run_inflight`, `run_complete`,
  `run_partial`, `manifest_claude`, `manifest_grok`, `manifest_manual`) + loader.
- [x] P01-S06 — Round-trip + state-machine + template tests (legal + illegal edges).

## Works Test

```text
Run `swift test --package-path Packages/AllnighterCore`. All model fixtures
decode and re-encode equivalently; every legal run/member transition is allowed
and every illegal one is rejected; the manual_paste manifest decodes with a nil
`invoke`. Green.
```

**Result (2026-06-14):** `swift test` → 24 tests, 0 failures. Round-trips cover
the team, all three manifests, and all three run fixtures; state-machine tests
cover every legal/illegal/terminal edge for both `RunStatus` and `WorkerAnswerStatus`;
template tests prove the prompt is passed as a single argv element (injection
safe).

## Exit Gates

- [x] Works Test passes; `swift test` green (24 passing).
- [x] No I/O in Core (pure types; only `Bundle.module` reads bundled fixtures).
- [x] Model names/fields match `00` §4–§6 (forward-compatible with `ON HOLD/00`).
- [x] Fixtures cover the Founder's Six-worker team (incl. Composer 2.5 + Grok
  Build sharing the `grok` driver).

## Closeout

**Complete.** `AllnighterCore` lives at `Packages/AllnighterCore`. Green wall
(`scripts/check.sh`) runs the package. Activate **Phase 02 (Model Drivers +
Fan-Out Engine)**, which executes real CLIs against these types.

### Durable notes for Phase 02

- Fixtures are bundled via `.copy("Resources/Fixtures")` and read with
  `Bundle.module` subdirectory `"Fixtures"` (`.process` flattened the tree).
- `grok` driver manifest (`manifest_grok.json`) is a **best-effort guess**
  (`grok -p "..." --model {{model}}`); the real headless flags must be verified
  on-device in Phase 02. Until verified, Grok Build / Composer 2.5 fall back to
  `manual_paste`.
- `DriverManifest.resolvedArgs/stdinPrompt/resolvedCommandString` already give
  the engine injection-safe substitution — reuse, do not reinvent.
