# Code Review — Follow-Up & Recommendations Log

Status: **living log** — update on every triage
Owner: Serial hardening pass
Updated: 2026-06-29

Master tracker for every upheld finding, sprint promotion, backlog item, and Phase 2
review slice. **Nothing closes here until shipped or explicitly rejected.**

Playbook: [`docs/operations/GLM_Worker_Best_Practices.md`](../../operations/GLM_Worker_Best_Practices.md)

Planner triage: [`planner-triage-verdict.md`](planner-triage-verdict.md) · [`planner-triage-verdict-phase2.md`](planner-triage-verdict-phase2.md)

---

## Promoted to sprint (implement)

| ID | Finding | Sprint doc | Status |
| --- | --- | --- | --- |
| CR-01 P1 | Owner-token `release` — stray/double release → two writers | [`RUNLOCK-S01`](../sprint/runlock/RUNLOCK-S01-owner-token-release.md) | ready |
| CR-01 P1 | Symlink/case canonical repo key | [`RUNLOCK-S02`](../sprint/runlock/RUNLOCK-S02-canonical-key-symlinks.md) | ready |
| CR-04 P0 | Full parent env → `/bin/sh -c` check (secret exfiltration) | [`CHECK-S01`](../sprint/checkrunner/CHECK-S01-minimal-subprocess-env.md) | ready |
| CR-05 P0/P1 | Serve child exit, pipes, port ownership, spawn errors | [`OC-S02`](../sprint/opencode/OC-S02-serve-lifecycle-hardening.md) | ready |
| CR-02 P1 | `isInfraBackoff` on `.done` workers | [`CLASS-S02`](../sprint/classifier/CLASS-S02-infra-backoff-ordering.md) | ready |
| CR-02 P1 | Empty output → `.stalled` before check | [`CLASS-S03`](../sprint/classifier/CLASS-S03-advisory-check-before-empty.md) | ready |
| CR-03 P1 | Allowlist content + check.method validation | [`GATE-S01`](../sprint/slicegate/GATE-S01-allowlist-content.md) | ready |
| CR-04 P1 | Skipped check `exitCode: 0` | [`CHECK-S02`](../sprint/checkrunner/CHECK-S02-skipped-exitcode.md) | ready |
| CR-06 P1 | Compaction/infraBackoff retry caps | [`QUEUE-S01`](../sprint/queue/QUEUE-S01-compaction-backoff-caps.md) | ready |
| CR-06 P1 | `options.until` mid-slice | [`QUEUE-S02`](../sprint/queue/QUEUE-S02-mid-slice-deadline.md) | ready |
| CR-08 P1 | Gate cancel + acquire timeout | [`DRIVER-S01`](../sprint/spawn/DRIVER-S01-gate-cancel-timeout.md) | ready |
| CR-09 P1 | Timeline read-clear perf (S01–S03 merged) | [`TIMELINE-S01`](../sprint/timeline/TIMELINE-S01-readclear-perf.md) | ready |
| CR-10 P1 | `newestSuffix` O(n) | [`STREAM-S01`](../sprint/stream/STREAM-S01-newest-suffix-on.md) | ready |
| CR-10 P1 | Serializer reentrancy | [`STREAM-S02`](../sprint/stream/STREAM-S02-serializer-reentrant.md) | ready |
| CR-07 P1 | Slow GLM stall threshold | [`WATCHDOG-S01`](../sprint/watchdog/WATCHDOG-S01-slow-glm-threshold.md) | ready |
| CR-15 P1 | `reviewVerify` silent pass on empty output | [`CLASS-S04`](../sprint/classifier/CLASS-S04-reviewverify-requires-signal.md) | ready |
| CR-20 P1 | Subprocess watchdog not cancelled on exit | [`SUBPROCESS-S03`](../sprint/subprocess/SUBPROCESS-S03-cancel-watchdog.md) | ready |
| CR-24 P1 | Stdin `write` NSException on EPIPE | [`SUBPROCESS-S04`](../sprint/subprocess/SUBPROCESS-S04-stdin-throwing-write.md) | done |
| CR-31+32 | Double-close listen FD in `stop()` | [`LOOPBACK-S01`](../sprint/loopback/LOOPBACK-S01-single-close-stop.md) | done |
| CR-23 P1 | Pending stuck when transcript write fails | [`PENDING-S01`](../sprint/pending/PENDING-S01-settle-before-transcript.md) | ready |

