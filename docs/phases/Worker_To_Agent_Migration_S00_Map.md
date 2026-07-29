# WTA-S00 — Inventory + id-meaning map

Appendix to `docs/phases/Worker_To_Agent_Migration.md`.
Status: **Adjudicated** — 2026-07-28
Method: four parallel readers gathered evidence; the lead adjudicated every
bucket. No reader was permitted to decide meaning (packet, Orchestration §).

Baseline measured at `7972d65a`. Binary rebuilt to match HEAD before any
delegation (`scripts/rebuild_cli.sh`) — the installed `alln` predated the vocab
cutover and still exposed retired `--worker` grammar, which would have made every
delegated round reason from a stale surface.

---

## The finding that changes the plan

`worker` is not one overloaded name. It is **two different overloads that look
identical to a grep**, plus one honest process-layer use.

### Overload 1 — `workerId` that is really a MODEL PIN

Every field on the *request* side spelled `workerId` holds a **model catalog id**
(`model_opus`), resolved via `ExactIdResolver.resolveWorker(..., flag: "--model",
models: context.models)` against the bench catalog.

```text
--model <id>  →  RunRequest.workerId  →  RunInvocationNormalizedFlags.workerId
              →  ResolvedRunInvocation.workerId          ← ALL model catalog ids
```

Destination is **not** `agentId`. It is `modelId` / `pinnedModelId`. Renaming
these to `agentId` is the exact false-precision failure the packet forbids.

There is already a correctly-named precedent in the codebase to imitate:
`RunInvocationNormalizedFlags.explicitSeatModelIds` — "explicit" + "seat" +
"ModelIds" says in the name that these are model ids pinned into seat slots.

### Overload 2 — `workerId` that is really a RUN-MEMBER instance

Every field on the *result* side spelled `workerId` holds a **composite**
`"\(modelId)#\(instanceIndex)"`, built by `Worker.makeID` (`Worker.swift:73-75`)
and matched against `TeamAnswer.memberId`, never against the model catalog.

### The collision that proves "no global grep"

Both meanings are produced by **the same function**, in **the same returned
value**, in `ResolvedRunInvocation.swift`:

```swift
return ResolvedRunInvocation(
    workerId: workerId,   // "model_opus"    ← MODEL PIN      (line 241 / set 551)
    seats: seats,         // seats[0].workerId = "model_opus#0" ← RUN MEMBER (line 15 / set 606)
)
```

Same token, opposite meaning, one struct. A `sed` over `workerId` corrupts one of
these two no matter which way it runs.

---

## Adjudicated decisions (lead)

### D1 — `agentId` means the **roster seat row**, and it must be PLUMBED, not derived

Today the roster seat id is **thrown away** at resolve time.
`TeamWorkerSpec.id` is a stable seat/row slug (`BuiltInTeams.swift:51,278`;
matched by `SeatReseat.swift:91-92`), but `TeamResolver.makeWorker` receives the
row and does not carry `row.id` into the `Worker`:

```swift
func makeWorker(_ model: Model, row: TeamWorkerSpec, ...) -> Worker {
    return Worker(
        id: Worker.makeID(modelId: model.id, instanceIndex: index),
        modelId: model.id, instanceIndex: index,
        skillId: row.skillId, ...)      // ← row.id is in scope and dropped
}
```

So `agentId` as the packet defines it ("which roster seat was supposed to run")
**does not exist in the run layer today**. It is not a rename — it is a genuine
information gain, and it is a ~2-line plumb because `row` is already in scope.

Precedent for the name already exists one function below: `disable(...)` records
`DisabledRow(rowId: row.id, ...)`.

### D1a — the SHARPEST collision is one wire key with two value shapes

In a single emitted `TeamRunJSON` document, the key `workerId` appears with two
incompatible shapes (`Resources/Fixtures/team_run.json`):

```json
"teamRun":       { "workerId": "model_sonnet"   }   ← line 21: BARE MODEL ID   (A3)
"workerAnswers": [{ "workerId": "model_sonnet#0" }]  ← line 44: SEAT COMPOSITE  (A2)
```

