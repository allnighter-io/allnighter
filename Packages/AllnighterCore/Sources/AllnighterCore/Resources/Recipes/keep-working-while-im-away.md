# Keep working while I'm away

Unattended PM↔dev loop (Relay). A PM seat reviews and a dev seat builds, round after round, until done / escalate / a ceiling.

## Example utterances

1. "Keep going without me for a while."
2. "Run an unattended PM↔dev relay on this spec."
3. "Keep working while I'm away — escalate only if stuck."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v5 hash=5d05c3b988357e0a225ac98e55d8297520efcc86ad175d824daac6da9e295210 -->
1. Before first Allnighter use in a session, read `alln menu --json`.
2. Choose from `useWhen` / `dontUseWhen`; pass canonical ids only.
3. Before an unfamiliar agent-starting action, run its validation template.
4. Re-read the live menu in a new session; never trust a pasted catalog.
5. After `--no-wait`, run the returned delivery command once; never poll or use resume for terminal delivery.
6. Relay running ≠ dev running — check devRunId.
7. Parallel feedback: `alln run --read-only --model …` — not `--no-commit` (that still queues).
8. One mutator per repo root; `running` is not progress — inspect queue ticket and progressStale.
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

If you detach with `--no-wait`, use its returned waiter to receive the terminal PM Turn:

```bash
alln pair relay-status --relay <run-id> --wait-for terminal --timeout 7200 --json
```

Stop an owned tree when needed:

```bash
alln kill <run-id> --json
```
