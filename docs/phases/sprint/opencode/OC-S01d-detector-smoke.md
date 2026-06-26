# OC-S01d — CLIDetector smoke + coordinator before OpenCode spawn

Status: **ready** (requires OC-S01c done)
SSOT: `docs/phases/setup/OpenCode_CLI_Support.md` (Trusted Workflow Slice)

## Goal

Before OpenCode smoke or worker spawn, ensure serve is up; extract stdout before
`smokeTestExpect` match.

## Copy-paste prompt

```text
You are implementing sprint work order OC-S01d ONLY.

Read ONLY:
- docs/phases/sprint/opencode/OC-S01d-detector-smoke.md
- Packages/AllnighterCore/Sources/AllnighterEngine/CLIDetector.swift (smokeClassify function)
- Packages/AllnighterCore/Sources/AllnighterEngine/WorkerRunner.swift (invoke entry — where spawn starts)

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/CLIDetector.swift
- Packages/AllnighterCore/Sources/AllnighterEngine/WorkerRunner.swift
- Packages/AllnighterCore/Sources/AllnighterEngine/ModelHealthChecker.swift (if smoke lives there too)

Do NOT read full repo. Do NOT change manifests.

1. When manifest.id == "opencode": await OpenCodeServeCoordinator().ensureRunning() before runResolved smoke/invoke.
2. When matching smokeTestExpect on stdout for opencode: use TextUtil.extractOpenCodeVisibleText first.

Proof: swift test --package-path Packages/AllnighterCore
Optional live (founder): opencode serve running, alln doctor --agent opencode
```

## Read only

- `CLIDetector.swift` — `smokeClassify`
- `WorkerRunner.swift` — spawn chokepoint
- `ModelHealthChecker.swift` — if duplicate smoke path

## Touch only

- `CLIDetector.swift`
- `WorkerRunner.swift`
- `ModelHealthChecker.swift` (only if needed)

## Do not read / do not touch

- Manifests, ModelCatalog, tests (unless adding one focused test is trivial)

## Steps

1. Inject or construct `OpenCodeServeCoordinator` at opencode smoke/invoke sites.
2. `ensureRunning()` before subprocess.
3. Apply `extractOpenCodeVisibleText` before `contains(smokeTestExpect)`.
4. Run package tests.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore
```

Live (founder, optional):

```bash
# terminal 1: opencode serve --port 4096
alln doctor --agent opencode --json
```

## Done when

- [ ] OpenCode smoke uses extractor on stdout
- [ ] Coordinator ensured before opencode spawn
- [ ] Package tests green
