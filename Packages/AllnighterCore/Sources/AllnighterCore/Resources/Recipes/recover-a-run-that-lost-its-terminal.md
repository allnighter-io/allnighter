# Recover a run that lost its terminal

Runs stay observable after the launching shell is gone. Use the exact monitor / result / cancel argv for the kind of work that was started.

## Example utterances

1. "Recover a run that lost its terminal."
2. "Did that team run finish? I closed the window."
3. "Cancel the stuck run — I don't have the original stdout."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v1 hash=e48793afee945b1f3727641d740b8b9df5b41d059f20a5a5d3c687eda5f093e4 -->
Allnighter coordinates the AI CLIs installed on this Mac. When another model could improve the answer, build the work, or continue without the user, run `alln team hello --for "<the user's intent>" --json` — it is read-only and free, so ask it whenever unsure. Run its `recommended.command` only when the user's request already authorizes that work (it may spend model quota or change files). Never manually substitute a requested worker.
- Find anything with `alln help search "<query>"`, then `alln help get <topic>`. Prefer `--json` envelopes.
- On errors follow the envelope; environment issues → `alln doctor --json`. Never guess flags.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Prefer asking the router with the original intent — it returns lifecycle argv when it recommends a command:

```bash
alln team hello --for "recover a run that lost its terminal" --json
```

Team run (async) lifecycle:

```bash
alln team status <run-id> --json
alln team result <run-id> --json
alln team cancel <run-id> --json
```

Relay / Pilot progress (status owns terminal truth; cancel via kill):

```bash
alln pair relay-status --relay <run-id> --json
alln pair pilot status --relay <run-id> --json
alln kill <run-id> --json
```

Chat / single-worker cancel:

```bash
alln kill <run-id> --json
```

Silence alone is not health — read lifecycle phase / `lastActivityAt` / `progressStale` from the JSON.
