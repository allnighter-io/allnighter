# OpenCode dogfood log — AI Readiness (ARA) execution

PM: Cursor agent. Implementer: DeepSeek V4 Pro via OpenCode (`model_opencode_deepseek_v4_pro`).
Packet: `docs/phases/AI_Readiness.md`. Playbook: Execution-Playbook + OMH slice bounds.
Harness: `docs/qa/opencode-mutating-commit/SLICE_TEMPLATE.md`.

| When | Run | Slice | Symptom | Verdict |
| --- | --- | --- | --- | --- |
| 2026-08-09 | (pending) | ARA-S01 | — | — |

## Standing rules

- Pro mutating + must commit; host audits every commit.
- If Pro defers a Works Test → host completes before next slice.
- Wall >15m → consider kill + split; log overrun here.
- Follow-up OpenCode product work → separate phase packet after ARA closeout.
