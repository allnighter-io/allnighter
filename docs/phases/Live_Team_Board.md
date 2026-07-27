# Live Team Board

Status: Draft feature packet — grounded contract only
Owner: AllnighterCore + AllnighterEngine + Mac app
Updated: 2026-06-20

## Authority

Read with:

- `docs/workflows/Product_Vocabulary.md`
- Code SSOT `RunService.swift` (the run model)
- `docs/phases/Team_Run_Floor.md`
- `docs/archive/phases/CLI_Implementation_Contract.md`
- `docs/phases/threads/03_Mac_Streaming.md`
- `docs/gui/GUI_Workflow.md`
- `docs/design-system/production.md`

This doc owns the live in-thread board for a running Send to team / answer-team
run. The Floor remains the deeper inspectable receipt after or during the run.

## Founder Intent

Raw request:

```text
The current running state hides the team behind one line for minutes. Show each
assigned worker, show which workers have started, show real streaming text when
it exists, show finished work when it is actually available, and let the user
open each worker result. Do not fabricate worker activity or progress prose.
```

Product value:

```text
The user can see the real team working instead of staring at a generic spinner.
```

Trusted workflow slice:

```text
Send to team
-> thread shows a Live Team Board for that run
-> each assigned worker has a sourced row
-> started workers show a live indicator
-> stream-capable workers may show real answer deltas, capped to a few lines
-> completed workers expose that a real answer exists when the contract carries it
-> terminal thread card routes to the Factory Floor
-> the Floor owns full result reading and the inspectable receipt
```

## Non-Goals

- Do not invent per-worker narration such as "reading file X", "found likely
  cause", "editing Y", or "thinking about Z" unless a sourced event carries that
  exact user-visible text.
- Do not show fake percentages, ETAs, token burn, quota burn, or future cost.
- Do not imply a worker is streaming when no answer-delta event has arrived.
- Do not show inferred model reasoning by default. Reasoning events, where they
  exist, are separate from answer text and need a deliberate product decision
  before becoming visible in this board.
- Do not create a new run schema for the Mac app. GUI presents `RunEvent`,
  `TeamStatusResponse`, `TeamRun`, `TeamRunJSON`, and eventually `FloorRun`.
- Do not make the board a replacement for the Factory Floor / Floor receipt.
- Do not dump full worker answers or the full synthesized result into the thread
  as the primary terminal experience. The thread is the live cockpit; the Floor
  is the reader and receipt.

## Current State

Useful substrate already exists:

- `TeamRun.workers[]` stores the assigned workers for a run.
- `TeamRun.workerAnswers[]` stores one worker answer/failure record with
  `status`, `output`, `errorReason`, timestamps, duration, and exit code.
- `TeamRunJSON.workers[]` exposes worker id, skill id/name, model id/name,
  source id, purpose, and instance index.
- `TeamRunJSON.workerAnswers[]` exposes worker status, duration, final markdown
  when present, and structured error when present.
- `TeamStatusResponse.workers[]` exposes live worker id, display name, status,
  start/finish timestamps when known, and warning.
- `RunEventKind.workerStatusChanged` exists and is emitted when team workers move
  between queued/running/done/failed/timed-out/cancelled states.
- `RunEventKind.workerAnswerDelta` exists for visible answer deltas. In the run
  event payload, `text` is the accumulated visible answer so far and
  `truncated` marks display truncation.
- `WorkerStreamEvent.answerDelta` exists at the worker runner layer.
- Driver manifests can declare streaming support and answer delta paths.
- `FactoryFloorView`, `FloorRun`, `TeamRunJSONPresenter`, `WorkerChip`, and
  `StatusPill` already exist as relevant UI/contract pieces.

Important gaps:

- Multi-worker answer-team runs currently emit worker status events through
  `CatalogRunCoordinator`, but they do not emit per-worker answer deltas.
- `CatalogRunCoordinator` persists answer output after a worker group settles,
  not necessarily at the exact moment each individual worker returns.
- `workerStatusChanged` can say a worker finished; it does not carry the final
  answer markdown.
- `RunEventKind.workerOutput` exists as a named event kind, but this board must
  not rely on it until the team-run path actually emits a documented payload.
- `TeamStatusWorker` does not currently expose model name, source id, or skill
  name by itself; those come from the run/team worker snapshot.
- The existing thread turn has one `text` field. A multi-worker board needs
  per-worker live text state, not one shared running answer field.

## No-Theater Rule

Every visible field on the board must come from one of the owner fields below.
If the owner does not have the fact, the UI leaves the field blank or shows a
neutral state like `waiting`, `running`, `done`, or `failed`.

Forbidden examples:

```text
Found likely cause in ...
Reading ...
Scanning ...
Editing ...
Thinking about ...
Almost done
90%
About 2 minutes left
```

Allowed examples when sourced:

