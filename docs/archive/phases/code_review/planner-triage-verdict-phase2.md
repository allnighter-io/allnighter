# Planner Triage Verdict — Phase 2 (CR-11–32)

Status: **complete**
Reviewer: Composer (planner) — source spot-checks against repo
Updated: 2026-06-29

Principle: GLM reviewed **inlined snippets** without full codebase context.
Promote only claims **verified in source** that fix real invariants or crash/leak
paths. Reject phantom P0s, duplicate Phase 1 sprint items, and policy nits.

---

## Verdict summary

| Verdict | Count | Meaning |
| --- | --- | --- |
| **Promote (new sprint)** | 5 | New work orders authored |
| **Already sprint / shipped** | 8 | Phase 1 sprint or local fix covers it |
| **Confirmed (no new sprint)** | 4 | GLM correct; fold into existing doc or accept risk |
| **Defer backlog** | 18 | Real but lower priority / forward surface / needs design |
| **Reject** | 12 | Phantom, wrong snippet, or contradicted by source |

---

## Promoted to sprint (new work orders)

| Source | Finding | Why upheld | Sprint |
| --- | --- | --- | --- |
| CR-15 | `reviewVerify` + empty visible → `.passed` | Verified: `SliceTerminalClassifier` treats all advisory modes alike; verify must emit signal | [`CLASS-S04`](../sprint/classifier/CLASS-S04-reviewverify-requires-signal.md) |
| CR-20 | Timeout watchdog `Task` never cancelled | Verified: `SubprocessCommandRunner.swift:131-137` fire-and-forget sleep | [`SUBPROCESS-S03`](../sprint/subprocess/SUBPROCESS-S03-cancel-watchdog.md) |
| CR-24 | Deprecated stdin `write` → NSException on EPIPE | Verified: `SubprocessCommandRunner.swift:302` | [`SUBPROCESS-S04`](../sprint/subprocess/SUBPROCESS-S04-stdin-throwing-write.md) |
| CR-31 + CR-32 | Double `close(listenFD)` in `stop()` | Verified: both servers cancel handler + explicit close | [`LOOPBACK-S01`](../sprint/loopback/LOOPBACK-S01-single-close-stop.md) |
| CR-23 | Transcript `try` after worker → stuck Pending | Verified: `PendingRunExecutor.swift:76-77` vs team path `try?` | [`PENDING-S01`](../sprint/pending/PENDING-S01-settle-before-transcript.md) |

---

## Already sprint / shipped (no new work order)

| Source | GLM claim | Planner verdict |
| --- | --- | --- |
| CR-16 | Unbounded compaction retries | **Reject** — wrong inlined lines; `PairCoordinator` has `maxCompactionRetries` + `compactionRetries` cap (`QUEUE-S01` ready) |
| CR-17 | Deadline only in compaction branch | **Reject** — `isPastDeadline` at loop top `:232` and inner `:253` (`QUEUE-S02` ready) |
| CR-18 | `[""]` allowlist passes | **Shipped** — `GATE-S01` ready; mixed-list normalize is polish only |
| CR-19 | Skipped + exitCode 0 false pass | **Shipped** — `CheckRunner` returns `.init(skipped: true)` with `exitCode: nil` (`CHECK-S02` done) |
| CR-02/15 | Check before empty-output stall | **Shipped** — `SliceTerminalClassifier` checks check before empty visible (`CLASS-S03` done) |
| CR-22 | OpenCode spawn gate leak on success | **Reject** — `RunService.swift:628` releases when `gateHeld` |
| CR-11 | Fire-and-forget gate release in `runOpenCode` | **Reject** — `finish()` awaits release on every path (`WorkerRunner.swift:272-274`) |
| CR-12 | `mutating` vs `writePolicy` divergence | **Reject** — `writePolicy` is computed from `mutating` (`RunShape.swift:19`) |
| Infra | 600s timeout / serve teardown | **Shipped (local)** — `RunRequest.workerTimeoutSeconds` + worker-driver `usesOpenCodeServe` (uncommitted) |

---

## Confirmed — no new sprint (document only)

| Source | Finding | Notes |
| --- | --- | --- |
| CR-15 | Non-advisory `.done` + green check + empty visible → `.stalled` | Theoretically hurts file-only workers; pair slices use executable check as truth. **Defer** unless mutating pair slices hit this. |
| CR-25 | Fence escape in nudge/takeover tails | Real prompt-injection shape; allowlist enforced by packet + check for CR. **Defer** `PAIR-S02` unless prompt is sole enforcement for mutating pair. |
| CR-20 | Pipe drain race before snapshot | Plausible; bundle after SUBPROCESS-S03. |
| CR-05/22 | `ensureRunning` / error classification | Partially in `OC-S02`; do not duplicate until serve path stable (CR-14 blocked). |

---

## Defer backlog (real, not sprinted now)