`RunInfo.workerId` is fed by `RunIdentity.primaryWorkerModelId(run)` — whose own
doc comment says "Primary **worker model id** — the model that ran."

A mechanical `workerId → agentId` sweep would put a **model id under the key
`agentId`** at `teamRun.agentId`, while every other `agentId` in the same
document is a seat id. `RunInfo.workerId` → **`modelId`**, decided separately,
never folded into the mechanical rename.

### D1b — GOOD NEWS: the answer layer is already correctly split

Contrary to the packet's assumption, answer rows already carry seat and model as
two distinct, always-populated fields:

```swift
// CatalogRunCoordinator.swift:320
TeamAnswer(memberId: worker.id, modelId: settledModel.id, ...)
// line 359 — roster converges to the model that actually ran:
run.workers[wi].modelId = answer.modelId
```

`settledModel` is the model that actually executed *after* any in-attempt
`SeatReseat` substitution. So at `AnswerInfo`/`WorkerInfo`/NDJSON level, S03 is a
**straight rename, not a new field** — materially more delegable than assumed.
`DesignBoardOption` and `FloorWorkerLane` already ship the correct
`workerId` + `modelId` sibling shape; use them as the reference.

### D2 — `agentId` MUST be model-independent

On substitution, both `Worker.id` and `Worker.modelId` are rewritten to the
substitute (`AsyncTeamService.applyModelPin` lines 859-864;
`RunService.runExecution` 1197-1203, 1298-1327):

```swift
worker.substitutedFromModelId = worker.modelId
worker.modelId = modelId
worker.id = Worker.makeID(modelId: modelId, instanceIndex: worker.instanceIndex)
```

Because `Worker.id` embeds `modelId`, the "seat" identity mutates whenever the
model changes. Therefore **renaming `Worker.id` to `agentId` would preserve the
current lie under a better name** — an `agentId` that silently changes when the
model is substituted is not a seat identity.

Packet Works Test #2 ("every run answer exposes `agentId` + `modelId` with
distinct meanings") is only satisfiable if `agentId` stops embedding the model.

### D3 — `modelId` needs no new name; it is already correct everywhere

`Worker.modelId`, `ResolvedRunSeat.modelId`, `TeamAnswer.modelId`,
`RunAttempt.requestedModelId`/`resolvedModelId`, `WorkerSpec.modelId`,
`TeamWorkerSpec.preferredModelId`/`fallbackModelIds`/`allowedModelIds`,
`TeamLeadSpec.preferredModelId` — all resolve against `Model.id`, zero exceptions
found. **These are not part of the problem and must not be touched.**

The public contract already emits `modelId` on answer rows (verified on a live
run: `workerAnswers[0] = { workerId: "model_gemini#0", modelId: "model_gemini" }`).
What is missing from the contract is the **seat**, not the model.

### D4 — two distinct Swift types both read as "a worker row"

- `TeamWorkerSpec` (`TeamCatalog.swift:118`) — roster seat. `id` = row slug. **A1.**
- `WorkerSpec` (`Worker.swift:87`) — legacy bench/panel row, `modelId`-only, 125
  call sites, feeds `PanelPreset`, `TeamAssembler`, `WorkflowPreset`. **A3.**

A rename that greps `WorkerSpec` hits both. These are **two independent tracks**.
`TeamWorkerSpec` → `TeamAgentSpec` is safe and unambiguous; `WorkerSpec` is a
separate, lower-priority question (and its `workerSpecs`/`workerId` keys are
persisted to `Config/WorkflowPresets/*.json`).

### D5 — names that are outright lies today

- `PanelPreset.workerIds` (`PanelPreset.swift:64-71`) — doc says "worker ids",
  body returns `spec.modelId`. Always model ids. → `modelIds`.
- `WorkflowStage.StageBinding.workerId` — always a model id; no production
  construction site found (tests only). → `modelId`, but verify no live reader
  before touching a persisted key.
- `WorkflowPreset.executionWorkerId` — **UNKNOWN**, no non-nil write site found.
  Do not rename until a live writer is identified or it is confirmed dead.

### D6 — Layer E stays; `--worker` is already dead in source

`WarmWorker*`, `ProcessOwnership*`, ownership `kind: "worker"`, run-storage worker
dirs: **do not touch.** Different concept.

