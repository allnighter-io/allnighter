# Stalled Work Watchdog

Status: WTK-S00/S01a/S01b/S02a/S02c built; **next handoff is WTK-S03
one-shot wake scheduling for workerChat Wake Tickets**
Owner: AllnighterCore + AllnighterEngine + Mac app backend + CLI/MCP contracts
Updated: 2026-06-19

## Authority

This doc owns the stalled-work detection and recovery contract.

Read with:

- `docs/workflows/SSOT_Founder_Input_Workflow.md`
- `docs/workflows/SSOT_Feature_Workflow.md`
- `docs/phases/Project_Spine_And_Project_Manager.md`
- `docs/phases/Persistent_Work_Threads.md`
- `docs/phases/threads/02_Notifications.md`
- `docs/phases/Pending_Work_And_Drain.md`
- `docs/phases/Agent_First_MCP_And_Messaging_Workflows.md`
- `docs/operations/Execution-Playbook.md`

Durable semantics live in AllnighterCore and Project Manager turns. SwiftUI,
notifications, prompt copy, CLI output, MCP output, and worker prose render or
project this truth; they do not own it.

All watchdog and Wake Ticket work is CLI/MCP-first. `alln` commands and MCP
tools are product surfaces for OpenClaw, Hermes, scripts, and future apps; Mac
GUI/iOS surfaces only present the same contract. With zero users, do not add
compatibility shims or production migrations for stale local shapes. Update the
Core contract, generated schemas, fixtures, CLI registry, and MCP specs directly;
old dev records without required truth are repair-only or disposable.

## Current Code Reality

Do not hand this doc to a developer as one end-to-end implementation request yet.
The target behavior is clear, but code inspection on 2026-06-19 found prerequisite
seams that must land first.

Built substrate:

- `PendingResume` already has `observedResetAt` and `wakeAfter`.
- `CapacityObservation` and `CapacityClassifier` exist in Core.
- `PendingResumeReason.providerBusy` exists, and `PendingResume` can store
  `capacityObservation`.
- `PendingItemJSON` projects `nextWakeAt` and `capacityObservation` from
  `PendingResume`.
- `pending_list`, `pending_show`, and `pending_run` MCP tool specs exist in the
  registry contract, but live MCP handlers are not wired yet.
- `WorkerRunner` captures raw nonzero stdout/stderr with `CapacityClassifier`
  before reducing output to `errorReason`, and propagates observations through
  `WorkerRunOutcome` / `WorkerAnswer`.
- CLI `alln pending run <id> --json` executes and settles `workerChat` Pending
  items end to end through `PendingRunExecutor`.
- WorkerChat Pending attempts write transcript receipts under the Pending store
  and expose `transcriptRef` in attempt summaries, not inline transcript content.
- Live MCP handlers for `pending_list`, `pending_show`, and `pending_run` are
  wired through `MCPPendingHandlers` and dispatch from `MCPServer`.
- Worker chat turns have durable `projectId`, `queued`/`running` status, and
  timestamps.
- Async team runs persist durable `TeamRun` truth through `RunStore`, including
  orphan recovery to `interrupted`.
- `ProjectManagerTurnStore` exists for durable Project Manager turns.

Missing blockers:

- `teamRun`, `followUp`, `returnReview`, `workOrder`, dispatch, and mutating
  execute Pending items do not execute through Pending yet.
- Other non-Pending call sites may still need resume writers if they should turn
  classified capacity observations into Pending resumes.
- `ResidentCoordinator` is still health-only; it has no wake timer or watchdog
  scanner.
- `PendingRunExecutor` currently enters `PendingService.beginRun` through the
  default CLI lease owner. WTK-S03 should add a narrow owner/provenance seam so
  resident wake attempts are leased to `serve` without changing CLI/MCP behavior.
- New `alln pending add` items are not reliably Project-scoped unless the caller
  supplies/binds `projectId`; unassigned dev records are repair-only/disposable
  and must not become watchdog targets.

Therefore the next implementation handoff is **WTK-S03**: add a narrow resident
one-shot wake loop for due workerChat Wake Tickets. Do not detour into broad
native drain or teamRun Pending execution first; CLI and MCP already expose the
workerChat path, and the utilization unlock is making `alln serve` resume one
due capacity-sleeping item at the sourced wake boundary. SWW stalled nudges
should wait until Wake Ticket suppression truth exists, otherwise expected
cooldown sleep will be mislabeled as stalled work.

## Feature Packet - Watchdog Prerequisite WTK-S00/S01a

Status: Shipped in `b331c2ae` (`core(wtk): add CapacityObservation contract and
classifier (WTK-S00/S01a)`). The full watchdog is not ready for end-to-end
handoff.

Founder Intent:

- Raw request: keep subscribed CLI agents from sitting idle after capacity
  cooldowns, and make Allnighter operable by other agents through CLI/MCP.
- Product value: Allnighter preserves already-authorized work, understands
  sourced cooldown/busy notices, and exposes machine-readable sleep/blocker facts.
- Trusted workflow slice: worker/Pending attempt hits capacity -> Allnighter
  captures `CapacityObservation` -> Pending JSON exposes `nextWakeAt`/blocker
  facts -> MCP Pending tools expose the same facts -> later Wake Ticket code can
  resume the same work once.
- Non-goals: no provider probes, no GUI, no native drain, no broad scheduler, no
  invented quota/runtime/cost estimates, no migration/backcompat shims.

Shipped:

- `CapacityObservation` model and `CapacityClassifier`.
- `PendingResumeReason.providerBusy` and optional `PendingResume.capacityObservation`.
- Pending JSON capacity projection and fixtures.
- MCP Pending tool specs for `pending_list`, `pending_show`, and `pending_run`.

Remaining gaps:

- WorkerRunner capture/classification shipped in WTK-S01b.
- WorkerChat Pending resume writing shipped in WTK-S02a; other team/thread call
  sites still need a narrow audit before they can claim Wake Ticket behavior.
- WorkerChat Pending execution/settlement shipped in WTK-S02a; teamRun and
  mutating Pending execution remain deferred.
- No live MCP Pending handlers in `MCPServer`.

SSOT:

- Truth owner: AllnighterCore owns `CapacityObservation`, Pending resume/blocker
  semantics, JSON schemas, fixtures, and classifier fixtures.
- Lie-prone layers: worker prose, CLI stderr text, Mac UI badges, MCP adapters,
  notifications, and prompt copy.
- New semantic rules:
  - account quota/rate limit and provider/server overload are distinct.
  - observed provider reset is stored only when sourced by CLI/API output.
  - local conservative retry windows use `wakeAfter`, not a fake provider reset.
  - auth/manual/setup blockers do not create Wake Tickets or stalls.
  - stale local/dev records without required Project truth are repair-only or
    disposable; do not preserve aliases for them.
- Duplicate truth to delete: any provider-specific cooldown parsing embedded
  directly in `WorkerRunner`, CLI command handlers, MCP adapters, or UI copy.

Implementation:

- CLI surface:
  - `alln pending show <id> --json`
  - `alln pending list --project <project> --json`
  - `alln pending list --all --json`
  - `alln project pending <project> --json`
  - These commands must project the same `PendingItemJSON` schema. WTK-S00/S01a
    added capacity fields to that schema and fixtures; WTK-S02a now populates
    them from real workerChat `pending run` execution.
- MCP tools:
  - `pending_show`, `pending_list`, and `pending_run` use the same
    `PendingItemJSON` / `PendingListJSON` schema and shared error envelope.
  - If live MCP handlers are not added in this first slice, the phase remains
    blocked for end-to-end watchdog handoff until A1 Pending-over-MCP lands.
- JSON shape:
  - Add a capacity observation object on the attempt/admission projection:
    `kind`, `source`, `sourceConfidence`, `observedAt`, `observedResetAt`,
    `retryAfterSeconds`, `wakeAfter`, and a redacted/truncated `rawSnippet`.
  - `kind` values: `accountRateLimit`, `providerBusy`, `cooldown`,
    `authRequired`, `manualRequired`, `unknownCapacity`.
  - `sourceConfidence` values should distinguish structured event/header,
    message fallback, local policy, and unknown.
  - `rawSnippet` is diagnostic only; no prompt body, secrets, tokens, cookies,
    or large transcripts.
