# OpenCode Completion-Truth Follow-up

Status: **COMPLETE — CT-01…09,11–13 shipped; CT-10 deferred; ARCHIVED 2026-08-09.**
  Code SSOT: AgentOS `OpenCodeServeClient`, `OpenCodeSSEParser`,
  `OpenCodeServeCoordinator`, `OpenCodePermissionPolicy`, `DriverConcurrencyGate`;
  Allnighter `OpenCodeOutcomeAuthority`, `RunService`. Help: `opencode_headless_completion`.
Owner: code SSOT above (not this archive).
Home: was `docs/phases/` — archived with parent S123.
Created: 2026-08-07
Updated: 2026-08-09 (closeout)
Parent: [`OpenCode_Long_Run_Continuity.md`](OpenCode_Long_Run_Continuity.md) (S123)
Origin audit: `alln` run `7E8E0930-FA7E-4345-8760-A2D386798B95`
(DeepSeek V4 Pro via `--team code_plan --model model_opencode_deepseek_v4_pro`)

**Shipped AgentOS commits (this flight):** `ab96e7c` → `d4a5d01` (completion-truth,
smoke refuse, spawn recover, mediums, path harden, CT-14 note).
**Shipped Allnighter commits:** `4950d63f` (outcome rewrite), `43e1b8a9` (`answerOnly`).

**Dogfood (2026-08-07, `alln` git `cb18e54d`):** subagent-heavy long Pro
`ABB38F3C` (`local_idle`, `task`+`read`+`grep`, ~2m); concurrent long+short
`F67766CF`/`6FC2DACB` (long completed, short queued then refused orphan serve —
no `stream_drop`); CT-14 cross-process flock proven (two-PID flock script + live
contention). **Prereq fix:** port `:4096` must be **free** — let `alln` spawn;
manual `opencode serve` or orphan child → `portOwnedByForeignProcess`.

**Still open:** CT-08 lock-gated sibling `external_directory` **code** (ruling
below); CT-10 poll-permission gap (deferred — not hit in dogfood).

Phases are ephemeral. At closeout: promote durable law into code + help; archive.

---

## If you only read one thing

The completion-truth trio (CT-01…03) and the high lifecycle/authority defects
are **coded** with unit proofs. Do **not** archive S123 until live dogfood covers
subagent-heavy long Pro + concurrent seats, and until CT-08’s write-lock ruling
lands (path `..` harden already shipped).

| ID | Sev | Claim (audit) | Re-verify | Status |
| --- | --- | --- | --- | --- |
| **CT-01** | Blocker | Poll declares clean success mid-turn | **Verified** | **Coded** AgentOS `ab96e7c` |
| **CT-02** | High | Stall watchdog defeated by poll `touch()` | **Verified** | **Coded** `ab96e7c` |
| **CT-03** | High | Foreign SSE events defeat scoping twice | **Verified** | **Coded** `ab96e7c` |
| **CT-04** | High | Outcome rewrite destroys permission/session reasons | **Verified** | **Coded** Allnighter `4950d63f` |
| **CT-05** | High | Doctor/smoke can SIGTERM a live foreign serve | **Verified** | **Coded** `9ebbec2` |
| **CT-06** | High | One spawn failure poisons coordinator forever | **Verified** | **Coded** `2b21b13` |
| **CT-07** | High | `answerOnly` never reaches production | **Verified** | **Coded** Allnighter `43e1b8a9` (option A) |
| **CT-08** | High | Sibling-repo allow bypasses write lock + dirty gate | **Verified** (policy) | **Coded** — AgentOS `d82b070` + Allnighter `99aa2c70` |
| **CT-09** | Med | Empty `sessionID` on permission ask fails open | **Verified** | **Coded** `06ef131` |
| **CT-10** | Med | Poll never observes pending permissions | **Verified** | **Open** (deferred) |
| **CT-11** | Med | `parentID` capability probe is data-presence | **Verified** | **Coded** sticky probe `06ef131` |
| **CT-12** | Med | `DriverConcurrencyGate` timeout/handoff permit leak | **Verified** | **Coded** `06ef131` |
| **CT-13** | Med | Client vs authority disagree on reason precedence | **Verified** | **Coded** `4950d63f` |
| **CT-14** | Med | Spawn-lock test is in-process only | **Verified** | **Proven** — live two-`alln` contention `F67766CF`/`6FC2DACB` + cross-PID flock script |
| **CT-15** | Low | S123 FIXED column / uncommitted polish | **Verified** | **Done** — parent F-table + commit refs amended 2026-08-07 |

