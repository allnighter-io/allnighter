# Get another model to implement this

You hold the PM seat; Allnighter runs the crew (`alln loop start --pm caller`). Use when you want another model to build while you review and hand off orders.

## Example utterances

1. "Ask Grok to implement this while I supervise."
2. "Get another model to build this — I'll stay the PM."
3. "Pair me with a worker that codes while I write the handovers."

## Teaching

<!-- ALLNIGHTER:TEACHING:INSERT -->

## Recipe

Ask the menu first (read-only, free):

```bash
alln menu --json
```

Start a loop with yourself as PM (fill `--project`; `--spec` is optional):

```bash
alln loop start "<what you want done>" --pm caller --project <id|path> --json
```

Each round for a long job: write the order, submit it, then run the returned
waiter once to receive the parked PM Turn (do not re-dispatch while status is
`running`):

```bash
alln loop step <loop-id> "<order text>" --json
alln loop status <loop-id> --wait-for parked --timeout 7200 --json
```

`loop wait` is optional/interactive and disposable — a killed waiting window is not a failed round. If status shows the owner died (orphan), inspect status and the repo before any new step — never blind retry.

Only run a spending command when the user already authorized that work.
