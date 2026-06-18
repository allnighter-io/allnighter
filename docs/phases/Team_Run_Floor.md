# Team Run Floor

Status: Draft backend/product spec
Owner: AllnighterCore + Engine + CLI/MCP + Mac app
Updated: 2026-06-18

## Authority

Read with:

- `docs/phases/Language_Cutover.md`
- `docs/phases/Team_Delegation_Surface.md`
- `docs/phases/Project_Spine_And_Project_Manager.md`
- `docs/phases/CLI_Product_Spine.md`
- `docs/phases/CLI_Implementation_Contract.md`
- `docs/phases/Persistent_Work_Threads.md`
- `docs/strategy/Allnighter_Public_Signal_Wedge.md`

This doc owns the durable product/contract for the **Floor**: the inspectable
workroom and return record for one team run.

Visual layout is intentionally out of scope except where it reveals backend
requirements. GUI work must add a separate `docs/gui/surfaces/.../brief.md` once
the Core projection exists.

## Founder Intent

Raw request:

```text
Every time you send a team into action, show the Floor. The aha is not choosing a
team; it is watching the agents I already pay for show up, work in parallel, and
collapse into one decisive, sourced return. I should be able to inspect every
worker's real answer and source artifacts, not only hear from the team lead.
```

Product value:

```text
The Floor proves that Allnighter coordinated a real team and kept the receipts.
```

Trusted workflow slice:

```text
Send to team
-> Floor opens for that team run
-> workers run in parallel and return honestly
-> every worker return is preserved as a durable artifact
-> synthesis produces a typed Return or Insight
-> next actions route to Copy/Code/Design/Pending/Execute as appropriate
```

## Decision

Public noun: **Floor**.

Definition:

```text
Floor = the visible workroom and receipt for one team run.
```

The picker is the doorway. The Floor is the room.

```text
Send to team = choose and start the team
Floor        = inspect the run, worker lanes, artifacts, synthesis, receipts
Execute      = approve mutating work that should become real
```

The Project Manager may summarize or link to a Floor, but it must not replace
the Floor. Chat can show the team lead's answer; the Floor preserves and exposes
the whole team run.

## Non-Goals

- Do not design the final GUI in this doc.
- Do not make Project Manager team recommendation the center of this feature.
  Humans usually know the team they want before the prompt is polished.
- Do not create a separate run store from `TeamRun`.
- Do not copy all run truth into thread chat turns.
- Do not expose private local paths or raw context in exported/shared output
  without an explicit export action.
- Do not auto-execute mutating next actions.
- Do not treat worker output as proof. Proof remains proof commands,
  verification records, receipts, or explicit waiver.

## Current State

Useful substrate already exists:

- `TeamRun` stores prompt, status, origin, team/preset, workers, worker answers,
  stages, warnings, thread links, and created time.
- `WorkerAnswer` stores worker id, model id, status, output markdown, error,
  start/end timestamps, duration, and exit code.
- `StageOutput` stores post-answer stages with typed payloads for analysis, plan,
  review, final spec, dispatch, return review, outcome score, and board.
- `TeamRunJSON` exposes `workers`, `workerAnswers[].markdown`, `stages`, `plan`,
  warnings, errors, next actions, and `audit.runJournalPath`.
- `RunStore` persists `run.json` plus derived `bundle.md`, `analysis.md`,
  `master_plan.md`, review files, and final spec files.
- `ThreadTurn.artifactRefs[]` already exists for timeline pointers to durable
  run/file artifacts.
- `SpecRetrieval` can project summary/full/artifact-refs output for agents.

Current gaps:

- Worker answers live inline in `run.json`; there is no durable per-worker `.md`
  artifact ref.
- Worker prompts/snapshots are not consistently preserved as inspectable local
  artifacts.
- Stage outputs do not consistently produce artifact refs.
- Signal has no typed `Insight` output separate from generic `plan.markdown`.
- Signal receipts are not structured: source links, timestamps, freshness,
  quote/snippet boundaries, skeptic pass, and saturation/window status are not
  first-class.
- The public run contract does not expose a Floor projection with worker lanes,
  artifact refs, synthesized return, timeline, and Execute requirements.
- Timeline data is incomplete for the full converge story: worker start/end
  exists, but queue/start/finish/synthesis/converge events are not projected in
  one contract.