Planner triage: [`planner-triage-verdict.md`](planner-triage-verdict.md) · [`planner-triage-verdict-phase2.md`](planner-triage-verdict-phase2.md)

---

## Backlog — defer (not sprinted yet)

| Source | Priority | Finding | Sprint ID | Defer reason |
| --- | --- | --- | --- | --- |
| CR-01 | P1 | Holder crash without `release` leaks key | RUNLOCK-S03 | Needs process watchdog / TTL design |
| CR-02 | P0/P1 | Structured compaction marker | CLASS-S01 | CLI contract; optional CR-11/14 GLM |
| CR-04 | P1 | Nil exitCode spawn failure silent | CHECK-S03 | Needs CommandRunner (CR-20) |
| CR-04 | P0 | `check.command` provenance | CHECK-S04 | Policy/doc slice |
| CR-06 | P1 | No `Task` cancellation in `runQueue` | QUEUE-S03 | Bundle after QUEUE-S02 |
| CR-06 | P1 | Gate-blocked escalation metadata | QUEUE-S04 | Lower priority polish |
| CR-08 | P1 | `withPermit` slot leak if `body` throws | DRIVER-S02 | `body` non-throwing today |
| CR-09 | P1 | Team-run turn kinds read-clear | TIMELINE-S04 | Needs ThreadTurn.Kind (CR-26) |
| CR-25 | P1 | Prompt fence escape in nudge/takeover | PAIR-S02 | Defense in depth; SliceGate + check enforce CR |
| CR-13 | P1 | ThreadsViewModel reload coalescing | GUI-S01 | Forward Mac GUI perf |
| CR-22 | P1 | OpenCode reasoning buffer / serve start timeout | OC-S03 | After OC-S02 + CR-14 |
| CR-20 | P1 | Pipe drain race before snapshot | SUBPROCESS-S05 | After SUBPROCESS-S03 |
| CR-24 | P1 | `setpgid` race / orphan tree | SUBPROCESS-S06 | posix_spawn scope |
| CR-27 | P1 | ThreadStore symlink root keys | RUNLOCK-S02 ext | When thread writes hot |
| CR-29–30 | P1 | Remote snapshot ordering / resident PID probe | IOS-S01 / RESIDENT-S01 | Forward surfaces |
| CR-14 | — | OpenCode stream echo / no findings | OC-S04 | Dogfood; split packet |
| CR-21 | — | Driver gate liveness re-review | CR-21 retry | GLM flaky |

---

## Rejected / archived (do not implement)

| Source | Claim | Verdict |
| --- | --- | --- |
| CR-01 | P0 TOCTOU waiter registration | **Rejected** — false alarm (actor serialization) |
| CR-03 | P0 scope bypass | **Rejected** — gate fail-closed on verified paths |
| CR-06 | P0 invariant violation | **Rejected** — bounded paths hold; liveness issues are P1 |
| CR-08 | P0 gate handoff broken | **Rejected** — slot transfer correct |
| CR-10 | P0 | **Rejected** — no security invariant violation in inlined source |
| CR-16 | P1 unbounded compaction in snippet | **Rejected** — wrong inlined lines; QUEUE-S01 |
| CR-17 | P1 deadline only in compaction | **Rejected** — `isPastDeadline` at loop top |
| CR-22 | P0 spawn gate leak on success | **Rejected** — release at RunService:628 |
| CR-11 | P1 fire-and-forget gate release | **Rejected** — `finish()` awaits release |
| CR-12 | P1 mutating vs writePolicy | **Rejected** — computed property |
| CR-23 | P1 team vs resolved mutating | **Rejected** — same field via TeamResolver |

---

## Phase 2 review slices (GLM serial pass)

