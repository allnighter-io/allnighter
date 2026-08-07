# Phase 123 — OpenCode Long-Run & Concurrent Continuity

Status: **OPEN — F1–F10 partial; completion-truth follow-up open — do not archive**
Owner: AgentOS (`OpenCodeServeClient`, `OpenCodeSSEParser`, `OpenCodeRoutingWorkerRunner`,
`OpenCodeServeCoordinator`, `OpenCodeSpawnLock`, `DriverConcurrencyGate`) + Allnighter (`RunService`,
`observation`, outcome gates)
Created: 2026-08-07
Updated: 2026-08-07 (follow-up audit verified CT-01…03 still defeat F2/F4/reconnect)

**Follow-up (verified defects, not yet authorized to implement):**
[`OpenCode_Completion_Truth_Followup.md`](OpenCode_Completion_Truth_Followup.md)
— DeepSeek V4 Pro audit `7E8E0930` re-checked against source. Treat F2/F4/F1 as
**partial** until that packet’s CT-01…03 land.

**Successor to archived**
[`OpenCode_Headless_Completion_And_Session_Scoping.md`](../archive/phases/OpenCode_Headless_Completion_And_Session_Scoping.md)
(S122). S122 fixed **honest completion** (no prompt echo, no foreign idle as success).
This packet fixes **turn continuity** so long investigative Pro runs and concurrent
seats on one `opencode serve` actually finish.

**Related:**

- [`setup/OpenCode_CLI_Support.md`](setup/OpenCode_CLI_Support.md) — serve driver baseline
- [`One_Paste_Cold_Start.md`](One_Paste_Cold_Start.md) — cold `opencode serve` bootstrap
- Code SSOT: AgentOS `OpenCodeServeClient.swift`, `OpenCodeSSEParser.swift`;
  Allnighter `OpenCodeOutcomeAuthority.swift`, `RunService.swift`

**Durable truths graduate to:** AgentOS integration tests + Allnighter Works Test +
`alln help opencode_headless_completion` amendment. Do **not** demote DeepSeek V4 Pro
or restrict OpenCode to “shallow reads only.”

---

## If you only read one thing

S122 made failures **honest**. Continuity is still broken for real work:

1. **Concurrent seats** across separate `alln` processes hit one `:4096` serve and
   can kill / stall the first turn (`stream_drop` or silent hang).
2. **Long solo turns** with `@explore` / `task` subagents can stall indefinitely —
   child detection ignores OpenCode’s real `parentID`, and there is no stall watchdog.

Partial S123.1/S123.2 landed in AgentOS (`335d778`: SSE reconnect + HTTP poll) but a
DeepSeek V4 Pro code review found **seven** remaining defects. **Fix those first;
then dogfood.** Do not declare OpenCode “rock solid” from short constrained reads.

---

## Goal

OpenCode-backed `alln` runs — including **long read-only audits** and **concurrent
seats on one `:4096` serve** — must either:

1. Finish with a real assistant answer (≠ prompt echo), **or**
2. Fail loudly with a classified reason (`stream_drop`, `stalled_no_progress`,
   `foreign_idle`, `timeout`, `permission`, etc.) within declared wall bounds.

Never: silent hang, fake success, or “works only if you forbid subagents.”

---

## Non-Goals

- Demoting DeepSeek V4 Pro or routing audits to Flash.
- Banning `task` / subagent tools on read-only runs (workaround, not a fix).
- Replacing HTTP `serve` with cold `opencode run`.
- Generic cross-vendor job queue (S122.5 scope stays OpenCode-only).
- Live token streaming in the Mac GUI (still out of scope per OpenCode CLI Support).

---

## Evidence — live dogfood 2026-08-07

Tagged **BUILT** from `alln show <id> --json`, run artifacts under
`~/Library/Application Support/Allnighter/Runs/`, and OpenCode `GET /session`.

### A — S122 wins (baseline)

| Run | Prompt class | Outcome | `openCodeTurnSignal` |
| --- | --- | --- | --- |
| `4C84AD7C` | Short read-only audit (5 bullets, no subagents) | **completed** 16s | `local_idle`, real markdown, `toolNames: ["read"]` |
| `45AD5853` | One-line concurrent probe | **completed** 5s | `local_idle`, `OPENCODE_CONCURRENT_PROBE_OK …` |
| `5A09B582` | Solo read of this packet (post-S123.1 binary) | **completed** ~20s | real 3 bullets |

Honest failure replaces fake success on short constrained turns.

### B — Concurrent seat kills / stalls first turn

