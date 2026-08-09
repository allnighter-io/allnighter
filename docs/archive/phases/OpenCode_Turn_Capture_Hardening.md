# OpenCode Turn Capture Hardening

Status: **COMPLETE — OCH-S01…S04 shipped AgentOS `65da768` (2026-08-09).**
Owner: AgentOS (`OpenCodeSSEParser`, `OpenCodeServeClient`, `OpenCodeRoutingWorkerRunner`,
`OpenCodeSpawnLock`, private actor `IdleGate`)
Created: 2026-08-09 | Updated: 2026-08-09 (closeout)
Parent: [`OpenCode_Completion_Truth_Followup.md`](../phases/OpenCode_Completion_Truth_Followup.md)
  (COMPLETE) + [`OpenCode_Long_Run_Continuity.md`](../phases/OpenCode_Long_Run_Continuity.md)
Doc reviews: Flash `5BBA6E13` (PRIMARY accumulate) · Pro `54CFCA2B` (idle+stall, rejected, S02 retry, S03)

**Shipped:** AgentOS `65da768` (actor parser last-only, harden reconcile, busy/idle-defer
+ clock injection, shared seat timeout budget). Help aliases on
`opencode_headless_completion`. Live: Flash pong smokes green; Pro+`task` dogfood
`9BED7495` → `local_idle` / done (not `stalled_no_progress`).

Archive copy — durable SSOT is AgentOS code + help topic above.

---

## If you only read one thing

`9579bb8` closed the empty-SSE-idle false fail. Four residual defects remain in
the same headless path:

| ID | Sev | Defect | Slice |
| --- | --- | --- | --- |
| **OCH-S01** | High | SSE + poll race; messageID-agnostic accumulator → regress / double-count (`pongpong`) | Actor parser + last-assistant-only per-messageID buffers |
| **OCH-S02** | High | Post-idle reconcile under-gated (`isEmpty` only, no `time.completed`); `try?` swallows fetch failures; single-shot races late commit | Harden reconcile + bounded retry |
| **OCH-S04** | High | Shared busy evidence missing → `stalled_no_progress` / clean idle while `task` child works (`EE9542AD`) | Busy predicate + idle deferral + clock injection |
| **OCH-S03** | Med | Spawn-lock wait + `ensureRunning` + `streamRun` each burn full `timeout` → up to 2× seat latency | Shared deadline budget |

Ship **S01 → S02 → S04 → S03** (race + truth first; latency last). Owner: AgentOS only.

---

## Cross-slice invariants (read before any OCH slice)

1. `accumulatedAnswer` (terminal text) is the **latest assistant message only** —
   never a concatenation of multiple assistant messages. Matches the synchronous
   `POST /session/{id}/message` path (`extractAnswer` returns the latest response's
   parts), keeps `isPromptEcho` exact-match meaningful, and keeps S02's
   prefix-superset reconcile coherent. Intermediate narration is streamed live as
   `answerDelta` events and is not part of the terminal output.
2. Every HTTP merge and SSE delta is **keyed by assistant `messageID`**; "latest"
   advances only on first-seen order. A merge/delta for an already-superseded id is
   dropped, never merged into the exposed buffer (prevents poll-regress and
   reconnect double-count).
3. The delta path never raw-`+=` once a poll merge has advanced that messageID's
   buffer; incoming deltas are suffix-checked against that buffer.
4. HTTP reconcile (S02) runs only on **clean-idle terminals** (`sawCleanIdle`) —
   never to rescue `stream_drop` / `timeout` / `stalled_no_progress` into fabricated
   success.
5. `stalled_no_progress` (S04) is deferred while the turn is **busy** (active
   children, running tools, or an open `task` delegation); the wall `deadline`
   remains the hard stop.
6. One seat timeout bounds **spawn-lock wait + ensureRunning + streamRun**
   end-to-end (S03). The process-local `DriverConcurrencyGate` wait (CHS-S01) is a
   separate, CHS-owned budget and is out of scope here.

---

## Rejected

