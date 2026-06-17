# Working Rules

## Positioning

Allnighter is a **local-first agent factory and Project Manager** for
terminal-based AI coding tools. Projects are the floor: local repo/folder scope
plus threads, runs, approvals, and proof. Lead with parallel safe lanes,
team-driven planning, and native Mac + iOS delight — not with model/provider
choice.

## Product Boundary

Allnighter owns orchestration, scheduling, remote control, and unified UX. It
does **not** own the agents themselves, model APIs, or agent reasoning.

In scope:

- spawn/manage CLI agent sessions and team runs;
- lane/worktree isolation for parallel work;
- Mac command center + iOS remote over Tailscale;
- BYOK key storage on Mac;
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
- Mac menu-bar / dashboard shell.

Deferred from v1 (documented in `docs/phases/`):

- full lane factory and worktree automation;
- iOS remote Project Manager (`docs/phases/ios/`);
- push notifications and Live Activities;
- preference ledger and taste memory;
- local model workers.

## Platform Boundary

**macOS app**

- Unsandboxed by design for process control and git/worktree operations.
- Distributed via notarized DMG/PKG (Developer ID).
- Menu-bar / status-item first; dashboard window optional.
- Local HTTP/WebSocket server is the API truth surface for iOS.

**iOS app**

- Sandbox App Store app.
- Connects only to user's Mac app over Tailscale.
- No durable run truth on device; Mac is source of record.

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

- API keys never leave the Mac Keychain for iOS use; iOS sends commands, Mac executes.
- Pairing tokens are short-lived; device identity is explicit.
- Tailscale private tailnet is the preferred transport; document fallback behavior.
- Full Disk Access and other permissions require first-run wizard copy explaining why.

## Validation Boundary

Every accepted slice should eventually pass:

- `swift test` for shared package logic;
- focused XCTest for app surfaces touched;
- integration test or Works Test script for cross-app protocol behavior.

During bootstrap, explicitly name missing validation before accepting risk.

## Forecast Guardrail

SwiftUI, CLI, and MCP render work shape from `AllnighterCore` types. Core types
**do not** compute pre-run cost, time, token, or quota forecasts. If a line of
code implies we know the future before a run completes, delete it. See
`docs/archive/phases/Estimate_Cleanup_And_Effort_Dial.md`.

## Communication Rule

Prefer dense updates:

- What changed.
- What remains.
- What was verified.
- What is blocked.