---

## Verified defects

### CT-01 — Poll fallback declares clean success mid-turn (blocker)

**Where:** AgentOS `OpenCodeServeClient.pollSessionProgress`
(approx. lines 428–444).

**Evidence:**

```swift
guard let data = try? await fetchSessionMessages(...) else {
    continue
}
await idleGate.touch()
// ...
if hasRunningToolsInLatestAssistant(from: data) {
    continue
}
if !parser.accumulatedAnswer.isEmpty {
    await idleGate.signal(clean: true)
    return
}
```

The poll path never checks assistant `time.completed`, never requires a
session-scoped `session.idle`, and never checks SSE recency. Any pause with
accumulated answer text + no *currently running* tool parts → `sawCleanIdle`
→ product-facing success while the server-side session may still be working.

**Why it matters:** Reintroduces the S122 fake-success class through the S123.2
HTTP fallback. The abandoned live session then becomes foreign chatter for CT-03.

**Proposed fix (not implementing):**

1. Poll may signal **clean** only when at least one of:
   - scoped `session.idle` was observed for this session, or
   - the latest assistant message carries a completed timestamp / terminal state
     that OpenCode documents as finished.
2. Otherwise keep polling / wait for stall or wall deadline.
3. Fixture: messages with text + completed tools, **no** completion marker, SSE
   still open → must **not** `.done` on the next poll tick.

**Maps to S123:** Defeats F2 completion predicate; related to Bug C class.

---

### CT-02 — Stall watchdog is effectively dead while serve answers HTTP (high)

**Where:** Same `pollSessionProgress` — `await idleGate.touch()` immediately
after a successful `fetchSessionMessages`, even when nothing changed.
`IdleGate.isStalled` only compares `Date()` to `lastActivityAt`.

**Evidence:**

```swift
guard let data = try? await fetchSessionMessages(...) else { continue }
await idleGate.touch()   // every successful GET, including identical payloads
```

```swift
func isStalled(quiet: Duration) -> Bool {
    guard let lastActivityAt else { return false }
    return Date().timeIntervalSince(lastActivityAt) >= seconds(quiet)
}
```

While `:4096` is up, the 5s poll refreshes activity forever. Hung subagent turns
(`18B2E77D` class) burn the wall clock and classify `timeout`, almost never
`stalled_no_progress`. Allnighter’s “honor `stalled_no_progress`” path is moot
if AgentOS rarely produces the signal.

**Also:** `stallQuietInterval` is a hardcoded `static let` with no clock
injection; “stall tests” that only assert string mapping on hand-built signals
cannot catch this.

**Proposed fix (not implementing):**

1. `touch()` only on **real progress**: new assistant text suffix, tool status
   transition, new/active child session, or scoped SSE event for *this* session.
2. Successful HTTP with identical payload must **not** touch.
3. Inject a clock (or test hook) so a unit test can advance quiet time without
   sleeping 120s.
4. Proof: hung fixture with repeating identical poll payloads →
   `stalled_no_progress` inside the quiet window, not wall `timeout`.

**Maps to S123:** Defeats F4 / F9 intent.

---

### CT-03 — Foreign sessions defeat scoping twice (high)

**Where:** AgentOS `OpenCodeSSEParser` + `OpenCodeServeClient.consumeSSEBus`.

**(a) Unscoped progress → watchdog reset**

`message.created` / `message.updated` always:

1. `recordMessage` (including foreign sessions), and
2. yield `.rawEvent`.

`default:` also yields `.rawEvent` for unknown types.

In `consumeSSEBus`, **any** yielded event sets `sawProgress = true` →
`idleGate.touch()`. Foreign traffic on the shared `/event` bus therefore resets
our stall timer.

**(b) Latched `foreignIdleDetected` aborts reconnect**

Foreign `session.idle` sets `foreignIdleDetected = true` (correct for the
signal). After a transient SSE drop, `consumeSSEBus` does:

