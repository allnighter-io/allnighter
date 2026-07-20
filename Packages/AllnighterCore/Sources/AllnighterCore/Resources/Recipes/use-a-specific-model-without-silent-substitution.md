# Use a specific model without silent substitution

Pin a named worker. Never invent a substitute when the user named one — ask the menu, then run the exact `--worker` it returns (or surface unread).

## Example utterances

1. "Use Grok for this — not Auto."
2. "Ask Claude for feedback; don't swap in someone else."
3. "Pin Codex Sol; never silently substitute."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v3 hash=428a37496be9dffc4070f094dfc4410b4fae625cb5c412e452e61df649a751ba -->
1. Before first Allnighter use in a session, read `alln menu --json`.
2. Choose from `useWhen` / `dontUseWhen`; pass canonical ids only.
3. Before an unfamiliar worker-starting action, run its validation template.
4. Re-read the live menu in a new session; never trust a pasted catalog.
<!-- ALLNIGHTER:TEACHING:END -->

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
alln run --project <id|path> --worker <model-id> --dry-run --json "<prompt>"
alln run --project <id|path> --worker <model-id> --json "<prompt>"
```

If the requested worker is unavailable, follow menu blockedReason / doctor — do not pick a different worker unless the user says so.
