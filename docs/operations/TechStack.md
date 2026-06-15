# Tech Stack

Status: MVP in progress — `AllnighterCore` and `AllnighterMac` exist; iOS scaffold
is transitional.

## Stack

| Layer | Choice |
| --- | --- |
| Language | Swift 6 |
| UI | SwiftUI (+ targeted AppKit on macOS) |
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

```txt
Packages/AllnighterCore/     # models, engine, CLI tools
Apps/AllnighterMac/          # macOS menu-bar app + team UI
Allnighter/                  # transitional iOS Xcode scaffold
```

## Commands

```text
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
- Codex commit handoff: `scripts/commit_handoff_queue.py` + `.cursor/hooks/`.
- Install once per clone: `bash scripts/install_commit_queue_watcher.sh`.

## Open Technical Decisions

Track durable decisions in phase docs and `docs/mvp/00_MVP_Architecture.md`.

| Topic | Options | Phase owner |
| --- | --- | --- |
| iOS project layout | root `Allnighter/` vs `Apps/AllnighteriOS/` via XcodeGen | `docs/phases/ios/02` |
| Push notifications | none vs optional self-hosted relay | Phase 20+ |
| Event vocabulary freeze | `synthesis.*` → `stage.*` | `docs/phases/ios/01` |
