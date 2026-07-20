# Recover a run that lost its terminal

Runs stay observable after the launching shell is gone. Use the exact monitor / result / cancel argv for the kind of work that was started.

## Example utterances

1. "Recover a run that lost its terminal."
2. "Did that team run finish? I closed the window."
3. "Cancel the stuck run — I don't have the original stdout."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v2 hash=3afb704d0deb3954b8baebc289f0723e2674ed09a7c5393c57efa093c9c0dfcc -->
Allnighter coordinates the AI CLIs installed on this Mac. Before first spend in a session, read `alln menu --json`, choose from useWhen/dontUseWhen, and pass canonical ids only. Before an unfamiliar worker-starting action, run its validation template (usually `alln run --dry-run`). Never invent flags or substitute a requested worker by display name.
- Find anything with `alln help search "<query>"`, then `alln help get <topic>`. Prefer `--json` envelopes.
- On errors follow the envelope; environment issues → `alln doctor --json`. Never guess flags.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Prefer asking the menu with the original intent — it returns lifecycle argv when it recommends a command:

```bash
alln menu --json
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