| Run | Project | Started | Outcome | Signal / notes |
| --- | --- | --- | --- | --- |
| `2E522011` | Allnighter — long audit | first | **failed** 13s | `idleReason: stream_drop`, 9× `read`, `foreignIdleDetected: false` |
| `45AD5853` | AgentOS — short probe | +2s while A running | **completed** | `local_idle` |
| `F0E196A7` | Allnighter — long (post-reconnect) | first | **stalled** 150s | 0 tools, 0 answer; killed at stall bound |
| `19D4A421` | AgentOS — short | concurrent | **completed** | `CONCURRENT_RETEST_OK` |
| `C96E2AD9` | Allnighter — earlier retest | first | **stalled** 5+ min | 0 tools after dispatch |

**BUILT:** Concurrent failure is **not** only foreign-idle. After S123.1 reconnect,
some long seats never emit tools when a second process is in flight — consistent with
Finding 5 (process-local gate) + SSE churn.

### C — Long solo turn stalls on subagents

| Run | Prompt class | Duration | Outcome |
| --- | --- | --- | --- |
| `18B2E77D` | Full 3-file audit (no subagent ban) | **9+ min** then killed | hung `alive`; `task` → explore children |

**BUILT:** Parent `ses_022f65e62…` froze; children kept updating. Explained by Findings
1–2 + 4 below.

### D — Counter-evidence (capability is there)

Short Pro audits produce concrete, useful bullets when the turn completes. Pro is not
the bottleneck — continuity is.

---

## Code review findings (DeepSeek V4 Pro / OpenCode terminal, 2026-08-07)

Reviewed against AgentOS HEAD after `335d778`. Severity from the reviewer; disposition
by implementer.

