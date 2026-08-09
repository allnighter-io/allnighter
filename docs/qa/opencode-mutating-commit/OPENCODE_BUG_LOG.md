# OpenCode bugs / dogfood log (CRS execution)

Scratch log while executing `Capacity_Serve_Refresh_Polish.md` with DeepSeek V4 Pro.
Not SSOT — promote durable lessons into help / packets on closeout.

| When | Run | Seat | Symptom | Verdict |
| --- | --- | --- | --- | --- |
| 2026-08-09 | `2CEEDE81` | GLM-5.2 | Mutating doc edit delivered; run `failed` / `incomplete_uncommitted` | **Prompt**, not OpenCode — instructed “do not commit.” Same seat + Flash commit dogfood green (`24A8B6D3`, `4A3275D3`). |
| 2026-08-09 | `78C6514D` | DeepSeek V4 Pro | CRS-S02 implement+commit | **Green** — `70a961bd`, 10/10 tests, host audit CLEAN. |
| 2026-08-09 | `33E4E984` | DeepSeek V4 Pro | CRS-S01 implement+commit | **Green** — `5e30f3f2`, 11/11 tests, host audit CLEAN. Note: post-refresh `isCancelled` check makes tick-counter cancel predicates need `>2` to reach sleep (test comment); not a product bug. |
| 2026-08-09 | (CRS-S04…) | Pro | _pending_ | |

## Rules for CRS Pro slices

- Mutating + **must git commit** explicit paths for the slice.
- Leave unrelated untracked dirs alone.
- Host audits Pro’s diff before accepting the commit if Pro commits first; amend only if Pro’s commit is wrong and policy allows — prefer fixup commit from host.
