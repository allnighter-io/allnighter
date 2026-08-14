# Tech Stack

Status: MVP in progress — `AllnighterCore` and `AllnighterMac` exist; iOS is
parked foundation under `Apps/AllnighteriOS/`.

## Stack

| Layer | Choice |
| --- | --- |
| Language | Swift 6 language mode |
| UI | SwiftUI + Observation (`@Observable`; targeted AppKit on macOS) |
| Shared code | Swift Package `AllnighterCore` |
| Mac app | XcodeGen project at `Apps/AllnighterMac/` |
| iOS app | `Apps/AllnighteriOS/` (parked) |
| Mac networking | Tailscale serve + loopback HTTP/WebSocket |
| iOS networking | `URLSessionWebSocketTask` over Tailscale / local (when unparked) |
| Session/process | Foundation.Process; one mutating worker per registered repo root |
| Secrets | Vendor CLI Keychain logins only — Allnighter never BYOK |
| Remote transport | Tailscale private tailnet / local network |
| Mac distribution | Website DMG: Developer ID + notarize + staple (`docs/operations/Public_Release.md`). Sparkle is later transport; `latest.json` is what’s-latest. |
| iOS distribution | TestFlight → App Store (when unparked) |
| CI | GitHub Actions macOS runner via project wrappers (not raw runners) |

## Repo Targets

**Canonical remote:** `origin` → `https://github.com/allnighter-io/allnighter.git`

Local worktrees: `~/Documents/GitHub/Allnighter` (primary). Sibling checkout
required: `~/Documents/GitHub/AgentOS` (path dependency from
`Packages/AllnighterCore/Package.swift`). `scripts/rebuild_cli.sh` fails fast
if AgentOS is missing.

The ikiro.io marketing site is a separate repo: `website` remote →
`https://github.com/Ikiro-io/website.git` (do not push Allnighter branches there).

```txt
Packages/AllnighterCore/     # models, engine, CLI tools
Apps/AllnighterMac/          # macOS Dock app + team UI
Apps/AllnighteriOS/          # parked iOS companion
```

## Commands

Raw `swift test` / `xcodebuild test` are blocked by a PATH shim. Use the
wrappers — they are the only working path on agent hosts
(`docs/operations/Execution-Playbook.md` § Green Wall).

```text
# State-pattern gate
bash scripts/check_swiftui_state.sh

# Shared package — iteration proof (filter required for speed)
scripts/swift-test.sh --filter <TouchedTests>

# Rebuild and reinstall the agent-facing CLI (fails fast if AgentOS sibling missing)
bash scripts/rebuild_cli.sh

# Hygiene only (no compile suites)
bash scripts/check-fast.sh

# Green wall — closeout ONLY, never mid-slice
bash scripts/check.sh

# Emergency stale-runner cleanup
scripts/kill-stale-tests.sh
```

Mac / iOS app XCTest: use the project’s documented wrapper scripts under
`scripts/` (for example `scripts/ios_unit_tests.sh`); do not teach raw
`xcodebuild test` as the agent path.

## Agent Tooling

- Cursor + Codex share the same doc router (`AGENTS.md`).
- SwiftUI state rules live in `docs/operations/SwiftUI_State_Rules.md`; owned
  UI code uses Observation, not `ObservableObject`/`@Published` era patterns.
- Commits: all agents commit directly with git; the commit-queue/handoff watcher
  is retired (2026-06-18). See `docs/operations/Execution-Playbook.md` § Commits.

## Open Technical Decisions

Track durable decisions in phase docs and `docs/mvp/00_MVP_Architecture.md`.

| Topic | Options | Phase owner |
| --- | --- | --- |
| iOS product UI | parked foundation vs active companion | `docs/phases/ios/README.md` |
| Push notifications | none vs optional self-hosted relay | Phase 20+ |
| Event vocabulary freeze | `synthesis.*` → `stage.*` | `docs/phases/ios/01` |
