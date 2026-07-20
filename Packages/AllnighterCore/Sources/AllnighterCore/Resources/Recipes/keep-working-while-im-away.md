# Keep working while I'm away

Unattended PM↔dev loop (Relay). A PM seat reviews and a dev seat builds, round after round, until done / escalate / a ceiling.

## Example utterances

1. "Keep going tonight without me."
2. "Run the overnight PM↔dev loop on this spec."
3. "Keep working while I'm away — escalate only if stuck."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v2 hash=3afb704d0deb3954b8baebc289f0723e2674ed09a7c5393c57efa093c9c0dfcc -->
Allnighter coordinates the AI CLIs installed on this Mac. Before first spend in a session, read `alln menu --json`, choose from useWhen/dontUseWhen, and pass canonical ids only. Before an unfamiliar worker-starting action, run its validation template (usually `alln run --dry-run`). Never invent flags or substitute a requested worker by display name.
- Find anything with `alln help search "<query>"`, then `alln help get <topic>`. Prefer `--json` envelopes.
- On errors follow the envelope; environment issues → `alln doctor --json`. Never guess flags.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Ask the menu first:

```bash
alln menu --json
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
