# Phase 123 — OpenCode Long-Run & Concurrent Continuity

Status: **OPEN — dogfood gaps after S122; investigation authorized**
Owner: AgentOS (`OpenCodeServeClient`, `OpenCodeSSEParser`, `OpenCodeRoutingWorkerRunner`,
`OpenCodeServeCoordinator`) + Allnighter (`RunService`, `observation`, outcome gates)
Created: 2026-08-07
Updated: 2026-08-07 (post-S122 live dogfood)

**Successor to archived**
[`OpenCode_Headless_Completion_And_Session_Scoping.md`](../archive/phases/OpenCode_Headless_Completion_And_Session_Scoping.md)
(S122). S122 fixed **honest completion** (no prompt echo, no foreign idle as success).
This packet fixes **turn continuity** so long investigative Pro runs and concurrent
seats on one `opencode serve` actually finish.

**Related:**

- [`setup/OpenCode_CLI_Support.md`](setup/OpenCode_CLI_Support.md) — serve driver baseline
- [`One_Paste_Cold_Start.md`](One_Paste_Cold_Start.md) — cold `opencode serve` bootstrap (gap called out below)
- Code SSOT: AgentOS `OpenCodeServeClient.swift`, `OpenCodeSSEParser.swift`;
  Allnighter `OpenCodeOutcomeAuthority.swift`, `RunService.swift`

**Durable truths graduate to:** AgentOS integration tests + Allnighter Works Test +
`alln help opencode_headless_completion` amendment. Do **not** demote DeepSeek V4 Pro
or restrict OpenCode to “shallow reads only.”

---

## If you only read one thing

S122 made failures **honest**. Dogfood on 2026-08-07 shows two **remaining**
failure modes that block real work:

1. **Concurrent seats** — starting a second OpenCode run can **kill the first turn**
   via `stream_drop` (not the old prompt-echo bug).
2. **Long solo turns** — Pro investigative audits that spawn `@explore` / `task`
   subagents can **stall open indefinitely** while child sessions still run.

Short constrained reads **do** complete (`local_idle`, real answer). That is not an
acceptable product ceiling.

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
- Banning `task` / subagent tools on read-only runs (that is a workaround, not a fix).
- Replacing HTTP `serve` with cold `opencode run`.
- Generic cross-vendor job queue (S122.5 scope stays OpenCode-only).
- Live token streaming in the Mac GUI (still out of scope per OpenCode CLI Support).

---

## Evidence — live dogfood 2026-08-07

Tagged **BUILT** from `alln show <id> --json`, run artifacts under
`~/Library/Application Support/Allnighter/Runs/`, and OpenCode `GET /session`.
Binary: `/tmp/alln-dogfood/alln` built from Allnighter `2847480` + AgentOS S122
(`a0f7f55`…`810ce40`). Serve: `opencode serve --port 4096` healthy.

### A — S122 wins (baseline)

| Run | Prompt class | Outcome | `openCodeTurnSignal` |
| --- | --- | --- | --- |
| `4C84AD7C` | Short read-only audit (5 bullets, no subagents) | **completed** 16s | `local_idle`, real markdown, `toolNames: ["read"]` |
| `45AD5853` | One-line concurrent probe | **completed** 5s | `local_idle`, `OPENCODE_CONCURRENT_PROBE_OK …` |

Honest failure replaces fake success: no prompt echo observed on any run.

### B — Concurrent seat kills first turn (`stream_drop`)

| Run | Project | Started | Outcome | Signal |
| --- | --- | --- | --- | --- |
| `2E522011` | Allnighter — long audit | first | **failed** 13s | `idleReason: stream_drop`, `foreignIdleDetected: false`, `toolNames: ["read"]` (9× read) |
| `45AD5853` | AgentOS — short probe | +2s while A running | **completed** | `local_idle` |

**BUILT:** Run A failed `incomplete_no_final_message` when B started — **not**
prompt echo. Error class is **`stream_drop`**, not `foreign_idle`. S122.0 scoped
foreign idle correctly; the SSE consumer still **lost the turn** when a second
session opened on the same serve.

**Hypothesis (investigate first):** shared `GET /event` byte stream ends or the
task-group consumer exits without `session.idle` for the scoped session when another
client/session starts — distinct from the pre-S122 “foreign idle = done” bug.

### C — Long solo turn stalls on subagents (open hang)

| Run | Prompt class | Duration observed | Outcome |
| --- | --- | --- | --- |
| `18B2E77D` | Full 3-file audit (no subagent ban) | **9+ min** then killed | **failed** after kill; was `running` / `ownerState: alive` |

**BUILT timeline:**

- `16:23:49`–`16:26:06Z` — parent session `ses_022f65e62…` (“Post-S122 OpenCode
  headless audit”): 9× `read`, then 7× `task`.
- `alln` `lastActivityAt` froze at `16:26:06Z`; answer stuck at 49 chars
  (“Let me verify the actual code against these docs.”).
