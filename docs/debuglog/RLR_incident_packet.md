# RLR-S00 DEBUGLOG incident packet — original field hang + 2026-07-19 re-hang

Status: evidence only (RLR-S00 deliverable). No product/source changes were
made while gathering this packet. SSOT: `docs/phases/Run_Lifecycle_Reliability.md`
(status FINAL) — "Founder intent", "Risk and debugger classification", "Current
state (verified 2026-07-19)".

Evidence source: `/Users/mike/Library/Application Support/Allnighter` (read-only
inspection; nothing was deleted, moved, or rewritten). All three run ids named
in the spec's provenance line were found on disk:

| Run id (spec label) | Path found |
| --- | --- |
| `8AAA520D-1BB0-431C-803B-0D479B7653B6` | `Runs/run_8AAA520D-1BB0-431C-803B-0D479B7653B6/` (`run.json`, `heartbeat.json`, `owner.json`) |
| `BD26C1D1-7CBE-4F96-B1C5-B353DF143C92` | `Runs/run_BD26C1D1-7CBE-4F96-B1C5-B353DF143C92/` (`run.json`, `heartbeat.json`, `owner.json`) |
| `2ADCE96A-A095-4B5D-8DFB-20FDF1AE130F` | `Runs/run_2ADCE96A-A095-4B5D-8DFB-20FDF1AE130F/` (`run.json`, `heartbeat.json`, `events.jsonl`, `bundle.md`, `workers/*`) — the Spec Review Min run that reviewed this very doc |

**Important honesty note before the incident narrative:** every timestamp found
for `8AAA520D` and `BD26C1D1` is **2026-07-19**, and the two journals are only
**4 seconds apart** (`8AAA520D.finishedAt` `07:58:01Z`→`08:09:36Z`;
`BD26C1D1.createdAt` `08:09:40Z`). I could not find any earlier-dated journal
for either id, nor any other run journal that looks like a separate,
older "original field hang." I am not able to confirm on disk that the
"original field hang" (Founder intent) and the "re-hang reproduced 2026-07-19"
(Current state) are two temporally separate incidents rather than the same
2026-07-19 session narrated twice in the spec (first occurrence, then a
deliberate reproduction 4 seconds later). Where the spec's own prose
distinguishes them, I have kept the same Incident A / Incident B split below,
but the on-disk evidence reads as one continuous session. I am stating this
explicitly rather than inventing a separate pre-2026-07-19 artifact I did not
find.

---

## Incident A — original field hang (`8AAA520D-…`)

### Timeline (from `run.json` / `heartbeat.json` / `owner.json`)

