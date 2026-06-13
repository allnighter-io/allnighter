# CLI Loci — Product Spec

Internal product specification for the CLI Loci macOS + iOS apps.

## What This Is

CLI Loci is the **universal remote and mission-control layer** above terminal-based
AI coding agents. It is not another agent. It orchestrates agents the developer
already runs locally.

## Primary Docs

| Doc | Role |
| --- | --- |
| `Docs/strategy/CLI-Loci-Vision.md` | Vision, personas, architecture, MVP, open questions |
| `Docs/product/SSOT.md` | Durable product vocabulary and truth ownership |
| `Docs/WORKING_RULES.md` | MVP boundary, platform laws, agent isolation |
| `Docs/phases/README.md` | Live execution phases and priority stack |

## Platform Split

**macOS app (primary)** — unsandboxed SwiftUI app that:

- spawns and manages PTY/background CLI agent sessions;
- parses output into structured events and diff cards;
- exposes a local WebSocket API (SwiftNIO);
- runs as menu-bar / status-item with optional dashboard window;
- stores API keys in Keychain (BYOK).

**iOS app (companion)** — SwiftUI remote that:

- connects to the Mac app over Tailscale or local network;
- mirrors dashboard and rich session views;
- supports approvals, haptics, Live Activities, Shortcuts.

**Shared Swift package** — `Packages/CLILociCore/` owns models, parsers, and
protocol definitions reused by both apps.

## MVP Loop (v1)

```text
pair Mac + iPhone (Tailscale)
-> paste BYOK keys on Mac
-> launch agent session (Claude / Grok / Aider)
-> stream output + basic approvals on Mac or iOS
-> session persists in background
```

## Communication

- Preferred: encrypted Tailscale P2P.
- Fallback: local network.
- Auth: short-lived pairing tokens + device identity.
- Protocol truth owner: `Docs/product/WebSocket_Protocol_Contract.md`.

## Distribution

- macOS: notarized DMG/PKG, Sparkle updates.
- iOS: TestFlight → App Store.
- No mandatory cloud. Optional self-hosted push relay only.

## Agent Workflow

All implementation work routes through `AGENTS.md`. Feature semantics require
a Feature Packet (`Docs/workflows/SSOT_Feature_Workflow.md`) before code.
