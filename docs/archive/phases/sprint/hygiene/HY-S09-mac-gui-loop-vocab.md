# HY-S09 — Mac GUI Loop vocabulary (PM Relay → Loop)

Status: ready
Owner: hygiene / product vocabulary
Updated: 2026-08-03

## Goal

Mac app user-facing copy and file comments: `PM Relay` → `Loop` where teaching
product vocabulary. **No symbol renames, no fixture titles (HY-S12).**

## Copy-paste prompt

```text
Implement HY-S09 only. Read this file.

Touch ONLY:
- Apps/AllnighterMac/Sources/ThreadView.swift
- Apps/AllnighterMac/Sources/RelayLaunchView.swift
- Apps/AllnighterMac/Sources/RelayGUIRuntime.swift
- Apps/AllnighterMac/Sources/RootView.swift

In user-visible strings and // / /// comments:
- "PM Relay" → "Loop" (product noun)
- Keep archive doc path refs (PM_Relay.md) where citing historical packets.

Do NOT touch ThreadsFixtureSeeder.swift (HY-S12).

Proof:
scripts/swift-test.sh --filter RetiredVocabulary
xcodebuild test -scheme AllnighterMac -destination 'platform=macOS' -only-testing:AllnighterMacTests 2>&1 | tail -5

Commit only listed files.
Message: docs(mac): loop GUI vocabulary PM Relay → Loop
```

## Works Test

```text
scripts/swift-test.sh --filter RetiredVocabulary
```
