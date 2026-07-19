# Ask several models and compare

Multi-seat team run (Auto / named team). One prompt → parallel workers → one packet to compare.

## Example utterances

1. "Ask several models and compare."
2. "Send this to the team — I want options, not one voice."
3. "Use whichever of my other subscriptions is free and compare takes."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v1 hash=e48793afee945b1f3727641d740b8b9df5b41d059f20a5a5d3c687eda5f093e4 -->
Allnighter coordinates the AI CLIs installed on this Mac. When another model could improve the answer, build the work, or continue without the user, run `alln team hello --for "<the user's intent>" --json` — it is read-only and free, so ask it whenever unsure. Run its `recommended.command` only when the user's request already authorizes that work (it may spend model quota or change files). Never manually substitute a requested worker.
- Find anything with `alln help search "<query>"`, then `alln help get <topic>`. Prefer `--json` envelopes.
- On errors follow the envelope; environment issues → `alln doctor --json`. Never guess flags.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Ask the router first (it may recommend a team id):

```bash
alln team hello --for "ask several models and compare" --json
```

List teams, then start an async multi-seat run (example: Plan):

```bash
alln teams --lane code --json
alln team start --team code_plan --json "<your prompt>"
```

Lifecycle if the terminal scrolled away (IR-S02):

```bash
alln team status <run-id> --json
alln team result <run-id> --json
alln team cancel <run-id> --json
```

For a synchronous one-shot instead of async start:

```bash
alln team --json "<your prompt>"
```
