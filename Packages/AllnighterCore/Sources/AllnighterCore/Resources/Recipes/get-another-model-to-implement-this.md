# Get another model to implement this

You hold the PM seat; Allnighter runs the crew (Pilot). Use when you want another model to build while you review and hand off orders.

## Example utterances

1. "Ask Grok to implement this while I supervise."
2. "Get another model to build this — I'll stay the PM."
3. "Pair me with a worker that codes while I write the handovers."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v3 hash=428a37496be9dffc4070f094dfc4410b4fae625cb5c412e452e61df649a751ba -->
1. Before first Allnighter use in a session, read `alln menu --json`.
2. Choose from `useWhen` / `dontUseWhen`; pass canonical ids only.
3. Before an unfamiliar worker-starting action, run its validation template.
4. Re-read the live menu in a new session; never trust a pasted catalog.
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