- Exit codes/errors:
  - Read commands return exit 0 with empty arrays when no Pending/Wake facts exist.
  - Unknown Project returns the shared project-not-found error.
  - Unassigned Pending returns/records the existing unassigned/repair error and
    is not runnable or watchdog-eligible.
  - Classifier no-match is not an error; it yields no capacity observation.
- Model/package impact: add Core model + classifier, update Codable schemas,
  fixtures, registry docs, and generated artifacts.
- Mac app/iOS impact: none in this slice.
- Agent driver impact: worker driver output capture must preserve stdout/stderr/
  JSONL/RPC-ish error text long enough for the pure classifier to run before
  reducing failures to `errorReason`.
- Auth/privacy/permissions impact: no new credentials, Keychain access,
  network calls, provider pages, or macOS permissions.

Proof:

- Fixture tests for Claude `rate_limit_error`, Claude `overloaded_error`, Codex
  `codex exec --json` `error`/`turn.failed` usage-limit text, AGY cooldown-until
  text, auth/manual blockers, no-estimate, and no-false-positive cases.
- Schema/fixture tests prove Pending JSON exposes capacity facts without
  forecast fields.
- Registry/export check proves generated CLI docs and schemas match code.

Done:

- `CapacityObservation` exists in Core with fixture-tested classification.
- Pending JSON schema/fixtures expose sourced capacity facts for CLI/MCP clients.
- No stale migration/backcompat aliases are introduced for zero-user local data.
- WorkerRunner capture shipped in WTK-S01b; workerChat Pending execution and
  resume mapping shipped in WTK-S02a.
- A1 Pending-over-MCP live list/show/run handlers shipped in WTK-S02c; WTK-S03
  resident one-shot wake scheduling is the current workerChat Wake Ticket
  blocker.

## Feature Packet - WTK-S01b Worker Output Capture

Status: Shipped in `3fe9aae0` (`engine(wtk): wire CapacityClassifier into
WorkerRunner outcomes (WTK-S01b)`).

Founder Intent:

- Raw request: use actual CLI-to-CLI capacity notices instead of pinging stalled
  CLIs blindly.
- Product value: Allnighter preserves capacity facts from real worker attempts so
  later Pending/Wake code can sleep and resume correctly.
- Trusted workflow slice: worker CLI exits nonzero with capacity output ->
  `WorkerRunner` classifies stdout/stderr/exit code before reducing to
  `errorReason` -> `WorkerRunOutcome` / `WorkerAnswer` carries
  `CapacityObservation` for later Pending resume writers.
- Non-goals: no scheduler, no provider probes, no GUI/iOS, no live MCP handlers,
  no real Pending execution, no retry.

Current State:

- Existing truth owners: `CapacityObservation`, `CapacityClassifier`,
  `WorkerRunner`, `WorkerRunOutcome`, `WorkerAnswer`, `PendingResume`, and
  `PendingItemJSON`.
- Existing gaps: worker outcomes do not carry capacity observations, so team,
  thread, and future Pending execution paths would have to scrape `errorReason`.

SSOT:

- Truth owner: AllnighterCore owns the observation shape/classifier;
  AllnighterEngine owns attaching it to worker execution outcomes.
- Lie-prone layers: `errorReason` text, UI copy, MCP adapters, and future Pending
  resume writers.
- New/changed semantic rule: capacity observation must be captured from raw
  command stdout/stderr before any user-facing error reduction.
- Duplicate truth to delete/avoid: do not add provider-specific parsing at team,
  thread, Pending, MCP, or UI call sites.

Implementation:

- CLI/MCP surface: no new command or tool behavior in this slice. Existing JSON
  contracts already include `capacityObservation`; this slice only creates the
  Engine plumbing that future execution/settlement code will use.
- Model/package impact: add optional `CapacityObservation` to
  `WorkerRunOutcome` and, if needed, `WorkerAnswer`.
- Agent driver impact: `WorkerRunner.invoke` classifies raw `CommandResult`
  stdout/stderr/exitCode with the manifest/driver source id and runner clock.
- Auth/privacy/permissions impact: no new permissions, credentials, network
  calls, or provider pages.

Proof:

- WorkerRunner tests for Claude account limit, Claude provider busy, Codex JSONL
  stdout, auth/manual blockers, and successful output with capacity-like prose.
- Existing WorkerRunner behavior remains unchanged for status/errorKind/
  errorReason/output/exitCode/timings.

Done:

- Failed worker outcomes can carry sourced `CapacityObservation`.
- No successful worker answer is reclassified as a capacity failure.
- No scheduler, Pending execution, GUI, or MCP handler work lands.
- WTK-S02 and A1 live MCP Pending handlers remain explicitly named as blockers.

## Feature Packet - WTK-S02a WorkerChat Pending Execution

Status: Shipped in `0c4335c8` (`engine(wtk): execute and settle workerChat
pending run (WTK-S02a)`).

Shipped:

- `PendingRunExecutor` executes `workerChat` Pending items from CLI
  `alln pending run <id> --json`.
- `PendingService.beginRun` submits Draft items, records a running attempt, and
  applies a CLI lease.
- Worker output is written as `attempts/<attemptId>.txt` under the Pending store;
  `transcriptRef` is exposed on attempt summaries and generated schema.
- `PendingService.settleRun` maps success, ordinary failure, cooldown,
  providerBusy, auth/manual blockers, timeout, and cancellation into settled
  Pending state before the CLI returns.
- Capacity outcomes return the item to `pending` with `PendingResume` and
  `capacityObservation` where appropriate.

Still deferred:

- Live MCP Pending handlers.
- `teamRun` Pending execution.
- Mutating dispatch / work-order execution.
- Resident wake scheduler, broad drain, GUI/iOS, automatic retry, worker
  substitution, or prompt rewriting.

## Feature Packet - A1 / WTK-S02c Live MCP Pending Handlers

Status: Shipped in `79aa7cb8` (`mcp(wtk): live pending_list/show/run handlers
(WTK-S02c)`).

Founder Intent:

- Raw request: OpenClaw, Hermes, and other agent shells should operate
  Allnighter through a real machine contract, not by scraping CLI text.
- Product value: external agents can list, inspect, and explicitly run Pending
  work through MCP with the same JSON facts as `alln pending`.
- Trusted workflow slice: external agent calls MCP `pending_list` -> chooses a
  submitted item -> calls MCP `pending_run` -> Allnighter invokes the same
  `PendingRunExecutor` path as CLI -> returns settled `PendingItemJSON` with
  capacity/wake facts when blocked.
- Non-goals: no scheduler, wake timers, broad drain, GUI/iOS, teamRun Pending
  execution, mutating dispatch/work-order execution, automatic retry, worker
  substitution, prompt rewriting, or MCP-only JSON.

Current State:

- Registry specs for `pending_list`, `pending_show`, and `pending_run` exist and
  generated `mcp-tools.json` was updated by WTK-S00/S01a.
- CLI `pending list`, `pending show`, and workerChat `pending run` are the
  semantic source for the MCP handlers.
- `MCPServer` still does not expose live Pending handlers.

SSOT:

- Truth owner: AllnighterCore owns `PendingItemJSON`, `PendingListJSON`,
  `ErrorEnvelope`, and the MCP registry specs; AllnighterEngine owns
  `PendingRunExecutor`; `MCPServer` is only an adapter.
- Lie-prone layers: MCP result text, hand-written tool JSON, CLI summary copy,
  external agent prompts, and generated docs.
- New/changed semantic rules:
  - MCP `pending_*` handlers must use the same Core/Engine code path and JSON
    schemas as CLI.
  - MCP may add human-readable result text, but the structured JSON string must
    match `PendingItemJSON` / `PendingListJSON`.
  - `pending_run` over MCP is explicit user/agent-triggered work, not resident
    scheduling.
  - `origin` is `mcp` for new MCP attempts/provenance; `originAgent` is metadata,
    not authorization.
- Duplicate truth to delete/avoid: no MCP-only Pending models, no separate MCP
  cooldown parser, no transcript inlining, and no friendlier alternate JSON.

Implementation:

- Add live `MCPServer` handlers for `pending_list`, `pending_show`, and
  `pending_run`.
- `pending_list` returns `PendingListJSON` using the same mapper/service as CLI
  list. Support the contract's `limit`, `cursor`, and status/project filters
  where those already exist; do not invent a parallel paging model.
- `pending_show` requires a Pending id and returns one `PendingItemJSON`.
- `pending_run` calls the same `PendingRunExecutor` path used by CLI
  `alln pending run`.
