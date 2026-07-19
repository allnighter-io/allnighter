# RLR-S01 Execution Plan — mint/persist before waits · lifecycle+phase convergence

Status: **Architect recon + design (RLR-S01). No source changed to produce this.**
Read-only audit of branch `feat/design-chain` (2026-07-19). SSOT:
`docs/archive/phases/Run_Lifecycle_Reliability.md` (FINAL). S00 evidence:
`docs/archive/phases/rlr/Spawn_Site_Matrix.md`, `docs/debuglog/RLR_incident_packet.md`.

This plan turns the **fanning_out leg** of
`RunLifecycleTwoProcessTests` green (signature (a)); the terminal-lie leg
(signature (b)) is **S04**, untouched here.

Scope discipline: P0 vertical = **cold, single-worker, foreground mutating**
`alln run` / `alln team start` with the deterministic fake CLI. Multi-worker
team runs keep their existing `fanning_out → answers_in → planning → …` stage
machine; S01 only removes `fanning_out` from the **one-worker** path and adds
the canonical public lifecycle as a projection over everything.

---

## PART 1 — CURRENT-STATE MAP

### 1.1 Every lifecycle/status enum in play today

| Enum | Definition | Cases | Role |
| --- | --- | --- | --- |
| `RunStatus` | `AllnighterCore/Enums.swift:8` | draft · fanningOut(`fanning_out`) · answersIn(`answers_in`) · planning · reviewing · finalizing · complete · partial · cancelled · failed · interrupted | **The durable journal truth** — `TeamRun.status` (`TeamRun.swift:23`). This is what `store.loadRaw().status` returns in the RED test. |
| `RunEndReason` | `Enums.swift:43` | completed · failed · cancelled · reconciledOrphan · killed · unknown | `TeamRun.endReason`; the RED test (b) reads `.killed`. |
| `AsyncTeamLiveStatus` | `AsyncTeamContracts.swift:5` | accepted · running · synthesizing · completed · failed · timedOut · cancelled · interrupted | **Live poll wire** returned by `team start/status/cancel/result`. Projected from `RunStatus` by `AsyncTeamStatusMapper.liveStatus` (`AsyncTeamStatusMapper.swift:10`). |
| `TeamRunJSON.Status` | `TeamRunJSON.swift:73` | queued · running · done · failed · timedOut · cancelled · skipped · interrupted | `alln team`/`run --json` DTO wire; projected by `TeamRunJSONMapper.mapRun` (`TeamRunJSONMapper.swift:170`). |
| `FloorRun.Status` | `FloorRun.swift:40` | queued · running · done · failed · timedOut · cancelled · interrupted | Floor projection; `FloorProjector.status(for:)` (`FloorProjector.swift:60`). Already the lifecycle shape (template). |
| `ThreadTurnStatus` | `ThreadTurn.swift:216` | queued · running · … · timedOut · … | GUI thread projection; `ThreadsViewModel.turnStatus(for:)` (`ThreadsViewModel.swift:1051`). |
| `ProgressHeartbeat.phase` | `ProcessOwnership.swift:174` (free `String`) | written strings: `"accepted"`, `"runner_starting"`, `"spawned"`, `"output"`, `"exited"` | heartbeat.json phase — a **free string, divergent from both `RunStatus` and the spec phase vocab.** |

**Producers of `fanning_out`** (all must be re-routed for one-worker; multi-worker keeps it):
- `RunService.swift:540` (event payload `to: fanning_out`) and `:550` (`status: .fanningOut` in the single-worker mint) and `:840` (event `from: fanning_out`).
- `AsyncTeamService.swift:392` — `mintRun(... status: .fanningOut)` (used for **both** single- and multi-worker `team start`).
- `CatalogRunCoordinator.swift:82` — `transition(run, to: .fanningOut)`.
- `TeamRunCoordinator.swift:58` — `transition(run, to: .fanningOut)`.
- `DesignCoordinator.swift:68` — `transition(run, to: .fanningOut)` (design lane; multi-worker, out of P0).
- `NDJSONStreamProjector.swift:126` — consumes `RunStatus.fanningOut.rawValue` → `teamRunStarted`.

**Consumers that `switch` over these enums (HIGH-RISK, exhaustive, no `default:` — compile-break on case add):**

