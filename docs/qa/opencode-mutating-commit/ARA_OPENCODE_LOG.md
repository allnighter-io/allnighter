# OpenCode dogfood log — AI Readiness (ARA) execution

PM: Cursor agent. Implementer: DeepSeek V4 Pro via OpenCode (`model_opencode_deepseek_v4_pro`).
Packet: archived `docs/archive/phases/AI_Readiness.md`. Playbook + OMH slice bounds.
Harness: `docs/qa/opencode-mutating-commit/SLICE_TEMPLATE.md`.

| When | Run | Slice | Symptom | Verdict |
| --- | --- | --- | --- | --- |
| 2026-08-09 | `B6D64D7D` | ARA-S01 | Clean commit `378a47a` in ~208s; Works Tests green | **PASS** — host added `Finding.id` (`aab85fa7`) Pro omitted from §8 |
| 2026-08-09 | `55A8AE94` | ARA-S02 | Clean commit `6598dd0` in ~311s; 10+1 tests green | **PASS** — full nine seats + strong charter tests |
| 2026-08-09 | `49F85A6B` | ARA-S03 | Clean commit `5c832b6` in ~333s; 27 receipts + SkillCatalog green | **PASS** — host polish: `seatAnswers:` tally (`01d8c0de`/`103d75ec`) |
| 2026-08-09 | `814CA26D` | ARA-S04 | Clean commit `34f19a1` in ~371s; 23 shape tests green | **PASS** |
| 2026-08-09 | `C5A1F0CB` | ARA-S05 | Clean commit `e6db142` in ~378s; artifact + RunStore JSON | **PASS** |
| 2026-08-09 | `A7859053` | ARA-S06 | Clean commit `ebbe5cf` in ~251s; Works Test + cold-start | **PASS** |

## OpenCode follow-up?

**None required for this packet.** All six Pro mutating slices committed in-budget
(~3.5–6.5m each), Works Tests in the same commit, no stalls, no under-ships, no
`incomplete_uncommitted`. Host gaps were tiny schema/API polish only (Finding.id,
tally seat ids) — not OpenCode product defects.

Standing OMH harness + help `opencode_mutating_commit_contract` remain the
improvement surface. Do **not** open a new OpenCode phase from ARA dogfood.

## Standing rules (kept for the next Pro campaign)

- Pro mutating + must commit; host audits every commit.
- If Pro defers a Works Test → host completes before next slice.
- Wall >15m → consider kill + split; log overrun here.
