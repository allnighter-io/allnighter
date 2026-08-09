# OpenCode Turn Capture Hardening

Status: **OPEN — Ready to code after Flash/Pro doc harden (v1).**
Owner: AgentOS (`OpenCodeSSEParser`, `OpenCodeServeClient`, `OpenCodeRoutingWorkerRunner`,
`OpenCodeSpawnLock`, `IdleGate`)
Created: 2026-08-09
Parent: [`OpenCode_Completion_Truth_Followup.md`](OpenCode_Completion_Truth_Followup.md)
  (COMPLETE) + [`OpenCode_Long_Run_Continuity.md`](OpenCode_Long_Run_Continuity.md)
Origin:
- Empty-answer false fail: Flash smokes `D969E325` / `12380D2B` (OpenCode DB had
  `pong`; client reported `incomplete_no_final_message`) — mitigated by AgentOS
  `9579bb8` (post-idle HTTP reconcile when accumulator empty).
- Residual review: Flash `C04DF145` + Pro `44A2B410` (read-only AgentOS audit after
  `9579bb8`); Pro stall incident `EE9542AD` (`stalled_no_progress` mid-`task`).

Phases are ephemeral. At closeout: promote durable law into AgentOS code + tests;
archive. No Allnighter product law changes required unless teaching must name a
new `errorReason`.

---

## If you only read one thing

`9579bb8` closed the empty-SSE-idle false fail. Four residual defects remain in
the same headless path:

| ID | Sev | Defect | Slice |
| --- | --- | --- | --- |
| **OCH-S01** | High | SSE + poll mutate `OpenCodeSSEParser` unsynchronized; single turn accumulator loses prior assistant messages / can double-count deltas | Parser actor + per-message accumulate |
| **OCH-S02** | High | Post-idle reconcile under-gated (`isEmpty` only, no `time.completed`) and swallows fetch failures with `try?` | Harden reconcile |
| **OCH-S03** | Med | Spawn-lock wait + `streamRun` deadline each use full `timeout` → up to 2× seat latency | Shared deadline budget |
| **OCH-S04** | High | Parent stall watchdog fires while a live `task` child is still working (`EE9542AD`) | Touch/stall while children active |

Ship **S01 → S02 → S04 → S03** (race + truth first; latency last).

---

## Rejected

| Idea | Why rejected |
| --- | --- |
| Remove poll fallback; SSE-only | Subagent/`task` turns still need HTTP when SSE is quiet (S123.2). |
| Raise `stallQuietInterval` only | Masks OCH-S04; burns wall on truly hung turns. |
| Cap flock wait at a fixed 30s unrelated to seat timeout | Breaks long seats that legitimately queue; budget must flow from the seat's own timeout. |
| Soften `emitTerminal` to `.done` on any partial text when stalled | Lies about completion; keep classified `stalled_no_progress` when the turn did not finish. |
| Buffer orphan `message.part` without a cap | Memory hazard on a busy shared `/event` bus; if done, cap ≤16 and drain at idle. |

---

## OCH-S01 — Single-writer parser + per-message accumulation

### Defect

`OpenCodeSSEParser` is `final class … @unchecked Sendable` with unsynchronized
`answerAccumulator` / `reasoningAccumulator` / seq counters / maps.

`streamRun` runs two concurrent tasks on one instance:

1. `consumeSSEBus` → `parser.receive(chunk)` (delta `+=`, fullText `newSuffix`)
2. `pollSessionProgress` → `parser.mergeAssistantTextIfNew`

Until `group.cancelAll()`, that is a data race on Swift `String`/`Int` storage.

Separately, accumulation is **turn-global**, while ownership maps are keyed by
`messageID`. After a tool loop, assistant message 2's text is not a prefix of
message 1's text → `newSuffix` **replaces** and drops message 1. The SSE `delta`
path appends raw; poll stores trimmed full text → reconnect replay can yield
`pongpong`.

### Fix design

1. **Convert `OpenCodeSSEParser` to an `actor`** (preferred) so `receive`,
   `flush`, `mergeAssistantTextIfNew`, and snapshot getters serialize. Call sites
   in `OpenCodeServeClient` become `await parser.…`.
2. **Accumulate per assistant `messageID`**, then expose:
   - `accumulatedAnswer` = join of assistant message texts in arrival order
     (or last completed assistant only — pick one and fixture both tool-loop and
     single-shot). **Recommended:** concatenate completed assistant `text` parts
     in session order with `\n\n` between messages; in-progress message uses
     live accumulator for that id only.