RunStatus:
1. `TeamRun.swift:196` — `isTerminal`
2. `TeamRun.swift:210` — `allowedTransitions()` (the state-machine graph)
3. `TeamRunJSONMapper.swift:170` — `mapRun` → `TeamRunJSON.Status`
4. `FloorProjector.swift:60` — `status(for:)` → `FloorRun.Status`
5. `AsyncTeamStatusMapper.swift:10` — `liveStatus(for:)` → `AsyncTeamLiveStatus` (the enum-to-enum bridge)
6. `Apps/AllnighterMac/Sources/ThreadsViewModel.swift:1051` — `turnStatus(for:)` → `ThreadTurnStatus` (**GUI**)

AsyncTeamLiveStatus:
7. `AsyncTeamContracts.swift:9` — `isTerminal`
8. `AsyncTeamStatusMapper.swift:52` — `nextPollAfterMs`
9. `AllnighterCLI.swift:1213` — wait-for terminalMismatch → exit code
10. `AllnighterCLI.swift:1225` — wait-for target-matched → exit code

**Non-exhaustive / string-drift consumers (no compiler protection):**
`NDJSONStreamProjector.swift:126-135` (rawValue string switch), `AsyncTeamStatusMapper.swift:101` (`["completed","failed","timedOut","cancelled"]` literal set), `AllnighterCLI.swift:1190` (help string listing all live cases), `ContractRegistry+Milestone1.swift:313` (`--wait-for` flag summary listing cases), `ContractSchema.swift:121`. `AppModel.swift:406` (`== .complete || == .partial || == .answersIn` GUI persist gate — **boolean equality, not a switch, silently misses new terminal cases**). `StalledWorkDetector.swift:103-104,124,126` (`== .accepted/.running/.synthesizing`).

`.isTerminal`-only readers (robust to case add; listed for completeness): `CatalogRunCoordinator.swift:151`, `PendingService.swift:401`, `RunStore.swift:38/237/248/272`, `ProcessOwnershipGarbageCollector.swift:139/196`, `ProcessOwnershipSurface.swift:155/188`, remote/relay projectors. iOS (`Apps/AllnighteriOS/**`) has **no** direct `RunStatus`/`AsyncTeamLiveStatus` consumer — it reads the already-mapped `TeamRunJSON.Status` strings.

### 1.2 Phase / heartbeat model today

`ProcessOwnership.ProgressHeartbeat` (`ProcessOwnership.swift:174`) = `{ sequence: UInt64, phase: String, lastProgressAt, touchedAt }`, one `heartbeat.json` per run dir.
- `recordProgress(in:phase:now:)` (`ProcessOwnership.swift:398`) advances `sequence` + writes `phase` + `lastProgressAt`.
- `touchHeartbeatFloor` (`:410`) only bumps `touchedAt`; the seed is `phase: "accepted", sequence: 0` (`:416`).
- Writers: `AsyncTeamService.swift:665` (`phase: "accepted"`), `:608` (`"runner_starting"`), `:741` (`touchHeartbeatFloor`); `ProcessGroupCommandRunner.swift:95/99/106/120/206/…` (`"spawned"/"output"/"exited"`); `RunStore.swift:64` (floor touch on save).
- **Sequence semantics:** monotonic per `recordProgress` call; the incident froze at `sequence: 0`/`phase: "accepted"` (never spawned). The heartbeat phase vocabulary is a **third, disjoint** vocabulary from `RunStatus` and the spec's phase enum — this is the divergence the incident packet flagged.

### 1.3 Acceptance path — mint / first persist / waits before persist

**Sync `alln run` / `alln team` (RunService.run, `RunService.swift:~290`):**
- `:298` `requestedAt`; `:302` normalize root; `:349` `lockKey`; `:351` `takesWriteLock = preset.writePolicy == .mutating`.
- **`:358` `await writeLock.waitToAcquire(lockKey, timeout: 1800s)` — the long blocking wait.**
- Run is **minted at `:549` and `runStore.save`d at `:568`** — i.e. **AFTER** the up-to-1800s lock wait. During the wait there is **no `run.json`, no blocker record, no emitted id.**
- ⇒ **Spec Current-state item 1: CONFIRMED** at `RunService.swift:358` (wait) vs `:549/:568` (mint/save). (This is the sync path only; see async below.)

