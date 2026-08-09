# OpenCode Mutating Long-Run Hardening

Status: **OPEN — Ready for Implementation** (founder: long Pro mutating must
work, not read-only-only)
Owner: Allnighter (`RunService` / teaching / Works Test gate) + AgentOS
(`OpenCode*` capture continuity) as named per slice
Created: 2026-08-09 | Updated: 2026-08-09
Parent dogfood: CRS Pro mutating slices (`78C6514D`, `33E4E984`, `E01E1514`,
`C495ABFE`) + GLM `2CEEDE81` + commit harness
`docs/qa/opencode-mutating-commit/`
Related: archived OCH `OpenCode_Turn_Capture_Hardening.md` (capture races);
archive-ready `OpenCode_Long_Run_Continuity.md` (stream/stall)

---

## If you only read one thing

Short OpenCode mutating edits that **git commit** succeed. Long DeepSeek V4 Pro
mutating runs often finish with a commit but **under-ship** the packet Works
Test (CRS-S04 deferred mid-probe cancel; host had to complete). Read-only long
audits and tiny commit dogfoods are not enough — Pro must be trustworthy for
multi-file mutating slices.

| ID | Sev | Defect | Slice |
| --- | --- | --- | --- |
| **OMH-S01** | High | Mutating seat leaves dirty tree → `incomplete_uncommitted` even with a delivered answer when commit was skipped (prompt or seat) | Mutating commit contract + teaching |
| **OMH-S02** | High | Long mutating Pro can ship code while skipping a named Works Test (CRS-S04) | Under-ship / Works Test gate in the slice prompt + host checklist |
| **OMH-S03** | Med | Long tool marathons (~20–30m) have weak progress truth; host cannot tell stuck vs thinking | Observation / activity heartbeat for OpenCode tool storms |
| **OMH-S04** | Med | Slice prompts oversized → Pro thrash, defer critical pieces | Bound OpenCode mutating slices (time + file + Works Test count) |
| **OMH-S05** | Low | Dogfood only covers one-file TARGET stamp | Extend harness to multi-file + required Works Test file |

Ship **S01 → S02 → S04 → S03 → S05**. Prefer Allnighter teaching/orchestration
first; AgentOS only when capture/activity is the truth owner.

---

## Founder intent

DeepSeek V4 Pro via OpenCode must reliably execute **multi-file mutating
slices** and land them with a green Works Test in the same commit. One-file
stamps and read-only audits do not prove this.

---

## Evidence (2026-08-09)

| Run | Seat | Shape | Outcome |
| --- | --- | --- | --- |
| `4A3275D3` / `24A8B6D3` | Flash / GLM | 1-file edit+commit | `done` + `committed: true` |
| `2CEEDE81` | GLM | Doc mutate, prompt said no commit | `failed` / `incomplete_uncommitted` (prompt) |
| `78C6514D` | Pro | CRS-S02 code+tests+commit | Green |
| `33E4E984` | Pro | CRS-S01 code+tests+commit | Green |
| `E01E1514` | Pro | CRS-S04 ~27m | Commit green; **deferred** mid-probe Works Test |
| `C495ABFE` | Pro | CRS-S03 ~10m | Green |
| Host | — | Follow-up commit | `8a0e7306` completed what Pro deferred |

Log: `docs/qa/opencode-mutating-commit/OPENCODE_BUG_LOG.md`

---

## Cross-slice invariants

1. Mutating OpenCode seats **must commit** run-owned paths unless `--no-commit`
   was explicit. Delivered answer + dirty run-owned tree → `incomplete_uncommitted`
   is correct; teaching must say so up front.
2. A slice is not done until its **Works Test** is green in the same commit, or
   an explicit host follow-up commit names the gap and the reason.
3. Host may complete a deferred Works Test after Pro; that is a **product
   incident** for OMH, not a silent pass.
4. Do not raise stall timeouts to hide hung tool loops (OCH rejected list).
5. Capacity / CRS code is out of scope — this packet is OpenCode mutating
   reliability only.
6. A Pro answer that says “deferred,” “follow-up,” or “TODO” for an in-slice
   Works Test is **not** a completed slice; host must resolve it before the next
   slice is dispatched.

---

## Rejected

| Idea | Why |
| --- | --- |
| Use Pro read-only only | Founder: not good enough |
| Disable `incomplete_uncommitted` for OpenCode | Hides real uncommitted mutators |
| One mega-prompt for whole packets | Caused S04 under-ship; prefer bounded slices |
| Blame only the model | Harness + teaching + Works Test gate are ours |
| Defer an in-slice Works Test to a future slice without a named follow-up commit | Breaks invariant 2; silent deferral is the bug |
| Run unbounded multi-theme slices and hope Pro “figures it out” | Caused the 27m under-ship; S04 bounds are mandatory |

