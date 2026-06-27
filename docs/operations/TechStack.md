# Tech Stack

Status: MVP in progress — `AllnighterCore` and `AllnighterMac` exist; iOS scaffold
is transitional.

## Stack

| Layer | Choice |
| --- | --- |
| Language | Swift 6 language mode |
| UI | SwiftUI + Observation (`@Observable`; targeted AppKit on macOS) |
| Shared code | Swift Package `AllnighterCore` |
| Mac app | XcodeGen project at `Apps/AllnighterMac/` |
| iOS app | `Allnighter/` (transitional) → `Apps/AllnighteriOS/` |
| Mac networking | Tailscale serve + loopback HTTP/WebSocket (see `docs/phases/ios/01`) |
| iOS networking | `URLSessionWebSocketTask` over Tailscale |
| Session/process | Foundation.Process + git worktrees (lanes) |
| Secrets | Keychain (macOS) |
| Remote transport | Tailscale private tailnet |
| Mac distribution | Notarized DMG/PKG, Sparkle updates |
| iOS distribution | TestFlight → App Store |
| CI | GitHub Actions macOS runner + `xcodebuild test` |

## Repo Targets

**Canonical remote:** `origin` → `https://github.com/MikeReining/allnighter.git`

Local worktrees: `~/Documents/GitHub/Allnighter` (primary) and
`~/Documents/GitHub/Allnighter-iOS` (`codex/ios-foundation`). The ikiro.io
marketing site is a separate repo: `website` remote →
`https://github.com/Ikiro-io/website.git` (do not push Allnighter branches there).

```txt
Packages/AllnighterCore/     # models, engine, CLI tools
Apps/AllnighterMac/          # macOS menu-bar app + team UI
Allnighter/                  # transitional iOS Xcode scaffold
```

## Commands

```text
# State-pattern gate
bash scripts/check_swiftui_state.sh

# Shared package
swift test --package-path Packages/AllnighterCore

# Green wall
bash scripts/check.sh

# Mac app
xcodebuild test -scheme AllnighterMac -destination 'platform=macOS'

# iOS app (simulator) — when AllnighteriOS target exists
xcodebuild test -scheme Allnighter -destination 'platform=iOS Simulator,name=iPhone 16'
```

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
| iOS project layout | root `Allnighter/` vs `Apps/AllnighteriOS/` via XcodeGen | `docs/phases/ios/02` |
| Push notifications | none vs optional self-hosted relay | Phase 20+ |
| Event vocabulary freeze | `synthesis.*` → `stage.*` | `docs/phases/ios/01` |
