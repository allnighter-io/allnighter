# Phase 1 Run Log — GLM Code Review (CR-01–10)

Status: **paused — infra upgrades landed; re-run with verify + parallel safety**
Updated: 2026-06-27

## Dogfood learnings

| Learning | Action taken |
| --- | --- |
| Inlined sources work | `expand_cr_packet.py` mandatory |
| Check pass / slice fail (empty stream) | `SliceTerminalClassifier` review-mode fix |
| Phantom symbol in packet | Auto symbols in expand; removed CR-01 hand stubs |
| Phantom P0 possible (CR-01 P0-2) | Verify pass added; **hold P0-2 until verify** |
| Serial 2–3 hr batch | Parallel only when `cr_parallel_plan.py` safe (≤4) |
| Write lock serialized reviews | `advisoryReview` skips lock for findings-only |

## CR-01 triage (pre-verify)

| Claim | Pre-verify | Post-verify |
| --- | --- | --- |
| P0-1 owner-token `release` | promote candidate | run verify |
| P0-2 TOCTOU waiter registration | **hold** — may be phantom | run verify |
| P1 symlink keys | backlog | — |

## Re-run

```bash
# Full pipeline: expand → parallel review (safe) → verify per slice
scripts/run_cr_phase1.sh Allnighter

# Serial only
PAIR_CR_PARALLEL=0 scripts/run_cr_phase1.sh Allnighter 01
```

## Run status

| ID | Review | Verify | Notes |
| --- | --- | --- | --- |
| CR-01 | findings yes | pending re-run | pre-upgrade slice failed; check passed |
| CR-02–10 | pending | pending | batch stopped for learning |