```swift
if parser.foreignIdleDetected {
    await idleGate.signal()
    return
}
```

So after **any** other session on the serve goes idle (TUI, zombie from CT-01,
another seat), the next reconnect attempt terminates our healthy turn instead of
continuing. Terminal idle reason becomes `foreign_idle`.

**Proposed fix (not implementing):**

1. For scoped parsers: do not yield progress-driving events for foreign
   `message.*` / unknown types (or yield them without counting as progress).
2. Still record foreign message IDs if needed for part ownership — but do not
   `touch()` on them.
3. `foreignIdleDetected` must **not** abort the reconnect loop by itself.
   Use it only at final terminal classification when *our* session never went
   idle (S122 table), after deadline/stall — never as “stop reconnecting.”
4. Fixtures: foreign `message.created` must not reset stall; foreign idle + SSE
   drop must reconnect until local idle / stall / deadline.

**Maps to S123:** Defeats S123.1b reconnect; interacts with S122 foreign-idle.

---

### CT-04 — Outcome rewrite destroys classified worker reasons (high)

**Where:** AgentOS emits permission/session/prompt failures **before**
`emitTerminal`, but still stamps `OpenCodeTurnSignal` with a non-local
`idleReason` (often `.streamDrop` because `idleGate.signal()` was unclean).
Allnighter `RunService` then always runs `OpenCodeOutcomeAuthority.resolve` and
`apply`, which overwrite `errorKind` / `errorReason`.

**Evidence (AgentOS terminal branches):**

```swift
} else if parser.permissionAsk != nil {
    failed(.permissionRequired, "blockedOn: permission")
} else {
    Self.emitTerminal(signal: signal, done: done, failed: failed)
}
```

**Evidence (Allnighter rewrite):**

```swift
// RunService — sets run.blocker from pre-rewrite permission, then:
OpenCodeOutcomeAuthority.apply(verdict, to: &rewritten)
run.answers[0].result = rewritten
```

```swift
// OpenCodeOutcomeAuthority.resolve (mutating) — idleReason before preserving
// permissionRequired:
case .foreignIdle, .streamDrop, .timeout, .stalledNoProgress:
    return .failed(reason: classifiedFailure(for: signal.idleReason))
```

```swift
// apply always:
outcome.errorKind = .emptyOutput
outcome.errorReason = reason   // e.g. "stream_drop"
```

**Result:** Run-level `blocker` may still say permission, while the worker answer
reports retryable `stream_drop` / `emptyOutput`. AgentOS tests that assert
`blockedOn: permission` at the client layer stay green; no Allnighter test pins
the **post-rewrite** worker fields.

**Proposed fix (not implementing):**

1. Authority must not downgrade terminal kinds that are already classified
   (`permissionRequired`, nonzero session/prompt failures).
2. Or: clear/omit non-local `idleReason` when emitting those early terminals so
   resolve cannot invent `stream_drop`.
3. Prefer preserving `errorReason` text when status is already `.failed` with a
   human-action reason.
4. Allnighter test: permission terminal + signal `idleReason == .streamDrop` →
   post-rewrite still `permissionRequired` / `blockedOn: permission`.

**Maps to S123:** Undermines F8 observability goal.

---

### CT-05 — Doctor/smoke can kill a live serve outside the spawn lock (high)

**Where:** AgentOS `OpenCodeServeClient.smokeReason` →
`coordinator.ensureRunning()` with **no** `OpenCodeSpawnLock`.
`OpenCodeServeCoordinator.reclaimForeignListenerIfNeeded` SIGTERMs any listener
on `:4096` when **this process** has `spawnedPID == nil`.

**Evidence:**

```swift
public static func smokeReason(...) async -> String? {
    do { try await coordinator.ensureRunning() }
    ...
}
```

```swift
private func reclaimForeignListenerIfNeeded() async {
    guard await state.currentSpawnedPID() == nil else { return }
    guard let foreignPID = portListenerPID(Self.defaultPort), foreignPID > 0 else { return }
    Self.terminateProcess(foreignPID)  // SIGTERM then SIGKILL
}
```