**Async `alln team start` (AsyncTeamService.startDetached, `:239`):**
- `:276` `mintRun` (status `.fanningOut`) → `:283` `persist(run)` **before** `:336` `spawnDetachedRunner` and `:350` `waitForRunnerReady`. So the detached path **already persists before its spawn wait** (good). Its write-lock wait happens later, inside the runner/coordinator, where the journal already exists.
- ⇒ item 1 does **not** apply to the async path; it is specifically the sync RunService path.

**Emit-then-persist race (item 8):** `RunService.swift:538-542` `emit(runStatusChanged, to: fanning_out)` runs **before** `runStore.save` at `:568`. ⇒ **item 8: CONFIRMED.** Additionally the sync-`team` CLI **class-5 race** at `AllnighterCLI.swift:131-137`: `loadRun(result.runId)` immediately after `service().run(...)` can return `nil` → `emitFailure("RUN_NOT_FOUND", "team run did not persist")`. The async `team start` handler (`runTeamStart`, `AllnighterCLI.swift:1124-1136`) prints the response built from the minted run — **no `loadRun`, no class-5 race.**

### 1.4 `--wait-for` today

- Values accepted: **`AsyncTeamLiveStatus` raw values** + alias `terminal` — parsed by `TeamStatusWaitTarget.parse` (`AsyncTeamContracts.swift:215`): `accepted|running|synthesizing|completed|failed|timedOut|cancelled|interrupted|terminal`.
- Parsed/validated at CLI `AllnighterCLI.swift:1187` (usage/help lists all cases at `:1190`; requires `--timeout`, `:1182-1185`). Consumed by `AsyncTeamService.waitForStatus(target:)` (`:794`). Two exhaustive exit-code switches at `:1213`/`:1225`. Flag doc at `ContractRegistry+Milestone1.swift:313`.
- ⇒ Today it accepts **live-poll states, not lifecycle states** — S01a must restrict it to `RunLifecycle` (+`terminal`).

### 1.5 IdempotencyStore — shape / key / call sites / what RLR-L9 needs

`IdempotencyStore` (`IdempotencyStore.swift:6`): durable `{ key, payloadDigest, runId, acceptedAt }` entries in `Config/Tool/idempotency.json`, 24h retention (`:7`), flock-guarded RMW (`:153`).
- Keys on **`key`** (`lookup`/`claim` match `$0.key == key`); digest = SHA256 of `AsyncTeamCanonicalPayload` (`digest`, `:120`).
- **Persisted at acceptance already:** `claim(...)` (`:46`) writes the digest under the flock **before** mint/spawn — `AsyncTeamService.swift:211/266` (`claimIdempotency`) and refreshed at `:362`. `forceClaim`/`record` handle peer-vanished + refresh.
- Canonical payload today (`AsyncTeamCanonicalPayload`, `AsyncTeamContracts.swift:296`): `prompt, lane, teamPresetId, effort, modelId, type, context, repoRoot`.

**What RLR-L9 generalization requires (no second store):**
1. **Extend `AsyncTeamCanonicalPayload`** to the spec's canonical field list — add: attachment digests, `threadId`, resolved team/worker, the four timeouts, proof command, commit-message/no-commit, contract version. (Normalize root already via `repoRoot`.) The store, digest, retention, and flock stay as-is.
2. **Wire the SYNC path in.** `RunRequest`/`RunService` have **no** `idempotencyKey`/`retryOf` fields and never call `IdempotencyStore` (grep clean in `RunCLI.swift`/`RunService.swift`). Add `idempotencyKey`/`retryOf` to the sync request + persist key+hash at acceptance, so `alln run`/`team` match the spec CLI contract. (Replay/`--retry-of` **execution** is S05; S01 only persists.)

### 1.6 Legacy journals on disk (read-only sample of `~/Library/Application Support/Allnighter/Runs`)

