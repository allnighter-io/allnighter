# Keep working while I'm away

Unattended PM↔dev loop (`alln loop start`). A PM seat reviews and a dev seat builds, round after round, until done / escalate / a ceiling.

## Example utterances

1. "Keep going without me for a while."
2. "Set up a loop and have it execute this doc."
3. "Keep working while I'm away — escalate only if stuck."

## Teaching

<!-- ALLNIGHTER:TEACHING:INSERT -->

## Recipe

Ask the menu first:

```bash
alln menu --json
```

Pick ready seat ids, then start a loop. The brief is the only required input —
seats default by tier:

```bash
alln models --json
alln loop start "<what you want done>" --project <id|path> --json
```

Point at a spec instead of restating it in the brief (optional — a shortcut, not
the shape), or pin seats the user named:

```bash
alln loop start "<what you want done>" --spec <path> --project <id|path> --pm <agent-id> --dev <agent-id> --json
```

If you detach with `--no-wait`, use its returned waiter to receive the terminal PM Turn:

```bash
alln loop status <run-id> --wait-for "terminal" --timeout 7200 --json
```

Stop an owned tree when needed:

```bash
alln kill <run-id> --json
```
