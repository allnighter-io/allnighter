# Bug Hunt R6 — gate telemetry evidence (5bdca918)

Controlled R6 replay on case `gen_5dc28030c4fb97d7` (same Composer session-continuity prompt).
Built with `gateWaitMs` / `ttftMs` / pure `durationMs` attribution.

| Arm | Lab dir | Contract | gitHead |
|-----|---------|----------|---------|
| Champion | `.lab/code_bug_hunt_champion-r6_r6_20260622_145605` | 0.889 | 5bdca918 |
| Candidate | `.lab/code_bug_hunt_candidate-r6_r6_20260622_152029` | 0.889 | 5bdca918 |

Compare refused both arms (`runContractScore < 0.95`).

## agy (`model_gemini`) seats — classification

| Seat | Arm | gateWaitMs | durationMs | ttftMs | status | Verdict |
|------|-----|------------|------------|--------|--------|---------|
| #0 | champion | 0 | 232394 | — | done | first in line |
| #1 | champion | 232394 | 304715 | — | done | queued, then ran |
| #2 | champion | **537110** | 303367 | **none** | timed_out | queued ~9m, then **300s silence** |
| #0 | candidate | **0** | 305061 | **none** | timed_out | **seat 1, no queue — pure silence stall** |
| #1 | candidate | 305061 | 170157 | — | done | queued behind #0 timeout |
| #2 | candidate | 475216 | 308159 | — | done | queued, then ran |

**Conclusion:** failures are CLI silence (`no output for 300s`), not gate drops. Seat N always
acquires; high `gateWaitMs` on #2/#3 is expected serialization behind long peers. Candidate
`model_gemini#0` (`gateWaitMs: 0`) proves the stall also happens at n=1.

## cursor (`model_cursor_composer_25`) — all seats done both arms

All three cursor seats completed with healthy `ttftMs` (streaming kept idle timer alive).
See `champion/workers/model_cursor_composer_25_*.metadata.json`.

## Artifacts

Per-seat `workers/*.metadata.json` copied from run journals. Source of truth fields:
`gateWaitMs`, `ttftMs`, `durationMs`, `queueMs` (when present), `status`, `errorReason`.