- Unsupported kinds preserve current CLI semantics:
  - workerChat executes and settles.
  - dispatch / mutating execute returns `PENDING_MUTATION_DEFERRED`.
  - teamRun, followUp, returnReview, and workOrder stay unsupported unless a
    real existing safe path already handles them.
- Use the existing MCP tool-result envelope and shared error envelope. Do not
  expose richer capacity truth than CLI.

Proof:

- `tools/list` includes `pending_list`, `pending_show`, and `pending_run` with
  current schemas, errors, and idempotency metadata.
- MCP `pending_list` returns the same `PendingListJSON` shape as CLI/Core.
- MCP `pending_show` returns one `PendingItemJSON`; not-found and usage failures
  use the shared error envelope.
- MCP `pending_run` on workerChat invokes `PendingRunExecutor` and returns the
  settled item.
- MCP `pending_run` on a capacity failure returns a pending item with
  `PendingResume`, `capacityObservation`, and `nextWakeAt`.
- MCP `pending_run` on unsupported kinds returns the same error semantics as CLI
  and does not spawn a worker.
- List/show JSON contains `transcriptRef` only, never transcript body content.
- Existing ContractRegistry, MCP contract, PendingService, and PendingRunExecutor
  tests remain green.

Done When:

- External MCP clients can list, inspect, and run eligible workerChat Pending
  items without scraping CLI text.
- MCP Pending outputs are contract-parity projections of CLI/Core JSON.
- No scheduler, GUI/iOS, teamRun Pending execution, mutating dispatch/work-order
  execution, automatic retry, worker substitution, or prompt rewriting lands.
- Remaining blockers are explicitly WTK-S02b teamRun Pending execution, WTK-S03
  one-shot wake scheduler, and WTK-S01c other call-site resume writers.

## Feature Packet - WTK-S03 One-Shot Wake Scheduler

Status: Ready for implementation as the next narrow wake slice.

Founder Intent:

- Raw request: subscribed CLI agents should not sit idle after a sourced
  cooldown/capacity boundary when the work is already authorized.
- Product value: `alln serve` becomes the local, honest wake owner for sleeping
  workerChat Pending items while external agents keep the same MCP controls.
- Trusted workflow slice: workerChat Pending attempt hits capacity -> S02a stores
  `PendingResume` with `nextWakeAt` -> S02c exposes it over MCP -> `alln serve`
  sleeps until the earliest due wake -> reloads truth -> makes one same-work
  `PendingRunExecutor` attempt -> success clears resume, a new sourced cooldown
  replaces it, ordinary failure settles normally.
- Non-goals: no broad drain, no fairness sweep, no idle Pending scheduling, no
  teamRun Pending execution, no mutating dispatch/work-order execution, no
  provider probes, no GUI/iOS, no worker substitution, no prompt rewriting, no
  scheduler-owned new work.

Current State:

- `ResidentCoordinator` owns foreground `alln serve` health state only.
- `PendingRunExecutor` can execute and settle one `workerChat` Pending item.
- `PendingItemDerivation.nextWakeAt` already derives
  `resume.observedResetAt ?? resume.wakeAfter`.
- CLI and MCP can list/show/run Pending with the same JSON.
- `PendingLeaseOwner` already has `.serve`, but `beginRun` currently defaults to
  `.cli`; the scheduler needs a small owner/attempt-reason seam.

SSOT:

- Truth owner: AllnighterCore owns `PendingResume`, `nextWakeAt`, and
  `PendingItemJSON`; AllnighterEngine owns resident wake scheduling and attempt
  execution.
- Lie-prone layers: timers, health copy, MCP summaries, CLI stderr, and future UI
  badges.
- New/changed semantic rules:
  - Only Pending items with status `pending`, kind `workerChat`, Project truth,
    and resume reason `cooldown` or `providerBusy` are wake-eligible.
  - A Wake Ticket is due only when `nextWakeAt <= now`.
  - Items without `nextWakeAt`, without `projectId`, with auth/manual blockers,
    or with unsupported kinds are skipped and not marked failed by the scheduler.
  - The scheduler re-loads the item immediately before running it; stale in-memory
    snapshots cannot start work.
  - One scheduler wake attempt is just a normal `PendingRunExecutor` attempt with
    lease owner `serve`; settlement remains owned by `PendingService`.
  - A new sourced cooldown replaces the old resume ticket. Success clears it.
- Duplicate truth to delete/avoid: no separate wake queue, no copied
  `nextWakeAt` store, no provider-specific parser in the scheduler, and no MCP
  or GUI-only wake state.

Implementation:

- Add a small Engine wake planner/scheduler, name flexible:
  `PendingWakeScheduler`, `WakeTicketScheduler`, or similar.
- Selection:
  - load ordered Pending items from `PendingStore`;
  - filter to status `pending`, kind `workerChat`, non-nil `projectId`, resume
    reason `cooldown` or `providerBusy`, and `nextWakeAt != nil`;
  - choose the earliest due item first;
  - expose a pure function for tests that returns next due item and next sleep
    deadline.
- Execution:
  - add a narrow `PendingRunExecutor` / `PendingService.beginRun` option for
    lease owner and attempt reason, defaulting to existing CLI behavior;
  - resident wake calls the executor with lease owner `.serve` and an attempt
    reason like `wakeTicket`;
  - preserve CLI and MCP run behavior.
- Coordinator:
  - wire the scheduler into `ResidentCoordinator.run` after health state is saved;
  - run until shutdown, respecting SIGINT/SIGTERM cancellation;
  - sleep until the earliest wake plus small deterministic/injectable jitter;
  - after each wake attempt, reload store and compute the next deadline;
  - do not run a tight loop when there are no due tickets.
- Observability:
  - keep `serve --health --json` shape stable unless a minimal optional
    wake-summary field is already covered by contract tests;
  - no notification or GUI work in this slice.

Proof:

- Fake-clock/fake-sleeper tests for due selection, earliest deadline, and no
  busy-loop when no tickets exist.
- Scheduler skips Draft, Done, Failed, Running, idle Pending without resume,
  unsupported kinds, unassigned items, auth/manual blockers, and future wakes.
- Due workerChat wake invokes `PendingRunExecutor` exactly once with lease owner
  `.serve`.
- Success clears resume; new cooldown/providerBusy replaces wake facts; ordinary
  failure settles normally; unsupported kind is skipped rather than spawned.
- Resident coordinator starts health and wake loop, and shuts down without
  leaving durable coordinator state.
- Existing PendingRunExecutor, MCPPendingHandlers, PendingService, and
  Coordinator tests remain green.

Done When:

- `alln serve` can resume one due workerChat Wake Ticket without a user or MCP
  client manually calling `pending_run`.
- The scheduler does not touch idle Pending or unsupported work.
- The scheduler does not probe providers, rewrite prompts, switch workers, or
  create new work.
- Remaining blockers are explicitly WTK-S02b teamRun Pending execution,
  WTK-S01c other call-site resume writers, and WTK-S04 suppression/fallback.

## Copy-Paste Developer Prompt - WTK-S03

