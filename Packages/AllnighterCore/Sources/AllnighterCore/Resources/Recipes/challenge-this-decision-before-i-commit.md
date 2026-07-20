# Challenge this decision before I commit

Session-led blind jury (Panel). Spec Review is the common recipe — you synthesize; seats return structured findings only.

## Example utterances

1. "Challenge this decision before I commit."
2. "Run Spec Review on this doc — I want a second opinion."
3. "Blind-jury this architecture call before we build."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v2 hash=3afb704d0deb3954b8baebc289f0723e2674ed09a7c5393c57efa093c9c0dfcc -->
Allnighter coordinates the AI CLIs installed on this Mac. Before first spend in a session, read `alln menu --json`, choose from useWhen/dontUseWhen, and pass canonical ids only. Before an unfamiliar worker-starting action, run its validation template (usually `alln run --dry-run`). Never invent flags or substitute a requested worker by display name.
- Find anything with `alln help search "<query>"`, then `alln help get <topic>`. Prefer `--json` envelopes.
- On errors follow the envelope; environment issues → `alln doctor --json`. Never guess flags.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Ask the menu first:

```bash
alln menu --json
```

Start a Panel on the target (required `--doc` / `--project`):

```bash
alln panel start --doc <path> --project <id|path> --json
```

Dispatch one blind round (built-in brief on round 1):

```bash
alln panel round --panel <id> --json
```

Check durable state / declare done when finished judging:

```bash
alln panel status --panel <id> --json
alln panel done --panel <id> --json
```

Optional chain into Pilot on the same doc after `panel done`:

```bash
alln pair pilot start --doc <same-path> --project <id|path> --json
```
