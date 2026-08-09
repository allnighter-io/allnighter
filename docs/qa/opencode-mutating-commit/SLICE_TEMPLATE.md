# OpenCode mutating slice prompt template (OMH-S02)

Paste into `alln run` prompts for DeepSeek V4 Pro / other OpenCode mutators.

```text
MUTATING — you MUST edit AND git commit run-owned paths.
Leaving dirty run-owned files fails the run (`incomplete_uncommitted`).
Help: alln help opencode_mutating_commit_contract

Slice: <ID> — <one behavioral theme only>
Files (≤3 prod + ≤1 test):
- …
- …

Works Tests for this slice (must pass in the SAME commit):
1. <name>: scripts/swift-test.sh --filter <Test>
2. …

Do not mark the slice done if a Works Test is deferred. If you must stop,
state exactly what is deferred and why; the host will complete it before the
next slice runs.

Wall budget: ≤15 minutes. Prefer finishing a smaller slice over under-shipping.

Commit only the listed paths with an explicit git add + HEREDOC message.
Do not push. Do not amend. Ignore unrelated untracked dirs.
```

CRS-S04 reminder: Pro deferred mid-probe cancel after a 27m run; host had to
ship `8a0e7306`. Do not repeat that pattern.
