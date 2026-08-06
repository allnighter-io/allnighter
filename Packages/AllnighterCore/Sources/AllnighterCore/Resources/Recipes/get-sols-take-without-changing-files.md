# Get Sol's take without changing files

One named worker, one read-only ask — use `alln run`, not a multi-seat team. Prefer Codex Sol (`model_gpt_sol`) when the user says "Sol" without naming a host.

## Example utterances

1. "Get Sol's take on this spec — don't change anything."
2. "Read-only review from Sol; findings only."
3. "Ask Sol about these docs; change nothing."

## Teaching

<!-- ALLNIGHTER:TEACHING:INSERT -->

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
