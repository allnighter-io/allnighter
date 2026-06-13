# Working Rules

## Positioning

CLI Loci is a **local-first, multi-agent mission control** for terminal-based AI
coding tools. Lead with universality, parallel walk-away execution, and native
Mac + iOS delight — not with model/provider choice.

## Product Boundary

CLI Loci owns orchestration, remote control, and unified UX. It does **not**
own the agents themselves, model APIs, or agent reasoning.

In scope:

- spawn/manage CLI agent PTY sessions;
- parse output into structured events and diffs;
- Mac dashboard + iOS remote over private network;
- BYOK key storage on Mac;
- pairing, session persistence, approvals.

Out of product core (v1):

- hosting a coordination cloud;
- running inference servers;
- replacing agent CLIs with embedded models;
- Windows/Linux desktop (possible later);
- Android companion (v2+);
- collaborative multi-user sessions;
- plugin marketplace (v2+).

## MVP Boundary (v1)

Must ship for first testers (4–8 weeks focused work):

- Tailscale-first onboarding + device pairing.
- Three agents: Claude Code, Grok Build, Aider (extensible bridge layer).
- Mac: dashboard (machines + sessions), launch/attach session, streaming output,
  basic approvals.
- iOS: connect, dashboard, one rich session view with streaming + basic approvals.
- Simple parsed diff cards (approve/reject).
- Context-aware haptics on key events.
- BYOK flow (Keychain on Mac).
- Background session persistence (tmux or native PTY management).

Phase 2 (wow release) — not v1:

- true parallel headless spawning from phone/Mac;
- swipeable diff cards + rich haptics;
- Live Activities + Dynamic Island;
- multi-machine support;
- voice + Shortcuts deep integration;
- cost tracking;
- session history + searchable diffs.

## Platform Boundary

**macOS app**

- Unsandboxed by design for PTY/process control.
- Distributed via notarized DMG/PKG (Developer ID).
- Menu-bar / status-item first; dashboard window optional.
- Local WebSocket server (SwiftNIO) is the API truth surface for iOS.

**iOS app**

- Sandbox App Store app.
- Connects only to user's Mac app (Tailscale preferred).
- No durable session truth on device; Mac is source of record.

**Shared package**

- All cross-platform models and protocol types live in `CLILociCore`.
- Parsers and diff logic are shared; UI is platform-specific.

## Agent Bridge Boundary

Each supported CLI agent has a bridge config describing:

- executable and args;
- spawn environment;
- output parsing hooks;
- approval/diff extraction expectations.

Bridges are configuration + adapters, not alternate session stores. Session state
lives in the orchestration layer.

## Security Boundary

- API keys never leave the Mac Keychain for iOS use; iOS sends commands, Mac executes.
- Pairing tokens are short-lived; device identity is explicit.
- Tailscale P2P is the preferred transport; document fallback behavior.
- Full Disk Access and other permissions require first-run wizard copy explaining why.

## Validation Boundary

Every accepted slice should eventually pass:

- `swift test` for shared package logic;
- focused XCTest for app surfaces touched;
- integration test or Works Test script for cross-app protocol behavior.

During bootstrap, explicitly name missing validation before accepting risk.

## Communication Rule

Prefer dense updates:

- What changed.
- What remains.
- What was verified.
- What is blocked.
