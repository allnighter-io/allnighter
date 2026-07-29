# Challenge this decision before I commit

Session-led blind jury (Spec Review team). Spec Review is the common recipe — you synthesize; seats return structured findings only.

## Example utterances

1. "Challenge this decision before I commit."
2. "Run Spec Review on this doc — I want a second opinion."
3. "Blind-jury this architecture call before we build."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v4 hash=9e49c668915fdd9919d0c99681c0a88772b7b0f842afed680ebbf8be9d735c1f -->
1. Before first Allnighter use in a session, read `alln menu --json`.
2. Choose from `useWhen` / `dontUseWhen`; pass canonical ids only.
3. Before an unfamiliar agent-starting action, run its validation template.
4. Re-read the live menu in a new session; never trust a pasted catalog.
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

Optional chain into Pilot on the same doc once the run settles:

```bash
alln pair pilot start --doc <same-path> --project <id|path> --json
```
