# Use a specific model without silent substitution

Pin a named model. Never invent a substitute when the user named one — ask the menu, then run the exact `--model` it returns (or surface unread).

## Example utterances

1. "Use Grok for this — not Auto."
2. "Ask Claude for feedback; don't swap in someone else."
3. "Pin Codex Sol; never silently substitute."

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

Read the live menu, choose the model id from useWhen/dontUseWhen, then dry-run:

```bash
alln menu --json
```

Confirm the model id is on the Bench:

```bash
alln models --json
```

Validate, then run the pinned worker (fill `--project`; use the canonical id only):

```bash
alln run --project <id|path> --model <model-id> --dry-run --json "<prompt>"
alln run --project <id|path> --model <model-id> --json "<prompt>"
```

If the requested worker is unavailable, follow menu blockedReason / doctor — do not pick a different worker unless the user says so.
