# Keep working while I'm away

Unattended PM↔dev loop (Relay). A PM seat reviews and a dev seat builds, round after round, until done / escalate / a ceiling.

## Example utterances

1. "Keep going without me for a while."
2. "Run an unattended PM↔dev relay on this spec."
3. "Keep working while I'm away — escalate only if stuck."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v4 hash=9e49c668915fdd9919d0c99681c0a88772b7b0f842afed680ebbf8be9d735c1f -->
1. Before first Allnighter use in a session, read `alln menu --json`.
2. Choose from `useWhen` / `dontUseWhen`; pass canonical ids only.
3. Before an unfamiliar agent-starting action, run its validation template.
4. Re-read the live menu in a new session; never trust a pasted catalog.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Ask the menu first:

```bash
alln menu --json
```

Pick ready seat ids, then start Relay:

```bash
alln models --json
alln pair relay --doc <path> --project <id|path> --pm-model <pm-model-id> --dev-model <dev-model-id> --json
```

Monitor / recover if the terminal is gone (status is also terminal truth):

```bash
alln pair relay-status --relay <run-id> --json
```

Stop an owned tree when needed:

```bash
alln kill <run-id> --json
```