- `TeamRunJSON.NextAction.Kind` is too narrow: currently `showRun`, `export`,
  and `showHistory`.
- "Open raw worker return" cannot be implemented cleanly from the public
  contract because there is no per-worker artifact ref.

## Product Contract

Add a Core-owned Floor projection over one persisted `TeamRun`.

Draft shape:

```text
FloorRun
  schemaVersion
  run
  intent
  team
  workerLanes[]
  stages[]
  return
  timeline[]
  receipts[]
  nextActions[]
  executeRequirements[]
  artifacts[]
  warnings[]
  errors[]
  audit
```

`FloorRun` is a projection. It does not replace `TeamRun`.

### Run

```text
FloorRun.run
  id
  projectId?
  threadId?
  status: queued | running | done | failed | timedOut | cancelled | interrupted
  family: signal | code | design | copy
  posture: scout | propose | review | execute
  mutating: Bool
  origin
  originAgent?
  createdAt
  startedAt?
  completedAt?
  durationMs?
  reproduceCommand?
```

Rules:

- `family`, `posture`, and `mutating` come from the selected Team/Card/run
  request, not from prompt inference.
- `mutating == true` requires Execute approval before make-real dispatch.
- A failed worker remains visible even if synthesis succeeds.

### Intent

```text
FloorRun.intent
  prompt
  promptSource
  attachments[]
  contextPacketId?
  selectedTeamCardId?
```

Rules:

- Intent is what the user sent to the team, not what the team later inferred.
- The Floor may link the Project Context Packet receipt, but it must not dump
  sensitive context into shared/exported output by default.

### Team

```text
FloorRun.team
  teamId
  displayName
  family
  outputKind
  workerCount
  modelCount
  leadWorkerId?
  readinessSnapshot?
```

Rules:

- The team snapshot must be self-describing enough to inspect old Floors after
  Team/Skill catalog changes.
- One model wearing multiple skills is shown truthfully as multiple worker lanes
  on one model.

### Worker Lanes

Each worker lane is the user's inspectable unit.

```text
FloorWorkerLane
  workerId
  skillId
  skillName
  modelId
  modelName
  sourceId
  purpose: answer | review | lead | stage
  status
  startedAt?
  finishedAt?
  durationMs?
  exitCode?
  summary?
  artifactRefs[]
  promptArtifactRef?
  error?
```

Rules:

- Every worker answer produces a worker lane, including failed, timed-out,
  skipped, and cancelled workers.
- `summary` is a derived excerpt for scanning. The raw answer is the artifact.
- `artifactRefs[]` must include the worker's durable return markdown when output
  exists.
- `promptArtifactRef` is local-only and may be hidden by default, but it must be
  available for audit/debug when policy allows.
- Worker lanes are ordered by Team definition unless a later product decision
  chooses timeline order.

## Durable Artifacts

Each run folder should become an inspectable receipt directory.

Minimum layout:

```text
Runs/run_<id>/
  run.json
  floor.json
  bundle.md
  workers/
    <workerId>.answer.md
    <workerId>.prompt.md
    <workerId>.metadata.json
  stages/
    <stageId>.<purpose>.md
    <stageId>.metadata.json
  receipts/
    signal_receipts.json
    source_<n>.md
  return/
    insight.json
    return.md
```

Rules:

- `run.json` remains the canonical internal persistence model.
- `floor.json` is a derived public projection and may be regenerated from
  `run.json` plus artifact metadata.
- Worker `.answer.md` files are durable source artifacts, not prettier copies
  in the GUI.
- Markdown files are local artifacts. Export/share commands decide what leaves
  the machine.
- Artifact refs should be stable relative identifiers, not absolute paths, in
  public JSON. The app can resolve them to local files.

Draft artifact ref:

```text
RunArtifactRef
  id
  runId
  kind: workerAnswer | workerPrompt | stageOutput | receipt | returnMarkdown |
        insightJSON | bundle | source
  title
  relativePath
  mimeType
  workerId?
  stageId?
  createdAt
  contentSHA256?
  localOnly: Bool
```

## Typed Return

The Floor right side is not always a generic plan. It is a typed return.

```text
FloorReturn
  kind: insight | plan | board | draft | proposal | workOrderDraft |
        proofPacket | audit | executionReturn
  status
  title
  summaryMarkdown
  producedByWorkerId?
  stageId?
  artifactRefs[]
```

