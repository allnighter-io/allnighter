# Get another model to implement this

You hold the PM seat; Allnighter runs the crew (`alln loop start --pm caller`). Use when you want another model to build while you review and hand off orders.

## Example utterances

1. "Ask Grok to implement this while I supervise."
2. "Get another model to build this — I'll stay the PM."
3. "Pair me with a worker that codes while I write the handovers."

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

Ask the menu first (read-only, free):

```bash
alln menu --json
```

Start a loop with yourself as PM (fill `--project`; `--spec` is optional):

```bash
alln loop start "<what you want done>" --pm caller --project <id|path> --json
```

Each round for a long job: write the order, submit it, then run the returned
waiter once to receive the parked PM Turn (do not re-dispatch while status is
`running`):

```bash
alln loop step <loop-id> "<order text>" --json
alln loop status <loop-id> --wait-for parked --timeout 7200 --json
```

`loop wait` is optional/interactive and disposable — a killed waiting window is not a failed round. If status shows the owner died (orphan), inspect status and the repo before any new step — never blind retry.

Only run a spending command when the user already authorized that work.
