# CR-04 — CheckRunner subprocess boundary

Status: **ready**
SSOT: [`Pair_Programming_Team.md`](../../Pair_Programming_Team.md) §2, §4

## Goal

Review how repo-declared check commands run — injection, timeout, skipped checks, and stdout tail limits.

## Why this chunk

`CheckRunner` drives pass/fail for the entire pair queue. A malicious or accidental packet command
runs as `/bin/sh -c` in the repo root. ~70 lines, high security + correctness leverage.

## Review lenses

1. Shell injection via `check.command` — is escaping/trust model documented?
2. Timeout behavior — partial output, zombie processes?
3. `skipped: true` paths — when does a slice pass without running checks?
4. `stdoutTailLimit` (4096) — can failure signal be truncated away?
5. Working directory / env inheritance — surprises for monorepos?

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/CheckRunner.swift` (full file)
- `CommandRunner.run` signature only (timeout, cwd, env params)

## Touch only

- `docs/phases/code_review/findings/CR-04.md`

## Copy-paste prompt

```text
Review CheckRunner — runs repo-declared proof commands for pair-programming slices via /bin/sh -c.

READ ONLY inlined CheckRunner.swift. CommandRunner signature provided — do not open that file.

Lenses:
1. Shell injection / trust model for packet.check.command
2. Timeout + process cleanup
3. skipped check → passed classifier interaction (see SliceTerminalClassifier: check.skipped → passed)
4. stdout tail truncation hiding failures
5. cwd/env surprises

Output: docs/phases/code_review/findings/CR-04.md. Tag security findings P0.
```

## Check

```bash
test -f docs/phases/code_review/findings/CR-04.md && grep -q "## Findings" docs/phases/code_review/findings/CR-04.md
```

## MCP packet

[`packets/CR-04.json`](../packets/CR-04.json)
