# CR-07 — StalledWorkDetector worker-turn scan: slow-GLM false-positive risk

## Summary
`scanWorkerTurns` applies a single 30-min `workerChatSeconds` threshold to every
`.workerChat` turn, with no per-run or per-model differentiation. For slow GLM
pair slices (Supervisor + Hammer) that legitimately run 30-60+ min, the
false-positive behavior hinges entirely on whether the un-inlined
`observableEvent(for:thread:)` resets on worker progress signals. The function
also ignores `input.runs` entirely, so it cannot apply pair-team-aware
thresholds or parent/child turn policy even though that metadata is already in
the input.

## Findings

### P0 — None
No invariant or security violation is visible in the inlined source (lines
1-77). The function is a pure, stateless scan with no mutation, no I/O, and no
credential/privacy surface. The issues below are correctness/UX false-positives,
not invariant breaks.

### P1 — Single global threshold can't distinguish slow GLM pair slices from real stalls

- **Invariant:** A legitimately-progressing long run must not be reported as
  `.runningNoProgress` (AGENTS.md: "A failed worker is shown failed, never
  faked" — by symmetry, a progressing worker must not be shown stalled).
- **Evidence:** `StalledWorkDetector.swift:3-9` (`workerChatSeconds: Int = 30 *
  60` is a single field, no per-run override); `StalledWorkDetector.swift:64`
  (`guard age >= TimeInterval(thresholds.workerChatSeconds) else { continue }`
  applies it uniformly); `StalledWorkDetector.swift:67` (`reason: ...
  .runningNoProgress` is emitted purely from age + status, no progress signal).
- **Suggested fix:** Add an optional per-run threshold override looked up from
  `input.runs` by `turn.runId`, or a `runKind`/`posture` field on the threshold
  struct so pair-team (Supervisor+Hammer) runs can carry a longer window (e.g.
  90 min) without weakening detection for normal Claude Code turns.
- **Suggested slice:** SWW-S03: per-run stalled-work thresholds

### P1 — `input.runs` is available but unused; pair-team parent/child policy impossible

- **Invariant:** Worker-turn scanning should be run-aware so a parent supervisor
  turn waiting on an active hammer child, or a queued hammer child waiting on
  sequential dispatch, is not flagged as stalled-by-design.
- **Evidence:** `StalledWorkDetector.swift:22-28` (`StalledWorkScanInput` carries
  `runs: [TeamRun]`); `StalledWorkDetector.swift:44-76` (`scanWorkerTurns` reads
  `input.threads`, `input.pendingItems`, `input.now` — never `input.runs`).
  Contrast: `scan` at line 38 also calls `scanTeamRuns`, which by name consumes
  `input.runs`, so the same pair-team work is scanned under two policies.
- **Suggested fix:** In `scanWorkerTurns`, resolve `turn.runId` against
  `input.runs` to (a) skip `.queued` turns whose parent run is still `.running`
  and dispatching sequentially, and (b) apply a pair-team threshold when the
  run's posture/kind indicates Supervisor+Hammer.
- **Suggested slice:** SWW-S04: pair child run suppression in worker-turn scan

### P1 — False-positive risk hinges on un-inlined `observableEvent` reset policy

- **Invariant:** A turn actively emitting tokens/heartbeats must reset its stall
  clock; otherwise any run longer than `workerChatSeconds` is flagged regardless
  of liveness.
- **Evidence:** `StalledWorkDetector.swift:58` (`let lastEvent =
  observableEvent(for: turn, thread: thread)`); `StalledWorkDetector.swift:59`
  (`let age = input.now.timeIntervalSince(lastEvent.at)`);
  `StalledWorkDetector.swift:64` (`guard age >=
  TimeInterval(thresholds.workerChatSeconds)`). The `observableEvent`
  implementation is below line 77 and not inlined, so its reset policy cannot be
  verified in this review.
- **Suggested fix:** Confirm `observableEvent` resets `lastEvent.at` on every
  worker progress signal (token delta, heartbeat, partial-message append, status
  transition). If it only anchors on turn start or last user message, every GLM
  pair slice >30 min false-positives. Add a unit test asserting a turn that
  emitted a token at T+29min is not flagged at T+31min.
- **Suggested slice:** SWW-S05: observableEvent progress-reset proof

### P2 — `firstDetectedAt: input.now` re-stamps on every scan

- **Invariant:** `firstDetectedAt` should name the first scan that detected the
  stall, not the current scan.
- **Evidence:** `StalledWorkDetector.swift:71` (`firstDetectedAt: input.now`)
  inside the per-turn loop; `idFactory` at line 69 mints a fresh ID per
  emission, so repeated scans of the same stalled turn produce distinct episodes
  with ever-advancing `firstDetectedAt`.
- **Suggested fix:** Either dedup upstream by `targetId` and preserve the
  earliest `firstDetectedAt`, or rename the field to `lastDetectedAt` /
  `scannedAt` if the caller treats each emission as transient.
- **Suggested slice:** (nit, fold into SWW-S03)

### P2 — Wake ticket suppression may not cover nil `runId` worker chats

- **Invariant:** A worker chat turn that is not part of a team run (`runId ==
  nil`) should still be suppressible by a thread-scoped wake ticket.
- **Evidence:** `StalledWorkDetector.swift:55`
  (`suppressedByWakeTicket(pending:input.pendingItems, threadId:thread.id,
  runId:turn.runId, now:input.now)`). `turn.runId` is optional; if
  `suppressedByWakeTicket` requires a non-nil `runId` to match, project-less /
  non-team worker chats can't be suppressed.
- **Suggested fix:** Confirm `suppressedByWakeTicket` falls back to thread-only
  matching when `runId` is nil. (Cannot verify — impl not inlined.)
- **Suggested slice:** (nit)

## False alarms ruled out
- `guard let projectId = thread.projectId else { continue }` (line 48): skipping
  project-less threads is correct — a stall episode needs a project scope to act
  on. Not a bug.
- `if turn.requiresUserAttention { continue }` (line 53): skipping user-blocked
  turns is correct — those are waiting on the user, not stalled. Even if they
  sit for hours, flagging them as "stalled work" would mislabel a user-action
  item. Not a bug.
- `age >= TimeInterval(thresholds.workerChatSeconds)` (line 64): using `>=`
  (tripping at exactly 30:00) is fine — off-by-one-second at the boundary is
  noise, not a defect.
- Negative `age` from clock skew: if `lastEvent.at` is slightly after
  `input.now`, `age` is negative and the `>=` guard fails, so no false positive.
  Safe.
- `reason` binary classification (line 67): `.queued` → `.queuedNoStart`,
  `.running` → `.runningNoProgress` is correct for the two admitted statuses
  (the `guard` at line 51 already excluded everything else).

## Greps avoided
No repo exploration performed. Review used only the inlined source
(StalledWorkDetector.swift lines 1-77) and the resolved-symbol list.
`observableEvent`, `suppressedByWakeTicket`, `makeEpisode`, `scanTeamRuns`,
`WorkThread`, `TeamRun`, `PendingItem`, `StallEpisode`, and `StallReason`
implementations were not read per the read-only constraint; findings that depend
on them are flagged as "cannot verify" and framed as confirm-or-fix items.