- **159 run dirs. 159/159 decode** against the current `TeamRun` (`nkeys` 17–20; all optional-field drift is absorbed by Codable defaults). **No struct-shape generation break exists.** None carry a `phase` field; all carry `status`, `createdAt`, `timing`.
- Distinct `status` values present: **`complete`×112, `failed`×37, `fanning_out`×8, `partial`×1.** No `draft/answers_in/planning/reviewing/finalizing/interrupted`, and (naturally) none of the new `queued/running/done/timedOut`.
- The **8 `fanning_out`** journals are non-terminal, `endReason: null` — the frozen-orphan class (dates 2026-07-17…19).
- Current decoder behavior (`RunStore.load`, `:199` / `loadRaw`, `:207`): `CoreJSON.decode(TeamRun.self)`; `load` additionally projects a reclaimable non-terminal run to `.interrupted`/`.reconciledOrphan` (`projectIfOrphaned`, `:236`). An unknown `status` **raw string** would throw in `decode` → today swallowed to `nil` = silently "no run" (**this is the JOURNAL_CORRUPT gap** the spec forbids).

⇒ Only **one** journal generation exists; the meaningful legacy axis is the **status vocabulary**, and every value on disk maps unambiguously to a lifecycle. Policy = **MAP** (see S01c).

### 1.7 Clock / timeout flags today

- Only `--idle-timeout` exists (`RunCLI.swift:7` `parseIdleTimeoutSeconds` → `RunRequest.workerTimeoutSeconds`, `:50/:68`). Default: **driver-manifest `timeoutSeconds`** (grok=1800; flag summary says "typically 300"), `ContractRegistry+Milestone1.swift:373`. Reused verbatim by relay/pilot (`RelayCLI.swift:154`, `PilotCLI.swift:104`).
- **No `--handshake-timeout`, `--first-activity-timeout`, or `--wall-timeout`** anywhere (grep clean). `ProcessOwnership.waitForRunnerReady` (`:503`) has an internal handshake bound but no user flag/default surfaced.

### 1.8 status/kill error paths that must print effective `ALLNIGHTER_SUPPORT_DIR` (RLR-L1)

- **None print it today** (grep of `AllnighterCLI`/`AsyncTeamService` for support-dir in error messages is clean; the only hit is env-forwarding at `AsyncTeamService.swift:331`). Resolution logic exists (`AllnighterPaths.swift:9`, `AllnighterSupportRoot.swift:8` honor the env override) but is never surfaced in an error.
- `RUN_NOT_FOUND` emit sites needing it: `AllnighterCLI.swift:137` (sync team), `:1176, :1203, :1244, :1263, :1507, :1528, :1548, :1579` (status/result/kill/cancel), `AsyncTeamService.swift:573/576`. Error builder: `emitFailure`/`fail` (`:181/:198`).

---

## PART 2 — EXECUTION PLAN (S01a → S01b → S01c, strict order)

### Design spine (shared by all three)

Add two **new public frozen enums** (Core, new file `Packages/AllnighterCore/Sources/AllnighterCore/RunLifecycle.swift`):

```swift
/// Frozen public run lifecycle (RLR-L3). The single wire vocabulary for
/// status, --wait-for, ps rows, and every JSON/NDJSON projection.
public enum RunLifecycle: String, Codable, Sendable, CaseIterable {
    case queued, running, done, failed, timedOut, cancelled
    public var isTerminal: Bool { switch self {
        case .queued, .running: return false
        case .done, .failed, .timedOut, .cancelled: return true } }
}

/// Frozen public phase axis (RLR-L3). Only meaningful for non-terminal runs.
public enum RunPhase: String, Codable, Sendable, CaseIterable {
    case waitingForWriteLock, spawningWorker   // lifecycle == .queued
    case working, proving, settling            // lifecycle == .running
}
```

The durable `RunStatus` gains the canonical cases and a **total** projection so
every surface can converge without ripping out the multi-worker stage machine:

```swift
// Enums.swift — add to RunStatus: queued, running, done, timedOut
public extension RunStatus {
    var lifecycle: RunLifecycle {
        switch self {
        case .queued, .draft:                                             return .queued
        case .running, .fanningOut, .answersIn, .planning,
             .reviewing, .finalizing:                                     return .running
        case .done, .complete, .partial:                                  return .done
        case .timedOut:                                                   return .timedOut
        case .cancelled:                                                  return .cancelled
        case .failed, .interrupted:                                       return .failed
        }
    }
}
```

`.partial`'s plan-aware nuance (no-plan partial → failed) stays in the
run-aware mapper (`AsyncTeamStatusMapper`), not the bare projection.

---

### S01a — lifecycle + phase convergence  *(flips RED signature (a) green)*