```text
You are implementing WTK-S03 for Allnighter: a resident one-shot wake scheduler
for due workerChat Wake Tickets.

Goal:
Make `alln serve` resume already-authorized workerChat Pending items once their
sourced capacity/cooldown wake boundary is due.

Do not implement broad drain, fairness sweeps, idle Pending scheduling, teamRun
Pending execution, mutating dispatch/work-order execution, provider probes,
GUI/iOS, automatic worker substitution, prompt rewriting, or scheduler-created
new work.

Read first:
- AGENTS.md
- docs/workflows/SSOT_Founder_Input_Workflow.md
- docs/workflows/SSOT_Feature_Workflow.md
- docs/phases/Stalled_Work_Watchdog.md
- docs/phases/Pending_Work_And_Drain.md
- docs/phases/CLI_Implementation_Contract.md
- docs/phases/Agent_First_MCP_And_Messaging_Workflows.md

Code reality:
- WTK-S00/S01a landed in b331c2ae.
- WTK-S01b landed in 3fe9aae0.
- WTK-S02a landed in 0c4335c8: CLI `alln pending run <id> --json` executes and
  settles workerChat Pending through PendingRunExecutor.
- A1/WTK-S02c landed in 79aa7cb8: MCP pending_list/show/run handlers are live.
- Pending JSON includes capacityObservation, nextWakeAt, and
  attempts[].transcriptRef.
- ResidentCoordinator is still health-only.
- PendingItemDerivation.nextWakeAt already derives observedResetAt ?? wakeAfter.
- PendingLeaseOwner has `.serve`, but PendingService.beginRun currently defaults
  to CLI ownership.
- We have zero users: no production migrations or stale compatibility shims.

Implement WTK-S03 only:
1. Add a small Engine wake planner/scheduler, name flexible.
2. Wake eligibility:
   - item.status == pending
   - item.kind == workerChat
   - item.projectId is non-nil
   - item.resume.reason is cooldown or providerBusy
   - nextWakeAt exists and is <= now
3. Skip, without failing, Draft/Running/Done/Failed/Cancelled items, idle Pending
   without resume, auth/manual blockers, unsupported kinds, unassigned items, and
   future wakes.
4. Add a pure planner function for tests that returns:
   - the earliest due item id, if any
   - the next future wake deadline, if any
   - enough reason/debug data to prove skip behavior without exposing new public
     JSON unless necessary.
5. Add a narrow lease/provenance seam:
   - PendingService.beginRun and/or PendingRunExecutor should accept leaseOwner
     and attemptReason options.
   - Defaults must preserve current CLI/MCP behavior.
   - Resident wake uses leaseOwner `.serve` and attemptReason `wakeTicket`.
6. Wire the scheduler into ResidentCoordinator.run:
   - health server/state still starts first;
   - scheduler runs until shutdown and respects SIGINT/SIGTERM cancellation;
   - it sleeps until the earliest wake plus small deterministic/injectable jitter;
   - it reloads Pending truth immediately before executing;
   - after one wake attempt, it recomputes the next deadline.
7. Use PendingRunExecutor for execution and PendingService for settlement. Do not
   add a separate wake queue or duplicate Pending state.
8. Keep serve --health --json stable unless a minimal optional wake field is
   explicitly added with contract/schema tests.

Required tests:
1. Planner selects the earliest due workerChat Wake Ticket.
2. Planner returns a future deadline and performs no run when all Wake Tickets are
   in the future.
3. Planner skips Draft, Running, Done, Failed, Cancelled, idle Pending without
   resume, auth/manual blockers, unsupported kinds, unassigned items, and items
   without nextWakeAt.
4. Due wake invokes PendingRunExecutor exactly once with leaseOwner `.serve`.
5. Success clears resume; a new cooldown/providerBusy replaces wake facts;
   ordinary failure settles normally.
6. The coordinator can start health plus wake loop and shut down cleanly without
   leaving durable coordinator state.
7. Existing PendingRunExecutor, MCPPendingHandlers, PendingService, Coordinator,
   ContractRegistry, and MCP contract tests remain green.

Proof commands:
- swift test --disable-sandbox --package-path Packages/AllnighterCore --filter 'PendingWake|ResidentCoordinator|CoordinatorTests|PendingRunExecutorTests|PendingServiceTests'
- swift test --disable-sandbox --package-path Packages/AllnighterCore --filter 'MCPPendingHandlers|MCPToolContractTests|ContractRegistryTests'
- swift run --disable-sandbox --package-path Packages/AllnighterCore alln dev export-contracts --check

Closeout:
- State that WTK-S03 landed: alln serve can resume due workerChat Wake Tickets.
- State that no broad drain, teamRun Pending execution, mutating dispatch,
  provider probes, GUI/iOS, worker substitution, prompt rewriting, or new work
  creation was added.
- State remaining blockers: WTK-S02b teamRun Pending execution, WTK-S01c other
  call-site resume writers, and WTK-S04 watchdog suppression/fallback.
- Commit only explicit changed files with a clear message.
```

## Founder Intent

Allnighter should keep Project work moving after the user walks away.

The important user question is not:

```text
Can Allnighter predict quota, runtime, or cooldowns?
```

It is:

```text
Did the work I asked for get stuck, and what should I do next?
```

The better first question is:

```text
Did the worker stop because it was expected to sleep, or did work go quiet when
it should still be moving?
```

The Project Manager should notice old nonterminal work from local truth, create
one durable nudge in the right Project, and offer safe recovery actions without
becoming a quota brain, global queue, or broad background scheduler.

Expected capacity cooldown is not a stall. When a CLI says "try again at T" or
"retry after N," Allnighter should preserve the already-authorized work, sleep
silently until that observed boundary, and make one same-work resume attempt.

## Product Claim

```text
The Project Manager notices when Project work stops moving, lets expected
cooldowns sleep, and gives you one safe next move when human judgment is needed.
```

It should feel like:

```text
The Project Manager knows this Project has a run that has not moved, checked the
local truth before bothering me, and can help me refresh, wait, open, or cancel.
```

It must not feel like:

```text
A timer that nags, a second job tracker, a quota predictor, a polling loop, or
an agent that invents new work behind my back.
```

## First-Principles Decision

Stalled work is a recovery loop, not admission control.

There are two different silences:

| Silence | Meaning | Owner |
| --- | --- | --- |
| Sleep | A worker stopped and produced a sourced capacity/cooldown signal. | Pending Resume / Wake Ticket |
| Stall | Work should be moving, but local truth stopped changing. | Stalled Work Watchdog |

The watchdog owns unexpected silence. Wake Tickets own expected cooldown sleep.
Do not combine them into a provider polling loop.

Admission asks:

```text
Should a worker start now?
```

The watchdog asks:

```text
Work already started or was queued for start. Has local truth stopped changing
long enough that the Project Manager should ask the user to decide?
```

Therefore v1 uses only observed local truth:

- Project id;
- thread/run/turn status;
- journal or stage events;
- known terminal outcomes;
- known auth/setup/manual blockers;
- notification mute/debounce settings;
- user decisions on the current stall episode.

It does not estimate quota, cost, token burn, reset windows, runtime, task
complexity, or provider capacity.

Wake Tickets may use observed reset/cooldown times only when they come from a
worker attempt, CLI structured event, JSONL event, stderr/stdout, RPC error, or
user-entered recovery fact. They are sourced wake contracts, not capacity
predictions.

## Trusted Workflow Slice

Expected cooldown:

```text
worker attempt exits/blocks with sourced capacity signal
-> Allnighter records a CapacityObservation
-> the already-authorized work becomes Pending/Sleeping with PendingResume
-> resident coordinator waits until observed reset / wakeAfter plus jitter
-> Allnighter makes one same-work resume attempt
-> success clears the resume ticket; a new sourced cooldown updates it
-> repeated/unknown failure routes to Project Manager attention
```

Unexpected silence:

```text
worker chat turn or async team run enters queued/running
-> watchdog records the last observable local event
-> deadline passes with no new event
-> watchdog refreshes status from existing local truth
-> if still nonterminal and still no progress, create one Project Manager nudge
-> Mac notification points to that nudge when allowed
-> user checks status, opens the thread, keeps waiting, or cancels
-> stall episode clears when local truth moves terminal or user recovery ends it
```

## V1 Scope

V1 targets only the two cases with the clearest signal and highest user pain:

| Target | Included states | Default threshold | Why v1 |
| --- | --- | --- | --- |
| Capacity sleep / Wake Ticket | blocked attempt with sourced capacity signal and already-authorized work | observed reset / retry-after, else conservative backoff | This is the overnight utilization unlock: do not call expected cooldown a stall; resume once at the boundary. |
| Worker chat turn | `queued`, `running` | 30 minutes since last observable event | The user asked one worker for an answer and nothing came back. |
| Async team run | `queued`, `running`, nonterminal worker stage | 60 minutes since last observable event | Team runs are core Allnighter value and already have status/result refresh paths. |

The defaults are intentionally boring. They are product defaults, not
predictions. They can become per-Project/user settings after real dogfood
evidence shows the noise shape.

Deferred from v1:

- idle Pending items that have not been run;
- approved proposals or work orders that have not been dispatched;
- dispatch return review follow-ups;
- broad native drain/scheduler loops;
- admission ledgers, quota accounting, and capacity routing;
- continuous provider probes or keepalive pings;
- cooldown resume for work that was not already user-authorized;
- worker substitution;
- prompt rewriting;
- retry that creates new work or changes the worker/prompt without approval.

Pending may be "blocked" or "needs attention," but idle Pending is not
stalled. Pending means work is on the Project desk until a user or external loop
owner runs it.

A Wake Ticket is not idle Pending. It is a submitted or already-running item
that attempted real work, hit a sourced capacity/cooldown boundary, and has an
observed or conservative wake time for one same-work resume.

