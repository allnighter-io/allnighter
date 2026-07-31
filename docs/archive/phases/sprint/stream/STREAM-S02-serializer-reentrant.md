# STREAM-S02 — ThreadStoreWriteSerializer reentrancy guard

Status: **done**
Source: [`code_review/triage/CR-10-findings.md`](../../code_review/triage/CR-10-findings.md) (P1)

## Goal

Detect and fail fast (or use queue-specific sync) when `ThreadStoreWriteSerializer`
is entered recursively on the same lane — `queue.sync` from within `queue.sync` deadlocks.

## Copy-paste prompt

```text
You are implementing sprint work order STREAM-S02 ONLY.

Read ONLY:
- docs/phases/sprint/stream/STREAM-S02-serializer-reentrant.md
- Packages/AllnighterCore/Sources/AllnighterEngine/ThreadStoreWriteSerializer.swift

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/ThreadStoreWriteSerializer.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/ThreadStoreWriteSerializerTests.swift (new)

Add per-lane reentrancy detection (e.g. thread-local depth or DispatchSpecificKey).
On nested synchronized() for same root: preconditionFailure in debug / thrown error in
tests; document that production must not reenter.

Proof: swift test --package-path Packages/AllnighterCore --filter ThreadStoreWriteSerializer
```

## Read only

- `ThreadStoreWriteSerializer.swift`

## Touch only

- `ThreadStoreWriteSerializer.swift`
- `ThreadStoreWriteSerializerTests.swift`

## Steps

1. Track enter/exit depth per lane queue.
2. Assert or trap on depth > 1 in test configuration.
3. Test nested call from same queue fails predictably.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter ThreadStoreWriteSerializer
```

## Done when

- [x] Reentrant synchronized() is detected
- [x] Non-reentrant paths unchanged
- [x] Test proves deadlock class is caught
