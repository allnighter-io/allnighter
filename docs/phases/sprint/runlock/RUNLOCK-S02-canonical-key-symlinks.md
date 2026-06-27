# RUNLOCK-S02 — Symlink-resolving canonical key

Status: **ready**
SSOT: CR-01 triage [`../../code_review/triage/CR-01-findings.md`](../../code_review/triage/CR-01-findings.md) (P1 — symlink/case keys)
Promoted from: Phase 1 code review CR-01 (2026-06-27)

## Goal

`RunWriteLock.key(repoRoot:)` must resolve symlinks (and document case behavior) so one physical repo cannot acquire two independent locks.

## Copy-paste prompt

```text
Harden RunWriteLock.normalize/key to resolve symlinks after standardizingPath.

READ: RunWriteLock.swift, CR-01-findings P1 symlink section.

CHANGE: After standardizingPath, use URL.resolvingSymlinksInPath().path before FNV hash.
Add tests: same repo via symlink alias → same key; /var vs /private/var collapse.

TOUCH ONLY: RunWriteLock.swift + tests.

PROOF: swift test --filter RunWriteLock
```

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/RunWriteLock.swift`
- `docs/phases/code_review/triage/CR-01-findings.md`

## Touch only

- `Packages/AllnighterCore/Sources/AllnighterEngine/RunWriteLock.swift`
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/RunWriteLockTests.swift`

## Steps

1. Extend `normalize` to resolve symlinks (document case-insensitive FS caveat).
2. Add unit tests with temp symlinks or documented fixture paths.
3. Ensure blank/unknown-root behavior unchanged.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter RunWriteLock
```

## Done when

- [ ] Symlink alias and target produce identical lock key
- [ ] `/var` and `/private/var` paths collapse when applicable
- [ ] No regression on empty/blank root conservative lane