---

## OMH-S01 — Mutating commit contract + teaching

### Defect

Seats that edit and skip commit fail the run. Operators (and orchestrators) still
write “leave dirty / do not commit,” which makes OpenCode look broken.

### Fix

1. Help topic / teaching alias: mutating OpenCode → commit run-owned paths;
   `--no-commit` is the only intentional dirty exit.
2. `alln bootstrap` / menu selection copy: one line pointing at that topic.
3. Extend `OPENCODE_BUG_LOG` / harness README with the rule.

### Works Test

Unit or help-search: query `incomplete_uncommitted` + `opencode` + `commit` finds
the contract. Manual: Flash or GLM stamp harness still green.

---

## OMH-S02 — Under-ship / Works Test gate

### Defect

Pro can commit while documenting “deferred” for a packet Works Test. Host only
notices on audit.

### Fix

1. Slice prompts (Execution Playbook + this packet’s template) require: list
   Works Tests; commit must include failing→passing proof command output or
   test names.
2. Orchestrator rule (this repo’s agent workflow): if Pro answer says
   “deferred” / “follow-up” / “TODO” for an in-slice Works Test, **host completes
   before the next slice** (already practiced on CRS-S04) — promote to standing
   playbook sentence under OpenCode mutating.
3. Create `docs/qa/opencode-mutating-commit/SLICE_TEMPLATE.md` with the gate
   text to paste.

### Slice prompt gate (copy-paste)

```text
Works Tests for this slice:
1. <name>: <command or test> must pass in the same commit.
2. ...

Do not mark the slice done if a Works Test is deferred. If you must stop,
state exactly what is deferred and why; the host will complete it before the
next slice runs.
```

### Works Test

Doc + playbook sentence exists; CRS-S04 incident cited. No silent deferral in
future Pro prompts for this packet’s own slices.

---

## OMH-S04 — Bound OpenCode mutating slices

### Defect

CRS-S04 combined async refresh + backoff + Snapshot schema + cancel + many
tests in one Pro run → 27m and under-ship.

### Fix

Standing bound for OpenCode Pro mutating:

- ≤3 production files + ≤1 test file per slice, **or**
- ≤1 behavioral theme (e.g. “backoff only” separate from “mid-probe cancel”)
- ≤3 named Works Tests per slice
- Wall budget target ≤15m; if exceeded, **host aborts the current run and
  redispatches the remainder** — the seat must not keep going.

Document in this packet + one playbook bullet. No code required unless a
linter/script later enforces (out of v1).

### Works Test

Packet + playbook text. Next OMH code slice follows the bound.

---

## OMH-S03 — Tool-storm observation heartbeat

### Defect

During long Pro tool storms, `observation.lastActivityAt` updates but hosts
cannot distinguish healthy edit loops from near-stall without streaming noise.

### Fix (Allnighter observation / journal)

1. Ensure OpenCode tool activity continues to bump `lastActivityAt` (verify;
   fix if gaps > ~60s during active tools).
2. Optional: surface `observation.activityKind` / last tool name on
   `alln show --json` if not already (no new parallel schema — extend existing
   observation).
3. Help: how to read activity during long mutating OpenCode runs.

### Works Test

Focused test or live dogfood: during a multi-minute Flash/Pro tool run,
`lastActivityAt` advances at least every 60s while tools are active. If already
true, prove and close with evidence only.

---

## OMH-S05 — Multi-file mutating harness

### Defect

`TARGET.md` only proves one-file stamp+commit.

### Fix

Add `docs/qa/opencode-mutating-commit/MULTI.md` (+ tiny second file) with
instructions: edit both, run a named noop test or touch a `.swift` fixture
under `Tests/` that is harness-only, commit. Document Pro prompt.

### Works Test

Live Flash or Pro: `committed: true`, both paths in `repoDelta.files`, and the
named noop test / fixture verification passes.

---

## Suggested ship order

```text
OMH-S01 (teaching) → OMH-S02 (under-ship gate) → OMH-S04 (slice bounds)
  → OMH-S03 (heartbeat) → OMH-S05 (multi-file harness)
```

S01 and S02 change how we instruct and check Pro before any new code is
written. S04 prevents the next oversized prompt. S03 and S05 are proof and
harness work.

---

## Out of scope

- CRS capacity scheduler further polish
- Native capacity channels
- Raising stall timeouts
- Replacing OpenCode with another driver
- New OpenCode capture/session bugs — those stay in AgentOS long-run continuity
  packets unless they surface during OMH dogfood

---

## Closeout

Archive when S01–S05 ship or are waived with evidence. Promote playbook + help
sentences; leave code SSOT in `RunService` / AgentOS OpenCode modules named by
each slice.
