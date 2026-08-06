# Ask several models and compare

Multi-seat team run (Auto / named team). One prompt → parallel workers → one packet to compare.

## Example utterances

1. "Ask several models and compare."
2. "Send this to the team — I want options, not one voice."
3. "Use whichever of my other subscriptions is free and compare takes."

## Teaching

<!-- ALLNIGHTER:TEACHING:INSERT -->

## Recipe

Read the live menu first:

```bash
alln menu --json
```

List teams, then run a multi-seat team (example: Plan). Runs are foreground —
the answer comes back in this terminal:

```bash
alln teams --lane code --json
alln run --team code_plan --json "<your prompt>"
```

Read a settled run again by id:

```bash
alln show <run-id> --json
```