3. **Delta path must prefix-dedup** the same way fullText does (or only accept
   deltas when no poll merge has advanced past them). Simplest durable rule:
   never raw-`+=` after any HTTP merge for that messageID; treat incoming delta
   as a suffix check against that message's buffer.
4. Keep fail-closed scoping: unknown `messageID` still drops (orphan buffer is
   **out of scope** for S01 unless a fixture proves live reorder; if added, cap 16).

### Proof

| Test | Must assert |
| --- | --- |
| Actor / serialized access | Existing stream+poll fixtures still green under TSan or by construction (actor) |
| Multi-assistant turn | Fixture: asst1 text `"Let me check"` + asst2 `"answer"` → terminal contains both (or documented last-only policy) |
| No double-count | Poll merges `"pong"`, then SSE delta `"pong"` → accumulator stays `"pong"` |
| Unchanged: foreign drop, tool-only, prompt echo | Existing `OpenCodeSSEParserTests` / `OpenCodeServeClientTests` |

### Done when

Parser has no `@unchecked Sendable` class with shared mutable storage across
tasks; multi-message and double-count fixtures green.

---

## OCH-S02 — Harden post-idle HTTP reconcile

### Defect

After `9579bb8`, clean idle + **empty** accumulator triggers:

```text
fetchSessionMessages → extractLatestAssistantText → mergeAssistantTextIfNew
```

Gaps (Flash `C04DF145`):

1. No `latestAssistantMessageCompleted` — can `.done` on mid-flight partial text.
2. Gate is `isEmpty` only — truncated non-empty SSE text skips reconcile.
3. `try?` on fetch — silent miss; still looks like `incomplete_no_final_message`.

### Fix design

Replace the empty-only block with `reconcileAssistantTextIfNeeded(...)`:

```text
preconditions to merge:
  - sawCleanIdle (or always-at-terminal for empty/partial — prefer sawCleanIdle)
  - latestAssistantMessageCompleted(from: data) == true
  - !hasRunningToolsInLatestAssistant(from: data)
  - let httpText = extractLatestAssistantText(from: data)
  - httpText is a strict prefix-superset of accumulatedAnswer
      (newSuffix(previous: accumulated, current: httpText) non-empty
       OR accumulated empty and httpText non-empty)

on fetch failure:
  - if accumulated still empty → failed reason includes
    "reconcile failed: <short error>" (do not invent success)
  - if accumulated non-empty → keep current terminal path (no rewrite)
```

Align with CT-01: reconcile must never be weaker than `pollMaySignalCleanIdle`'s
completion predicate for the HTTP side.

Optional stretch (not required for S02 close): if parent tools include completed
`task` and parent text empty, GET child session message (OCH-S04 adjacent).

### Proof

| Test | Must assert |
| --- | --- |
| Existing empty+idle+HTTP pong | Still `.done("pong")` |
| Idle + empty + HTTP text **without** `time.completed` | Must **not** merge / must not `.done` from reconcile |
| Idle + SSE prefix `"po"` + HTTP `"pong"` completed | `.done("pong")` |
| Idle + empty + fetch throws | `errorReason` contains `reconcile failed` |

### Done when

Reconcile cannot fabricate `.done` from incomplete HTTP; truncated SSE is healed
when HTTP is a completed superset; fetch failures are visible.

---

## OCH-S03 — Shared seat timeout budget (no 2× stack)

### Defect

`OpenCodeRoutingWorkerRunner`:

```swift
try await OpenCodeSpawnLock.withLock(timeout: timeout) {
    try await coordinator.ensureRunning()
    for try await event in client.streamRun(..., timeout: timeout, ...)
}
```

Lock wait may consume up to `timeout`, then `streamRun` starts
`deadline = now + timeout` again. Worst case ≈ **2×** the seat's invoke timeout.

### Fix design

1. Capture `budgetStart = now()` before `withLock`.
2. Pass **remaining** budget into `streamRun`:
   - Add `deadline: Date? = nil` (or `timeout` computed from remaining) on
     `streamRun` / keep `timeout` but compute
     `min(timeout, max(0, budgetStart + timeout - now()))` at entry.
3. Cap flock wait: `withLock(timeout: remaining)` where remaining shrinks; if
   lock acquired with little time left (< e.g. 5s), fail closed with
   `opencode spawn lock: insufficient budget` rather than starting a doomed turn.
4. Do **not** change `DriverConcurrencyGate` bounds here (CHS already owns that).

### Proof