`alln run --worker` no longer exists in source — `RetiredVocabulary.swift` deny-
lists `--worker`/`--dev-worker`/`--pm-worker`, and `RunCLI.swift` parses only
`opts.value("model")` and `opts.valuesList("seat")`. Live grammar is `--model`
(single pin) and `--seat` (repeatable pin-per-slot); both accept **model catalog
ids only** and both bottom out in the same resolver.

---

## Compiler-blind surface: live user data (NOT in the original packet)

The packet scoped compiler-blind risk to fixtures. It is much larger. Measured in
`~/Library/Application Support/Allnighter`:

```text
1281  files containing "worker"    (Runs 993, Threads 203, Relays 60, Panels 14,
                                    Recipes 7, ProjectReadiness 2, Pending 1)

 827  "workerId"                    ← values are "model_cursor_grok_45#0" style
 432  "producedByWorkerId"          ← NOT in the packet inventory
 260  "worker"
 236  "resolvedWorkerPromptSnapshot" ← NOT in the packet inventory
 230  "workers"
 230  "workerAnswers"
  76  "explicitWorkerIds"
  69  "devWorkerId"                 ← relay/pilot dev seat; holds MODEL ids
  66  "pmWorkerId"                  ← holds model ids or the sentinel "external"
   1  each: workerIds, workerChat, requiredWorkerIds, preferredWorkerIds,
          fallbackWorkerIds
```

Sampled values confirm the buckets:

```text
"devWorkerId" : "model_cursor_grok_45"     → A3 model pin → devModelId
"pmWorkerId"  : "external" | "model_sonnet" → A3 model pin → pmModelId
"producedByWorkerId" : "model_cursor_grok_45#0" → A2 run member
```

**Consequence:** "zero external users" is true, but the founder is a user with
1,281 files of live history. A hard key cutover with no migration silently
orphans every existing thread, run, and relay.

**Resolution (keeps Law 5 intact):** hard-cut the keys in code — no aliases, no
dual-decode — and ship a **one-time on-disk migration** in the same slice that
cuts the key. A migration is not an alias: it runs once, then the old spelling is
gone everywhere. Add as **WTA-S03a**, blocking S03 closeout.

### Compiler-blind surfaces beyond fixtures and live data

None of these fail a build; all of them silently drift:

| surface | why the compiler can't see it |
| --- | --- |
| `ContractSchema.swift` | JSON-Schema `$defs` hardcode wire keys as **string literals** in a `[String: Any]` DSL (`"workerId": nullable("string")`). Generates `team-run.schema.json` / `floor-run.schema.json`. |
| `ContractRegistry+Milestone1.swift` `EventSpec` | `requiredData: ["workerId","modelId","skillId"]` — separately hardcoded from the projector that emits them. |
| Error codes | `WORKER_FAILED`, `WORKER_NOT_READY`, `WORKER_NOT_AVAILABLE`, `WORKER_NOT_READY_IN_PROJECT`, `FILE_REFERENCE_WORKER_UNSUPPORTED` — **four separate literal sites per code**, plus `ruleId`s (`run.worker_not_available`, `worker.failed`). Not centralized in an enum. |
| `RunIdentity.swift` | Bakes `"worker \(workerId) · lane …"` into an emitted **string value**, not a key. No CodingKeys to catch it. Same for `outcomeHeadline()`. |
| `RunEvent.payload` (Mac GUI bus) | `[String: JSONValue]` dict keyed `"workerId"`. **Producers** (`RunService`, `TeamRunCoordinator`, `CatalogRunCoordinator`, `PlanWriter`, `LiveArtifactProjector`) and **consumers** (`AppModel.swift:876`, `ThreadsViewModel.swift:799,1475`) must move together — a matched pair. |
| `ArtifactProjector.swift` | HTML anchor ids `seat-<workerId>` embedded in generated `href`/`id`. Renaming breaks in-document links in every already-written artifact. |
| `FloorProjector.swift` | On-disk artifact paths `workers/<stem>.answer.md`. The `workers/` path segment is A4 storage layout — **keep**, decide separately. |
| iOS local caches | `ConversationHomeCache` / `ConversationThreadDetailCache` round-trip locally-written Codable structs. Compiler-verified within a build, but old cached files fail to decode after the rename ships. |
| Other fixtures | `error_envelope.json`, `doctor_result.json`, `pending_item*.json`, `thread_chat.json`, `team_preset_default.json`, `run_{complete,partial,inflight}.json`. |

