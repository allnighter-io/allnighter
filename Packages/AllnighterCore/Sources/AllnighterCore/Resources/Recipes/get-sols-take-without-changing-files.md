# Get Sol's take without changing files

One named worker, one read-only ask — use `alln run`, not a multi-seat team. Prefer Codex Sol (`model_gpt_sol`) when the user says "Sol" without naming a host.

## Example utterances

1. "Get Sol's take on this spec — don't change anything."
2. "Read-only review from Sol; findings only."
3. "Ask Sol about these docs; change nothing."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v4 hash=9e49c668915fdd9919d0c99681c0a88772b7b0f842afed680ebbf8be9d735c1f -->
1. Before first Allnighter use in a session, read `alln menu --json`.
2. Choose from `useWhen` / `dontUseWhen`; pass canonical ids only.
3. Before an unfamiliar agent-starting action, run its validation template.
4. Re-read the live menu in a new session; never trust a pasted catalog.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

menu first (named-worker + read-only):

```bash
alln menu --json
```

Paste-ready Codex Sol review (`--project` required; `--no-commit` reinforces no commit):

```bash
alln run --project <id|path> --model model_gpt_sol --lane code --no-commit --stream \
  "Read-only review of <path/to/Doc_A.md> and <path/to/Doc_B.md>. Do not edit files. Return findings only."
```

Notes:

- `model_gpt_sol` = Codex Sol; `model_cursor_gpt_sol` = Cursor Sol (different driver / quota).
- `--stream` for live control; swap to `--json` only when you want one final envelope.
- Cancel if needed: `alln kill <run-id> --json`.