## Project Law

Every stall candidate must resolve to exactly one Project.

Rules:

- A candidate without a reliable `projectId` is a repair/unassigned problem, not
  a stalled-work nudge.
- Stalls in one Project must not block, reorder, or reprioritize another
  Project.
- Project root truth comes from `ProjectStore`; raw `workingDir` values are
  historical receipts only.
- The durable nudge is a `ProjectManagerTurn` for that Project with typed
  `nextActions`.
- The target thread receives the existing `thread.needsAttention` signal with a
  `stallReason` facet. Do not create a parallel attention system.
- Global stalled views are aggregate floor views grouped by Project. They are
  not a global durable queue.
- Project Manager triage order comes from the same Home/Project triage contract
  used by threads and notifications, not watchdog scan order.

## Dependency On Project Spine

The watchdog is Project Manager behavior. It should not ship as a global run
scanner ahead of the Project floor.

Minimum Project Spine dependencies:

- durable Projects exist;
- new threads and runs can resolve `projectId`;
- Project context can include active runs and attention records;
- Project Manager turns can carry typed `nextActions`;
- notifications can open the linked Project/thread/turn.

Rules:

- Before a target can resolve `projectId`, the scanner must emit no stalled
  episode for it. It may surface a repair/unassigned warning through the owning
  repair path.
- Active stalls may be summarized in `ProjectContextPacket.work`, but the
  packet is a receipt. `StallEpisode` remains the durable stall truth.
- Non-git folder Projects may still have stalled chat/team-run attention, but
  recovery remains limited to safe actions. They can never gain commit-proof
  semantics from the watchdog.

## State Distinctions

The watchdog must not relabel every old item as stalled.

| State | Truth owner | Watchdog role |
| --- | --- | --- |
| Terminal failure, timeout, cancellation, or completion | Turn/run lifecycle + notification policy | Do not create a stalled nudge. Existing failure/completion attention owns it. |
| Auth/setup/manual-paste blocked | Worker readiness, turn state, or notification events | Surface setup/manual copy through existing attention. Do not call it stalled. |
| Capacity sleeping | Pending resume / Wake Ticket | Suppress stalled nudges while `wakeAfter` or `observedResetAt` is in the future. |
| Idle Pending | Pending model | Do not call it stalled. It is waiting for a user, CLI, GUI, MCP client, or external loop owner to run it. |
| Blocked Pending | Pending model + admission/safety reason | Keep the Pending label and sourced blocker. It may need attention, but it is not stalled. |
| True stall | Stalled Work Watchdog | Nonterminal queued/running work in one Project with no local progress past threshold after refresh. |

Canonical active stall states:

```text
candidate -> refreshing -> active -> snoozed -> cleared
```

`candidate` and `refreshing` are internal. The user sees only `active`,
`snoozed`, or cleared history.

## Progress Signal

V1 uses cheap progress signals already present in local truth. It does not run a
provider probe to decide whether something is stalled.

`lastObservableEvent` is the newest of:

- turn status change;
- run/team stage status change;
- journal append for that turn/run/stage;
- worker answer/result chunk committed to durable thread/run truth;
- explicit user recovery action;
- terminal result observation.

If process liveness is already recorded by the run subsystem, it may contribute
as a sourced event. The watchdog must not add a separate process monitor in v1.

A stall is eligible only when both are true:

```text
target is still nonterminal
lastObservableEvent.at is older than the target threshold
```

Before promotion to `active`, the scanner must refresh from the existing status
path for that target. For async team runs this means the same source of truth
used by `team_status` / `team_result`. For worker chat turns this means the
thread/run store and any existing journal finalization path.

The watchdog must not create a watchdog-only result schema. Team-run refresh
continues to project the shared async team contracts and `TeamRunJSON` result
shape.

If refresh finds terminal completion, failure, timeout, cancellation, auth
required, or manual action required, the candidate is suppressed and routed to
the existing owner.

If refresh finds a future `wakeAfter` / `observedResetAt`, the candidate is
suppressed as capacity sleeping. Cooling work is not stale just because no local
event occurs during the sleep window.

## Capacity Observation

Truth owner: `AllnighterCore` model + `AllnighterEngine` driver adapters.

`CapacityObservation` is the small, sourced fact that turns worker output into a
Wake Ticket. It is not a quota ledger.

```text
CapacityObservation
  id
  projectId?
  threadId?
  runId?
  pendingItemId?
  attemptId?
  workerId
  sourceId
  kind: accountRateLimit | providerBusy | cooldown | authRequired |
        manualRequired | unknownCapacity
  observedAt
  observedResetAt?
  retryAfterSeconds?
  wakeAfter?
  source: structuredEvent | jsonlEvent | rpcError | stderr | stdout |
          exitCode | userEntered
  sourceConfidence: high | medium | low
  rawSnippet
```

Rules:

- Prefer structured CLI/API/RPC events over message parsing.
- Message parsing is allowed only on the worker attempt's own stdout/stderr,
  JSONL events, or local RPC error text. No provider web scraping.
- `observedResetAt` means the worker/provider gave the time or duration. If the
  time is derived from local backoff, store only `wakeAfter` and label the source
  as local policy in UI copy.
- `providerBusy` / overload is different from `accountRateLimit`: overload may
  use short backoff or explicit fallback; account limit preserves the same item
  until reset.
- `authRequired` and `manualRequired` never auto-resume.
- `unknownCapacity` may schedule a conservative one-shot retry only when policy
  permits; otherwise it routes to the Project Manager nudge path.
- Keep `rawSnippet` short and sanitized. It is a receipt, not a transcript.

Wake Ticket projection:

```text
CapacityObservation(accountRateLimit/cooldown, observedResetAt or retryAfter)
-> PendingResume(reason: cooldown, observedResetAt, wakeAfter)
-> attempt.status = blocked
-> attempt.reason = sourced capacity reason
-> item.status = pending
```

`providerBusy` should use a separate resume reason (`providerBusy`) rather than
`localBusy`; local busy means the user's machine or Allnighter process capacity
is occupied.

## CLI-To-CLI Capacity Conventions

These conventions are implementation fixtures, not universal promises. Adapters
must fail closed to generic message classification when a specific version does
not expose the expected machine signal.

| Source | Preferred capture | Useful fields | Fallback |
| --- | --- | --- | --- |
| Claude Code CLI | Structured error JSON / nonzero attempt result. | Distinguish `rate_limit_error` from `overloaded_error`; use `retry-after` or reset text when exposed. | First non-empty stderr/stdout line containing rate/capacity/wait language. |
| Codex CLI | `codex exec --json` JSONL `error` / `turn.failed` messages. | Classify `usage_limit_reached`, credits/spend-cap copy, and capacity messages; richer `resetsAt` lives behind app-server rate-limit notifications when available. | Nonzero exit + message classification. |
| AGY CLI | Local server/RPC or stderr error text. | Parse `capacity exhausted: cooldown active until <timestamp>` as high-confidence cooldown. | Nonzero exit + stderr/stdout classification. |

General adapter rules:

- Capture both machine events and raw failure text before `WorkerRunner` reduces
  output to `errorReason`.
- Treat process exit as the attempt boundary. Most CLIs will not send a later
  out-of-band notice after they stop.
- Use the real authorized attempt as the baseline observation. Do not run
  separate probes while cooling down.
- Optional smoke/probe at wake time is a later policy choice, not the default
  v1 contract.

## Core Model

Truth owner: `AllnighterCore`.

```text
StallEpisode
  id
  projectId
  targetKind: workerTurn | teamRun
  targetId
  threadId
  runId?
  status: active | snoozed | cleared
  reason: queuedNoStart | runningNoProgress | statusUnknownNoProgress
  firstDetectedAt
  deadlineAnchorAt
  thresholdSeconds
  lastObservableEvent
    at
    kind
    source
    summary
  lastRefreshAt?
  lastNudgeTurnId?
  lastNudgeAt?
  snoozedUntil?
  clearedAt?
  clearedBy?: terminalResult | userCancel | userRetry | userDismiss |
              refreshedOut | targetDeleted
  primaryAction
  secondaryActions[]
```

Episode rules:

- Idempotency key: `(targetKind, targetId, id)`.
- At most one non-cleared episode exists for a target.
- A new episode starts only after the previous episode cleared and the same
  target later becomes newly eligible, or a retry/new attempt creates a new
  target id.
