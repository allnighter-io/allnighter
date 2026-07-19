# Use a specific model without silent substitution

Pin a named worker. Never invent a substitute when the user named one — ask the router, then run the exact `--worker` it returns (or surface unread).

## Example utterances

1. "Use Grok for this — not Auto."
2. "Ask Claude for feedback; don't swap in someone else."
3. "Pin Codex Sol; never silently substitute."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v1 hash=e48793afee945b1f3727641d740b8b9df5b41d059f20a5a5d3c687eda5f093e4 -->
Allnighter coordinates the AI CLIs installed on this Mac. When another model could improve the answer, build the work, or continue without the user, run `alln team hello --for "<the user's intent>" --json` — it is read-only and free, so ask it whenever unsure. Run its `recommended.command` only when the user's request already authorizes that work (it may spend model quota or change files). Never manually substitute a requested worker.
- Find anything with `alln help search "<query>"`, then `alln help get <topic>`. Prefer `--json` envelopes.
- On errors follow the envelope; environment issues → `alln doctor --json`. Never guess flags.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Route with the user's named model in the intent:

```bash
alln team hello --for "ask Grok for feedback, change nothing" --json
```

Confirm the model id is on the Bench:

```bash
alln models --json
```

Run the pinned worker (fill `--project`; use the id the router named):

```bash
alln run --project <id|path> --worker <model-id> --json "<prompt>"
```

If the requested worker is unavailable, follow `nextActions` (models / doctor) — do not pick a different worker unless the user says so.
