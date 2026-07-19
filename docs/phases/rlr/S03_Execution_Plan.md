# RLR-S03 Execution Plan — durable activity truth · monotonic durable `seq` NDJSON · derived heartbeats · `--json` final-only

Status: **Architect recon + design (RLR-S03). No source changed to produce this.**
Read-only audit of branch `feat/design-chain` (HEAD `9414dcaf`, 2026-07-19).
SSOT: `docs/phases/Run_Lifecycle_Reliability.md` (FINAL) — laws **RLR-L6**
(activity vs heartbeat), **RLR-L7** (JSON + stream contracts), Current-state
items **3** + **8**, Works Test items **4** + **11**. Prior landed:
`rlr/S01_Execution_Plan.md` (`53510dc2`/`373baf63`/`704cb315`) +
`rlr/S02_Execution_Plan.md` (`7ff18d7b`/`84b42268`/`9655b6a1`).

**Headline:** the two pieces S03 needs already exist as separate, un-joined
substrates. (1) A **durable, flock-guarded, monotonic per-Mac `seq` allocator
with replay** — `RemoteRunEventJournal` — is live on the async path but the
`--stream` CLI seq is a throwaway in-memory counter. (2) An **activity signal**
exists as `RunEvent`s (`workerAnswerDelta`/`workerReasoningDelta`/`workerStatusChanged`/
`stage*`) **and** as `heartbeat.json`, but **neither is projected onto the run's
durable journal as pollable `lastActivityAt`**, and the stream **drops** every
activity event. S03 is **wiring + demotion**, not new machinery: project L6
activity onto `run.json`, retire `heartbeat.json` as truth, and give the stream
the durable `seq` the journal already mints.

---

## PART 1 — CURRENT-STATE MAP

### 1.1 `heartbeat.json` today — writers, readers, what phase/sequence mean

**Type:** `ProcessOwnership.ProgressHeartbeat`
(`AllnighterEngine/ProcessOwnership.swift:174`) =
`{ sequence: UInt64, phase: String, lastProgressAt: Date, touchedAt: Date }`,
one `heartbeat.json` per run dir. `phase` is a **free `String`**, a **third
vocabulary disjoint from `RunStatus` and `RunPhase`**: observed values
`"accepted" | "runner_starting" | "spawned" | "output" | "exited"` +
per-status-transition raw strings.

- **`sequence`** — monotonic per `recordProgress` call
  (`ProcessOwnership.swift:396-406`, `(previous?.sequence ?? 0) &+ 1`). The
  incident froze it at `sequence: 0` / `phase: "accepted"` — seeded but never
  advanced while a live child worked. **This is the exact lie S03 kills.**
- **`touchedAt`** — bumped by `touchHeartbeatFloor` (`:410`) **without** bumping
  `sequence`/`lastProgressAt`; seeds `{sequence: 0, phase: "accepted"}` when
  absent (`:416`).

**Writers:**
| Site | Call | Meaning |
| --- | --- | --- |
| `AsyncTeamService.swift:672` | `recordProgress(phase:"accepted", at: acceptedAt)` | acceptance seed (the frozen value in the incident) |
| `AsyncTeamService.swift:615` | `recordProgress(phase:"runner_starting")` | runner spawn |
| `AsyncTeamService.swift:729` | `recordProgress(phase: incoming.status.rawValue)` | **per durable status transition** (inside `persistDuringRun`) |
| `AsyncTeamService.swift:748` | `touchHeartbeatFloor` every `heartbeatIntervalSeconds`(=10s) | **per-tick timer floor task** (`heartbeatTask`, `:745-751`) |
| `RunStore.swift:74` | `touchHeartbeatFloor` on every `save` | floor touch on persist |
| `ProcessGroupCommandRunner.swift:95/99/106/120/206/219/227/243` | `ProgressTracker.note("spawned"/"output"/"exited")` → `recordTurnProgress` | cold subprocess stdout/stderr byte + exit; **writes to `TurnOwnerDirectory`, throttled 0.5s** (`ProgressTracker.diskThrottleSeconds`, `:345`) |

**Readers (all read `lastProgressAt`, never `sequence`/`phase` semantically):**
| Site | Use |
| --- | --- |
| `AsyncTeamService.status` `:788` | `response.lastProgressAt = lastProgressAt(in:)`; `:791` sets `response.progressStale` from `isProgressStale(in:)` when non-terminal + owner alive |
| `ProcessOwnershipSurface.swift:157/167`, `:235/262` | `ps` rows' `lastProgressAt` + `heartbeatAgeSeconds` |
| `ProcessGroupCommandRunner.swift:279` | `progress.effectiveLastProgressAt()` → `classifyProgressStall` → **idle-kill watchdog** (the in-process stall timer) |