| Idea | Why rejected |
| --- | --- |
| Remove poll fallback; SSE-only | Subagent/`task` turns still need HTTP when SSE is quiet (S123.2). |
| Raise `stallQuietInterval` only | Masks OCH-S04; burns wall on truly hung turns. |
| Cap flock wait at a fixed 30s unrelated to seat timeout | Breaks long seats that legitimately queue; budget must flow from the seat's own timeout. |
| Soften `emitTerminal` to `.done` on any partial text when stalled | Lies about completion; keep classified `stalled_no_progress` when the turn did not finish. |
| Buffer orphan `message.part` / orphan-buffer cap | With last-only + drop-superseded, the orphan-buffer hazard disappears; no cap needed (v1 "if added, cap 16" reopened a Rejected idea). |
| Use `NSLock` instead of `actor` for parser serialization | Actors are the language-owned isolation primitive; `NSLock` inside a `final class` is worse (no compiler enforcement, no sendability guard). |
| Use a serial `DispatchQueue` instead of `actor` | Nested `queue.sync` deadlocks; `queue.async` allows reorder between SSE+poll. |
| Make `emitTerminal` auto-promote mid-turn text on stall when children active | Mid-turn narration is not a final answer; fabricating `.done` lies. |
| Defer S04 idle-suppression to a follow-up slice | SSE `signal(clean: true)` on parent `session.idle` while a child works is co-terminal with stall; idle deferral and stall deferral ship together. |
| Concatenate all assistant messages into `accumulatedAnswer` | Garbles narration+answer, breaks `isPromptEcho` exact-match and S02's prefix-superset gate, diverges from sync `extractAnswer`, changes product output. Pinned: last-completed-assistant-only (invariant 1). |
| Defer stall while any session in the same directory is busy | Foreign-directory peers would mask genuine stalls. Busy is gated on THIS turn: children, running tools, or an open `task` part. |
| Never stall while the latest assistant message is incomplete | Converts hung-open-message turns to `timeout` (burns wall). Busy requires real activity evidence, not mere message-openness. |
| Call `pollMaySignalCleanIdle` instead of a dedicated reconcile | That helper gates on `!answer.isEmpty`; truncated-SSE healing needs an explicit prefix-superset forward-progress check. |

---

## OCH-S01 — Actor parser + last-assistant-only per-messageID accumulation

### Defect

`OpenCodeSSEParser` is a `final class … @unchecked Sendable`
(OpenCodeSSEParser.swift:12) with unsynchronized `answerAccumulator` /
`reasoningAccumulator` / seq counters / maps. `streamRun` runs two concurrent
tasks on one instance (OpenCodeServeClient.swift:197-241):
`consumeSSEBus → parser.receive(chunk)` and `pollSessionProgress →
parser.mergeAssistantTextIfNew`. Until `group.cancelAll()`, that is a data race.

Accumulation is not messageID-keyed, and the two writer styles disagree:

- poll `mergeAssistantTextIfNew` replaces the whole accumulator with the HTTP
  full text (`:78`);
- the SSE delta path raw-`+=`s (`:265`).

Real defects (not "dropped message 1"):

1. **Regress** — a poll merge of an earlier/superseded HTTP message overwrites
   the message SSE is currently streaming.
2. **Double-count** — reconnect replay or a late delta after a poll merge yields
   `pongpong`.
3. **Race** — unsynchronized `String`/`Int` mutation from two tasks.

Under invariant 1, dropping prior assistant text from the *terminal* answer is
intended: intermediate narration streams as deltas only.

### Fix design

1. Convert `OpenCodeSSEParser` to an `actor`; `receive` / `flush` /
   `mergeAssistantTextIfNew` / snapshot reads become `await` at call sites. The
   ~35 synchronous parser unit tests become `async` (mechanical). An
   internal-lock alternative is acceptable; actor preferred.
2. **Per-messageID accumulation, last-only exposure:**
   - Track `latestAssistantMessageID`, advanced on first-seen order.
   - Each assistant messageID owns one live buffer. Exposed `accumulatedAnswer`
     is the buffer of `latestAssistantMessageID` only.
   - Incoming part/merge with id == latest → suffix-dedup merge into that buffer.
   - Incoming part/merge with a NEW id → promote latest, start a fresh buffer.
   - Incoming part/merge with an id already seen and != latest → **drop**
     (superseded; no memory retained — orphan-buffer cap unnecessary).