### Teaching surface has a hash-locked lockstep requirement

`TeachingSnippet.swift:31` teaches `"Before an unfamiliar worker-starting action…"`
— and `alln bootstrap` writes that line into the **calling agent's own**
`CLAUDE.md`/`AGENTS.md`. The same line is hand-copied into **6 files** under
`Resources/Recipes/*.md` with a `hash=` marker.

Changing it requires, in one commit: the snippet, all 6 recipes, the `hash=`
markers, and a `TeachingSnippet.schemaVersion` bump (currently 3) —
`RecipeCatalogTests.testEveryRecipeEmbedsCurrentTeachingSnippet` enforces byte
equality.

Also stale from the last cutover: `FlagSpec.summary` for the already-renamed
`--model` flag still reads `"Requested worker/model id."`, `"Fallback worker id."`.

### RetiredVocabulary ordering trap

`HelpTopicRegistryTests.testNoRetiredVocabularyInPublicProse` sweeps all help
prose against `denyTerms`. Adding `workerId`/`workerAnswers`/`WORKER_FAILED` to
the deny-list **before** rewriting the prose turns the gate red immediately.
Add deny terms in the **same commit** that rewrites the prose (packet Law 8).

### Three overlapping "worker event" vocabularies — do not conflate

1. **NDJSON `--stream` wire** — `workerStarted`/`workerAnswered`/`workerFailed`/
   `workerActivity`, catalogued in `ContractRegistry`, emitted by
   `NDJSONStreamProjector`. Agent-facing.
2. **`FloorTimelineEvent.Kind`** — `workerStarted`/`workerReturned`/`workerFailed`,
   exposed via `alln floor show`, populated by `FloorProjector`.
3. **`RunEventKind`** — `"worker.status_changed"`, `"worker.answer_delta"`,
   Mac-GUI-internal pub/sub bus. Not the CLI wire contract.

### Contract version: this is a MAJOR bump

`ContractRegistry+Milestone1.swift:11` — currently `"5.2.0"`. Its own stated rule:
*"removing/renaming a command or flag = major."* Every wire-key rename here is a
rename. Gate: `alln dev export-contracts --check` fails with
`CONTRACT_DRIFT` or `CONTRACT_VERSION_NOT_BUMPED`.

### Three consumers already hand-parse the composite

The codebase already knows `workerId` contains a model id, and three places
independently re-derive it with ad-hoc string splitting:

```text
Apps/AllnighterMac/Sources/ThreadView.swift:255
    let modelId = wid.split(separator: "#").first.map(String.init) ?? wid
Apps/AllnighteriOS/.../ConversationAgentPresentation.swift:14, :58
    workerId.split(separator: "#").first.map(String.init) ?? workerId
Packages/.../RemoteIOSThreadMirrorExecutor.swift:193
    return modelId.contains("#") ? modelId : "\(modelId)#0"
```

These three deletions are the concrete, non-cosmetic payoff of S01. They are also
the proof that the overload costs real engineering, not just readability.

---

## Meaning map

