# OpenCode dogfood log — AI Readiness (ARA) execution

PM: Cursor agent. Implementer: DeepSeek V4 Pro via OpenCode (`model_opencode_deepseek_v4_pro`).
Packet: `docs/phases/AI_Readiness.md`. Playbook: Execution-Playbook + OMH slice bounds.
Harness: `docs/qa/opencode-mutating-commit/SLICE_TEMPLATE.md`.

| When | Run | Slice | Symptom | Verdict |
| --- | --- | --- | --- | --- |
| 2026-08-09 | `B6D64D7D` | ARA-S01 | Clean commit `378a47a` in ~208s; Works Tests green | **PASS** — host added `Finding.id` (`aab85fa7`) Pro omitted from §8 |
| 2026-08-09 | (pending) | ARA-S02 | — | — |

## Standing rules

- Pro mutating + must commit; host audits every commit.
- If Pro defers a Works Test → host completes before next slice.
- Wall >15m → consider kill + split; log overrun here.
- Follow-up OpenCode product work → separate phase packet after ARA closeout.

## Host notes

- S01 Pro quality was high (schema + parser + banned-key scan). Only gap: finding `id`.
- Prefer ≤3 prod + ≤1 test; S02 = SkillCatalog + BuiltInTeams + one test file.
