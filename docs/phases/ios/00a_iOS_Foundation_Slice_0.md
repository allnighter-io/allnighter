# 00a — iOS Foundation Slice 0 (preflight before remote code)

Status: Draft — first active foundation prep slice; no iOS UI.
Milestone: iOS foundation
Owner: Mac + Shared Core
Created: 2026-06-19
Updated: 2026-06-19
Depends on: `README.md`, `00_iOS_Transport_Decision.md`, `01_Connection_Spine.md`,
`01a_Pairing_Ceremony.md`, `../CLI_Product_Spine.md`,
`../CLI_Implementation_Contract.md`, `../Mac_Standalone_App_And_Background_Coordinator.md`

## Purpose

Before building the remote spine, get the foundation specs and repo reality back in
sync, then clear the cleanup/hardening gates that would otherwise make the first
wire contract brittle.

This slice is allowed to prepare shared Core/Engine contracts, tests, and fixtures.
It is not allowed to start the iOS app shell or create durable product truth beyond
the foundation contracts in `00`, `01`, and `01a`.

## Current Reality (2026-06-19)

| Area | State |
| --- | --- |
| CLI spine | `alln` M1 is built; async team, Pending, Project core pieces, and MCP pieces exist. |
| Coordinator | `alln serve` exists as a resident coordinator with health/wake behavior. It is not yet the cloud outbound agent and not yet the Direct Mode command/event HTTP/WS server. |
| Run durability | `RunStore` writes non-terminal `run.json` snapshots + `owner.pid` and reads dead owners as `interrupted`. It does not yet write append-only `events.jsonl` or a persisted global monotonic `seq`. |
| Event vocabulary | Generic `stage.*` events exist, but `RunEventKind` still carries legacy `synthesis.*` constants. The wire must not lock until those are removed or mapped out of public remote output. |
| iOS scaffold | `Apps/AllnighteriOS/` is still the SwiftData starter scaffold with `Item.swift`, `ModelContainer`, and a hand-managed `.xcodeproj`. It is quarantined; no foundation work should depend on it. |
| Project Manager | Project Core slices PRJ-S00-S06 are built; Project CLI/Manager/proposal/verification slices PRJ-S07-S13 are still moving. Remote foundation must not promise the phone Project Manager UI yet. |

## Slice Packet

Slice:
iOS Foundation Slice 0.

Goal:
Make the foundation docs current and define the exact cleanup/hardening gates that
must pass before `iOS01-S00` implementation starts.

Out of scope:
Supabase provisioning, R2 uploads, Apple/Google auth setup, iOS SwiftUI, app-shell
XcodeGen, mobile push, Project Manager phone surfaces, arbitrary remote shell/MCP,
and production Tailscale exposure.

Truth owner:
`AllnighterCore` owns remote models, crypto envelopes, command enums, replay
reducers, and fixtures. `AllnighterEngine` owns Mac journal/coordinator execution.
The iOS app target presents later and owns no transport truth.

Lie-prone layer:
The existing starter iOS target, stale Tailscale-first wording, legacy
`synthesis.*` event constants, coordinator health being mistaken for a remote
agent, and model output claiming a Mac is live without a signed Mac event.

Works Test:
An implementation agent can read `README.md -> 00a -> 00 -> 01 -> 01a` and know
what to clean before coding, what is forbidden, and what proof command must pass.

Proof command:

```bash
swift test --package-path Packages/AllnighterCore --disable-sandbox
rg -n -e "allnighter serve" -e "allnighter pair" -e "allnighter://pair" -e "Allnighter/Allnighter[.]xcodeproj" docs/phases/ios/README.md docs/phases/ios/00_iOS_Transport_Decision.md docs/phases/ios/01_Connection_Spine.md docs/phases/ios/01a_Pairing_Ceremony.md
```

The `rg` command should return no matches in the routed foundation docs. `synthesis.*` may
appear only as an explicit Slice 0 cleanup target until that cleanup lands.

Done when:
The foundation docs are current, the pre-code gates below are explicit, and no doc
invites UI or cloud work before the local proof harness is green.

## Pre-Code Gates

These gates happen before `iOS01-S00` code begins.

1. **Docs/current-state sync.** Foundation docs must name the real current state:
   `alln`, `alln serve` coordinator skeleton, partial journal durability, unfinished
   remote agent, and quarantined SwiftData scaffold.
2. **Vocabulary freeze plan.** The remote wire publishes `run.*`, `worker.*`, and
   `stage.*` only. Legacy `synthesis.*` constants are removed from remote output or
   mapped privately before any fixture becomes a wire fixture.
3. **Journal contract plan.** Define the append-only `events.jsonl`, global sequence
   index, replay window, snapshot builder, and orphan/interrupted behavior before
   remote stream code.
4. **Coordinator boundary.** Document that current `alln serve` health/wake is not
   enough for remote control. The remote agent extends the coordinator with typed
   command/event carriers; it does not create a second semantic engine.
5. **Closed command set.** Reserve and test the remote enum shape:
   `startRun`, `stopRun`, `stopAll`, plus deferred
   `approveRequest`, `rejectRequest`, `openOnMac`, and `landPlane`. There is no
   shell case and no generic MCP passthrough.
6. **Crypto proof harness plan.** The first code slice must include deterministic
   round-trip tests for two-key device/Mac identity, signing strings, HPKE
   `SealedBlob`, replay/skew rejection, protocol mismatch, and signed Mac events.
7. **Pairing CLI naming.** Foundation docs and generated contracts use `alln pair`,
   not `allnighter pair`. Pairing CLI can be reserved before implementation, but it
   must not imply UI readiness.
8. **iOS scaffold quarantine.** The SwiftData template remains unused until `02`.
   Foundation code lives in `AllnighterCore`/`AllnighterEngine`; no remote model or
   fixture is added to the app target.
9. **Project Manager boundary.** Foundation can expose typed team-run start/stop,
   snapshots, design-board refs, and kill switch semantics. Proposal, approval,
   return verification, and phone Project Manager UX wait for PRJ-S07-S13.

## First Implementable Slice After This

`iOS01-S00` starts only after the gates above are accepted:

```text
Core remote models
-> signing/sealing crypto helpers
-> signed command/event envelopes
-> round-trip fixtures and negative tests
-> no Supabase, no R2, no SwiftUI
```

That keeps the first real work boring, local, and falsifiable.