**Idle-timer / watchdog vs the journal (Current-state item 3 — CONFIRMED):**
The stall/idle timers consume a **different** signal than any durable pollable
activity:
- **`ProcessGroupCommandRunner` stall watchdog** (`:277-304`): reads
  `ProgressTracker.effectiveLastProgressAt()` = `max(in-memory memoryLast, disk
  lastProgressAt, heartbeat mtime)` (`:368-382`). Its primary truth is the
  **in-process `memoryLast`** (bumped on every stdout/stderr chunk, `:347-361`);
  the disk file is a floor. Kills via `classifyProgressStall`
  (`ProcessOwnership.swift:467`). **This is a live in-process detector — it never
  reads `run.json`.**
- **`StalledWorkDetector`** (`AllnighterEngine/StalledWorkDetector.swift`): a
  scan-time detector that anchors stall age on `observableEvent(for: run)`
  (`:278-288`) = `max(workerAnswers.timing.finished/started, stages.finishedAt,
  run.createdAt)` — i.e. **worker-answer + stage timestamps, which only settle
  when a worker/stage completes**, not during a live token stream. So a run with
  a busy child but no settled answer looks "last active at createdAt."
- **`heartbeat.json`** is the only bridge between them, and it is a **separate
  file from `run.json`**, per-tick (10s floor), disjoint vocabulary. **Nothing
  writes `lastActivityAt` onto the durable journal today** (§1.4).

⇒ **Idle-timer activity ≠ durable pollable activity is CONFIRMED**: the idle
timer sees in-memory progress; a second process polling `run.json` sees neither
(no field) nor a trustworthy `heartbeat.json` (froze at seq 0).

### 1.2 Where worker activity signals surface in-process today

The P0 cold single-worker `alln run` path is `RunService`
(`AllnighterEngine/RunService.swift`). It emits a **rich** live `RunEvent` stream
via `emit(_:_:)` (`:662`), but the events are ephemeral (in-memory
`AsyncStream`) unless a consumer journals them:

| L6 kind | Source event(s) | Site | Reaches durable journal? |
| --- | --- | --- | --- |
| `message` (reasoning/answer) | `workerAnswerDelta`, `workerReasoningDelta` | `RunService.swift:818/824/911/918/953` | **No** — emitted to the `AsyncStream` only; dropped by LiveMapper (§1.3); never written to `run.json` |
| `child` (transition) | `workerStatusChanged`, `stageStarted/Completed`, `runStatusChanged` | `:790/800/981/1058/1067/1072` | Status changes persist via `persistDuringRun`→`store.save`; but no `lastActivityAt` field is set |
| `stdout`/`stderr` (bounded metadata) | `ProgressTracker.note("output")` | `ProcessGroupCommandRunner.swift:99/106/219/227` | Writes `heartbeat.json` only (throttled 0.5s), **into `TurnOwnerDirectory`, not the run journal** |
| `exit` | `ProgressTracker.note("exited")`; `workerStatusChanged→done/failed` | `PGCR:120/243`; `RunService:981` | `heartbeat.json` + status transition; no `lastActivityAt` |
| spawn (must NOT advance activity) | `note("spawned")`; worker OS identity | `PGCR:95/206` | advances `startedAt`/ownership only — correct per L6 |

**Cold vs warm capture:**
- **Cold** (`ProcessGroupCommandRunner`, P0 vertical): stdout/stderr chunk →
  `ProgressTracker.note` → `heartbeat.json`; `runStreaming` also yields
  `.stdout(data)`/`.stderr(data)` `CommandEvent`s (`:220/228`) up to
  `WorkerInvoker`, which re-emits them as `workerAnswerDelta`/`Reasoning`.
- **Warm** (`ProcessACPTransport`/`WarmWorkerPool`/`ACPSession`, **excluded from
  the P0 Works Test** by the S00 matrix): structured ACP messages surface as the
  same `workerAnswerDelta`/`Reasoning` events; **no** `ProgressTracker` /
  `heartbeat.json` path. S03 must key durable activity off the **event stream**,
  not off `heartbeat.json`, so warm runs get activity truth for free — but P0
  acceptance only asserts cold.

⇒ **The activity signals all exist in-process; none land on the durable journal
as `lastActivityAt`.** S03a's job is one projection: `RunEvent` → coalesced
`run.json.lastActivityAt/Kind`.

### 1.3 The NDJSON stream today — vocabulary, `seq`, drops, replay, terminal

`NDJSONStreamProjector` (`AllnighterCore/NDJSONStreamProjector.swift`). Two
producers:

**(a) `events(for: TeamRun)` / `lines(for:)`** (`:42-100`) — post-hoc projection
of a **settled** run. `seq` is a local `var seq = 0` incremented per `add`
(`:44-47`) — **restarts at 1 every call, not durable, not cross-attach.** Emits
`teamRunStarted` → per-worker `workerStarted`/`workerAnswered`/`workerFailed` →
`planStarted`/`planWritten` → exactly one terminal (`teamRunCompleted` or
`teamRunFailed`, `:82-93`). Terminal-exactly-once holds **for a settled run
snapshot**; it is not a live attachment model.

