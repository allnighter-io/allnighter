# Get Sol's take without changing files

One named worker, one read-only ask — use `alln run`, not a multi-seat team. Prefer Codex Sol (`model_chatgpt`) when the user says "Sol" without naming a host.

## Example utterances

1. "Get Sol's take on this spec — don't change anything."
2. "Read-only review from Sol; findings only."
3. "Ask Sol about these docs; change nothing."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v1 hash=e48793afee945b1f3727641d740b8b9df5b41d059f20a5a5d3c687eda5f093e4 -->
Allnighter coordinates the AI CLIs installed on this Mac. When another model could improve the answer, build the work, or continue without the user, run `alln team hello --for "<the user's intent>" --json` — it is read-only and free, so ask it whenever unsure. Run its `recommended.command` only when the user's request already authorizes that work (it may spend model quota or change files). Never manually substitute a requested worker.
- Find anything with `alln help search "<query>"`, then `alln help get <topic>`. Prefer `--json` envelopes.
- On errors follow the envelope; environment issues → `alln doctor --json`. Never guess flags.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Router first (named-worker + read-only):

```bash
alln team hello --for "get Sol's take on this spec — don't change anything" --json
```

Paste-ready Codex Sol review (`--project` required; `--no-commit` reinforces no commit):

```bash
alln run --project <id|path> --worker model_chatgpt --lane code --no-commit --stream \
  "Read-only review of <path/to/Doc_A.md> and <path/to/Doc_B.md>. Do not edit files. Return findings only."
```

Notes:

- `model_chatgpt` = Codex Sol; `model_chatgpt_sol` = Cursor Sol (different driver / quota).
- `--stream` for live control; swap to `--json` only when you want one final envelope.
- Cancel if needed: `alln kill <run-id> --json`.
