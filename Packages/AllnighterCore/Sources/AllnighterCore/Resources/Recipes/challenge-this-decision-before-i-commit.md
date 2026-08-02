# Challenge this decision before I commit

Session-led blind jury (Spec Review team). Spec Review is the common recipe — you synthesize; seats return structured findings only.

## Example utterances

1. "Challenge this decision before I commit."
2. "Run Spec Review on this doc — I want a second opinion."
3. "Blind-jury this architecture call before we build."

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

Run Spec Review on the target (fill `--project`; pass the doc path or its content
in the prompt). Runs are foreground — the verdict comes back in this terminal:

```bash
alln run --team code_spec_review --project <id|path> --json "<path to the doc, or its content>"
```

Read a settled run again by id:

```bash
alln show <run-id> --json
```

Optional chain into a loop on the same doc once the run settles:

```bash
alln loop start "<what you want done>" --spec <same-path> --pm caller --project <id|path> --json
```