**Goal:** one-worker runs never carry `fanning_out` in the durable journal;
public surfaces speak `RunLifecycle`+`RunPhase`; transition table is code;
`--wait-for` accepts lifecycle states only; phase+blocker change atomically.

**Files + edits:**

1. **New `RunLifecycle.swift`** — `RunLifecycle`, `RunPhase` (above).
2. **`Enums.swift:8`** — add `queued, running, done, timedOut` to `RunStatus`; add `var lifecycle` (above).
3. **`TeamRun.swift`**
   - `:196 isTerminal` (exhaustive) — `.done, .timedOut` terminal; `.queued, .running` non-terminal.
   - `:210 allowedTransitions()` (exhaustive) — add edges: `.draft → [.queued, .fanningOut, …]`; `.queued → [.running, .cancelled, .failed, .timedOut]`; `.running → [.done, .failed, .timedOut, .cancelled]`; `.done/.timedOut → []`. Keep legacy multi-stage edges intact.
   - Add stored `public var phase: RunPhase?` (+ init param, optional so legacy decodes `nil`). This is the **durable phase** (moves phase truth off heartbeat.json onto run.json, per L6/atomic rule).
4. **Single-worker mint/transition — drop `fanning_out`:**
   - `RunService.swift:549-568` (single-worker default run): mint `status: .queued, phase: .spawningWorker` (or `.waitingForWriteLock` when the lock is still pending — see S01b ordering); transition to `.running`/`phase: .working` at worker spawn; terminal sets `.done/.failed/.timedOut/.cancelled` + `phase = nil`. Update event payloads `:539-540` (`to: queued`/`running`, not `fanning_out`) and `:840`.
   - `AsyncTeamService.mintRun:392` — mint `status: .queued` (+ `phase: .spawningWorker`) for all; the **coordinator** picks the running state by worker count.
   - `CatalogRunCoordinator.swift:82` and `TeamRunCoordinator.swift:58` — branch: `run.workers.count == 1 → transition(to: .running, phase: .working)`; `else → transition(to: .fanningOut)` (multi-worker unchanged). `DesignCoordinator.swift:68` stays multi-worker (`.fanningOut`).
   - Extend the `transition` helpers (`CatalogRunCoordinator.swift:401`, `TeamRunCoordinator.swift:133`) to take `phase:` and write status+phase in the **same** `save` revision (atomic rule; blocker clear/replace joins the same revision in S02).
5. **Exhaustive mapper switches — add the 4 cases:**
   - `TeamRunJSONMapper.swift:170` → `.queued→.queued, .running→.running, .done→.done, .timedOut→.timedOut`.
   - `FloorProjector.swift:60` → same (maps onto `FloorRun.Status`).
   - `AsyncTeamStatusMapper.swift:10 liveStatus` → **return `RunLifecycle`** (see wire convergence below).
6. **AsyncTeamLiveStatus → RunLifecycle wire convergence** (converge the public surface, retire accepted/synthesizing/interrupted):
   - Change `TeamStartResponse.status`, `TeamStatusResponse.status`, `TeamCancelResponse.status`, `TeamResultNotReady.status` (`AsyncTeamContracts.swift:84/140/258/284`) from `AsyncTeamLiveStatus` → `RunLifecycle`.
   - `AsyncTeamStatusMapper`: `liveStatus`→`RunLifecycle`; `nextPollAfterMs`/`resultAvailable`/`nextAction`/`withWaitGuidance`/hardcoded terminal set `:101` re-expressed over `RunLifecycle`; legacy `accepted→queued`, `synthesizing→running`, `interrupted→failed`.
   - `TeamStatusWaitTarget` (`AsyncTeamContracts.swift:211`) → wrap `RunLifecycle`; `parse` accepts `queued|running|done|failed|timedOut|cancelled|terminal`.
   - CLI wait-for exit-code switches `AllnighterCLI.swift:1213/1225` → over `RunLifecycle`; help `:1190`; flag summary `ContractRegistry+Milestone1.swift:313`; `ContractSchema.swift:121`.
   - `StalledWorkDetector.swift:103-104,124,126` — migrate `== .accepted/.synthesizing` → `.queued/.running`.
   - **Retire `AsyncTeamLiveStatus`** (or keep as a private legacy alias only if a decode test needs it). Recommendation: delete; nothing on disk stores it (verified — journals store `RunStatus`, not live status).