3. Delta path: never raw-`+=` after any poll merge for that messageID; treat each
   delta as a suffix check against that message's buffer.
4. Keep fail-closed scoping: unknown `messageID` still drops.

Observable change: a tool-loop streams message 1 *then* message 2 deltas; the
terminal answer is message 2 only. Allnighter's journal mapper must tolerate
both messages streaming (Works Test note).

### Proof

| Test | Must assert |
| --- | --- |
| Actor / serialized access | Existing stream+poll fixtures green by construction (actor); TSan clean preferred |
| Multi-assistant, last-only | asst1 `"Let me check"` + tool parts + asst2 `"answer"` → terminal == `"answer"`; asst1 NOT concatenated; both streamed as deltas |
| No regress | Poll HTTP merge of asst1 (superseded) after asst2 streamed → accumulator stays `"answer"` |
| No double-count | Poll merges `"pong"` (id A), then SSE delta `"pong"` for id A → stays `"pong"` |
| Reconnect replay | SSE replay of id A after poll merge → no duplication |
| Unchanged: foreign drop, tool-only, prompt echo | Existing `OpenCodeSSEParserTests` / `OpenCodeServeClientTests` |

### Done when

Parser is an actor (or lock-equivalent) with messageID-keyed, last-only
accumulation; no-regress, no-double-count, and multi-assistant fixtures green;
prompt-echo and tool-only fixtures still green.

---

## OCH-S02 — Harden post-idle HTTP reconcile

### Defect

After `9579bb8`, clean idle + **empty** accumulator triggers
`fetchSessionMessages → extractLatestAssistantText → mergeAssistantTextIfNew`
(OpenCodeServeClient.swift:249-257). Gaps (Flash `C04DF145`):

1. No `latestAssistantMessageCompleted` gate — can `.done` on mid-flight partial
   text (helper exists at `:637`, unused here).
2. Gate is `isEmpty` only — truncated non-empty SSE (e.g. `"po"`) skips reconcile.
3. `try?` on fetch — silent miss → still looks like `incomplete_no_final_message`.
4. Single-shot reconcile races server-side commit after SSE idle.

### Fix design

Run reconcile on every `sawCleanIdle` terminal (drop the `isEmpty` gate — merge
is a no-op when there is no suffix). Reconcile only when all of:

- `latestAssistantMessageCompleted(from: data) == true`
- `!hasRunningToolsInLatestAssistant(from: data)`
- `(id, httpText) = latestCompletedAssistant(from: data)` — S01 dependency:
  merge keyed by `id`; if `id` already superseded, drop (invariant 2)
- `newSuffix(previous: latestBuffer, current: httpText)` non-empty OR
  latestBuffer empty and httpText non-empty

Skip the fetch when `promptFail` / `sessionError` / `permissionAsk` are set.

On fetch failure:

- latestBuffer still empty → terminal `errorReason` includes
  `"reconcile failed: <short error>"` (never fabricated success). Emit order:
  promptFail → sessionError → permissionAsk → reconcileFailure → emitTerminal.
- latestBuffer non-empty → keep current terminal path (no rewrite).

**Bounded retry:** if the latest assistant exists but is not yet completed at
the first fetch, retry up to ~3 times with 250ms–1s backoff (never exceed wall
deadline). A single-shot reconcile can still truncate.

Keep the `sawCleanIdle` gate (invariant 4): never reconcile
`stream_drop` / `timeout` / `stall` into success. Align with CT-01: never weaker
than `pollMaySignalCleanIdle`'s HTTP-side completion predicate.

`"reconcile failed:"` is user-visible — closeout help-alias applies.

### Proof

