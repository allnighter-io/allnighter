# Phase 1 Run Log — GLM Code Review (CR-01–10)

Status: **partial batch — CR-01–03 complete; CR-04–10 pending re-run**
Updated: 2026-06-27

## Durable findings archive

Raw GLM output lives in `findings/` (gitignored). **Committed copies** so nothing is lost:

| ID | Archive | Promoted |
| --- | --- | --- |
| CR-01 | [`triage/CR-01-findings.md`](triage/CR-01-findings.md) | RUNLOCK-S01, RUNLOCK-S02 |
| CR-02 | [`triage/CR-02-findings.md`](triage/CR-02-findings.md) | backlog (compaction marker brittleness) |
| CR-03 | [`triage/CR-03-findings.md`](triage/CR-03-findings.md) | backlog (allowlist content check) |

## Dogfood learnings

| Learning | Resolution |
| --- | --- |
| Inlined sources work | `expand_cr_packet.py` mandatory |
| Check pass / slice fail (empty stream) | `OpenCodeServeClient` tool-only completion → worker `.done` (not classifier bypass) |
| Phantom P0 (TOCTOU) | **Rejected** in CR-01 final findings — verify + actor semantics |
| Phantom symbol in packet | Auto symbols in expand |
| Serial batch | Parallel when `cr_parallel_plan.py` safe (≤4) |
| Findings gitignored | Copy to `triage/` on triage |

## CR-01 triage (final)

| Claim | Verdict | Sprint |
| --- | --- | --- |
| P0 TOCTOU waiter registration | **Rejected** — false alarm (sync continuation append) | — |
| P1 owner-token `release` | **Promote** | [`RUNLOCK-S01`](../sprint/runlock/RUNLOCK-S01-owner-token-release.md) |
| P1 symlink/case canonical key | **Promote** | [`RUNLOCK-S02`](../sprint/runlock/RUNLOCK-S02-canonical-key-symlinks.md) |
| P1 holder crash leaks key | Backlog | — |
| P2 nits | Archive | — |

Original dogfood run: slice `failed` (empty_output) but check passed — fixed at worker layer, not classifier.

## CR-02 / CR-03 (summary — see triage archives)

**CR-02:** F2 protected but `contains("compaction")` is brittle; empty-output-before-check can stall file-writing workers. No sprint yet.

**CR-03:** Gate fail-closed; P1 = allowlist content not validated (`[""]` passes). No sprint yet.

## Run status

| ID | Review | Verify | Slice | Notes |
| --- | --- | --- | --- | --- |
| CR-01 | archived | — | pre-fix failed | triaged → RUNLOCK-S01/S02 |
| CR-02 | archived | pending | unknown | compaction classifier |
| CR-03 | archived | pending | unknown | SliceGate scope |
| CR-04–10 | pending | pending | — | batch stopped for infra |

## Re-run remaining

```bash
scripts/run_cr_phase1.sh Allnighter 04 05 06 07 08 09 10
```

After each slice: copy `findings/CR-NN.md` → `triage/CR-NN-findings.md`, update this log.