**(b) `LiveMapper`** (`:106-163`) — the **live** `--stream` path. Own in-memory
`private var seq = 0` (`:107`), `seq += 1` per mapped line (`:112`). Consumed by
`RunCLI.swift:93-96` (the real `alln run --stream`), `AllnighterCLI.swift:119`,
`TeamServiceStreamTests.swift:73`.

**`seq` today (RLR-L7 gaps):**
- **Not durable.** `LiveMapper.seq` lives in the CLI process for one attachment;
  a re-attach restarts at 1. Survives neither coordinator restart nor a second
  attach. RLR-L7 requires **monotonic durable `seq`**.
- **First event carries `runId`:** every event has `teamRunId` (`Event.init`,
  `:21`) — satisfied. But there is no explicit "first event carries runId"
  guarantee distinct from the rest, and no `replayed` marker.
- A **durable** monotonic seq **already exists elsewhere** — see §1.6.

**Where the stream drops events (Current-state item 3 — CONFIRMED):**
`LiveMapper.map` (`:118-161`) returns `nil` for every activity-bearing kind:
- `workerAnswerDelta` / `workerReasoningDelta` → **not matched → dropped**
  (no case). The live answer/reasoning tokens never reach the stream.
- `workerOutput`, `stageOutput` → **dropped**.
- `runStatusChanged` to intermediate states (`answers_in`/`planning`) → `nil`
  (`:137`) — intentional, but combined with the above the live stream shows only
  `teamRunStarted` + terminal, **no activity between**. "Stream drops
  tool/raw/started events in places" is confirmed: `started` (worker) survives,
  but all raw/token/tool activity is dropped.

**Attachment / replay:** **none exists** for the CLI stream. `LiveMapper` is a
single forward pass over a fresh `AsyncStream`; there is no attach/replay/
ack-and-close/gap-detection model. (Replay exists only for the **remote/iOS**
transport via `RemoteRunEventJournal.replay(after:)` + `RemoteSnapshotService`,
not for `--stream`.)

**Terminal-exactly-once:** for `events(for:)` a settled snapshot always ends in
exactly one terminal (`:82-93`). For `LiveMapper` the terminal is whichever
`runStatusChanged→terminal` arrives (`:129-135`); **exactly-one is not
structurally guaranteed** — two terminal status emits, or a terminal followed by
a late worker event, would each map to a line. No per-attachment terminal guard.

### 1.4 `--json` today — final-only?

**CONFIRMED final-only on the sync path.** `RunCLI.swift:101-121`:
`await service.run(request, …)` runs to completion, then prints **exactly one**
`TeamRunJSON` object (`:116`) or one `emitFailure` (`:104`). No interim writes
to stdout before terminal. The `--stream` branch (`:88-99`) is a **separate**
code path (NDJSON, never the final `--json` object) — the two are mutually
exclusive by flag. `alln team status --json` is a discrete one-shot read, not a
mid-run dribble. **No `--json` gap to fix; S03 only asserts it with a test**
(silence-until-terminal on `alln run --json`).

### 1.5 `TeamRun` / journal — existing activity-ish fields + the reserved names

`TeamRun` (`AllnighterCore/TeamRun.swift`):
- **No** `lastActivityAt`, `lastActivityKind`, `progressStale`, `ownerAlive`,
  `ownerHeartbeatAge` (grep clean). The only time-ish fields: `createdAt`
  (`:85`), `timing: RunTimingReport?` (`:117`, a stamp ladder for post-hoc
  inspection, not a pollable activity clock). **No `startedAt` stored field** —
  "started" is `createdAt` on the running mint (`RunService.swift:764/768/772`
  mints `.running/.working` with `createdAt: startedAt`).
- Landed earlier: `phase: RunPhase?` (`:70`, S01), `blocker: RunBlocker?`
  (`:137`) with S02 ticket facts (`holderId/holderKind/ticketPosition/
  holderAcquiredAt`, `:37-45`).

**Reserved wire names (S01c freeze).** `OwnershipProcessJSON`
(`AllnighterCore/OwnershipJSON.swift:24-30` doc-comment) explicitly reserves
**`lastActivityKind` / `progressStale` as owed by S03**, alongside `killOutcome`/
`contradiction` (S04). `OwnershipProcessJSON` today already carries
`lastProgressAt` (`:46`) + `heartbeatAgeSeconds` (`:48`) sourced from
`heartbeat.json` — S03 re-sources these from the journal and adds the two
reserved names. The status wire (`TeamStatusResponse`) already has
`lastProgressAt` (`AsyncTeamContracts.swift:146`) + `progressStale`
(set at `AsyncTeamService.swift:792`).

### 1.6 The durable `seq` substrate that already exists