| Test | Must assert |
| --- | --- |
| Existing empty+idle+HTTP pong | Still `.done("pong")` |
| Idle + empty + HTTP text WITHOUT `time.completed` | Must not merge; must not `.done` from reconcile |
| Idle + SSE prefix `"po"` + HTTP `"pong"` completed | `.done("pong")` |
| Idle + completed SSE `"pong"` + HTTP same | No change; `.done("pong")` |
| Idle + superseded id merge | Superseded id dropped (no regress) |
| Idle + empty + fetch throws | `errorReason` contains `reconcile failed` |
| Idle + session.error set | Reconcile fetch skipped; failure terminal unchanged |
| Idle + incomplete then completed on retry | Bounded retry heals; no fabricate on exhausted retries |

### Done when

Reconcile cannot fabricate `.done` from incomplete HTTP; truncated SSE is healed
when HTTP is a completed prefix-superset (with bounded retry); fetch failures are
visible; superseded merges never regress the answer.

---

## OCH-S04 — Shared busy predicate + idle deferral + stall

### Defect

Pro `EE9542AD` (~158s): parent emitted mid-turn text, spawned `task` child
`ses_019154ec6ffe…` that worked for minutes; client reported
`stalled_no_progress`.

v1 framing ("parent SSE goes quiet and poll is delayed") is wrong: poll already
`touch()`es every 5s while `activeChildren` non-empty (`:440-451`) and while
tools run (`:465-468`). Stall implies child activity became **invisible**:

1. `delegationActiveWindow` (90s, `:39`) drops a child whose session `updated`
   has not refreshed (`:557-563`).
2. OpenCode can mark the parent's `task` part terminal at dispatch (F2
   "dispatch ok" lie), so `hasRunningToolsInLatestAssistant` is false while the
   child runs → no busy evidence → stall after 120s quiet.
3. SSE `session.idle` (interleaved between steps) unconditionally
   `signal(clean: true)` (`:371-372`), cancelling the poll peer (`:238-239`) →
   truncated `.done(mid-turn)` while the child works. Co-terminal with stall —
   **required**, not optional.

Truth owners: poll busy predicate + SSE idle handler (not SSE stall alone).

### Fix design

1. **Shared busy predicate** (poll loop, SSE idle handler, stall decision):

   `busy` = `!activeChildren.isEmpty` OR `hasRunningToolsInLatestAssistant` OR
   `hasOpenTaskDelegation`

   `hasOpenTaskDelegation(from:)` (new pure static): latest assistant has a
   `task` tool part that is non-terminal (empty/running/pending) OR terminal
   while children remain. Never trust a `task` part's own state alone (F2).

2. **Poll loop:** `busy` → `touch()` + continue. Never clean-signal while busy.

3. **SSE idle handler (required):** scoped idle while `busy` → `touch()`, do NOT
   `signal(clean: true)`. Idle while not busy → clean as today.

4. **Stall:** fires only when NOT `busy` for the quiet window. Wall `deadline`
   stays the hard stop.

5. **Clock/interval injection (required):** injectable `now` or interval override
   on `IdleGate` / `isStalled`. Without it, fixtures cannot fail (CT-02 debt).

6. Do not auto-promote mid-turn narration to `.done` on stall. Keep
   `delegationActiveWindow` but document it as reachable only when the parent
   has no non-terminal `task`/tool part.

Before coding: confirm EE9542AD artifacts (`GET /session` — stale `time.updated`
>90s? parent `task` completed-at-dispatch?). Busy predicate covers either;
artifacts pin the primary driver.

### Proof

| Test | Must assert |
| --- | --- |
| Parent quiet + active child (parentID list) | No stall within quiet window (**injected short interval**) |
| Parent with non-terminal `task` part, empty child list | Still no stall (open-delegation busy) |
| Parent with terminal `task` + no children + no running tools | Stall DOES fire after quiet interval |
| Scoped SSE idle while child active | No clean signal; idle deferred |
| Scoped SSE idle, no children | Clean as today |
| No children + quiet ≥ interval | Still stalls |
| Live dogfood (Works Test) | EE9542AD-class Pro/`task` review reaches `local_idle` with a real answer, or a classified non-stall terminal; never `stalled_no_progress` while a parentID-matched child is updating |

### Done when

Shared busy predicate prevents clean idle and stall while the turn is busy;
clock injection makes stall fixtures fail-able; hung parent with no busy
evidence still stalls.