- `Keep waiting` sets `status = snoozed` and `snoozedUntil`; it does not clear
  the episode.
- Scanner reads `snoozedUntil` from durable state. Snooze is never memory-only.
- `lastNudgeAt` prevents duplicate Project Manager turns and notifications for
  the same episode.
- An ignored nudge does not auto-escalate. Repeat notification requires a user
  snooze that expires or a meaningful target state change.
- The episode clears automatically when refresh/local truth observes a terminal
  result or a non-stall owner state such as auth/manual blocker.
- Clearing an episode does not delete the historical Project Manager turn.

No `StallEpisode` fields may represent estimated runtime, cost, quota,
complexity, or reset windows. Observed reset/wake facts belong to
`CapacityObservation` / `PendingResume`, not to stalled-work truth.

## Scan Triggers

This is a coarse watchdog, not a precision scheduler. Wake Tickets use their own
one-shot wake timer; the watchdog does not poll providers on their behalf.

Run the scanner:

- when a watched target enters `queued` or `running`;
- when a watched target records a new local observable event;
- on a coarse periodic interval while the Mac app backend or resident
  coordinator is running;
- after app launch/resident restart;
- after sleep/wake, but only after refreshing status.

Default periodic interval:

```text
5 to 15 minutes
```

The exact interval is implementation policy. It must be coarse enough to avoid
becoming a provider polling loop.

App-closed behavior:

- If the resident coordinator is not running, v1 makes no app-closed stall or
  wake promise.
- On next launch/resident start, the scanner refreshes before declaring stale
  work stalled.
- Sleep/wake may make timestamps look old. Refresh-before-declare is mandatory
  to avoid a burst of false nudges.

## Wake Ticket Scheduler

The Wake Ticket scheduler is deliberately smaller than native Pending drain.

```text
load Pending items with PendingResume.nextWakeAt
-> choose the earliest due item
-> sleep until wakeAfter plus 30-90 seconds jitter
-> reload stores and Project/thread/run truth
-> if still eligible, make one same-work resume attempt
-> on success, clear resume
-> on new cooldown, replace wakeAfter from the new CapacityObservation
-> on auth/manual/permanent failure, route to existing attention
-> on repeated unknown failure, let SWW create a nudge
```

Rules:

- During cooldown, make zero provider calls.
- At the wake boundary, default to the real authorized work attempt. A smoke
  probe is optional future policy only when it is cheaper/safer and fixture
  proven for that driver.
- Resume only work the user already authorized: submitted Pending, a user-sent
  worker turn, or an explicitly approved work order. Do not auto-create new
  work from model prose.
- The scheduler may start with one item at a time: the interrupted head item.
  Full multi-Project fairness and Away Mode remain parked.
- Manual `pending run` may override a wake and attempt immediately.
- A future wake suppresses stall detection. A past due wake that repeatedly
  fails without a new sourced wake can become stalled/needs-attention.
- Resident restart recalculates the next wake from durable Pending/attempt state;
  in-memory timers are never authority.

## Project Manager Nudge

A stalled nudge is a durable Project Manager turn. The notification is only a
pointer.

Minimum `ProjectManagerTurn` projection:

```text
ProjectManagerTurn
  mode: wait
  projectId
  threadId: project.managerThreadId
  contextPacketId?
  warnings[]
  nextActions[]
  stallEpisodeId
```

Fixed facts block:

```text
What you asked for: <title>
Current status: <enum from local truth>
Last change: <timestamp + event kind + source>
Waiting since: <deadline anchor>
Suggested next move: <one primary action>
```

Rules:

- The nudge must name the Project.
- The nudge must link to the target thread/run/turn.
- The nudge must be source-labeled. No provider guesses.
- The nudge offers one primary action and demotes the rest.
- The nudge is created only after refresh confirms the item is still eligible.
- If the target thread is already visible/read, local notification delivery may
  be suppressed, but the durable nudge still exists when the episode is active.

Primary action policy:

| Reason | Primary action | Secondary actions |
| --- | --- | --- |
| `queuedNoStart` | `Cancel` when no worker has started, otherwise `Open thread` | `Check status`, `Keep waiting` |
| `runningNoProgress` | `Check status` | `Open thread`, `Keep waiting`, `Cancel` |
| `statusUnknownNoProgress` | `Open thread` | `Check status`, `Keep waiting`, `Cancel` |

`Retry` is not a silent watchdog action in v1. The Project Manager may help the
user create a new proposal/work order or restart path after an explicit cancel
or human approval, but the watchdog itself does not rewrite prompts, choose a
new worker, or start a replacement attempt.

## Recovery Actions

All actions are explicit and Project-scoped.

| Action | Effect |
| --- | --- |
| `Check status` | Refresh the target from existing local truth. If terminal or owner-blocked, clear/suppress the stall. If still stalled, update `lastRefreshAt` without creating a duplicate nudge. |
| `Open thread` | Navigate to the linked Project/thread/turn. Does not change episode state by itself. |
| `Keep waiting` | Set `snoozedUntil` using the same default threshold as the target unless the user picks a specific duration. Keeps attention visible but suppresses repeat nudges until snooze expires or state changes. |
| `Cancel` | Calls the existing safe cancel path for that target. On success, target becomes terminal `cancelled` and the episode clears. On failure, keep the episode active and show the sourced failure. |
| `Dismiss` | Clears only the nudge/episode attention, not the underlying run. Use sparingly in UI; prefer `Keep waiting` when work may still be running. |

Clear rules:

- Terminal refresh clears the episode silently; no "all good" turn is required.
- User cancel clears only after the target reports cancelled.
- Keep waiting does not clear; it snoozes.
- Opening the thread does not clear; viewing is not recovery.
- Target deletion or loss of Project binding clears with `targetDeleted` and
  should leave a repair warning when appropriate.
- A retry/new attempt gets a new target id or new episode; it does not mutate the
  historical episode into success.

## Notification Integration

Mac local notifications are governed by
`docs/phases/threads/02_Notifications.md`.

Rules:

- A stalled episode emits `thread.needsAttention` with a `stallReason` facet.
- Local notification delivery is content-light and points to the Project/thread
  at the nudge turn.
- Respect global notification settings, quiet hours, per-thread mute, and
  debounce.
- Emit at most one notification per stall episode unless the user snoozes and
  the snooze expires while the target is still stalled.
- Do not emit a stalled notification merely because persisted state was reread
  on app restart.
- Do not double-notify terminal failures, auth-required turns, or manual-paste
  blockers; their existing notification events own those cases.

Default copy examples:

```text
Allnighter work may be stalled in "Fix team setup UX"
Team run needs a decision in "Allnighter"
Codex has not moved in "Project Manager spine"
```

No secrets or prompt bodies in notification text by default.

## CLI And MCP Contract

CLI/MCP are product and integration surfaces, not afterthoughts. The Project
Manager nudge is the primary human UX, but external agents must be able to
inspect the same facts through `alln` and MCP without scraping GUI copy.

Wake/Pending capacity projection ships through the Pending contract first:

```text
alln pending show <pending-id> --json
alln pending list --project <project-id-or-name> --json
alln pending list --all --json
alln project pending <project-id-or-name> --json
```

MCP parity targets:

```text
pending_show
pending_list
pending_run
```

Capacity JSON must be the same shape for CLI and MCP:

```json
{
  "kind": "accountRateLimit",
  "source": "claude-code",
  "sourceConfidence": "structured",
  "observedAt": "2026-06-19T09:15:00Z",
  "observedResetAt": "2026-06-19T12:00:00Z",
  "retryAfterSeconds": 9900,
  "wakeAfter": "2026-06-19T12:00:00Z",
  "rawSnippet": "You've been rate limited..."
}
```

Rules:

- `rawSnippet` is redacted/truncated diagnostic text only. It must not include
  prompt bodies, secrets, tokens, cookies, or large transcripts.
- `observedResetAt` is present only when the CLI/API/source provided a reset
  time.
- `wakeAfter` may be a conservative local retry boundary, but copy must say it is
  local policy rather than provider truth.
- Auth/setup/manual blockers may be classified for attention, but they do not
  create Wake Tickets or stalls.
- Empty read-only lists return exit 0 with empty arrays.
- Unknown Project returns the shared Project-not-found error.
- Unassigned Pending/thread targets are repair-only/disposable local data and
  are not runnable or watchdog-eligible.

Project-scoped CLI:

```text
alln project stalled <project-id-or-name> --json
alln project stalled <project-id-or-name> --include-cleared --json
```

