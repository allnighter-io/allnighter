# Working Rules

## Positioning

Allnighter is a **local-first control plane** for terminal-based AI coding
tools — all-day multi-team work (Spec Review, Bug Hunt, Growth, Research, …)
and pilot/relay (strong lead → execution seats). The name is brand only;
overnight is a supported mode, not the default story. There is no separate
"Project Manager" surface — "where are we / what's next" is just chat, an agent
running with full repo access (archived `docs/archive/phases/Unified_Run_Model.md`;
code SSOT `RunService.swift`). Projects are
the floor: local repo/folder scope plus threads, runs, approvals, and proof.
Lead with parallel safe lanes, team-driven planning, and native Mac delight —
not with model/provider choice. iOS is a parked future remote surface, not
current scope (`docs/phases/ios/README.md`).

## Product Boundary

Allnighter owns orchestration, scheduling, remote control, and unified UX. It
does **not** own the agents themselves, model APIs, or agent reasoning.

In scope:

- spawn/manage CLI agent sessions and team runs;
- one mutating worker per project root under a write lock; answer-team
  workers run in parallel, observationally, in that same registered repo.
  Worktree/mirror/clone isolation is retired, not an alternate mode
  (archived `docs/archive/phases/Unified_Run_Model.md`, enforced by
  `config/architecture-policy.json`);
- Mac command center. Product shell is a Dock app; menu bar is status / quick
  controls only (`docs/operations/Project_Laws.md`). iOS remote is parked
  (`docs/phases/ios/README.md`);
- the user's existing CLI subscriptions/logins only — never API keys/BYOK;
- pairing, run persistence, review and kill-switch controls.

Out of product core (v1):

- hosting a coordination cloud;
- running inference servers;
- replacing agent CLIs with embedded models;
- Windows/Linux desktop (possible later);
- Android companion (v2+);
- collaborative multi-user sessions;
- plugin marketplace (v2+).

## MVP Boundary (v1)

Must ship for first testers (Team slice — see `docs/mvp/README.md`):

- Mac: enroll repo, run team (parallel subscription CLIs → plan).
- Text-only output; zero marginal cost path.
- Shared `AllnighterCore` engine and event envelope.
- Mac Dock app shell (menu bar = status / quick controls).

Deferred from v1 (documented in `docs/phases/`):

- worktree/mirror automation for parallel lanes — retired, not deferred
  (archived `docs/archive/phases/Unified_Run_Model.md`,
  `config/architecture-policy.json`);
- iOS remote surface (`docs/phases/ios/README.md`) — parked, foundation-only;
- push notifications and Live Activities;
- preference ledger and taste memory;
- local model workers.

## Platform Boundary

**macOS app**

- Unsandboxed by design for process control and git operations.
- Distributed via notarized DMG/PKG (Developer ID).
- Standalone Dock app is the product shell; menu-bar / status-item is status and
  quick controls only (`docs/operations/Project_Laws.md`).

**iOS app — parked, not current scope (`docs/phases/ios/README.md`)**

- Foundation prep may start; product UI is deferred and must not block macOS
  delivery.
- When built: connects only to the user's own Mac over Tailscale / local network
  by default (`docs/operations/Project_Laws.md`). No mandatory third-party coordination
  cloud.
- No durable run truth on device; Mac is source of record and final
  authorizer.

**Shared package**

- All cross-platform models and engine types live in `AllnighterCore`.
- Orchestration logic is shared; UI is platform-specific.

## Agent Bridge Boundary

Each supported CLI agent has a driver config describing:

- executable and args;
- spawn environment;
- output parsing hooks;
- team/worker expectations for team runs.

Drivers are configuration + adapters, not alternate run stores. Run state
lives in the orchestration layer.

## Security Boundary

- Allnighter never stores or requests API keys; it uses the user's existing
  CLI subscriptions/logins only, never BYOK (`docs/phases/README.md`
  Post-MVP Product Laws). Each vendor CLI keeps its own login in the macOS
  Keychain; Allnighter never reads or copies those credentials.
- iOS (parked) sends typed commands only; Mac executes and is the final
  authorizer. Pairing tokens are short-lived; device identity is explicit.
- Full Disk Access and other permissions require first-run wizard copy explaining why.

## Validation Boundary

Every accepted slice should eventually pass:

- `scripts/swift-test.sh --filter <TouchedTests>` for shared package iteration
  (raw `swift test` / `xcodebuild test` are blocked by the PATH shim);
- focused XCTest for app surfaces touched via the same wrappers;
- integration test or Works Test script for cross-app protocol behavior;
- closeout only: `bash scripts/check.sh`.

During bootstrap, explicitly name missing validation before accepting risk.

## Forecast Guardrail

SwiftUI and the CLI render work shape from `AllnighterCore` types. Core types
**do not** compute pre-run cost, time, token, or quota forecasts. If a line of
code implies we know the future before a run completes, delete it (Post-MVP
Product Law, `docs/phases/README.md`; see `CapacityClassifierTests` and
`TeamRunJSON`'s observed-only usage fields for the enforced shape).

## Communication Rule

Prefer dense updates:

- What changed.
- What remains.
- What was verified.
- What is blocked.
