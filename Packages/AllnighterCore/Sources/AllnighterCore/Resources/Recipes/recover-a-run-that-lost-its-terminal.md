# Recover a run that lost its terminal

Runs stay observable after the launching shell is gone. Use the exact monitor / result / cancel argv for the kind of work that was started.

## Example utterances

1. "Recover a run that lost its terminal."
2. "Did that team run finish? I closed the window."
3. "Cancel the stuck run — I don't have the original stdout."

## Teaching

<!-- ALLNIGHTER:TEACHING:INSERT -->

## Recipe

Read the live menu for lifecycle commands, then use the exact run id:

```bash
alln menu --json
```

Team run terminal delivery (one surface — reattach, then cancel if needed):

```bash
alln show <run-id> --stream
alln team cancel <run-id> --json
```

Loop terminal delivery (status owns terminal truth; cancel via kill). A killed
`loop wait` is not a failed round — run the appropriate status waiter; if
orphan, inspect before any new step:

```bash
alln loop status <run-id> --wait-for "terminal" --timeout 7200 --json
alln loop status <run-id> --wait-for parked --timeout 7200 --json
alln kill <run-id> --json
```

Chat / single-worker cancel:

```bash
alln kill <run-id> --json
```

Silence alone is not health — read `observation` (`ownerState` / `activityMode` / `lastActivityAt`) from `alln show <id> --json`.
