# Recover a run that lost its terminal

Runs stay observable after the launching shell is gone. Use the exact monitor / result / cancel argv for the kind of work that was started.

## Example utterances

1. "Recover a run that lost its terminal."
2. "Did that team run finish? I closed the window."
3. "Cancel the stuck run — I don't have the original stdout."

## Teaching (keep in sync with TeachingSnippet)

<!-- ALLNIGHTER:TEACHING v5 hash=20323b37ce8ab80e18fd86c54853ca740456a18131269f021a0b209731bdd8b2 -->
1. Before first Allnighter use in a session, read `alln menu --json`.
2. Choose from `useWhen` / `dontUseWhen`; pass canonical ids only.
3. Before an unfamiliar agent-starting action, run its validation template.
4. Re-read the live menu in a new session; never trust a pasted catalog.
5. After `--no-wait`, run the returned delivery command once; never poll or use resume for terminal delivery.
<!-- ALLNIGHTER:TEACHING:END -->

## Recipe

Read the live menu for lifecycle commands, then use the exact run id:

```bash
alln menu --json
```

Team run terminal delivery:

```bash
alln team status <run-id> --wait-for terminal --timeout 7200 --json
alln team cancel <run-id> --json
```

Relay / Pilot terminal delivery (status owns terminal truth; cancel via kill). For Pilot,
a killed `pilot watch` is not a failed round — run the appropriate status waiter; if orphan,
inspect before any new handoff:

```bash
alln pair relay-status --relay <run-id> --wait-for terminal --timeout 7200 --json
alln pair pilot status --relay <run-id> --wait-for parked --timeout 7200 --json
alln kill <run-id> --json
```

Chat / single-worker cancel:

```bash
alln kill <run-id> --json
```

Silence alone is not health — read lifecycle phase / `lastActivityAt` / `progressStale` from the JSON.
