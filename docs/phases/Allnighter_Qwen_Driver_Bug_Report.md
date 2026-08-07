# Bug report for the Allnighter team — Qwen driver

**Standalone. Written to be handed to the Allnighter team as-is; not Ikiro
policy. Move or delete freely.**

Observed 2026-08-06 · Allnighter contract `9.9.0` · macOS · project root
`/Users/mike/Documents/GitHub/Ikiro.Studio`.

---

## Headline

`alln run --model model_qwen_38_max` reports `writePolicy: mutating`, but the
worker has **no file-write capability**. Work is silently stranded in the run
record instead of reaching disk.

Two runs, ~50 minutes wall time and a large chunk of a weekly token budget, zero
bytes written to the target file. **The work itself was excellent** — it found a
live path-traversal bug in our build and corrected a false security claim in our
spec. This is a plumbing failure around a worker that is earning its keep, not a
reason to distrust the model.

## Repro

```bash
alln run "Edit the file Docs/foo.md in place. Do not run git." \
  --model model_qwen_38_max --no-wait --json
alln show <id> --json
```

**Expected:** the file is edited, or the run fails loudly saying it cannot write.

**Actual:** the file is untouched. ~29KB of finished work sits in
`answers[0].markdown`. Qwen's own narration explains why:

> *"I don't have direct file-write access, so I'll delegate the writing task to
> an agent with the exact revised content and then verify the result myself."*

It then wrote a complete write-this-file instruction — with `BEGIN-OF-FILE` /
`END-OF-FILE` delimiters — into its answer text, addressed to a sub-agent that
never materialised.

## Why this is a contract bug, not a model quirk

`alln run --model model_qwen_38_max --dry-run` reports:

```json
{ "writePolicy": "mutating", "writeLockHeld": false }
```

That is a promise the driver cannot keep.

**The obvious alternative explanation was checked and ruled out.** All four
`qwen-code` processes had `cwd = /Users/mike/Documents/GitHub/Ikiro.Studio`, so
it is not a working-directory problem:

```
pid 31344  cwd: /Users/mike/Documents/GitHub/Ikiro.Studio
  /Users/mike/.local/lib/qwen-code/lib/cli-entry.js -p "Review, improve, …"
```

The driver launches `cli-entry.js -p "<prompt>"` — non-interactive print mode —
which appears to give the model no write tools at all.

## Asks, in priority order

1. **Make `writePolicy` honest for the qwen driver.** Either grant write tools,
   or report `readOnly` and refuse mutating packets up front. Silently accepting
   an "edit this file" instruction it cannot perform is the worst of the three
   options.
2. **Surface answer text as a retrievable artifact.** `alln show <id> --json`
   returned `artifact: null` while holding 29KB of finished work in
   `answers[0].markdown`. Anyone following the documented "surface
   `artifact.path` / `artifact.openCommand`" guidance finds nothing and
   concludes the run produced nothing. That is how the first run's output was
   written off as lost.
3. **A recovery path for killed runs.** The run was killed mid-flight and the
   complete revised document was still in the record — genuinely good. But
   nothing tells you to look there. An `alln show <id> --answer`, or an artifact
   path, would turn accidental recovery into a documented one.

## Smaller papercuts, same session

- **`alln ps --all` sorts by UUID, not recency**, with no start-time column.
  Finding your own run among ~40 rows means grepping a UUID you had to have kept.
- **`alln history`** → `usage: alln history "<query>"`. Not discoverable as
  "list my recent runs".
- **`alln show <id> --json` has no top-level `status`.** Liveness had to be
  inferred from `observation.ownerState`, completion from `answers[0].status`.
- **`--stream` output twice exceeded the calling tool's capacity**, losing the
  attach both times. A `--tail N` or quieter mode would help agent callers.

## Working well, for balance

- `--no-wait` returning a real id with a single `nextAction`.
- `--read-only` genuinely running in parallel without contending for the write
  lock — a Cursor Grok 4.5 review ran alongside the stuck Qwen run and completed
  cleanly.
- `--dry-run` catching flag errors before spend.
- `alln kill` terminating cleanly:
  `endReason=killed killOutcome=stopped signalled=true`.

## Impact

Two Qwen runs, ~50 minutes, substantial token spend. One was recovered only
because the run record was dumped before killing it; the other produced nothing
retrievable. A Cursor Grok 4.5 read-only run in the same session worked
perfectly, which is what isolates this to the qwen driver rather than to `alln`
generally.
