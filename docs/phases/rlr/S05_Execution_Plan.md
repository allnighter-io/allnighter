# RLR-S05 Execution Plan — four clocks · idempotency replay · `--retry-of`

Status: **DELIVERED 2026-07-19.** Next: S06 (full Works Test matrix).
Branch `feat/design-chain`. SSOT: `docs/phases/Run_Lifecycle_Reliability.md`
laws **RLR-L8** (clocks) + **RLR-L9** (replay vs intentional retry). Builds on
S04b `KillSettlement` (operator-vs-clock asymmetry) and S01b/c clock defaults +
idempotency key/hash at acceptance.

## What landed

### L8 — four clocks

| Clock | Flag | Default | On fire |
| --- | --- | --- | --- |
| Handshake | `--handshake-timeout` | 60s (`RunClockDefaults`) | `timedOut` + kill tree |
| First activity | `--first-activity-timeout` | 120s | same |
| Idle | `--idle-timeout` (pre-existing) | per-manifest | same |
| Wall | `--wall-timeout` | 3600s | same |

- Budgets resolved at acceptance and persisted on `TeamRun.clockBudgets`.
- `RunClockEnforcer.fire` runs `KillSettlement` then stamps
  `status/endReason = timedOut` **regardless of reap** (clock asymmetry).
  Survivors → `killOutcome` + `contradiction: terminalWithLiveOwnership`.
- `RunEndReason.timedOut` added (was missing).
- Idle/wall still ride the existing ProcessGroupCommandRunner stall/total
  paths; when the worker returns `timedOut`, RunService routes through the
  enforcer rather than inventing a second timer.

### L9 — replay vs `--retry-of`

- Same key + same payload within **24h** (`IdempotencyStore.retention`) →
  original run (no second worker).
- Same key + different payload → public code **`IDEMPOTENCY_CONFLICT`**
  (legacy `IDEMPOTENCY_KEY_REUSED_WITH_DIFFERENT_PAYLOAD` kept as catalog alias).
- Past retention → **`IDEMPOTENCY_EXPIRED`** (tombstone; never silent re-exec).
- `--retry-of <id>` requires prior tree verified stopped (no identity-alive
  recorded workers) or `--accept-survivors`. Links via `RunLink.retryOf`.
  Refusal code: `RETRY_OF_SURVIVORS`.

## Proof

```bash
swift test --package-path Packages/AllnighterCore \
  --filter 'RunClock|Idempotency|RetryOf|RunAcceptance|KillSettlement|RunContradiction'
```

## Gaps / S06

- Full Works Test matrix (items 5 + 9 end-to-end with fake CLI two-process).
- Handshake/first-activity live watchdog on the async detached path (budgets
  persisted; evaluate helper ready; full wall-clock integration is S06 polish).
- Contract regen + `scripts/check.sh` wall.
- GC of very-old idempotency tombstones (S06 reaper territory).