Aggregate CLI:

```text
alln stalled list --all --json
```

Rules:

- Project command output is authoritative for one Project.
- Aggregate output groups by Project and must not become a global queue.
- JSON mirrors the same Core `StallEpisode` ids, status, facts block, and
  `nextActions` visible to the Project Manager.
- Read-only CLI ships before mutating CLI recovery commands.
- External loop owners may use the read-only list as a signal to message the
  user or call normal Project Manager tools. This does not make Allnighter own
  their scheduler.
- MCP may expose `project_stalled` and `stalled_list` only as projections of the
  same Core state.
  MCP must not invent MCP-only stall semantics or self-approve recovery.

## Privacy And Permissions

Rules:

- Stall scanning is local-first.
- No new provider credentials, Keychain entries, Full Disk Access, network
  permissions, or cloud storage are justified by this phase.
- The watchdog does not open provider account pages, scrape provider UI, accept
  prompts, or run quota probes.
- Recovery actions use existing run/thread cancel and navigation paths.
- Any future background behavior that changes macOS permission posture routes
  through the high-risk stop policy before implementation.

## Non-Goals

- No quota, billing, reset-window, cost, token, runtime, or complexity
  prediction.
- No provider scraping.
- No native scheduling/drain revival.
- No automatic retry from stalled-work nudges. Wake Tickets may perform their
  scoped one-shot same-work resume.
- No silent worker substitution.
- No prompt rewriting.
- No cross-Project queue.
- No new terminal viewer.
- No branch/worktree/commit manager.
- No iOS-first implementation.
- No global "all work is stalled" truth owner.

## Implementation Impact

Core:

- Add `CapacityObservation` fixture/schema and map it to `PendingResume`.
- Add `PendingResumeReason.providerBusy` (or equivalent) so provider overload is
  not mislabeled as local machine/process busy.
- Add `StallEpisode` and deterministic candidate derivation.
- Add fake-clock tests for thresholds, snooze, clear rules, and idempotency.
- Derive stall attention from existing Project/thread/run truth.
- Add Project-scoped JSON projection.

Engine/Mac backend:

- Add driver-aware CLI-to-CLI capacity observers for worker attempts.
- Record Wake Tickets when worker/team/Pending attempts exit with sourced
  cooldown/capacity signals.
- Run a one-shot wake scheduler from the resident coordinator while it is alive.
- Resume only the same authorized work item and only once per observed wake
  boundary.
- Run coarse scanner when coordinator/app is alive.
- Refresh target status before promoting a candidate to active.
- Execute safe recovery actions through existing run/thread APIs.
- Record nudge/action decisions durably.

ThreadStore/Project Manager:

- Create one `ProjectManagerTurn(mode: wait)` for each active episode.
- Link the turn to target Project/thread/run/turn.
- Set existing `thread.needsAttention` with a stall facet.
- Render sleeping/cooldown as sourced Pending/blocked state, not stalled state.
- Include active stalls in Project context packets under work/attention
  summaries without making the packet authority.

Notifications:

- Treat active stall as a `thread.needsAttention` source.
- Reuse existing mute, debounce, quiet-hours, visibility/read suppression, and
  click-through behavior.

CLI/MCP:

- Include Wake Ticket / capacity observation facts in Pending JSON where already
  modeled (`nextWakeAt`, `blockedReason`, attempt reason) before adding new
  commands.
- Add read-only Project and aggregate stalled-work projections.
- Keep action commands out of the first CLI slice unless Core recovery action
  APIs already exist and are tested.

iOS:

- No blocking work. Future iOS renders Mac-owned Project/thread attention after
  Mac Project truth works.

## Inference Bans

| Junction | Owner | Bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Old timestamp -> stall | Watchdog detector | Any old item is stalled. | Only nonterminal v1 targets with no observable progress after refresh can become active stalls. | Idle Pending older than a day is not stalled. |
| Failure -> stall | Turn/run lifecycle | A failed turn should also get a stalled nudge. | Terminal states are not stalled. | Failed turn emits failure attention only. |
| Cooldown -> stall | Pending Resume / Wake Ticket | A quiet cooldown window is stale work. | Future `wakeAfter` suppresses stalled-work promotion. | Pending item cooling until 2:14 AM creates no StallEpisode before 2:14 AM. |
| Auth/setup -> stall | Worker readiness / turn state | Sign-in blocker is a stall. | Auth/setup/manual blockers route to setup/manual copy. | Auth-required turn never creates a StallEpisode. |
| Reset copy -> estimate | CapacityObservation | If a provider does not give reset time, Allnighter may invent one. | `observedResetAt` only when sourced; local backoff uses `wakeAfter` and local-policy copy. | No-reset cooldown JSON contains no provider reset field. |
| Wake -> new work | Pending / Project Manager | The scheduler may rewrite the prompt or create a replacement task. | Wake resumes the same authorized work only. | Model suggestion text creates no new Pending item during wake. |
| Stalled -> retry | Project Manager / user approval | The watchdog may silently retry or pick another worker. | Watchdog actions are explicit; retry/replacement requires human approval through normal Project Manager flow. | Active episode creates no worker attempt until user approves a new run. |
| Project A stall -> global blocker | ProjectStore + triage | One Project's stalled run blocks another Project. | Stalls are Project-scoped; aggregate views group only. | Project B can dispatch while Project A has an active stall. |
| Nudge -> duplicate truth | ThreadStore / Project Manager | A separate stalled inbox owns attention state. | Reuse `thread.needsAttention` with a stall facet. | Menu badge count comes from existing attention derivation. |
| Refresh -> probe | Engine | Refresh may run provider quota probes. | Refresh reads existing target status/result/journal paths only. | No provider-only probe command runs during stall scan. |

## Ordered Slices

- [x] WTK-S00 - Capacity observation contract (DONE 2026-06-19, `b331c2ae`):
  add `CapacityObservation`,
  `providerBusy` vs `accountRateLimit` distinction, fixtures for Claude
  structured errors, Codex JSONL messages, AGY cooldown-until text, and
  no-estimate tests. Project capacity facts through Pending CLI JSON and matching
  MCP Pending specs. No scheduler yet.
- [x] WTK-S01a - Contract projection (DONE 2026-06-19, `b331c2ae`): add
  `PendingResumeReason.providerBusy`, store optional `capacityObservation`, project
  it through Pending JSON fixtures/schema, and register MCP Pending specs.
- [x] WTK-S01b - Worker output capture (DONE 2026-06-19, `3fe9aae0`): capture
  worker attempt stdout/stderr/JSONL/RPC error before reduction to `errorReason`;
  attach sourced capacity observations to `WorkerRunOutcome` / `WorkerAnswer`
  without changing execution behavior.
- [ ] WTK-S01c - Other call-site resume writers: workerChat Pending resume
  mapping is built in WTK-S02a. Audit team/thread paths that can produce sourced
  `CapacityObservation` and decide whether they should map into Pending resume
  facts before claiming Wake Ticket coverage there.
- [x] WTK-S02a - Real Pending workerChat execution seam (DONE 2026-06-19,
  `0c4335c8`): explicit CLI `pending run` can drive and settle one workerChat
  item with leases, transcript/receipt, attempt settlement, and
  cooldown/providerBusy resume mapping.
- [x] WTK-S02c - A1 live MCP Pending handlers (DONE 2026-06-19, `79aa7cb8`):
  `pending_list`, `pending_show`, and `pending_run` are wired in `MCPServer`
  with the same semantics, JSON schemas, and error envelope as CLI/Core.
- [ ] WTK-S02b - Real Pending teamRun execution seam: make explicit Pending
  teamRun execution drive the async/team path and settle attempts. Mutating
  dispatch/work orders remain deferred.
- [ ] WTK-S03 - One-shot wake scheduler (NEXT): resident coordinator loads
  durable workerChat Wake Tickets, sleeps until the earliest due `nextWakeAt`
  plus jitter, reloads truth, and makes one same-work resume attempt; new
  cooldown replaces the ticket. TeamRun and mutating Pending remain deferred.
- [ ] WTK-S04 - Watchdog suppression/fallback: future Wake Tickets suppress
  `StallEpisode`; past-due/repeated unknown failures route to Project Manager
  attention without continuous probes.
- [ ] SWW-S00 - Contract packet: add `StallEpisode`, state distinctions,
  reason enums, CLI/MCP command/tool specs, JSON fixtures, idempotency rules,
  no-estimate field tests, and Project-required candidate validation. No GUI.