Status: **20/22 findings archived** — see [`planner-triage-verdict-phase2.md`](planner-triage-verdict-phase2.md).

| Order | ID | Target | Review | Triage |
| --- | --- | --- | --- | --- |
| 1 | CR-07 | StalledWorkDetector | **triaged** | [CR-07-findings.md](triage/CR-07-findings.md) |
| 2 | CR-11 | WorkerRunner OpenCode | **triaged** | [CR-11-findings.md](triage/CR-11-findings.md) — defer polish |
| 3 | CR-14 | OpenCodeServeClient | **blocked** | no findings — re-run |
| 4 | CR-15 | Classifier + advisory | **triaged** | → CLASS-S04 |
| 5 | CR-18 | SliceGate content | **triaged** | GATE-S01 covers |
| 6 | CR-19 | CheckResult consumers | **triaged** | CHECK-S02 covers |
| 7 | CR-21 | DriverConcurrencyGate | **blocked** | no findings — re-run |
| 8 | CR-16 | runQueue compaction | **triaged** | QUEUE-S01 covers |
| 9 | CR-17 | runQueue deadline | **triaged** | QUEUE-S02 covers |
| 10 | CR-22 | RunService OpenCode | **triaged** | defer / reject leak |
| 11 | CR-12 | RunService write lock | **triaged** | defer |
| 12 | CR-23 | PendingRunExecutor | **triaged** | → PENDING-S01 |
| 13 | CR-20 | Subprocess lifecycle | **triaged** | → SUBPROCESS-S03 |
| 14 | CR-24 | Subprocess resolution | **triaged** | → SUBPROCESS-S04 |
| 15 | CR-25 | Nudge / planner prompts | **triaged** | defer PAIR-S02 |
| 16 | CR-13 | ThreadsViewModel | **triaged** | defer GUI |
| 17 | CR-26 | Timeline + ThreadTurn | **triaged** | TIMELINE-S04 |
| 18 | CR-27 | ThreadStore serializer | **triaged** | defer |
| 19 | CR-28 | ThreadView scroll | **triaged** | defer |
| 20 | CR-29 | RemoteSnapshotPublisher | **triaged** | defer iOS |
| 21 | CR-30 | ResidentCoordinatorProbe | **triaged** | defer |
| 22 | CR-31 | DirectModeCommandServer | **triaged** | → LOOPBACK-S01 |
| 23 | CR-32 | LoopbackHealthServer | **triaged** | → LOOPBACK-S01 |

---

## Phase 1 triage archive index

| ID | Archive | Sprint / follow-up |
| --- | --- | --- |
| CR-01 | [`triage/CR-01-findings.md`](triage/CR-01-findings.md) | RUNLOCK-S01/S02 |
| CR-02 | [`triage/CR-02-findings.md`](triage/CR-02-findings.md) | CLASS-S01–S03, CR-15 |
| CR-03 | [`triage/CR-03-findings.md`](triage/CR-03-findings.md) | GATE-S01/S02, CR-18 |
| CR-04 | [`triage/CR-04-findings.md`](triage/CR-04-findings.md) | CHECK-S01–S04, CR-19/20 |
| CR-05 | [`triage/CR-05-findings.md`](triage/CR-05-findings.md) | OC-S02 |
| CR-06 | [`triage/CR-06-findings.md`](triage/CR-06-findings.md) | QUEUE-S01–S04, CR-16/17 |
| CR-07 | [`triage/CR-07-findings.md`](triage/CR-07-findings.md) | WATCHDOG-S01 |
| CR-08 | [`triage/CR-08-findings.md`](triage/CR-08-findings.md) | GATE-S03–S05, CR-21 |
| CR-09 | [`triage/CR-09-findings.md`](triage/CR-09-findings.md) | TIMELINE-S01–S04, CR-26/28 |
| CR-10 | [`triage/CR-10-findings.md`](triage/CR-10-findings.md) | STREAM-S01/S02, CR-27 |

## Phase 2 triage archive index