- OpenCode spawned child sessions on same repo:
  - `ses_022f6155…` “Check test files for OpenCode (@explore subagent)”
  - `ses_022f61bf…` “Find OpenCode source files (@explore subagent)”
- Child sessions showed **later** `time.updated` than parent; parent session
  **stopped updating** ~8+ minutes before kill.
- `alln show --stream` reattach ran 3+ minutes with **no terminal frame**; process
  killed manually.

**Hypothesis (investigate second):** parent session idles or stops emitting scoped
SSE while `task` children run; our waiter treats “no scoped idle + no answer” as
indefinite liveness. We may need **child-session rollup** on the shared bus, a
**stall watchdog**, or an OpenCode API to await parent turn completion including
delegated work.

### D — Counter-evidence (capability is there)

`4C84AD7C` produced five concrete audit bullets naming real symbols
(`OpenCodeServeCoordinator`, `OpenCodeRoutingWorkerRunner`, S122.5, permission
symptom class C drift). Pro is not the bottleneck when the turn completes.

---

## Symptom → truth owner map

| Symptom | Likely lie layer | Truth owner (code) |
| --- | --- | --- |
| First run `stream_drop` when second starts | SSE consumer lifecycle | `OpenCodeServeClient.streamRun` task group + `subscribeToEvents` |
| `foreignIdleDetected: false` but turn still dies | Stream end misclassified | `OpenCodeSSEParser` + `IdleGate.sawCleanIdle` |
| Hang with `task` tools, frozen `lastActivityAt` | Subagent lifecycle not wired to parent turn | `OpenCodeServeClient` + Allnighter `observation` |
| Owner shows `alive` for 6+ min with no events | Missing stall terminal | `RunService` wall / progress enforcer |
| Child session updates invisible to `alln` | Observation only tracks parent worker tools | `RemoteRunEventJournal` / worker activity mapper |

---

## Proposed slices (founder defaults — implement unless rejected)

| Slice | Scope | Exit |
| --- | --- | --- |
| **S123.0** | Repro fixture: two concurrent OpenCode sessions on one serve; first is mid-`read` | Integration test fails today; passes when first run completes or fails `foreign_idle`/`stream_drop` only after honest timeout |
| **S123.1** | Trace why SSE byte stream ends on concurrent session create (tcp close? parser flush? task group cancel?) | Root cause doc in test comment + fix or explicit reconnect loop |
| **S123.2** | Subagent / child-session awareness: map `task` → child `sessionID`s; extend turn until parent idle **and** no active children | Long audit fixture completes or `stalled_no_progress` within wall |
| **S123.3** | Allnighter `observation.lastActivityAt` includes child-session SSE activity | `alln show` reflects subagent progress during long turns |
| **S123.4** | Stall watchdog: no journal/SSE progress for N seconds ⇒ terminal `stalled_no_progress` (distinct from `timeout`) | Hung `18B2E77D` class fails ≤ wall instead of infinite `alive` |
| **S123.5** | Promote Works Test from archived S122 + this packet; update help topic | Owner-visible dogfood script in phase closeout |

**Optional spike (S123.x-s):** does OpenCode expose per-session event subscription
instead of global `/event`? If yes, prefer that over bus filtering alone.

---

## Works Test (owner-visible)

```text
Prereq: opencode serve on :4096; alln menu --json once.

1. LONG SOLO
   alln run --model model_opencode_deepseek_v4_pro --read-only --idle-timeout 600 \
     "Read docs/archive/phases/OpenCode_Headless_Completion_And_Session_Scoping.md
      and AGENTS.md OpenCode rows; write 5 numbered hard bullets."
   → Must complete with real bullets OR fail ≤600s with classified reason.
   → Must NOT stay ownerState:alive with frozen lastActivityAt >120s.

2. CONCURRENT
   Start (1) with --no-wait; within 5s start a second short read-only Pro run
   on another project.
   → First run must NOT fail stream_drop at 13s with only reads complete.
   → Second run may complete.

3. alln show <id> --json on both → never prompt echo; errors empty only if answer real.
```

Mutator companion (from S122, still required at closeout): one-line create+commit;
dirty-no-commit ⇒ `incomplete_uncommitted`.

---

## Open questions (resolve during S123.0–S123.1)

1. Does the global `/event` connection multiplex all sessions, and does OpenCode
   close it when a new session spikes load?
2. Are child `@explore` sessions separate `sessionID`s on the same bus, and does
   parent completion require waiting for them?
3. Should `maxConcurrentSpawns: 1` queue the second **CLI dispatch** but still
   allow overlapping OpenCode **sessions** inside one dispatch? (Today both can be
   active.)
4. Is `stream_drop` on concurrent start a regression from S122 task-group
   refactor, or pre-existing?

---

## Closeout

- [ ] S123.0–S123.4 green in AgentOS + Allnighter tests
- [ ] Owner-visible Works Test passes on founder machine (Pro, concurrent + long)
- [ ] Help topic amended: long runs and concurrency expectations
- [ ] Archive this packet; link from `OpenCode_CLI_Support.md`