- [ ] SWW-S01 - Detector: fake-clock scanner for worker chat turns and async
  team runs, using `lastObservableEvent`, project scoping, thresholds, snooze,
  and negative cases for failed/auth/manual/Pending/fresh-running targets.
- [ ] SWW-S02 - Refresh-before-declare: wire candidate promotion through
  existing thread/run/journal and async `team_status` / `team_result` truth.
  Terminal or owner-blocked refresh suppresses the stall.
- [ ] SWW-S03 - CLI/MCP read-only projection: `alln project stalled <project>
  --json`, `alln stalled list --all --json`, MCP `project_stalled` and
  `stalled_list`, all with identical Core ids, facts, cursors, exit codes, and
  error envelope.
- [ ] SWW-S04 - Project Manager nudge and actions: create one durable
  `ProjectManagerTurn(mode: wait)`, set `thread.needsAttention` with a stall
  facet, and implement `Check status`, `Open thread`, `Keep waiting`, `Cancel`,
  and clear rules.
- [ ] SWW-S05 - Notifications/menu integration: local notification pointer,
  quiet-hours/mute/debounce/read suppression, one notification per episode, and
  no double-notify for failure/auth/manual blockers.

Backend/Core/CLI/MCP slices come before GUI polish. The user-visible win is the
Project Manager nudge; the CLI/MCP contract is how agents and scripts operate
the same truth.

## Works Tests

Capacity observation:

```text
Feed adapter fixtures:
- Claude structured `rate_limit_error` with retry-after;
- Claude `overloaded_error`;
- Codex `codex exec --json` `turn.failed` usage-limit message;
- AGY `capacity exhausted: cooldown active until <timestamp>`.
Expected:
- account limit/cooldown produces observed reset or wakeAfter;
- provider overload maps to providerBusy/short backoff, not account cooldown;
- auth/manual messages do not create Wake Tickets;
- no estimated quota/cost/runtime fields are emitted.
```

Wake Ticket:

```text
Create a submitted Pending item whose attempt fails with a sourced cooldown until
02:14.
Run settlement.
Expected:
- item returns to Pending;
- latest attempt is blocked with sourced reason;
- PendingResume has wakeAfter/observedResetAt;
- `nextWakeAt` appears in Pending JSON;
- no StallEpisode exists before 02:14.
```

One-shot resume:

```text
Start resident coordinator with fake clock.
Create two Pending items: one cooling until 02:14 and one idle Pending.
Advance clock to 02:14 plus jitter.
Expected:
- the cooling item gets exactly one resume attempt;
- idle Pending does not run just because the timer fired;
- if the resumed attempt returns a new cooldown, wakeAfter moves forward;
- if it succeeds, resume clears.
```

Detector:

```text
Create Project A and Project B.
Create a running worker chat turn in Project A with lastObservableEvent 31
minutes ago.
Create a running worker chat turn in Project B with lastObservableEvent 5
minutes ago.
Run the scanner with a fake clock.
Expected:
- Project A emits one active StallEpisode;
- Project B emits none;
- both candidates include projectId;
- no aggregate/global queue item is created.
```

Negative cases:

```text
Create old turns/runs with states failed, timedOut, cancelled, completed,
authRequired, awaitingManualPaste, idle Pending, blocked Pending, and
future-wake capacity sleeping.
Run the scanner.
Expected:
- none create StallEpisode;
- existing owner attention remains intact;
- failed/auth/manual/cooling cases do not receive duplicate stalled notifications.
```

Project binding gate:

```text
Create a stale queued/running target that has no reliable projectId.
Run the scanner.
Expected:
- no StallEpisode is created;
- no global stalled item is created;
- the target remains in the owning repair path.
```

Refresh-before-declare:

```text
Create an async team run whose local journal looks stale.
Make team_status/team_result refresh return terminal completed.
Run the scanner.
Expected:
- no active StallEpisode is created;
- any prior candidate clears as refreshedOut;
- no Project Manager nudge or notification is emitted.
```

Snooze/idempotency:

```text
Create one active StallEpisode.
Run the scanner twice.
Expected:
- one Project Manager nudge turn exists;
- one notification candidate exists before delivery policy;
- idempotency key is stable.
Choose Keep waiting.
Run the scanner before snoozedUntil.
Expected:
- no new nudge or notification.
Advance fake clock beyond snoozedUntil while target is still stalled.
Expected:
- the same episode becomes active again and may notify once.
```

Recovery actions:

```text
Create an active stalled team run.
Choose Check status and return still running.
Expected:
- lastRefreshAt updates;
- no duplicate nudge.
Choose Cancel and make cancel succeed.
Expected:
- target is terminal cancelled;
- episode clears;
- thread attention no longer includes the stall facet.
```

Project Manager nudge:

```text
Create a stalled worker turn in the Allnighter Project.
Run promotion.
Expected:
- Project Manager thread receives one mode=wait turn;
- facts block includes title, current status, last change, waiting since, and one
  primary action;
- turn links to the target thread/run/turn;
- target thread has needsAttention with stallReason.
```

Notification:

```text
Create an active stall in an unmuted thread that is not visible/read.
Expected:
- one local notification candidate is produced;
- clicking opens the Project/thread at the nudge turn.
Mute the thread and repeat.
Expected:
- no local notification delivery;
- durable Project Manager nudge still exists.
```

CLI proof:

```text
alln project stalled Allnighter --json
alln stalled list --all --json
```

Expected:

```text
- project command returns only Allnighter episodes;
- aggregate command groups by Project;
- JSON ids/facts/actions match the Project Manager-visible state;
- no estimated quota/cost/runtime fields exist.
```

Green wall:

```text
swift test --package-path Packages/AllnighterCore
bash scripts/check.sh
```

## Done When

- Worker capacity failures can produce sourced `CapacityObservation` records.
- Claude, Codex, and AGY CLI-to-CLI capacity conventions are fixture-tested and
  fail closed to generic message classification.
- Capacity cooldown produces `PendingResume` / Wake Ticket state and returns the
  item to Pending/Sleeping instead of leaving it indefinitely Running.
- Resident wake scheduling makes zero provider calls during cooldown and one
  same-work resume attempt at the observed/conservative wake boundary.
- Future Wake Tickets suppress stalled-work promotion.
- Worker chat turns and async team runs can produce Project-scoped stall
  episodes.
- Every active episode belongs to exactly one Project.
- Detection uses local progress signals and refreshes before declaring.
- Terminal failure/completion, auth/setup/manual blockers, and idle Pending do
  not become stalls.
- The Project Manager creates one durable nudge per episode with a fixed facts
  block and typed next actions.
- `thread.needsAttention` is reused with a stall facet; no parallel attention
  tracker ships.
- Mac local notifications point to the nudge and respect existing mute/debounce/
  quiet-hours rules.
- Stall state clears automatically when local truth shows terminal completion,
  owner-blocked state, or successful user recovery.
- Snooze and duplicate-nudge prevention survive app restart.
- Read-only CLI/MCP projections mirror Core state and remain Project-scoped.
- No quota accounting, admission ledger, continuous probe loop, broad drain
  scheduler, prompt rewrite, or worker substitution machinery is introduced.

## Closed Decisions

- Expected cooldown sleep is a Wake Ticket, not a stall.
- The wake action is a same-work resume attempt, not a generic CLI ping.
- Structured CLI-to-CLI events beat message parsing; message parsing remains the
  fallback.
- `accountRateLimit` and `providerBusy` are distinct capacity observations.
- A provider-observed reset may become `observedResetAt`; local backoff may only
  become `wakeAfter` with local-policy copy.
- V1 targets Wake Tickets, worker chat turns, and async team runs only.
- Refresh-before-declare is mandatory.
- Progress means local truth changed; provider guesses are not progress signals.
- PM turn owns durable recovery history; notification is only a pointer.
- One primary action is shown per stall reason.
- Retry/replacement is outside the watchdog action set unless routed through
  explicit Project Manager approval.
- Pending idle time is not stalled work.
- Global stalled views are aggregate-only.

## Open Questions

- Should default thresholds become per-Project settings after dogfood, or only
  global user settings?
- Should `Dismiss` be exposed in the main UI, or kept as a secondary/overflow
  action to avoid losing still-running work?
- Should future iOS show active stall episodes in the Project snapshot before
  Mac GUI action cards are polished?