| ID | Sev | Finding | Maps to | Status |
| --- | --- | --- | --- | --- |
| **F1** | HIGH | `listActiveDelegationSessions` ignores OpenCode `parentID` | Bug C / S123.2 | **PARTIAL** — prefers `parentID` when present; capability probe still data-presence ([CT-11](OpenCode_Completion_Truth_Followup.md#ct-11--parentid-capability-probe-incomplete-medium)) |
| **F2** | HIGH | Child poll gated on SSE `task` tool name | Bug C / S123.2 | **PARTIAL** — always polls children; completion predicate still fake-success ([CT-01](OpenCode_Completion_Truth_Followup.md#ct-01--poll-fallback-declares-clean-success-mid-turn-blocker)) |
| **F3** | MED | `promptAsync` error cancels live SSE via `cancelAll` | Resilience | **FIXED** — `idleGate.signalPromptFailed`; no group throw |
| **F4** | HIGH | No stall watchdog | Bug C / S123.4 | **DEFEATED** — poll `touch()` on every HTTP GET ([CT-02](OpenCode_Completion_Truth_Followup.md#ct-02--stall-watchdog-is-effectively-dead-while-serve-answers-http-high)) |
| **F5** | HIGH | Process-local concurrency gate | Bug B / S123.0 | **PARTIAL** — flock exists; smoke/doctor bypass + proof gap ([CT-05](OpenCode_Completion_Truth_Followup.md#ct-05--doctorsmoke-can-kill-a-live-serve-outside-the-spawn-lock-high), [CT-14](OpenCode_Completion_Truth_Followup.md#ct-14--cross-process-spawn-lock-proven-only-in-process-medium--proof)) |
| **F6** | MED | Flat 100ms SSE reconnect | S123.1 polish | **PARTIAL** — backoff shipped; foreign idle aborts reconnect ([CT-03](OpenCode_Completion_Truth_Followup.md#ct-03--foreign-sessions-defeat-scoping-twice-high)) |
| **F7** | MED | Zero isolated tests for poll/parent paths | Proof | **PARTIAL** — unit tests exist; do not pin CT-01…03 |
| **F8** | LOW | Outcome authority collapses stall/`stream_drop`/etc. to `incomplete_no_final_message` | Observability | **PARTIAL** — classified reasons in tree; rewrite can still clobber permission ([CT-04](OpenCode_Completion_Truth_Followup.md#ct-04--outcome-rewrite-destroys-classified-worker-reasons-high)); Allnighter F8 may be uncommitted ([CT-15](OpenCode_Completion_Truth_Followup.md#ct-15--s123-packet-fixed-column--uncommitted-polish-low--hygiene)) |
| **F9** | LOW | Stall timer starts at IdleGate construction (burns window during session/SSE open) | F4 polish | **PARTIAL** — nil-until-touch shipped; defeated by CT-02 |
| **F10** | LOW | Spawn lock busy-polls flock every 50ms | F5 polish | **PARTIAL** — backoff in working tree; verify commit ([CT-15](OpenCode_Completion_Truth_Followup.md#ct-15--s123-packet-fixed-column--uncommitted-polish-low--hygiene)) |

AgentOS commits: `335d778` (reconnect/poll), then S123.2b–S123.4 / F1–F7 follow-up, then F8–F10.
**Works Test (constrained):** solo long + concurrent short-over-long green 2026-08-07
(`4848765D`, `1AE9FC3A`/`91474DA9`) — no `stream_drop`; short queued ~4.5s behind flock.
**Still open:** subagent/`task`-heavy long stress (class `18B2E77D`); archive after that.

### F1 detail — `parentID` ignored

`OpenCodeServeClient.listActiveDelegationSessions` takes `parentID` but only uses it
to exclude self (`id != parentID`). Children are inferred by matching `directory` +
`created >= turnStartedAt` + recent `updated`.

**BUILT (Pro curl):** OpenCode `GET /session` returns `parentID` on subagent sessions
(e.g. child `"parentID": "ses_0236027e4ffe…"`). Using it is the truth owner; the
heuristic is a false-negative/false-positive source.

### F2 detail — task-gated poll cascade

`pollSessionProgress` only calls `listActiveDelegationSessions` when
`parser.toolNames` contains `"task"`. `toolNames` is SSE-derived. If `/event` drops
before the `task` part arrives:

1. Child branch never runs.
2. Parent messages may show `task` **completed** (dispatch ok) while children still run.
3. `accumulatedAnswer` empty → poll never signals clean idle → hang until deadline.

**Fix direction:** Always query children by `parentID`. Also detect `task` from
polled parent messages (HTTP), not only SSE.

### F3 detail — task group cancel on prompt failure

```text
group.addTask { consumeSSEBus }
group.addTask {
  try await promptAsync(...)   // non-CancellationError escapes
  await pollSessionProgress(...)
} catch is CancellationError {}  // only CancellationError swallowed
try await group.next() → cancelAll()  // kills SSE even if model started
```

**Fix direction:** Catch prompt failures, emit failed terminal without cancelling a
healthy SSE consumer that already saw work — or structure so prompt failure is a
controlled `idleGate` signal, not an unstructured group throw.

### F4 detail — missing stall watchdog

`consumeSSEBus` blocks on `for try await chunk in byteStream` with no activity timer.
`pollSessionProgress` only completes when answer non-empty + tools idle. The hung
`18B2E77D` class (frozen `lastActivityAt`, owner alive) has no terminal path.

**Fix direction:** Track last SSE/poll activity; after N quiet seconds emit
`stalled_no_progress` (distinct from wall `timeout`).

### F5 detail — process-local concurrency gate

`catalog.json` sets OpenCode `maxConcurrentSpawns: 1`. Gate is
`DriverConcurrencyGate.shared` **per process**. Two `--no-wait` CLIs (or two
terminals) each see an empty gate and both call `streamRun` against one serve —
exactly the dogfood concurrent scenario.

**Fix direction (pick one, founder default A):**

| Option | Approach |
| --- | --- |
| **A (preferred)** | File lock under OpenCode serve coordinator state (or `~/Library/.../opencode.spawn.lock`) shared across processes for driver `opencode` |
| B | Document “one OpenCode seat at a time” and queue in Allnighter store (heavier) |
| C | Rely only on SSE reconnect (insufficient — F0E196A7 still stalled) |

### F6 / F7

Exponential backoff on reconnect (cap ~2–5s). Extract testable helpers for
`listActiveDelegationSessions(parentID:)`, stall timer, and poll completion
predicates; fixture-cover F1/F2/F4 without live serve.

### F8 / F9 / F10 (quality follow-up, 2026-08-07)

- **F8:** AgentOS `emitTerminal` and Allnighter `OpenCodeOutcomeAuthority` now
  surface `idleReason.rawValue` as `errorReason` for non-local ends
  (`stalled_no_progress`, `stream_drop`, `foreign_idle`, `timeout`). Prompt-echo
  and tool-only-empty still use `incomplete_no_final_message`.
- **F9:** `IdleGate.lastActivityAt` starts nil; stall quiet window begins at first
  SSE/poll `touch()`, not gate construction. Never-started turns still end on
  wall `deadline`.
- **F10:** Spawn lock keeps cancelable `LOCK_NB` (blocking `LOCK_EX` cannot honor
  timeout without stranding a waiter on the fd) but backs off 50→500ms.

---

## Additional implementer notes (post-S123.1 dogfood)

- Short concurrent probe often completes; **long** seat is the one that dies or never
  starts tools — measure both.
- Dogfood scripts must **not** block on `alln show --stream` for the full
  `--idle-timeout`. Poll `show --json` every ~10s; kill if no event progress for 120s.
- Expected healthy timings: short probe 5–15s; constrained short audit 15–30s;
  long audit 2–10+ min when healthy; stall kill at 120s quiet.
- Solo constrained audit works after reconnect (`5A09B582`) — proves S123.1 helps
  the happy path, not concurrency/subagent.

---

## Symptom → truth owner map

| Symptom | Likely lie layer | Truth owner | Finding |
| --- | --- | --- | --- |
| First run `stream_drop` / stall when second `--no-wait` starts | Cross-process spawn + SSE | `DriverConcurrencyGate` + `OpenCodeServeClient` | F5, F6 |
| Hang with `task` / explore children | Child detection | `listActiveDelegationSessions` + poll | F1, F2 |
| `alive` + frozen `lastActivityAt` for minutes | Missing stall terminal | `consumeSSEBus` / poll watchdog | F4 |
| Prompt network fail cancels mid-flight SSE | Task group structure | `streamRun` task group | F3 |
| Child progress invisible on `alln show` | Observation | Allnighter journal mapper | S123.3 |

---

## Proposed slices (revised)

**Order: fix F1–F4 + F6 + F7 tests, then F5, then dogfood. No more open-ended live
waits until unit fixtures are green.**

| Slice | Scope | Exit |
| --- | --- | --- |
| **S123.1b** | Exponential SSE reconnect backoff (F6); keep reconnect loop | Fixture: many drops don’t spin at 10 Hz; still reaches local idle |
| **S123.2b** | Match children by `parentID` (F1); always poll children (F2); detect `task` from HTTP messages too | Unit tests with canned session list + messages; hang class fails closed or completes |
| **S123.4** | Stall watchdog: no SSE/poll progress for N seconds → `stalled_no_progress` (F4) | Fixture: quiet bus → failed with that reason before wall |
| **S123.1c** | `promptAsync` failure must not `cancelAll` a productive SSE consumer (F3) | Fixture: prompt error after tools seen → controlled failure signal |
| **S123.0** | Cross-process OpenCode spawn lock (F5 option A) | Two `--no-wait` processes: second waits or refuses loudly; first completes |
| **S123.3** | `observation.lastActivityAt` includes child-session activity | `alln show` advances during explore |
| **S123.5** | Works Test + help topic | Owner dogfood script with 120s stall kill |

**Optional spike:** per-session event subscription if OpenCode exposes it (prefer over
global `/event` filter alone).

---

## Works Test (owner-visible)

```text
Prereq: opencode serve on :4096; alln menu --json once.
Policy: poll show --json; never block on --stream for full idle-timeout.
Stall kill: no new events for 120s → kill and record failed.

1. LONG SOLO (may use task/subagents)
   alln run --model model_opencode_deepseek_v4_pro --read-only --no-wait \
     --idle-timeout 600 \
     "Read docs/archive/phases/OpenCode_Headless_Completion_And_Session_Scoping.md
      and AGENTS.md OpenCode rows; write 5 numbered hard bullets."
   → Complete with real bullets OR fail ≤600s with classified reason
     (incl. stalled_no_progress). Never silent alive >120s quiet.

2. CONCURRENT (two processes)
   Start (1); wait until ≥1 worker.tool; start short Pro --no-wait on other project.
   → First must NOT die at ~13s with only reads / stream_drop.
   → Second may complete.
   → After F5: second should queue or refuse, not corrupt first.

3. alln show <id> --json → never prompt echo; errors empty only if answer real.
```

Mutator companion (from S122): one-line create+commit; dirty-no-commit ⇒
`incomplete_uncommitted`.

---

## Open questions

1. Preferred F5 mechanism: file lock next to serve coordinator, or Allnighter store?
   **Default A:** file lock in AgentOS OpenCode coordinator.
2. Stall threshold default: 120s quiet? (Must be < typical idle-timeout.)
3. Does OpenCode expose per-session `/event`? Spike after F1–F4 land.

---

## Closeout

- [ ] F1–F4, F6, F7 green in AgentOS tests
- [ ] F5 cross-process gate (or explicit refuse) shipped
- [ ] Owner-visible Works Test passes (Pro, concurrent + long) with stall kill
- [ ] Help topic amended
- [ ] Archive this packet; link from `OpenCode_CLI_Support.md`
