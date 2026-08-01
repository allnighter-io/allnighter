# OC-S01b — WorkerRunner OpenCode extractor wire

Status: **superseded — shipped via AgentOS HTTP driver** (archive 2026-08-01)
SSOT: `docs/phases/setup/OpenCode_CLI_Support.md` (Output Contract — one paragraph)

## Goal

Call `TextUtil.extractOpenCodeVisibleText` in `WorkerRunner` when
`manifest.id == "opencode"`, same pattern as Grok.

## Copy-paste prompt

```text
You are implementing sprint work order OC-S01b ONLY.

Read ONLY:
- docs/phases/sprint/opencode/OC-S01b-worker-runner.md
- Packages/AllnighterCore/Sources/AllnighterEngine/WorkerRunner.swift (lines ~365-375 — Grok branch)

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/WorkerRunner.swift

Do NOT read other files. Do NOT add OpenCodeServeCoordinator yet.

Change: after `stripped = output(from:rawOutput, manifest:)`, apply extractors:
- grok → extractGrokStreamingVisibleText (existing)
- opencode → extractOpenCodeVisibleText (new branch)

Use a small private helper or chained if/else — match existing style, minimal diff.

Proof: swift test --package-path Packages/AllnighterCore --filter OpenCodeVisibleText
(if OC-S01a exists) OR build: swift build --package-path Packages/AllnighterCore

Stop. One file only.
```

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/WorkerRunner.swift` (Grok branch ~368)

## Touch only

- `Packages/AllnighterCore/Sources/AllnighterEngine/WorkerRunner.swift`

## Do not read / do not touch

- Coordinator, CLIDetector, manifests, tests (unless fixing compile error in same file)

## Steps

1. Find `manifest.id == "grok"` extractor branch in `finalize` / post-output path.
2. Add `manifest.id == "opencode"` → `TextUtil.extractOpenCodeVisibleText(stripped)`.
3. Keep Grok behavior unchanged.
4. Build or run OC-S01a tests.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter OpenCodeVisibleText
swift build --package-path Packages/AllnighterCore
```

## Done when

- [ ] OpenCode runs through extractor in `WorkerRunner`
- [ ] Grok path unchanged
- [ ] Only `WorkerRunner.swift` modified
