# Use a specific model without silent substitution

Pin a named model. Never invent a substitute when the user named one — ask the menu, then run the exact `--model` it returns (or surface unread).

## Example utterances

1. "Use Grok for this — not Auto."
2. "Ask Claude for feedback; don't swap in someone else."
3. "Pin Codex Sol; never silently substitute."

## Teaching

<!-- ALLNIGHTER:TEACHING:INSERT -->

## Recipe

Read the live menu, choose the model id from useWhen/dontUseWhen, then dry-run:

```bash
alln menu --json
```

Confirm the model id is on the Bench:

```bash
alln models --json
```

Validate, then run the pinned worker (fill `--project`; use the canonical id only):

```bash
alln run --project <id|path> --model <model-id> --dry-run --json "<prompt>"
alln run --project <id|path> --model <model-id> --json "<prompt>"
```

If the requested worker is unavailable, follow menu blockedReason / doctor — do not pick a different worker unless the user says so.
