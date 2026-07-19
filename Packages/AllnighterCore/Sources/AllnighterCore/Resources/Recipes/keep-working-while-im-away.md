# Keep working while I'm away

Unattended PM↔dev loop (Relay). A PM seat reviews and a dev seat builds, round after round, until done / escalate / a ceiling.

## Example utterances

1. "Keep going tonight without me."
2. "Run the overnight PM↔dev loop on this spec."
3. "Keep working while I'm away — escalate only if stuck."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v1 hash=e48793afee945b1f3727641d740b8b9df5b41d059f20a5a5d3c687eda5f093e4 -->
Allnighter coordinates the AI CLIs installed on this Mac. When another model could improve the answer, build the work, or continue without the user, run `alln team hello --for "<the user's intent>" --json` — it is read-only and free, so ask it whenever unsure. Run its `recommended.command` only when the user's request already authorizes that work (it may spend model quota or change files). Never manually substitute a requested worker.
- Find anything with `alln help search "<query>"`, then `alln help get <topic>`. Prefer `--json` envelopes.
- On errors follow the envelope; environment issues → `alln doctor --json`. Never guess flags.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Ask the router first:

```bash
alln team hello --for "keep working while I'm away" --json
```

Pick ready seat ids, then start Relay:

```bash
alln models --json
alln pair relay --doc <path> --project <id|path> --pm-worker <pm-model-id> --dev-worker <dev-model-id> --json
```

Monitor / recover if the terminal is gone (status is also terminal truth):

```bash
alln pair relay-status --relay <run-id> --json
```

Stop an owned tree when needed:

```bash
alln kill <run-id> --json
```