`OpenCodeServeCoordinatorError.portOwnedByForeignProcess` exists and
`OpenCodeRoutingWorkerRunner` maps it, but **nothing throws it** — reclaim
kills instead.

Allnighter `ModelHealthChecker` calls `smokeReason` for OpenCode readiness.

**Also verified:** idle TTL (`idleTTLSeconds`, default 15 min) only sees activity
updated in `ensureRunning` / `touchActivity`. A long turn does not touch activity
during `streamRun`; a later `ensureRunning` (smoke or next seat) can reap the
owned child mid-flight if last touch is older than TTL.

**Proposed fix (not implementing):**

1. Smoke/doctor path must take `OpenCodeSpawnLock` (or a shared serve-lifecycle
   lock) before `ensureRunning`.
2. When a healthy listener exists and this process does not own it: **refuse**
   with `portOwnedByForeignProcess` (or “serve busy”) — never SIGTERM.
3. Reap only the child **this** coordinator spawned, and only when no turn holds
   the spawn lock / an explicit in-turn heartbeat is stale.
4. Proof: process A holds a long `streamRun`; process B `smokeReason` must not
   kill A’s serve.

**Maps to S123:** Bypasses F5 flock for lifecycle; dogfood concurrent/doctor
interference class.

---

### CT-06 — One spawn failure poisons the coordinator for process lifetime (high)

**Where:** AgentOS `SpawnState.claimSpawn` / `recordSpawnFailure` /
`attachLaunchedServe`.

**Evidence:**

```swift
func claimSpawn() -> Bool {
    guard spawnedPID == nil, !spawnInProgress, lastSpawnFailure == nil else { return false }
    ...
}
func recordSpawnFailure(_ error: ...) {
    ...
    lastSpawnFailure = error
}
// lastSpawnFailure cleared only in attachLaunchedServe
```

`releaseSpawn` / `handleChildExit` do **not** clear `lastSpawnFailure`. After one
failed launch, `claimSpawn` never returns true, so `attachLaunchedServe` never
runs, so the failure bit never clears. `ensureRunning`’s wait loop then always
throws the stored failure.

Invisible in one-shot CLI processes and in tests (fresh state). Fatal for Mac app
/ `alln serve` long-lived processes.

**Proposed fix (not implementing):**

1. Clear `lastSpawnFailure` on a cooldown, on next explicit retry, or inside
   `releaseSpawn` / failed-claim recovery.
2. Or: allow `claimSpawn` after failure once the error has been thrown to the
   caller (single-shot sticky bit).
3. Test: record failure → subsequent `ensureRunning` with healthy launch path
   succeeds.

---

### CT-07 — S122 `answerOnly` never reaches production invoke sites (high)

**Where:** Allnighter `RunService` hardcodes `openCodeIntent: .mutating` at all
three invoke sites (~1695, ~1753, ~1815). `OpenCodeRoutingWorkerRunner` forwards
`invocation.openCodeIntent ?? .mutating`. No other Allnighter producer sets
`.answerOnly`.

**Evidence:** Repo-wide search shows `.answerOnly` only in:

- AgentOS client API + unit tests
- Allnighter `OpenCodeOutcomeAuthority` branch + tests that construct signals

S122 archive marks D2 shipped; tests certify the dead `answerOnly` authority
branch. Deleting that branch would not change production behavior today.

**Proposed fix (not implementing) — needs product ruling:**

| Option | Behavior |
| --- | --- |
| **A** | Pass `.answerOnly` for observational / `--read-only` / non-mutating team shapes |
| **B** | Delete `answerOnly` from the public intent surface and simplify authority to mutating-only |
| **C** | Keep API for tests but document that Allnighter always mutates intent (honest doc) |

Recommend **A** if read-only Plan/Bug Hunt seats should use the S122 client
terminal table; otherwise **B** to stop lying in the archive banner.

---

### CT-08 — Sibling-repo external_directory bypasses write lock + dirty-tree gate (high / policy)

**Where:** AgentOS `OpenCodePermissionPolicy.autoApprovePermissionRules` +
`patternsAllowed` + runtime `"always"` reply on allow-listed
`external_directory` asks. Allnighter `repoDelta` / `worktreeDirty` observe only
the claimed run root.

**Verified:**

