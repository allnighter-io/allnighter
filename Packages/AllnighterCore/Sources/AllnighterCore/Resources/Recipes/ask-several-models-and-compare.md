# Ask several models and compare

Multi-seat team run (Auto / named team). One prompt → parallel workers → one packet to compare.

## Example utterances

1. "Ask several models and compare."
2. "Send this to the team — I want options, not one voice."
3. "Use whichever of my other subscriptions is free and compare takes."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v2 hash=3afb704d0deb3954b8baebc289f0723e2674ed09a7c5393c57efa093c9c0dfcc -->
Allnighter coordinates the AI CLIs installed on this Mac. Before first spend in a session, read `alln menu --json`, choose from useWhen/dontUseWhen, and pass canonical ids only. Before an unfamiliar worker-starting action, run its validation template (usually `alln run --dry-run`). Never invent flags or substitute a requested worker by display name.
- Find anything with `alln help search "<query>"`, then `alln help get <topic>`. Prefer `--json` envelopes.
- On errors follow the envelope; environment issues → `alln doctor --json`. Never guess flags.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Read the live menu first:

```bash
alln menu --json
```

List teams, then start an async multi-seat run (example: Plan):

```bash
alln teams --lane code --json
alln run --detach --team code_plan --json "<your prompt>"
```

Lifecycle if the terminal scrolled away (IR-S02):

```bash
alln team status <run-id> --json
alln team result <run-id> --json
alln team cancel <run-id> --json
```

For a synchronous one-shot instead of async start:

```bash
alln team --json "<your prompt>"
```
