# Get another model to implement this

You hold the PM seat; Allnighter runs the crew (Pilot). Use when you want another model to build while you review and hand off orders.

## Example utterances

1. "Ask Grok to implement this while I supervise."
2. "Get another model to build this — I'll stay the PM."
3. "Pair me with a worker that codes while I write the handovers."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v4 hash=9e49c668915fdd9919d0c99681c0a88772b7b0f842afed680ebbf8be9d735c1f -->
1. Before first Allnighter use in a session, read `alln menu --json`.
2. Choose from `useWhen` / `dontUseWhen`; pass canonical ids only.
3. Before an unfamiliar agent-starting action, run its validation template.
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

Each round for a long job: write the order, hand off with `--no-wait`, then poll status until `awaitingPM` (do not re-dispatch while status is `running`):

```bash
alln pair pilot handoff --relay <id> --verdict continue --handover-file <order.md> --no-wait --json
alln pair pilot status --relay <id> --json
```

`pilot watch` is optional/interactive and disposable — a killed waiting window is not a failed round. If status shows the owner died (orphan), inspect status and the repo before any new handoff — never blind retry.

Only run a spending command when the user already authorized that work.