7. **GUI (must compile — cross-target):**
   - `ThreadsViewModel.swift:1051 turnStatus(for:)` (exhaustive) — add `.queued→.queued, .running→.running, .done→.done, .timedOut→.timedOut`.
   - `AppModel.swift:406` persist gate — add `.done` (and treat `.timedOut/.failed/.cancelled` as settled) so single-worker settled runs still persist. **Behavioral, not compiler-caught — must not be missed.**
8. **NDJSONStreamProjector.swift:126** — add `.queued/.running.rawValue → teamRunStarted` and `.done/.timedOut.rawValue → teamRunCompleted/Failed` so the single-worker stream still emits start/terminal.

**New types / signatures:** `RunLifecycle`, `RunPhase` (above); `RunStatus.lifecycle`; `TeamRun.phase: RunPhase?`; `transition(_ run:, to: RunStatus, phase: RunPhase?)`.

**Tests to add/modify:**
- Add `RunLifecycleProjectionTests` — `RunStatus.lifecycle` totality over `.allCases`; `RunLifecycle.isTerminal`; phase↔lifecycle legality table.
- Modify (break-and-fix): `StateMachineTests.swift:23/38-49` (new cases in `isTerminal`/`allowedTransitions`); `Apps/AllnighterMac/Tests/DefaultRunSettlementTests.swift:14/32` (loops `allCases`; add new non-terminal `.queued/.running`); `TeamRunJSONMapperTests.swift:76`, `FloorProjectorTests.swift:12`, `RunServiceTests.swift:49` (mapper/event assertions now `queued/running`); `AsyncTeamLifecycleTests` (live status → `RunLifecycle`); `RunStoreJournalTests.swift:27-28` (already touched on branch).
- Remote/event tests using `RunStatus.fanningOut.rawValue` payloads (`RemoteRunEventJournalTests`, `RemoteSnapshotServiceTests:188/211`, etc.) — still valid (`fanning_out` retained); re-run to confirm no drift.

**Acceptance proof:**
```bash
RLR_RED=1 swift test --package-path Packages/AllnighterCore --filter RunLifecycleTwoProcess
```
Signature **(a)** `testStatusPolledFromSecondProcessDisagreesWithDurableJournalDuringHang` → **GREEN** (A2 `journal.status != .fanningOut` because the one-worker run is now `.running`; A1 `polledStatus != "accepted"` because `liveStatus(.running) == .running`). Signature **(b)** stays **RED** (S04).
```bash
swift test --package-path Packages/AllnighterCore --filter RunLifecycle
swift test --package-path Packages/AllnighterCore --filter StateMachine
# plus the Mac target build (cross-target compile of ThreadsViewModel/AppModel)
```

---

### S01b — mint/persist before waits + acceptance boundary

**Goal:** durable journal + pollable id + typed blocker exist **before** any
long wait; kill the emit-then-persist race; print support dir on
status/kill errors; persist idempotency key + full canonical hash at acceptance.

**Files + edits:**

1. **Mint/persist before the write-lock wait (item 1) — `RunService.swift`:**
   - Move `mintRun` + `runStore.save` to **before** `:358 writeLock.waitToAcquire`. Mint as `status: .queued, phase: .waitingForWriteLock` (when `takesWriteLock`) with the emitted `runId` durable, then acquire the lock (S02 attaches the real `repoWriteLock` blocker; S01b writes a minimal blocker stub `resource: repoWriteLock, scopeRoot`), then transition to `.spawningWorker`. On `.writeLockBusy` timeout the run is already durable → stamp terminal `failed`/`timedOut` honestly rather than vanishing.
2. **Kill the emit-then-persist race (item 8):**
   - `RunService.swift` — `runStore.save` **before** the `emit(runStatusChanged)` (reorder `:538-542` after `:568`).
   - Sync-`team` class-5 site `AllnighterCLI.swift:131-137` — because save now precedes return, `loadRun` finds it; keep the guard but on `nil` print effective support dir (below), never a bare `RUN_NOT_FOUND`.
