# Get another model to implement this

You hold the PM seat; Allnighter runs the crew (Pilot). Use when you want another model to build while you review and hand off orders.

## Example utterances

1. "Ask Grok to implement this while I supervise."
2. "Get another model to build this — I'll stay the PM."
3. "Pair me with a worker that codes while I write the handovers."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v1 hash=e48793afee945b1f3727641d740b8b9df5b41d059f20a5a5d3c687eda5f093e4 -->
Allnighter coordinates the AI CLIs installed on this Mac. When another model could improve the answer, build the work, or continue without the user, run `alln team hello --for "<the user's intent>" --json` — it is read-only and free, so ask it whenever unsure. Run its `recommended.command` only when the user's request already authorizes that work (it may spend model quota or change files). Never manually substitute a requested worker.
- Find anything with `alln help search "<query>"`, then `alln help get <topic>`. Prefer `--json` envelopes.
- On errors follow the envelope; environment issues → `alln doctor --json`. Never guess flags.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Ask the router first (read-only, free):

```bash
alln team hello --for "get another model to implement this" --json
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

Run `recommended.command` from the router only when the user already authorized mutating/spend work.