```text
running
done
failed
timed out
2 workers running
3 done
Claude Opus · Code reviewer
No live text yet
```

`No live text yet` means exactly: the worker is running, and no
`worker.answer_delta` text has been received for that worker.

## User-Visible Claim

```text
When a team run starts, Allnighter shows every assigned worker and its sourced
status. If a worker supports live answer streaming and emits text, the board
shows a capped live excerpt. When a worker's final answer is available, the
worker row can open that real answer. Failed workers remain visible as failed.
```

No copy may claim "streaming for every model" until the team-run path emits
per-worker answer deltas for the relevant workers.

## Result Landing Decision

The thread timeline must not become the team-result reader.

Ownership split:

```text
Thread Live Team Board = compact live progress, sourced worker states, small
                         live excerpts, terminal counts, Open Floor action.
Factory Floor          = full worker answers, full synthesis, artifacts,
                         prompts where allowed, receipts, and next actions.
```

When a team run reaches a terminal state, the thread card settles into a compact
receipt row/card. It may show sourced counts and a short sourced preview, but the
primary action is `Open Floor`. Full worker answers and the full synthesized
result belong in the Factory Floor.

The current observed behavior - terminal results appearing directly in the
thread instead of landing in the Factory Floor - is a product bug against this
decision.

## Field Ownership Ledger

| GUI field | Owner field | Source | States | Notes |
| --- | --- | --- | --- | --- |
| Run id | `teamRun.id` / `run.id` | `TeamRunJSON` / `TeamRun` | all | Stable row attachment key. |
| Team name | `teamRun.teamDisplayName` / `run.teamDisplayName` | `TeamRunJSON` / `TeamRun` | all | Do not infer from prompt. |
| Worker row identity | `workers[].id` | `TeamRunJSON.WorkerInfo` / `TeamRun.workers[]` | all | Stable id. |
| Worker job | `workers[].skillName`, `workers[].purpose` | `TeamRunJSON.WorkerInfo` / `Worker` | all | If no skill name, use purpose or a neutral label. |
| Model label | `workers[].modelName` | `TeamRunJSON.WorkerInfo` | all | `TeamStatusWorker` alone is insufficient. |
| Source/driver | `workers[].sourceId` | `TeamRunJSON.WorkerInfo` | all | Use for glyph/source label when present. |
| Worker status | `workerAnswers[].status`, `TeamStatusWorker.status`, `workerStatusChanged.to` | Core run truth / live status / run event | all | Closed statuses only. |
| Started spinner | `workerStatusChanged.to == running` or live status `running` | `RunEvent` / `TeamStatusResponse` | running | A spinner means started/running, nothing more. |
| Started time | `workerAnswers[].startedAt`, `TeamStatusWorker.startedAt`, or `RunEvent.ts` | Core/live event | running, done | Event timestamp is allowed only as event time. |
| Finished time | `workerAnswers[].finishedAt`, `TeamStatusWorker.finishedAt` | Core/live status | done, failed, timedOut | Blank if absent. |
| Duration | `workerAnswers[].durationMs` | `WorkerAnswer` / `TeamRunJSON.AnswerInfo` | done, failed, timedOut | No estimates while running. |
| Live excerpt | `worker.answer_delta.text` | `RunEventKind.workerAnswerDelta` | running | Display last N lines of accumulated answer text. |
| Live truncation | `worker.answer_delta.truncated` | `RunEventKind.workerAnswerDelta` | running | Show only if true. |
| Final worker answer | `workerAnswers[].output` / `workerAnswers[].markdown` | `TeamRun` / `TeamRunJSON` | done | Clickable only when present. |
| Worker failure | `workerAnswers[].errorReason` / `workerAnswers[].error` / status event reason | Core run truth / event | failed, timedOut | Failure remains visible. |
| Synthesis status | run status `planning` / live status `synthesizing` / stage events | `TeamRun`, `TeamStatusResponse`, `RunEvent` | running | Do not call it done until `plan` exists. |
| Final synthesis | `plan.markdown` | `TeamRunJSON.Plan` / `TeamRun.plan` | done, partial | Not a per-worker answer. |
| Open Floor action | `runId` | `ThreadTurn.runId` + `RunStore` / `FloorRun` | all | Full receipt path. |

Rule: any GUI field not listed here needs a contract owner before it ships.

## Desired Board Behavior

### Queued / accepted

- Show the run as accepted/queued when that is the sourced state.
- Show assigned worker rows as soon as the worker snapshot is available.
- Rows without a started event are `waiting`, not spinning.

### Running

- A row spins only after a sourced running status for that worker.
- A row may show up to `N` lines of live text only after receiving
  `worker.answer_delta` for that worker.
- Default display cap: 3 lines. This is a display cap only; it does not change
  stored output.
- If no live text has arrived, the row may say `No live text yet` or show only
  status chrome.
- Running counts are derived from worker statuses, never from elapsed time.