---

## OCH-S03 — Shared seat timeout budget (no 2× stack)

### Defect

`OpenCodeRoutingWorkerRunner.invoke`:

```swift
try await OpenCodeSpawnLock.withLock(timeout: timeout) {
    try await coordinator.ensureRunning()
    for try await event in client.streamRun(..., timeout: timeout, ...)
}
```

Lock wait may consume up to `timeout`, then `streamRun` starts
`deadline = now + timeout` again. Worst case ≈ **2×** seat invoke timeout.
`ensureRunning` also burns wall inside the lock but outside the stream deadline.

### Fix design

1. Capture `budgetStart = now()` before `withLock`.
2. Compute `remaining = max(0, budgetStart + timeout - now())` at each phase;
   `withLock` uses remaining at acquire; after `ensureRunning`, recompute and
   pass `streamRun(..., timeout: remaining)` — drives createSession / sseReq
   timeouts and the internal deadline (no signature change required if remaining
   is folded into `timeout`).
3. Fail-closed: `insufficientBudgetGrace` ≈ **5s** →
   `OpenCodeSpawnLock.LockError.insufficientBudget` →
   errorReason `opencode spawn lock: insufficient budget` (only after the seat's
   own lifetime is exhausted — CHS "serialize, never refuse").
4. `ensureRunning`'s ~10s health-check deadline
   (OpenCodeServeCoordinator.swift:137) is **not** budget-aware; with typical
   180–240s seats the overshoot is small — document, do not fix here.
5. **Scope note (invariant 6):** process-local `DriverConcurrencyGate` wait
   (CHS-S01, `GatedWorkerRunner.swift:43,50`) is a separate CHS-owned budget.
   After this slice a same-process seat can still be gate-wait T + opencode
   budget T ≈ 2T wall **by CHS design**; the two-process case (the actual bug)
   is fixed because the flock waiter fails closed once its single budget is
   exhausted.

### Proof

| Test | Must assert |
| --- | --- |
| Unit: remaining budget | Injected `now` / fake clock: lock wait of T/2 leaves streamRun ≈ start+T (not start+1.5T); observable via `req.timeoutInterval` on injectable transport |
| Insufficient budget | Remaining < `insufficientBudgetGrace` → fail without calling `streamRun` |
| End-to-end | Lock contention → second run wall ≤ original seat timeout (not 2×) |

### Done when

One seat timeout bounds **flock wait + ensureRunning + streamRun** end-to-end;
CHS gate documented as a separate budget; insufficient-budget fails closed.

---

## Slice order and ownership

| Order | Slice | Primary files |
| --- | --- | --- |
| 1 | OCH-S01 | `OpenCodeSSEParser.swift` (actor + last-only per-messageID), `OpenCodeServeClient.swift` call sites (`await`), parser/client tests |
| 2 | OCH-S02 | `OpenCodeServeClient.swift` reconcile block (`:249-257`), reconcile tests |
| 3 | OCH-S04 | `OpenCodeServeClient` busy predicate + idle deferral + stall sites + `IdleGate` clock injection, tests |
| 4 | OCH-S03 | `OpenCodeRoutingWorkerRunner.swift` budget, lock / insufficient-budget tests |

All slices: **AgentOS only.** Rebuild `alln` after each for live dogfood.

Dependencies: S01 → S02 (await + messageID-keyed merge); S02 → S04 (reconcile
sees completed messages only after idle deferred while busy); S03 independent.

---

## Works Test (packet closeout)

1. **Unit:** AgentOS `OpenCodeServeClientTests` + `OpenCodeSSEParserTests` green
   for all fixtures above. After S01: `swift test --sanitize thread` preferred.
2. **Unit (S04):** Stall deferral and stall-firing proven with an **injected**
   quiet interval — live-only stall proof is insufficient.
3. **Live regression:** Flash one-word smoke ×3 sequential — zero
   `incomplete_no_final_message` with OpenCode DB showing text (D969/12380).
4. **Live task (mandatory):** Pro read-only review **allowed to use `task`** —
   must NOT end `stalled_no_progress` while a parentID-matched child is updating;
   must end `local_idle` with a real answer or a classified non-stall terminal
   (`EE9542AD` class). Packet does not close without one passing live run.
