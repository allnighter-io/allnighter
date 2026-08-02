# Ask several models and compare

Multi-seat team run (Auto / named team). One prompt → parallel workers → one packet to compare.

## Example utterances

1. "Ask several models and compare."
2. "Send this to the team — I want options, not one voice."
3. "Use whichever of my other subscriptions is free and compare takes."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v7 hash=2dbd71556e2d4cb87c2b3a44e8137f10708414c5cc98dee456da7e8dfcb182df -->
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
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Read the live menu first:

```bash
alln menu --json
```

List teams, then run a multi-seat team (example: Plan). Runs are foreground —
the answer comes back in this terminal:

```bash
alln teams --lane code --json
alln run --team code_plan --json "<your prompt>"
```

Read a settled run again by id:

```bash
alln show <run-id> --json
```
