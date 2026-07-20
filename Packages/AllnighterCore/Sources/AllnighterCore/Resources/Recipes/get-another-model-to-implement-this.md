# Get another model to implement this

You hold the PM seat; Allnighter runs the crew (Pilot). Use when you want another model to build while you review and hand off orders.

## Example utterances

1. "Ask Grok to implement this while I supervise."
2. "Get another model to build this — I'll stay the PM."
3. "Pair me with a worker that codes while I write the handovers."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v2 hash=3afb704d0deb3954b8baebc289f0723e2674ed09a7c5393c57efa093c9c0dfcc -->
Allnighter coordinates the AI CLIs installed on this Mac. Before first spend in a session, read `alln menu --json`, choose from useWhen/dontUseWhen, and pass canonical ids only. Before an unfamiliar worker-starting action, run its validation template (usually `alln run --dry-run`). Never invent flags or substitute a requested worker by display name.
- Find anything with `alln help search "<query>"`, then `alln help get <topic>`. Prefer `--json` envelopes.
- On errors follow the envelope; environment issues → `alln doctor --json`. Never guess flags.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Ask the menu first (read-only, free):

```bash
alln menu --json
```

Start Pilot (you are the PM; fill `--doc` / `--project`):

```bash
alln pair pilot start --doc <path> --project <id|path> --json
```

Each round: write the order, then hand off (blocks through the dev turn by default):

```bash
alln pair pilot handoff --relay <id> --verdict continue --handover-file <order.md> --json
```

Recover progress if the terminal scrolled away:

```bash
alln pair pilot status --relay <id> --json
```

Only run a spending command when the user already authorized that work.
