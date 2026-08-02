# Recover a run that lost its terminal

Runs stay observable after the launching shell is gone. Use the exact monitor / result / cancel argv for the kind of work that was started.

## Example utterances

1. "Recover a run that lost its terminal."
2. "Did that team run finish? I closed the window."
3. "Cancel the stuck run — I don't have the original stdout."

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

Read the live menu for lifecycle commands, then use the exact run id:

```bash
alln menu --json
```

Team run terminal delivery (one surface — reattach, then cancel if needed):

```bash
alln show <run-id> --stream
alln team cancel <run-id> --json
```

Loop terminal delivery (status owns terminal truth; cancel via kill). A killed
`loop wait` is not a failed round — run the appropriate status waiter; if
orphan, inspect before any new step:

```bash
alln loop status <run-id> --wait-for "terminal" --timeout 7200 --json
alln loop status <run-id> --wait-for parked --timeout 7200 --json
alln kill <run-id> --json
```

Chat / single-worker cancel:

```bash
alln kill <run-id> --json
```

Silence alone is not health — read `observation` (`ownerState` / `activityMode` / `lastActivityAt`) from `alln show <id> --json`.
