# Keep working while I'm away

Unattended PM↔dev loop (`alln loop start`). A PM seat reviews and a dev seat builds, round after round, until done / escalate / a ceiling.

## Example utterances

1. "Keep going without me for a while."
2. "Set up a loop and have it execute this doc."
3. "Keep working while I'm away — escalate only if stuck."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v8 hash=ef3cbd5b276afd8fcc4bffe660173d42abfc94b86288371d8f1f68789521dcdf -->
1. Before first Allnighter use in a session, read `alln menu --json`.
2. Choose from `useWhen` / `dontUseWhen`; pass canonical ids only.
3. Before an unfamiliar agent-starting action, run its validation template.
4. Re-read the live menu in a new session; never trust a pasted catalog.
5. After `--no-wait`, run the returned `nextAction.command` once (`alln show <id> --stream`); never poll or resume — re-run reattaches, kill never kills the run.
6. Relay running ≠ dev running — check devRunId.
7. Parallel feedback: `alln run --read-only --model …` — not `--no-commit` (that still queues).
8. One mutator per repo root; `running` is not progress — inspect queue ticket and `observation` on `alln show <id> --json`.
9. Pilot/relay dev report is `pmTurn.report` (not `devLeg` — that is settle/liveness only).
10. After a terminal team run, surface `artifact.path` / `artifact.openCommand` to the user — not only the lead answer.
11. When the user asks to print/show/display `alln capacity`, run bare `alln capacity` and include the COMPLETE human-readable stdout table verbatim in your final response — never a summary, selected highlights, JSON, or "shown above"; a summary may follow only after the full table. Use `--json` only when the user explicitly requests JSON/machine-readable output or a program needs the schema.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Ask the menu first:

```bash
alln menu --json
```

Pick ready seat ids, then start a loop. The brief is the only required input —
seats default by tier:

```bash
alln models --json
alln loop start "<what you want done>" --project <id|path> --json
```

Point at a spec instead of restating it in the brief (optional — a shortcut, not
the shape), or pin seats the user named:

```bash
alln loop start "<what you want done>" --spec <path> --project <id|path> --pm <agent-id> --dev <agent-id> --json
```

If you detach with `--no-wait`, use its returned waiter to receive the terminal PM Turn:

```bash
alln loop status <run-id> --wait-for "terminal" --timeout 7200 --json
```

Stop an owned tree when needed:

```bash
alln kill <run-id> --json
```
