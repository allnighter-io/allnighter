# HY-S12 — Fixture seeder loop thread titles

Status: ready
Owner: hygiene / product vocabulary
Updated: 2026-08-03

## Goal

GUI fixture thread titles in `ThreadsFixtureSeeder.swift`: `"PM Relay: …"` →
`"Loop: …"`. Comments in same file: `PM Relay` → `Loop`.

## Copy-paste prompt

```text
Implement HY-S12 only. Read this file.

Touch ONLY:
- Apps/AllnighterMac/Sources/ThreadsFixtureSeeder.swift

Replace fixture title strings "PM Relay:" → "Loop:".
In comments: "PM Relay" → "Loop" (keep PM_Relay.md path refs).

Proof:
xcodebuild test -scheme AllnighterMac -destination 'platform=macOS' 2>&1 | tail -8

Commit only listed file.
Message: docs(mac): fixture seeder loop titles PM Relay → Loop
```

## Works Test

```text
xcodebuild test -scheme AllnighterMac -destination 'platform=macOS'
```
