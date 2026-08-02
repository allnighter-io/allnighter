# GLM Worker — Best Practices

Status: **living doc** — update as we learn
Owner: Operations + agent control plane
Updated: 2026-07-20

This is the **eternal playbook** for seating GLM (OpenCode / Featherless, ~32K context)
productively in Allnighter. It captures lessons that survive any single batch or tool
version. The CR-01–CR-32 hardening queue is fully triaged and shipped, archived at
[`docs/archive/phases/code_review/`](../archive/phases/code_review/README.md); a future
review batch would recreate `docs/phases/code_review/` fresh. This doc is the *why* and
*how*, not the task list.

---

## Live path (use this)

Seat GLM as a named OpenCode worker through the CLI — not through any deleted
dispatch queue:

```bash
# Single-worker ask (chat / advisory review in the project root)
alln run --model model_opencode_glm_5_2 --json "Review <file>: what invariant breaks if X?"

# Or: confirm the worker is on the bench, then run
alln models --json          # look for model_opencode_glm_5_2
alln menu --json
```

Self-build + install if `which alln` fails:

```bash
swift build -c release --package-path Packages/AllnighterCore --product alln
alln install-cli
```

> Historical note (do **not** paste): the old slice-queue dispatch family and
> `scripts/run_cr_phase1.sh` were deleted at PM Relay R-S09. See
> [`docs/archive/phases/PM_Relay.md`](../archive/phases/PM_Relay.md) §1/§6.
> The F1–F5 lessons below are still real GLM-seating knowledge; the retired
> dispatch mechanics are not.

---

## What GLM is good for

GLM is a **cheap, patient invariant auditor** on bounded code — not an architect, not a
repo explorer, not a product owner.

| Strong fit | Weak fit |
| --- | --- |
| "What invariant breaks if X?" on inlined source | Open-ended "make this better" |
| Security / concurrency footguns in &lt;300 lines | 800+ line god files without line ranges |
| Adversarial review with required evidence (`file:line`) | Greenfield design without a contract |
| Serial hardening passes over load-bearing Core | Parallel fan-out before infra is proven |
| Surfacing hardening backlog (volume = feature) | Shipping merged code without planner triage |

**Primary output for review mode:** structured findings markdown → triage → sprint slices.
Volume of findings is **gold**, not noise — as long as each claim has evidence and survives
planner triage (or verify).

---

## Two modes (do not confuse)

| Mode | GLM writes code? | Success metric | Doc home |
| --- | --- | --- | --- |
| **Implement** (sprint / pair hammer) | Yes — allowlisted paths only | Works Test + merge | `docs/phases/sprint/` |
| **Advisory review** (hardening pass) | **No** — one findings file only | Findings + check pass | `docs/phases/code_review/` |

Same worker chair; different contract. Review never edits Swift.

---

## Eternal lessons (F1–F5)

From the deleted slice queue (`Pair_Programming_Team.md`, R-S09 — see
[`PM_Relay.md`](../archive/phases/PM_Relay.md)), adapted for GLM:

### F1 — Reads choke the window

GLM cannot grep a large repo inside 32K. **Pre-inline** the target file or line range in
the packet. Forbid tool-reads outside the inlined chunk in the prompt.

```bash
python3 scripts/expand_cr_packet.py . docs/phases/code_review/packets/CR-NN.json
```

### F2 — Compaction ≠ stall

When reviewing stall/classification code, give explicit lenses: compaction markers,
empty-output vs tool-only completion, infra backoff heuristics. Otherwise GLM (and the
classifier) conflate "still thinking" with "dead."

### F3 — Executor conforms to order

Narrow review questions. Required output schema. GLM is **faithful, not wise** — it will
defend a phantom P0 if the prompt invites one. Planner triage is mandatory.

### F4 — Pre-resolve symbols

Never hand-author `resolvedSymbols` in packet JSON. `expand_cr_packet.py` auto-generates
from inlined Swift. Phantom symbols → phantom P0s.

### F5 — Serial hardening breadth

Queue many bounded reviews **one at a time**. Triage findings into sprint docs. Do not
optimize for slice JSON turning green; optimize for **upheld findings → shipped fixes**.

---

## Serial hardening pass (default posture)

**Not** "overnight batch." A **serial investigation** over hard invariant chunks.

1. **One GLM review at a time** — seat a single `model_opencode_glm_5_2` run; do not
   fan out parallel GLM workers against the same OpenCode serve.
2. **Patient timeouts** — give the worker a long stall budget on hard reviews; GLM may
   reason a long time before writing via tools.
3. **Success = findings file + check** — if `findings/CR-NN.md` exists and the packet
   check passes, triage even when the run ends `stalled` or `failed`.
4. **Verify when triaging** — adversarial second pass; default P0 → reject unless upheld.
5. **Archive durably** — copy `findings/CR-NN.md` → `triage/CR-NN-findings.md`; promote
   P0/P1 to `docs/phases/sprint/`.

```text
# HISTORICAL — non-runnable. scripts/run_cr_phase1.sh no longer exists on disk.
# Kept only so agents do not invent a replacement paste from memory.
# Live replacement: alln run --model model_opencode_glm_5_2 … (see §Live path).
#
# PAIR_CR_PARALLEL=0 PAIR_CR_VERIFY=0 scripts/run_cr_phase1.sh Allnighter \
#   11 14 15 18 19 21 16 17 22 12 23 20 24 25 13 26 27 28 29 30 31 32
```

Monitor live runs with `alln show <run-id> --json` (or `--stream` to observe + deliver),
and inspect findings under `docs/phases/code_review/findings/`.

---

## What not to do (dogfood anti-patterns)

