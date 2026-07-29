# Get Sol's take without changing files

One named worker, one read-only ask — use `alln run`, not a multi-seat team. Prefer Codex Sol (`model_chatgpt`) when the user says "Sol" without naming a host.

## Example utterances

1. "Get Sol's take on this spec — don't change anything."
2. "Read-only review from Sol; findings only."
3. "Ask Sol about these docs; change nothing."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v3 hash=428a37496be9dffc4070f094dfc4410b4fae625cb5c412e452e61df649a751ba -->
1. Before first Allnighter use in a session, read `alln menu --json`.
2. Choose from `useWhen` / `dontUseWhen`; pass canonical ids only.
3. Before an unfamiliar worker-starting action, run its validation template.
4. Re-read the live menu in a new session; never trust a pasted catalog.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

menu first (named-worker + read-only):

```bash
alln menu --json
```

Paste-ready Codex Sol review (`--project` required; `--no-commit` reinforces no commit):

```bash
alln run --project <id|path> --model model_chatgpt --lane code --no-commit --stream \
  "Read-only review of <path/to/Doc_A.md> and <path/to/Doc_B.md>. Do not edit files. Return findings only."
```

Notes:

- `model_chatgpt` = Codex Sol; `model_chatgpt_sol` = Cursor Sol (different driver / quota).
- `--stream` for live control; swap to `--json` only when you want one final envelope.
- Cancel if needed: `alln kill <run-id> --json`.