Rules:

- Existing Code/Design/Copy teams may initially map their current `plan` or
  board payload into `FloorReturn`.
- Signal teams must produce `kind: insight` once the Signal contract lands.
- A return can be useful even when one worker failed; failure remains visible.

## Signal Insight

Signal needs a typed output separate from generic plan markdown.

```text
SignalInsight
  title
  summary
  whatHappened
  whyItMatters
  whyThisProject
  window: open | closing | closed | uncertain
  freshness
    observedAt
    newestSourceAt?
    oldestSourceAt?
    status: fresh | stale | uncertain
  internalLessons[]
  externalProductIdeas[]
  skepticPass
    verdict: pass | caution | reject | uncertain
    reason
    saturationRisk?
    ownedByAnotherAccount?
  receipts[]
  recommendedNextActionId?
```

Signal receipt:

```text
SignalReceipt
  id
  sourceKind: xPost | xThread | article | releaseNote | repo | other
  url?
  sourceId?
  authorOrPublisher?
  observedAt
  publishedAt?
  title?
  snippet?
  relevance
  evidenceRole: primary | corroborating | counterSignal | saturation | skeptic
  artifactRef?
```

Rules:

- Receipts must distinguish observed facts from model inference.
- Public-X collection remains public-only.
- If freshness cannot be proven, mark `freshness.status = uncertain`.
- "No move today" is a valid Insight when the signal is stale, saturated, or not
  a Project fit.

## Timeline

The Floor needs a compact timeline for the "team worked in parallel" truth.

```text
FloorTimelineEvent
  id
  runId
  kind: runQueued | runStarted | workerStarted | workerReturned |
        workerFailed | stageStarted | stageFinished | synthesisStarted |
        synthesisFinished | runFinished
  at
  workerId?
  stageId?
  status?
```

Rules:

- Timeline is derived from run/worker/stage timestamps where possible.
- If live event persistence exists, it may provide more accurate event order.
- Do not invent timestamps. Missing timestamps render as unknown, not guessed.
- The parallel/converge visualization is optional GUI. The contract is the event
  list.

## Next Actions

`TeamRunJSON.NextAction.Kind` is too narrow for Floor. Add a richer, typed action
catalog for Floor returns.

Draft kinds:

```text
openArtifact
copyReturn
exportFloor
sendTeam
draftCopy
createCodeProposal
createDesignBrief
createWorkOrder
savePending
execute
ignore
monitorExternally
showRun
showHistory
```

Action shape:

```text
FloorNextAction
  id
  kind
  label
  family?
  targetTeamId?
  targetArtifactRef?
  requiresExecute: Bool
  mutating: Bool
  command?
  disabledReason?
```

Rules:

- Mutating next actions must be disabled or route to Execute approval until the
  user approves.
- `execute` is an approval action, not a team family.
- `sendTeam` may preselect a family/team but must still show what will run.
- `monitorExternally` creates or reveals a Pending/CLI/MCP handoff; it does not
  create native scheduling in v1.

## Execute Requirements

When a Floor return proposes make-real work, it must preserve the gate.

```text
ExecuteRequirement
  reason
  affectedScope
  requiredApproval: Bool
  workOrderId?
  proofCommands[]
  proofWaiver?
  readinessBlockers[]
```

Rules:

- Code paths that write files, run mutating commands, post externally, or edit
  state require Execute approval.
- A Floor can present the proposed move before approval.
- Approval produces or links a `WorkOrder` and later a `VerificationRecord`.

## Thread Integration

A thread turn should reference the Floor, not copy it.

```text
ThreadTurn
  kind: teamRun
  runId
  artifactRefs[]
```

Rules:

- Chat timeline may show a compact team-run card and the Team Lead/Return
  summary.
- Opening the Floor loads the full projection from `runId`.
- `artifactRefs[]` points at important artifacts, but `run.json` remains the
  source for the full run.

## Privacy And Locality

The Floor deliberately captures more durable local detail. That is good for
trust and audit, but it raises privacy expectations.

Rules:

- Floor artifacts are local by default.
- Export/share commands must be explicit and should support redaction later.
- Raw worker prompts may include Project context and should be marked
  `localOnly: true`.
- Public Signal receipts may include public URLs/snippets, but protected/private
  data is out of scope.
