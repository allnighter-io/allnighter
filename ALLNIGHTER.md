# Allnighter — Product Spec

Internal product specification for the Allnighter macOS + iOS apps.

## What This Is

Allnighter turns the user's Mac into an overnight **agent factory** and their
iPhone into the **floor manager** for that factory. It coordinates the AI coding
tools the user already pays for — not another model provider or chat aggregator.

## Primary Docs

| Doc | Role |
| --- | --- |
| `docs/mvp/README.md` | Built MVP foundation and Council slice truth |
| `docs/phases/README.md` | Active post-MVP phase router |
| `docs/strategy/Allnighter-Agent-Control-Loop-Strategy.md` | Agent control loop strategy |
| `docs/WORKING_RULES.md` | MVP boundary, platform laws, agent isolation |
| `docs/phases/ios/README.md` | iOS remote floor manager spine |

## Platform Split

**macOS app (primary)** — `Apps/AllnighterMac/`:

- runs council/worker orchestration and lane management;
- exposes a local HTTP/WebSocket API for remote clients;
- menu-bar / status-item with dashboard window;
- stores API keys in Keychain (BYOK).

**iOS app (companion)** — `Allnighter/` (transitional scaffold) →
`Apps/AllnighteriOS/`:

- connects to the Mac over Tailscale;
- mirrors active runs, review queue, and floor-manager controls;
- no durable run truth on device; Mac is source of record.

**Shared Swift package** — `Packages/AllnighterCore/` owns models, engine,
CLI tools, and protocol types reused by both apps.

## MVP Loop (v1)

```text
run council on Mac
-> parallel subscription CLIs produce member answers
-> judge produces plan
-> grow through post-MVP phase docs
```

## Communication

- Preferred: encrypted Tailscale private tailnet.
- Auth: app-level device pairing on top of Tailscale membership.
- Contract truth owner: `docs/mvp/00_MVP_Architecture.md` § Event envelope.

## Distribution

- macOS: notarized DMG/PKG, Sparkle updates.
- iOS: TestFlight → App Store.
- No mandatory cloud. Optional push relay seam only (deferred).

## Agent Workflow

All implementation work routes through `AGENTS.md`. Feature semantics require
a Feature Packet (`docs/workflows/SSOT_Feature_Workflow.md`) before code.
