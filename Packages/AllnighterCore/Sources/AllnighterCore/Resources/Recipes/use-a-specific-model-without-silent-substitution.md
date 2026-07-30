# Use a specific model without silent substitution

Pin a named model. Never invent a substitute when the user named one — ask the menu, then run the exact `--model` it returns (or surface unread).

## Example utterances

1. "Use Grok for this — not Auto."
2. "Ask Claude for feedback; don't swap in someone else."
3. "Pin Codex Sol; never silently substitute."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v5 hash=20323b37ce8ab80e18fd86c54853ca740456a18131269f021a0b209731bdd8b2 -->
1. Before first Allnighter use in a session, read `alln menu --json`.
2. Choose from `useWhen` / `dontUseWhen`; pass canonical ids only.
3. Before an unfamiliar agent-starting action, run its validation template.
4. Re-read the live menu in a new session; never trust a pasted catalog.
5. After `--no-wait`, run the returned delivery command once; never poll or use resume for terminal delivery.
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
alln run --project <id|path> --model <model-id> --dry-run --json "<prompt>"
alln run --project <id|path> --model <model-id> --json "<prompt>"
```

If the requested worker is unavailable, follow menu blockedReason / doctor — do not pick a different worker unless the user says so.
