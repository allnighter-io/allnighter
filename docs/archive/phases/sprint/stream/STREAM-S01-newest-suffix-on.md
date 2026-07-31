# STREAM-S01 — StreamingPartialBuffer newestSuffix O(n)

Status: **done**
Source: [`code_review/triage/CR-10-findings.md`](../../code_review/triage/CR-10-findings.md) (P1)

## Goal

Replace O(drops × n) `newestSuffix` work on the streaming hot path with O(n) or
incremental maintenance suitable for high-frequency partial updates.

## Copy-paste prompt

```text
You are implementing sprint work order STREAM-S01 ONLY.

Read ONLY:
- docs/phases/sprint/stream/STREAM-S01-newest-suffix-on.md
- Packages/AllnighterCore/Sources/AllnighterEngine/StreamingPartialBuffer.swift

Touch ONLY:
- Packages/AllnighterCore/Sources/AllnighterEngine/StreamingPartialBuffer.swift
- Packages/AllnighterCore/Tests/AllnighterEngineTests/StreamingPartialBufferTests.swift (new or extend)

Refactor newestSuffix to avoid rescanning full buffer on every drop. Preserve
observable suffix semantics used by WorkerRunner streaming.

Proof: swift test --package-path Packages/AllnighterCore --filter StreamingPartialBuffer
```

## Read only

- `StreamingPartialBuffer.swift`

## Touch only

- `StreamingPartialBuffer.swift`
- `StreamingPartialBufferTests.swift`

## Steps

1. Profile logic: identify nested loop over drops × buffer length.
2. Maintain running suffix index or deque incrementally.
3. Test large drop count + long buffer still completes quickly (unit timing or iteration count).

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter StreamingPartialBuffer
```

## Done when

- [x] newestSuffix is linear in buffer size per call
- [x] Streaming semantics unchanged per tests
- [x] No ThreadStore changes in this slice