| bucket | symbol | current meaning | destination | slice |
| --- | --- | --- | --- | --- |
| A1 | `TeamWorkerSpec` | roster seat row | `TeamAgentSpec` | S02 |
| A1 | `TeamPreset.workerSpecs` | roster array | `agentSpecs` | S02 |
| A1 | `TeamWorkerSpec.id` | stable row slug | `TeamAgentSpec.id` (feeds new `agentId`) | S02 |
| A1 | `TeamShowJSON.CrewSeat.id` | row slug on CLI JSON | `agentId` | S03 |
| A2 | `Worker.id` | `modelId#index`, mutates on substitution | see D2 — open question below | S03 |
| A2 | `Worker` (type) | one runtime seat occupant | `Agent` | S03/S04 |
| A2 | `TeamRunJSON.workerAnswers` | answer rows | `answers` | S03 |
| A2 | `AnswerInfo.workerId`, `producedByWorkerId` | run-member instance | `agentId` | S03 |
| A2 | `ResolvedRunSeat.workerId` | run-member instance | `agentId` | S03 |
| A3 | `RunRequest.workerId` | **model pin** (`--model`) | `pinnedModelId` | S01 |
| A3 | `RunInvocationNormalizedFlags.workerId` | **model pin** | `pinnedModelId` | S01 |
| A3 | `ResolvedRunInvocation.workerId` | **model pin** | `pinnedModelId` | S01 |
| A3 | `TeamRun.explicitWorkerIds` | `--model` selectors | `explicitModelIds` | S01 |
| A3 | `PendingTarget.{preferred,fallback,required}WorkerIds` | **model pins** | `*ModelIds` | S01 |
| A3 | `ThreadSendCoordinator.*.workerId`, `requestedWorkerId` | **model pin** | `pinnedModelId` | S01 |
| A3 | `WorkThread.defaultWorkerId` / `lastWorkerId` | **model pins** | `default/lastModelId` | S01 |
| A3 | `devWorkerId` / `pmWorkerId` (relay) | **model pins** | `devModelId` / `pmModelId` | S01 |
| A3 | `PanelPreset.workerIds` | **model ids under a lying name** | `modelIds` | S04 |
| A4 | `WarmWorker*`, `ProcessOwnership*`, `kind:"worker"` | process/session | **UNCHANGED** | never |
| A5 | `WORKER_*` codes, `workerAnswerDelta`, `worker_answers` | event/error names | `AGENT_*` / `agentAnswerDelta` | S06 |

`Worker.modelId`, `TeamWorkerSpec.preferredModelId`, `substitutedFromModelId`,
`skillId`, `skillName`, `instanceIndex`, `purpose` — **already correct, do not
touch.**

---

## AMBIGUOUS — SPLIT BEFORE RENAME

No single field was found that is looked up two different ways at its own call
sites. The danger is entirely **cross-field collision of the same token**:

1. `ResolvedRunInvocation.workerId` (model pin) vs `ResolvedRunSeat.workerId`
   (run member) — same struct tree, same function, opposite meaning. **This pair
   must be split in S01 before any A2 rename touches the run path.**
2. `CatalogRunCoordinator` JSON key `"workerId"` (run member, from `worker.id`)
   vs every upstream `workerId` field (model pin). Same wire spelling, opposite
   meaning, one pipeline.
3. `TeamWorkerSpec` vs `WorkerSpec` — two Swift types, one grep.

---

## Open design question (lead recommendation, decide at S03)

Given D2, `agentId` must not embed the model. Two options:

- **(a) Keep `Worker.id` as the occupant key, add a separate stable `agentId`
  from `row.id`.** Additive, no wire break in S01, smallest step. Answer rows
  then carry `agentId` (seat, stable), `modelId` (ran), and the existing
  composite as an instance handle.
- **(b) Re-base the composite on the row: `agentId = "\(rowId)#\(index)"`.**
  Cleaner end state — one identity, stable across substitution — but changes the
  key format of 827 live `workerId` values and every answer-matching path.

**Recommendation: (a) in S01 (purely additive, zero risk), then (b) folded into
the S03 contract major with the S03a on-disk migration** — by then the migration
script exists and the key rewrite is one more field for it to handle.

Do not let an executor decide this. It is the one genuine architecture call in
the packet.

---

## Delegation readiness

| slice | safe to delegate? | why |
| --- | --- | --- |
| S01 | **No** — lead/Sonnet | New semantics; the A3/A2 split above is the whole point. |
| S02 | **Yes** — compiler-verified | `TeamWorkerSpec` → `TeamAgentSpec` is unambiguous (D1/D4). Exclusion list: `WorkerSpec`, all Layer E files. |
| S03 | **Split** | Lead owns schema + D2 decision + migration test; executor propagates. |
| S04/S05 | **Yes** | Compiler-verified, after S03 lands. |
| S06 | Sonnet drafts, lead verifies | Judgment about what is agent-facing. |
