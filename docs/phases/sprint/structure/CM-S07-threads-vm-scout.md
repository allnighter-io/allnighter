# CM-S07 — ThreadsViewModel Structure scout (split plan)

Status: done (`5bed561e`, Gemini via `alln run`)
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Produce a bounded split plan for `ThreadsViewModel.swift` (~1,627 LOC). **Docs only —
no Swift edits.**

## Copy-paste prompt

```text
Implement CM-S07 only. Read this file.

Touch ONLY:
- docs/operations/code-maintainer/plans/ThreadsViewModel-split.md (NEW)
- docs/operations/code-maintainer/MAINTENANCE-QUEUE.md (update ThreadsViewModel row: in-progress → scout done)

Read Apps/AllnighterMac/Sources/ThreadsViewModel.swift and its MARK sections. Write a
split plan mirroring docs/operations/code-maintainer/plans/RoutingComposer-split.md:

1. Current layout table (MARK → LOC estimate → job)
2. Proposed file batches (CM-S08+ ids) — each batch ≤500 LOC moved, one job per file
3. Natural seams: notifications, routing composer/send, fixtures, list/selection, attachments
4. Risks (shared @State, cross-file private access)
5. First extraction batch recommendation

Do NOT edit any Swift. Do NOT run xcodebuild.

Commit only the two docs above.
Message: docs(maintainer): ThreadsViewModel Structure scout plan (CM-S07)
```

## Works Test

```text
test -f docs/operations/code-maintainer/plans/ThreadsViewModel-split.md
```