- The app should show when a worker received Project context and when the Floor
  is displaying derived local artifacts.

## Implementation Slices

### FLOOR-S00 - Floor projection contract

- Add `FloorRun` projection types in Core.
- Project existing `TeamRun` into Floor with workers, stages, return, warnings,
  errors, and basic next actions.
- No new GUI required.

### FLOOR-S01 - Worker artifact persistence

- On every `RunStore.save`, write per-worker answer markdown and metadata.
- Add worker artifact refs to the Floor projection.
- Ensure failed/skipped workers still get metadata artifacts.

### FLOOR-S02 - Stage and return artifacts

- Write stage markdown/metadata consistently for every stage with markdown.
- Add `FloorReturn` projection over current plan/board/review/dispatch payloads.
- Keep `bundle.md` as an export artifact, not the only inspection path.

### FLOOR-S03 - Signal Insight payload

- Add typed Signal Insight and Signal Receipt models.
- Add a stage or return payload case for `insight`.
- Project Signal teams to `FloorReturn.kind = insight`.

### FLOOR-S04 - Timeline projection

- Add `FloorTimelineEvent` projection from worker/stage/run timestamps.
- If live event persistence lands first, use it as the preferred source.
- Missing timestamp data remains visibly unknown.

### FLOOR-S05 - Rich next actions and Execute requirements

- Add Floor next actions for artifact open, Send team, Copy/Code/Design routing,
  Pending, ignore, and Execute.
- Add Execute requirements projection for mutating moves.
- Keep existing `TeamRunJSON.NextAction` stable until the public contract bump is
  deliberate.

### FLOOR-S06 - CLI/MCP retrieval

- Add or extend CLI/MCP retrieval so agents can request:

```text
floor show <run-id> --json
floor artifact <artifact-id>
```

or the final equivalent under the `team.run` contract.

## Works Tests

### WT-FLOOR01 - Worker returns are inspectable artifacts

Setup:

```text
Run a non-mutating team with two successful workers and one failed worker.
```

Assertions:

- `run.json` stores all workers and statuses.
- Successful workers have `.answer.md` artifacts.
- Failed worker has metadata with error reason/status.
- Floor projection includes artifact refs for successful worker answers.
- Failed worker remains visible.

### WT-FLOOR02 - Floor projection round-trips

Gesture:

```text
Load persisted run and project FloorRun JSON.
```

Assertions:

- FloorRun decodes/encodes through `CoreJSON`.
- Worker lane count equals run worker count.
- Return links to the plan/stage artifact when present.
- Artifact refs are relative and resolve under the run directory.

### WT-FLOOR03 - Signal Insight carries receipts and freshness

Setup:

```text
Signal team returns an Insight with two source receipts and one skeptic pass.
```

Assertions:

- Insight is typed, not only markdown.
- Each receipt has source kind, observed timestamp, evidence role, and artifact
  ref or URL.
- Freshness is `fresh`, `stale`, or `uncertain`; no missing freshness on a
  time-sensitive Insight.

### WT-FLOOR04 - Timeline does not invent missing data

Setup:

```text
Persist a legacy run with partial timestamps.
```

Assertions:

- Floor timeline includes only events with sourced timestamps.
- Missing worker start/end renders as absent/unknown, not fabricated.

### WT-FLOOR05 - Mutating next action routes to Execute

Setup:

```text
Floor return recommends a Code work order that would write files.
```

Assertions:

- Next action has `mutating: true`.
- Next action has `requiresExecute: true`.
- No direct run command is emitted before approval.
- Execute requirement names proof commands or waiver.

## Proof Commands

Expected backend proof once implemented:

```bash
swift test --package-path Packages/AllnighterCore
alln show latest --json
```

CLI/MCP proof should add fixture replay for Floor JSON and artifact retrieval
once those commands exist.

## Done When

- Every team run has a Floor projection.
- Every worker lane is visible, including failures.
- Every successful worker answer is inspectable through a durable artifact ref.
- Synthesis/Return is typed enough to distinguish Insight, plan, board, draft,
  proposal, proof packet, and execution return.
- Signal Insights carry structured receipts, freshness, skeptic pass, and next
  actions.
- Timeline data is sourced and honest.
- Mutating actions route through Execute approval.
- Chat can summarize the team lead, but the full Floor remains one click away.