### Worker finished

- A row changes to `done`, `failed`, `timed out`, or `cancelled` from sourced
  status.
- The row becomes result-clickable only when final markdown/output exists.
- If the status says done but output is not yet in the store/contract, show
  `done` without pretending the answer is available.

### Synthesis

- Show synthesis as a separate row or footer only when run status/stage events
  say the plan/output stage has started.
- Show final synthesis only when `plan.markdown` exists.
- Do not describe what synthesis is doing beyond sourced stage/status labels.

### Done / failed / partial

- Show concrete counts: done, failed, timed out, cancelled.
- Failed workers stay visible even if the run produced a usable synthesis.
- The terminal thread card stays compact and points to `Open Floor`.
- The full Floor is the complete result-reading and receipt surface.

## CLI / MCP Surface

Existing surfaces:

- `alln team --json` returns terminal `TeamRunJSON`.
- `alln team --stream` returns NDJSON, but the current contract warns it is a
  settled event log, not necessarily a live incremental feed.
- MCP async tools use `team_start`, `team_status`, `team_result`, and
  `team_cancel`.
- `team_status` returns workers and `nextPollAfterMs`, and must not report fake
  percentages.

Contract gaps before the Live Team Board is fully honest:

- Live team status must expose enough worker snapshot data for the board, or the
  Mac must join live worker status with the persisted `TeamRun.workers[]`
  snapshot.
- Team-run worker answer deltas need a documented event payload if the board is
  going to show live text per worker.
- Per-worker final output needs to become available as each worker settles if
  the board promises "open results as they arrive." Either persist each answer as
  it arrives or emit/store a documented worker-output event.
- MCP/CLI should expose the same facts eventually; the Mac must not grow a
  private-only live schema that iOS/agents cannot consume.

## Implementation Slices

### LTB-S00 — Contract audit and presenter

- Build a pure presenter over `TeamRun`, `TeamRunJSON`, `TeamStatusResponse`, and
  `RunEvent`.
- Prove it only renders fields from the Field Ownership Ledger.
- No visual work beyond presenter tests.

### LTB-S01 — Live roster with honest statuses

- Replace the generic running line with a compact Team board turn.
- Show every assigned worker row once the worker snapshot exists.
- Show worker name/job/model and sourced status.
- Show spinners only for sourced running workers.
- No live text and no result-click promise in this slice.

### LTB-S02 — Open final worker answers when actually available

- Make completed worker rows clickable only when `workerAnswers[].output` /
  `markdown` exists.
- If output is not available at individual completion time, keep the row marked
  done and non-clickable until the answer arrives.
- If product requires "as each worker arrives," change the Engine/Core contract
  first so each answer is persisted or emitted at settlement.

### LTB-S03 — Per-worker live answer excerpts

- Add team-run worker streaming only after `CatalogRunCoordinator` or its
  replacement emits `worker.answer_delta` per worker.
- The board displays the last `N` lines of accumulated answer text for that
  worker.
- Non-streaming workers show status only.

### LTB-S04 — Floor landing

- Add `Open Floor` and row-level open actions that land on the existing Factory
  Floor / Floor receipt.
- Ensure terminal team results do not render as full answers inside the thread
  timeline.
- The Floor owns full reading, artifacts, prompts where allowed, and synthesis.

## Works Test

Scenario:

```text
Given a team run with three workers:
- worker A starts, streams two answer deltas, and finishes with markdown;
- worker B starts and finishes without streaming;
- worker C starts and fails with an error.
```

Assertions:

- All three assigned workers render with sourced job/model labels.
- Only started workers show running spinners.
- Worker A shows only real streamed text, capped to the configured line count.
- Worker B never shows fake activity text.
- Worker A and B become clickable only when final answer markdown exists.
- Worker C remains visible as failed with its sourced error.
- No row contains invented activity prose.

Proof command:

```text
swift test --package-path Packages/AllnighterCore
```

Mac GUI work also requires the GUI Visual Proof Gate for the changed thread
timeline surface.

## Done When

- The thread running state shows a sourced worker roster instead of one generic
  line.
- Every displayed worker fact maps to the Field Ownership Ledger.
- Per-worker streaming appears only for workers that emit answer deltas.
- Per-worker final answers open only when final output is present.
- Failed and timed-out workers remain visible.
- Terminal results land in the Factory Floor; the thread keeps a compact receipt
  card with `Open Floor`.
- CLI/MCP/iOS have a path to the same facts; no Mac-only durable schema exists.

## Open Questions

- Should the compact board say `No live text yet`, or should it simply leave the
  excerpt area empty until the first answer delta?
- Should per-worker answer output be persisted immediately when each worker
  returns, or is it acceptable to expose final answers after the whole answer
  group settles?
- Should visible reasoning ever appear in this board, or remain hidden/audit-only
  as the streaming docs currently prefer?
