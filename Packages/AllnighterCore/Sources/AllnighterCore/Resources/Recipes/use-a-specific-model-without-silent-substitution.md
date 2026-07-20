# Use a specific model without silent substitution

Pin a named worker. Never invent a substitute when the user named one — ask the menu, then run the exact `--worker` it returns (or surface unread).

## Example utterances

1. "Use Grok for this — not Auto."
2. "Ask Claude for feedback; don't swap in someone else."
3. "Pin Codex Sol; never silently substitute."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v2 hash=3afb704d0deb3954b8baebc289f0723e2674ed09a7c5393c57efa093c9c0dfcc -->
Allnighter coordinates the AI CLIs installed on this Mac. Before first spend in a session, read `alln menu --json`, choose from useWhen/dontUseWhen, and pass canonical ids only. Before an unfamiliar worker-starting action, run its validation template (usually `alln run --dry-run`). Never invent flags or substitute a requested worker by display name.
- Find anything with `alln help search "<query>"`, then `alln help get <topic>`. Prefer `--json` envelopes.
- On errors follow the envelope; environment issues → `alln doctor --json`. Never guess flags.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Route with the user's named model in the intent:

```bash
alln menu --json
```

Confirm the model id is on the Bench:

```bash
alln models --json
```

Run the pinned worker (fill `--project`; use the id the menu named):

```bash
alln run --project <id|path> --worker <model-id> --json "<prompt>"
```

If the requested worker is unavailable, follow `nextActions` (models / doctor) — do not pick a different worker unless the user says so.