| Time (UTC) | Event |
| --- | --- |
| `2026-07-19T07:58:00Z` | `timing.events`: `run.requested` → `worker.resolve.start` → `worker.resolve.end` → `driver.command.resolved`, all in the same second |
| `2026-07-19T07:58:01Z` | `createdAt`; `heartbeat.json` written: `phase: "accepted"`, `sequence: 0` |
| *(no further heartbeat writes found — file's mtime never advances past this)* | |
| `2026-07-19T08:09:36Z` | `finishedAt`; `status: "failed"`, `endReason: "cancelled"` |

Elapsed accepted→cancelled: **~11m35s** (spec rounds this to "12+ minutes").

### Observed signatures (quoted, bounded)

`heartbeat.json` (full file, 129 bytes):

```json
{
  "lastProgressAt" : "2026-07-19T07:58:01Z",
  "phase" : "accepted",
  "sequence" : 0,
  "touchedAt" : "2026-07-19T07:58:01Z"
}
```

`owner.json` (full file, 82 bytes) — the **only** OS identity ever durably
recorded for this run:

```json
{
  "kind" : "inProcess",
  "pid" : 73790,
  "startTimeTicks" : 1784447880783468
}
```

`run.json` worker-answer tail (the operator's own after-the-fact annotation):

```json
"workerAnswers": [
  {
    "memberId": "model_kimi_k3#0",
    "modelId": "model_kimi_k3",
    "result": { "status": "cancelled", "errorReason": "operator cancelled orphaned fanning_out run" },
    "role": "answer"
  }
]
```

Request shape (from `run.json`): single-worker `model_kimi_k3` (`kimi-code/k3`),
`lane: "code"`, `effort: "high"`, `presetId: "default_chat"`, `teamDisplayName:
"Default Team"` — i.e. a one-worker, non-team `alln run` invocation, matching
the trusted-workflow-slice shape the spec targets (not a multi-worker team).
Note: the run's persisted `lane` field reads `"code"`, not `"design"` as in the
founder-intent command-line example quoted in the spec — I flag this
discrepancy rather than silently reconciling it; either the field example is
illustrative, or lane resolution changed the value between CLI input and
journal.

**What could not be recovered:** no `events.jsonl` exists for this run (only
`run.json`/`heartbeat.json`/`owner.json`), so there is no append-only transition
log to show intermediate `status`/`phase` values during the live 11m35s window
— only the pre-hang acceptance facts and the post-cancel terminal state. No
`workers/` subdirectory exists (contrast `2ADCE96A`, which has a full
`workers/*.answer.md` / `*.metadata.json` / `*.prompt.md` set) — no
worker-level prompt, answer, or metadata was ever durably captured for the
`kimi-code` child. There is no captured stdout/stderr from the `kimi-code`
process itself, and no raw CLI transcript of the `alln kill --all` invocation
that ended this run (its outcome is described only via the operator's
`errorReason` annotation, not a machine-recorded `KillOutcome`).

### Strongest single piece of evidence

`owner.json` contains **only** the coordinator's `inProcess` identity
(`pid`/`startTimeTicks`) — there is no second, worker-scoped identity record
anywhere in the run directory. Combined with the missing `workers/`
subdirectory, this proves the run never reached a point where the spawned
`kimi-code` child's OS identity (pid/pgid) was durably recorded *anywhere* in
the journal. This is the mechanical reason a kill path that only walks
recorded ownership has nothing worker-specific to signal — it directly
corroborates spec "Current state" item 4: "Coordinator `.inProcess` owner is
recorded; worker pgid is not durably attached for external kill." Grep
confirms `runtimeOwnership` (the spec's proposed per-worker record, L5) does
not exist in source today — only the single coordinator `owner.json`
(`Packages/AllnighterCore/Sources/AllnighterEngine/ProcessOwnership.swift:18`,
`ownerFileName = "owner.json"`).

---

## Incident B — re-hang reproduced 2026-07-19 (`BD26C1D1-…`)

### Timeline

| Time (UTC) | Event |
| --- | --- |
| `2026-07-19T08:09:40Z` | `createdAt` — 4 seconds after `8AAA520D` was stamped `finishedAt`; `heartbeat.json` written: `phase: "accepted"`, `sequence: 0` |
| *(heartbeat never advances)* | |
| `2026-07-19T08:26:21Z` | `finishedAt`; `status: "failed"`, `endReason: "cancelled"` |

Elapsed accepted→cancelled: **~16m41s**.

### Observed signatures (quoted, bounded)

`heartbeat.json` (full file, 129 bytes):

```json
{
  "lastProgressAt" : "2026-07-19T08:09:40Z",
  "phase" : "accepted",
  "sequence" : 0,
  "touchedAt" : "2026-07-19T08:09:40Z"
}
```

`owner.json` (full file, 82 bytes) — again the only recorded identity, a
different coordinator process than Incident A's:

```json
{
  "kind" : "inProcess",
  "pid" : 75000,
  "startTimeTicks" : 1784448580668358
}
```

`run.json` worker-answer tail — this one is explicitly self-labeled as a
reproduction attempt, not an accidental repeat:

```json
"workerAnswers": [
  {
    "memberId": "model_kimi_k3#0",
    "modelId": "model_kimi_k3",
    "result": {
      "status": "cancelled",
      "errorReason": "operator cancelled: no progress after 16m (RLR field-failure reproduction)"
    },
    "role": "answer"
  }
]
```

Same request shape as Incident A: single-worker `model_kimi_k3`
(`kimi-code/k3`), `lane: "code"`, `effort: "high"`, `presetId: "default_chat"`.

**`kill --all` / lane-holder claims — what is and is not corroborated on
disk:** the spec's account ("`kill --all` → `killedCount: 0` while the lane
holder still named the dead coordinator pid") is not backed by a stored CLI
output artifact — `alln kill --all`'s stdout is not journaled anywhere I could
find, and I did not locate a log of that specific invocation. This detail
rests on the spec's own provenance line and the PM handover text for this
slice, not an independently recoverable file. I am stating this rather than
fabricating a matching kill-output artifact.

Separately, and **not** verified as causally connected to this specific run:
`Lanes/` (`AllnighterPaths.lanes`, keyed by canonical-root lane key per
`ExecutionLaneFlock.swift`) contains a `holder.json` for lane key
`d18746ae6151216e` naming holder `pid 54116`, `acquiredAt:
"2026-07-18T21:20:27Z"` — i.e. a lock acquisition that predates both
`8AAA520D` and `BD26C1D1` by roughly 10.5 hours and was never observed to
release in the files inspected. `ps -p 54116` at the time of this
investigation still shows a live process (an `xctest` invocation), but I
cannot confirm from static files alone whether this is the same process that
acquired the lane in in the first place or a reused pid — `startTimeTicks`
vs. wall-clock `lstart` were suggestively close but not something I can
verify without live identity-alive tooling (exactly the ambiguity RLR-L5's
`pid ∧ startTimeTicks ∧ non-zombie` check exists to resolve). I flag this as
supporting context for the "orphan lane holder" signature class in general,
**not** as proven evidence specific to Incident B — the `8AAA520D`/`BD26C1D1`
journals never show `phase: "waitingForWriteLock"`, so they were not observed
blocked on this particular lock; they froze at `accepted` before any lock-wait
or spawn signature would show up in the journal fields I have access to.

**What could not be recovered:** same gaps as Incident A — no `events.jsonl`,
no `workers/` subdirectory, no raw `kimi-code` stdout/stderr, no machine
`KillOutcome` record, no captured `alln kill --all` output.

### Strongest single piece of evidence

The `heartbeat.json` for `BD26C1D1` is byte-for-byte structurally identical to
`8AAA520D`'s (`phase: "accepted"`, `sequence: 0`, never advancing) despite the
run living **16m41s** instead of ~11m35s — proving the freeze is not a
one-off timing fluke but a deterministic reproduction of the same signature
under the same request shape (`model_kimi_k3`, `lane: code`, `effort: high`,
`default_chat`) 4 seconds after the first occurrence was cancelled. Combined
with the identical "coordinator-only, no worker identity" `owner.json` shape,
this is the clearest evidence that the bug is structural (nothing advances
`heartbeat.sequence` or writes a `workers/` artifact between accept and
spawn/first-activity for this request shape), not environmental noise from
one bad run.

---

## Signature classes → spec's lie-prone layers

The spec ("Risk and debugger classification") names lie-prone layers:
`fanning_out`, status projection, `ps`, `kill`, silent `--json`, streams
without activity, orphan lane holders after coordinator death. Mapping what
was actually observed on disk to each:

| Observed signature | Spec's lie-prone layer | Evidence |
| --- | --- | --- |
| `heartbeat.phase: "accepted"`, `sequence: 0`, frozen for 11–16 minutes | status projection / `fanning_out` | `heartbeat.json` in both `8AAA520D` and `BD26C1D1`; note `"accepted"` is not itself one of the P0 phase names (`waitingForWriteLock\|spawningWorker\|working\|proving\|settling`) — it is a pre-freeze internal/legacy phase label, itself evidence the current phase vocabulary and the live heartbeat vocabulary have already diverged |
| No `workers/` subdirectory for either incident run (contrast `2ADCE96A`'s full `workers/*` set) | streams without activity / `ps` (no worker-level facts to project) | directory listings above |
| `owner.json` holds only the coordinator's `inProcess` identity, never a worker pid/pgid | `kill` (nothing worker-specific to signal) / orphan lane holders after coordinator death | `owner.json` contents above; `runtimeOwnership` (spec's proposed per-worker record) does not exist in source (`ProcessOwnership.swift` only defines `ownerFileName`/coordinator identity) |
| `alln kill --all` outcome (`killedCount: 0`) not present as a stored artifact anywhere in the support dir | silent `--json` / `kill` | absence noted above; only the spec's own provenance line and this slice's PM handover assert it |
| Stale `Lanes/d18746ae6151216e` `holder.json` naming a pid acquired ~10.5h before the incident, never observed released in the files inspected | orphan lane holders after coordinator death | `Lanes/d18746ae6151216e/holder.json`; explicitly **not** proven causally linked to `8AAA520D`/`BD26C1D1` (see caveat above) |
| `run.json` top-level `status: "failed"` / `endReason: "cancelled"` only appears **after** operator cancellation — no durable evidence of what `alln team status <id>` printed live during the 11–16 minute window | status projection (`RunEvent` is "a projection of journal transitions, not peer truth") | no `events.jsonl` for either run; only pre-hang acceptance facts and post-cancel terminal state exist on disk |

---

## RCA classes for `RUN_NOT_FOUND`

Per the spec's error-catalog restriction: `RUN_NOT_FOUND` is reserved for
*malformed / never-emitted / wrong support root* — never "journal corrupt"
(that must map to `JOURNAL_CORRUPT`). Enumerated cause classes, with the
discriminating field evidence for each, and what I actually verified in
source vs. what remains open:

1. **Malformed id** — the caller passes a string that is not a valid run-id
   shape (not a UUID matching any `run_<id>` directory name at all).
   *Discriminating evidence:* the id fails basic shape validation before any
   directory lookup is attempted; distinguishable from class 2/3 because no
   well-formed id was ever produced by an accept path in the first place.

2. **Id never emitted / acceptance failed before journal** — the CLI printed
   nothing usable (or a refusal) and no `run_<id>` directory was ever created.
   Per spec RLR-L1: "validation/governor/capacity refusals have no run id and
   no journal" — this is the *expected*, non-buggy case, not a lie. *Discriminating
   evidence:* the caller has no id at all to query (refusal envelope only),
   so this class is inherently distinguishable from the other four purely by
   "did the accept path ever hand back a `runId`."

3. **Wrong `ALLNIGHTER_SUPPORT_DIR` resolution between processes** — the
   emitting process and the querying process (e.g. `alln run` vs. a later
   `alln team status`/`alln kill`) resolve different support roots (env var
   set in one shell/process but not the other), so the second process looks
   in a directory where the `run_<id>` folder genuinely does not exist.
   *Discriminating evidence per spec:* "Status/kill errors print the
   effective `ALLNIGHTER_SUPPORT_DIR`" — **I verified this is not yet
   implemented.** `AllnighterCLI.swift`'s `emitFailure`/`fail` helpers (lines
   181–201) build an `ErrorEnvelope` from `code`/`message`/catalog metadata
   only; none of the ~9 `RUN_NOT_FOUND` call sites in `AllnighterCLI.swift`
   (e.g. lines 137, 1176, 1203, 1244, 1263, 1507, 1528, 1548, 1579) or
   `AsyncTeamService.swift` (lines 573/576) include the resolved support-dir
   path in the message. Until that lands, class 3 is **not currently
   distinguishable in the field** from classes 1/2/4/5 — an agent hitting
   `RUN_NOT_FOUND` today cannot tell "wrong root" from "id truly doesn't
   exist" without manually diffing `ALLNIGHTER_SUPPORT_DIR` across shells.
   `AllnighterPaths.swift:9` and `AllnighterSupportRoot.swift:8` both honor
   the env override, so the resolution logic itself exists — only the
   error-message surfacing is missing.

4. **Journal present but unreadable** — the `run_<id>` directory and
   `run.json` exist, but the file is truncated/corrupt/undecodable JSON (e.g.
   a crash mid-write). Per the spec this **must** map to `JOURNAL_CORRUPT`,
   not `RUN_NOT_FOUND`. *Discriminating evidence:* directory exists on disk;
   a decode attempt throws rather than returning "not found." I did not find
   a call site in the grepped `RUN_NOT_FOUND` occurrences that distinguishes
   "directory missing" from "directory present but undecodable" — several
   sites (e.g. `AllnighterCLI.swift:1176/1203/1244/1263/1507/1528/1548/1579`,
   message `"no run matches \(runId)"`) read generically as "no run matches,"
   which is the exact ambiguity the spec's error-catalog note is guarding
   against. This is a live gap, not something I fixed (S00 is evidence only).

5. **Id emitted but journal written after emit (transient race)** — the
   accept path hands back a `runId` before the journal write that makes it
   durable has completed/flushed; a query landing in that narrow window sees
   "not found" for an id that will exist microseconds later. *Discriminating
   evidence, concretely found in source:* `AllnighterCLI.swift:131-137`:
   ```swift
   let result = await runtime.service().run(request, origin: .cli, ...)
   if opts.flag("json") {
       guard !result.runId.isEmpty else { ... }
       guard let run = loadRun(result.runId) else {
           emitFailure(code: "RUN_NOT_FOUND", message: "team run did not persist")
           exit(1)
       }
   ```
   Here `result.runId` is already non-empty (the id **was** emitted) and the
   very next statement, `loadRun(result.runId)`, can still return `nil` →
   `RUN_NOT_FOUND` with the message `"team run did not persist"`. This is the
   exact race class 5 describes, present today as a literal reachable code
   path in the same process (not even cross-process) — the strongest
   concrete evidence in this packet that class 5 is real and already
   reachable, independent of any cross-process timing. RLR-L2 ("mint and
   persist the run ... before any long wait") is the spec's proposed fix for
   this exact site.

One-line summary of the five classes:

1. Malformed id — id never round-trips because it was never well-formed.
2. Never-emitted id — refusal path, no id was ever handed back (expected, not a bug).
3. Wrong `ALLNIGHTER_SUPPORT_DIR` — different resolved root between processes; **currently unprovable in the field** because errors don't print the effective root yet (verified gap).
4. Journal present but unreadable — must surface as `JOURNAL_CORRUPT`, not `RUN_NOT_FOUND`; no call site found that makes this distinction today (verified gap).
5. Emitted-then-persisted race — id returned before `loadRun` can see it; concretely reachable today at `AllnighterCLI.swift:131-137` (verified in source).

---

## Files referenced in this packet

- `docs/phases/Run_Lifecycle_Reliability.md` (SSOT, read only)
- `/Users/mike/Library/Application Support/Allnighter/Runs/run_8AAA520D-1BB0-431C-803B-0D479B7653B6/{run.json,heartbeat.json,owner.json}`
- `/Users/mike/Library/Application Support/Allnighter/Runs/run_BD26C1D1-7CBE-4F96-B1C5-B353DF143C92/{run.json,heartbeat.json,owner.json}`
- `/Users/mike/Library/Application Support/Allnighter/Runs/run_2ADCE96A-A095-4B5D-8DFB-20FDF1AE130F/{run.json,heartbeat.json,events.jsonl,workers/*}`
- `/Users/mike/Library/Application Support/Allnighter/Lanes/d18746ae6151216e/holder.json`
- `/Users/mike/Library/Application Support/Allnighter/Coordinator/coordinator.json`
- `Packages/AllnighterCore/Sources/AllnighterEngine/ProcessOwnership.swift` (read only, for `owner.json`/`runtimeOwnership` confirmation)
- `Packages/AllnighterCore/Sources/AllnighterEngine/ExecutionLaneFlock.swift`, `ExecutionLane.swift` (read only, for `Lanes/` layout)
- `Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift` (read only, `RUN_NOT_FOUND` call sites, `emitFailure`/`fail`)
- `Packages/AllnighterCore/Sources/AllnighterEngine/AsyncTeamService.swift` (read only, `RUN_NOT_FOUND` call sites)
- `Packages/AllnighterCore/Sources/AllnighterEngine/AllnighterPaths.swift`, `Packages/AllnighterCore/Sources/AllnighterCore/AllnighterSupportRoot.swift` (read only, `ALLNIGHTER_SUPPORT_DIR` resolution)