| Test | Must assert |
| --- | --- |
| Unit: remaining budget | With fake clock / injected `now`, lock wait of T/2 leaves streamRun deadline ≈ start+T (not start+1.5T) |
| Insufficient budget | After lock wait leaving < threshold, fail without calling `streamRun` |

### Done when

One seat timeout bounds **lock wait + ensureRunning + streamRun** end-to-end.

---

## OCH-S04 — Stall must not fire while delegation children are active

### Defect

Pro `EE9542AD` (~158s): parent emitted mid-turn text
`"Let me also read the supporting types…"`, spawned `task` child
`ses_019154ec6ffe…` that continued grep/read for minutes. Client reported
`stalled_no_progress` with `assistantText` still the mid-turn line. OpenCode DB
showed the child finishing after the parent client had already failed.

`pollSessionProgress` already `touch()`es when `listActiveDelegationSessions` is
non-empty — but:

- First poll sleep is 5s; SSE idle/progress may stop on the parent while the
  child works.
- `consumeSSEBus` stall check uses `IdleGate.isStalled(quiet: 120s)` based on
  last **SSE/poll progress touch**. If parent SSE goes quiet and poll is delayed
  or cancelled paths don't run, stall wins.
- `emitTerminal` fails closed on `.stalledNoProgress` **even when** some
  assistant text exists — correct for hung turns, wrong when children are live.

### Fix design

1. **Before `signalStalled()`** (SSE path and poll path), re-check
   `listActiveDelegationSessions` (same parentID sticky probe). If any active
   child → `touch()` and **do not** stall.
2. Optionally: while children active, treat parent `session.idle` as
   **non-terminal** (do not `signal(clean: true)` until children empty **or**
   require completed parent assistant after children drain). Prefer (1) first —
   smaller blast radius; add idle deferral if dogfood still stalls.
3. Keep wall `deadline` as the hard stop (budget from S03).
4. Do not auto-promote mid-turn narration to `.done` on stall.

### Proof

| Test | Must assert |
| --- | --- |
| Fixture: parent quiet + active child in session list | Must not `stalled_no_progress` inside quiet window |
| Fixture: no children + quiet ≥ stall interval | Still stalls |
| Live dogfood (optional Works Test) | Pro/`task` review like `EE9542AD` reaches `local_idle` or classified non-stall terminal |

### Done when

A live child under `parentID` prevents `stalled_no_progress`; hung parent with no
children still stalls.

---

## Slice order and ownership

| Order | Slice | Primary files |
| --- | --- | --- |
| 1 | OCH-S01 | `OpenCodeSSEParser.swift`, call sites in `OpenCodeServeClient.swift`, parser/client tests |
| 2 | OCH-S02 | `OpenCodeServeClient.swift` reconcile + tests |
| 3 | OCH-S04 | `OpenCodeServeClient.consumeSSEBus` / `pollSessionProgress` / `IdleGate` usage + tests |
| 4 | OCH-S03 | `OpenCodeRoutingWorkerRunner.swift`, optionally `streamRun` deadline API, lock tests |

All slices: AgentOS only. Rebuild `alln` after each for live dogfood.

---

## Works Test (packet close)

1. Unit: AgentOS `OpenCodeServeClientTests` + `OpenCodeSSEParserTests` green for
   all new fixtures above.
2. Live: Flash one-word smoke ×3 sequential — zero `incomplete_no_final_message`
   with OpenCode DB showing text (regression of D969/12380).
3. Live: Pro read-only review **allowed to use `task`** — must not end
   `stalled_no_progress` solely because a child was active (`EE9542AD` class).

---

## Closeout

1. Promote: none beyond AgentOS code + tests (help only if a new errorReason
   string is user-visible — add alias on `opencode_headless_completion`).
2. Update AGENTS.md OpenCode long-run row to point at archived packet + code SSOT.
3. `git mv` this file to `docs/archive/phases/`; board + archive index rows.
4. Mark parent CT follow-up / S123 archive-ready note if still open.

---

## Origin evidence (do not relitigate)

| Run | Role |
| --- | --- |
| `D969E325`, `12380D2B` | Empty SSE idle; DB had `pong` → `9579bb8` |
| `C04DF145` | Flash residual audit (S01/S02/S03 themes) |
| `44A2B410` | Pro residual audit |
| `EE9542AD` | Pro `stalled_no_progress` mid-`task` (S04) |
| AgentOS `9579bb8` | Post-idle empty reconcile (incomplete; S02 hardens) |