| Source | Priority | Finding | Defer reason |
| --- | --- | --- | --- |
| CR-11 | P1/P2 | Stream error kinds, dead `NSTemporaryDirectory`, durationMs parity | Polish; not invariant |
| CR-12 | P1 | Root TOCTOU before lock | Theoretical; single-user Mac; RUNLOCK path already queued |
| CR-12 | P1 | lockWaitTimeout vs workerTimeout assertion | Nice test; not blocking |
| CR-18 | P1 | `.userObservation` on mutating slices | Product policy; no current mutating pair packets use it |
| CR-18 | P1 | Mixed empty strings in allowlist | Hand-authored CR packets; GATE-S01 covers single empty |
| CR-19 | P1 | Tri-state `CheckResult` enum | Refactor; skipped path fixed at source |
| CR-20 | P1 | Pipe drain before snapshot | After SUBPROCESS-S03 |
| CR-24 | P1 | `setpgid` race / orphan grandchildren | Large change (`posix_spawn`); defer |
| CR-22 | P1 | Unbounded reasoning buffer, `ensureRunning` timeout | After OC-S02 + CR-14 dogfood |
| CR-23 | P1 | `team.mutating` vs `resolved.mutating` | **Reject** — `TeamResolver` copies `team.mutating` |
| CR-23 | P1 | Per-id double dispatch | Needs actor design; low traffic today |
| CR-23 | P1 | Disabled models in workerChat | Defer parity polish |
| CR-25 | P1 | Empty allowlist section in planner takeover | Edge case; empty allowlist packets invalid at gate |
| CR-13 | P1 | ThreadsViewModel railRows / MainActor / checkpoint | Forward GUI; not GLM-pass blocker |
| CR-26 | P1 | Exhaustive `countsTowardReadClear` | Already `TIMELINE-S04` backlog |
| CR-27 | P1 | ThreadStore symlink keys | Extend `RUNLOCK-S02` pattern when threading hot |
| CR-28–32 | P2 | Scroll nits, remote mirror, resident probe | Forward / iOS / background coordinator surfaces |
| CR-29 | P1 | Snapshot publish ordering | iOS companion; single-writer assumption OK for now |
| CR-30 | P0→P1 | PID reuse in resident probe | Edge case; defer until resident mode ships |
| CR-31 | P1 | `listenFD` read race, connection cap | After LOOPBACK-S01; add tests |
| CR-14 | — | OpenCode stream echo / no findings | Dogfood blocked; needs packet split or OC path fix |
| CR-21 | — | Driver gate liveness | Flaky GLM; re-run after infra commit |

---

## Rejected (do not implement)

| Source | Claim | Verdict |
| --- | --- | --- |
| CR-16 | Queue hang / no retry bound in snippet | Wrong scope — snippet was escalation path only |
| CR-17 | No deadline at loop top | False — lines 232, 253 |
| CR-22 P0 | Gate leak on streaming success | False — line 628 releases |
| CR-11 P1 | Gate leak via defer Task | False — `finish()` awaits release |
| CR-12 P1 | Dual mutating/writePolicy | False — computed property |
| CR-23 P1 | Mutation guard bypass | False — same field through resolver |
| CR-30 P0 | PID reuse = fake liveness (as hot fix) | Downgraded defer — rare; not worker-faking |
| CR-25 P0 | Fence escape as P0 | Downgraded defer — defense in depth; hard gate exists for CR |

---

## Phase 2 archive index

| ID | Archive | Triage outcome |
| --- | --- | --- |
| CR-11 | [`triage/CR-11-findings.md`](triage/CR-11-findings.md) | Reject / defer polish |
| CR-12 | [`triage/CR-12-findings.md`](triage/CR-12-findings.md) | Reject / defer |
| CR-13 | [`triage/CR-13-findings.md`](triage/CR-13-findings.md) | Defer GUI |
| CR-15 | [`triage/CR-15-findings.md`](triage/CR-15-findings.md) | **CLASS-S04** |
| CR-16 | [`triage/CR-16-findings.md`](triage/CR-16-findings.md) | Reject (QUEUE-S01) |
| CR-17 | [`triage/CR-17-findings.md`](triage/CR-17-findings.md) | Reject (QUEUE-S02) |
| CR-18 | [`triage/CR-18-findings.md`](triage/CR-18-findings.md) | GATE-S01 shipped |
| CR-19 | [`triage/CR-19-findings.md`](triage/CR-19-findings.md) | CHECK-S02 shipped |
| CR-20 | [`triage/CR-20-findings.md`](triage/CR-20-findings.md) | **SUBPROCESS-S03** |
| CR-22 | [`triage/CR-22-findings.md`](triage/CR-22-findings.md) | Reject leak / defer |
| CR-23 | [`triage/CR-23-findings.md`](triage/CR-23-findings.md) | **PENDING-S01** |
| CR-24 | [`triage/CR-24-findings.md`](triage/CR-24-findings.md) | **SUBPROCESS-S04** |
| CR-25 | [`triage/CR-25-findings.md`](triage/CR-25-findings.md) | Defer prompt hardening |
| CR-26 | [`triage/CR-26-findings.md`](triage/CR-26-findings.md) | TIMELINE-S04 backlog |
| CR-27 | [`triage/CR-27-findings.md`](triage/CR-27-findings.md) | Defer / RUNLOCK pattern |
| CR-28 | [`triage/CR-28-findings.md`](triage/CR-28-findings.md) | Defer GUI |
| CR-29 | [`triage/CR-29-findings.md`](triage/CR-29-findings.md) | Defer iOS |
| CR-30 | [`triage/CR-30-findings.md`](triage/CR-30-findings.md) | Defer resident |
| CR-31 | [`triage/CR-31-findings.md`](triage/CR-31-findings.md) | **LOOPBACK-S01** |
| CR-32 | [`triage/CR-32-findings.md`](triage/CR-32-findings.md) | **LOOPBACK-S01** |

CR-14, CR-21: no findings file — triage pending re-run.

---

## Recommended sprint order (hot fix first)

1. **LOOPBACK-S01** — FD table corruption risk (small, verified)
2. **SUBPROCESS-S04** — host crash on EPIPE (small)
3. **SUBPROCESS-S03** — leak under long timeouts
4. **PENDING-S01** — stuck Pending items
5. **CLASS-S04** — only when `PAIR_CR_VERIFY=1` is used

Then continue Phase 1 queue: RUNLOCK, CHECK, OC-S02, CLASS-S02, QUEUE, etc.
