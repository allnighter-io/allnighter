# Phase 1 Run Log — GLM Code Review (CR-01–10)

Status: **in progress**
Started: 2026-06-27
Executor: `model_opencode_glm_5_2` via OpenCode serve
Dispatch: `scripts/run_cr_phase1.sh` + expanded packets

## Dogfood learnings (control plane)

| Learning | Evidence | Action |
| --- | --- | --- |
| **Inlined sources work** | CR-01 prompt carried full `RunWriteLock.swift`; findings cite line numbers with no grep section | Keep `expand_cr_packet.py` mandatory |
| **ReviewAttemptPrompt works** | Prompt sections rendered; GLM wrote only findings file | — |
| **Check can pass while slice fails** | CR-01: check exit 0, `status: failed`, worker `empty_output` | Triage: classifier should weigh check pass for review mode, or OpenCode stream must surface tool writes |
| **~20 min / review** | CR-01 wall clock ~20 min | Batch 02–10 overnight; F5 parallel breadth holds |
| **Resolved symbol drift** | Packet listed `waitToAcquire(key:ownerLabel:)` but source has `timeout:` | Fix packet stubs; expand script could validate symbols |

## Triage — CR-01 RunWriteLock

**Slice status:** failed (worker `empty_output`) · **Check:** passed · **Findings quality:** high

### Promote to sprint (P0)

1. **Owner-token release** — `release` without holder proof allows two writers (CR-01 P0-1).
2. **Waiter registration TOCTOU** — gap between `held.insert` and queue append can hang or break FIFO (CR-01 P0-2).

### Backlog (P1)

- Symlink-resolving canonical key
- Holder-death watchdog / document restart requirement

### Archive (P2)

- `nextWaiterId` wrap, weak-self timeout task inconsistency

## Run status

| ID | Findings file | Check | Slice status | Triage |
| --- | --- | --- | --- | --- |
| CR-01 | yes | pass | failed (empty_output) | done |
| CR-02 | — | — | pending | — |
| CR-03 | — | — | pending | — |
| CR-04 | — | — | pending | — |
| CR-05 | — | — | pending | — |
| CR-06 | — | — | pending | — |
| CR-07 | — | — | pending | — |
| CR-08 | — | — | pending | — |
| CR-09 | — | — | pending | — |
| CR-10 | — | — | pending | — |

_Update this table as batch `scripts/run_cr_phase1.sh` completes._
