# CR-05 — OpenCodeServeCoordinator lifecycle

Status: **ready**
SSOT: [`setup/OpenCode_CLI_Support.md`](../../setup/OpenCode_CLI_Support.md), [`Pair_Programming_Team.md`](../../Pair_Programming_Team.md) §4.1

## Goal

Review GLM's serve bootstrap — the path every pair slice hits before dispatch.

## Why this chunk

If serve is flaky, **every** GLM slice fails before reasoning. ~95 lines, directly affects the
executor chair you're proving. Ties to `OpenCode_Smoke_Probe_Blocker` pain.

## Review lenses

1. `ensureRunning()` idempotency — double-call, concurrent callers?
2. Health probe vs process-alive — false healthy / false dead?
3. Port / URL selection and stale process reuse?
4. Error propagation to `PairCoordinator` (`PAIR_SERVE_UNAVAILABLE`) — recoverable?
5. Shutdown / restart during active slice?

## Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/OpenCodeServeCoordinator.swift` (full file)
- `Packages/AllnighterCore/Sources/AllnighterEngine/OpenCodeServeClient.swift` (signatures + public methods only — inline in prompt)

## Touch only

- `docs/phases/code_review/findings/CR-05.md`

## Copy-paste prompt

```text
Review OpenCodeServeCoordinator — keeps OpenCode serve alive for GLM executor dispatch.

READ ONLY inlined coordinator file. Client signatures provided — no greps.

Lenses:
1. ensureRunning idempotency + concurrency
2. Health vs alive false positives
3. Stale process / port reuse
4. Error surfaces to pair loop
5. Restart mid-slice

Output: docs/phases/code_review/findings/CR-05.md
Suggest minimal smoke test additions if probes are weak.
```

## Check

```bash
test -f docs/phases/code_review/findings/CR-05.md && grep -q "## Findings" docs/phases/code_review/findings/CR-05.md
```

## MCP packet

[`packets/CR-05.json`](../packets/CR-05.json)