5. **Live timeout budget:** Short timeout (e.g. 30s) while another seat holds
   the lock ~20s → second run wall ≤ 30s (not ~50s).
6. **Live stream shape:** Confirm multi-assistant tool-loop streams m1 then m2
   deltas; terminal answer is last-only (journal mapper tolerates both).

---

## Remaining risks (ranked)

| Rank | Risk | Mitigation |
| --- | --- | --- |
| 1 | S01 actor hop per SSE chunk under high-frequency tokens | Accept; I/O-bound. Revisit only if dogfood shows measurable regression. |
| 2 | S04 TOCTOU between busy-check and `signalStalled()` | Double-check shrinks window; full close needs IdleGate owning HTTP (layering violation). Accepted. |
| 3 | S02 reconcile after child drain before `time.completed` syncs | Bounded retry (~3, 250ms–1s) in S02; if still incomplete after retries, fail closed (do not fabricate). |
| 4 | CHS gate + opencode budget can still stack ≈2T same-process | Documented (invariant 6); out of scope — CHS-owned. |
| 5 | `ensureRunning` ~10s unbudgeted overshoot | Documented; typical seats absorb it; S03 grace gate covers worst case. |
| 6 | New `reconcile failed:` needs Allnighter help alias | Closeout. |
| 7 | Actor conversion churn across ~35 parser tests | Mechanical cost, not a blocker. |

---

## Closeout

1. Promote: none beyond AgentOS code + tests (help if new `errorReason` is
   user-visible — S02 `reconcile failed:` → alias on `opencode_headless_completion`).
2. Update AGENTS.md OpenCode long-run / turn-capture row to archived packet +
   code SSOT.
3. `git mv` this file to `docs/archive/phases/`; board + archive index rows.
4. Mark parent CT follow-up + S123 archive-ready note if still open.

---

## Origin evidence (do not relitigate)

| Run | Role |
| --- | --- |
| `D969E325`, `12380D2B` | Empty SSE idle; DB had `pong` → `9579bb8` |
| `C04DF145` | Flash residual audit (S01/S02/S03 themes) |
| `44A2B410` | Pro residual audit |
| `EE9542AD` | Pro `stalled_no_progress` mid-`task` (S04) |
| AgentOS `9579bb8` | Post-idle empty reconcile (incomplete; S02 hardens) |
| Flash doc review `5BBA6E13` | PRIMARY: last-only accumulate, busy predicate, clock injection, S02 retry |
| Pro doc review `54CFCA2B` | Idle+stall co-ship, rejected alternatives, S03 budget scope |

---

## Harden changelog (v1 → v2)

| Decision | v1 | v2 (locked) |
| --- | --- | --- |
| S01 accumulate | Ambiguous concat vs last-only | **Last-assistant-only** (Flash D1); concat Rejected |
| S01 orphan cap | "if added, cap 16" escape hatch | Deleted; last-only + drop-superseded eliminates hazard |
| S01 defect framing | "drops prior assistant message 1" | Regress / double-count / race; drop is intended terminal semantic |
| S02 reconcile gate | `isEmpty` only | Every `sawCleanIdle`; `time.completed` + no running tools + prefix-superset by messageID |
| S02 retry | None | Bounded ~3, 250ms–1s; never heal stream_drop/timeout/stall |
| S04 mechanism | "poll delayed / SSE quiet" | Invisible busy: 90s delegation window + F2 task-terminal-at-dispatch |
| S04 idle deferral | Optional stretch | **Required**; co-ships with stall |
| S04 busy | Children list only | Shared predicate: children OR running tools OR open `task` delegation |
| S04 proof | Unclockable 120s fixtures | Clock/interval injection required |
| S03 budget | Implied "one timeout" | Flock + ensureRunning + streamRun shared; CHS gate separate; `insufficientBudgetGrace` ≈5s |
| Ship order | S01 → S02 → S04 → S03 | Unchanged |
| Owner | AgentOS | Unchanged |

No founder rulings required. Ready to code.
