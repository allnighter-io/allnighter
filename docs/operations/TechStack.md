# Tech Stack

Status: bootstrap — docs and process only; Swift targets land in Phase 01+.

## Planned Stack

| Layer | Choice |
| --- | --- |
| Language | Swift 6 |
| UI | SwiftUI (+ targeted AppKit on macOS) |
| Shared code | Swift Package `CLILociCore` |
| Mac networking | SwiftNIO + NIOWebSocket |
| iOS networking | `URLSessionWebSocketTask` |
| Session/process | Foundation.Process + PTY (tmux-backed option for v1 reliability) |
| Secrets | Keychain (macOS) |
| Remote transport | Tailscale P2P (preferred), local network fallback |
| Mac distribution | Notarized DMG/PKG, Sparkle updates |
| iOS distribution | TestFlight → App Store |
| CI | GitHub Actions macOS runner + `xcodebuild test` |

## Repo Targets (planned)

```txt
Packages/CLILociCore/     # models, parsers, protocol Codable types
Apps/CLILociMac/          # macOS menu-bar app + WebSocket server
Apps/CLILociIOS/          # iOS companion
```

## Commands (when targets exist)

```text
# Shared package
swift test --package-path Packages/CLILociCore

# Green wall
bash scripts/check.sh

# Mac app
xcodebuild test -scheme CLILociMac -destination 'platform=macOS'

# iOS app (simulator)
xcodebuild test -scheme CLILociIOS -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Agent Tooling

- Cursor + Codex share the same doc router (`AGENTS.md`).
- Codex commit handoff: `scripts/commit_handoff_queue.py` + `.cursor/hooks/`.
- Install once per clone: `bash scripts/install_commit_queue_watcher.sh`.

## Open Technical Decisions

Track durable decisions in `Docs/product/SSOT.md` § Open Decisions.

| Topic | Options | Phase owner |
| --- | --- | --- |
| PTY strategy | tmux-backed vs native PTY management | Phase 02 |
| Workspace layout | SPM-only vs Xcode workspace with apps | Phase 01 |
| Push notifications | none vs optional self-hosted ntfy relay | Phase 2+ |
