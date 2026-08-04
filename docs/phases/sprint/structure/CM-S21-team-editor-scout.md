# CM-S21 — TeamEditorView Structure scout (split plan)

Status: done (`d97ba5c0`, Gemini via `alln run`)
Owner: code-maintainer Structure lens
Updated: 2026-08-03

## Goal

Produce a bounded split plan for `TeamEditorView.swift` (~1,036 LOC). **Docs only —
no Swift edits.**

## Copy-paste prompt

```text
Implement CM-S21 only. Read this file.

Touch ONLY:
- docs/operations/code-maintainer/plans/TeamEditorView-split.md (NEW)
- docs/operations/code-maintainer/MAINTENANCE-QUEUE.md (add open row for TeamEditorView scout done)

Read Apps/AllnighterMac/Sources/TeamEditorView.swift. Write a split plan mirroring
docs/operations/code-maintainer/plans/ThreadsViewModel-split.md:

1. Current layout table (section → LOC estimate → job)
2. Proposed file batches (CM-S22+ ids) — each ≤500 LOC, one job per file
3. Natural seams
4. Risks
5. First extraction batch recommendation

Do NOT edit any Swift. Do NOT run xcodebuild.

Commit only the two docs above.
Message: docs(maintainer): TeamEditorView Structure scout plan (CM-S21)
```

## Works Test

```text
test -f docs/operations/code-maintainer/plans/TeamEditorView-split.md
```
