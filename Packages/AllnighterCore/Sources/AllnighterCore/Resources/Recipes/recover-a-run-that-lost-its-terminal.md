# Recover a run that lost its terminal

Runs stay observable after the launching shell is gone. Use the exact monitor / result / cancel argv for the kind of work that was started.

## Example utterances

1. "Recover a run that lost its terminal."
2. "Did that team run finish? I closed the window."
3. "Cancel the stuck run — I don't have the original stdout."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v4 hash=9e49c668915fdd9919d0c99681c0a88772b7b0f842afed680ebbf8be9d735c1f -->
1. Before first Allnighter use in a session, read `alln menu --json`.
2. Choose from `useWhen` / `dontUseWhen`; pass canonical ids only.
3. Before an unfamiliar agent-starting action, run its validation template.
4. Re-read the live menu in a new session; never trust a pasted catalog.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Read the live menu for lifecycle commands, then use the exact run id:

```bash
alln menu --json
```

Team run (async) lifecycle:

```bash
alln team status <run-id> --json
alln team result <run-id> --json
alln team cancel <run-id> --json
```

Relay / Pilot progress (status owns terminal truth; cancel via kill). For Pilot,
a killed `pilot watch` is not a failed round — poll status; if orphan, inspect
before any new handoff:

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