3. **Support-dir printing (RLR-L1) —** add a helper `effectiveSupportRoot()` (from `AllnighterSupportRoot`/`AllnighterPaths`) and append `" (support dir: <path>)"` to every `RUN_NOT_FOUND` message: `AllnighterCLI.swift:137/1176/1203/1244/1263/1507/1528/1548/1579`, `AsyncTeamService.swift:573/576`. Extend `emitFailure` with an optional `supportDir` field on the envelope for machine callers.
4. **Persist idempotencyKey + full canonical hash at acceptance (RLR-L9):**
   - Extend `AsyncTeamCanonicalPayload` (`AsyncTeamContracts.swift:296`) with: `attachmentDigests: [String]`, `threadId`, `resolvedTeamId`, `resolvedWorkerIds: [String]`, `handshakeTimeout/firstActivityTimeout/idleTimeout/wallTimeout`, `proofCommand`, `commitMessage`, `noCommit: Bool`, `contractVersion`. (Digest/store/flock unchanged.)
   - Add `idempotencyKey`/`retryOf` to the **sync** `RunRequest` (+ parse in `RunCLI.swift`), and call `IdempotencyStore.claim` at sync acceptance (same store, `claim`-before-mint). Persist `RunLink.retryOf` durably when `--retry-of` is present (link only; **no** replay execution — S05).

**Tests:** blocked-lock durability test (pre-hold the lock, assert `run.json` with `status: queued`, `phase: waitingForWriteLock`, blocker, and a second-process-pollable id exist **during** the wait); save-before-emit ordering test; `RUN_NOT_FOUND`-includes-support-dir test; extended-canonical-digest round-trip + sync-path `claim` test.

**Acceptance proof:**
```bash
swift test --package-path Packages/AllnighterCore --filter RunAcceptanceBoundary   # new
swift test --package-path Packages/AllnighterCore --filter Idempotency
RLR_RED=1 swift test --package-path Packages/AllnighterCore --filter RunLifecycleTwoProcess  # (a) still green, (b) still red
```

---

### S01c — legacy-journal policy · clock defaults · wire freeze · docs regen

**Chosen legacy-journal policy: MAP (deterministic), with a typed
`JOURNAL_CORRUPT` guard for the truly unmappable.** Justification (Part 1.6):
all 159 on-disk journals decode against the current `TeamRun` (single Codable
generation; optional-field drift only), and every `status` value present
(`complete/failed/fanning_out/partial`) maps unambiguously via
`RunStatus.lifecycle`. Quarantine is unwarranted (no undecodable generation
exists); a blanket typed-error would reject readable history. The only invention
risk is an **unknown status raw string**, which must surface as
`JOURNAL_CORRUPT` — never silently coerced.

**Files + edits:**
1. **Map:** `RunStatus.lifecycle` (S01a) already covers every legacy case; `TeamRun.phase` decodes `nil` on legacy (fine). No migration write-back (foundation-first: read old, project canonical).
2. **Guard:** wrap `RunStore.load/loadRaw` (`:199/:207`) decode so a `DecodingError` on an existing `run.json` returns a typed `JOURNAL_CORRUPT`, distinct from directory-absent `RUN_NOT_FOUND` (closes incident RCA classes 3/4). Add `JOURNAL_CORRUPT` to the error catalog (`ContractRegistry+Milestone1.swift`, currently absent).
3. **Clock defaults (name finite values; S05 enforces):** new `RunClockDefaults` in Core (config path `DefaultConfig`):
   - `--handshake-timeout` = **60s** (runner-ready bound; `waitForRunnerReady` already ~this order).
   - `--first-activity-timeout` = **120s** (first post-spawn activity; 2× handshake headroom for cold model warmup).
   - `--wall-timeout` = **3600s** (1h hard ceiling; > longest driver manifest 1800s idle so it never pre-empts a healthy long run).
   - `--idle-timeout` = **unchanged** (driver-manifest `timeoutSeconds`).
4. **Wire-shape freeze:** freeze `RunLifecycle`/`RunPhase` raw values + the §CLI-first JSONC block; note the projection additions still owed — `OwnershipProcessJSON` (`OwnershipJSON.swift:25`) gains `phase` (S01a) and typed `blocker` (S02, richer than the current `OwnershipLaneJSON`); `lastActivityKind`/`progressStale` (S03); `killOutcome`/`contradiction` (S04). Field **names** freeze now.
5. **Docs regen:** update `--wait-for` flag summary + help to lifecycle states; add `JOURNAL_CORRUPT`; regenerate `docs/generated/alln/*` (contract registry) and re-run the contract-drift/parity test.