1. Default allow roots include both
   `~/Documents/GitHub/AgentOS` and `~/Documents/GitHub/Allnighter`.
2. Mutating runs rooted in Allnighter can auto-approve writes into AgentOS
   without holding AgentOS’s write-lock lane.
3. A run can settle `complete` with a clean claimed-root delta while files
   changed in the sibling repo.
4. `patternsAllowed` does no path normalization: a pattern whose string
   `hasPrefix(root + "/")` passes even with `..` segments after the root prefix
   (fail open).

**Not verified here:** whether OpenCode’s server-side matcher lets the leading
`permission: "*" / action: allow` rule cover `external_directory` without the
runtime ask handler (needs live serve).

**Ruling adopted (2026-08-07 dogfood):** auto-approve sibling `external_directory`
only when the caller also holds that root's write lock (or an explicit cross-root
grant). Code slice still open.

**Proposed fix (code slice — not yet implementing):**

1. Default: auto-approve sibling `external_directory` only when the caller also
   holds that root’s write lock (or an explicit cross-root grant).
2. Normalize paths before prefix checks (`URL.standardizedFileURL` /
   `resolvingSymlinksInPath`).
3. Reject `..` / over-broad trailing `*` patterns fail-closed.
4. Live probe for the wildcard-rule question before changing session-create
   rulesets.

---

### CT-09 — Permission asks with empty `sessionID` fail open (medium)

**Where:** `OpenCodeSSEParser.permissionAskEvents`:

```swift
if let scoped = scopedSessionID, !sessionID.isEmpty, sessionID != scoped {
    return []
}
```

Empty `sessionID` skips the foreign filter and is adopted as ours. Contrasts with
`session.error` / `session.idle`, which fail closed on missing session id.

**Proposed fix:** When scoped, missing/empty `sessionID` → drop (fail closed),
same as lifecycle events.

---

### CT-10 — Permission ask during SSE reconnect gap → misclassified stall (medium)

**Where:** Permission handling runs only inside `consumeSSEBus` on SSE chunks.
`pollSessionProgress` never inspects pending permissions.

**Verified shape:** An ask that lands while SSE is down is invisible until
reconnect; poll may keep touching (CT-02) or eventually stall/timeout instead of
`blockedOn: permission`. `try? await replyPermission` also swallows reply
failures.

**Proposed fix:** Poll path checks pending permission state (HTTP) or treats
unanswered ask as blocked; do not `try?`-swallow reply failures without
terminalizing.

---

### CT-11 — `parentID` capability probe incomplete (medium)

**Where:** `activeDelegationSessionIDs`:

```swift
let serveExposesParentID = sessions.contains { $0["parentID"] is String }
```

If the list has **no** child sessions yet, no `parentID` field appears → code
assumes “old serve” and falls back to the directory/created heuristic. A
concurrent root session in the same directory can look like our child; F1 is
only half-fixed.

**Proposed fix:** Probe schema once (sample session known to support `parentID`,
version endpoint, or sticky capability flag after first positive sighting) —
do not infer “no parentID support” from an empty/parent-only list.

---

### CT-12 — `DriverConcurrencyGate` timeout vs handoff race (medium)

**Where:** `DriverConcurrencyGate.acquire` uses a racing timeout task;
`release` transfers a slot by resuming the next waiter **without** a paired
acquire/release on the waiter side. If timeout wins the outer group after the
waiter was already resumed, the caller throws and never `release`s → lane wedged
(`active` stuck) for process lifetime.

**Proposed fix:** `defer { release }` only after ownership is confirmed; on
timeout, ensure cancel removes waiter **before** any handoff resume, or use a
generation token so a late resume is ignored. Add a regression test that races
timeout with release.

---

### CT-13 — Client vs authority reason precedence (medium)

**Where:**

- `emitTerminal`: `idleReason` first, then `promptEcho`
- `OpenCodeOutcomeAuthority.resolve` (mutating): `promptEcho` first, then
  `idleReason`

Same signal can surface `stream_drop` in one layer and
`incomplete_no_final_message` in the other. Fold into CT-04’s single precedence
table and pin with one shared fixture.

---

### CT-14 — Cross-process spawn lock proven only in-process (medium / proof)

