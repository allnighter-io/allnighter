# Allnighter — Product Spec

Internal product specification for the Allnighter macOS + iOS apps.

## What This Is

Allnighter is the all-day control plane for the AI coding tools the user already
pays for — named Teams (Spec Review, Bug Hunt, Growth, Research, and more) for
parallel judgment, and pilot / relay so a strong lead can route execution to
other seats (e.g. Opus steers, Grok or Composer mutates). Mac (CLI + app) is the
floor; iPhone is optional remote. Detach is supported, not the product
definition. Not another model provider or chat aggregator. The name Allnighter
is brand/domain only.

## Primary Docs

| Doc | Role |
| --- | --- |
| `AGENTS.md` | Agent/human/CI router (read first). Full laws: `docs/operations/Project_Laws.md` |
| `docs/WORKING_RULES.md` | MVP boundary, platform laws, credential posture |
| `docs/mvp/README.md` | Built MVP foundation and Council slice truth |
| `docs/phases/README.md` | Active post-MVP phase router |
| `docs/strategy/Allnighter-Agent-Control-Loop-Strategy.md` | Agent control loop strategy |
| `docs/phases/ios/README.md` | iOS companion — parked; foundation only |

## Platform Split

Standing law lives in `docs/operations/Project_Laws.md` (compact restatement
in `AGENTS.md` § Project Laws) and `docs/WORKING_RULES.md`.
This section summarizes; if anything here conflicts, those docs win — link them,
do not restate a second truth.

**macOS app (primary)** — `Apps/AllnighterMac/`:

- runs team/worker orchestration and lane management;
- exposes a local HTTP/WebSocket API for remote clients;
- product shell is a standalone Dock app; the menu bar is status / quick
  controls only (`docs/operations/Project_Laws.md`);
- uses the user's existing CLI subscriptions/logins only — never stores or
  requests API keys / BYOK (`docs/WORKING_RULES.md` Security Boundary). Vendor
  CLIs keep their own Keychain items; Allnighter does not read or copy them.

**iOS app (companion, parked)** — `Apps/AllnighteriOS/`:

- connects only to the user's own Mac over Tailscale / local network by default
  (`docs/operations/Project_Laws.md`); no mandatory third-party coordination cloud;
- mirrors active runs and floor-manager controls when built;
- no durable run truth on device; Mac is source of record.
- Product UI must not block Mac delivery (`docs/phases/ios/README.md`).

**Shared Swift package** — `Packages/AllnighterCore/` owns models, engine,
CLI tools, and protocol types reused by both apps. Package resolution also
requires a sibling `AgentOS` checkout (see `scripts/rebuild_cli.sh`).

## MVP Loop (v1)

```text
run team on Mac
-> parallel subscription CLIs produce member answers
-> lead produces plan / artifact
-> grow through post-MVP phase docs
```

## Communication

- Preferred: encrypted Tailscale private tailnet / local network to the owner's Mac.
- Auth: app-level device pairing on top of Tailscale membership.
- Contract truth owner: `docs/mvp/00_MVP_Architecture.md` § Event envelope.

## Distribution

- macOS: notarized DMG/PKG, Sparkle updates.
- iOS: TestFlight → App Store (when unparked).
- No mandatory cloud. Optional push relay seam only (deferred).

## Agent Workflow

All implementation work routes through `AGENTS.md`. Feature semantics require
a Feature Packet (`docs/workflows/SSOT_Feature_Workflow.md`) before code.