`RemoteRunEventJournal` (`AllnighterEngine/RemoteRunEventJournal.swift`) — a
**Mac-truth, append-only, flock-guarded, monotonic per-Mac `seq` allocator with
replay**:
- `append(_ event:)` (`:41-55`) takes `ThreadFlockLock`, `nextSeq =
  lastSeqLocked() + 1`, stamps `event.seq`, persists to `remote_event_seq.txt`
  (`:33`), per-run `events(forRunId:)` NDJSON, and a global
  `remote_event_index.jsonl`. **Durable across process restart** (seq on disk).
- `replay(after: seq, limit:)` (`:69`) / `events(after:)` — **replay history
  from any seq**; `RemoteRunEventReplay{events, lastSeq}`; gap-detectable by
  `missingIndexedEvent(seq:…)`.
- `RunEvent` already carries `seq: Int64` (`RunEvent.swift:9`, "Monotonic
  per-Mac sequence number; clients persist the last seq seen").
- **Already live on the async path:** `AsyncTeamService.recordRemoteEvents`
  (`:767-778`) appends every coordinator `RunEvent` → durable seq. **NOT wired
  to `--stream`** (RunCLI's `LiveMapper` ignores `RunEvent.seq` and mints its
  own).

⇒ S03b does **not** build a durable seq store — it **routes `--stream` through
the one that exists** (or reads its allocated `RunEvent.seq`), and adds the
attach/replay/one-terminal envelope on top.

---

## PART 2 — EXECUTION PLAN (S03a → S03b → S03c, strict order)

Design spine (shared): **project, don't duplicate.** Durable activity is one new
projection of the existing `RunEvent` stream onto `run.json`; durable stream
`seq` is the existing `RemoteRunEventJournal` seq surfaced to `--stream`;
heartbeats and staleness become **read-time derivations** (the `heldSinceSeconds`
pattern), never per-tick journal writes. Every sub-slice is independently
committable + testable. Wire-freeze law: `OwnershipProcessJSON` field **names**
are frozen — **additions only** (`lastActivityKind`/`progressStale` were pre-reserved).

---

### S03a — durable activity projection on the journal + heartbeat demotion

**Goal:** `run.json` carries `lastActivityAt` / `lastActivityKind`, advanced
**only** by L6-qualifying events (bounded metadata, never raw payload/secrets),
**never** by spawn; `progressStale` / `ownerAlive` / `ownerHeartbeatAge` are
read-time derivations; `heartbeat.json` is retired as a truth source.

**Files + types:**

1. **New enum** `RunActivityKind` (`AllnighterCore/RunActivity.swift`):
   ```swift
   public enum RunActivityKind: String, Codable, Sendable, CaseIterable {
       case tool, message, stdout, stderr, child, exit
   }
   ```
   (`tool` reserved now for warm/ACP tool events; the P0 cold path produces
   `message`/`stdout`/`stderr`/`child`/`exit`.)

2. **`TeamRun` (`TeamRun.swift`) — additive optional fields** (legacy decodes
   `nil`; init params default `nil`; frozen names untouched):
   ```swift
   public var lastActivityAt: Date?      // advances ONLY on post-spawn L6 activity
   public var lastActivityKind: RunActivityKind?
   ```
   `startedAt`/ownership stay as-is; **spawn does not touch these** (RLR-L6
   negative-proof).

3. **The one projection function** (`RunActivity.swift`, pure, testable):
   ```swift
   static func activityKind(for event: RunEvent) -> RunActivityKind?
   ```
   maps `workerAnswerDelta`/`workerReasoningDelta` → `.message`;
   `workerStatusChanged`/`stageStarted`/`stageCompleted` → `.child`;
   `workerStatusChanged(to: done/failed)` / run-terminal → `.exit`;
   **returns `nil` for the spawn/`running` transition and for `runStatusChanged`
   to `queued`/`spawningWorker`** (spawn must not advance activity). stdout/stderr
   metadata is fed from `ProgressTracker` (edit 5), not from a `RunEvent`.

4. **Advance point — the emit/persist seam, coalesced.** In the coordinators'
   persist path (the `persistDuringRun`/`store.save` seam already on the live
   path — `AsyncTeamService.swift:723-731`, and `RunService`'s own persist), and
   at each `emit` in `RunService.emit` (`:662`), call a new
   `RunActivityRecorder.note(runId:, kind:, at:)` that:
   - updates an **in-memory** `lastActivityAt/Kind` immediately (feeds live
     detectors), and
   - **flushes to `run.json` at most once per `activityCoalesceInterval`**
     (default **1.0s**, a Core constant), **always flushing on kind-change and on
     terminal.** Reuses the exact `ProgressTracker` throttle discipline
     (`diskThrottleSeconds`) so chatty token streams do not thrash `run.json`
     (see write-amplification, below). The flush rides the existing `store.save`
     revision when one is already happening; otherwise a minimal activity-only
     save.

5. **stdout/stderr metadata → activity (bounded).** `ProgressTracker.note("output")`
   (`ProcessGroupCommandRunner.swift:99/106/219/227`) additionally calls
   `RunActivityRecorder.note(kind: .stdout/.stderr, at:)` with **only** timestamp
   (byte-count/worker-id may ride `lastActivityKind` context, **never raw
   bytes**). No stdout text touches `run.json` (non-goal: unbounded raw
   stdout/stderr in the journal).

6. **Read-time derivations (mapper layer — the `heldSinceSeconds` pattern, no
   stored booleans):**
   - `progressStale`: `now - lastActivityAt > idleBudget`; **absent (nil) before
     first post-spawn activity** (RLR-L6). Derive in `AsyncTeamStatusMapper`
     (replaces the `isProgressStale(in:)`/heartbeat read at
     `AsyncTeamService.swift:789-792`) and in `TeamRunJSONMapper`. `idleBudget`
     = the same source as `--idle-timeout` (driver manifest / `RunClockDefaults`).
   - `ownerAlive` / `ownerHeartbeatAge`: derive from `ProcessOwnership.isIdentityAlive`
     + `now - lastActivityAt` at projection; surface on status where the spec's
     `ownerAlive`/`ownerHeartbeatAge` are named.
   - `OwnershipProcessJSON` gains **`lastActivityKind: String?`** +
     **`progressStale: Bool?`** (pre-reserved names); `lastProgressAt`/
     `heartbeatAgeSeconds` re-source from `run.json.lastActivityAt`
     (`ProcessOwnershipSurface.swift:157/235`) instead of `heartbeat.json`.

7. **heartbeat.json fate — RETIRE AS TRUTH, demote the file to a debug artifact
   (recommended; see verdict).** Concretely:
   - Delete the **per-tick timer floor** (`AsyncTeamService.heartbeatTask`
     `:745-751`, `RunStore.save` touch `:74`) — this is the RLR-L6-banned
     per-tick write and the source of the `touchedAt`-advances-while-`sequence`-
     frozen lie.
   - Keep the **in-process `ProgressTracker`** (`ProcessGroupCommandRunner`) for
     the **idle-kill watchdog only** — it is a live in-process L8 detector, not
     durable pollable activity; it may keep an in-memory clock and (optionally)
     the file purely as a local debug trace, but **no external poller, `ps`, or
     `status` reads `heartbeat.json` after S03a.**
   - Repoint the readers (`AsyncTeamService.status:788-792`,
     `ProcessOwnershipSurface:157/235`) at `run.json.lastActivityAt`.

**Write-amplification guard (the explicit answer).** Activity is high-frequency
(one `workerAnswerDelta` per token). We **never** write `run.json` per token:
`RunActivityRecorder` bumps an **in-memory** clock on every L6 event but flushes
to the journal **≤ once per `activityCoalesceInterval` (1.0s)**, always flushing
on **kind-change** and **terminal**. This is the same discipline PERF-S01 already
applied to the GUI stream (`applyLiveDelta` + coalesced reload — no
full-reload/write per token) and that `ProgressTracker` applies to
`heartbeat.json` (0.5s). **Staleness tolerance:** a second-process poller may see
`lastActivityAt` up to ~1.0s stale — three orders of magnitude below the idle
budget (30–90 min), so `progressStale` is never falsely tripped. Bound:
**≤ 1 activity-driven `run.json` write / second / run**, on top of the
already-existing per-transition saves.

**Tests (Works Test 4, activity leg):**
- `RunActivityProjectionTests` (pure): `activityKind(for:)` totality over
  `RunEventKind`; spawn/`running`/`queued` → `nil`; delta → `.message`;
  worker-terminal → `.exit`.
- `testActivityAdvancesOnlyOnL6Events`: drive a fake-CLI cold run; assert
  `lastActivityAt` is `nil` after mint/spawn (before first post-spawn event),
  advances on the first `workerAnswerDelta`, and its `lastActivityKind` matches;
  assert spawn alone did **not** advance it.
- `testActivityWriteCoalesces`: N rapid deltas in < 1s → ≤ 1 `run.json`
  activity write (assert via save-count spy), but in-memory clock reflects the
  last.
- `testProgressStaleIsDerivedAndAbsentBeforeFirstActivity`: `progressStale ==
  nil` pre-activity; `true` after `now - lastActivityAt` exceeds a tiny injected
  budget; `false` otherwise.
- `testHeartbeatJsonNotReadForStatus`: with `heartbeat.json` frozen at
  `accepted/seq 0` but `run.json.lastActivityAt` advancing, `status`/`ps` report
  live progress (regression against the incident).

**Acceptance proof:**
```bash
swift test --package-path Packages/AllnighterCore --filter RunActivity
swift test --package-path Packages/AllnighterCore --filter ProcessOwnershipProgressStall
```

---

### S03b — monotonic durable `seq` on `--stream` + exactly-one-terminal + replay attach + gap detection

**Goal:** every `--stream` event carries a **durable monotonic `seq`** that
survives coordinator restart; first event carries `runId`; **exactly one terminal
per attachment**; **replay attach** replays history with events marked
`replayed`; gaps detectable by `seq`.

**Files + edits:**

1. **Source `seq` from the durable journal, not `LiveMapper`.** Route the
   `--stream` path (`RunCLI.swift:88-99`) through `RemoteRunEventJournal.append`
   (as the async path already does at `AsyncTeamService.swift:773`) so each
   `RunEvent` gets its **durable per-Mac `seq`** **before** projection. Change
   `NDJSONStreamProjector.LiveMapper` to **carry through `runEvent.seq`**
   (`:112-114`) instead of minting its own counter. The per-run event NDJSON
   (`events(forRunId:)`) becomes the durable stream log.
2. **First-event `runId` guarantee.** Ensure the first emitted line is a
   `teamRunStarted` (or a synthetic `streamAttached`) carrying `runId` — already
   true structurally; add an explicit invariant + test. `Event` already has
   `teamRunId` on every line (`NDJSONStreamProjector.swift:19`).
3. **Exactly-one-terminal per attachment (structural guard).** Add an attachment
   wrapper `NDJSONAttachment` that (a) forwards mapped lines, (b) tracks
   `didEmitTerminal`, (c) drops any post-terminal line, (d) guarantees a terminal
   is emitted exactly once when the run settles or the attachment closes. For an
   **ack-and-close** attach, **the ack IS the terminal** (RLR-L7).
4. **Replay attach + `replayed` marker + gap detection.** New attach mode:
   `RemoteRunEventJournal.replay(after: lastSeq)` (`:69`) → emit history with
   `Event.replayed = true` (new optional bool on `Event`, `NDJSONStreamProjector.swift:14-25`),
   then live-tail from `lastSeq+1`. Gap = consumer sees `seq` jump; expose the
   contiguity check (the journal already throws `missingIndexedEvent(seq:)`).
   This reuses `RemoteSnapshotService`'s resume shape — no parallel schema
   (RLR-L7 "no parallel run schema").
5. **`durable seq` design (2-sentence summary for PM, expanded here):** the
   stream's `seq` is the `RemoteRunEventJournal` per-Mac monotonic counter
   persisted in `remote_event_seq.txt` under a flock and stamped onto each
   `RunEvent` at `append`; because it is on disk and allocated before projection,
   a re-attach or a coordinator restart continues from `lastSeq` with no
   collision and no reset. Replay reads the same durable per-run NDJSON via
   `replay(after:)`, so history and live tail share one seq space.

**Tests (Works Test 4 stream leg + 11 non-kill legs):**
- `testStreamSeqIsMonotonicAndDurableAcrossReattach`: attach, capture seqs;
  re-attach → seqs continue (no reset to 1), first line carries `runId`.
- `testReplayAttachMarksReplayedThenLiveTails`: history events carry
  `replayed:true`, live events `replayed:false`, one contiguous seq run.
- `testExactlyOneTerminalPerAttachment` on **success / cancel / timeout**
  (drive fake CLI): exactly one `teamRunCompleted`/`teamRunFailed`; no
  post-terminal line. **Kill leg is GATED RED → S04** (see below).
- `testJsonIsFinalOnly`: `alln run --json` writes nothing to stdout until the
  single terminal object (asserts §1.4).

**Works Test 11 — the kill leg stays gated red for S04 (explicit).** "Exactly
one terminal NDJSON event on **kill**" depends on the **foreground-kill
settlement protocol** (RLR-L5): the *killer* stamps the terminal journal
revision and a **responsive coordinator** observes settlement and emits the
single terminal event before exiting. That stamper + `runtimeOwnership` +
contradiction surface are **S04**. S03b delivers exactly-one-terminal for
success/cancel/timeout (coordinator-driven terminals); the **kill** leg of Works
Test 11 must remain behind the `RLR_RED` gate until S04 wires the settlement
stamp. Do **not** green it in S03.

**Acceptance proof:**
```bash
swift test --package-path Packages/AllnighterCore --filter NDJSONStreamProjector
swift test --package-path Packages/AllnighterCore --filter TeamServiceStream
RLR_RED=1 swift test --package-path Packages/AllnighterCore --filter RunLifecycleTwoProcess  # (a) green, (b)+kill-terminal red → S04
```

---

### S03c — wire the dropped activity events into the live stream (bounded)

**Goal:** the `--stream` stays **live** — it emits activity between `started` and
terminal — without putting unbounded raw stdout/stderr in the journal.

**Files + edits:**

1. **Map the currently-dropped kinds in `LiveMapper.map`
   (`NDJSONStreamProjector.swift:118-161`):**
   - `workerAnswerDelta` / `workerReasoningDelta` → a new public
     `workerActivity` NDJSON event carrying **bounded metadata only**
     (`workerId`, `kind: message`, `ts`, optional `byteCount`/`charCount`) —
     **never the raw token text** (non-goal). This is the "raw/tool/started
     events the stream drops" fix, projected as metadata.
   - `workerOutput`/`stageOutput` → `workerActivity`(`kind: stdout`) /
     `stageActivity` metadata.
   - `stageStarted`/`stageCompleted` already mapped (`:155-158`) — keep.
2. **Contract + docs:** add `workerActivity` (and `Event.replayed`) to the
   NDJSON contract in `ContractSchema.swift` / the generated stream schema;
   regenerate `docs/generated/alln/*`; extend the contract-drift/parity test.
   Keep `EventData` additive (all-optional keys, omitted-on-encode — the existing
   discipline at `NDJSONStreamProjector.swift:27-40`).
3. **Reconcile with S03a:** `workerActivity` is the **stream** projection of the
   same L6 event that advances `run.json.lastActivityAt`; both read the one
   `RunActivity.activityKind(for:)` classifier so stream and journal never
   disagree about what counts as activity.

**Non-goal restated:** no raw stdout/stderr/token payload in `run.json` or the
NDJSON stream — only bounded metadata (ts, byte/char count, worker id, kind).

**Tests:**
- `testStreamEmitsWorkerActivityBetweenStartAndTerminal`: fake CLI dribbles
  deltas → stream shows ≥1 `workerActivity` line with monotonic `seq`, no raw
  text, before the single terminal.
- `testStreamCarriesNoRawPayload`: assert no `workerActivity` line contains the
  delta text.
- `ContractDrift` green after regen.

**Acceptance proof:**
```bash
swift test --package-path Packages/AllnighterCore --filter NDJSONStreamProjector
swift test --package-path Packages/AllnighterCore --filter Contract
bash scripts/check.sh
```

---

## RISKS

**Consumers of `heartbeat.json` (retire-as-truth blast radius):**
- **`ps`** (`ProcessOwnershipSurface.swift:157/167/235/262`) — reads
  `lastProgressAt`/`heartbeatAgeSeconds`. Re-sourced to `run.json.lastActivityAt`
  in S03a; `ps` output shape unchanged (same field names, better truth).
- **`alln team status`** (`AsyncTeamService.swift:788-792`) — `lastProgressAt` +
  `progressStale` re-derived from journal. Wire shape unchanged.
- **Idle-kill watchdog** (`ProcessGroupCommandRunner.swift:277-304` via
  `effectiveLastProgressAt`) — **keep** its in-process `ProgressTracker` clock;
  it is a live L8 detector, not a durable poller. **Do not** starve it by
  deleting `ProgressTracker`; only delete the per-tick **floor timer**
  (`AsyncTeamService.heartbeatTask`, `RunStore.save` touch). Getting this wrong
  either (a) leaves the banned per-tick write, or (b) breaks idle-kill.
- **`StalledWorkDetector`** (`observableEvent(for:run)` `:278-288`) — should also
  read `run.json.lastActivityAt` instead of the settled-answer/stage timestamps,
  else GUI stall detection stays blind mid-token (recommended follow-through in
  S03a; low risk if deferred, but it is the same "activity ≠ pollable" bug).
- **Relay/pilot watchdog** — verify no relay path reads `heartbeat.json`
  directly (grep shows only the above readers; **UNDETERMINED for any
  out-of-tree relay tooling** — I checked `Packages`/`Apps` only).

**Stream consumers expecting the current event shapes:**
- **GUI streaming** (`ThreadsViewModel.applyLiveDelta`) consumes `RunEvent`
  directly, **not** the NDJSON projection — unaffected by LiveMapper changes, but
  it will now *also* see `workerActivity` is redundant (GUI already renders
  deltas). Confirm no double-render.
- **Remote/iOS snapshot** (`RemoteSnapshotService`/`RemoteRunEventJournal`) —
  S03b **shares** its durable seq + replay; verify routing `--stream` through the
  journal does not double-append (the async path already appends at `:773`; the
  sync `--stream` path must append **once**, not twice).
- **`--stream` scripted callers** relying on "only started + terminal" would now
  see interleaved `workerActivity` lines — additive, but a strict parser that
  rejects unknown `event` names would break. Mitigation: additive contract + regen
  + drift test; `workerActivity` documented as skippable.

**Top 3 risks:**
1. **Retiring `heartbeat.json` while the idle-kill watchdog still needs a live
   clock.** The file conflates two jobs — durable pollable activity (move to
   `run.json`) and the in-process idle timer (keep in `ProgressTracker`). Delete
   the wrong half and you either keep the RLR-L6-banned per-tick write or you
   disarm the idle-timeout that stops hung workers. Mitigation: S03a deletes
   **only** the floor-timer writes and repoints **only** the external readers;
   the `ProgressTracker` in-memory clock stays; covered by
   `testHeartbeatJsonNotReadForStatus` + an idle-kill regression.
2. **Write-amplification on `run.json` from token-rate activity.** Without the
   coalescing guard, one `workerAnswerDelta` per token = hundreds of atomic
   `run.json` writes/sec, thrashing disk and racing the S02 blocker/phase saves
   in the same file. Mitigation: `RunActivityRecorder` in-memory clock + ≤1
   flush/1.0s (+ always on kind-change/terminal), ride the existing save
   revision; asserted by `testActivityWriteCoalesces`. Staleness tolerance ≈ 1s,
   far under the idle budget.
3. **The S04 boundary — activity truth must not pretend to fix kill
   verification.** S03 makes the run *observably alive*; it must **not** stamp any
   terminal, touch `runtimeOwnership`, or claim a run *stopped*. The kill leg of
   Works Test 11 (exactly-one terminal on kill) and the terminal-lie signature
   (b) **stay gated red for S04**. Risk: a tempting "the coordinator saw exit,
   just stamp terminal on kill" shortcut in S03b would re-introduce the S00
   terminal-lie. Mitigation: S03b's one-terminal guard covers only
   success/cancel/timeout (coordinator-driven); the kill terminal is explicitly
   left to S04's settlement stamper.

---

## Verdicts (for PM)

- **`heartbeat.json` fate (3 sentences):** Retire it **as a truth source** and
  demote the file to an optional local debug artifact — durable pollable activity
  moves onto `run.json` as `lastActivityAt`/`lastActivityKind`, written coalesced
  from L6 events only, and `progressStale`/`ownerAlive`/`ownerHeartbeatAge` become
  read-time derivations (the `heldSinceSeconds` pattern), matching the spec's
  truth-owners table (RunStore/TeamRun is truth) and RLR-L6 (heartbeats are never
  per-tick journal writes). The RLR-L6-banned **per-tick floor timer**
  (`AsyncTeamService.heartbeatTask`, `RunStore.save` touch) is deleted, killing
  the incident's "`touchedAt` advances while `sequence` frozen at 0" lie. The
  in-process `ProgressTracker` clock **stays** — it feeds the idle-kill watchdog
  (a live L8 detector), which is not durable pollable activity and needs no
  journal.
- **Durable `seq` design (2 sentences):** `--stream`'s `seq` becomes the existing
  `RemoteRunEventJournal` per-Mac monotonic counter — persisted in
  `remote_event_seq.txt` under a flock and stamped onto each `RunEvent` at
  `append` before projection — so a re-attach or coordinator restart continues
  from `lastSeq` with no reset or collision, replacing the throwaway in-memory
  `LiveMapper.seq`. Replay attach reads the same durable per-run NDJSON via
  `replay(after:)`, so history (marked `replayed`) and live tail share one seq
  space and gaps are detectable by seq contiguity — no parallel schema.
- **Sub-slices:**
  - **S03a** — durable `lastActivityAt`/`lastActivityKind` on `run.json` from L6
    events only (spawn excluded), coalesced writes, `progressStale`/`ownerAlive`/
    `ownerHeartbeatAge` derived at read time, `heartbeat.json` retired as truth.
  - **S03b** — route `--stream` through the durable `RemoteRunEventJournal` seq;
    exactly-one-terminal per attachment; replay attach with `replayed` marking +
    gap detection; confirm `--json` final-only.
  - **S03c** — project the currently-dropped delta/output/stage events as bounded
    `workerActivity` NDJSON metadata (no raw payload) so the stream is live;
    contract regen + drift.
- **Write-amplification answer:** in-memory activity clock bumps on every L6
  event; `run.json` flushes **≤ once per 1.0s coalesce interval** (always on
  kind-change + terminal), riding the existing `store.save` revision — same
  discipline as PERF-S01's coalesced stream and `ProgressTracker`'s 0.5s throttle.
  **Bound: ≤ 1 activity write/sec/run; staleness tolerance ≈ 1s**, ~3 orders of
  magnitude below the 30–90 min idle budget, so `progressStale` never false-trips.
- **Top 3 risks:** (1) retiring `heartbeat.json` without starving the in-process
  idle-kill watchdog (delete only the floor-timer + external readers, keep the
  `ProgressTracker` clock); (2) `run.json` write-amplification at token rate
  (coalesce ≤1/s, ride existing saves); (3) the S04 boundary — S03 must observe,
  never stamp: the kill leg of Works Test 11 and terminal-lie (b) **stay gated red
  for S04**, no "coordinator saw exit → stamp terminal on kill" shortcut.
- **`--json` — already final-only** (`RunCLI.swift:101-121`); S03 only adds the
  silence-until-terminal assertion, no behavior change.
- **UNDETERMINED (what I checked):** whether any out-of-tree relay/pilot tooling
  reads `heartbeat.json` directly — grep of `Packages/`+`Apps/` shows only the
  four readers named above; I did not scan outside the repo. Whether routing sync
  `--stream` through the journal risks a double-append vs the async path's
  existing `:773` append — the sync path currently does **not** append, so S03b
  adds exactly one appender, but the PM should confirm no code path drives both.