| Anti-pattern | Why it fails |
| --- | --- |
| Parallel fan-out by default | Single OpenCode serve (`:4096`), `maxConcurrentSpawns: 1`, SwiftPM lock — fights, not speed |
| 10-minute worker timeout on hard reviews | GLM still reasoning; parent gives up; zombie child writes findings later |
| Treating run `failed` as "no output" | Findings may land after timeout; run store showed `empty_output` + good markdown |
| Skipping triage | Phantom P0s happen (CR-01 TOCTOU rejected after verify) |
| Hand-authored symbol stubs | Phantom cross-refs in findings |
| Expecting GLM to explore | Window dies; quality drops |

Parallel is **opt-in only**; serve lifecycle hardening shipped
([`OC-S02`](../archive/phases/sprint/opencode/OC-S02-serve-lifecycle-hardening.md)).

---

## Task selection (good vs bad CR targets)

**Good:**

- Load-bearing invariants (write lock, slice gate, serve coordinator, check runner)
- Small enough to inline (&lt;300 lines, one file or one function chunk)
- Clear review lenses ("never kill compacting GLM as stalled")
- Proof nearby (existing tests to reference)

**Bad:**

- Whole god files without line-range splits
- GUI polish without stated invariant
- Areas with no contract (review becomes astrology)

---

## Findings contract (every review output)

```markdown
# CR-NN — <title>

## Summary

## Findings

### P0 — …
- **Invariant:** …
- **Evidence:** path:line
- **Suggested fix:** …
- **Suggested slice:** …

### P1 — …

## False alarms ruled out

## Greps avoided
```

### Triage rules (planner / Composer)

1. **P0** — invariant violation, security, data loss → sprint slice this week (after verify).
2. **P1** — clear win with allowlist → backlog sprint doc.
3. **P2** — nit → archive in findings only.
4. **Noise** — grepped anyway or off-scope → discard; tighten prompt.

---

## Phase 2 after sprint landings

Ship fixes **before** re-running GLM on the same surface — otherwise Phase 2 becomes
**delta review** (confirm shipped, find gaps) not greenfield discovery.

| Pattern | What to expect |
| --- | --- |
| CR-15/16/17/18/21 | May report "already fixed" or find edge cases missed in sprint |
| CR-27 | Re-review after STREAM-S02 — expect confirmation or deeper deadlock paths |
| CR-07 | Skip if triaged; WATCHDOG-S01 may overlap |
| Slices on shipped code | **Gold** = new P1s and regression risks, not duplicate backlog |

**Planner loop unchanged:** findings → verify evidence → sprint doc or reject. Volume
still matters; duplicates get archived fast.

---

## Infra dependencies (review reliability)

GLM review quality can be high while the **control plane lies**. Harden these before
re-enabling parallel or trusting status alone:

| Issue | Source | Sprint | Status |
| --- | --- | --- | --- |
| `spawnedPID` never cleared on child exit | CR-05 | OC-S02 | **shipped** |
| Undrained serve pipes / silent timeouts | CR-05 | OC-S02 | **shipped** |
| Full env → check subprocess | CR-04 | CHECK-S01 | **shipped** |
| Empty output before check (advisory) | CR-02 | CLASS-S03 | **shipped** |
| Foreign port on :4096 | CR-05 | OC-S02 | **shipped** — external `opencode serve` may block spawn |
| Tool-only completion vs empty stream | OpenCode path | CR-14 | Phase 2 |

Use a prebuilt `alln` (not `swift run` per review) to avoid SwiftPM lock contention.

---

## ROI framing

**Wrong:** "10/10 reviews passed in under an hour."

**Right:** "How many upheld findings became sprint docs and shipped fixes?"

Early hardening pass results (illustrative):

| Review | Promoted |
| --- | --- |
| CR-01 | RUNLOCK-S01, RUNLOCK-S02 |
| CR-04 | CHECK-S01, CHECK-S02 |
| CR-05 | OC-S02 |
| CR-02 | CLASS-S02, CLASS-S03 |
| CR-03 | GATE-S01 |
| CR-06 | QUEUE-S01, QUEUE-S02 |
| CR-07 | WATCHDOG-S01 |
| CR-08 | DRIVER-S01 |
| CR-09 | TIMELINE-S01 |
| CR-10 | STREAM-S01, STREAM-S02 |

Fifteen sprint work orders from Phase 1 planner triage (2026-06-28).

---

## Related docs

| Doc | Role |
| --- | --- |
| [`docs/archive/phases/code_review/README.md`](../archive/phases/code_review/README.md) | Closed queue, packets, runlog (CR-01–32, all triaged/shipped) |
| [`docs/archive/phases/code_review/phase2-hardening-queue.md`](../archive/phases/code_review/phase2-hardening-queue.md) | Phase-2 slice history (CR-07–32) |
| [`docs/archive/phases/PM_Relay.md`](../archive/phases/PM_Relay.md) | F1–F4 origin (`Pair_Programming_Team.md`, implement mode) — deleted R-S09 |
| [`docs/phases/sprint/README.md`](../phases/sprint/README.md) | Work orders from triaged findings |
| [`docs/operations/Execution-Playbook.md`](Execution-Playbook.md) | Slice closeout, commits, proof |

---

## Changelog

| Date | Learning |
| --- | --- |
| 2026-06-27 | Initial doc: serial hardening pass, findings-as-gold, F1–F5, anti-patterns from Phase 1 dogfood (CR-01–05), infra deps OC-S02/CHECK-S01 |
| 2026-06-28 | Phase 2 resumed after 15 sprint landings; post-sprint delta-review pattern; infra table marked shipped |
| 2026-07-20 | ASF-S07: lead with live `alln run --model model_opencode_glm_5_2`; fix PM_Relay archive links; fence deleted batch script; drop instructional dead verbs |