**Where:** `OpenCodeSpawnLockTests.testSecondAcquireWaitsUntilFirstReleases`
uses two tasks in one process. That exercises `flock` on one host, but would
also pass if `flock` were replaced by an in-process lock.

**Proposed fix:** Add a proof that fails without real cross-process exclusion
(helper subprocess, or documented manual Works Test with two `alln` PIDs). Do
not treat the current unit test as sufficient for F5 closeout.

---

### CT-15 — S123 packet FIXED column / uncommitted polish (low / hygiene)

**Closed 2026-08-07:** parent [`OpenCode_Long_Run_Continuity.md`](OpenCode_Long_Run_Continuity.md)
F1–F10 table refreshed to match shipped CT fixes; F8/F10 confirmed committed.

---

## Rejected or unverified (do not implement from this packet)

| Claim | Disposition | Why |
| --- | --- | --- |
| Wildcard `permission: "*"` silently approves all `external_directory` | **Needs live serve** | Session-create ruleset shape is visible; OpenCode match precedence is not proven here |
| Exact-match prompt-echo gate is a bug | **Rejected as defect** | `OpenCodeServeClient.isPromptEcho` is exact normalized equality; S122 table encodes text-implies-done. Spec prose “approximately equal” is soft language, not a second algorithm |
| `ProjectRootScope` is an OpenCode bug | **Rejected** | Aggregate kill/ps scoping only; audit correctly listed it clean |
| Low noise (trimmed merge dupes, decorative `askTimeout`, ceiling-only gate test, etc.) | **Deferred** | Not blocking completion truth; revisit in deslop if still true after CT-01…04 |

---

## Recommended slice order (when authorized)

Do **not** start these until a founder/slice work order says so.

1. **Completion-truth trio (CT-01 + CT-02 + CT-03)** in AgentOS
   `OpenCodeServeClient` / `OpenCodeSSEParser` — one slice; they form a loop.
2. **CT-05** serve lifecycle / smoke kill outside lock.
3. **CT-04 + CT-13** Allnighter outcome rewrite honesty.
4. **CT-06** spawn-failure sticky bit.
5. **CT-07 / CT-08** product rulings, then code.
6. Mediums CT-09…12, CT-14 proof, CT-15 doc hygiene.

---

## Works Test (for future implementation — not run now)

Owner-visible claim after the trio lands:

> A long OpenCode turn with accumulated answer text but no session idle must not
> complete successfully; a hung turn with identical poll payloads must end as
> `stalled_no_progress` within the quiet window; foreign session traffic must
> neither reset that quiet window nor abort reconnect as `foreign_idle`.

Proof sketch:

1. Fixture/unit: poll completion predicates (CT-01/02).
2. Fixture/unit: foreign message + foreign idle during reconnect (CT-03).
3. Dogfood: two-process smoke vs long run must not SIGTERM (CT-05).
4. Allnighter unit: permission terminal survives authority rewrite (CT-04).

Waiver: none for claiming S123 closed.

---

## Explicitly clean (re-verified)

Agree with the audit on these — no defect filed:

- SSE part / idle / error session scoping for known message IDs (unknown drops)
- `isIdleSignal` JSON-parsed and session-scoped (no substring match)
- `OpenCodeSpawnLock` flock mechanics (fd lock + unlock ordering) as code
- `OpenCodeTurnSignal` shape / Codable surface
- `ProjectRootScope` (non-OpenCode)
- `GitObserver` within the claimed root
- RunService dirty-tree downgrade ordering relative to authority rewrite
- S122 regression suite intent (foreign-idle, prompt-echo, permission fail-fast,
  session-scoped parts) — still the strongest pin set; it does not cover CT-01…03

---

## Related docs

- Parent: [`OpenCode_Long_Run_Continuity.md`](OpenCode_Long_Run_Continuity.md)
- Baseline driver: [`setup/OpenCode_CLI_Support.md`](setup/OpenCode_CLI_Support.md)
- Archived honest-completion: [`../archive/phases/OpenCode_Headless_Completion_And_Session_Scoping.md`](../archive/phases/OpenCode_Headless_Completion_And_Session_Scoping.md)
- Audit receipt: `alln show 7E8E0930-FA7E-4345-8760-A2D386798B95 --json`