**Tests:** legacy-decode matrix (feed the 4 on-disk `status` strings → expected `RunLifecycle`; unknown string → `JOURNAL_CORRUPT`); clock-defaults presence/finiteness test; contract-drift test green after regen.

**Acceptance proof:**
```bash
swift test --package-path Packages/AllnighterCore --filter LegacyJournal   # new
swift test --package-path Packages/AllnighterCore --filter Contract
bash scripts/check.sh
```

---

## RISKS

**Consumers the plan explicitly updates (so they compile/behave):** the 10
high-risk exhaustive switches (Part 1.1), `NDJSONStreamProjector:126`,
`StalledWorkDetector`, `AppModel.swift:406`, the GUI `ThreadsViewModel:1051`,
and the string-drift sites (`AsyncTeamStatusMapper:101`, `AllnighterCLI:1190`,
`ContractRegistry:313`, `ContractSchema:121`).

**Consumers the plan does NOT change (called out, with recommendation):**
- `Apps/AllnighteriOS/**` — no direct enum consumer; reads `TeamRunJSON.Status` strings (already `queued/running/done/…`). **Safe**, no action.
- Remote/relay projectors that only read `.isTerminal` (`RelayThreadProjector`, `RemoteSnapshotService`, GC/Surface) — robust to case-add. **Safe**; re-run their tests.
- Remote event tests embedding `RunStatus.fanningOut.rawValue` — `fanning_out` is retained (multi-worker), so payloads stay valid. **No edit**; recommend a re-run to confirm.
- `PendingService.swift:401` and `CatalogRunCoordinator.swift:152` (switch **with** `default:`) — compile-safe on add, but their `default:` will now also catch `.queued/.running/.done/.timedOut`; **recommend** auditing that the default branch is correct for the new non-terminal cases (esp. `PendingService` attempt settlement).

**Top 3 risks:**
1. **AsyncTeamLiveStatus retirement is a wide, partly compiler-blind wire change.** `team status/start/cancel/result` + `--wait-for` + `StalledWorkDetector` + `ContractSchema.swift:121` + `AsyncTeamStatusMapper:101` all speak the old vocabulary; the string-literal sites have **no** compiler protection. If any is missed, relay/pilot stall-detection or agent poll loops silently misread status (the exact "lie-prone layer" class the phase exists to kill). Mitigation: land the retirement atomically in S01a and cover it with the contract-drift test + an explicit `AsyncTeamLifecycleTests` rewrite.
2. **GUI settle/persist gates keyed on legacy cases are behavioral, not compiler-caught.** `AppModel.swift:406` (`== .complete || .partial || .answersIn`) and `ThreadsViewModel.turnStatus` decide whether a finished run is written to the inbox. One-worker runs now terminate as `.done`; if `:406` isn't extended, the Mac app **silently fails to persist real single-worker runs** (inbox data loss). Mitigation: the S01a GUI edits + a Mac settlement test over the new terminal cases.
3. **Adding cases to `RunStatus` forces a single cross-target (Core+Engine+CLI+Mac) commit or the build breaks.** Six exhaustive switches (one in the Mac target) must change together; an S01a that green-builds Core but not `Apps/AllnighterMac` is a false pass. Mitigation: S01a's acceptance must build the Mac target too (`scripts/check.sh` scope), and the PM should confirm the Mac test target compiles before calling S01a done.

---

## Verdicts (for PM)

- **Spec Current-state item 1 — CONFIRMED.** `RunService.swift:358` (`writeLock.waitToAcquire`, 1800s) runs before mint/save at `:549`/`:568`; no durable run/blocker/id during the wait. Sync path only (async `startDetached` already persists at `AsyncTeamService.swift:283` before its spawn wait).
- **Spec Current-state item 2 — CONFIRMED.** One-worker mint is `.fanningOut` at `RunService.swift:550`, `AsyncTeamService.swift:392`, `CatalogRunCoordinator.swift:82`, `TeamRunCoordinator.swift:58`; 8 on-disk journals frozen at `fanning_out`.
- **Spec Current-state item 8 — CONFIRMED.** `RunService.swift:538-542` emits before `runStore.save` at `:568`; plus the reachable class-5 `RUN_NOT_FOUND` at `AllnighterCLI.swift:131-137`. The async `team start` handler (`:1124-1136`) has no such race.