| ID | Archive | Sprint / outcome |
| --- | --- | --- |
| CR-11 | [`triage/CR-11-findings.md`](triage/CR-11-findings.md) | defer polish |
| CR-12 | [`triage/CR-12-findings.md`](triage/CR-12-findings.md) | defer |
| CR-13 | [`triage/CR-13-findings.md`](triage/CR-13-findings.md) | defer GUI |
| CR-15 | [`triage/CR-15-findings.md`](triage/CR-15-findings.md) | CLASS-S04 |
| CR-16 | [`triage/CR-16-findings.md`](triage/CR-16-findings.md) | QUEUE-S01 (reject duplicate) |
| CR-17 | [`triage/CR-17-findings.md`](triage/CR-17-findings.md) | QUEUE-S02 (reject duplicate) |
| CR-18 | [`triage/CR-18-findings.md`](triage/CR-18-findings.md) | GATE-S01 |
| CR-19 | [`triage/CR-19-findings.md`](triage/CR-19-findings.md) | CHECK-S02 |
| CR-20 | [`triage/CR-20-findings.md`](triage/CR-20-findings.md) | SUBPROCESS-S03 |
| CR-22 | [`triage/CR-22-findings.md`](triage/CR-22-findings.md) | defer |
| CR-23 | [`triage/CR-23-findings.md`](triage/CR-23-findings.md) | PENDING-S01 |
| CR-24 | [`triage/CR-24-findings.md`](triage/CR-24-findings.md) | SUBPROCESS-S04 |
| CR-25 | [`triage/CR-25-findings.md`](triage/CR-25-findings.md) | defer PAIR-S02 |
| CR-26 | [`triage/CR-26-findings.md`](triage/CR-26-findings.md) | TIMELINE-S04 |
| CR-27 | [`triage/CR-27-findings.md`](triage/CR-27-findings.md) | defer |
| CR-28 | [`triage/CR-28-findings.md`](triage/CR-28-findings.md) | defer |
| CR-29 | [`triage/CR-29-findings.md`](triage/CR-29-findings.md) | defer iOS |
| CR-30 | [`triage/CR-30-findings.md`](triage/CR-30-findings.md) | defer |
| CR-31 | [`triage/CR-31-findings.md`](triage/CR-31-findings.md) | LOOPBACK-S01 |
| CR-32 | [`triage/CR-32-findings.md`](triage/CR-32-findings.md) | LOOPBACK-S01 |

---

## Verify pass backlog (optional adversarial second pass)

| ID | Review archived | Verify run |
| --- | --- | --- |
| CR-02 | yes | pending |
| CR-03 | yes | pending |
| CR-04 | yes | partial (`CR-04-verified.md` exists locally) |
| CR-05 | yes | partial |
| CR-06–10 | yes | pending |
| CR-11–32 | archived | triaged 2026-06-29 |
| Infra | `workerTimeoutSeconds` + opencode serve teardown | shipped locally (uncommitted) |

---

## Infra / dogfood (not GLM findings — engineering)

| Issue | Owner | Tracked in |
| --- | --- | --- |
| OpenCode stream 0 events / `empty_output` | OC-S02 + CR-14 | phase2-runlog |
| Zombie worker writes after parent timeout | CR-15 + worker layer | follow-up |
| Parallel batch script typo (`erify_exp`) | `run_cr_phase1.sh` parallel path | fix when parallel re-enabled |
| `swift run` SwiftPM lock | prebuilt `alln` in script | done (default) |

---

## Changelog

| Date | Change |
| --- | --- |
| 2026-06-27 | Initial log: Phase 1 triage → sprint/backlog; Phase 2 slices CR-07,11–32 specced |
| 2026-06-28 | Planner triage: 11 backlog items → sprint docs; 8 deferred |
| 2026-06-29 | **Phase 2 planner triage** — 20 findings archived; **5 new sprints** (CLASS-S04, SUBPROCESS-S03/S04, LOOPBACK-S01, PENDING-S01); 12 rejects; see [`planner-triage-verdict-phase2.md`](planner-triage-verdict-phase2.md) |
